# Spec 2 W4 (Verification and age assurance) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Summary (one paragraph).** W4 is two batches, seven tasks, two migrations (each with its grants twin), one new edge function and one removed. **W4a** (Tasks 1–4) → `20261109100000_dating_v2_age_assurance.sql` (+ `20261109100010_dating_v2_age_assurance_grants.sql`): the verification record reshaped (methods and pass/fail only, no DOB), the sessions, the service writers, the far-below-18 path into Spec 1's `place_account_hold` with three arguments, `age_review` / `age_verification_invalid` closing every match, the human-review bucket and its INSERT policy, the person's own status read, the sweep, the flag `dating_age_assurance` and the dev-script extension (Task 1); the `dating-verification` edge function with the §3.3.5 seam (fake, AWS Face Liveness and CompareFaces, Smile ID, an unconfigured estimation seam) and `verify-dating-profile` removed (Task 2); the client's verification data layer, the capture seam with spoken prompts and haptics, and the home's `verifying` state and `verification` pause in the section (Task 3); D11's whole flow (intro and consent, the video check and every outcome, the ID route, the human route), the manual passage, and the W4a gate (Task 4). **W4b** (Tasks 5–7) → `20261109110000_dating_v2_trusted_devices.sql` (+ `20261109110010_dating_v2_trusted_devices_grants.sql`): trusted devices, the real `dating_require_trusted_device()`, `trust_dating_device`, `dating_eligibility` gate 8, the reverify session kind, exit unbinding every phone, one race case (Task 5); the install id under `attune.install_id`, the Dating-scoped client that alone sends `x-attune-device`, and the edge function's re-check (Task 6); `/dating/verify` with the re-check and the setup-restart variant, and every `reverify_device` answer leading there, and the W4b gate (Task 7).

**Replayed.** Every task below was replayed in order in a scratch copy of the repo (on a clone of `attune_spec3a`): every "Create … with exactly" block, every edit script, ARB fragment, `gen-l10n`, `dart format` and test command, and every mutant set. The Expected lines are what that replay printed (Replay record, end of plan).

**Goal:** Build Spec 2's verification and age assurance (§3.3, D11) on the W1–W3 server and app: a live person whose face matches every approved photo, aged 18+ by facial age estimation at the challenge age 25 or by an ID whose date of birth equals the declared one, with a human route for identity only, Spec 1's account hold for a far-below-18 estimate, and new-device re-verification behind trusted devices; nothing biometric stored, the vendors behind a seam, `fake` refused in production mode, and Dating still off in production.

**Architecture:** Server first in each batch, then the edge function, then the app. Every re-created SQL function is taken from its LIVE body (`pg_get_functiondef` on `attune_spec3a` after the earlier batches) with only the lines marked `-- Spec 2 W4a` / `-- Spec 2 W4b` changed; a check script diffs them (`marked_diff.py`). New functions are `SECURITY DEFINER SET search_path = ''`, pre-validate input and answer `{ok:false, reason}` with a fixed code instead of raising. The edge function holds no state: every result goes through a service function, no database call is open across a vendor or storage call, and nothing biometric is logged, stored or returned. The app keeps verification state in account-keyed `autoDispose` providers and route-scoped widgets (D8), nothing on disk but the install id (C-5); every Dating screen sits behind the lock gate (`datingRoute()`), and only the Dating-scoped client sends the device header (S-7).

**Tech Stack:** Supabase Postgres 17 (RLS, `SECURITY DEFINER`, pg_cron, `extensions.digest`), psql, Python 3 (edit, build-check and mutation scripts), Deno 2.8.1 (edge function and its tests, frozen lock `.github/deno-w9.lock`), Flutter 3.29.1 / Dart 3.7 / Riverpod 2.6 / go_router 10, `supabase_flutter` 2.14 (`supabase` 2.12: `SupabaseClient(httpClient:, accessToken:)`), `http`, `flutter_secure_storage`, `image_picker`, `image` (all already dependencies). No new package.

**Spec:** `docs/superpowers/specs/2026-10-24-dating-mode-design.md` — §8 W4 (W4a, W4b, the gate line); §3.3 (3.3.1–3.3.5); §3.0, §3.1 (`verifying`, `reverify_device`), §3.14 (`/dating/verify`), §3.15 row D11; §2.1 gate 8; §4.1, §4.3 (`dating_age_verifications`, `dating_trusted_devices`, `dating_verification_sessions`, `dating_account_restrictions`), §4.4 (the device check, `trust_dating_device`, `record_dating_age_assurance`, `record_dating_identity_check`, `revoke_dating_age_verification`), §4.5 (the review bucket), §4.7 (`dating-verification`, `verify-dating-profile`), §4.8 (sessions 30 days, review photos 72 h, the age result kept), §4.9 W4a/W4b, §4.10 (every row tagged W4), §6.2–§6.3 (`age_review`), §6.8 (biometric, transfers); §7.1 (`dating_v2_verification_contracts.sql`, `storage_bucket_policies.sql`), §7.2 S1/S2/S5/S7/S16/S19, §7.3 (`dating-verification`), §7.4 (the header architecture test), §7.5 mutants 8 and 9, §7.6, §7.7 (W4's device checks); §9 R8, R15. `docs/superpowers/specs/2026-10-24-app-flow-identity-design.md` — `place_account_hold(p_user, p_kind, p_ref DEFAULT NULL)` (I-7), the W6a access-token hook and dormancy (§3.5, H1), the W6b date-of-birth correction (`correct_my_birth_date`, Settings → Date of birth), `account_birthdates`. `docs/superpowers/specs/2026-10-24-cross-spec-review.md` — I-7, S-7, C-6, R-6, W-3. Carries: `.superpowers/sdd/2026-11-09-spec2-w4/carries.md` (all 11, mapped below). Format reference: `docs/superpowers/plans/2026-11-07-spec2-w3-setup-ui.md`.

## Global Constraints

- **Where and how.** Work in the main working tree on `main` (`/Users/user/attune`). HEAD is `7ddbe9c2` (S2 W1–W3 committed). The owner may have uncommitted edits (`supabase/.temp/cli-latest`, `backup-before-planning-p2.sql`): never revert, stash, stage, checkout or reformat them. Every edit to an existing file is an exact replacement made by a script that asserts each anchor occurs once (`anchor.py`); if an anchor moved because a later fix changed it, apply the same change to the current text and say so in the task report.
- **NO commits.** No `git add`, `git commit`, `git stash`, `git checkout`, `git reset`, `git rm` (delete files with `rm`). Where a skill says "commit", instead: **do not commit; record the tree in the report** with `T=$(mktemp -u); GIT_INDEX_FILE=$T git read-tree HEAD && GIT_INDEX_FILE=$T git add -A && GIT_INDEX_FILE=$T git write-tree; rm -f $T` (a private index; the real index is untouched). The controller commits only when the owner approves.
- **Formatting.** Never `dart format` a pre-existing file (the repo uses an older formatter; formatting reflows it). `dart format` only the files a task creates. A later task that edits a file an earlier W4 task created writes its edit in `dart format` style by hand (every edit script below is already in that style) and does not run the formatter on it. A pre-existing file that a task replaces whole (`verify_step.dart`, `dating_supabase_client.dart`) is written in formatter style and is not formatted.
- **SQL target.** Contracts run only on `attune_spec3a`, from the repo root. A file with a top-level `BEGIN;` runs as `psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f F`; one without runs wrapped: `psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -c 'BEGIN' -f F -c 'ROLLBACK'` (`suite.sh` does both). Migrations and their twins are applied with `psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f <file>`. Confirm the target first (`psql -X -d attune_spec3a -Atc 'select current_database()'` prints `attune_spec3a`). **NEVER `attune_test`. NEVER run `scripts/local_pg_setup.sh` or `scripts/local_pg_grants.sql`** — but DO append each new twin's `\i` line to `scripts/local_pg_grants.sql` (`grants_line.py`). Mutants run inside one transaction that the contract's own `ROLLBACK` ends (`mutate.py`, with the grants twin applied after each migration mutant). Never name a `pg_temp` helper `begin` (in the replay it made a `\i`'d script's writes vanish; the helper is `pg_temp.start`). A DO block's side-effecting calls are their own statements: an `IF a OR b` has no evaluation order.
- **Migrations.** `20261109100000_dating_v2_age_assurance.sql` (+ `…100010_…_grants.sql`) and `20261109110000_dating_v2_trusted_devices.sql` (+ `…110010_…_grants.sql`), later than every file in `supabase/migrations/` (the newest is `20261107170010_dating_v2_photos_grants.sql`). If `ls supabase/migrations | sort | tail -1` shows anything at or after `20261109100000` when Task 1 starts, shift all four to the next free hours keeping their order and change every header, `\i` line and command. Each file is one `BEGIN; … COMMIT;`, idempotent (applied twice, `exit=0` both times), with `SET LOCAL lock_timeout = '5s'`. Every new function: `SECURITY DEFINER SET search_path = ''`, fully-qualified names, `REVOKE ALL … FROM PUBLIC, anon` and `service_role` unless the spec gives it the service role, `GRANT EXECUTE … TO authenticated` only for the two client functions (`get_my_dating_verification()`, `dating_review_upload_open(text)`); server-only objects are revoked in the migration too and every grant is re-asserted in the twin. Re-created functions start from their LIVE body and change only lines marked `-- Spec 2 W4a|W4b` (`marked_diff.py` checks). Pre-validate input so no raw constraint error echoes input; NULL never counts as eligible or trusted (`IS NOT TRUE`, `IS DISTINCT FROM`, `coalesce(…, false)`); the device check never answers NULL (its callers use `IF NOT x`). Shared lock order for every writer: the per-person setup lock (`private.dating_lock_setup`) first, then rows, with a bounded 40P01/55P03/40001 retry (3) then `busy` / `dating:busy`. Exposure-reducing writes are never gated by the device (carry 11); deletion is never blocked. No `CREATE INDEX CONCURRENTLY`; no function names a table a later batch creates.
- **Production stays off.** No Dating flag turns on in production; no migration turns a flag on or sets `attune_environment`. `supabase/sql/dev_enable_spec2_dating_flags.sql` turns every Dating flag that exists ON in development, now including `dating_age_assurance`, and sets `age_assurance_mode` (only when none is set: `fake` locally, `sandbox` on the development project). `fake` is refused unless `private.attune_environment()` reads `development` (the database and the edge function each refuse it).
- **Vendors and data.** No vendor call in any test (Deno tests inject `fetch`; no `--allow-net`). Never read `.env*`, credentials or the keychain. The reference frame, the photos' bytes, the estimate and the ID's date of birth live only inside the call that needs them (zeroed after use) and never reach a log, the database or an answer; no S3 output and no audit images on liveness sessions; Smile ID is asked for no images; `us-east-1` is refused (§3.3.5). This matches the DPIA's biometric section (owner gate).
- **Copy.** New strings go into `lib/i10n/app_en.arb` under `dating_` only through `python3 -I .superpowers/sdd/2026-10-26-spec1-w3/arb_append.py <fragment>`, then `flutter gen-l10n --arb-dir=lib/i10n --template-arb-file=app_en.arb --output-dir=lib/i10n/generated --output-localization-file=app_localizations.dart --no-synthetic-package`. Straight apostrophes only. Copy names people, never "they" for the partner or another person. Every displayed date goes through `MyDateFormat` (W4 shows none). Exact spec strings are copied verbatim; strings this plan adds are marked "plan copy" in their ARB description and listed for the reviewers (Owner checklist). The app never shows a server's or a vendor's text: every answer is a fixed code mapped to ARB copy.
- **UI.** Every Dating screen and sheet is under `AllowLargeText` (through `FlowFrame` / `DatingStepFrame`, the shared step frame: offline banner, "Connect to save this answer.", step counter). Error red is `#C62828` in light (`FlowErrorLine`) and the theme's own `colorScheme.error` in dark; errors are icon-plus-text live regions; busy, vendor and device answers are calm lines. Goldens at 1.0, 1.3, 2.0 and RTL (`expectFlowGoldens`), the three guidelines (`expectFlowGuidelines`), a dark-theme test, the large-text audit at 2.0 (`0 site(s) to fix`). Taps in tests use `tapInReach` (the W10 helper). Motion: D11's outcomes never animate except the one "You're verified." check, a 400 ms fade, none under reduce motion; spoken prompts go through the screen reader (`SemanticsService.announce` only when `accessibleNavigation`), haptic ticks only without reduce motion. No text field in W4 (so no keyboard-learning concern).
- **D8 shared phones, D20 / C-5.** Every Dating read is keyed to the signed-in account and every screen clears its state on an account change; tests hold the next account's read open and assert no frame shows the last account's state. Nothing Dating is written to prefs, files or secure storage except the install id `attune.install_id` (created at first launch for everyone, §7.2 S19's allow-list); the human route's camera files are deleted as soon as read. Quick exit disposes the route (every Dating route is a top-level `GoRoute`).
- **Every answer settles.** One idempotency key per action (`DatingActionKeys`), settled once the answer is final (`keys.settle`); a busy or failed answer keeps it.
- **Off limits.** In-chat Games (`test/architecture/games_untouched_test.dart` stays green), Opinions, `ATTUNE_SOUL.md`, `ATTUNE_THESIS.md`, `lib/home/home_screen.dart` and its latch (byte-identical; `shasum -c .superpowers/sdd/2026-11-07-spec2-w3/latch.sha`), `quick_exit_service.dart`, `auth_provider.dart`, `lib/main.dart`, `set_user_path_internal`, `get_public_app_config()`, every applied migration, every Spec 1 file but the one microtask line in `lib/app/app.dart` (Task 6, R-23), every edge function but `dating-verification` (new) and `verify-dating-profile` (removed). **No deploys** (`supabase db push`, function deploys and deletes, secrets and app builds are the owner's; Owner checklist).
- **Gates, every batch (Tasks 4 and 7).** (1) The wrapped SQL suite on `attune_spec3a`: no new FAIL (baseline **159 PASS / 14 FAIL**; after W4a **160 / 14** — `dating_v2_verification_contracts.sql` is new — and still **160 / 14** after W4b, whose sections extend that file). (2) Full `flutter test`: no failure beyond the known flakes outside Dating (`chat_controller_test:259`, `chat_screen_list_anchor` D<0, `reflection_journal` at midnight, `planning_recent`, and — seen once in this plan's replay — `story_outbox_notices_test` "Discard asks first…"; re-run a failing file alone before calling it a flake); baseline **+7975**; the count moves by the tests each task adds (listed per task). (3) `flutter analyze --no-pub lib test`: **571 issues, 0 new** (compared line-insensitively against Task 1's saved list). (4) `shasum -c .superpowers/sdd/2026-11-04-spec1-w10-accessibility-docs/w10-1.0.sha` and `shasum -c .superpowers/sdd/2026-11-04-spec1-w9/flag_off.sha`: every line `OK`. (5) `scripts/concurrency/dating_kill_switch_races.sh` on an IDLE scratch DB built from `pg_dump -s attune_spec3a` plus the config tables' data (`public.metric_key_prefixes`, `public.feature_flags`, `public.country_safety_config`, `private.dating_calling_codes`; the script sets `dating_push_key` itself), dropped after: every case `PASS` (28 after W4a, 29 after W4b). (6) The Deno CI line (`.github/workflows/tests.yml` job `deno-w9`, frozen lock) passes in full. (7) `test/architecture/games_untouched_test.dart` passes and the latch is `OK`. (8) Each task's named mutants all RED (a `CONTRACT VIOLATED` line, a named constraint, `KILLED`), the RED line quoted in the report; a `COMPILE` or an `anchor missing` is a broken mutant to fix, never a kill.

## Review Focus

Five things a real person will do that this wave must survive. Each is pinned to tests that fail if it regresses.

1. **The vendor goes down mid-session.** The person taps Start, the capture runs, and the liveness, CompareFaces or Smile ID call times out or answers 5xx. Expect: nothing counted (no attempt used, no result written, the session still open), the calm line "That didn't go through. Try again." in the theme's own colours (never error red, never a server's or vendor's text), the same session resumed on the retry, and no database lock held while the vendor call was in flight. Tests: Task 2 Deno `a vendor that can't answer counts nothing (§3.15 D11)` and `only fixed codes leave: a server's text is never passed on` (mutants `vendor_down_counts`, `raw_reason_passed_on`); Task 4 `the vendor can't answer: "That didn't go through. Try again." and nothing moves; a server's text never shows` (mutant `vendor_red`); Task 1 contract H (every refusal by name, never a raise; a closed session answers `session_unavailable`).
2. **The app is killed mid-check and opened again later.** Expect: D11 opens on "Let's pick up where you left off." with the same session (same step, attempts kept, never a fresh 5-a-day slot), a session older than 30 minutes swept to `expired` so a new one starts, a waiting human or ID check shown as waiting (never the intro), and a pending ID check read again on Check again. Tests: Task 4 `a session left open: "Let's pick up where you left off."`, `a person checking; an ID being checked; a date of birth that differs; an age not confirmed`, `a pending ID check is read again on Check again` (mutant `waiting_shows_intro`); Task 1 contract H (`resumed: true` for the same step; a refused start never ends the open session, mutant `begin_limit_after_ending`) and M (the sweep, mutant `sweep_keeps_old_photos`); Task 2 Deno `a pending ID check stays waiting and is read again`.
3. **A far-below-18 estimate on a shared phone** (an older sibling's phone, a child at the camera). Expect: the age fails, Spec 1's `place_account_hold(p_user, 'age_review', <session id>)` is called exactly once with three arguments (its only Dating caller), every match closes as `age_review`, the screen shows support copy only (no retry, no "another way", nothing naming the reason), and the next account signed in on that phone sees none of it. Tests: Task 1 contract G (`hold_two_args`, `far_below_no_replay_guard`, `age_review_closes_as_restricted`) and F; Task 2 Deno `the fakes' scenarios walk every video outcome` and `mutant 8 (§7.5)…` (`far_below_ignored`); Task 4 `far below 18: support copy only (Spec 1's hold)` and `D8: another account sees nothing of the last one while its read is held` (mutant `d8_no_reset`).
4. **A new phone during an active match** (lost phone, restored backup, a partner picking up the person's phone). Expect: every Dating read and write from the new phone answers `reverify_device` (never a NULL that slips through), except pause, leave, clear and photo delete, which always work; the home and every refusal lead to `/dating/verify`; a verified person does a video check only (liveness and every photo, no age, no ID); a stranger's failed re-check never unverifies the owner and never trusts the phone; the owner's other phones keep working; at most three phones stay trusted. Tests: Task 5 contract Q, R, S, T (mutants `m9_profile_read_unguarded`, `guard_null_when_untrusted`, `lists_no_device`, `reverify_fail_unverifies_owner`, `cap_not_enforced`), race `two devices trusted at once: at most three stay`; Task 6 Deno `W4b: a re-check that doesn't match never unverifies the owner; another phone's session is refused` (mutant `reverify_writes_owner_result`); Task 7 `no consent box; the re-check actions; verified, back to Me`, `the other way is a person, never an ID`, the `carry 9` group.
5. **The ID's date of birth differs from the one given at sign-up.** Expect: the session waits for review with "The date of birth on your ID doesn't match the one you gave us. A person will check this within 24 hours.", nothing passes, the app never sends or shows a date of birth, the person can correct the declared date through Spec 1's path (Settings → Date of birth) and tap Check again, which compares again without a new capture; an ID that shows under 18 takes the far-below path; an ID whose face doesn't match the person never confirms the age. Tests: Task 2 Deno `the ID route: pass, fail, date-of-birth mismatch, minor, pending` (mutant `id_minor_human_review`) and `an ID whose face doesn't match the person never confirms the age (§3.3.1)` (mutant `id_face_ignored`); Task 1 contract L (`check_dating_id_birth_date`: match, mismatch, minor, unknown; mutant `dob_minor_as_mismatch`); Task 4 `pick a document, the capture, then the outcome` (R-12's Check again on the same session, mutant `idcheck_forgets_session`).

## Pre-flight (read before Task 1)

### Shared files and interfaces between tasks

| File or interface | Tasks | Rule |
|---|---|---|
| `.superpowers/sdd/2026-11-09-spec2-w4/` (`$D`) | 1 creates (tools, baselines, `before_w4a/`); every task adds its scripts and outputs | `suite.sh`, `grants_line.py`, `dmut.py`, `anchor.py` are W3's, copied unchanged; `mutate.py`, `denomut.py`, `marked_diff.py` are new |
| `supabase/tests/dating_v2_verification_contracts.sql` | 1 creates (A–P); 5 inserts Q–T above the final `NOTICE`/`ROLLBACK` | helpers `pg_temp.start` (never `begin`), `call_on`, `err_on`, `guard_on`, `elig_on`, `dev`, `dev_hash` |
| `begin_dating_verification(uuid,text,text,text,text,text)`, `decide_dating_human_review(uuid,text,uuid)`, `get_dating_home()`, `private.dating_exit_internal(uuid,boolean)` | 1 creates or re-creates; 5 re-creates from the post-W4a live body | Task 5's builder reads `$D/before_w4b/` saved after Task 1's migration is applied |
| `get_my_dating_verification()` payload | 1 produces; 3 reads; 5's `device` field is already in it (`trusted` until W4b binds) | keys pinned by contract J and `dating_verification_data_test.dart` |
| `dating-verification` actions (`start`, `complete`, `start_id`, `complete_id`, `human_start`, `submit_human`; W4b `reverify_start`, `reverify_complete`, `human_start {reverify:true}`) | 2 creates; 6 adds the re-check; 3/4/7 call through `DatingVerificationGateway.act` | the answers are fixed codes only (`DatingVerifyOutcome`, `DatingVerifyRefusal`) |
| `supabase/functions/dating-verification/{handler.ts, handler.test.ts}` | 2 creates; 6 edits (`edit_edge_T6.py`) | Task 6 appends four tests; the fake's switch gains `trust_dating_device` |
| `lib/features/dating/verify/verify_flow.dart` | 4 creates; 7 edits (`edit_T7.py`, formatter-style edits, no `dart format`) | the `reverify` flag |
| `lib/features/dating/data/dating_home.dart` (W3) | 3 (`verifying`, `DatingPauseReason.verification`), 7 (`DatingReverifyVariant`) | edits only |
| `lib/features/dating/section/dating_section.dart` (W3) | 3 (verifying card, verification pause), 7 (reverify card, carry 9 link) | edits only |
| `test/features/dating/support/dating_shell.dart` (W3) | 4 (a verification override, default verified) | edit only; every W3 shell test still passes |
| `lib/i10n/app_en.arb` + generated | 3, 4, 7 | `arb_fragment_T{3,4,7}.txt` via `arb_append.py`, then gen-l10n |
| `supabase/tests/dating_rls_canary.sql` | 1 (W4a rows), 5 (W4b row) | `edit_canary_T1.py`, `edit_tests_T5.py` |
| `supabase/tests/service_role_grants_test.sql` | 1 (`dating_verification_sessions`), 5 (`dating_trusted_devices`) | exemption list only |
| `supabase/tests/{dating_v2_home,dating_v2_identity,dating_v2_setup,identity_foundation,dating_mode,account_deletion}_contracts.sql` | 1 (v1 age fixtures → v2 shape; the setup photo-readers pin), 5 (identity's W1c pass-through check becomes the real check; home's reverify pin) | `edit_tests_T1.py`, `edit_tests_T5.py`; never a loosened check |
| `supabase/tests/storage_bucket_policies.sql` | 1 | the second bucket's policy and predicate hashes |
| `scripts/local_pg_grants.sql` | 1, 5 | one `\i` block each (`grants_line.py`) |
| `scripts/concurrency/dating_kill_switch_races.sh` | 5 | one case (`two devices trusted at once`) and the delay trigger on `dating_trusted_devices` |
| `supabase/sql/dev_enable_spec2_dating_flags.sql` | 1 | `dating_age_assurance` and the mode |
| `.github/workflows/tests.yml`, `supabase/config.toml` | 2 | the two Deno test files on the CI line; `[functions.dating-verification] verify_jwt = true` |
| `lib/app/app.dart` (Spec 1) | 6 only | one microtask line (R-23) |
| `test/architecture/text_scale_routes_test.dart` | 7 | `datingVerify` in `_audited` |

### Carries → tasks

| # | Carry (`carries.md`) | Where |
|---|---|---|
| 1 | the age-change trigger pauses with a NULL reason; mirror in resume and the client | Task 1 (`enforce_dating_age_verification_change` re-created: `pause_reason = 'verification'`, the CHECK widened; `resume_dating_mode` refuses it: contract E, mutants `invalidate_no_age_reasons`, `resume_ignores_verification`); Task 3 (`DatingPauseReason.verification` → `resumeOffered` false, the section's "Verify it's you": test `carry 1: a verification pause offers the check, never Resume`, mutants `verification_pause_resumes`, `verification_pause_plain_line`) |
| 2 | every re-creation keeps the path-pause / failed-sweep handler | Ruling R-31 (every re-created body is its live body plus marked lines; `marked_diff.py` in Tasks 1 and 5 fails on any unmarked change, so no handler can be lost) |
| 3 | D11's shell becomes the real flow; D13's Done copy; "We keep only whether it passed" matches retention | Task 4 (`verify_step.dart` replaced by `DatingVerifyFlow`; `d11_d13_test` rewritten), Ruling R-33 (D13's line stays true: activation refuses until the check passes, and it now links to D11), Ruling R-22 and Owner checklist 1 (the DPIA and the vendors' deletion terms back the sentence) |
| 4 | the manual's verification passages | Task 4 (`edit_T4.py` rewrites `dating_setup_verify` to what W4 builds: the video check, the ID route, the person route, what is kept) |
| 5 | far-below → `place_account_hold` (3 args); `underage_risk` / `age_verification_invalid` close matches; Spec 1 W6a ordering and W6b DOB correction | Task 1 (contract G: one hold, three arguments, the session id as `p_ref`, once per session; F: an `age_review` restriction closes every match as `age_review`; E: a revocation closes as `age_verification_invalid`); Ruling R-12 (the DOB correction is Spec 1's `correct_my_birth_date` path, then Check again); Ruling R-34 (the W6a hook is untouched: an age_review hold is Spec 1's own kind, so its ordering with dormancy is Spec 1's) |
| 6 | `dating_require_trusted_device()` becomes real; W3's lists guard and its contracts still pass; `lists_no_device` dies against the real function | Task 5 (the real function; contract Q; W3's setup contracts in the suite; mutant `lists_no_device` re-creates `get_dating_setup_lists` without its guard and dies at Q) |
| 7 | `dating_has_data` counts `dating_session_context` if W4b writes rows people hold | Ruling R-19 (W4b writes no such row: trusted devices and sessions are deleted on exit and never shown as data; `dating_has_data` unchanged) |
| 8 | D6 country note's location variant with `dating-device-check` | Ruling R-18 (stays with W8b; W4b builds no network-country read) |
| 9 | every writer's `reverify_device` answer routes to re-verification | Task 7 (`datingRefusalLine` in the step frame, `datingLifecycleErrorRows`, the section's error rows, the gentle wait's two places, the home card: the `carry 9` tests, mutants `writer_refusal_no_link`, `lifecycle_refusal_no_link`, `gentle_wait_no_link`) |
| 10 | `isDatingModeAvailable` through the Dating-scoped client | Already done in W3 Task 12 (`documentation_flags.dart` reads `datingSupabaseClientProvider`, pinned by `documentation_registry_flags_test.dart`); Task 6's architecture test `only the Dating client names x-attune-device` keeps every Dating read on that client |
| 11 | exposure-reducing writes never refused by the device guard | Task 5 (contract Q: pause, leave, clear the reflection and delete a photo all succeed from an untrusted phone; the guard is never added to them) |

### Rulings (the spec wins over this plan; each records its cost if wrong)

- **Ruling R-1:** `dating_age_verifications` is reshaped in place (§4.3 W4a). Its v1 rows (W1's `verify_dating_age`, a typed date of birth) are deleted by a guarded `DELETE` (only rows without a v2 method), and the table gains the v2 columns and CHECKs. Dating has never been on in production, so no real person loses a result. Cost if wrong: a development tester verifies again.
- **Ruling R-2:** the record keeps no date of birth, no estimate, no image and no template (§1.4, §4.3); the existing contracts' fixtures move to the v2 shape by exact edits (`edit_tests_T1.py`), never by loosening a check.
- **Ruling R-3:** two decision times, `age_decided_at` and `identity_decided_at`, instead of one `verified_at`, so a later identity check (a new photo, W5) never resets how long the age result is kept (§4.8). Cost: one column.
- **Ruling R-4:** a session keeps only its last outcome and the photo slot it named (`outcome_position`, for "Change that photo"), the attempts, the gestures (human route) and the document code (ID route); never a score, a frame or a date.
- **Ruling R-5:** an open session of the same step resumes ("Let's pick up where you left off."); at most 5 new sessions a day per person (`rate_limited`), and the limit is read **before** another step's open session is ended, so a refused start never loses the open one. Cost if wrong: the limit is one constant.
- **Ruling R-6:** the sweep is its own cron, `dating-verification-sweep` every 15 minutes: open sessions expire after 30 minutes, review photos go at 72 hours (or at the decision), sessions at 30 days (§4.8). Cost: one more cron.
- **Ruling R-7:** the dev script sets `age_assurance_mode` only when none is set: `fake` where `app_setting('supabase_url')` is NULL (local), `sandbox` on the development project. No migration sets a mode; with none set the mode reads `off`.
- **Ruling R-8:** an ID that shows under 18 takes the far-below path (the age fails, Spec 1's `age_review` hold, every match closed), like a far-below estimate. Cost if wrong: an adult whose ID was misread waits for Spec 1's review.
- **Ruling R-9:** no UK-recognised estimation vendor is chosen, so in sandbox and live the estimation seam is "unconfigured": it never passes and never fails. The video check then confirms identity (liveness and every photo) and the age goes to the ID route. In `fake` mode the fake estimates. Cost if wrong: until a vendor is signed, everyone in production needs an ID (owner gate 1). **Owner-approved 2026-11-09.**
- **Ruling R-10:** no native vendor capture view (AWS's Face Liveness detector, Smile ID's document capture) and no text-to-speech package in W4: the capture seam (`DatingCaptureLauncher`) has a practice capture for `fake` only, and for any other vendor the app answers "unavailable" calmly. A later SDK batch adds the native views behind the same seam. Cost: real-device liveness checks (§7.7) wait for that batch. **Owner-approved 2026-11-09:** W4 builds the seam and the fake vendor; real capture comes in a later vendor batch.
- **Ruling R-11:** the capture's prompts are shown, and announced only through the screen reader (`SemanticsService.announce` when `accessibleNavigation` is on), one every 1.2 s; a haptic tick per prompt unless reduce motion. Cost if wrong: speech for people without a screen reader needs the TTS package (with R-10's batch).
- **Ruling R-12:** a date-of-birth mismatch puts the session in review ("A person will check this within 24 hours."); the person may correct the declared date through Spec 1's path (Settings → Date of birth, `correct_my_birth_date`), and "Check again" compares the vendor's answer with the corrected date on the same session. The app never sends or shows a date of birth.
- **Ruling R-13 (owner ruling 2026-11-09):** a failed or uncertain age estimate never ends the check; it sends the person to the ID check. An estimate below 25 answers `needs_id` (§3.3.2's "Estimate below 25" copy); no estimate, a non-number, or one the vendor flags as unsure answers `age_uncertain` ("The video couldn't confirm your age this time. Let's check with your ID instead."); neither records anything, and `record_dating_age_assurance` refuses a `fae` fail (`invalid`), so no estimate can ever be final. Only two things end the check: a failed ID check (the document fails, or its face doesn't match the person; "Age not confirmed" support copy, nothing to try again, every later start answers `age_not_confirmed`) and Spec 1's under-18 hold (a clear far-below-18 estimate or an ID showing under 18: the `age_review` hold, every match closed, R-8). Appeals go through support (W7). Tests: contract C2, Deno `R-13: …` (two) and the decision table's uncertain rows, Task 4 `R-13: …` (three).
- **Ruling R-14:** a re-check (W4b) never writes the account's own identity result. A pass trusts the phone it ran on; a fail only fails that session. A stranger's failed check on a new phone can never unverify the owner.
- **Ruling R-15:** a device is the sha256 hex of the 32-hex install id sent as `x-attune-device`; at most 3 trusted per person (the least recently used is dropped), untrusted after 180 days unused, last use written at most once a day (and at most 200 ms of waiting for that write).
- **Ruling R-16:** an account with no trusted device yet is "unbound": its requests pass until the first setup write binds that phone (the setup guard), and the phone that passes D11 is trusted. Cost: an old app build (no header) on a bound account reads `reverify_device` until updated, so the W4b app ships with or before the W4b push (owner checklist 6).
- **Ruling R-17:** gate 8 (a trusted device) applies only to the caller's own requests (`dating_eligibility` reads the request's header only when the caller is the person); a candidate's phone never removes them from someone else's pool.
- **Ruling R-18:** the D6 country note's location variant stays with W8b's `dating-device-check` (carry 8).
- **Ruling R-19:** `dating_has_data` is unchanged (carry 7): W4b writes no row a person holds as Dating data.
- **Ruling R-20:** pause, leave, clearing the reflection and deleting a photo are never gated by the device (carry 11); deletion is never blocked.
- **Ruling R-21:** `verify-dating-profile` (v1) is removed from the repo; deleting the hosted function is the owner's (checklist 6).
- **Ruling R-22:** D11's consent line "… Nothing is kept after the check." (and the manual's "we keep only whether it passed") is true only with the vendors' deletion terms (AWS: no S3 output, no audit images; Smile ID: no images returned or kept beyond its contract). Owner gate 1 (the DPIA's biometric section) must confirm it before the flag is on anywhere real.
- **Ruling R-23:** the install id is created at first launch for everyone (one microtask line in `lib/app/app.dart`), under the neutral key `attune.install_id` in the safety keystore (§7.2 S19's allow-list), never named Dating. No other Spec 1 file is touched.
- **Ruling R-24:** only the Dating-scoped client sends `x-attune-device` (a wrapping `http` client on its own `SupabaseClient`, with the app's session token and no refresh of its own); an architecture test fails if any other file names the header or reads the id.
- **Ruling R-25:** the human route's photos are taken with the camera only (`image_picker`, no gallery), read, deleted from disk, and uploaded as `<session id>/1.jpg` and `<session id>/2.jpg` to `dating-verification-review` (2 MB, JPEG), whose only policy is an INSERT on a definer predicate (`dating_review_upload_open`: the caller's own open human-route session); only the service role reads them; they go at the decision or at 72 hours.
- **Ruling R-26:** a person's decision is `decide_dating_human_review(session, outcome, reviewer)` (service role); until W7's console, development decides with `supabase/sql/dev_dating_review_decide.sql`.
- **Ruling R-27:** the fake vendor answers the scenario picked on the practice capture (pass, liveness fail, photo mismatch, far below, under 25, vendor down, ID outcomes); the database and the edge function each refuse `fake` unless the environment reads `development`.
- **Ruling R-28:** `get_dating_operational_health()` adds `age_assurance_mode`, `verification_awaiting_review` and `verification_oldest_waiting_hours`, so the 24-hour promise can be watched.
- **Ruling R-29:** a revoked or failed age check pauses with `verification` (carry 1); resume refuses it until a new check passes; the section offers "Verify it's you" while the server's `can_resume` is false, and Resume only once `can_resume` says the check holds (Task 3 D1, after T1 fix round 1 M-2).
- **Ruling R-30:** `age_review` and `age_verification_invalid` close every match with their own `closed_reason` (carry 5); `evidence_until` is set as for W1's other safety closes.
- **Ruling R-31:** carry 2 is enforced by construction: every re-created function is its live body plus marked lines (`marked_diff.py`).
- **Ruling R-32 (owner ruling 2026-11-09):** setup_restart's "Start again" leaves Dating as §3.8 exit **keeping the 'Never introduce me' list** (`keepNeverIntroduce: true`, as exit v2 keeps it when its box is ticked), says so ("Your 'Never introduce me' list stays. You can delete it from Leave Dating and delete my data."), then opens D1; the person can still delete the list from Leave (a later exit without the box). No SQL function changes: exit v2 already keeps the list when asked and is never device-gated (carry 11); contract Q pins that the list survives a restart from a new phone and that a later Leave deletes it (mutant `restart_drops_list`).
- **Ruling R-33:** D13's line "We still need to check it's you before introductions start." stays: it is still true when activation refuses for the check, and it now links to D11.
- **Ruling R-35 (with R-13):** "a failed face match" in the owner's ruling is read as the ID route's face match (the face on the document against the person). A profile photo that doesn't match the video stays recoverable ("Change that photo, or ask a person to review it", §3.3.2), and a person's failed review (`identity_failed`) offers the video again, as before. Cost if wrong: one outcome mapping in `verify_flow.dart`.
- **Ruling R-34:** Spec 1's access-token hook, dormancy and hold kinds are untouched; W4 only calls `place_account_hold` with Spec 1's own `age_review` kind.

## Interfaces this plan consumes (read from the current code; adjust here if a later fix renames one)

- **Spec 1:** `public.place_account_hold(p_user uuid, p_kind text, p_ref text DEFAULT NULL)` (I-7); `public.account_birthdates (user_id, birth_date)`; `private.attune_environment()`; `private.assert_development_project()`; `private.app_setting(text)`; `public.feature_flags`, `private.flag_production_gates`; `SafetyPinStore` keystore options (`lib/features/safety/data/safety_pin_store.dart`); `Haptics` (`lib/core/ui/feedback/haptics.dart`); `homeLocation`, `AppTab.me`; `FlowFrame`, `FlowPrimaryButton`, `FlowSecondaryButton`, `FlowTextLink`, `FlowErrorLine`; `AllowLargeText`; test helpers `expectFlowGoldens`, `expectFlowGuidelines`, `tapInReach`, `scripts/large_text_audit.py`.
- **S2 W1–W3 (live):** `public.dating_flag_enabled(text)`; `private.dating_lock_setup(uuid)`; `public.check_dating_rate_limit(text, int, interval)`; `public.invalidate_dating_for_user(uuid, text)`; `public.dating_eligibility(uuid, text)`; `private.dating_setup_guard()`; `public.dating_require_trusted_device()` (W1c pass-through); `public.get_dating_home()` (W3 v2); `private.dating_exit_internal(uuid, boolean)`; `public.dating_profile_photos` (approved photos and their storage paths); `public.dating_consent_events` and `record_dating_consent(…, p_purpose 'biometric_verification', …)`; the bucket `dating-profile-photos`; `_shared/aws_rekognition.ts` (`compareFaces`); `DatingRpc`, `DatingActionKeys`, `datingWrite`, `DatingLifecycleError` (`reverifyDevice`, `activationGatesNotMet`), `DatingHome`, `DatingHomeState` (`verifying`, `reverifyDevice` already parsed as unknown), `DatingPauseReason`, `datingAccountProvider`, `datingSupabaseClientProvider`, `datingHomeProvider`, `datingLifecycleGatewayProvider`, `DatingStepFrame`, `datingRefusalLine`, `datingRoute()`, `DatingPaths`, `DatingMotion`, `datingPhotosProvider`, `DatingImagePreparer`, the D11 shell in `verify_step.dart`.

## Interfaces this plan produces (for W5 onward)

- **SQL (W4a):** tables `dating_verification_sessions`; the reshaped `dating_age_verifications` (`age_method` `fae|id`, `age_result`, `challenge_age`, `age_vendor`, `age_decided_at`, `identity_method` `liveness_compare|human_review|id_face`, `identity_result`, `identity_vendor`, `identity_decided_at`, `decided_by`, `revoked_at`, `revoke_reason`); the flag `dating_age_assurance`; the vault setting `age_assurance_mode` (`off|fake|sandbox|live`); service functions `get_dating_verification_config()`, `begin_dating_verification(p_user, p_kind, p_step, p_vendor, p_device_hash DEFAULT NULL, p_document DEFAULT NULL)`, `get_dating_verification_session(p_user, p_session)`, `get_dating_verification_photos(p_user)`, `set_dating_verification_ref(p_session, p_ref)`, `record_dating_liveness_attempt(p_session, p_passed)`, `finish_dating_verification_session(p_session, p_state, p_outcome, p_position)`, `record_dating_identity_check(p_user, p_session, p_method, p_result, p_vendor)`, `record_dating_age_assurance(p_user, p_session, p_method, p_result, p_challenge_age, p_vendor)`, `record_dating_age_far_below(p_user, p_session)`, `check_dating_id_birth_date(p_user, p_dob) → match|mismatch|minor|unknown`, `submit_dating_human_review(p_user, p_session)`, `decide_dating_human_review(p_session, p_outcome pass|fail|ask_for_id, p_decided_by)`, `revoke_dating_age_verification(p_user, p_reason)`, `sweep_dating_verification_sessions()`; client functions `get_my_dating_verification()` and `dating_review_upload_open(text)`; `get_dating_home()` state `verifying`; pause reason `verification`; closed reasons `age_review`, `age_verification_invalid`. **(W4b):** table `dating_trusted_devices`; `trust_dating_device(p_user, p_device_hash)`; the real `dating_require_trusted_device()` (never NULL); `private.dating_device_state(uuid, text) → unbound|trusted|untrusted`, `private.dating_device_gate(uuid)`, `private.dating_reverify_variant(uuid) → setup_restart|verified`, `private.dating_request_device_hash()`; `get_dating_home()`'s `reverify_device` carries `variant`; session kind `reverify`.
- **Edge:** `dating-verification` (`verify_jwt = true`): `{action, …}` → `{ok:true, …}` | `{ok:false, reason}` with fixed codes; `_shared/age_assurance/{types,fake,aws,smile_id,providers}.ts` (`providersFor(mode, env, fetch)`); `_shared/aws_rekognition.ts` gains `rekognitionCall`.
- **App:** `lib/features/dating/verify/{dating_verification.dart (DatingVerification, DatingCheck, DatingVerifyOutcome, DatingVerifyRefusal, DatingVerifySession, DatingIdDocument, DatingVerifyAnswer), dating_verification_repository.dart (DatingVerificationGateway, DatingVerificationRepository), dating_verification_providers.dart (datingVerificationGatewayProvider, datingVerificationProvider, datingReviewCameraProvider), dating_capture.dart (DatingCaptureLauncher, DatingDevCaptureLauncher, DatingCaptureVoice, DatingPracticeCaptureScreen, kDatingPromptGap), verify_flow.dart (DatingVerifyFlow, DatingVerifyStage, kDatingVerifiedFade), reverify_route.dart (DatingReverifyRoute, DatingStartAgainScreen)}`; `lib/core/device/install_id.dart` (`InstallIdStore`, `installIdStoreProvider`); `DatingDeviceHttpClient`, `datingDeviceHeader`; `DatingPaths.verify`; `DatingHome.reverifyVariant`, `DatingReverifyVariant`.

## File map

**W4a.** Task 1 creates `$D/{suite.sh, grants_line.py, dmut.py, anchor.py, mutate.py, marked_diff.py, before_w4a/, sql-baseline.txt, flutter-baseline.txt, analyze-baseline.txt, mig_T1_head.sql, mig_T1_tail.sql, build_mig_T1.py, edit_tests_T1.py, edit_canary_T1.py, edit_dev_T1.py, mut_T1.py}`, `supabase/migrations/20261109100000_dating_v2_age_assurance.sql`, `…100010_…_grants.sql`, `supabase/tests/dating_v2_verification_contracts.sql`, `supabase/sql/dev_dating_review_decide.sql`; modifies `supabase/tests/{dating_v2_home,dating_v2_identity,dating_v2_setup,identity_foundation,dating_mode,account_deletion}_contracts.sql`, `dating_rls_canary.sql`, `storage_bucket_policies.sql`, `service_role_grants_test.sql`, `supabase/sql/dev_enable_spec2_dating_flags.sql`, `scripts/local_pg_grants.sql`. Task 2 creates `supabase/functions/_shared/age_assurance/{types,fake,aws,smile_id,providers,providers.test}.ts`, `supabase/functions/dating-verification/{handler,index,handler.test}.ts`, `$D/{denomut.py, edit_rekognition_T2.py, edit_ci_T2.py, mut_T2.py}`; modifies `_shared/aws_rekognition.ts`, `.github/workflows/tests.yml`, `supabase/config.toml`; deletes `supabase/functions/verify-dating-profile/`. Task 3 creates `lib/features/dating/verify/{dating_verification,dating_verification_repository,dating_verification_providers,dating_capture}.dart`, `test/features/dating/support/dating_verify_fakes.dart`, `test/features/dating/verify/{dating_verification_data,dating_capture_section}_test.dart`, `$D/{edit_T3.py, arb_fragment_T3.txt, mut_T3.py}`; modifies `dating_home.dart`, `dating_section.dart`, `test/features/dating/data/dating_home_test.dart`, the ARB and generated l10n. Task 4 creates `lib/features/dating/verify/verify_flow.dart`, `test/features/dating/verify/verify_flow_test.dart` and its goldens, `$D/{edit_T4.py, arb_fragment_T4.txt, mut_T4.py}`; replaces `lib/features/dating/setup/verify_step.dart`; modifies `dating_list_names.dart`, `dating_mode_docs.dart`, `test/features/dating/support/dating_shell.dart`, `test/features/dating/setup/d11_d13_test.dart` and `d11_verify` goldens, the ARB.

**W4b.** Task 5 creates `supabase/migrations/20261109110000_dating_v2_trusted_devices.sql`, `…110010_…_grants.sql`, `$D/{before_w4b/, mig_T5_head.sql, mig_T5_tail.sql, build_mig_T5.py, contract_T5.sql, edit_tests_T5.py, edit_races_T5.py, mut_T5.py}`; modifies `dating_v2_verification_contracts.sql`, `dating_v2_identity_contracts.sql`, `dating_v2_home_contracts.sql`, `dating_rls_canary.sql`, `service_role_grants_test.sql`, `scripts/local_pg_grants.sql`, `scripts/concurrency/dating_kill_switch_races.sh`. Task 6 creates `lib/core/device/install_id.dart`, `test/core/device/install_id_test.dart`, `test/features/dating/data/dating_supabase_client_test.dart`, `test/architecture/dating_device_header_test.dart`, `$D/{edit_edge_T6.py, edit_T6.py, mut_T6_deno.py, mut_T6.py}`; replaces `lib/features/dating/data/dating_supabase_client.dart`; modifies `dating-verification/{handler,handler.test}.ts`, `lib/app/app.dart` (one line). Task 7 creates `lib/features/dating/verify/reverify_route.dart`, `test/features/dating/verify/reverify_test.dart` and its goldens, `$D/{edit_T7.py, arb_fragment_T7.txt, mut_T7.py}`; modifies `dating_home.dart`, `dating_routes.dart`, `verify_flow.dart`, `dating_step_frame.dart`, `dating_lifecycle_errors.dart`, `dating_section.dart`, `gentle_wait_screen.dart`, `test/architecture/text_scale_routes_test.dart`, the ARB.

**Not edited:** `lib/main.dart`, `lib/home/home_screen.dart`, `quick_exit_service.dart`, `auth_provider.dart`, every Spec 1 file but `lib/app/app.dart`'s one line, every applied migration, `scripts/local_pg_setup.sh`, every edge function but the two named, every contract not named above, Games, Opinions, `ATTUNE_SOUL.md`, `ATTUNE_THESIS.md`.

---

## Batch W4a — the verification seam and D11

### Task 1: The W4 tool folder, the baselines, migration `dating_v2_age_assurance` and its contract (§4.9 W4a, §3.3.1–§3.3.3, §4.3, §4.4, §4.5, §4.8, §4.10, §6.3, §7.1, §7.5 mutant 8; I-7, R8; carries 1, 2, 5; R-1–R-8, R-12–R-13, R-25–R-31)

**Files:**
- Create: `$D/{mutate.py, marked_diff.py, before_w4a/, mig_T1_head.sql, mig_T1_tail.sql, build_mig_T1.py, edit_tests_T1.py, edit_canary_T1.py, edit_dev_T1.py, mut_T1.py}` (and `suite.sh`, `grants_line.py`, `dmut.py`, `anchor.py` copied from W3), `supabase/migrations/20261109100000_dating_v2_age_assurance.sql`, `supabase/migrations/20261109100010_dating_v2_age_assurance_grants.sql`, `supabase/tests/dating_v2_verification_contracts.sql`, `supabase/sql/dev_dating_review_decide.sql`
- Modify: `supabase/tests/{dating_v2_home,dating_v2_identity,dating_v2_setup,identity_foundation,dating_mode,account_deletion}_contracts.sql` (v1 age fixtures to v2; the setup photo-readers pin), `supabase/tests/dating_rls_canary.sql`, `supabase/tests/storage_bucket_policies.sql`, `supabase/tests/service_role_grants_test.sql`, `supabase/sql/dev_enable_spec2_dating_flags.sql`, `scripts/local_pg_grants.sql`

**Interfaces:**
- Consumes: the live bodies of the nine functions in Step 4 (read from `attune_spec3a`); Spec 1's `place_account_hold(uuid, text, text)`, `account_birthdates`; W1's `dating_age_verifications`, `dating_consent_events`, `private.dating_lock_setup`; W3's `dating_profile_photos`, `get_dating_home()` v2.
- Produces: every W4a SQL interface under "Interfaces this plan produces". `get_my_dating_verification()` answers `{ok:true, available, device:'trusted'|'untrusted', age, identity, photos_ready, id_documents:[{code, name_key}], session:{id, kind, step, state, attempts, outcome, position, open, gestures}|null}` (no vendor reference, no hash, no date); an untrusted device (W4b) reads only `{ok, available, device, session}` for its own re-check. `get_dating_home()` answers `{state:'verifying'}` while a person or the ID vendor checks.

- [ ] **Step 1: Check the target and the free timestamps**

```bash
psql -X -d attune_spec3a -Atc 'select current_database()'
ls supabase/migrations | sort | tail -1
git rev-parse --short HEAD
```

Expected: `attune_spec3a`; `20261107170010_dating_v2_photos_grants.sql`; `7ddbe9c2` (or a later commit of the owner's: then read `git log --oneline 7ddbe9c2..HEAD` and say in the report what changed). If the last migration is at or after `20261109100000`, shift the four W4 timestamps (Global Constraints).

- [ ] **Step 2: The tool folder**

```bash
D=.superpowers/sdd/2026-11-09-spec2-w4; mkdir -p $D/mut
for f in suite.sh grants_line.py dmut.py anchor.py; do cp .superpowers/sdd/2026-11-07-spec2-w3/$f $D/$f; done
chmod +x $D/suite.sh
```

Create `$D/mutate.py` with exactly:

```python
#!/usr/bin/env python3
"""Spec 2 W4 mutation runner (attune_spec3a; W4_DB names a scratch clone
of it when the plan says so).
usage: mutate.py <migration.sql> <contract.sql> <spec.py> <dir> [<twin.sql>]
spec.py defines MUTS = {name: mutation}; a mutation is
  (old, new)            one exact occurrence in the migration, whose own
                        BEGIN/COMMIT are removed;
  ('MULTI', [(o, n)])   several such edits;
  ('RAW', sql)          SQL of its own;
  ('LIVE', (sig, [(o, n)]))  the function's LIVE body (pg_get_functiondef,
                        read at run time) with each edit made exactly once,
                        re-created; an anchor that is missing raises
                        'mutant anchor missing' (reported, never a kill).
Each runs after a BEGIN and before the contract, whose ROLLBACK undoes it.
With <twin.sql>, the twin (its BEGIN/COMMIT removed) runs right after a
(old, new) or MULTI mutant, as it does after the real migration (W3 I-7).
The contract's first ERROR is printed."""
import os, pathlib, re, runpy, subprocess, sys

mig, con, spec, out = sys.argv[1], sys.argv[2], sys.argv[3], pathlib.Path(sys.argv[4])
db = os.environ.get('W4_DB', 'attune_spec3a')
out.mkdir(parents=True, exist_ok=True)

def strip(path):
    t = pathlib.Path(path).read_text()
    assert t.count("\nBEGIN;\n") <= 1 and t.count("\nCOMMIT;\n") <= 1, path
    return t.replace("\nBEGIN;\n", "\n").replace("\nCOMMIT;\n", "\n")

def dollar(s):
    assert '$mut$' not in s
    return '$mut$' + s + '$mut$'

body = strip(mig)
twin = strip(sys.argv[5]) if len(sys.argv) > 5 else None
for name, (a, b) in runpy.run_path(spec)['MUTS'].items():
    if a == 'RAW':
        text = b
    elif a == 'LIVE':
        sig, edits = b
        steps = '\n'.join(
            f"  IF position({dollar(o)} IN v) = 0 THEN RAISE EXCEPTION 'mutant anchor missing: %', {dollar(o[:40])}; END IF;\n"
            f"  v := replace(v, {dollar(o)}, {dollar(n)});" for o, n in edits)
        text = (f"DO $live$\nDECLARE v text := pg_get_functiondef('{sig}'::regprocedure);\nBEGIN\n{steps}\n"
                f"  EXECUTE v;\nEND $live$;\n")
    elif a == 'MULTI':
        text = body
        for x, y in b:
            assert text.count(x) == 1, (name, x[:50], text.count(x))
            text = text.replace(x, y)
    else:
        assert body.count(a) == 1, (name, body.count(a))
        text = body.replace(a, b)
    if twin is not None and a not in ('RAW', 'LIVE'):
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

Create `$D/marked_diff.py` with exactly:

```python
#!/usr/bin/env python3
"""usage: marked_diff.py <before dir> <db> <tag>
For every <before dir>/<signature>.sql (a pg_get_functiondef saved before
the migration), diffs it with the function's body now. Every added or
changed line must carry <tag> (e.g. 'Spec 2 W4a'), or sit inside a run of
added lines that starts with a comment line carrying it. The header (the
lines before AS $function$, rebuilt from the catalog, so a comment there
is lost) is shown as "header:" and never fails. Prints one line per
function and exits 1 on any unmarked change in a body."""
import difflib, pathlib, subprocess, sys
before, db, tag = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]
bad = 0
for f in sorted(before.glob('*.sql')):
    sig = f.stem
    now = subprocess.run(['psql', '-X', '-d', db, '-Atc', f"select pg_get_functiondef('{sig}'::regprocedure)"],
                         check=True, capture_output=True, text=True).stdout.rstrip('\n').splitlines()
    old = f.read_text().rstrip('\n').splitlines()
    cut = next((i for i, l in enumerate(now) if l.startswith('AS $')), 0)
    header = [l[2:].strip() for l in difflib.ndiff(old, now[:cut + 1]) if l.startswith('+ ')]
    now = now[cut:]
    old = old[next((i for i, l in enumerate(old) if l.startswith('AS $')), 0):]
    added = [l[2:] for l in difflib.ndiff(old, now) if l.startswith('+ ')]
    unmarked = []
    in_block = False
    for line in added:
        if tag in line:
            in_block = line.lstrip().startswith('--')
            continue
        if in_block and line.strip():
            continue
        unmarked.append(line.strip())
    status = 'OK' if not unmarked else 'UNMARKED'
    bad += bool(unmarked)
    print(f'{sig}: {len(added)} added line(s) {status}' + ('' if not unmarked else ': ' + ' | '.join(unmarked)[:200])
          + ('' if not header else '; header: ' + ' | '.join(header)))
sys.exit(1 if bad else 0)
```

Expected: no output.

- [ ] **Step 3: The baselines**

```bash
D=.superpowers/sdd/2026-11-09-spec2-w4
$D/suite.sh attune_spec3a > $D/sql-baseline.txt; echo "$(grep -c '^PASS' $D/sql-baseline.txt) PASS, $(grep -c '^FAIL' $D/sql-baseline.txt) FAIL"
flutter analyze --no-pub lib test > $D/analyze-baseline.txt 2>&1; tail -1 $D/analyze-baseline.txt
flutter test --reporter compact > $D/flutter-baseline.txt 2>&1; tr '\r' '\n' < $D/flutter-baseline.txt | grep -E '^[0-9:]+ \+[0-9]+' | tail -1
shasum -c .superpowers/sdd/2026-11-04-spec1-w10-accessibility-docs/w10-1.0.sha | grep -vc ': OK$'
shasum -c .superpowers/sdd/2026-11-04-spec1-w9/flag_off.sha | grep -vc ': OK$'
shasum -c .superpowers/sdd/2026-11-07-spec2-w3/latch.sha
```

Expected: `159 PASS, 14 FAIL`; `571 issues found. (ran in …)`; a last line with `+7975` and only the known flakes failing (`chat_controller_test:259`, `chat_screen_list_anchor` D<0, `reflection_journal` at midnight, `planning_recent`; name each one that failed in the report); `0`; `0`; `lib/home/home_screen.dart: OK`. The full run takes 12–15 minutes; if the machine sleeps it can time out loading files (`TimeoutException after 0:12:00`): re-run those files alone, never count them as failures.

- [ ] **Step 4: Save the live bodies the migration re-creates**

```bash
D=.superpowers/sdd/2026-11-09-spec2-w4; mkdir -p $D/before_w4a
for sig in 'public.dating_age_gate_holds(uuid)' 'public.enforce_dating_age_verification_change()' 'public.invalidate_dating_for_user(uuid,text)' 'public.enforce_dating_restriction_change()' 'public.dating_pair_passes_hard_filters(uuid,uuid)' 'public.resume_dating_mode(text)' 'public.get_dating_home()' 'private.dating_exit_internal(uuid,boolean)' 'public.get_dating_operational_health()'; do
  psql -X -d attune_spec3a -Atc "select pg_get_functiondef('$sig'::regprocedure)" > "$D/before_w4a/$sig.sql"
done
ls $D/before_w4a | wc -l
```

Expected: `9`.

- [ ] **Step 5: Write the failing contract**

Create `supabase/tests/dating_v2_verification_contracts.sql` with exactly:

```sql
-- supabase/tests/dating_v2_verification_contracts.sql
-- Spec 2 W4a (§3.3, §4.3, §4.4, §4.5, §6.3, §7.1, §7.2 S1/S2/S16, §7.5
-- mutant 8; I-7, R8; carries 1, 5): the verification record keeps no DOB,
-- estimate or image (A); a typed DOB alone never opens the age gate (B);
-- only the service role records a result, and a fae pass needs the
-- challenge age 25 (C); identity sets the profile's verification state
-- (D); a revocation or a failed age check pauses with its own reason and
-- closes every match (E, carry 1); an age_review restriction closes every
-- match as age_review (F); far below 18 places Spec 1's account hold once,
-- with three arguments, and nothing else in Dating calls it (G, R8); the
-- sessions (H); the human route (I); the person's own status read (J);
-- get_dating_home's verifying state (K); the ID's date of birth is compared,
-- never stored (L); the sweep (M); exit (N); no Dating function reads a
-- stored DOB (O); the dev script (P).
-- W4b appends its sections (trusted devices) above the final ROLLBACK.
-- One BEGIN ... ROLLBACK. Run only on attune_spec3a:
--   psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/dating_v2_verification_contracts.sql
-- Fixture ids 5e400000-0000-0000-0000-0000000000NN; phones 15558707NN.
BEGIN;

DO $$
BEGIN
  PERFORM set_config('app.settings.dating_exclusion_key', 'spec2-w4a-verify-key', true);
  PERFORM set_config('app.settings.dating_field_key', 'spec2-w4a-field-key-0123456789abcdef-0123', true);
  PERFORM set_config('app.settings.age_assurance_mode', 'fake', true);
END $$;
SELECT private.seed_dating_exclusion_key_fingerprint() AS seeded \gset
SELECT private.seed_dating_field_key_fingerprint() AS seeded_field \gset
INSERT INTO public.feature_flags (key, enabled) VALUES ('dating_mode_enabled', true), ('dating_age_assurance', true)
ON CONFLICT (key) DO UPDATE SET enabled = true;
SELECT public.publish_country_config('GH', '{"dating_enabled": true, "open_regions": ["AA", "AH"]}') AS gh \gset
SELECT public.publish_country_config('GB', '{"dating_enabled": true}') AS gb \gset

CREATE FUNCTION pg_temp.id(p_n text) RETURNS uuid LANGUAGE sql IMMUTABLE AS $$
  SELECT ('5e400000-0000-0000-0000-0000000000' || p_n)::uuid;
$$;
-- An adult [p_n] (declared age [p_years]) on the Dating path with a draft
-- profile in [p_country]/[p_region], every D4 consent and the biometric one,
-- and [p_photos] approved, scanned photos.
CREATE FUNCTION pg_temp.person(p_n text, p_years int DEFAULT 30, p_photos int DEFAULT 2,
                               p_country text DEFAULT 'GB', p_region text DEFAULT 'TLI',
                               p_biometric boolean DEFAULT true) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE
  v_u constant uuid := pg_temp.id(p_n);
BEGIN
  INSERT INTO auth.users (id, phone, phone_confirmed_at, created_at)
  VALUES (v_u, '15558707' || p_n, now(), now() - interval '40 days');
  INSERT INTO public.users (id, phone, display_name, path, created_at, eula_accepted_at, eula_version)
  VALUES (v_u, '15558707' || p_n, 'Verify ' || p_n, 'dating', now() - interval '40 days', now(), '2');
  IF p_years IS NOT NULL THEN
    INSERT INTO public.account_birthdates (user_id, birth_date)
    VALUES (v_u, (current_date - make_interval(years => p_years) - interval '10 days')::date);
  END IF;
  INSERT INTO public.dating_enrollments (user_id, state, opted_in_at) VALUES (v_u, 'profile_draft', now());
  INSERT INTO public.dating_profiles (user_id, display_name, country_code, region_code)
  VALUES (v_u, 'Verify', p_country, p_region);
  INSERT INTO public.dating_consent_events (user_id, idempotency_key, purpose, action, policy_version, occurred_at)
  SELECT v_u, 'w4a-consent-' || p, p, 'granted', 'dating-2.0', clock_timestamp()
    FROM unnest(ARRAY['dating_terms', 'dating_opt_in', 'special_category_profile']
                || CASE WHEN p_biometric THEN ARRAY['biometric_verification'] ELSE ARRAY[]::text[] END) AS p;
  INSERT INTO public.dating_profile_photos (user_id, storage_key, position, moderation_state, csam_state)
  SELECT v_u, 'w4a/' || v_u || '/' || n || '.jpg', n, 'approved', 'clear' FROM generate_series(1, p_photos) AS n;
  RETURN v_u;
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
-- [p_sql] run as [p]; its raised SQLSTATE and message, or 'ok'.
CREATE FUNCTION pg_temp.err(p uuid, p_sql text) RETURNS text LANGUAGE plpgsql AS $$
BEGIN
  PERFORM pg_temp.as_person(p);
  EXECUTE p_sql;
  PERFORM pg_temp.as_db();
  RETURN 'ok';
EXCEPTION WHEN OTHERS THEN
  PERFORM pg_temp.as_db();
  RETURN SQLSTATE || ':' || SQLERRM;
END $$;
CREATE FUNCTION pg_temp.start(p uuid, p_step text DEFAULT 'liveness', p_doc text DEFAULT NULL) RETURNS jsonb LANGUAGE sql AS $$
  SELECT public.begin_dating_verification(p, 'activation', p_step, 'fake', NULL, p_doc);
$$;
CREATE FUNCTION pg_temp.match(p_a uuid, p_b uuid) RETURNS uuid LANGUAGE sql AS $$
  INSERT INTO public.dating_matches (user_low_id, user_high_id, state)
  VALUES (least(p_a, p_b), greatest(p_a, p_b), 'active') RETURNING id;
$$;
CREATE FUNCTION pg_temp.metric(p_key text) RETURNS bigint LANGUAGE sql AS $$
  SELECT coalesce((SELECT sum(c.count) FROM public.metric_counters AS c
                    WHERE c.day = (now() AT TIME ZONE 'utc')::date AND c.key = p_key), 0)::bigint;
$$;

-- =====================================================================
-- A. (§4.3, §1.4) The record keeps methods and pass/fail only: no DOB, no
--    date of any kind, no estimate, image or template; a fae pass below
--    the challenge age, or without one, is refused by the table itself.
-- =====================================================================
DO $a$
DECLARE
  v_u constant uuid := pg_temp.person('01');
  v_got text;
BEGIN
  SELECT string_agg(c.column_name, ', ' ORDER BY c.column_name) INTO v_got
    FROM information_schema.columns AS c
   WHERE c.table_schema = 'public' AND c.table_name = 'dating_age_verifications'
     AND (c.data_type = 'date' OR c.column_name ~ '(birth|dob|estimate|image|template|frame|selfie)');
  IF v_got IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: dating_age_verifications keeps %', v_got;
  END IF;
  SELECT string_agg(c.column_name, ', ' ORDER BY c.column_name) INTO v_got
    FROM information_schema.columns AS c
   WHERE c.table_schema = 'public' AND c.table_name = 'dating_verification_sessions'
     AND (c.data_type IN ('bytea', 'date') OR c.column_name ~ '(birth|dob|estimate|image|template|frame|selfie)');
  IF v_got IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: dating_verification_sessions keeps %', v_got;
  END IF;
  BEGIN
    INSERT INTO public.dating_age_verifications (user_id, age_method, age_result, challenge_age, age_vendor)
    VALUES (v_u, 'fae', 'pass', 24, 'fake');
    RAISE EXCEPTION 'CONTRACT VIOLATED: a fae pass at challenge age 24 was stored';
  EXCEPTION WHEN check_violation THEN
    NULL;
  END;
  BEGIN
    INSERT INTO public.dating_age_verifications (user_id, age_method, age_result, challenge_age, age_vendor)
    VALUES (v_u, 'fae', 'pass', NULL, 'fake');
    RAISE EXCEPTION 'CONTRACT VIOLATED: a fae pass with no challenge age was stored';
  EXCEPTION WHEN check_violation THEN
    NULL;
  END;
END $a$;

-- =====================================================================
-- B. (§3.3.1, §7.1, Q4) The age gate: a passed age check (fae or id), not
--    revoked, AND Spec 1's declared age 18 or over. A typed DOB alone, an
--    identity pass alone, a declared minor or no declared DOB never pass.
-- =====================================================================
DO $b$
DECLARE
  v_adult constant uuid := pg_temp.person('02');
  v_minor constant uuid := pg_temp.person('03', 17);
  v_none constant uuid := pg_temp.person('04', NULL);
  v_failed constant uuid := pg_temp.person('31');
BEGIN
  IF public.dating_age_gate_holds(v_adult) IS NOT FALSE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a typed DOB alone opened the age gate';
  END IF;
  INSERT INTO public.dating_age_verifications (user_id, identity_method, identity_result, identity_vendor, identity_decided_at)
  VALUES (v_adult, 'liveness_compare', 'pass', 'fake', now());
  IF public.dating_age_gate_holds(v_adult) IS NOT FALSE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an identity pass alone opened the age gate';
  END IF;
  UPDATE public.dating_age_verifications SET age_method = 'fae', age_result = 'pass', challenge_age = 25,
         age_vendor = 'fake', age_decided_at = now() WHERE user_id = v_adult;
  INSERT INTO public.dating_age_verifications (user_id, age_method, age_result, challenge_age, age_vendor, age_decided_at)
  VALUES (v_minor, 'fae', 'pass', 25, 'fake', now()), (v_none, 'id', 'pass', NULL, 'fake', now());
  IF public.dating_age_gate_holds(v_adult) IS NOT TRUE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a fae pass for a declared adult is shut';
  END IF;
  IF public.dating_age_gate_holds(v_minor) IS NOT FALSE OR public.dating_age_gate_holds(v_none) IS NOT FALSE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a declared minor or a missing DOB passed the age gate';
  END IF;
  INSERT INTO public.dating_age_verifications (user_id, age_method, age_result, challenge_age, age_vendor, age_decided_at)
  VALUES (v_failed, 'id', 'fail', NULL, 'fake', now());
  IF public.dating_age_gate_holds(v_failed) IS NOT FALSE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a failed age check opened the gate';
  END IF;
  UPDATE public.dating_age_verifications SET revoked_at = now(), revoke_reason = 'contract' WHERE user_id = v_adult;
  IF public.dating_age_gate_holds(v_adult) IS NOT FALSE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a revoked age check still opens the gate';
  END IF;
END $b$;

-- =====================================================================
-- C. (§7.1, mutant 8) Only the service role records a result; a client
--    can't, even by calling the writer. A fae pass below 25 is refused
--    by name (no row); 25 passes; id needs no challenge age; bad input is
--    'invalid', never a raise.
-- =====================================================================
DO $c$
DECLARE
  v_u constant uuid := pg_temp.person('05');
  v_w constant uuid := pg_temp.person('06');
  v_sig text;
  v_got jsonb := '[]'::jsonb;
BEGIN
  FOREACH v_sig IN ARRAY ARRAY['public.record_dating_age_assurance(uuid,text,text,smallint,text)',
                               'public.record_dating_identity_check(uuid,text,text,text,uuid)',
                               'public.record_dating_age_far_below(uuid,uuid)',
                               'public.revoke_dating_age_verification(uuid,text)',
                               'public.begin_dating_verification(uuid,text,text,text,text,text)',
                               'public.decide_dating_human_review(uuid,text,uuid)'] LOOP
    IF has_function_privilege('authenticated', v_sig, 'EXECUTE') OR has_function_privilege('anon', v_sig, 'EXECUTE')
       OR NOT has_function_privilege('service_role', v_sig, 'EXECUTE') THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: % is not the service role''s alone', v_sig;
    END IF;
  END LOOP;
  IF pg_temp.err(v_u, format('SELECT public.record_dating_age_assurance(%L, ''id'', ''pass'', NULL, ''self'')', v_u))
       NOT LIKE '42501:%' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a signed-in person recorded their own age check';
  END IF;
  v_got := v_got || jsonb_build_array(
    public.record_dating_age_assurance(v_u, 'fae', 'pass', 24::smallint, 'fake'),
    public.record_dating_age_assurance(v_u, 'fae', 'pass', NULL, 'fake'),
    public.record_dating_age_assurance(v_u, 'id', 'pass', 25::smallint, 'fake'),
    public.record_dating_age_assurance(v_u, 'video', 'pass', NULL, 'fake'),
    public.record_dating_age_assurance(v_u, 'id', NULL, NULL, 'fake'),
    public.record_dating_age_assurance(v_u, 'id', 'pass', NULL, 'Not A Vendor'));
  IF v_got IS DISTINCT FROM '[{"ok": false, "reason": "challenge_too_low"}, {"ok": false, "reason": "invalid"},
      {"ok": false, "reason": "invalid"}, {"ok": false, "reason": "invalid"}, {"ok": false, "reason": "invalid"},
      {"ok": false, "reason": "invalid"}]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the age writer answered %', v_got;
  END IF;
  IF EXISTS (SELECT 1 FROM public.dating_age_verifications WHERE user_id = v_u) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a refused age result left a row';
  END IF;
  IF public.record_dating_age_assurance(v_u, 'fae', 'pass', 25::smallint, 'fake') ->> 'ok' IS DISTINCT FROM 'true'
     OR public.record_dating_age_assurance(v_w, 'id', 'pass', NULL, 'smile_id') ->> 'ok' IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a fae pass at 25 or an id pass was refused';
  END IF;
  IF NOT public.dating_age_gate_holds(v_u) OR NOT public.dating_age_gate_holds(v_w)
     OR (SELECT challenge_age FROM public.dating_age_verifications WHERE user_id = v_u) IS DISTINCT FROM 25
     OR (SELECT age_vendor FROM public.dating_age_verifications WHERE user_id = v_w) IS DISTINCT FROM 'smile_id' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a recorded age pass does not hold';
  END IF;
END $c$;

-- =====================================================================
-- C2. (R-13, owner ruling 2026-11-09) An estimate never ends the check: a
--     fae fail is refused ('invalid') and leaves no row; a video check that
--     ended needs_id or age_uncertain lets the ID check begin; only a failed
--     ID check (or Spec 1's under-18 hold, section G) is final.
-- =====================================================================
DO $c2$
DECLARE
  v_u constant uuid := pg_temp.person('32');
  v_v constant uuid := pg_temp.person('33');
  v_s uuid;
  v_o text;
  v_got jsonb := '[]'::jsonb;
BEGIN
  IF public.record_dating_age_assurance(v_u, 'fae', 'fail', 25::smallint, 'fake') IS DISTINCT FROM '{"ok": false, "reason": "invalid"}'::jsonb
     OR EXISTS (SELECT 1 FROM public.dating_age_verifications WHERE user_id = v_u) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a failed estimate was recorded as an age result';
  END IF;
  FOREACH v_o IN ARRAY ARRAY['needs_id', 'age_uncertain'] LOOP
    v_s := (pg_temp.start(v_u) ->> 'session_id')::uuid;
    v_got := v_got || jsonb_build_array(public.finish_dating_verification_session(v_s, 'passed', v_o, NULL) ->> 'ok');
    v_got := v_got || jsonb_build_array(pg_temp.start(v_u, 'id', 'passport') ->> 'ok');
  END LOOP;
  IF v_got IS DISTINCT FROM '["true", "true", "true", "true"]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a failed or uncertain estimate ended the check: %', v_got;
  END IF;
  -- A failed ID check is final: no step begins again.
  PERFORM public.record_dating_age_assurance(v_v, 'id', 'fail', NULL, 'fake');
  v_got := jsonb_build_array(pg_temp.start(v_v), pg_temp.start(v_v, 'id', 'passport'), pg_temp.start(v_v, 'human'));
  IF v_got IS DISTINCT FROM '[{"ok": false, "reason": "age_not_confirmed"}, {"ok": false, "reason": "age_not_confirmed"},
                              {"ok": false, "reason": "age_not_confirmed"}]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a failed ID check was not final: %', v_got;
  END IF;
END $c2$;

-- =====================================================================
-- D. (§3.3.1, §4.4) Identity: liveness_compare (no decider) or
--    human_gesture (a reviewer's id) sets the profile's verification
--    state; a fail clears it; no profile, no record.
-- =====================================================================
DO $d$
DECLARE
  v_u constant uuid := pg_temp.person('07');
  v_got jsonb;
BEGIN
  v_got := jsonb_build_array(
    public.record_dating_identity_check(v_u, 'liveness_compare', 'pass', 'fake', pg_temp.id('99')),
    public.record_dating_identity_check(v_u, 'human_gesture', 'pass', 'attune', NULL),
    public.record_dating_identity_check(pg_temp.id('98'), 'liveness_compare', 'pass', 'fake', NULL));
  IF v_got IS DISTINCT FROM '[{"ok": false, "reason": "invalid"}, {"ok": false, "reason": "invalid"},
                              {"ok": false, "reason": "not_eligible"}]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the identity writer answered %', v_got;
  END IF;
  PERFORM public.record_dating_identity_check(v_u, 'liveness_compare', 'pass', 'fake', NULL);
  IF (SELECT verification_state || '/' || verification_method FROM public.dating_profiles WHERE user_id = v_u)
       IS DISTINCT FROM 'verified/liveness_compare'
     OR (SELECT identity_result FROM public.dating_age_verifications WHERE user_id = v_u) IS DISTINCT FROM 'pass' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an identity pass did not verify the profile';
  END IF;
  PERFORM public.record_dating_identity_check(v_u, 'human_gesture', 'fail', 'attune', pg_temp.id('99'));
  IF (SELECT verification_state FROM public.dating_profiles WHERE user_id = v_u) IS DISTINCT FROM 'unverified'
     OR (SELECT decided_by FROM public.dating_age_verifications WHERE user_id = v_u) IS DISTINCT FROM pg_temp.id('99') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an identity fail did not clear the profile''s verification';
  END IF;
END $d$;

-- =====================================================================
-- E. (§4.10, 04 G14, carry 1) A revocation, or an age check that fails,
--    pauses the active enrolment with 'verification' and closes every
--    match as age_verification_invalid (30-day evidence window); resume
--    refuses while it stands.
-- =====================================================================
DO $e$
DECLARE
  v_a constant uuid := pg_temp.person('08');
  v_b constant uuid := pg_temp.person('09');
  v_c constant uuid := pg_temp.person('10');
  v_m uuid;
  v_n uuid;
BEGIN
  PERFORM public.record_dating_age_assurance(u, 'fae', 'pass', 25::smallint, 'fake') FROM unnest(ARRAY[v_a, v_b, v_c]) AS u;
  UPDATE public.dating_enrollments SET state = 'active', activated_at = now() WHERE user_id IN (v_a, v_c);
  UPDATE public.dating_profiles SET profile_state = 'active' WHERE user_id IN (v_a, v_c);
  v_m := pg_temp.match(v_a, v_b);
  v_n := pg_temp.match(v_c, v_b);
  IF public.revoke_dating_age_verification(v_a, 'contract') ->> 'ok' IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the revocation was refused';
  END IF;
  IF (SELECT state || '/' || coalesce(pause_reason, 'NULL') FROM public.dating_enrollments WHERE user_id = v_a) IS DISTINCT FROM 'paused/verification'
     OR NOT EXISTS (SELECT 1 FROM public.dating_matches WHERE id = v_m AND state = 'closed'
                     AND closed_reason = 'age_verification_invalid'
                     AND evidence_until BETWEEN now() + interval '29 days' AND now() + interval '31 days') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a revocation did not pause with its reason or close the match: % / %',
      (SELECT state || '/' || coalesce(pause_reason, 'NULL') FROM public.dating_enrollments WHERE user_id = v_a),
      (SELECT state || '/' || coalesce(closed_reason, 'NULL') FROM public.dating_matches WHERE id = v_m);
  END IF;
  IF pg_temp.err(v_a, 'SELECT public.resume_dating_mode(''w4a-resume-00001'')') IS DISTINCT FROM '22023:resume_gates_not_met' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: resume did not refuse a revoked age check: %',
      pg_temp.err(v_a, 'SELECT public.resume_dating_mode(''w4a-resume-00002'')');
  END IF;
  PERFORM public.record_dating_age_assurance(v_c, 'id', 'fail', NULL, 'fake');
  IF (SELECT state || '/' || coalesce(pause_reason, 'NULL') FROM public.dating_enrollments WHERE user_id = v_c) IS DISTINCT FROM 'paused/verification'
     OR NOT EXISTS (SELECT 1 FROM public.dating_matches WHERE id = v_n AND closed_reason = 'age_verification_invalid') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a failed age check did not pause or close';
  END IF;
END $e$;

-- =====================================================================
-- F. (§6.3, §7.1, §7.2 S2) An age_review restriction (the underage_risk
--    path) closes every match as age_review.
-- =====================================================================
DO $f$
DECLARE
  v_a constant uuid := pg_temp.person('11');
  v_b constant uuid := pg_temp.person('12');
  v_c constant uuid := pg_temp.person('13');
  v_m1 uuid;
  v_m2 uuid;
BEGIN
  v_m1 := pg_temp.match(v_a, v_b);
  v_m2 := pg_temp.match(v_a, v_c);
  INSERT INTO public.dating_account_restrictions (user_id, restriction_type) VALUES (v_a, 'age_review');
  IF (SELECT count(*) FROM public.dating_matches WHERE id IN (v_m1, v_m2) AND state = 'closed' AND closed_reason = 'age_review') <> 2 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an age_review left a match open or closed it under another reason';
  END IF;
END $f$;

-- =====================================================================
-- G. (§3.3.2, §6.3, I-7, R8) Far below 18: the age check fails, every
--    match closes as age_review, and Spec 1's age_review hold is placed
--    with the session as its reference, once; a replay places nothing more.
--    Nothing else in Dating calls place_account_hold.
-- =====================================================================
DO $g$
DECLARE
  v_a constant uuid := pg_temp.person('14');
  v_b constant uuid := pg_temp.person('15');
  v_s uuid;
  v_m uuid;
  v_at timestamptz;
  v_got text;
BEGIN
  v_s := (pg_temp.start(v_a) ->> 'session_id')::uuid;
  v_m := pg_temp.match(v_a, v_b);
  IF public.record_dating_age_far_below(v_a, v_s) IS DISTINCT FROM '{"ok": true, "replayed": false}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the far-below path was refused';
  END IF;
  SELECT created_at INTO v_at FROM public.account_holds WHERE user_id = v_a AND kind = 'age_review';
  IF (SELECT reason_ref FROM public.account_holds WHERE user_id = v_a AND kind = 'age_review' AND resolved_at IS NULL)
       IS DISTINCT FROM v_s::text THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the age_review hold does not name the session (three arguments, I-7)';
  END IF;
  IF (SELECT age_result || '/' || age_method FROM public.dating_age_verifications WHERE user_id = v_a) IS DISTINCT FROM 'fail/fae'
     OR (SELECT closed_reason FROM public.dating_matches WHERE id = v_m) IS DISTINCT FROM 'age_review'
     OR (SELECT state || '/' || outcome FROM public.dating_verification_sessions WHERE id = v_s) IS DISTINCT FROM 'failed/far_below' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: far below 18 did not fail the age check, close as age_review and end the session';
  END IF;
  IF public.record_dating_age_far_below(v_a, v_s) IS DISTINCT FROM '{"ok": true, "replayed": true}'::jsonb
     OR (SELECT created_at FROM public.account_holds WHERE user_id = v_a AND kind = 'age_review') IS DISTINCT FROM v_at THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a replay of the far-below path placed the hold again';
  END IF;
  IF public.record_dating_age_far_below(v_b, v_s) IS DISTINCT FROM '{"ok": false, "reason": "session_unavailable"}'::jsonb
     OR EXISTS (SELECT 1 FROM public.account_holds WHERE user_id = v_b) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: another person''s session placed a hold';
  END IF;
  SELECT string_agg(p.oid::regprocedure::text, ', ' ORDER BY p.oid::regprocedure::text) INTO v_got
    FROM pg_proc AS p
   WHERE p.prosrc ~ 'place_account_hold\(' AND p.proname <> 'place_account_hold';
  IF v_got IS DISTINCT FROM 'consume_fresh_start(text,text), correct_my_birth_date(date), private.handle_csam_match(text,text,uuid,text,text,boolean,text), record_dating_age_far_below(uuid,uuid), set_my_birth_date(date)' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the callers of place_account_hold changed (R8): %', v_got;
  END IF;
  -- The hold is Spec 1's: Dating reads it as account_unavailable / age_review.
  IF public.dating_eligibility(v_a, 'setup') IS DISTINCT FROM 'account_unavailable'
     OR private.dating_unavailable_state(v_a) IS DISTINCT FROM 'age_review' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the hold does not close Dating';
  END IF;
END $g$;

-- =====================================================================
-- H. (§3.3.2, §4.7) Sessions: every refusal by name, never a raise; a
--    resumed session is the same row; another step ends the open one; 5 a
--    day; a liveness failure counts (retry, then another way).
-- =====================================================================
DO $h$
DECLARE
  v_u constant uuid := pg_temp.person('16');
  v_one constant uuid := pg_temp.person('17', 30, 1);
  v_nobio constant uuid := pg_temp.person('18', 30, 2, 'GB', 'TLI', false);
  v_gh constant uuid := pg_temp.person('19', 30, 2, 'GH', 'AA');
  v_bare constant uuid := pg_temp.id('20');
  v jsonb;
  v_s uuid;
  v_t uuid;
  v_got jsonb;
BEGIN
  INSERT INTO auth.users (id, phone, phone_confirmed_at, created_at) VALUES (v_bare, '1555870720', now(), now() - interval '40 days');
  INSERT INTO public.users (id, phone, display_name, path, created_at, eula_accepted_at, eula_version)
  VALUES (v_bare, '1555870720', 'Verify 20', 'dating', now() - interval '40 days', now(), '2');
  INSERT INTO public.account_birthdates (user_id, birth_date) VALUES (v_bare, current_date - interval '30 years');
  v_got := jsonb_build_array(
    public.begin_dating_verification(v_u, 'reverify', 'liveness', 'fake', NULL, NULL),
    public.begin_dating_verification(v_u, 'activation', 'selfie', 'fake', NULL, NULL),
    public.begin_dating_verification(v_u, 'activation', 'liveness', 'Fake!', NULL, NULL),
    public.begin_dating_verification(v_u, 'activation', 'liveness', 'fake', 'not-a-hash', NULL),
    public.begin_dating_verification(v_u, 'activation', 'id', 'fake', NULL, NULL),
    public.begin_dating_verification(v_u, 'activation', 'liveness', 'fake', NULL, 'passport'),
    pg_temp.start(v_bare), pg_temp.start(v_nobio), pg_temp.start(v_one),
    pg_temp.start(v_gh, 'id', 'uk_photocard_driving_licence'));
  IF v_got IS DISTINCT FROM '[{"ok": false, "reason": "invalid"}, {"ok": false, "reason": "invalid"},
      {"ok": false, "reason": "invalid"}, {"ok": false, "reason": "invalid"}, {"ok": false, "reason": "invalid"},
      {"ok": false, "reason": "invalid"}, {"ok": false, "reason": "not_eligible"}, {"ok": false, "reason": "consent_required"},
      {"ok": false, "reason": "photos_required"}, {"ok": false, "reason": "invalid"}]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: begin answered %', v_got;
  END IF;
  -- Off: the flag, or a fake mode outside development.
  UPDATE public.feature_flags SET enabled = false WHERE key = 'dating_age_assurance';
  v := pg_temp.start(v_u);
  UPDATE public.feature_flags SET enabled = true WHERE key = 'dating_age_assurance';
  PERFORM set_config('app.settings.attune_environment', 'production', true);
  v_got := jsonb_build_array(v, pg_temp.start(v_u));
  PERFORM set_config('app.settings.attune_environment', '', true);
  IF v_got IS DISTINCT FROM '[{"ok": false, "reason": "unavailable"}, {"ok": false, "reason": "unavailable"}]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: begin ran with the flag off or fake in production: %', v_got;
  END IF;
  -- Begin, resume (same row, no new one), then a liveness failure twice.
  v := pg_temp.start(v_u);
  v_s := (v ->> 'session_id')::uuid;
  IF v ->> 'resumed' IS DISTINCT FROM 'false' OR (pg_temp.start(v_u) ->> 'session_id')::uuid IS DISTINCT FROM v_s
     OR pg_temp.start(v_u) ->> 'resumed' IS DISTINCT FROM 'true'
     OR (SELECT count(*) FROM public.dating_verification_sessions WHERE user_id = v_u) <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a resumed session is not the same row: %', v;
  END IF;
  v_got := jsonb_build_array(public.record_dating_liveness_attempt(v_s, false), public.record_dating_liveness_attempt(v_s, false),
                             public.record_dating_liveness_attempt(v_s, true));
  IF v_got IS DISTINCT FROM '[{"ok": true, "outcome": "retry", "attempts": 1}, {"ok": true, "outcome": "another_way", "attempts": 2},
                              {"ok": true, "attempts": 2}]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: liveness attempts answered %', v_got;
  END IF;
  -- Another step ends the open one; an expired session is gone for writes.
  v_t := (pg_temp.start(v_u, 'human') ->> 'session_id')::uuid;
  IF v_t IS NULL OR v_t = v_s OR (SELECT state FROM public.dating_verification_sessions WHERE id = v_s) <> 'expired'
     OR (SELECT cardinality(gestures) FROM public.dating_verification_sessions WHERE id = v_t) <> 2
     OR (SELECT gestures[1] <> gestures[2] AND gestures <@ ARRAY['three_fingers', 'left_ear', 'thumbs_up']
           FROM public.dating_verification_sessions WHERE id = v_t) IS NOT TRUE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the human route did not end the video session or pick two gestures';
  END IF;
  UPDATE public.dating_verification_sessions SET expires_at = now() - interval '1 second' WHERE id = v_t;
  IF public.record_dating_liveness_attempt(v_s, false) IS DISTINCT FROM '{"ok": false, "reason": "session_unavailable"}'::jsonb
     OR public.set_dating_verification_ref(v_t, 'ref') IS DISTINCT FROM '{"ok": false, "reason": "session_unavailable"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an ended or expired session was written';
  END IF;
  -- Five sessions a day.
  FOR i IN 1..3 LOOP
    PERFORM pg_temp.start(v_u, CASE WHEN i % 2 = 1 THEN 'liveness' ELSE 'human' END);
  END LOOP;
  IF (SELECT count(*) FROM public.dating_verification_sessions WHERE user_id = v_u) <> 5
     OR pg_temp.start(v_u, 'id', 'passport') IS DISTINCT FROM '{"ok": false, "reason": "rate_limited"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a sixth session in a day was opened';
  END IF;
  -- The refused start left the open session as it was.
  IF (SELECT count(*) FROM public.dating_verification_sessions WHERE user_id = v_u AND state = 'started') <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a refused start ended the open session';
  END IF;
  -- awaiting review, already verified, age not confirmed.
  UPDATE public.dating_verification_sessions SET state = 'awaiting_review' WHERE user_id = v_u AND state = 'started';
  IF pg_temp.start(v_u) ->> 'reason' IS DISTINCT FROM 'awaiting_review' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a session opened beside one awaiting review';
  END IF;
  PERFORM public.record_dating_age_assurance(v_gh, 'fae', 'pass', 25::smallint, 'fake');
  PERFORM public.record_dating_identity_check(v_gh, 'liveness_compare', 'pass', 'fake', NULL);
  v_got := jsonb_build_array(pg_temp.start(v_gh), pg_temp.start(v_gh, 'id', 'ghana_card'), pg_temp.start(v_gh, 'human'));
  PERFORM public.record_dating_age_assurance(v_gh, 'id', 'fail', NULL, 'fake');
  v_got := v_got || jsonb_build_array(pg_temp.start(v_gh));
  IF v_got IS DISTINCT FROM '[{"ok": false, "reason": "already_verified"}, {"ok": false, "reason": "already_verified"},
                              {"ok": false, "reason": "already_verified"}, {"ok": false, "reason": "age_not_confirmed"}]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a verified or failed person began a session: %', v_got;
  END IF;
  -- A new photo after the check needs the video again (W3c: needs_review).
  UPDATE public.dating_age_verifications SET age_result = 'pass', age_method = 'fae', challenge_age = 25 WHERE user_id = v_gh;
  UPDATE public.dating_profiles SET verification_state = 'needs_review' WHERE user_id = v_gh;
  IF pg_temp.start(v_gh) ->> 'ok' IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a new photo after the check could not be checked again';
  END IF;
  -- finish: named outcomes only; a mismatch names its slot.
  v_s := (SELECT id FROM public.dating_verification_sessions WHERE user_id = v_gh AND state = 'started');
  v_got := jsonb_build_array(public.finish_dating_verification_session(v_s, 'failed', 'photo_mismatch', NULL),
                             public.finish_dating_verification_session(v_s, 'failed', 'verified', 2::smallint),
                             public.finish_dating_verification_session(v_s, 'started', 'verified', NULL),
                             public.finish_dating_verification_session(v_s, 'failed', 'photo_mismatch', 2::smallint),
                             public.finish_dating_verification_session(v_s, 'passed', 'verified', NULL));
  IF v_got IS DISTINCT FROM '[{"ok": false, "reason": "invalid"}, {"ok": false, "reason": "invalid"}, {"ok": false, "reason": "invalid"},
                              {"ok": true, "reason": null}, {"ok": false, "reason": "session_unavailable"}]'::jsonb
     OR (SELECT outcome || '/' || outcome_position FROM public.dating_verification_sessions WHERE id = v_s) IS DISTINCT FROM 'photo_mismatch/2' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: finish answered %', v_got;
  END IF;
END $h$;

-- =====================================================================
-- I. (§3.3.3, §4.5) The human route: the two photos go only under the
--    person's own open human session's two paths; submit needs both; a
--    reviewer decides identity only (never age); the photos are queued
--    for deletion at the decision.
-- =====================================================================
DO $i$
DECLARE
  v_u constant uuid := pg_temp.person('21');
  v_x constant uuid := pg_temp.person('22');
  v_s uuid;
  v_v uuid;
  v_got jsonb;
BEGIN
  PERFORM public.record_dating_age_assurance(v_u, 'fae', 'pass', 25::smallint, 'fake');
  v_v := (pg_temp.start(v_u) ->> 'session_id')::uuid;
  v_s := (pg_temp.start(v_u, 'human') ->> 'session_id')::uuid;
  v_got := jsonb_build_array(
    pg_temp.call(v_u, format('SELECT to_jsonb(public.dating_review_upload_open(%L))', v_s || '/1.jpg')),
    pg_temp.call(v_u, format('SELECT to_jsonb(public.dating_review_upload_open(%L))', v_s || '/2.jpg')),
    pg_temp.call(v_u, format('SELECT to_jsonb(public.dating_review_upload_open(%L))', v_s || '/3.jpg')),
    pg_temp.call(v_u, format('SELECT to_jsonb(public.dating_review_upload_open(%L))', v_s || '/1.png')),
    pg_temp.call(v_u, format('SELECT to_jsonb(public.dating_review_upload_open(%L))', v_v || '/1.jpg')),
    pg_temp.call(v_x, format('SELECT to_jsonb(public.dating_review_upload_open(%L))', v_s || '/1.jpg')));
  IF v_got IS DISTINCT FROM '[true, true, false, false, false, false]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the review upload predicate answered %', v_got;
  END IF;
  INSERT INTO storage.objects (bucket_id, name, owner) VALUES ('dating-verification-review', v_s || '/1.jpg', v_u);
  IF public.submit_dating_human_review(v_u, v_s) IS DISTINCT FROM '{"ok": false, "reason": "photos_missing"}'::jsonb
     OR public.submit_dating_human_review(v_x, v_s) IS DISTINCT FROM '{"ok": false, "reason": "session_unavailable"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a review was submitted with one photo, or for someone else';
  END IF;
  INSERT INTO storage.objects (bucket_id, name, owner) VALUES ('dating-verification-review', v_s || '/2.jpg', v_u);
  -- (Each call is its own statement: an IF's terms have no evaluation order.)
  v_got := public.submit_dating_human_review(v_u, v_s);
  IF v_got ->> 'ok' IS DISTINCT FROM 'true'
     OR (SELECT state || '/' || outcome FROM public.dating_verification_sessions WHERE id = v_s) IS DISTINCT FROM 'awaiting_review/human_pending'
     OR (SELECT verification_state FROM public.dating_profiles WHERE user_id = v_u) IS DISTINCT FROM 'needs_review' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a submitted review is not waiting for a person';
  END IF;
  IF pg_temp.call(v_u, format('SELECT to_jsonb(public.dating_review_upload_open(%L))', v_s || '/1.jpg')) <> 'false'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a submitted review still takes uploads';
  END IF;
  v_got := jsonb_build_array(public.decide_dating_human_review(v_s, 'pass', NULL),
                             public.decide_dating_human_review(v_s, 'approve', pg_temp.id('99')));
  IF v_got IS DISTINCT FROM '[{"ok": false, "reason": "invalid"}, {"ok": false, "reason": "invalid"}]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: decide answered %', v_got;
  END IF;
  UPDATE public.dating_age_verifications SET age_result = 'fail', age_method = 'id', challenge_age = NULL WHERE user_id = v_u;
  v_got := public.decide_dating_human_review(v_s, 'pass', pg_temp.id('99'));
  IF v_got ->> 'ok' IS DISTINCT FROM 'true'
     OR (SELECT identity_method || '/' || identity_result || '/' || decided_by FROM public.dating_age_verifications WHERE user_id = v_u)
          IS DISTINCT FROM 'human_gesture/pass/' || pg_temp.id('99')
     OR (SELECT age_result FROM public.dating_age_verifications WHERE user_id = v_u) IS DISTINCT FROM 'fail'
     OR (SELECT state || '/' || outcome FROM public.dating_verification_sessions WHERE id = v_s) IS DISTINCT FROM 'passed/verified'
     OR (SELECT count(*) FROM public.media_deletion_queue WHERE bucket_id = 'dating-verification-review'
          AND object_name IN (v_s || '/1.jpg', v_s || '/2.jpg')) <> 2 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a reviewer''s pass did not decide identity only, or kept the photos';
  END IF;
  -- ask for ID: the profile goes back to unverified, identity untouched.
  v_s := (pg_temp.start(v_x, 'human') ->> 'session_id')::uuid;
  INSERT INTO storage.objects (bucket_id, name, owner) VALUES
    ('dating-verification-review', v_s || '/1.jpg', v_x), ('dating-verification-review', v_s || '/2.jpg', v_x);
  PERFORM public.submit_dating_human_review(v_x, v_s);
  PERFORM public.decide_dating_human_review(v_s, 'ask_for_id', pg_temp.id('99'));
  IF (SELECT verification_state FROM public.dating_profiles WHERE user_id = v_x) IS DISTINCT FROM 'unverified'
     OR EXISTS (SELECT 1 FROM public.dating_age_verifications WHERE user_id = v_x AND identity_result IS NOT NULL)
     OR (SELECT outcome FROM public.dating_verification_sessions WHERE id = v_s) IS DISTINCT FROM 'ask_for_id' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: ask for ID decided identity';
  END IF;
END $i$;

-- =====================================================================
-- J. (§3.3.2) The person's own status read: signed in; their own data
--    only; never a vendor reference, a device hash or an estimate; on an
--    untrusted device only the device answer; unavailable with the flag
--    off or fake in production.
-- =====================================================================
DO $j$
DECLARE
  v_u constant uuid := pg_temp.person('23', 30, 2, 'GH', 'AA');
  v_x constant uuid := pg_temp.person('24');
  v jsonb;
  v_s uuid;
  v_msg text;
BEGIN
  BEGIN
    PERFORM public.get_my_dating_verification();
    RAISE EXCEPTION 'CONTRACT VIOLATED: the status read answered a signed-out caller';
  EXCEPTION WHEN insufficient_privilege THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg IS DISTINCT FROM 'not_authenticated' THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: signed out raised %', v_msg;
    END IF;
  END;
  v_s := (pg_temp.start(v_u) ->> 'session_id')::uuid;
  PERFORM public.set_dating_verification_ref(v_s, 'vendor-secret-ref');
  UPDATE public.dating_verification_sessions SET device_hash = repeat('a', 64) WHERE id = v_s;
  PERFORM public.record_dating_liveness_attempt(v_s, false);
  v := pg_temp.call(v_u, 'SELECT public.get_my_dating_verification()');
  IF v ->> 'available' IS DISTINCT FROM 'true' OR v ->> 'device' IS DISTINCT FROM 'trusted'
     OR v -> 'age' IS DISTINCT FROM 'null'::jsonb OR v -> 'identity' IS DISTINCT FROM 'null'::jsonb
     OR v #>> '{session,id}' IS DISTINCT FROM v_s::text OR v #>> '{session,open}' IS DISTINCT FROM 'true'
     OR v #>> '{session,outcome}' IS DISTINCT FROM 'retry' OR v #>> '{session,attempts}' IS DISTINCT FROM '1'
     OR v -> 'id_documents' IS DISTINCT FROM '[{"code": "ghana_card", "name_key": "dating_id_ghana_card"}, {"code": "passport", "name_key": "dating_id_passport"}]'::jsonb
     OR v ->> 'photos_ready' IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the status read answered %', v;
  END IF;
  IF position('vendor-secret-ref' IN v::text) > 0 OR position(repeat('a', 64) IN v::text) > 0
     OR position('vendor' IN v::text) > 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the status read carries a vendor reference or a device hash: %', v;
  END IF;
  IF pg_temp.call(v_x, 'SELECT public.get_my_dating_verification()') -> 'session' IS DISTINCT FROM 'null'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the status read showed another person''s session';
  END IF;
  -- An untrusted device (stub, rolled back): only the device answer.
  BEGIN
    CREATE OR REPLACE FUNCTION public.dating_require_trusted_device() RETURNS boolean
      LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $stub$ SELECT false $stub$;
    v := pg_temp.call(v_u, 'SELECT public.get_my_dating_verification()');
    RAISE SQLSTATE 'W4A99';
  EXCEPTION WHEN SQLSTATE 'W4A99' THEN
    NULL;
  END;
  IF v IS DISTINCT FROM '{"ok": true, "device": "untrusted", "session": null, "available": true}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an untrusted device read %', v;
  END IF;
  UPDATE public.feature_flags SET enabled = false WHERE key = 'dating_age_assurance';
  v := pg_temp.call(v_u, 'SELECT public.get_my_dating_verification()');
  UPDATE public.feature_flags SET enabled = true WHERE key = 'dating_age_assurance';
  PERFORM set_config('app.settings.attune_environment', 'production', true);
  v := jsonb_build_array(v ->> 'available', pg_temp.call(v_u, 'SELECT public.get_my_dating_verification()') ->> 'available');
  PERFORM set_config('app.settings.attune_environment', '', true);
  IF v IS DISTINCT FROM '["false", "false"]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the check reads available with the flag off or fake in production: %', v;
  END IF;
END $j$;

-- =====================================================================
-- K. (§3.1) get_dating_home: 'verifying' while a person or the ID vendor
--    is checking (and the check is the next step); setup otherwise.
-- =====================================================================
DO $k$
DECLARE
  v_u constant uuid := pg_temp.person('25');
  v_s uuid;
BEGIN
  INSERT INTO public.dating_profile_sensitive (user_id, identity_enc, seeking_enc)
  VALUES (v_u, private.dating_field_encrypt('{"identity": "woman"}'), private.dating_field_encrypt('{"seeking": ["man"]}'));
  UPDATE public.dating_profiles SET intention = 'committed', not_married_attested_at = now(), attestation_version = '2026-10-v1',
         children_have = false, children_want = 'open' WHERE user_id = v_u;
  INSERT INTO public.dating_prompts (user_id, position, prompt_id, answer, moderation_state)
  SELECT v_u, n, (ARRAY['perfect_sunday', 'friends_say'])[n], 'An answer long enough ' || n, 'approved' FROM generate_series(1, 2) AS n;
  IF pg_temp.call(v_u, 'SELECT public.get_dating_home()') ->> 'next_step' IS DISTINCT FROM 'verify'
     OR pg_temp.call(v_u, 'SELECT public.get_dating_home()') ->> 'state' IS DISTINCT FROM 'setup_in_progress' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the fixture is not at the check: %', pg_temp.call(v_u, 'SELECT public.get_dating_home()');
  END IF;
  v_s := (pg_temp.start(v_u, 'human') ->> 'session_id')::uuid;
  INSERT INTO storage.objects (bucket_id, name, owner) VALUES
    ('dating-verification-review', v_s || '/1.jpg', v_u), ('dating-verification-review', v_s || '/2.jpg', v_u);
  PERFORM public.submit_dating_human_review(v_u, v_s);
  IF (pg_temp.call(v_u, 'SELECT public.get_dating_home()') - 'has_data') IS DISTINCT FROM '{"state": "verifying", "next_step": "verify"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a review in progress does not read verifying: %', pg_temp.call(v_u, 'SELECT public.get_dating_home()');
  END IF;
END $k$;

-- =====================================================================
-- L. (§3.3.2) The ID's date of birth is compared with the declared one and
--    forgotten: match, mismatch, minor, unknown.
-- =====================================================================
DO $l$
DECLARE
  v_u constant uuid := pg_temp.person('26');
  v_none constant uuid := pg_temp.person('27', NULL);
  v_dob date;
BEGIN
  SELECT birth_date INTO v_dob FROM public.account_birthdates WHERE user_id = v_u;
  IF jsonb_build_array(public.check_dating_id_birth_date(v_u, v_dob), public.check_dating_id_birth_date(v_u, v_dob - 1),
                       public.check_dating_id_birth_date(v_u, (current_date - interval '16 years')::date),
                       public.check_dating_id_birth_date(v_none, v_dob), public.check_dating_id_birth_date(v_u, NULL),
                       public.check_dating_id_birth_date(v_u, current_date + 1))
     IS DISTINCT FROM '["match", "mismatch", "minor", "unknown", "unknown", "unknown"]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the ID date-of-birth check is wrong';
  END IF;
  IF (SELECT provolatile FROM pg_proc WHERE oid = 'public.check_dating_id_birth_date(uuid,date)'::regprocedure) <> 's' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the ID date-of-birth check can write';
  END IF;
END $l$;

-- =====================================================================
-- M. (§4.8, R-6) The sweep: an open session past its time expires; a
--    review waiting 72 hours expires (asked again); every review photo
--    older than 72 hours is queued for deletion; sessions older than 30
--    days are deleted.
-- =====================================================================
DO $m$
DECLARE
  v_u constant uuid := pg_temp.person('28');
  v_w constant uuid := pg_temp.person('29');
  v_s uuid;
  v_r uuid;
BEGIN
  v_s := (pg_temp.start(v_u) ->> 'session_id')::uuid;
  UPDATE public.dating_verification_sessions SET expires_at = now() - interval '1 minute' WHERE id = v_s;
  v_r := (pg_temp.start(v_w, 'human') ->> 'session_id')::uuid;
  INSERT INTO storage.objects (bucket_id, name, owner, created_at) VALUES
    ('dating-verification-review', v_r || '/1.jpg', v_w, now() - interval '73 hours'),
    ('dating-verification-review', v_r || '/2.jpg', v_w, now() - interval '73 hours'),
    ('dating-verification-review', 'orphan-of-a-deleted-account/1.jpg', NULL, now() - interval '80 hours');
  PERFORM public.submit_dating_human_review(v_w, v_r);
  UPDATE public.dating_verification_sessions SET created_at = now() - interval '73 hours' WHERE id = v_r;
  INSERT INTO public.dating_verification_sessions (user_id, kind, step, state, created_at, expires_at)
  VALUES (v_u, 'activation', 'liveness', 'failed', now() - interval '31 days', now() - interval '31 days');
  PERFORM public.sweep_dating_verification_sessions();
  IF (SELECT state FROM public.dating_verification_sessions WHERE id = v_s) <> 'expired'
     OR (SELECT state FROM public.dating_verification_sessions WHERE id = v_r) <> 'expired'
     OR (SELECT verification_state FROM public.dating_profiles WHERE user_id = v_w) <> 'unverified'
     OR (SELECT count(*) FROM public.media_deletion_queue WHERE bucket_id = 'dating-verification-review'
          AND object_name IN (v_r || '/1.jpg', v_r || '/2.jpg', 'orphan-of-a-deleted-account/1.jpg')) <> 3
     OR EXISTS (SELECT 1 FROM public.dating_verification_sessions WHERE user_id = v_u AND created_at < now() - interval '30 days') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the sweep left a session, a review or a photo';
  END IF;
END $m$;

-- =====================================================================
-- N. (§3.8, §4.8) Exit: the sessions and their review photos go, and the
--    identity result (it covered the deleted photos); the age result stays.
-- =====================================================================
DO $n$
DECLARE
  v_u constant uuid := pg_temp.person('30');
  v_s uuid;
BEGIN
  PERFORM public.record_dating_age_assurance(v_u, 'fae', 'pass', 25::smallint, 'fake');
  PERFORM public.record_dating_identity_check(v_u, 'liveness_compare', 'pass', 'fake', NULL);
  UPDATE public.dating_profiles SET verification_state = 'needs_review' WHERE user_id = v_u;
  v_s := (pg_temp.start(v_u, 'human') ->> 'session_id')::uuid;
  INSERT INTO storage.objects (bucket_id, name, owner) VALUES ('dating-verification-review', v_s || '/1.jpg', v_u);
  PERFORM pg_temp.call(v_u, 'SELECT to_jsonb(public.exit_dating_mode(''w4a-exit-000001''))');
  IF EXISTS (SELECT 1 FROM public.dating_verification_sessions WHERE user_id = v_u)
     OR NOT EXISTS (SELECT 1 FROM public.media_deletion_queue WHERE bucket_id = 'dating-verification-review' AND object_name = v_s || '/1.jpg')
     OR (SELECT identity_result FROM public.dating_age_verifications WHERE user_id = v_u) IS NOT NULL
     OR (SELECT age_result FROM public.dating_age_verifications WHERE user_id = v_u) IS DISTINCT FROM 'pass' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: exit kept a session, a review photo or the identity result, or lost the age result';
  END IF;
END $n$;

-- =====================================================================
-- O. (§1.4) No function reads a date of birth from the verification
--    record; the v1 writers are gone.
-- =====================================================================
DO $o$
DECLARE
  v_got text;
BEGIN
  SELECT string_agg(p.oid::regprocedure::text, ', ') INTO v_got FROM pg_proc AS p
   WHERE p.prosrc ~ 'dating_age_verifications' AND p.prosrc ~ '(birth_date|verified_by)';
  IF v_got IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: functions read v1 verification columns: %', v_got;
  END IF;
  IF to_regprocedure('public.verify_dating_age(uuid,date,text,uuid,timestamptz)') IS NOT NULL
     OR to_regprocedure('public.resolve_dating_verification_review(uuid,text)') IS NOT NULL
     OR to_regprocedure('public.revoke_dating_age_verification(uuid)') IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a v1 age writer is still there';
  END IF;
  -- §4.10 health: the mode and the review backlog are reported.
  IF NOT (public.get_dating_operational_health() ?& ARRAY['age_assurance_mode', 'verification_awaiting_review',
                                                         'verification_oldest_waiting_hours'])
     OR public.get_dating_operational_health() ->> 'age_assurance_mode' IS DISTINCT FROM 'fake' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: health does not report the verification mode and backlog';
  END IF;
END $o$;

-- =====================================================================
-- P. (§4.9 dev switch-on, I-15) The dev script turns dating_age_assurance
--    on and, with no mode set on a local database, sets 'fake'.
-- =====================================================================
DO $p$
BEGIN
  UPDATE public.feature_flags SET enabled = false WHERE key = 'dating_age_assurance';
  PERFORM set_config('app.settings.age_assurance_mode', '', true);
END $p$;
\i supabase/sql/dev_enable_spec2_dating_flags.sql
DO $p2$
BEGIN
  IF public.dating_flag_enabled('dating_age_assurance') IS NOT TRUE
     OR private.dating_verification_mode() IS DISTINCT FROM 'fake' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the dev script left dating_age_assurance % and the mode %',
      public.dating_flag_enabled('dating_age_assurance'), private.dating_verification_mode();
  END IF;
END $p2$;

DO $$ BEGIN RAISE NOTICE 'dating_v2_verification_contracts: all held'; END $$;
ROLLBACK;
```

- [ ] **Step 6: Run it to see it fail**

```bash
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/dating_v2_verification_contracts.sql 2>&1 | grep -m1 ERROR
```

Expected: `…: ERROR:  function public.begin_dating_verification(uuid, unknown, text, unknown, unknown, text) does not exist` (the contract's first helper names W4a's session function).

- [ ] **Step 7: Build the migration and its twin, and apply them**

Create `$D/mig_T1_head.sql` with exactly (the new objects, sections 1–21, and section 22's heading):

```sql
-- Spec 2 W4a, migration 1 (§4.9 W4a; §3.3; §4.3 dating_age_verifications,
-- dating_verification_sessions; §4.4 record_dating_age_assurance,
-- record_dating_identity_check, revoke_dating_age_verification; §4.5
-- dating-verification-review; §4.10 rows tagged W4; §6.3 account-level age
-- review; I-7; R8; plan R-1..R-14): the verification record keeps methods
-- and pass/fail only (no DOB, no estimate, no image, no template); the
-- verification sessions; the service writers the dating-verification edge
-- function calls, the far-below-18 path into Spec 1's place_account_hold
-- with three arguments (its only Dating caller); age_review and
-- age_verification_invalid close every match; the human-review bucket and
-- its INSERT policy; the client's own status read; the sweep; the flag
-- dating_age_assurance (off). Re-created from their live bodies (changed
-- lines marked -- Spec 2 W4a): dating_age_gate_holds,
-- enforce_dating_age_verification_change, invalidate_dating_for_user,
-- enforce_dating_restriction_change, dating_pair_passes_hard_filters,
-- resume_dating_mode, get_dating_home, private.dating_exit_internal,
-- get_dating_operational_health. Dropped: verify_dating_age,
-- resolve_dating_verification_review, the one-argument
-- revoke_dating_age_verification.
-- Grants in 20261109100010_dating_v2_age_assurance_grants.sql.
BEGIN;
SET LOCAL lock_timeout = '5s';

-- 1. The flag (off; supabase/sql/dev_enable_spec2_dating_flags.sql turns it
--    on in development) and its production gate (Spec 1's gate trigger).
INSERT INTO private.flag_production_gates (flag_key, gate) VALUES
  ('dating_age_assurance', 'Spec 2 W4 gate: signed estimation-vendor (UK highly effective, skin-tone and West African error data) and Smile ID (or equivalent) contracts, the DPIA biometric section, the AWS region recorded, the UK OSA HEAA method documented')
ON CONFLICT (flag_key) DO NOTHING;
INSERT INTO public.feature_flags (key, enabled) VALUES ('dating_age_assurance', false)
ON CONFLICT (key) DO NOTHING;

-- 2. A pause has a reason (carry 1): a revoked or failed age check pauses
--    with 'verification' (resume mirrors it; the app maps it).
ALTER TABLE public.dating_enrollments DROP CONSTRAINT IF EXISTS dating_enrollments_pause_reason_check;
ALTER TABLE public.dating_enrollments ADD CONSTRAINT dating_enrollments_pause_reason_check
  CHECK (pause_reason IS NULL OR pause_reason IN ('user', 'relationship', 'path_change', 'same_gender_switch',
                                                  'away', 'account_parked', 'gates', 'verification'));

-- 3. dating_age_verifications reshaped (§4.3, §1.4): one row per person,
--    the two checks' methods and results, who decided (a reviewer, for
--    identity only: a person never passes age), when, and a revocation.
--    The v1 rows held a typed date of birth and never ran in production:
--    they are deleted once, while the birth_date column still exists (a
--    replay deletes nothing). R-3: each check keeps its own decision time
--    (the ID and human routes finish at different times).
DO $reshape$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns AS c
              WHERE c.table_schema = 'public' AND c.table_name = 'dating_age_verifications'
                AND c.column_name = 'birth_date') THEN
    DELETE FROM public.dating_age_verifications;
  END IF;
END $reshape$;
ALTER TABLE public.dating_age_verifications
  DROP CONSTRAINT IF EXISTS dating_age_verifications_birth_date_check,
  DROP CONSTRAINT IF EXISTS dating_age_verifications_verification_method_check,
  DROP COLUMN IF EXISTS birth_date,
  DROP COLUMN IF EXISTS verification_method,
  DROP COLUMN IF EXISTS expires_at,
  DROP COLUMN IF EXISTS verified_by,
  DROP COLUMN IF EXISTS verified_at,
  ADD COLUMN IF NOT EXISTS age_method text,
  ADD COLUMN IF NOT EXISTS age_result text,
  ADD COLUMN IF NOT EXISTS challenge_age smallint,
  ADD COLUMN IF NOT EXISTS age_vendor text,
  ADD COLUMN IF NOT EXISTS age_decided_at timestamptz,
  ADD COLUMN IF NOT EXISTS identity_method text,
  ADD COLUMN IF NOT EXISTS identity_result text,
  ADD COLUMN IF NOT EXISTS identity_vendor text,
  ADD COLUMN IF NOT EXISTS identity_decided_at timestamptz,
  ADD COLUMN IF NOT EXISTS decided_by uuid,
  ADD COLUMN IF NOT EXISTS revoke_reason text;
ALTER TABLE public.dating_age_verifications DROP CONSTRAINT IF EXISTS dating_age_verifications_v2_check;
ALTER TABLE public.dating_age_verifications ADD CONSTRAINT dating_age_verifications_v2_check CHECK (
  (age_method IS NULL OR age_method IN ('fae', 'id'))
  AND (age_result IS NULL OR age_result IN ('pass', 'fail'))
  AND ((age_method IS NULL) = (age_result IS NULL))
  AND (identity_method IS NULL OR identity_method IN ('liveness_compare', 'human_gesture'))
  AND (identity_result IS NULL OR identity_result IN ('pass', 'fail'))
  AND ((identity_method IS NULL) = (identity_result IS NULL))
  AND (age_vendor IS NULL OR age_vendor ~ '^[a-z0-9_]{1,40}$')
  AND (identity_vendor IS NULL OR identity_vendor ~ '^[a-z0-9_]{1,40}$')
  AND (revoke_reason IS NULL OR revoke_reason ~ '^[a-z0-9_]{1,40}$')
  AND (challenge_age IS NULL OR challenge_age BETWEEN 18 AND 40));
-- §7.1: an estimate below the challenge age can never be a fae pass (a
-- missing challenge age is not one either).
ALTER TABLE public.dating_age_verifications DROP CONSTRAINT IF EXISTS dating_age_verifications_fae_challenge_check;
ALTER TABLE public.dating_age_verifications ADD CONSTRAINT dating_age_verifications_fae_challenge_check
  CHECK (age_method IS DISTINCT FROM 'fae' OR age_result IS DISTINCT FROM 'pass' OR coalesce(challenge_age, 0) >= 25);

-- 4. Verification sessions (§4.3; R-4: the last outcome, the slot it named,
--    the two gestures, the ID document and the device the session runs on
--    are kept with it, so a resumed or a waiting session reads the same).
CREATE TABLE IF NOT EXISTS public.dating_verification_sessions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  kind text NOT NULL CHECK (kind IN ('activation', 'reverify')),
  step text NOT NULL CHECK (step IN ('liveness', 'id', 'human')),
  vendor text CHECK (vendor IS NULL OR vendor ~ '^[a-z0-9_]{1,40}$'),
  vendor_session_ref text CHECK (vendor_session_ref IS NULL OR char_length(vendor_session_ref) BETWEEN 1 AND 200),
  attempts smallint NOT NULL DEFAULT 0 CHECK (attempts BETWEEN 0 AND 20),
  state text NOT NULL DEFAULT 'started'
    CHECK (state IN ('started', 'awaiting_review', 'passed', 'failed', 'expired')),
  outcome text CHECK (outcome IS NULL OR outcome IN (
    'retry', 'another_way', 'verified', 'needs_id', 'age_uncertain', 'photo_mismatch', 'far_below',
    'id_pending', 'dob_mismatch', 'age_not_confirmed', 'human_pending', 'identity_failed', 'ask_for_id')),
  outcome_position smallint CHECK (outcome_position IS NULL OR outcome_position BETWEEN 1 AND 6),
  gestures text[] CHECK (gestures IS NULL OR cardinality(gestures) = 2),
  id_document text CHECK (id_document IS NULL OR id_document ~ '^[a-z0-9_]{1,40}$'),
  device_hash text CHECK (device_hash IS NULL OR device_hash ~ '^[0-9a-f]{64}$'),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL
);
-- One open session per person (begin expires a stale one first).
CREATE UNIQUE INDEX IF NOT EXISTS dating_verification_sessions_open_idx
  ON public.dating_verification_sessions (user_id) WHERE state IN ('started', 'awaiting_review');
CREATE INDEX IF NOT EXISTS dating_verification_sessions_user_created_idx
  ON public.dating_verification_sessions (user_id, created_at DESC);
ALTER TABLE public.dating_verification_sessions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.dating_verification_sessions FROM PUBLIC, anon, authenticated;

-- 5. The human route's private bucket (§3.3.3, §4.5): INSERT only through
--    an open human session's two paths, <session id>/<1|2>.jpg; no client
--    SELECT; JPEG up to 2 MB.
INSERT INTO storage.buckets (id, name, public)
VALUES ('dating-verification-review', 'dating-verification-review', false)
ON CONFLICT (id) DO NOTHING;
DO $limits$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns AS c
              WHERE c.table_schema = 'storage' AND c.table_name = 'buckets' AND c.column_name = 'file_size_limit')
     AND EXISTS (SELECT 1 FROM information_schema.columns AS c
                  WHERE c.table_schema = 'storage' AND c.table_name = 'buckets' AND c.column_name = 'allowed_mime_types') THEN
    EXECUTE $q$UPDATE storage.buckets SET public = false, file_size_limit = 2097152, allowed_mime_types = ARRAY['image/jpeg'] WHERE id = 'dating-verification-review'$q$;
  END IF;
END $limits$;

-- 6. The mode, availability and challenge age the edge function reads
--    (§3.3.5): fake, sandbox or live from app_setting('age_assurance_mode');
--    anything else is unconfigured; fake is never available outside
--    development (the edge function refuses it too). Unavailable whenever
--    the flag is off.
CREATE OR REPLACE FUNCTION private.dating_verification_mode()
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT CASE WHEN s.m IN ('fake', 'sandbox', 'live') THEN s.m ELSE 'unconfigured' END
    FROM (SELECT lower(btrim(coalesce(public.app_setting('age_assurance_mode'), ''))) AS m) AS s;
$$;

CREATE OR REPLACE FUNCTION private.dating_verification_available()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT coalesce(public.dating_flag_enabled('dating_age_assurance'), false)
     AND private.dating_verification_mode() <> 'unconfigured'
     AND NOT (private.dating_verification_mode() = 'fake'
              AND private.attune_environment() IS DISTINCT FROM 'development');
$$;

CREATE OR REPLACE FUNCTION public.get_dating_verification_config()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT jsonb_build_object(
    'available', private.dating_verification_available(),
    'flag', coalesce(public.dating_flag_enabled('dating_age_assurance'), false),
    'mode', private.dating_verification_mode(),
    'environment', private.attune_environment(),
    'challenge_age', 25);
$$;

-- 7. The person's verification state: age and identity, each passed,
--    failed or not decided (revoked counts as not decided).
CREATE OR REPLACE FUNCTION private.dating_verification_state(p_user uuid)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT jsonb_build_object(
    'age', CASE WHEN v.revoked_at IS NULL THEN v.age_result END,
    'identity', CASE WHEN v.revoked_at IS NULL THEN v.identity_result END)
    FROM (SELECT p_user AS id) AS me
    LEFT JOIN public.dating_age_verifications AS v ON v.user_id = me.id;
$$;

-- 8. A session begins (service role: dating-verification's start, start_id
--    and human_start). Fails closed with a named reason, never a raise:
--    unavailable, invalid, not_eligible (setup eligibility, a Dating
--    enrolment), consent_required (biometric_verification), photos_required
--    (2 approved, for the video and the human route), age_not_confirmed (an
--    age check failed), already_verified, awaiting_review, rate_limited (5
--    sessions a day), busy. An open session of the same step resumes (R-5:
--    no new row, no rate cost); another step's open session ends first.
CREATE OR REPLACE FUNCTION public.begin_dating_verification(
  p_user uuid, p_kind text, p_step text, p_vendor text,
  p_device_hash text DEFAULT NULL, p_document text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
SET lock_timeout = '2s'
AS $$
DECLARE
  v_try integer;
  v_open public.dating_verification_sessions;
  v_row public.dating_verification_sessions;
  v_state jsonb;
  v_country text;
  v_gestures text[];
  v_has_open boolean;
BEGIN
  IF p_user IS NULL OR p_kind IS DISTINCT FROM 'activation'
     OR (p_step IN ('liveness', 'id', 'human')) IS NOT TRUE
     OR coalesce(p_vendor ~ '^[a-z0-9_]{1,40}$', false) IS NOT TRUE
     OR (p_device_hash IS NOT NULL AND p_device_hash !~ '^[0-9a-f]{64}$')
     OR (p_step = 'id') IS DISTINCT FROM (p_document IS NOT NULL)
     OR (p_document IS NOT NULL AND p_document !~ '^[a-z0-9_]{1,40}$') THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'invalid');
  END IF;
  IF private.dating_verification_available() IS NOT TRUE THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'unavailable');
  END IF;
  FOR v_try IN 1..3 LOOP
    BEGIN
      PERFORM private.dating_lock_setup(p_user);
      IF public.dating_eligibility(p_user, 'setup') IS DISTINCT FROM 'eligible'
         OR NOT EXISTS (SELECT 1 FROM public.dating_enrollments AS e
                         WHERE e.user_id = p_user AND e.state IN ('profile_draft', 'active', 'paused')) THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'not_eligible');
      END IF;
      IF private.dating_consent_granted(p_user, 'biometric_verification') IS NOT TRUE THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'consent_required');
      END IF;
      v_state := private.dating_verification_state(p_user);
      IF v_state ->> 'age' = 'fail' THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'age_not_confirmed');
      END IF;
      IF (p_step = 'id' AND v_state ->> 'age' = 'pass')
         OR (p_step = 'human' AND v_state ->> 'identity' = 'pass'
             AND (SELECT p.verification_state FROM public.dating_profiles AS p WHERE p.user_id = p_user) = 'verified')
         OR (p_step = 'liveness' AND v_state ->> 'age' = 'pass' AND v_state ->> 'identity' = 'pass'
             AND (SELECT p.verification_state FROM public.dating_profiles AS p WHERE p.user_id = p_user) = 'verified') THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'already_verified');
      END IF;
      IF p_step IN ('liveness', 'human')
         AND (SELECT count(*) FROM public.dating_profile_photos AS f
               WHERE f.user_id = p_user AND f.moderation_state = 'approved') < 2 THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'photos_required');
      END IF;
      IF p_step = 'id' THEN
        SELECT p.country_code::text INTO v_country FROM public.dating_profiles AS p WHERE p.user_id = p_user;
        IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(coalesce((public.dating_country_config(v_country)).id_documents, '[]'::jsonb)) AS d
                        WHERE d ->> 'code' = p_document) THEN
          RETURN jsonb_build_object('ok', false, 'reason', 'invalid');
        END IF;
      END IF;
      UPDATE public.dating_verification_sessions AS s
         SET state = 'expired', updated_at = now()
       WHERE s.user_id = p_user AND s.state = 'started' AND s.expires_at <= now();
      SELECT * INTO v_open FROM public.dating_verification_sessions AS s
       WHERE s.user_id = p_user AND s.state IN ('started', 'awaiting_review') FOR UPDATE;
      v_has_open := FOUND;
      IF v_has_open AND v_open.state = 'awaiting_review' THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'awaiting_review', 'session_id', v_open.id);
      END IF;
      IF v_has_open AND v_open.step = p_step AND v_open.id_document IS NOT DISTINCT FROM p_document THEN
        UPDATE public.dating_verification_sessions AS s
           SET vendor = p_vendor, device_hash = coalesce(p_device_hash, s.device_hash), updated_at = now()
         WHERE s.id = v_open.id RETURNING * INTO v_row;
        RETURN jsonb_build_object('ok', true, 'session_id', v_row.id, 'step', v_row.step, 'attempts', v_row.attempts,
                                  'resumed', true, 'gestures', to_jsonb(v_row.gestures), 'expires_at', v_row.expires_at);
      END IF;
      -- A refused start never ends the open session (the limit is read first).
      IF (SELECT count(*) FROM public.dating_verification_sessions AS s
           WHERE s.user_id = p_user AND s.created_at > now() - interval '1 day') >= 5 THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'rate_limited');
      END IF;
      IF v_has_open THEN
        UPDATE public.dating_verification_sessions AS s SET state = 'expired', updated_at = now() WHERE s.id = v_open.id;
      END IF;
      IF p_step = 'human' THEN
        SELECT array_agg(g ORDER BY random()) INTO v_gestures
          FROM (SELECT g FROM unnest(ARRAY['three_fingers', 'left_ear', 'thumbs_up']) AS g ORDER BY random() LIMIT 2) AS pick;
      END IF;
      INSERT INTO public.dating_verification_sessions (user_id, kind, step, vendor, device_hash, id_document, gestures, expires_at)
      VALUES (p_user, p_kind, p_step, p_vendor, p_device_hash, p_document, v_gestures,
              now() + CASE p_step WHEN 'liveness' THEN interval '30 minutes'
                                  WHEN 'id' THEN interval '24 hours' ELSE interval '72 hours' END)
      RETURNING * INTO v_row;
      PERFORM private.bump_metric_internal('dating.verification.started');
      RETURN jsonb_build_object('ok', true, 'session_id', v_row.id, 'step', v_row.step, 'attempts', 0,
                                'resumed', false, 'gestures', to_jsonb(v_row.gestures), 'expires_at', v_row.expires_at);
    EXCEPTION WHEN deadlock_detected OR lock_not_available OR serialization_failure OR unique_violation THEN
      IF v_try = 3 THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'busy');
      END IF;
    END;
  END LOOP;
  RETURN jsonb_build_object('ok', false, 'reason', 'busy');
END;
$$;

-- 9. The edge function's read of one of the person's sessions (its vendor
--    reference included; no client ever reads it) and of the approved
--    photos it compares against.
CREATE OR REPLACE FUNCTION public.get_dating_verification_session(p_user uuid, p_session uuid)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT CASE WHEN s.id IS NULL THEN jsonb_build_object('ok', false, 'reason', 'session_unavailable')
    ELSE jsonb_build_object('ok', true, 'session_id', s.id, 'kind', s.kind, 'step', s.step, 'state', s.state,
      'vendor', s.vendor, 'vendor_session_ref', s.vendor_session_ref, 'attempts', s.attempts,
      'id_document', s.id_document, 'device_hash', s.device_hash, 'outcome', s.outcome,
      'country', (SELECT p.country_code::text FROM public.dating_profiles AS p WHERE p.user_id = p_user),
      'expired', s.expires_at <= now(), 'age', private.dating_verification_state(p_user) ->> 'age',
      'identity', private.dating_verification_state(p_user) ->> 'identity') END
    FROM (SELECT 1) AS one
    LEFT JOIN public.dating_verification_sessions AS s ON s.id = p_session AND s.user_id = p_user;
$$;

CREATE OR REPLACE FUNCTION public.get_dating_verification_photos(p_user uuid)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT coalesce(jsonb_agg(jsonb_build_object('position', f.position, 'storage_key', f.storage_key) ORDER BY f.position), '[]'::jsonb)
    FROM public.dating_profile_photos AS f
   WHERE f.user_id = p_user AND f.moderation_state = 'approved' AND f.csam_state = 'clear';
$$;

CREATE OR REPLACE FUNCTION public.set_dating_verification_ref(p_session uuid, p_ref text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
SET lock_timeout = '2s'
AS $$
BEGIN
  IF p_session IS NULL OR coalesce(char_length(p_ref) BETWEEN 1 AND 200, false) IS NOT TRUE THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'invalid');
  END IF;
  UPDATE public.dating_verification_sessions AS s SET vendor_session_ref = p_ref, updated_at = now()
   WHERE s.id = p_session AND s.state = 'started' AND s.expires_at > now();
  RETURN jsonb_build_object('ok', FOUND, 'reason', CASE WHEN NOT FOUND THEN 'session_unavailable' END);
EXCEPTION WHEN lock_not_available OR deadlock_detected OR serialization_failure THEN
  RETURN jsonb_build_object('ok', false, 'reason', 'busy');
END;
$$;

-- 10. A liveness attempt the vendor answered (§3.3.2): a failure counts
--     (the first offers a retry, from the second "check another way"); a
--     network failure never reaches here (the edge function answers
--     vendor_unavailable without counting, §3.15 D11).
CREATE OR REPLACE FUNCTION public.record_dating_liveness_attempt(p_session uuid, p_passed boolean)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
SET lock_timeout = '2s'
AS $$
DECLARE
  v_row public.dating_verification_sessions;
BEGIN
  IF p_session IS NULL OR p_passed IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'invalid');
  END IF;
  IF p_passed THEN
    SELECT * INTO v_row FROM public.dating_verification_sessions AS s
     WHERE s.id = p_session AND s.step = 'liveness' AND s.state = 'started' AND s.expires_at > now();
    RETURN CASE WHEN FOUND THEN jsonb_build_object('ok', true, 'attempts', v_row.attempts)
                ELSE jsonb_build_object('ok', false, 'reason', 'session_unavailable') END;
  END IF;
  UPDATE public.dating_verification_sessions AS s
     SET attempts = least(s.attempts + 1, 20),
         outcome = CASE WHEN s.attempts + 1 >= 2 THEN 'another_way' ELSE 'retry' END, updated_at = now()
   WHERE s.id = p_session AND s.step = 'liveness' AND s.state = 'started' AND s.expires_at > now()
  RETURNING * INTO v_row;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'session_unavailable');
  END IF;
  PERFORM private.bump_metric_internal('dating.verification.liveness_failed');
  RETURN jsonb_build_object('ok', true, 'attempts', v_row.attempts, 'outcome', v_row.outcome);
EXCEPTION WHEN lock_not_available OR deadlock_detected OR serialization_failure THEN
  RETURN jsonb_build_object('ok', false, 'reason', 'busy');
END;
$$;

-- 11. A session ends with its outcome (the slot a mismatch named).
CREATE OR REPLACE FUNCTION public.finish_dating_verification_session(
  p_session uuid, p_state text, p_outcome text, p_position smallint DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
SET lock_timeout = '2s'
AS $$
BEGIN
  IF p_session IS NULL OR (p_state IN ('awaiting_review', 'passed', 'failed')) IS NOT TRUE
     OR (p_outcome IN ('verified', 'needs_id', 'age_uncertain', 'photo_mismatch', 'far_below', 'id_pending', 'dob_mismatch',
                       'age_not_confirmed', 'human_pending', 'identity_failed', 'ask_for_id')) IS NOT TRUE
     OR (p_outcome = 'photo_mismatch') IS DISTINCT FROM (p_position IS NOT NULL)
     OR (p_position IS NOT NULL AND p_position NOT BETWEEN 1 AND 6) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'invalid');
  END IF;
  UPDATE public.dating_verification_sessions AS s
     SET state = p_state, outcome = p_outcome, outcome_position = p_position, updated_at = now()
   WHERE s.id = p_session AND s.state IN ('started', 'awaiting_review');
  RETURN jsonb_build_object('ok', FOUND, 'reason', CASE WHEN NOT FOUND THEN 'session_unavailable' END);
EXCEPTION WHEN lock_not_available OR deadlock_detected OR serialization_failure THEN
  RETURN jsonb_build_object('ok', false, 'reason', 'busy');
END;
$$;

-- 12. The identity result (§3.3.1, §4.4; replaces
--     resolve_dating_verification_review): liveness_compare (the edge
--     function, no decider) or human_gesture (a reviewer's id). It sets the
--     profile's verification_state, which activation and the next step read.
CREATE OR REPLACE FUNCTION public.record_dating_identity_check(
  p_user uuid, p_method text, p_result text, p_vendor text, p_decided_by uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
SET lock_timeout = '2s'
AS $$
DECLARE
  v_try integer;
BEGIN
  IF p_user IS NULL OR (p_method IN ('liveness_compare', 'human_gesture')) IS NOT TRUE
     OR (p_result IN ('pass', 'fail')) IS NOT TRUE
     OR coalesce(p_vendor ~ '^[a-z0-9_]{1,40}$', false) IS NOT TRUE
     OR (p_method = 'human_gesture') IS DISTINCT FROM (p_decided_by IS NOT NULL) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'invalid');
  END IF;
  FOR v_try IN 1..3 LOOP
    BEGIN
      PERFORM private.dating_lock_setup(p_user);
      IF NOT EXISTS (SELECT 1 FROM public.dating_profiles AS p WHERE p.user_id = p_user) THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'not_eligible');
      END IF;
      INSERT INTO public.dating_age_verifications AS v (user_id, identity_method, identity_result, identity_vendor,
                                                       identity_decided_at, decided_by)
      VALUES (p_user, p_method, p_result, p_vendor, now(), p_decided_by)
      ON CONFLICT (user_id) DO UPDATE
        SET identity_method = EXCLUDED.identity_method, identity_result = EXCLUDED.identity_result,
            identity_vendor = EXCLUDED.identity_vendor, identity_decided_at = EXCLUDED.identity_decided_at,
            decided_by = EXCLUDED.decided_by, updated_at = now();
      UPDATE public.dating_profiles AS p
         SET verification_state = CASE WHEN p_result = 'pass' THEN 'verified' ELSE 'unverified' END,
             verification_method = p_method,
             verified_at = CASE WHEN p_result = 'pass' THEN now() END
       WHERE p.user_id = p_user;
      PERFORM private.bump_metric_internal('dating.verification.identity_' || p_result);
      RETURN jsonb_build_object('ok', true);
    EXCEPTION WHEN deadlock_detected OR lock_not_available OR serialization_failure THEN
      IF v_try = 3 THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'busy');
      END IF;
    END;
  END LOOP;
  RETURN jsonb_build_object('ok', false, 'reason', 'busy');
END;
$$;

-- 13. The age result (§3.3.1, §4.4; replaces verify_dating_age: no DOB
--     argument). fae passes only at the challenge age 25 or above (the
--     estimate itself never reaches the database); id needs no challenge
--     age. A new pass clears an earlier revocation; a fail pauses and
--     closes (the trigger).
CREATE OR REPLACE FUNCTION public.record_dating_age_assurance(
  p_user uuid, p_age_method text, p_age_result text, p_challenge_age smallint, p_vendor text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
SET lock_timeout = '2s'
AS $$
DECLARE
  v_try integer;
BEGIN
  IF p_user IS NULL OR (p_age_method IN ('fae', 'id')) IS NOT TRUE
     OR (p_age_result IN ('pass', 'fail')) IS NOT TRUE
     OR coalesce(p_vendor ~ '^[a-z0-9_]{1,40}$', false) IS NOT TRUE
     OR (p_age_method = 'fae') IS DISTINCT FROM (p_challenge_age IS NOT NULL)
     OR (p_challenge_age IS NOT NULL AND p_challenge_age NOT BETWEEN 18 AND 40) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'invalid');
  END IF;
  -- R-13 (owner ruling 2026-11-09): an estimate never ends the check. A
  -- failed or uncertain estimate sends the person to the ID route, so a fae
  -- fail is never recorded (far below 18 is record_dating_age_far_below's).
  IF p_age_method = 'fae' AND p_age_result = 'fail' THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'invalid');
  END IF;
  IF p_age_method = 'fae' AND p_age_result = 'pass' AND p_challenge_age < 25 THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'challenge_too_low');
  END IF;
  FOR v_try IN 1..3 LOOP
    BEGIN
      PERFORM private.dating_lock_setup(p_user);
      INSERT INTO public.dating_age_verifications AS v (user_id, age_method, age_result, challenge_age, age_vendor, age_decided_at)
      VALUES (p_user, p_age_method, p_age_result, p_challenge_age, p_vendor, now())
      ON CONFLICT (user_id) DO UPDATE
        SET age_method = EXCLUDED.age_method, age_result = EXCLUDED.age_result,
            challenge_age = EXCLUDED.challenge_age, age_vendor = EXCLUDED.age_vendor,
            age_decided_at = EXCLUDED.age_decided_at,
            revoked_at = CASE WHEN EXCLUDED.age_result = 'pass' THEN NULL ELSE v.revoked_at END,
            revoke_reason = CASE WHEN EXCLUDED.age_result = 'pass' THEN NULL ELSE v.revoke_reason END,
            updated_at = now();
      PERFORM private.bump_metric_internal('dating.verification.age_' || p_age_method || '_' || p_age_result);
      RETURN jsonb_build_object('ok', true);
    EXCEPTION WHEN deadlock_detected OR lock_not_available OR serialization_failure THEN
      IF v_try = 3 THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'busy');
      END IF;
    END;
  END LOOP;
  RETURN jsonb_build_object('ok', false, 'reason', 'busy');
END;
$$;

-- 14. Far below 18 for a declared adult (§3.3.2, §6.3, R8): the vendor's
--     high-confidence under-18 band, or an ID whose date of birth is under
--     18. The age check fails, every match closes as age_review, and Spec
--     1's account hold is placed with all three arguments (I-7), the
--     session id as its reference. The only Dating caller of
--     place_account_hold (a contract scans for others). Once per session.
CREATE OR REPLACE FUNCTION public.record_dating_age_far_below(p_user uuid, p_session uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
SET lock_timeout = '2s'
AS $$
DECLARE
  v_row public.dating_verification_sessions;
  v_try integer;
BEGIN
  IF p_user IS NULL OR p_session IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'invalid');
  END IF;
  FOR v_try IN 1..3 LOOP
    BEGIN
      PERFORM private.dating_lock_setup(p_user);
      SELECT * INTO v_row FROM public.dating_verification_sessions AS s
       WHERE s.id = p_session AND s.user_id = p_user FOR UPDATE;
      IF NOT FOUND OR v_row.step NOT IN ('liveness', 'id') THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'session_unavailable');
      END IF;
      IF v_row.outcome = 'far_below' THEN
        RETURN jsonb_build_object('ok', true, 'replayed', true);
      END IF;
      PERFORM public.invalidate_dating_for_user(p_user, 'age_review');
      INSERT INTO public.dating_age_verifications AS v (user_id, age_method, age_result, challenge_age, age_vendor, age_decided_at)
      VALUES (p_user, CASE WHEN v_row.step = 'id' THEN 'id' ELSE 'fae' END, 'fail',
              CASE WHEN v_row.step = 'id' THEN NULL ELSE 25 END, coalesce(v_row.vendor, 'unknown'), now())
      ON CONFLICT (user_id) DO UPDATE
        SET age_method = EXCLUDED.age_method, age_result = 'fail', challenge_age = EXCLUDED.challenge_age,
            age_vendor = EXCLUDED.age_vendor, age_decided_at = EXCLUDED.age_decided_at, updated_at = now();
      PERFORM public.place_account_hold(p_user, 'age_review', p_session::text);
      UPDATE public.dating_verification_sessions AS s
         SET state = 'failed', outcome = 'far_below', outcome_position = NULL, updated_at = now()
       WHERE s.id = p_session;
      PERFORM private.bump_metric_internal('dating.verification.far_below');
      RETURN jsonb_build_object('ok', true, 'replayed', false);
    EXCEPTION WHEN deadlock_detected OR lock_not_available OR serialization_failure THEN
      IF v_try = 3 THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'busy');
      END IF;
    END;
  END LOOP;
  RETURN jsonb_build_object('ok', false, 'reason', 'busy');
END;
$$;

-- 15. The ID's date of birth against the one the person declared (§3.3.2,
--     Spec 1 account_birthdates): match, mismatch, minor (under 18) or
--     unknown (none declared). Compared and forgotten: nothing is stored.
CREATE OR REPLACE FUNCTION public.check_dating_id_birth_date(p_user uuid, p_dob date)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT CASE
    WHEN p_user IS NULL OR p_dob IS NULL OR p_dob > current_date THEN 'unknown'
    WHEN p_dob > (current_date - interval '18 years')::date THEN 'minor'
    WHEN b.birth_date IS NULL THEN 'unknown'
    WHEN b.birth_date = p_dob THEN 'match'
    ELSE 'mismatch'
  END
    FROM (SELECT 1) AS one
    LEFT JOIN public.account_birthdates AS b ON b.user_id = p_user;
$$;

-- 16. The human route (§3.3.3): the two photos land under an open human
--     session's paths (the storage policy's predicate), then the person
--     submits; a reviewer decides identity only (pass, fail, ask for ID;
--     never age). Until W7b's console, from supabase/sql/dev_dating_review_decide.sql.
--     The photos are queued for deletion at the decision (or by the sweep
--     at 72 hours).
CREATE OR REPLACE FUNCTION public.dating_review_upload_open(p_name text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT coalesce(p_name ~ '^[0-9a-f-]{36}/[12]\.jpg$', false) AND EXISTS (
    SELECT 1 FROM public.dating_verification_sessions AS s
     WHERE s.id::text = split_part(p_name, '/', 1) AND s.user_id = auth.uid()
       AND s.step = 'human' AND s.state = 'started' AND s.expires_at > now());
$$;

CREATE OR REPLACE FUNCTION public.submit_dating_human_review(p_user uuid, p_session uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
SET lock_timeout = '2s'
AS $$
DECLARE
  v_row public.dating_verification_sessions;
BEGIN
  IF p_user IS NULL OR p_session IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'invalid');
  END IF;
  PERFORM private.dating_lock_setup(p_user); -- the shared lock order: the person first, then rows
  SELECT * INTO v_row FROM public.dating_verification_sessions AS s
   WHERE s.id = p_session AND s.user_id = p_user AND s.step = 'human' FOR UPDATE;
  IF NOT FOUND OR v_row.state <> 'started' OR v_row.expires_at <= now() THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'session_unavailable');
  END IF;
  IF (SELECT count(DISTINCT o.name) FROM storage.objects AS o
       WHERE o.bucket_id = 'dating-verification-review'
         AND o.name IN (p_session::text || '/1.jpg', p_session::text || '/2.jpg')) < 2 THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'photos_missing');
  END IF;
  UPDATE public.dating_verification_sessions AS s
     SET state = 'awaiting_review', outcome = 'human_pending', updated_at = now()
   WHERE s.id = p_session;
  UPDATE public.dating_profiles AS p SET verification_state = 'needs_review'
   WHERE p.user_id = p_user AND p.verification_state IS DISTINCT FROM 'verified';
  PERFORM private.bump_metric_internal('dating.verification.human_submitted');
  RETURN jsonb_build_object('ok', true);
EXCEPTION WHEN lock_not_available OR deadlock_detected OR serialization_failure THEN
  RETURN jsonb_build_object('ok', false, 'reason', 'busy');
END;
$$;

CREATE OR REPLACE FUNCTION public.decide_dating_human_review(p_session uuid, p_outcome text, p_decided_by uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
SET lock_timeout = '2s'
AS $$
DECLARE
  v_row public.dating_verification_sessions;
  v_user uuid;
  v jsonb;
BEGIN
  IF p_session IS NULL OR p_decided_by IS NULL OR (p_outcome IN ('pass', 'fail', 'ask_for_id')) IS NOT TRUE THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'invalid');
  END IF;
  SELECT s.user_id INTO v_user FROM public.dating_verification_sessions AS s WHERE s.id = p_session;
  IF v_user IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'session_unavailable');
  END IF;
  PERFORM private.dating_lock_setup(v_user); -- the shared lock order: the person first, then rows
  SELECT * INTO v_row FROM public.dating_verification_sessions AS s
   WHERE s.id = p_session AND s.step = 'human' AND s.state = 'awaiting_review' FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'session_unavailable');
  END IF;
  IF p_outcome IN ('pass', 'fail') THEN
    v := public.record_dating_identity_check(v_row.user_id, 'human_gesture', p_outcome, 'attune', p_decided_by);
    IF (v ->> 'ok')::boolean IS NOT TRUE THEN
      RETURN v;
    END IF;
  ELSE
    UPDATE public.dating_profiles AS p SET verification_state = 'unverified'
     WHERE p.user_id = v_row.user_id AND p.verification_state = 'needs_review';
  END IF;
  UPDATE public.dating_verification_sessions AS s
     SET state = CASE WHEN p_outcome = 'pass' THEN 'passed' ELSE 'failed' END,
         outcome = CASE p_outcome WHEN 'pass' THEN 'verified' WHEN 'fail' THEN 'identity_failed' ELSE 'ask_for_id' END,
         updated_at = now()
   WHERE s.id = p_session;
  PERFORM public.queue_media_deletion('dating-verification-review', p_session::text || '/' || n || '.jpg')
     FROM unnest(ARRAY['1', '2']) AS n;
  RETURN jsonb_build_object('ok', true);
EXCEPTION WHEN lock_not_available OR deadlock_detected OR serialization_failure THEN
  RETURN jsonb_build_object('ok', false, 'reason', 'busy');
END;
$$;

-- 17. Revocation takes a reason (§4.10); its trigger pauses and closes.
DROP FUNCTION IF EXISTS public.revoke_dating_age_verification(uuid);
CREATE OR REPLACE FUNCTION public.revoke_dating_age_verification(p_user uuid, p_reason text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
SET lock_timeout = '2s'
AS $$
BEGIN
  IF p_user IS NULL OR coalesce(p_reason ~ '^[a-z0-9_]{1,40}$', false) IS NOT TRUE THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'invalid');
  END IF;
  PERFORM private.dating_lock_setup(p_user);
  UPDATE public.dating_age_verifications AS v
     SET revoked_at = coalesce(v.revoked_at, now()), revoke_reason = coalesce(v.revoke_reason, p_reason), updated_at = now()
   WHERE v.user_id = p_user;
  RETURN jsonb_build_object('ok', FOUND);
EXCEPTION WHEN lock_not_available OR deadlock_detected OR serialization_failure THEN
  RETURN jsonb_build_object('ok', false, 'reason', 'busy');
END;
$$;

-- 18. The v1 writers go (§4.10: replaced by the two recorders above).
DROP FUNCTION IF EXISTS public.verify_dating_age(uuid, date, text, uuid, timestamptz);
DROP FUNCTION IF EXISTS public.resolve_dating_verification_review(uuid, text);

-- 19. The device a request comes from (§3.3.4): the SHA-256 (hex) of the
--     x-attune-device header when it is 32 lowercase hex characters, else
--     NULL. W4b's trusted-device check reads it; nothing stores the id.
CREATE OR REPLACE FUNCTION private.dating_request_device_hash()
RETURNS text
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_id text;
BEGIN
  BEGIN
    v_id := nullif(current_setting('request.headers', true), '')::jsonb ->> 'x-attune-device';
  EXCEPTION WHEN OTHERS THEN
    RETURN NULL;
  END;
  IF v_id IS NULL OR v_id !~ '^[0-9a-f]{32}$' THEN
    RETURN NULL;
  END IF;
  RETURN encode(extensions.digest(v_id, 'sha256'), 'hex');
END;
$$;

-- 20. The person's own verification state (client RPC, §3.3.2): whether
--     the check can run, the two results ('review' while a person or the ID
--     vendor is checking), the open or the last session (no vendor
--     reference, no estimate, nothing about anyone else), the country's ID
--     documents and whether two photos are approved. On a device the
--     trusted-device check refuses, only the re-verification session on
--     this device (W4b) and nothing else.
CREATE OR REPLACE FUNCTION public.get_my_dating_verification()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user constant uuid := auth.uid();
  v_state jsonb;
  v_profile public.dating_profiles;
  v_session public.dating_verification_sessions;
  v_open boolean;
  v_country text;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  IF public.dating_require_trusted_device() IS NOT TRUE THEN
    SELECT * INTO v_session FROM public.dating_verification_sessions AS s
     WHERE s.user_id = v_user AND s.kind = 'reverify'
       AND s.device_hash IS NOT DISTINCT FROM private.dating_request_device_hash()
       AND s.created_at > now() - interval '1 day'
     ORDER BY s.created_at DESC LIMIT 1;
    RETURN jsonb_build_object('ok', true, 'device', 'untrusted',
      'available', private.dating_verification_available(),
      'session', CASE WHEN v_session.id IS NULL THEN NULL ELSE jsonb_build_object(
        'id', v_session.id, 'kind', v_session.kind, 'step', v_session.step, 'state', v_session.state,
        'attempts', v_session.attempts, 'outcome', v_session.outcome,
        'open', v_session.state IN ('started', 'awaiting_review') AND (v_session.state = 'awaiting_review' OR v_session.expires_at > now()),
        'gestures', to_jsonb(v_session.gestures)) END);
  END IF;
  v_state := private.dating_verification_state(v_user);
  SELECT * INTO v_profile FROM public.dating_profiles AS p WHERE p.user_id = v_user;
  SELECT * INTO v_session FROM public.dating_verification_sessions AS s
   WHERE s.user_id = v_user AND s.kind = 'activation' AND s.created_at > now() - interval '7 days'
   ORDER BY (s.state IN ('started', 'awaiting_review')) DESC, s.created_at DESC LIMIT 1;
  v_open := v_session.id IS NOT NULL AND (v_session.state = 'awaiting_review'
            OR (v_session.state = 'started' AND v_session.expires_at > now()));
  v_country := v_profile.country_code::text;
  RETURN jsonb_build_object(
    'ok', true,
    'device', 'trusted',
    'available', private.dating_verification_available(),
    'age', CASE WHEN v_state ->> 'age' IS NOT NULL THEN v_state ->> 'age'
                WHEN v_open AND v_session.step = 'id' AND v_session.state = 'awaiting_review' THEN 'review' END,
    'identity', CASE WHEN v_state ->> 'identity' = 'pass' AND v_profile.verification_state = 'verified' THEN 'pass'
                     WHEN v_open AND v_session.step = 'human' AND v_session.state = 'awaiting_review' THEN 'review'
                     WHEN v_state ->> 'identity' = 'fail' THEN 'fail' END,
    'session', CASE WHEN v_session.id IS NULL THEN NULL ELSE jsonb_build_object(
      'id', v_session.id, 'kind', v_session.kind, 'step', v_session.step, 'state', v_session.state,
      'attempts', v_session.attempts, 'outcome', v_session.outcome, 'position', v_session.outcome_position,
      'open', v_open, 'gestures', to_jsonb(v_session.gestures)) END,
    'id_documents', coalesce((SELECT jsonb_agg(jsonb_build_object('code', d ->> 'code', 'name_key', d ->> 'name_key'))
                                FROM jsonb_array_elements(coalesce((public.dating_country_config(v_country)).id_documents, '[]'::jsonb)) AS d), '[]'::jsonb),
    'photos_ready', (SELECT count(*) FROM public.dating_profile_photos AS f
                      WHERE f.user_id = v_user AND f.moderation_state = 'approved') >= 2);
END;
$$;

-- 21. The sweep (cron dating-verification-sweep, every 15 minutes; R-6):
--     an open video or ID session past its time expires; a human review
--     waiting past 72 hours expires (the person is asked again); every
--     human-review photo older than 72 hours is queued for deletion (the
--     objects of a deleted account included); sessions older than 30 days
--     are deleted (§4.8). Each step in its own block, counted.
CREATE OR REPLACE FUNCTION public.sweep_dating_verification_sessions()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
SET lock_timeout = '2s'
AS $$
DECLARE
  v_n integer := 0;
  v_k integer;
BEGIN
  BEGIN
    UPDATE public.dating_verification_sessions AS s SET state = 'expired', updated_at = now()
     WHERE s.state = 'started' AND s.expires_at <= now();
    GET DIAGNOSTICS v_k = ROW_COUNT; v_n := v_n + v_k;
    UPDATE public.dating_profiles AS p SET verification_state = 'unverified'
     WHERE p.verification_state = 'needs_review'
       AND EXISTS (SELECT 1 FROM public.dating_verification_sessions AS s
                    WHERE s.user_id = p.user_id AND s.step = 'human' AND s.state = 'awaiting_review'
                      AND s.created_at <= now() - interval '72 hours');
    UPDATE public.dating_verification_sessions AS s SET state = 'expired', updated_at = now()
     WHERE s.step = 'human' AND s.state = 'awaiting_review' AND s.created_at <= now() - interval '72 hours';
    GET DIAGNOSTICS v_k = ROW_COUNT; v_n := v_n + v_k;
  EXCEPTION WHEN OTHERS THEN
    PERFORM private.bump_metric_internal('dating.verification.sweep_failed');
  END;
  BEGIN
    PERFORM public.queue_media_deletion(o.bucket_id, o.name)
       FROM storage.objects AS o
      WHERE o.bucket_id = 'dating-verification-review' AND o.created_at <= now() - interval '72 hours';
  EXCEPTION WHEN OTHERS THEN
    PERFORM private.bump_metric_internal('dating.verification.sweep_failed');
  END;
  BEGIN
    DELETE FROM public.dating_verification_sessions AS s WHERE s.created_at <= now() - interval '30 days';
    GET DIAGNOSTICS v_k = ROW_COUNT; v_n := v_n + v_k;
  EXCEPTION WHEN OTHERS THEN
    PERFORM private.bump_metric_internal('dating.verification.sweep_failed');
  END;
  RETURN v_n;
END;
$$;
DO $unschedule$
BEGIN
  PERFORM cron.unschedule(j.jobid) FROM cron.job AS j WHERE j.jobname = 'dating-verification-sweep';
END $unschedule$;
SELECT cron.schedule('dating-verification-sweep', '*/15 * * * *',
  $cron$SELECT public.sweep_dating_verification_sessions()$cron$);

DROP POLICY IF EXISTS dating_verification_review_insert_by_session ON storage.objects;
CREATE POLICY dating_verification_review_insert_by_session ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'dating-verification-review' AND public.dating_review_upload_open(name));

-- 22. Re-created from their live bodies; every changed line is marked
--     -- Spec 2 W4a (Task 1 Step 8 diffs them).
```

Create `$D/mig_T1_tail.sql` with exactly (section 23, the revokes, and `COMMIT`):

```sql
-- 23. The server-only objects are closed in the migration itself (the twin
--     re-asserts them and opens the two client functions).
REVOKE ALL ON public.dating_verification_sessions FROM service_role;
REVOKE ALL ON FUNCTION private.dating_verification_mode() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_verification_available() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_verification_state(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_request_device_hash() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.sweep_dating_verification_sessions() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.get_dating_verification_config() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.begin_dating_verification(uuid, text, text, text, text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.get_dating_verification_session(uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.get_dating_verification_photos(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.set_dating_verification_ref(uuid, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.record_dating_liveness_attempt(uuid, boolean) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.finish_dating_verification_session(uuid, text, text, smallint) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.record_dating_identity_check(uuid, text, text, text, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.record_dating_age_assurance(uuid, text, text, smallint, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.record_dating_age_far_below(uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.check_dating_id_birth_date(uuid, date) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.submit_dating_human_review(uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.decide_dating_human_review(uuid, text, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.revoke_dating_age_verification(uuid, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.get_my_dating_verification() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.dating_review_upload_open(text) FROM PUBLIC, anon;

COMMIT;
```

Create `$D/build_mig_T1.py` with exactly:

```python
#!/usr/bin/env python3
# Spec 2 W4a: builds supabase/migrations/20261109100000_dating_v2_age_assurance.sql from
# mig_T1_head.sql (the new objects), the functions below re-created from
# their LIVE bodies (saved to before_w4a/ before the migration is applied) with
# only the lines marked "-- Spec 2 W4a" changed, and mig_T1_tail.sql (the
# revokes, COMMIT). Every anchor must occur exactly once.
import pathlib
D = pathlib.Path('.superpowers/sdd/2026-11-09-spec2-w4')
OUT = pathlib.Path('supabase/migrations/20261109100000_dating_v2_age_assurance.sql')

def live(sig):
    return (D / 'before_w4a' / f'{sig}.sql').read_text().rstrip('\n')

M = '-- Spec 2 W4a'
FNS = []

# 1. dating_age_gate_holds: the whole body.
FNS.append(('public.dating_age_gate_holds(uuid)', [(
"""  SELECT EXISTS (
    SELECT 1 FROM public.dating_age_verifications dav
    WHERE dav.user_id = p_user_id
      AND dav.revoked_at IS NULL
      AND (dav.expires_at IS NULL OR dav.expires_at > now())
      AND dav.birth_date <= current_date - interval '18 years'
  );""",
f"""  -- Spec 2 W4a (§3.3.1, §4.10): an age check passed (fae or id) and not
  -- Spec 2 W4a revoked, and Spec 1's declared age 18 or over; the record
  -- Spec 2 W4a keeps no date of birth, and a typed DOB alone never passes.
  SELECT EXISTS (
    SELECT 1 FROM public.dating_age_verifications dav
    WHERE dav.user_id = p_user_id
      AND dav.revoked_at IS NULL
      AND dav.age_result = 'pass' {M}
      AND dav.age_method IN ('fae', 'id') {M}
  ) AND coalesce(public.account_age(p_user_id) >= 18, false); {M}: NULL never passes""")]))

# 2. The verification trigger: the new shape (carry 1: a reason).
FNS.append(('public.enforce_dating_age_verification_change()', [(
"""  IF NEW.revoked_at IS NOT NULL
     OR NEW.birth_date > current_date - interval '18 years'
     OR (NEW.expires_at IS NOT NULL AND NEW.expires_at <= now()) THEN
    UPDATE public.dating_enrollments SET state='paused',paused_at=COALESCE(paused_at,now()),updated_at=now()
      WHERE user_id=NEW.user_id AND state='active';""",
f"""  -- Spec 2 W4a (§4.10, 04 G14): a revocation, or an age check that fails,
  -- Spec 2 W4a pauses the active enrolment with its own reason (carry 1;
  -- Spec 2 W4a resume and the app mirror it) and closes every match.
  IF (NEW.revoked_at IS NOT NULL AND (TG_OP = 'INSERT' OR OLD.revoked_at IS NULL)) {M}
     OR (NEW.age_result = 'fail' AND (TG_OP = 'INSERT' OR OLD.age_result IS DISTINCT FROM 'fail')) THEN {M}
    UPDATE public.dating_enrollments SET state='paused',paused_at=COALESCE(paused_at,now()), {M}
      pause_reason=COALESCE(pause_reason,'verification'),updated_at=now() {M} (carry 1)
      WHERE user_id=NEW.user_id AND state='active';""")]))

# 3. invalidate_dating_for_user: the two new closing reasons.
FNS.append(('public.invalidate_dating_for_user(uuid,text)', [(
"""  IF p_reason IN (
    'exit', 'dating_consent_withdrawn', 'account_restricted', 'profile_deleted'
  ) THEN
    UPDATE public.dating_matches
    SET state = 'closed',
        closed_at = COALESCE(closed_at, now())
    WHERE""",
f"""  IF p_reason IN (
    'exit', 'dating_consent_withdrawn', 'account_restricted', 'profile_deleted', {M}
    'age_review', 'age_verification_invalid' {M} (§6.3, §4.10): every match closes
  ) THEN
    UPDATE public.dating_matches
    SET state = 'closed',
        closed_at = COALESCE(closed_at, now()), {M}
        closed_reason = CASE WHEN p_reason IN ('age_review', 'age_verification_invalid') THEN p_reason ELSE closed_reason END, {M}
        evidence_until = CASE WHEN p_reason IN ('age_review', 'age_verification_invalid') {M}
                              THEN now() + interval '30 days' ELSE evidence_until END {M} (§4.8)
    WHERE""")]))

# 4. enforce_dating_restriction_change: an age_review closes as age_review.
FNS.append(('public.enforce_dating_restriction_change()', [(
"""    PERFORM public.invalidate_dating_for_user(NEW.user_id,'account_restricted');""",
f"""    PERFORM public.invalidate_dating_for_user(NEW.user_id, {M} (§6.3): an underage_risk age_review closes every match as age_review
      CASE WHEN NEW.restriction_type = 'age_review' THEN 'age_review' ELSE 'account_restricted' END); {M}""")]))

# 5. The hard filters read the declared age (the v1 birth_date column is gone).
FNS.append(('public.dating_pair_passes_hard_filters(uuid,uuid)', [(
"""  -- Age from the verified birth date, never a client-supplied integer.
  SELECT date_part('year', age(current_date, birth_date))::int INTO v_age_a
  FROM public.dating_age_verifications
  WHERE user_id = p_a AND revoked_at IS NULL;
  SELECT date_part('year', age(current_date, birth_date))::int INTO v_age_b
  FROM public.dating_age_verifications
  WHERE user_id = p_b AND revoked_at IS NULL;""",
f"""  -- Spec 2 W4a (§1.4): Spec 1's declared age, counted only while the age
  -- Spec 2 W4a check holds; never a client-supplied integer, never a stored DOB.
  v_age_a := CASE WHEN public.dating_age_gate_holds(p_a) THEN public.account_age(p_a) END; {M}
  v_age_b := CASE WHEN public.dating_age_gate_holds(p_b) THEN public.account_age(p_b) END; {M}""")]))

# 6. resume_dating_mode: the verification pause holds while its cause stands.
FNS.append(('public.resume_dating_mode(text)', [(
"""     OR (v_enrollment.pause_reason IS NOT DISTINCT FROM 'gates' -- Spec 2 W2 (final review M-3): the cron's pause holds while its cause stands""",
f"""     OR (coalesce(v_enrollment.pause_reason IN ('gates', 'verification'), false) {M} (carry 1): the cron's and a revocation's pause hold while their cause stands""")]))

# 7. get_dating_home: 'verifying' (§3.1) while a person or the ID vendor checks.
FNS.append(('public.get_dating_home()', [(
"""  RETURN coalesce(v_has, '{"has_data": true}') || jsonb_build_object('state', 'setup_in_progress', 'next_step', private.dating_next_step(v_user), -- Spec 2 W3a (C-2)""",
f"""  IF private.dating_next_step(v_user) IS NOT DISTINCT FROM 'verify' {M} (§3.1): a person or the ID vendor is checking
     AND EXISTS (SELECT 1 FROM public.dating_verification_sessions AS vs {M}
                  WHERE vs.user_id = v_user AND vs.kind = 'activation' AND vs.state = 'awaiting_review') THEN {M}
    RETURN coalesce(v_has, '{{"has_data": true}}') || jsonb_build_object('state', 'verifying', 'next_step', 'verify'); {M}
  END IF; {M}
  RETURN coalesce(v_has, '{{"has_data": true}}') || jsonb_build_object('state', 'setup_in_progress', 'next_step', private.dating_next_step(v_user), -- Spec 2 W3a (C-2)""")]))

# 8. Exit: sessions and their photos go, and the identity result (it
#    covered the photos exit deletes); the age result stays (§4.8).
FNS.append(('private.dating_exit_internal(uuid,boolean)', [(
"""  -- Conversations close for both and stay sealed for the evidence window.""",
f"""  -- Spec 2 W4a: the verification sessions go, a human review's photos with
  -- Spec 2 W4a them (queued, as every Dating object), and the identity
  -- Spec 2 W4a result, which covered the photos deleted above; the age
  -- Spec 2 W4a result stays while the account exists (§4.8).
  PERFORM public.queue_media_deletion('dating-verification-review', o.name) {M}
     FROM storage.objects AS o {M}
    WHERE o.bucket_id = 'dating-verification-review' {M}
      AND split_part(o.name, '/', 1) IN (SELECT vs.id::text FROM public.dating_verification_sessions AS vs {M}
                                          WHERE vs.user_id = p_user); {M}
  DELETE FROM public.dating_verification_sessions AS vs WHERE vs.user_id = p_user; {M}
  UPDATE public.dating_age_verifications AS av {M}
     SET identity_method = NULL, identity_result = NULL, identity_vendor = NULL, {M}
         identity_decided_at = NULL, decided_by = NULL, updated_at = now() {M}
   WHERE av.user_id = p_user AND av.identity_result IS NOT NULL; {M}
  -- Conversations close for both and stay sealed for the evidence window.""")]))

# 9. Health (§4.10): the mode and the review backlog.
FNS.append(('public.get_dating_operational_health()', [(
"""    'enabled_countries',to_jsonb(private.dating_open_countries()), -- Spec 2 W1d""",
f"""    'enabled_countries',to_jsonb(private.dating_open_countries()), -- Spec 2 W1d
    'age_assurance_mode',private.dating_verification_mode(), {M}
    'verification_awaiting_review',(SELECT count(*) FROM public.dating_verification_sessions WHERE state='awaiting_review'), {M}
    'verification_oldest_waiting_hours',(SELECT floor(extract(epoch FROM now() - min(created_at)) / 3600)::int {M}
                                           FROM public.dating_verification_sessions WHERE state='awaiting_review'), {M}""")]))

parts = []
for sig, pairs in FNS:
    body = live(sig)
    for old, new in pairs:
        n = body.count(old)
        assert n == 1, f'{sig}: anchor occurs {n} times: {old[:60]!r}'
        body = body.replace(old, new)
    parts.append(body + ';\n')
OUT.write_text((D / 'mig_T1_head.sql').read_text() + '\n'.join(parts) + '\n' + (D / 'mig_T1_tail.sql').read_text())
print(f'{OUT}: {len(FNS)} functions re-created')
```

Create `supabase/migrations/20261109100010_dating_v2_age_assurance_grants.sql` with exactly:

```sql
-- Spec 2 W4a: grants for 20261109100000_dating_v2_age_assurance.sql. The
-- session table is no API role's, the service role included (the edge
-- function goes through the service functions only). The status read and
-- the human-review upload predicate are the app's (the predicate runs inside
-- the storage policy as the signed-in role). The session, result and review
-- writers, the config read and the far-below path are the service role's
-- (dating-verification; the review decision until W7b's console). The
-- helpers and the sweep are the database's own. The re-created functions
-- keep their grants.
BEGIN;
SET LOCAL lock_timeout = '5s';
REVOKE ALL ON public.dating_verification_sessions FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_verification_mode() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_verification_available() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_verification_state(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_request_device_hash() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.sweep_dating_verification_sessions() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.get_my_dating_verification() FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.get_my_dating_verification() TO authenticated;
REVOKE ALL ON FUNCTION public.dating_review_upload_open(text) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.dating_review_upload_open(text) TO authenticated;
REVOKE ALL ON FUNCTION public.get_dating_verification_config() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.begin_dating_verification(uuid, text, text, text, text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.get_dating_verification_session(uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.get_dating_verification_photos(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.set_dating_verification_ref(uuid, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.record_dating_liveness_attempt(uuid, boolean) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.finish_dating_verification_session(uuid, text, text, smallint) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.record_dating_identity_check(uuid, text, text, text, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.record_dating_age_assurance(uuid, text, text, smallint, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.record_dating_age_far_below(uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.check_dating_id_birth_date(uuid, date) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.submit_dating_human_review(uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.decide_dating_human_review(uuid, text, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.revoke_dating_age_verification(uuid, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_dating_verification_config() TO service_role;
GRANT EXECUTE ON FUNCTION public.begin_dating_verification(uuid, text, text, text, text, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.get_dating_verification_session(uuid, uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.get_dating_verification_photos(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.set_dating_verification_ref(uuid, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.record_dating_liveness_attempt(uuid, boolean) TO service_role;
GRANT EXECUTE ON FUNCTION public.finish_dating_verification_session(uuid, text, text, smallint) TO service_role;
GRANT EXECUTE ON FUNCTION public.record_dating_identity_check(uuid, text, text, text, uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.record_dating_age_assurance(uuid, text, text, smallint, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.record_dating_age_far_below(uuid, uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.check_dating_id_birth_date(uuid, date) TO service_role;
GRANT EXECUTE ON FUNCTION public.submit_dating_human_review(uuid, uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.decide_dating_human_review(uuid, text, uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.revoke_dating_age_verification(uuid, text) TO service_role;
COMMIT;
```

```bash
D=.superpowers/sdd/2026-11-09-spec2-w4
python3 -I $D/build_mig_T1.py
for f in supabase/migrations/20261109100000_dating_v2_age_assurance.sql supabase/migrations/20261109100010_dating_v2_age_assurance_grants.sql; do
  for run in 1 2; do psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f $f > /dev/null; echo "$(basename $f) run $run exit=$?"; done
done
```

Expected: `supabase/migrations/20261109100000_dating_v2_age_assurance.sql: 9 functions re-created`; four `exit=0` lines, followed by the second runs' `NOTICE: … does not exist, skipping` / `already exists, skipping` lines (the `IF EXISTS` / `IF NOT EXISTS` guards; harmless). An `anchor occurs 0 times` means a live body changed since this plan was written: stop and report the function.

- [ ] **Step 8: Every re-created line is marked; the grants harness line**

```bash
D=.superpowers/sdd/2026-11-09-spec2-w4
python3 -I $D/marked_diff.py $D/before_w4a attune_spec3a 'Spec 2 W4a'; echo "exit=$?"
python3 -I $D/grants_line.py supabase/migrations/20261107170010_dating_v2_photos_grants.sql \
  "Spec 2 W4a: the verification sessions and the service writers are the service role's; the status read and the review-upload predicate are the app's." \
  supabase/migrations/20261109100010_dating_v2_age_assurance_grants.sql
```

Expected: nine lines each ending `OK` (some also print `; header: …`, the catalog's rebuilt header, which never fails), `exit=0`; `local_pg_grants.sql: one \i block added`.

- [ ] **Step 9: The existing contracts, the canary, the bucket policies and the dev script**

The W1–W3 contracts insert v1 age rows (a `birth_date`); they move to the v2 shape, and the setup contract's photo-readers pin gains the three W4a readers. The canary and the bucket-policy test learn the new table, functions, bucket and policy. The dev script turns the new flag on and sets the mode (R-7).

Create `$D/edit_tests_T1.py` with exactly:

```python
# Spec 2 W4a Task 1: the contracts' v1 age-verification fixtures and pins
# move to the v2 shape (no DOB in the record; R-2). Exact anchors only.
import pathlib, sys
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from anchor import edit

V2 = ("(user_id, age_method, age_result, age_vendor, age_decided_at, "
      "identity_method, identity_result, identity_vendor, identity_decided_at)")

def row(who):
    return f"({who}, 'id', 'pass', 'contract', now(), 'liveness_compare', 'pass', 'contract', now())"

def v1(who, dob, method):
    return (f"INSERT INTO public.dating_age_verifications (user_id, birth_date, verification_method, verified_at)\n"
            f"  VALUES ({who}, {dob}, '{method}', now());")

def v2(who):
    return f"INSERT INTO public.dating_age_verifications {V2} -- Spec 2 W4a (R-2)\n  VALUES {row(who)};"

T = 'supabase/tests/'
edit(T + 'dating_v2_home_contracts.sql', [
    (v1('v', "current_date - interval '30 years'", 'test'), v2('v'))], 'T1 home')
edit(T + 'dating_v2_identity_contracts.sql', [
    (v1('v_u', "current_date - interval '30 years'", 'w1d-contract') + "\n  INSERT INTO public.dating_profile_photos",
     v2('v_u') + "\n  INSERT INTO public.dating_profile_photos"),
    (v1('v_u', "current_date - interval '30 years'", 'w1d-contract') + "\n  IF NOT public.dating_profile_complete(v_u) THEN",
     v2('v_u') + "\n  IF NOT public.dating_profile_complete(v_u) THEN")], 'T1 identity')
edit(T + 'dating_v2_setup_contracts.sql', [
    (v1('v_u', "current_date - interval '30 years'", 'contract') + "\n  RETURN v_u;", v2('v_u') + "\n  RETURN v_u;"),
    (v1('v_u', "current_date - interval '30 years'", 'contract') + "\n  -- (B8 I-2: a plain profile, woman",
     v2('v_u') + "\n  -- (B8 I-2: a plain profile, woman"),
    (v1('v_young', "current_date - interval '30 years'", 'contract'), v2('v_young')),
    (v1('v_noprefs', "current_date - interval '30 years'", 'contract'), v2('v_noprefs')),
    (v1('v_none', "current_date - interval '30 years'", 'contract'), v2('v_none'))], 'T1 setup')
edit(T + 'dating_v2_setup_contracts.sql', [
    ("""  -- dead-lettered unscanned), the service role's. None returns a photo.
  IF v_got IS DISTINCT FROM 'private.dating_exit_internal(uuid, boolean):; private.dating_has_data(uuid):; private.dating_next_step(uuid):; private.dating_photo_bucket_limits():; public.check_dating_photo_strip""",
     """  -- dead-lettered unscanned), the service role's. None returns a photo.
  -- Spec 2 W4a: the verification session's start (two approved photos) and
  -- Spec 2 W4a the compare list (the person's own keys, the service role's:
  -- Spec 2 W4a dating-verification), and the person's own status read (a
  -- Spec 2 W4a count). None returns a photo to anyone else.
  IF v_got IS DISTINCT FROM 'private.dating_exit_internal(uuid, boolean):; private.dating_has_data(uuid):; private.dating_next_step(uuid):; private.dating_photo_bucket_limits():; public.begin_dating_verification(uuid, text, text, text, text, text):service_role; public.check_dating_photo_strip"""),
    ("public.get_dating_profile_preview():authenticated; public.insert_dating_profile_photo",
     "public.get_dating_profile_preview():authenticated; public.get_dating_verification_photos(uuid):service_role; public.get_my_dating_verification():authenticated; public.insert_dating_profile_photo")],
    'T1 setup photo readers')
edit(T + 'identity_foundation_contracts.sql', [
    (v1('v_c', "DATE '1990-01-01'", 'w1_contract'), v2('v_c'))], 'T1 identity foundation')
edit(T + 'dating_mode_contracts.sql', [
    ("""  INSERT INTO public.dating_age_verifications(user_id, birth_date, verification_method, verified_at)
  VALUES
    (a, current_date - interval '30 years', 'test', now()),
    (b, current_date - interval '31 years', 'test', now()),
    (d, current_date - interval '32 years', 'test', now())
  ON CONFLICT (user_id) DO UPDATE SET birth_date=EXCLUDED.birth_date;""",
     f"""  INSERT INTO public.dating_age_verifications {V2} -- Spec 2 W4a (R-2)
  VALUES
    {row('a')},
    {row('b')},
    {row('d')}
  ON CONFLICT (user_id) DO UPDATE SET age_result = EXCLUDED.age_result; -- Spec 2 W4a"""),
    ("""    INSERT INTO public.dating_age_verifications(user_id, birth_date, verification_method, verified_at)
    VALUES ('00000000-0000-0000-0000-00000000da01', current_date - interval '30 years', 'self', now());""",
     """    INSERT INTO public.dating_age_verifications (user_id, age_method, age_result, age_vendor, age_decided_at) -- Spec 2 W4a
    VALUES ('00000000-0000-0000-0000-00000000da01', 'id', 'pass', 'self', now()); -- Spec 2 W4a"""),
    ("""                WHERE user_id='00000000-0000-0000-0000-00000000da01' AND verification_method='self') THEN""",
     """                WHERE user_id='00000000-0000-0000-0000-00000000da01' AND age_vendor='self') THEN -- Spec 2 W4a"""),
    ("""  IF has_function_privilege('authenticated','public.verify_dating_age(uuid,date,text,uuid,timestamptz)','EXECUTE') THEN
    RAISE EXCEPTION 'authenticated can execute the age-verification writer';
  END IF;
  IF has_function_privilege('authenticated','public.revoke_dating_age_verification(uuid)','EXECUTE') THEN
    RAISE EXCEPTION 'authenticated can execute the age-verification revoker';
  END IF;
  IF NOT has_function_privilege('service_role','public.verify_dating_age(uuid,date,text,uuid,timestamptz)','EXECUTE') THEN""",
     """  IF has_function_privilege('authenticated','public.record_dating_age_assurance(uuid,text,text,smallint,text)','EXECUTE') THEN -- Spec 2 W4a
    RAISE EXCEPTION 'authenticated can execute the age-verification writer';
  END IF;
  IF has_function_privilege('authenticated','public.revoke_dating_age_verification(uuid,text)','EXECUTE') THEN -- Spec 2 W4a
    RAISE EXCEPTION 'authenticated can execute the age-verification revoker';
  END IF;
  IF NOT has_function_privilege('service_role','public.record_dating_age_assurance(uuid,text,text,smallint,text)','EXECUTE') THEN -- Spec 2 W4a""")],
    'T1 dating_mode')
edit(T + 'account_deletion_contracts.sql', [
    ("     OR EXISTS (SELECT 1 FROM public.dating_age_verifications WHERE verified_by = pg_temp.d())",
     "     OR EXISTS (SELECT 1 FROM public.dating_age_verifications WHERE decided_by = pg_temp.d()) -- Spec 2 W4a")],
    'T1 account deletion')
p = pathlib.Path(T + 'service_role_grants_test.sql')
s = p.read_text()
old = """                          'dating_gentle_wait_reflections')"""
new = """                          'dating_gentle_wait_reflections',
                          -- Spec 2 W4a: verification sessions hold vendor references;
                          -- dating-verification reaches them through service functions.
                          'dating_verification_sessions')"""
assert s.count(old) == 2, s.count(old)
p.write_text(s.replace(old, new))
print(f'{p}: 2 edit(s) (T1 service_role_grants)')
```

Create `$D/edit_canary_T1.py` with exactly:

```python
# Spec 2 W4a Task 1: the RLS canary's W4a rows and the bucket contract's
# second bucket. Exact anchors only.
import pathlib, sys
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from anchor import edit

CHECKS = """-- ---------------------------------------------------------------------
-- Checks (every batch adds its rows above this line)."""
edit('supabase/tests/dating_rls_canary.sql', [(CHECKS, """-- ---------------------------------------------------------------------
-- W4a (migration 1): the v1 age writers are gone (§4.10); the session
-- table is no API role's, the service role included (vendor references:
-- dating-verification reaches it through its service functions); the
-- status read and the human-review upload predicate are the app's (the
-- predicate runs inside the storage policy); the session, result, review
-- and far-below writers and the config read are the service role's; the
-- helpers and the sweep are the database's own.
DELETE FROM allowed_fn WHERE sig IN ('resolve_dating_verification_review(uuid,text)',
  'revoke_dating_age_verification(uuid)', 'verify_dating_age(uuid,date,text,uuid,timestamp with time zone)');
INSERT INTO allowed_rel (name, authenticated, service_dml) VALUES
  ('dating_verification_sessions', '', '');
INSERT INTO allowed_fn (sig, clients, service) VALUES
  ('get_my_dating_verification()', 'authenticated', ''),
  ('dating_review_upload_open(text)', 'authenticated', ''),
  ('get_dating_verification_config()', '', 'service_role'),
  ('begin_dating_verification(uuid,text,text,text,text,text)', '', 'service_role'),
  ('get_dating_verification_session(uuid,uuid)', '', 'service_role'),
  ('get_dating_verification_photos(uuid)', '', 'service_role'),
  ('set_dating_verification_ref(uuid,text)', '', 'service_role'),
  ('record_dating_liveness_attempt(uuid,boolean)', '', 'service_role'),
  ('finish_dating_verification_session(uuid,text,text,smallint)', '', 'service_role'),
  ('record_dating_identity_check(uuid,text,text,text,uuid)', '', 'service_role'),
  ('record_dating_age_assurance(uuid,text,text,smallint,text)', '', 'service_role'),
  ('record_dating_age_far_below(uuid,uuid)', '', 'service_role'),
  ('check_dating_id_birth_date(uuid,date)', '', 'service_role'),
  ('submit_dating_human_review(uuid,uuid)', '', 'service_role'),
  ('decide_dating_human_review(uuid,text,uuid)', '', 'service_role'),
  ('revoke_dating_age_verification(uuid,text)', '', 'service_role'),
  ('sweep_dating_verification_sessions()', '', ''),
  ('private.dating_verification_mode()', '', ''),
  ('private.dating_verification_available()', '', ''),
  ('private.dating_verification_state(uuid)', '', ''),
  ('private.dating_request_device_hash()', '', '');
""" + CHECKS)], 'T1 canary')

B = 'supabase/tests/storage_bucket_policies.sql'
edit(B, [
    ("""    'dating-profile-photos',
    'dating_profile_photos_insert_by_intent:INSERT:{authenticated};dating_profile_photos_select_owner:SELECT:{authenticated}');""",
     """    'dating-profile-photos',
    'dating_profile_photos_insert_by_intent:INSERT:{authenticated};dating_profile_photos_select_owner:SELECT:{authenticated}',
    -- Spec 2 W4a (§3.3.3, §4.5): the human route's photos: INSERT only, no client SELECT.
    'dating-verification-review',
    'dating_verification_review_insert_by_session:INSERT:{authenticated}');"""),
    ("""     AND p.policyname IN ('dating_profile_photos_insert_by_intent', 'dating_profile_photos_select_owner');""",
     """     AND p.policyname IN ('dating_profile_photos_insert_by_intent', 'dating_profile_photos_select_owner',
                          'dating_verification_review_insert_by_session'); -- Spec 2 W4a"""),
    ("""  IF v_got IS DISTINCT FROM 'dating_profile_photos_insert_by_intent=9d7dc3110cf2de1a35eb71135348cca5;'
                            'dating_profile_photos_select_owner=91e5256f5bc6ddfba83d30e571585244' THEN""",
     """  IF v_got IS DISTINCT FROM 'dating_profile_photos_insert_by_intent=9d7dc3110cf2de1a35eb71135348cca5;'
                            'dating_profile_photos_select_owner=91e5256f5bc6ddfba83d30e571585244;'
                            'dating_verification_review_insert_by_session=a1e02f11af65b060f7a9262f5dbc92d9' THEN -- Spec 2 W4a"""),
    ("""   WHERE n.nspname = 'public' AND p.proname IN ('dating_storage_intent_open', 'dating_storage_owns');
  IF v_got IS DISTINCT FROM 'dating_storage_intent_open=e06c835fdb2d5569b475e782c3052437;'
                            'dating_storage_owns=2c9a38d7244b6e2211bdcb298f1262e0' THEN""",
     """   WHERE n.nspname = 'public' AND p.proname IN ('dating_storage_intent_open', 'dating_storage_owns',
                                                'dating_review_upload_open'); -- Spec 2 W4a
  IF v_got IS DISTINCT FROM 'dating_review_upload_open=7465719589715a4603eab123b0179cf7;' -- Spec 2 W4a
                            'dating_storage_intent_open=e06c835fdb2d5569b475e782c3052437;'
                            'dating_storage_owns=2c9a38d7244b6e2211bdcb298f1262e0' THEN"""),
    ("""VALUES ('dating-profile-photos', 'spec2-w1-bucket-probe/photo.jpg', '5e2a0000-0000-0000-0000-0000000000f1');""",
     """VALUES ('dating-profile-photos', 'spec2-w1-bucket-probe/photo.jpg', '5e2a0000-0000-0000-0000-0000000000f1'),
       ('dating-verification-review', 'spec2-w4a-bucket-probe/1.jpg', '5e2a0000-0000-0000-0000-0000000000f1'); -- Spec 2 W4a"""),
    ("""    SELECT count(*) INTO v_n FROM storage.objects WHERE bucket_id = 'dating-profile-photos';""",
     """    SELECT count(*) INTO v_n FROM storage.objects WHERE bucket_id IN ('dating-profile-photos', 'dating-verification-review'); -- Spec 2 W4a"""),
], 'T1 buckets')
```

Create `$D/edit_dev_T1.py` with exactly:

```python
# Spec 2 W4a Task 1: the dev script turns dating_age_assurance on and
# sets the verification mode when none is set (§4.9 dev switch-on; R-7).
import pathlib, sys
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from anchor import edit

edit('supabase/sql/dev_enable_spec2_dating_flags.sql', [
    ("""    ('dating_same_gender_matching', true)
  ON CONFLICT (key) DO UPDATE SET enabled = EXCLUDED.enabled, updated_at = now();""",
     """    ('dating_same_gender_matching', true),
    ('dating_age_assurance', true) -- Spec 2 W4a
  ON CONFLICT (key) DO UPDATE SET enabled = EXCLUDED.enabled, updated_at = now();

  -- Spec 2 W4a (§3.3.5, §4.9): the verification mode, only when none is set
  -- Spec 2 W4a (an owner's 'live' or 'sandbox' is kept): 'fake' on a local
  -- Spec 2 W4a database (no project URL), 'sandbox' on the development
  -- Spec 2 W4a project. Vault, which app_setting reads first.
  IF public.app_setting('age_assurance_mode') IS NULL THEN -- Spec 2 W4a
    PERFORM vault.create_secret(CASE WHEN public.app_setting('supabase_url') IS NULL THEN 'fake' ELSE 'sandbox' END, -- Spec 2 W4a
                                'age_assurance_mode', 'Spec 2 W4a: dev verification mode'); -- Spec 2 W4a
  END IF; -- Spec 2 W4a"""),
    ("""-- I-15). Turns every Spec 2 Dating flag that exists ON, and opens Ghana and
-- the UK for Dating, on the development project only.""",
     """-- I-15). Turns every Spec 2 Dating flag that exists ON, and opens Ghana and
-- the UK for Dating, on the development project only. W4a: also the
-- verification mode (fake locally, sandbox on the project) when none is set.""")],
    'T1 dev script')
```

Create `supabase/sql/dev_dating_review_decide.sql` with exactly:

```sql
-- DEV / MANUAL TESTING ONLY. Never a migration (Spec 2 §8 W4a: until W7b's
-- console, a reviewer decides a human review here). Decides the identity
-- of one human-review session (pass, fail or ask_for_id; a person never
-- passes age), on the development project only (Spec 1's guard first;
-- env:not_development stops it). The two photos are queued for deletion
-- by the decision. Usage, from the repo root:
--   psql -v session=<session uuid> -v outcome=pass -v reviewer=<reviewer uuid> \
--        -f supabase/sql/dev_dating_review_decide.sql
\set ON_ERROR_STOP 1
SELECT private.assert_development_project();
SELECT public.decide_dating_human_review(:'session'::uuid, :'outcome', :'reviewer'::uuid) AS decided;
```

```bash
D=.superpowers/sdd/2026-11-09-spec2-w4
python3 -I $D/edit_tests_T1.py && python3 -I $D/edit_canary_T1.py && python3 -I $D/edit_dev_T1.py
```

Expected: one line per edited file (`…: N edit(s) (…)`), no `AssertionError`.

- [ ] **Step 10: The contract passes, and the whole suite**

```bash
D=.superpowers/sdd/2026-11-09-spec2-w4
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/dating_v2_verification_contracts.sql 2>&1 | grep -E 'ERROR|all held'
$D/suite.sh attune_spec3a > $D/sql-after-T1.txt; echo "$(grep -c '^PASS' $D/sql-after-T1.txt) PASS, $(grep -c '^FAIL' $D/sql-after-T1.txt) FAIL"
diff <(grep '^FAIL' $D/sql-baseline.txt) <(grep '^FAIL' $D/sql-after-T1.txt) && echo "no new FAIL"
```

Expected: `NOTICE:  dating_v2_verification_contracts: all held`; `160 PASS, 14 FAIL`; `no new FAIL`.

- [ ] **Step 11: Mutants (§7.5 mutant 8 and the W4a rules)**

Create `$D/mut_T1.py` with exactly:

```python
# Spec 2 W4a Task 1 mutants (mutate.py with the twin). Each must end in a
# CONTRACT VIOLATED line (or a named constraint) of
# dating_v2_verification_contracts.sql, never 'NO ERROR'.
FAE_CHECK = """  IF p_age_method = 'fae' AND p_age_result = 'pass' AND p_challenge_age < 25 THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'challenge_too_low');
  END IF;
"""
MUTS = {
 # §7.5 mutant 8: a fae pass with an estimate below 25 (both layers gone).
 'm8_fae_below_challenge': ('MULTI', [
    (FAE_CHECK, ''),
    ("  CHECK (age_method IS DISTINCT FROM 'fae' OR age_result IS DISTINCT FROM 'pass' OR coalesce(challenge_age, 0) >= 25);",
     "  CHECK (true);")]),
 'm8a_writer_only': (FAE_CHECK, ''),
 'gate_typed_dob': ("      AND dav.age_result = 'pass' -- Spec 2 W4a", ""),
 'gate_no_declared_age': ("coalesce(public.account_age(p_user_id) >= 18, false)", "coalesce(public.account_age(p_user_id) >= 18, true)"),
 'hold_two_args': ("      PERFORM public.place_account_hold(p_user, 'age_review', p_session::text);",
                   "      PERFORM public.place_account_hold(p_user, 'age_review');"),
 'far_below_no_replay_guard': ("      IF v_row.outcome = 'far_below' THEN", "      IF false THEN"),
 'revoke_null_reason': ("pause_reason=COALESCE(pause_reason,'verification'),updated_at=now()", "updated_at=now()"),
 'age_review_closes_as_restricted': ("      CASE WHEN NEW.restriction_type = 'age_review' THEN 'age_review' ELSE 'account_restricted' END); -- Spec 2 W4a",
                                     "      'account_restricted');"),
 'invalidate_no_age_reasons': ("    'age_review', 'age_verification_invalid' -- Spec 2 W4a (§6.3, §4.10): every match closes", "    'never'"),
 'resume_ignores_verification': ("coalesce(v_enrollment.pause_reason IN ('gates', 'verification'), false)",
                                 "coalesce(v_enrollment.pause_reason IN ('gates'), false)"),
 'begin_no_consent': ("      IF private.dating_consent_granted(p_user, 'biometric_verification') IS NOT TRUE THEN",
                      "      IF false THEN"),
 'begin_no_photos': ("               WHERE f.user_id = p_user AND f.moderation_state = 'approved') < 2 THEN",
                     "               WHERE f.user_id = p_user AND f.moderation_state = 'approved') < 1 THEN"),
 'begin_limit_after_ending': ('MULTI', [
    ("""      -- A refused start never ends the open session (the limit is read first).
      IF (SELECT count(*) FROM public.dating_verification_sessions AS s
           WHERE s.user_id = p_user AND s.created_at > now() - interval '1 day') >= 5 THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'rate_limited');
      END IF;
      IF v_has_open THEN
        UPDATE public.dating_verification_sessions AS s SET state = 'expired', updated_at = now() WHERE s.id = v_open.id;
      END IF;""",
     """      IF v_has_open THEN
        UPDATE public.dating_verification_sessions AS s SET state = 'expired', updated_at = now() WHERE s.id = v_open.id;
      END IF;
      IF (SELECT count(*) FROM public.dating_verification_sessions AS s
           WHERE s.user_id = p_user AND s.created_at > now() - interval '1 day') >= 5 THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'rate_limited');
      END IF;""")]),
 'fake_in_production': ("              AND private.attune_environment() IS DISTINCT FROM 'development');",
                        "              AND false);"),
 'upload_any_owner': ("     WHERE s.id::text = split_part(p_name, '/', 1) AND s.user_id = auth.uid()",
                      "     WHERE s.id::text = split_part(p_name, '/', 1)"),
 'submit_one_photo': ("         AND o.name IN (p_session::text || '/1.jpg', p_session::text || '/2.jpg')) < 2 THEN",
                      "         AND o.name IN (p_session::text || '/1.jpg', p_session::text || '/2.jpg')) < 1 THEN"),
 'decide_passes_age': ("""    v := public.record_dating_identity_check(v_row.user_id, 'human_gesture', p_outcome, 'attune', p_decided_by);""",
                       """    v := public.record_dating_identity_check(v_row.user_id, 'human_gesture', p_outcome, 'attune', p_decided_by);
    PERFORM public.record_dating_age_assurance(v_row.user_id, 'id', 'pass', NULL, 'attune');"""),
 'decide_keeps_photos': ("  PERFORM public.queue_media_deletion('dating-verification-review', p_session::text || '/' || n || '.jpg')\n     FROM unnest(ARRAY['1', '2']) AS n;",
                         ""),
 'status_leaks_ref': ("      'open', v_open, 'gestures', to_jsonb(v_session.gestures)) END,",
                      "      'open', v_open, 'gestures', to_jsonb(v_session.gestures), 'ref', v_session.vendor_session_ref) END,"),
 'status_untrusted_full': ("  IF public.dating_require_trusted_device() IS NOT TRUE THEN\n    SELECT * INTO v_session",
                           "  IF false THEN\n    SELECT * INTO v_session"),
 'home_no_verifying': ("  IF private.dating_next_step(v_user) IS NOT DISTINCT FROM 'verify' -- Spec 2 W4a",
                       "  IF false AND private.dating_next_step(v_user) IS NOT DISTINCT FROM 'verify' -- Spec 2 W4a"),
 'sweep_keeps_old_photos': ("      WHERE o.bucket_id = 'dating-verification-review' AND o.created_at <= now() - interval '72 hours';",
                            "      WHERE false;"),
 'exit_keeps_sessions': ("  DELETE FROM public.dating_verification_sessions AS vs WHERE vs.user_id = p_user; -- Spec 2 W4a", ""),
 'dob_minor_as_mismatch': ("    WHEN p_dob > (current_date - interval '18 years')::date THEN 'minor'\n", ""),
 # R-13 (owner ruling 2026-11-09): a failed estimate recorded as final.
 'fae_fail_recorded': ('''  IF p_age_method = 'fae' AND p_age_result = 'fail' THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'invalid');
  END IF;
''', ''),
}
```

```bash
D=.superpowers/sdd/2026-11-09-spec2-w4
python3 -I $D/mutate.py supabase/migrations/20261109100000_dating_v2_age_assurance.sql supabase/tests/dating_v2_verification_contracts.sql $D/mut_T1.py $D/mut supabase/migrations/20261109100010_dating_v2_age_assurance_grants.sql | tee $D/mut_T1.txt | grep -c 'NO ERROR'
wc -l < $D/mut_T1.txt
```

Expected: `0` (no survivor) and `25`. Every line but one reads `<name>: ERROR:  CONTRACT VIOLATED: …` (e.g. `m8_fae_below_challenge: … a fae pass at challenge age 24 was stored`, `hold_two_args: … the age_review hold does not name the session (three arguments, I-7)`, `begin_limit_after_ending: … a refused start ended the open session`, `fae_fail_recorded: … a failed estimate was recorded as an age result`, R-13); `m8a_writer_only` (the writer stops refusing a fae pass under 25) dies at the table's own CHECK `dating_age_verifications_fae_challenge_check`, the second wall mutant 8 needs. Quote each line in the report.

- [ ] **Step 12: The race script on an idle scratch copy**

```bash
D=.superpowers/sdd/2026-11-09-spec2-w4
dropdb --if-exists w4_race; createdb w4_race
pg_dump -s attune_spec3a | psql -X -q -d w4_race > /dev/null 2>&1
pg_dump -a -t public.metric_key_prefixes -t public.feature_flags -t public.country_safety_config -t private.dating_calling_codes attune_spec3a | psql -X -q -d w4_race > /dev/null 2>&1
scripts/concurrency/dating_kill_switch_races.sh w4_race > $D/race_T1.txt 2>&1; echo "exit=$?"; grep -c '^PASS' $D/race_T1.txt; grep -vc '^PASS' $D/race_T1.txt
dropdb w4_race
```

Expected: `exit=0`; `28`; `0`, and `dropdb --if-exists`'s `NOTICE: … does not exist, skipping` on a first run (W4a adds no case: no W4a writer takes a second lock; every one takes the setup lock first). Do not commit; record the tree in the report.

### Task 2: The `dating-verification` edge function and the vendor seam; `verify-dating-profile` removed (§3.3.1–§3.3.3, §3.3.5, §4.7, §6.8, §7.3, §7.5 mutant 8; R-8, R-9, R-12, R-13, R-22, R-27)

**Files:**
- Create: `supabase/functions/_shared/age_assurance/{types.ts, fake.ts, aws.ts, smile_id.ts, providers.ts, providers.test.ts}`, `supabase/functions/dating-verification/{handler.ts, index.ts, handler.test.ts}`, `$D/{denomut.py, edit_rekognition_T2.py, edit_ci_T2.py, mut_T2.py}`
- Modify: `supabase/functions/_shared/aws_rekognition.ts` (an optional `fetch` and the exported `rekognitionCall`), `.github/workflows/tests.yml` (the two test files on the Deno line), `supabase/config.toml` (`verify_jwt = true`)
- Delete: `supabase/functions/verify-dating-profile/`

**Interfaces:**
- Consumes: Task 1's service functions (each called through `deps.rpc`, never a table); the buckets `dating-profile-photos` (read) and `dating-verification-review` (written by the app, read here only by path for the reviewer, W7).
- Produces: `handleVerification(body, caller, deps)`; actions `start {scenario?}`, `complete {session_id}`, `start_id {document, scenario?}`, `complete_id {session_id}`, `human_start`, `submit_human {session_id}`; a start answers `{ok:true, session_id, vendor, vendor_session|vendor_job, resumed}` (the vendor's own session id, which the capture needs; never stored in the app) or, for the human route, `{ok:true, session_id, gestures, paths}`; a completion answers `{ok:true, outcome}` with `outcome` one of `verified`, `retry` (+ `attempts`), `another_way`, `needs_id` (an estimate below 25), `age_uncertain` (no estimate, or an unsure one; R-13), `photo_mismatch` (+ `position`), `far_below`, `id_pending`, `dob_mismatch`, `age_not_confirmed`, `human_pending`, `identity_failed`, `pending`; every refusal is `{ok:false, reason}` with a fixed code (`invalid`, `busy`, `unavailable`, `photos_required`, `session_unavailable`, `reverify_device`, `vendor_unavailable`, or the database's own: `not_eligible`, `consent_required`, `rate_limited`, `already_verified`, `age_not_confirmed`, `awaiting_review`).

- [ ] **Step 1: The shared types, the fake and the vendors**

`types.ts` holds the decision table (§3.3.1: liveness × estimate × photos; challenge age 25) and the fake's scenarios; `fake.ts` answers a scenario; `aws.ts` runs Face Liveness (no S3 output, no audit images, refuses `us-east-1`) and CompareFaces through `rekognitionCall`; `smile_id.ts` signs a document-verification job and reads `job_status` asking for no images; `providers.ts` picks the vendors per mode (estimation stays unconfigured outside `fake`, R-9).

Create `supabase/functions/_shared/age_assurance/types.ts` with exactly:

```ts
// supabase/functions/_shared/age_assurance/types.ts
// Spec 2 W4a (§3.3.5): the four vendor seams the dating-verification edge
// function runs through, each with a fake and a real implementation, and
// the one age decision. Nothing here logs, stores or returns an image, a
// reference frame, an estimate or a date of birth beyond the call that
// needs it (§3.3.5, DPIA biometric section).

export type Mode = "fake" | "sandbox" | "live";

/// What a liveness session answered: passed with the reference frame
/// (held in memory by the caller and cleared after use), failed, still
/// running, or expired.
export interface LivenessResult {
  status: "passed" | "failed" | "pending" | "expired";
  reference: Uint8Array | null;
}

export interface LivenessProvider {
  readonly name: string;
  /// A new vendor session for the capture view; its id goes to the device.
  createSession(opts: { scenario?: string }): Promise<{ ref: string }>;
  results(ref: string): Promise<LivenessResult>;
}

/// An estimate is never stored or logged: only ageDecision reads it.
export interface AgeEstimate {
  age: number;
  /// The vendor's under-18 band with high confidence (§6.3, R8).
  under18HighConfidence: boolean;
  /// The vendor's own "not sure" (low confidence, a poor frame): never a
  /// pass and never an ending (R-13).
  uncertain?: boolean;
}

export interface AgeEstimationProvider {
  readonly name: string;
  /// null when the vendor can't answer (or none is configured).
  estimate(frame: Uint8Array): Promise<AgeEstimate | null>;
}

/// An ID check (§3.3.1): the document is valid and its face matches the
/// person; its date of birth (YYYY-MM-DD) is compared on the server with
/// the declared one and then dropped.
export interface IdResult {
  status: "pending" | "pass" | "fail";
  dob: string | null;
  faceMatch: boolean | null;
}

export interface IdDocumentProvider {
  readonly name: string;
  startJob(opts: { document: string; country: string; sessionId: string; scenario?: string }): Promise<{ ref: string }>;
  result(ref: string): Promise<IdResult>;
}

export interface FaceMatchProvider {
  readonly name: string;
  /// Whether [target] (photo [index], 0-based) shows the face in [source].
  compare(source: Uint8Array, target: Uint8Array, index: number): Promise<boolean>;
}

export interface Providers {
  liveness: LivenessProvider;
  age: AgeEstimationProvider;
  id: IdDocumentProvider;
  faceMatch: FaceMatchProvider;
}

/// §3.3.1, §3.3.2: the challenge age is 25. A pass only at or above it;
/// the vendor's high-confidence under-18 band is "far below 18" (Spec 1's
/// account hold). R-13 (owner ruling 2026-11-09): an estimate never ends
/// the check. Below the challenge age it needs the ID route; no estimate,
/// or one the vendor isn't sure of, is uncertain (the ID route too).
export const CHALLENGE_AGE = 25;

export type AgeDecision = "pass" | "needs_id" | "uncertain" | "far_below";

export function ageDecision(estimate: AgeEstimate | null, challengeAge = CHALLENGE_AGE): AgeDecision {
  if (estimate === null || !Number.isFinite(estimate.age) || estimate.uncertain === true) return "uncertain";
  if (estimate.under18HighConfidence) return "far_below";
  if (challengeAge < CHALLENGE_AGE) return "needs_id";
  return estimate.age >= challengeAge ? "pass" : "needs_id";
}

/// The fixed scenarios the fake providers play (development only; the
/// handler refuses a scenario in any other mode).
export const FAKE_SCENARIOS = [
  "pass", "liveness_fail", "under_25", "uncertain", "far_below", "photo_mismatch", "vendor_down",
  "id_pass", "id_fail", "id_dob_mismatch", "id_minor", "id_pending",
] as const;
export type FakeScenario = typeof FAKE_SCENARIOS[number];

export function isFakeScenario(value: unknown): value is FakeScenario {
  return typeof value === "string" && (FAKE_SCENARIOS as readonly string[]).includes(value);
}
```

Create `supabase/functions/_shared/age_assurance/fake.ts` with exactly:

```ts
// supabase/functions/_shared/age_assurance/fake.ts
// Spec 2 W4a (§3.3.5): the fake providers, for development and tests only
// (age_assurance_mode 'fake'; refused in production mode by the handler
// and by private.dating_verification_available()). Each plays the
// scenario named in its session reference (fake:<scenario>:<id>), so a
// tester can walk every outcome of §3.3.2 on a development build. They see
// no image: the "reference frame" is the scenario's own bytes.
import {
  type AgeEstimate,
  type AgeEstimationProvider,
  type FaceMatchProvider,
  type FakeScenario,
  type IdDocumentProvider,
  type IdResult,
  isFakeScenario,
  type LivenessProvider,
  type LivenessResult,
  type Providers,
} from "./types.ts";

const FRAME_PREFIX = "fake-frame:";

/// The date-of-birth answer the fake ID gives for id_pass: "the date the
/// person declared". Only the fake can say it; the handler takes it as a
/// match without reading any date (no DOB ever leaves the database).
export const FAKE_DECLARED_DOB = "declared";

function scenarioOf(ref: string): FakeScenario {
  const s = ref.split(":")[1];
  return isFakeScenario(s) ? s : "pass";
}

function frameScenario(frame: Uint8Array): FakeScenario {
  const text = new TextDecoder().decode(frame);
  const s = text.startsWith(FRAME_PREFIX) ? text.slice(FRAME_PREFIX.length) : "";
  return isFakeScenario(s) ? s : "pass";
}

export const fakeLiveness: LivenessProvider = {
  name: "fake",
  createSession({ scenario }) {
    if (scenario === "vendor_down") return Promise.reject(new Error("fake_vendor_down"));
    return Promise.resolve({ ref: `fake:${isFakeScenario(scenario) ? scenario : "pass"}:${crypto.randomUUID()}` });
  },
  results(ref): Promise<LivenessResult> {
    const s = scenarioOf(ref);
    if (s === "liveness_fail") return Promise.resolve({ status: "failed", reference: null });
    return Promise.resolve({ status: "passed", reference: new TextEncoder().encode(FRAME_PREFIX + s) });
  },
};

export const fakeAgeEstimation: AgeEstimationProvider = {
  name: "fake",
  estimate(frame): Promise<AgeEstimate | null> {
    const s = frameScenario(frame);
    if (s === "under_25") return Promise.resolve({ age: 22, under18HighConfidence: false });
    if (s === "uncertain") return Promise.resolve({ age: 31, under18HighConfidence: false, uncertain: true });
    if (s === "far_below") return Promise.resolve({ age: 13, under18HighConfidence: true });
    return Promise.resolve({ age: 31, under18HighConfidence: false });
  },
};

export const fakeFaceMatch: FaceMatchProvider = {
  name: "fake",
  compare(source, _target, index) {
    return Promise.resolve(!(frameScenario(source) === "photo_mismatch" && index === 1));
  },
};

export const fakeIdDocument: IdDocumentProvider = {
  name: "fake",
  startJob({ scenario }) {
    return Promise.resolve({ ref: `fake:${isFakeScenario(scenario) ? scenario : "id_pass"}:${crypto.randomUUID()}` });
  },
  result(ref): Promise<IdResult> {
    const s = scenarioOf(ref);
    const sixteen = new Date(Date.now() - 16 * 365.25 * 864e5).toISOString().slice(0, 10);
    switch (s) {
      case "id_pending":
        return Promise.resolve({ status: "pending", dob: null, faceMatch: null });
      case "id_fail":
        return Promise.resolve({ status: "fail", dob: null, faceMatch: null });
      case "id_dob_mismatch":
        return Promise.resolve({ status: "pass", dob: "1970-01-01", faceMatch: true });
      case "id_minor":
        return Promise.resolve({ status: "pass", dob: sixteen, faceMatch: true });
      default:
        return Promise.resolve({ status: "pass", dob: FAKE_DECLARED_DOB, faceMatch: true });
    }
  },
};

export const fakeProviders: Providers = {
  liveness: fakeLiveness,
  age: fakeAgeEstimation,
  id: fakeIdDocument,
  faceMatch: fakeFaceMatch,
};
```

Create `supabase/functions/_shared/age_assurance/aws.ts` with exactly:

```ts
// supabase/functions/_shared/age_assurance/aws.ts
// Spec 2 W4a (§3.3.5): the real liveness and face-match providers, AWS
// Rekognition Face Liveness and CompareFaces, in the region the DPIA
// records (AWS_REKOGNITION_REGION; there is no default, and us-east-1 is
// refused: it is not used for UK or EU people). No S3 output is configured
// for liveness sessions and no audit images are kept (AuditImagesLimit 0):
// the reference frame comes back in the results call, is held in memory by
// the handler and cleared after the compare and the estimate.
import { compareFaces, rekognitionCall } from "../aws_rekognition.ts";
import type { FaceMatchProvider, LivenessProvider, LivenessResult } from "./types.ts";

export interface AwsConfig {
  accessKeyId: string;
  secretAccessKey: string;
  region: string;
  fetch?: typeof fetch;
}

/// A config the real providers accept, or null (missing, or us-east-1).
export function awsConfigFrom(env: (name: string) => string | undefined, f?: typeof fetch): AwsConfig | null {
  const accessKeyId = env("AWS_REKOGNITION_ACCESS_KEY_ID");
  const secretAccessKey = env("AWS_REKOGNITION_SECRET_ACCESS_KEY");
  const region = env("AWS_REKOGNITION_REGION");
  if (!accessKeyId || !secretAccessKey || !region || !/^[a-z]{2}-[a-z]+-\d$/.test(region) || region === "us-east-1") {
    return null;
  }
  return { accessKeyId, secretAccessKey, region, fetch: f };
}

/// A pass needs the vendor's confidence at or above this (percent).
export const LIVENESS_MIN_CONFIDENCE = 90;

function decodeBase64(b64: string): Uint8Array {
  const binary = atob(b64);
  const out = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) out[i] = binary.charCodeAt(i);
  return out;
}

export function awsLiveness(cfg: AwsConfig): LivenessProvider {
  return {
    name: "aws_rekognition",
    async createSession() {
      const r = await rekognitionCall({ ...cfg, target: "CreateFaceLivenessSession", payload: { Settings: { AuditImagesLimit: 0 } } });
      const id = r.SessionId;
      if (typeof id !== "string" || id.length === 0 || id.length > 200) throw new Error("liveness_bad_session");
      return { ref: id };
    },
    async results(ref): Promise<LivenessResult> {
      const r = await rekognitionCall({ ...cfg, target: "GetFaceLivenessSessionResults", payload: { SessionId: ref } });
      switch (r.Status) {
        case "SUCCEEDED": {
          const bytes = (r.ReferenceImage as { Bytes?: unknown } | undefined)?.Bytes;
          const confidence = typeof r.Confidence === "number" ? r.Confidence : 0;
          if (confidence < LIVENESS_MIN_CONFIDENCE || typeof bytes !== "string") return { status: "failed", reference: null };
          return { status: "passed", reference: decodeBase64(bytes) };
        }
        case "FAILED":
          return { status: "failed", reference: null };
        case "EXPIRED":
          return { status: "expired", reference: null };
        case "CREATED":
        case "IN_PROGRESS":
          return { status: "pending", reference: null };
        default:
          throw new Error("liveness_unknown_status");
      }
    },
  };
}

export function awsFaceMatch(cfg: AwsConfig): FaceMatchProvider {
  return {
    name: "aws_rekognition",
    async compare(source, target) {
      // Only the boolean leaves compareFaces' answer; the similarity is
      // never read, logged or stored.
      return (await compareFaces({ sourceImageBytes: source, targetImageBytes: target, ...cfg })).matched;
    },
  };
}
```

Create `supabase/functions/_shared/age_assurance/smile_id.ts` with exactly:

```ts
// supabase/functions/_shared/age_assurance/smile_id.ts
// Spec 2 W4a (§3.3.5): the real ID-document provider, Smile ID (Ghana
// Card, passports, UK driving licence). The device's Smile ID capture
// submits the document and selfie under the job this returns (no Attune
// user id is sent: the job is named after the verification session); the
// server reads the result with a signed job_status call. Only the outcome,
// the face-match answer and the document's date of birth are read (the
// date is compared with the declared one and dropped; never logged or
// stored). Images are never requested (image_links false). The response
// fields read here are checked against the vendor's sandbox at the W4 gate
// (owner checklist); anything not positively understood is "fail" or an
// error, never "pass".
import type { IdDocumentProvider, IdResult } from "./types.ts";

export interface SmileIdConfig {
  partnerId: string;
  apiKey: string;
  baseUrl: string;
  fetch?: typeof fetch;
  now?: () => Date;
}

export const SMILE_ID_SANDBOX = "https://testapi.smileidentity.com";
export const SMILE_ID_LIVE = "https://api.smileidentity.com";

export function smileIdConfigFrom(env: (name: string) => string | undefined, live: boolean, f?: typeof fetch): SmileIdConfig | null {
  const partnerId = env("SMILE_ID_PARTNER_ID");
  const apiKey = env("SMILE_ID_API_KEY");
  if (!partnerId || !apiKey || !/^[0-9]{1,12}$/.test(partnerId)) return null;
  return { partnerId, apiKey, baseUrl: live ? SMILE_ID_LIVE : SMILE_ID_SANDBOX, fetch: f };
}

/// base64(HMAC-SHA256(api key, timestamp + partner id + "sid_request")).
export async function smileIdSignature(apiKey: string, timestamp: string, partnerId: string): Promise<string> {
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(apiKey), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const sig = new Uint8Array(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(timestamp + partnerId + "sid_request")));
  let binary = "";
  for (const b of sig) binary += String.fromCharCode(b);
  return btoa(binary);
}

export function smileIdDocument(cfg: SmileIdConfig): IdDocumentProvider {
  return {
    name: "smile_id",
    startJob({ sessionId }) {
      // The session id names the job and the vendor-side user: nothing
      // that identifies the person in Attune leaves.
      return Promise.resolve({ ref: `attune_${sessionId}:${sessionId}` });
    },
    async result(ref): Promise<IdResult> {
      const [userId, jobId] = ref.split(":");
      if (!userId || !jobId) throw new Error("smile_id_bad_ref");
      const timestamp = (cfg.now ?? (() => new Date()))().toISOString();
      const body = {
        partner_id: cfg.partnerId,
        timestamp,
        signature: await smileIdSignature(cfg.apiKey, timestamp, cfg.partnerId),
        user_id: userId,
        job_id: jobId,
        image_links: false,
        history: false,
      };
      const res = await (cfg.fetch ?? fetch)(`${cfg.baseUrl}/v1/job_status`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(body),
        signal: AbortSignal.timeout(10000),
      });
      if (!res.ok) throw new Error(`smile_id_http_error_${res.status}`);
      const r = await res.json() as Record<string, unknown>;
      if (r.job_complete !== true) return { status: "pending", dob: null, faceMatch: null };
      const result = (r.result ?? {}) as Record<string, unknown>;
      const actions = (result.Actions ?? {}) as Record<string, unknown>;
      const documentOk = r.job_success === true && actions.Verify_Document === "Passed";
      if (!documentOk) return { status: "fail", dob: null, faceMatch: null };
      const compare = actions.Selfie_To_ID_Card_Compare ?? actions.Human_Review_Compare;
      const dob = typeof result.DOB === "string" && /^\d{4}-\d{2}-\d{2}$/.test(result.DOB) ? result.DOB : null;
      return { status: "pass", dob, faceMatch: compare === "Passed" || compare === "Completed" };
    },
  };
}
```

Create `supabase/functions/_shared/age_assurance/providers.ts` with exactly:

```ts
// supabase/functions/_shared/age_assurance/providers.ts
// Spec 2 W4a (§3.3.5): which providers a mode runs. fake: the fakes, and
// only in development (anything else refuses it). sandbox and live: AWS
// Face Liveness and CompareFaces (AWS_REKOGNITION_*), Smile ID
// (SMILE_ID_*, its sandbox host in sandbox mode) and the estimation
// vendor. R-9: the UK-recognised estimation vendor is not chosen yet
// (spec §10.1); until its adapter lands with the contract, estimation
// answers "unavailable", which never passes and sends the person to the ID
// route. A mode whose credentials are missing runs nothing (unavailable).
import { awsConfigFrom, awsFaceMatch, awsLiveness } from "./aws.ts";
import { fakeProviders } from "./fake.ts";
import { smileIdConfigFrom, smileIdDocument } from "./smile_id.ts";
import type { AgeEstimationProvider, Mode, Providers } from "./types.ts";

/// R-9: no vendor configured. Never a pass.
export const unconfiguredAgeEstimation: AgeEstimationProvider = {
  name: "unconfigured",
  estimate: () => Promise.resolve(null),
};

export function providersFor(
  mode: Mode,
  environment: string,
  env: (name: string) => string | undefined,
  f?: typeof fetch,
): Providers | null {
  if (mode === "fake") return environment === "development" ? fakeProviders : null;
  const aws = awsConfigFrom(env, f);
  const smile = smileIdConfigFrom(env, mode === "live", f);
  if (aws === null || smile === null) return null;
  return {
    liveness: awsLiveness(aws),
    age: unconfiguredAgeEstimation,
    id: smileIdDocument(smile),
    faceMatch: awsFaceMatch(aws),
  };
}
```

Create `$D/edit_rekognition_T2.py` with exactly:

```python
# Spec 2 W4a Task 2: _shared/aws_rekognition.ts takes an injected fetch
# (tests) and gains one signed call for the liveness API. compareFaces'
# behaviour is unchanged.
import pathlib, sys
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from anchor import edit
edit('supabase/functions/_shared/aws_rekognition.ts', [
    ("""  accessKeyId: string;
  secretAccessKey: string;
  region: string;
}): Promise<CompareFacesResult> {""",
     """  accessKeyId: string;
  secretAccessKey: string;
  region: string;
  /// Spec 2 W4a: tests pass their own; production uses the global fetch.
  fetch?: typeof fetch;
}): Promise<CompareFacesResult> {"""),
    ("""  const response = await fetch(`https://${host}/`, {
    method: "POST",
    headers,
    body,
    signal: AbortSignal.timeout(10000),
  });

  if (!response.ok) {
    throw new Error(`rekognition_http_error_${response.status}`);
  }

  const payload = await response.json();
  const matches""",
     """  const response = await (params.fetch ?? fetch)(`https://${host}/`, {
    method: "POST",
    headers,
    body,
    signal: AbortSignal.timeout(10000),
  });

  if (!response.ok) {
    throw new Error(`rekognition_http_error_${response.status}`);
  }

  const payload = await response.json();
  const matches"""),
    ("""async function signRequest(params: {""",
     """/// Spec 2 W4a (§3.3.5): one signed Rekognition call (the Face Liveness
/// session calls), signed as compareFaces is. A non-2xx answer throws
/// rekognition_http_error_<status>; nothing is logged.
export async function rekognitionCall(params: {
  target: string;
  payload: unknown;
  accessKeyId: string;
  secretAccessKey: string;
  region: string;
  fetch?: typeof fetch;
  timeoutMs?: number;
}): Promise<Record<string, unknown>> {
  const body = JSON.stringify(params.payload);
  const host = `rekognition.${params.region}.amazonaws.com`;
  const headers = await signRequest({
    method: "POST",
    host,
    region: params.region,
    service: "rekognition",
    target: `RekognitionService.${params.target}`,
    body,
    accessKeyId: params.accessKeyId,
    secretAccessKey: params.secretAccessKey,
  });
  const response = await (params.fetch ?? fetch)(`https://${host}/`, {
    method: "POST",
    headers,
    body,
    signal: AbortSignal.timeout(params.timeoutMs ?? 10000),
  });
  if (!response.ok) {
    throw new Error(`rekognition_http_error_${response.status}`);
  }
  return await response.json();
}

async function signRequest(params: {"""),
], 'T2 rekognition')
```

Create `supabase/functions/_shared/age_assurance/providers.test.ts` with exactly:

```ts
// Spec 2 W4a (§3.3.5): the real providers' requests and answers, with an
// injected fetch (no network): AWS Face Liveness keeps no audit images and
// no S3 output, needs its confidence and is refused in us-east-1; Smile ID
// signs its job_status call, asks for no images and reads only the
// outcome, the face match and the date; the provider choice per mode.
import { awsConfigFrom, awsLiveness, LIVENESS_MIN_CONFIDENCE } from "./aws.ts";
import { providersFor } from "./providers.ts";
import { SMILE_ID_SANDBOX, smileIdDocument, smileIdSignature } from "./smile_id.ts";

function eq(actual: unknown, expected: unknown, why = "") {
  const a = JSON.stringify(actual), e = JSON.stringify(expected);
  if (a !== e) throw new Error(`${why} expected ${e}, got ${a}`);
}

const env = (vars: Record<string, string>) => (name: string) => vars[name];
const AWS = {
  AWS_REKOGNITION_ACCESS_KEY_ID: "AKIDEXAMPLE",
  AWS_REKOGNITION_SECRET_ACCESS_KEY: "secret",
  AWS_REKOGNITION_REGION: "eu-west-2",
};
const SMILE = { SMILE_ID_PARTNER_ID: "1234", SMILE_ID_API_KEY: "test-api-key" };

function recorder(answer: unknown, status = 200) {
  const calls: Array<{ url: string; init: RequestInit }> = [];
  const f = ((url: string, init: RequestInit) => {
    calls.push({ url, init });
    return Promise.resolve(new Response(JSON.stringify(answer), { status }));
  }) as unknown as typeof fetch;
  return { calls, f };
}

Deno.test("AWS: no region, us-east-1 or a missing key runs nothing", () => {
  eq(awsConfigFrom(env({ ...AWS, AWS_REKOGNITION_REGION: "us-east-1" })), null);
  eq(awsConfigFrom(env({ ...AWS, AWS_REKOGNITION_REGION: "" })), null);
  eq(awsConfigFrom(env({ AWS_REKOGNITION_REGION: "eu-west-2" })), null);
  eq(awsConfigFrom(env(AWS))?.region, "eu-west-2");
});

Deno.test("AWS liveness: a session with no audit images and no S3 output", async () => {
  const r = recorder({ SessionId: "sess-1" });
  const p = awsLiveness({ ...awsConfigFrom(env(AWS))!, fetch: r.f });
  eq(await p.createSession({}), { ref: "sess-1" });
  const headers = r.calls[0].init.headers as Record<string, string>;
  eq([r.calls[0].url, headers["X-Amz-Target"]], ["https://rekognition.eu-west-2.amazonaws.com/", "RekognitionService.CreateFaceLivenessSession"]);
  eq(JSON.parse(String(r.calls[0].init.body)), { Settings: { AuditImagesLimit: 0 } });
});

Deno.test("AWS liveness: results by status and confidence; the frame decoded", async () => {
  const cases: Array<[unknown, string]> = [
    [{ Status: "SUCCEEDED", Confidence: LIVENESS_MIN_CONFIDENCE, ReferenceImage: { Bytes: btoa("JPEG") } }, "passed"],
    [{ Status: "SUCCEEDED", Confidence: LIVENESS_MIN_CONFIDENCE - 0.1, ReferenceImage: { Bytes: btoa("JPEG") } }, "failed"],
    [{ Status: "SUCCEEDED", Confidence: 99 }, "failed"],
    [{ Status: "FAILED" }, "failed"],
    [{ Status: "EXPIRED" }, "expired"],
    [{ Status: "IN_PROGRESS" }, "pending"],
  ];
  for (const [answer, want] of cases) {
    const r = recorder(answer);
    const res = await awsLiveness({ ...awsConfigFrom(env(AWS))!, fetch: r.f }).results("sess-1");
    eq(res.status, want, JSON.stringify(answer));
    if (want === "passed") eq(new TextDecoder().decode(res.reference!), "JPEG");
  }
  const bad = recorder({ Status: "SOMETHING_NEW" });
  let threw = false;
  try {
    await awsLiveness({ ...awsConfigFrom(env(AWS))!, fetch: bad.f }).results("sess-1");
  } catch {
    threw = true;
  }
  eq(threw, true, "an unknown status is an error, never a pass");
});

Deno.test("Smile ID: the signature and a job_status body asking for no images", async () => {
  eq(await smileIdSignature("test-api-key", "2026-11-09T10:00:00.000Z", "1234"), "Y/pgRyvB4c1kCAaMLc8beVj/dyY+TyQft30J1HHmiQA=");
  const r = recorder({ job_complete: false });
  const p = smileIdDocument({ partnerId: "1234", apiKey: "test-api-key", baseUrl: SMILE_ID_SANDBOX, fetch: r.f,
    now: () => new Date("2026-11-09T10:00:00.000Z") });
  const job = await p.startJob({ document: "ghana_card", country: "GH", sessionId: "s-1" });
  eq(job, { ref: "attune_s-1:s-1" });
  eq((await p.result(job.ref)).status, "pending");
  eq(r.calls[0].url, `${SMILE_ID_SANDBOX}/v1/job_status`);
  eq(JSON.parse(String(r.calls[0].init.body)), {
    partner_id: "1234", timestamp: "2026-11-09T10:00:00.000Z", signature: "Y/pgRyvB4c1kCAaMLc8beVj/dyY+TyQft30J1HHmiQA=",
    user_id: "attune_s-1", job_id: "s-1", image_links: false, history: false,
  });
});

Deno.test("Smile ID: only a passed document with a matching face is a pass", async () => {
  const done = (actions: Record<string, string>, dob: unknown = "1990-05-05", success = true) =>
    ({ job_complete: true, job_success: success, result: { Actions: actions, DOB: dob, FullName: "never read" } });
  const cases: Array<[unknown, unknown]> = [
    [done({ Verify_Document: "Passed", Selfie_To_ID_Card_Compare: "Passed" }), { status: "pass", dob: "1990-05-05", faceMatch: true }],
    [done({ Verify_Document: "Passed", Selfie_To_ID_Card_Compare: "Failed" }), { status: "pass", dob: "1990-05-05", faceMatch: false }],
    [done({ Verify_Document: "Failed" }), { status: "fail", dob: null, faceMatch: null }],
    [done({ Verify_Document: "Passed" }, "1990-05-05", false), { status: "fail", dob: null, faceMatch: null }],
    [done({ Verify_Document: "Passed", Human_Review_Compare: "Passed" }, "05/05/1990"), { status: "pass", dob: null, faceMatch: true }],
  ];
  for (const [answer, want] of cases) {
    const r = recorder(answer);
    eq(await smileIdDocument({ partnerId: "1234", apiKey: "k", baseUrl: SMILE_ID_SANDBOX, fetch: r.f }).result("u:j"), want);
  }
});

Deno.test("the providers per mode: sandbox and live need their keys; estimation stays unconfigured (R-9)", () => {
  eq(providersFor("sandbox", "development", env({})), null);
  eq(providersFor("live", "production", env(AWS)), null, "no Smile ID keys");
  const p = providersFor("live", "production", env({ ...AWS, ...SMILE }))!;
  eq([p.liveness.name, p.faceMatch.name, p.id.name, p.age.name], ["aws_rekognition", "aws_rekognition", "smile_id", "unconfigured"]);
});
```

```bash
python3 -I .superpowers/sdd/2026-11-09-spec2-w4/edit_rekognition_T2.py
cd supabase/functions && NO_COLOR=1 deno test --allow-read --allow-env --lock=../../.github/deno-w9.lock --frozen _shared/age_assurance/providers.test.ts 2>&1 | grep -E '^(ok|FAILED) \|'; cd ../..
```

Expected: `supabase/functions/_shared/aws_rekognition.ts: 3 edit(s) (T2 rekognition)`; `ok | 6 passed | 0 failed (…)`.

- [ ] **Step 2: Write the failing handler test**

Create `supabase/functions/dating-verification/handler.test.ts` with exactly:

```ts
// Spec 2 W4a (§3.3, §4.7, §7.3, §7.5 mutant 8): the dating-verification
// decision table over test providers (liveness pass/fail x estimate at or
// above / below 25 x photos match/mismatch, and the ID route's pass, fail,
// date-of-birth mismatch, minor and pending); the fakes' scenarios; a
// vendor that can't answer counts nothing; fake refused unless the
// environment reads development; nothing is ever logged (a console spy);
// the reference frame is cleared; only fixed codes leave; the device hash.
import { handleVerification, deviceHashOf, type VerificationDeps } from "./handler.ts";
import { fakeProviders } from "../_shared/age_assurance/fake.ts";
import { providersFor } from "../_shared/age_assurance/providers.ts";
import { ageDecision, type AgeEstimate, type Providers } from "../_shared/age_assurance/types.ts";

function eq(actual: unknown, expected: unknown, why = "") {
  const a = JSON.stringify(actual), e = JSON.stringify(expected);
  if (a !== e) throw new Error(`${why} expected ${e}, got ${a}`);
}

const SESSION = "11111111-2222-4333-8444-555555555555";
const DECLARED = "1990-05-05";

interface World {
  config: Record<string, unknown>;
  age: string | null;
  kind: string;
  step: string;
  state: string;
  outcome: string | null;
  ref: string | null;
  attempts: number;
  calls: Array<[string, Record<string, unknown> | undefined]>;
  photos: number;
}

function world(over: Partial<World> = {}): World {
  return {
    config: { available: true, mode: "fake", environment: "development", challenge_age: 25 },
    age: null, kind: "activation", step: "liveness", state: "started", outcome: null, ref: null, attempts: 0, calls: [], photos: 2,
    ...over,
  };
}

/// A database that answers like the W4a service functions, recording calls.
function deps(w: World, providers: Providers | null = fakeProviders, downloads: Uint8Array[] = []): VerificationDeps {
  return {
    rpc: (fn, args) => {
      w.calls.push([fn, args]);
      const ok = (data: unknown) => Promise.resolve({ data, error: null });
      if (fn === "record_dating_age_assurance") w.age = String(args?.p_age_result);
      switch (fn) {
        case "get_dating_verification_config":
          return ok(w.config);
        case "begin_dating_verification":
          if (w.age === "fail") return ok({ ok: false, reason: "age_not_confirmed" }); // R-13: a failed ID is final
          w.kind = String(args?.p_kind);
          w.step = String(args?.p_step);
          w.state = "started";
          return ok({ ok: true, session_id: SESSION, attempts: w.attempts, resumed: false, gestures: ["left_ear", "thumbs_up"] });
        case "set_dating_verification_ref":
          w.ref = String(args?.p_ref);
          return ok({ ok: true, reason: null });
        case "get_dating_verification_session":
          return ok({
            ok: true, session_id: SESSION, kind: w.kind, step: w.step, state: w.state, vendor: "fake",
            vendor_session_ref: w.ref, attempts: w.attempts, outcome: w.outcome, country: "GH", expired: false, age: w.age,
          });
        case "record_dating_liveness_attempt":
          if (args?.p_passed === true) return ok({ ok: true, attempts: w.attempts });
          w.attempts++;
          return ok({ ok: true, attempts: w.attempts, outcome: w.attempts >= 2 ? "another_way" : "retry" });
        case "get_dating_verification_photos":
          return ok(Array.from({ length: w.photos }, (_, i) => ({ position: i + 1, storage_key: `k${i + 1}` })));
        case "record_dating_identity_check":
        case "record_dating_age_assurance":
        case "record_dating_age_far_below":
        case "submit_dating_human_review":
          return ok({ ok: true });
        case "finish_dating_verification_session":
          w.state = String(args?.p_state);
          w.outcome = String(args?.p_outcome);
          return ok({ ok: true, reason: null });
        case "check_dating_id_birth_date": {
          const dob = String(args?.p_dob);
          const minor = Date.parse(dob) > Date.now() - 18 * 365.25 * 864e5;
          return ok(minor ? "minor" : dob === DECLARED ? "match" : "mismatch");
        }
        default:
          return Promise.resolve({ data: null, error: { code: "42883" } });
      }
    },
    download: (key) => {
      const b = new TextEncoder().encode(`photo:${key}`);
      downloads.push(b);
      return Promise.resolve(b);
    },
    providers: () => providers,
  };
}

const caller = { userId: "u-1", deviceHash: null };
const names = (w: World) => w.calls.map(([fn]) => fn);
const args = (w: World, fn: string) => w.calls.filter(([f]) => f === fn).map(([, a]) => a);

/// Test providers for the table: each axis set by hand.
function table(live: boolean, age: number | null, match: boolean, frames: Uint8Array[] = [], estimates: number[] = []): Providers {
  return {
    liveness: {
      name: "fake",
      createSession: () => Promise.resolve({ ref: "ref-1" }),
      results: () => {
        const frame = new TextEncoder().encode("FRAME-BYTES");
        frames.push(frame);
        return Promise.resolve(live ? { status: "passed", reference: frame } : { status: "failed", reference: null });
      },
    },
    age: {
      name: "fake",
      estimate: () => {
        estimates.push(1);
        return Promise.resolve(age === null ? null : { age, under18HighConfidence: false } as AgeEstimate);
      },
    },
    id: fakeProviders.id,
    faceMatch: { name: "fake", compare: (_s, _t, i) => Promise.resolve(match || i === 0) },
  };
}

Deno.test("the decision table: liveness x estimate x photos", async () => {
  for (const live of [true, false]) {
    for (const est of [25, 24, null]) {
      for (const match of [true, false]) {
        const w = world();
        const d = deps(w, table(live, est, match));
        const why = `live=${live} est=${est} match=${match}`;
        eq((await handleVerification({ action: "start" }, caller, d)).ok, true, why);
        const r = await handleVerification({ action: "complete", session_id: SESSION }, caller, d);
        const want = !live ? "retry" : !match ? "photo_mismatch" : est === null ? "age_uncertain" : est >= 25 ? "verified" : "needs_id";
        eq(r.outcome, want, why);
        const ages = args(w, "record_dating_age_assurance");
        eq(ages.length, want === "verified" ? 1 : 0, `${why} age records`);
        if (want === "verified") eq([ages[0]?.p_age_method, ages[0]?.p_age_result, ages[0]?.p_challenge_age], ["fae", "pass", 25], why);
        const ids = args(w, "record_dating_identity_check").map((a) => a?.p_result);
        eq(ids, !live ? [] : match ? ["pass"] : ["fail"], `${why} identity`);
        if (want === "photo_mismatch") eq(r.position, 2, why);
      }
    }
  }
});

Deno.test("mutant 8 (§7.5): an estimate below 25 never passes; 25 does; no estimate never does", () => {
  eq(ageDecision({ age: 24.9, under18HighConfidence: false }), "needs_id");
  eq(ageDecision({ age: 25, under18HighConfidence: false }), "pass");
  eq(ageDecision({ age: 40, under18HighConfidence: false }, 18), "needs_id", "a lower challenge age is refused");
  eq(ageDecision(null), "uncertain");
  eq(ageDecision({ age: Number.NaN, under18HighConfidence: false }), "uncertain");
  eq(ageDecision({ age: 31, under18HighConfidence: false, uncertain: true }), "uncertain", "the vendor isn't sure");
  eq(ageDecision({ age: 13, under18HighConfidence: true, uncertain: true }), "uncertain", "an unsure estimate never places a hold");
  eq(ageDecision({ age: 30, under18HighConfidence: true }), "far_below");
});

Deno.test("liveness fails twice: retry, then another way; nothing recorded", async () => {
  const w = world();
  const d = deps(w, table(false, 30, true));
  await handleVerification({ action: "start" }, caller, d);
  eq((await handleVerification({ action: "complete", session_id: SESSION }, caller, d)).outcome, "retry");
  eq((await handleVerification({ action: "complete", session_id: SESSION }, caller, d)).outcome, "another_way");
  eq(names(w).filter((n) => n.startsWith("record_dating_age") || n === "record_dating_identity_check"), []);
});

Deno.test("an age already passed: identity only, no estimate", async () => {
  const w = world({ age: "pass" });
  const estimates: number[] = [];
  const d = deps(w, table(true, 20, true, [], estimates));
  await handleVerification({ action: "start" }, caller, d);
  eq((await handleVerification({ action: "complete", session_id: SESSION }, caller, d)).outcome, "verified");
  eq(estimates.length, 0);
  eq(args(w, "record_dating_age_assurance").length, 0);
});

Deno.test("R-9: no estimation vendor (or one that throws) never passes: the ID route", async () => {
  for (const age of [null]) {
    const w = world();
    const d = deps(w, table(true, age, true));
    await handleVerification({ action: "start" }, caller, d);
    eq((await handleVerification({ action: "complete", session_id: SESSION }, caller, d)).outcome, "age_uncertain");
  }
  const w = world();
  const p = table(true, 30, true);
  p.age = { name: "fake", estimate: () => Promise.reject(new Error("timeout")) };
  const d = deps(w, p);
  await handleVerification({ action: "start" }, caller, d);
  eq((await handleVerification({ action: "complete", session_id: SESSION }, caller, d)).outcome, "age_uncertain");
  eq(args(w, "record_dating_age_assurance").length, 0);
});

Deno.test("the fakes' scenarios walk every video outcome", async () => {
  const want: Record<string, string> = {
    pass: "verified", liveness_fail: "retry", under_25: "needs_id", uncertain: "age_uncertain", far_below: "far_below",
    photo_mismatch: "photo_mismatch",
  };
  for (const [scenario, outcome] of Object.entries(want)) {
    const w = world();
    const d = deps(w);
    eq((await handleVerification({ action: "start", scenario }, caller, d)).ok, true, scenario);
    eq((await handleVerification({ action: "complete", session_id: SESSION }, caller, d)).outcome, outcome, scenario);
    if (scenario === "far_below") {
      eq(args(w, "record_dating_age_far_below"), [{ p_user: "u-1", p_session: SESSION }]);
      eq(args(w, "record_dating_age_assurance").length, 0, "far below records no pass");
    }
  }
});

Deno.test("the ID route: pass, fail, date-of-birth mismatch, minor, pending", async () => {
  const want: Record<string, string> = {
    id_pass: "verified", id_fail: "age_not_confirmed", id_dob_mismatch: "dob_mismatch", id_minor: "far_below", id_pending: "id_pending",
  };
  for (const [scenario, outcome] of Object.entries(want)) {
    const w = world();
    const d = deps(w);
    const s = await handleVerification({ action: "start_id", document: "ghana_card", scenario }, caller, d);
    eq([s.ok, s.vendor], [true, "fake"], scenario);
    eq((await handleVerification({ action: "complete_id", session_id: SESSION }, caller, d)).outcome, outcome, scenario);
    const ages = args(w, "record_dating_age_assurance").map((a) => `${a?.p_age_method}:${a?.p_age_result}`);
    eq(ages, outcome === "verified" ? ["id:pass"] : outcome === "age_not_confirmed" ? ["id:fail"] : [], `${scenario} ages`);
    if (scenario === "id_dob_mismatch") {
      eq(args(w, "check_dating_id_birth_date").map((a) => a?.p_dob), ["1970-01-01"]);
      eq(w.state, "awaiting_review");
    }
  }
});

Deno.test("a pending ID check stays waiting and is read again", async () => {
  const w = world();
  const d = deps(w);
  await handleVerification({ action: "start_id", document: "passport", scenario: "id_pending" }, caller, d);
  eq((await handleVerification({ action: "complete_id", session_id: SESSION }, caller, d)).outcome, "id_pending");
  eq((await handleVerification({ action: "complete_id", session_id: SESSION }, caller, d)).outcome, "id_pending");
  eq(args(w, "finish_dating_verification_session").length, 1, "finished once");
});

Deno.test("a vendor that can't answer counts nothing (§3.15 D11)", async () => {
  const w = world();
  const d = deps(w);
  eq(await handleVerification({ action: "start", scenario: "vendor_down" }, caller, d), { ok: false, reason: "vendor_unavailable" });
  const w2 = world();
  const p = table(true, 30, true);
  p.liveness = { ...p.liveness, results: () => Promise.reject(new Error("503")) };
  const d2 = deps(w2, p);
  await handleVerification({ action: "start" }, caller, d2);
  eq(await handleVerification({ action: "complete", session_id: SESSION }, caller, d2), { ok: false, reason: "vendor_unavailable" });
  eq(names(w2).includes("record_dating_liveness_attempt"), false, "no attempt counted");
  const w3 = world();
  const p3 = table(true, 30, true);
  p3.faceMatch = { name: "fake", compare: () => Promise.reject(new Error("throttled")) };
  const d3 = deps(w3, p3);
  await handleVerification({ action: "start" }, caller, d3);
  eq(await handleVerification({ action: "complete", session_id: SESSION }, caller, d3), { ok: false, reason: "vendor_unavailable" });
  eq(names(w3).includes("record_dating_identity_check"), false, "no identity recorded");
});

Deno.test("fake is refused unless the environment reads development; a scenario only in fake mode", async () => {
  let built = 0;
  for (const environment of ["production", "staging", ""]) {
    const w = world({ config: { available: true, mode: "fake", environment } });
    const d = { ...deps(w), providers: () => (built++, fakeProviders) };
    eq(await handleVerification({ action: "start" }, caller, d), { ok: false, reason: "unavailable" }, environment);
  }
  eq(built, 0, "no provider was built");
  const ok = world();
  eq((await handleVerification({ action: "start" }, caller, deps(ok))).ok, true, "development");
  const sandbox = world({ config: { available: true, mode: "sandbox", environment: "development" } });
  eq(await handleVerification({ action: "start", scenario: "pass" }, caller, deps(sandbox, table(true, 30, true))),
    { ok: false, reason: "invalid" });
  const off = world({ config: { available: false, mode: "fake", environment: "development" } });
  eq(await handleVerification({ action: "start" }, caller, deps(off)), { ok: false, reason: "unavailable" });
  eq(providersFor("fake", "production", () => undefined), null);
  eq(providersFor("fake", "development", () => undefined)?.liveness.name, "fake");
});

Deno.test("nothing is ever logged (images, estimates, dates of birth, vendor answers)", async () => {
  const seen: unknown[] = [];
  const saved = { log: console.log, info: console.info, warn: console.warn, error: console.error, debug: console.debug };
  for (const k of Object.keys(saved) as Array<keyof typeof saved>) console[k] = (...a: unknown[]) => seen.push(a);
  try {
    for (const scenario of ["pass", "liveness_fail", "under_25", "far_below", "photo_mismatch", "vendor_down"]) {
      const w = world();
      const d = deps(w);
      await handleVerification({ action: "start", scenario }, caller, d);
      await handleVerification({ action: "complete", session_id: SESSION }, caller, d);
    }
    for (const scenario of ["id_pass", "id_fail", "id_dob_mismatch", "id_minor", "id_pending"]) {
      const w = world();
      const d = deps(w);
      await handleVerification({ action: "start_id", document: "passport", scenario }, caller, d);
      await handleVerification({ action: "complete_id", session_id: SESSION }, caller, d);
    }
    const w = world();
    await handleVerification({ action: "human_start" }, caller, deps(w));
    await handleVerification({ action: "submit_human", session_id: SESSION }, caller, deps(w));
    await handleVerification({ action: "nope" }, caller, deps(w));
  } finally {
    Object.assign(console, saved);
  }
  eq(seen, []);
});

Deno.test("the reference frame and the photos' bytes are cleared after use", async () => {
  const frames: Uint8Array[] = [];
  const downloads: Uint8Array[] = [];
  const w = world();
  const d = deps(w, table(true, 30, true, frames), downloads);
  await handleVerification({ action: "start" }, caller, d);
  eq((await handleVerification({ action: "complete", session_id: SESSION }, caller, d)).outcome, "verified");
  eq([frames.length, downloads.length], [1, 2]);
  for (const b of [...frames, ...downloads]) eq(b.every((x) => x === 0), true, "zeroed");
});

Deno.test("only fixed codes leave: a server's text is never passed on", async () => {
  const w = world();
  const d = deps(w);
  const rpc = d.rpc;
  d.rpc = (fn, a) => fn === "begin_dating_verification"
    ? Promise.resolve({ data: { ok: false, reason: "duplicate key value violates unique constraint" }, error: null })
    : rpc(fn, a);
  eq(await handleVerification({ action: "start" }, caller, d), { ok: false, reason: "busy" });
  d.rpc = (fn, a) => fn === "begin_dating_verification" ? Promise.resolve({ data: { ok: false, reason: "rate_limited" }, error: null }) : rpc(fn, a);
  eq(await handleVerification({ action: "start" }, caller, d), { ok: false, reason: "rate_limited" });
  d.rpc = () => Promise.reject(new Error("connection reset"));
  eq(await handleVerification({ action: "start" }, caller, d), { ok: false, reason: "busy" });
  eq(await handleVerification({ action: "drop_tables" }, caller, deps(world())), { ok: false, reason: "invalid" });
  eq(await handleVerification({ action: "complete", session_id: "not-a-uuid" }, caller, deps(world())), { ok: false, reason: "invalid" });
});

Deno.test("the human route: two gestures and their two paths, then submitted", async () => {
  const w = world();
  const d = deps(w);
  eq(await handleVerification({ action: "human_start" }, caller, d), {
    ok: true, session_id: SESSION, gestures: ["left_ear", "thumbs_up"], paths: [`${SESSION}/1.jpg`, `${SESSION}/2.jpg`], resumed: false,
  });
  eq(args(w, "begin_dating_verification")[0]?.p_step, "human");
  eq(await handleVerification({ action: "submit_human", session_id: SESSION }, caller, d), { ok: true, outcome: "human_pending" });
});

Deno.test("the device hash (§3.3.4): sha256 of a 32-hex id, else nothing", async () => {
  eq(await deviceHashOf("0123456789abcdef0123456789abcdef"), "3eb1bd439947eb762998e566ccc2e099c791118b2f40579cc4f7da2b5061b7f9");
  for (const bad of [null, "", "0123456789ABCDEF0123456789ABCDEF", "0123456789abcdef", "0123456789abcdef0123456789abcdeg"]) {
    eq(await deviceHashOf(bad), null, String(bad));
  }
});

Deno.test("an ID whose face doesn't match the person never confirms the age (§3.3.1)", async () => {
  const w = world();
  const p = { ...fakeProviders };
  p.id = {
    name: "fake",
    startJob: () => Promise.resolve({ ref: "fake:id_pass:x" }),
    result: () => Promise.resolve({ status: "pass", dob: DECLARED, faceMatch: false }),
  };
  const d = deps(w, p);
  await handleVerification({ action: "start_id", document: "passport" }, caller, d);
  eq((await handleVerification({ action: "complete_id", session_id: SESSION }, caller, d)).outcome, "age_not_confirmed");
  eq(args(w, "record_dating_age_assurance").map((a) => `${a?.p_age_method}:${a?.p_age_result}`), ["id:fail"]);
  eq(names(w).includes("check_dating_id_birth_date"), false, "the date is not even compared");
});

// R-13 (owner ruling 2026-11-09): an estimate never ends the check; only a
// failed ID check (or Spec 1's under-18 hold) is final.
Deno.test("R-13: a failed or uncertain estimate never ends the check: nothing recorded, the ID check opens next", async () => {
  const rows: Array<[number | null, string]> = [[24, "needs_id"], [null, "age_uncertain"]];
  for (const [age, outcome] of rows) {
    const w = world();
    const d = deps(w, table(true, age, true));
    await handleVerification({ action: "start" }, caller, d);
    eq((await handleVerification({ action: "complete", session_id: SESSION }, caller, d)).outcome, outcome, `${age}`);
    eq([w.state, w.outcome], ["passed", outcome], `${age} session`);
    eq(args(w, "record_dating_age_assurance").length, 0, `${age}: no age result`);
    eq(names(w).includes("record_dating_age_far_below"), false, `${age}: no hold`);
    const s = await handleVerification({ action: "start_id", document: "ghana_card", scenario: "id_pass" }, caller, d);
    eq(s.ok, true, `${age}: the ID check opens`);
    eq((await handleVerification({ action: "complete_id", session_id: SESSION }, caller, d)).outcome, "verified", `${age}: by ID`);
  }
});
Deno.test("R-13: a failed ID check is final: nothing starts again", async () => {
  const w = world();
  const d = deps(w);
  await handleVerification({ action: "start_id", document: "passport", scenario: "id_fail" }, caller, d);
  eq((await handleVerification({ action: "complete_id", session_id: SESSION }, caller, d)).outcome, "age_not_confirmed");
  eq((await handleVerification({ action: "start" }, caller, d)).reason, "age_not_confirmed", "the video");
  eq((await handleVerification({ action: "start_id", document: "passport" }, caller, d)).reason, "age_not_confirmed", "the ID");
  eq((await handleVerification({ action: "human_start" }, caller, d)).reason, "age_not_confirmed", "a person");
});
```

```bash
cd supabase/functions && NO_COLOR=1 deno test --allow-read --allow-env --lock=../../.github/deno-w9.lock --frozen dating-verification/handler.test.ts 2>&1 | grep -m1 -E '^error'; cd ../..
```

Expected: `error: Type checking failed.` (the test imports `./handler.ts`, which does not exist yet).

- [ ] **Step 3: The handler and its entry point**

Every action reads the session through a service function, makes its vendor or storage calls with no database call open, then writes the result through another; a vendor that can't answer counts nothing (`vendor_unavailable`); nothing is logged; the frame and the photos' bytes are zeroed after use; only fixed codes leave.

Create `supabase/functions/dating-verification/handler.ts` with exactly:

```ts
// supabase/functions/dating-verification/handler.ts
// Spec 2 W4a (§3.3, §4.7): the verification flow behind D11, through the
// §3.3.5 seam. Actions: start, complete (the video check: liveness, then
// CompareFaces against every approved photo, then the age estimate),
// start_id, complete_id (the ID route), human_start, submit_human (the
// human route). Every result is written by the service functions of
// 20261109100000_dating_v2_age_assurance.sql; this file holds no state.
//
// Rules (W3 lessons, DPIA):
// - No database call is open across a vendor or storage call: each RPC is
//   its own short transaction, awaited before the network call starts.
// - A vendor that can't answer is "vendor_unavailable": nothing is
//   counted, nothing fails, the person tries again (§3.15 D11).
// - Nothing is logged here. The reference frame, the photos' bytes, the
//   estimate and the ID's date of birth live only inside the call that
//   needs them (the frame is zeroed after use) and never reach a log, the
//   database or the answer.
// - The answer carries fixed codes only, never vendor or server text.
// - fake is refused unless the environment reads development (§3.3.5,
//   Q19b), and a scenario is accepted only in fake mode.
import { FAKE_DECLARED_DOB } from "../_shared/age_assurance/fake.ts";
import { ageDecision, CHALLENGE_AGE, isFakeScenario, type Mode, type Providers } from "../_shared/age_assurance/types.ts";

export type RpcResult = { data: unknown; error: unknown };
export type Rpc = (fn: string, args?: Record<string, unknown>) => PromiseLike<RpcResult>;

export interface VerificationDeps {
  rpc: Rpc;
  /// An approved photo's bytes (dating-profile-photos), or null.
  download(key: string): Promise<Uint8Array | null>;
  providers(mode: Mode, environment: string): Providers | null;
}

export interface Caller {
  userId: string;
  /// sha256 hex of the x-attune-device header, or null (W4b reads it).
  deviceHash: string | null;
}

export type Answer = Record<string, unknown> & { ok: boolean };

const FIXED_REASONS = new Set([
  "unavailable", "invalid", "not_eligible", "consent_required", "photos_required", "age_not_confirmed",
  "already_verified", "awaiting_review", "rate_limited", "busy", "session_unavailable", "photos_missing",
  "reverify_device", "vendor_unavailable",
]);

function refusal(reason: unknown): Answer {
  return { ok: false, reason: typeof reason === "string" && FIXED_REASONS.has(reason) ? reason : "busy" };
}

async function call(deps: VerificationDeps, fn: string, args: Record<string, unknown>): Promise<Record<string, unknown> | null> {
  try {
    const { data, error } = await deps.rpc(fn, args);
    if (error || data === null || typeof data !== "object") return null;
    return data as Record<string, unknown>;
  } catch {
    return null;
  }
}

async function scalar(deps: VerificationDeps, fn: string, args: Record<string, unknown>): Promise<unknown> {
  try {
    const { data, error } = await deps.rpc(fn, args);
    return error ? null : data;
  } catch {
    return null;
  }
}

interface Setup {
  mode: Mode;
  providers: Providers;
}

async function setup(deps: VerificationDeps): Promise<Setup | Answer> {
  const cfg = await call(deps, "get_dating_verification_config", {});
  if (cfg === null) return refusal("busy");
  const mode = cfg.mode;
  const environment = typeof cfg.environment === "string" ? cfg.environment : "production";
  if (mode !== "fake" && mode !== "sandbox" && mode !== "live") return refusal("unavailable");
  // §3.3.5: fake is refused in production mode, whatever the database said.
  if (mode === "fake" && environment !== "development") return refusal("unavailable");
  if (cfg.available !== true) return refusal("unavailable");
  const providers = deps.providers(mode, environment);
  if (providers === null) return refusal("unavailable");
  return { mode, providers };
}

function isAnswer(x: Setup | Answer): x is Answer {
  return "ok" in x;
}

function scenarioFor(mode: Mode, body: Record<string, unknown>): { ok: true; scenario?: string } | { ok: false } {
  if (body.scenario === undefined || body.scenario === null) return { ok: true };
  if (mode !== "fake" || !isFakeScenario(body.scenario)) return { ok: false };
  return { ok: true, scenario: body.scenario };
}

function uuidOf(value: unknown): string | null {
  return typeof value === "string" && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(value) ? value : null;
}

async function finish(deps: VerificationDeps, session: string, state: string, outcome: string, position: number | null = null) {
  const r = await call(deps, "finish_dating_verification_session", {
    p_session: session, p_state: state, p_outcome: outcome, p_position: position,
  });
  return r?.ok === true;
}

/// start: a video session (resumed when one is open), then the vendor's.
async function start(caller: Caller, body: Record<string, unknown>, deps: VerificationDeps): Promise<Answer> {
  const s = await setup(deps);
  if (isAnswer(s)) return s;
  const sc = scenarioFor(s.mode, body);
  if (!sc.ok) return refusal("invalid");
  const begun = await call(deps, "begin_dating_verification", {
    p_user: caller.userId, p_kind: "activation", p_step: "liveness", p_vendor: s.providers.liveness.name,
    p_device_hash: caller.deviceHash, p_document: null,
  });
  if (begun === null) return refusal("busy");
  if (begun.ok !== true) return refusal(begun.reason);
  const session = uuidOf(begun.session_id);
  if (session === null) return refusal("busy");
  let ref: string;
  try {
    ref = (await s.providers.liveness.createSession({ scenario: sc.scenario })).ref;
  } catch {
    return refusal("vendor_unavailable");
  }
  const set = await call(deps, "set_dating_verification_ref", { p_session: session, p_ref: ref });
  if (set === null) return refusal("busy");
  if (set.ok !== true) return refusal(set.reason);
  return {
    ok: true, session_id: session, vendor: s.providers.liveness.name, vendor_session: ref,
    attempts: typeof begun.attempts === "number" ? begun.attempts : 0, resumed: begun.resumed === true,
  };
}

/// complete: the vendor's answer, then every photo, then the age.
async function complete(caller: Caller, body: Record<string, unknown>, deps: VerificationDeps): Promise<Answer> {
  const s = await setup(deps);
  if (isAnswer(s)) return s;
  const session = uuidOf(body.session_id);
  if (session === null) return refusal("invalid");
  const row = await call(deps, "get_dating_verification_session", { p_user: caller.userId, p_session: session });
  if (row === null) return refusal("busy");
  if (row.ok !== true || row.kind !== "activation" || row.step !== "liveness" || row.state !== "started"
      || row.expired === true || typeof row.vendor_session_ref !== "string") {
    return refusal("session_unavailable");
  }
  let result;
  try {
    result = await s.providers.liveness.results(row.vendor_session_ref);
  } catch {
    return refusal("vendor_unavailable");
  }
  if (result.status === "pending") return { ok: true, outcome: "pending" };
  if (result.status === "expired") return refusal("vendor_unavailable");
  if (result.status === "failed" || result.reference === null) {
    const r = await call(deps, "record_dating_liveness_attempt", { p_session: session, p_passed: false });
    if (r === null) return refusal("busy");
    if (r.ok !== true) return refusal(r.reason);
    return { ok: true, outcome: r.outcome === "another_way" ? "another_way" : "retry", attempts: r.attempts };
  }
  const frame = result.reference;
  try {
    const live = await call(deps, "record_dating_liveness_attempt", { p_session: session, p_passed: true });
    if (live === null) return refusal("busy");
    if (live.ok !== true) return refusal(live.reason);
    const photos = await scalar(deps, "get_dating_verification_photos", { p_user: caller.userId });
    if (!Array.isArray(photos)) return refusal("busy");
    if (photos.length < 2) return refusal("photos_required");
    for (let i = 0; i < photos.length; i++) {
      const p = photos[i] as { position?: unknown; storage_key?: unknown };
      if (typeof p?.storage_key !== "string" || typeof p.position !== "number") return refusal("busy");
      let bytes: Uint8Array | null;
      try {
        bytes = await deps.download(p.storage_key);
      } catch {
        bytes = null;
      }
      if (bytes === null) return refusal("vendor_unavailable");
      let same: boolean;
      try {
        same = await s.providers.faceMatch.compare(frame, bytes, i);
      } catch {
        return refusal("vendor_unavailable");
      } finally {
        bytes.fill(0);
      }
      if (!same) {
        const id = await call(deps, "record_dating_identity_check", {
          p_user: caller.userId, p_method: "liveness_compare", p_result: "fail", p_vendor: s.providers.faceMatch.name, p_decided_by: null,
        });
        if (id?.ok !== true) return refusal(id?.reason ?? "busy");
        if (!(await finish(deps, session, "failed", "photo_mismatch", p.position))) return refusal("busy");
        return { ok: true, outcome: "photo_mismatch", position: p.position };
      }
    }
    const id = await call(deps, "record_dating_identity_check", {
      p_user: caller.userId, p_method: "liveness_compare", p_result: "pass", p_vendor: s.providers.faceMatch.name, p_decided_by: null,
    });
    if (id?.ok !== true) return refusal(id?.reason ?? "busy");
    if (row.age === "pass") {
      if (!(await finish(deps, session, "passed", "verified"))) return refusal("busy");
      return { ok: true, outcome: "verified" };
    }
    let estimate = null;
    try {
      estimate = await s.providers.age.estimate(frame);
    } catch {
      estimate = null; // can't answer: never a pass (the ID route)
    }
    const decision = ageDecision(estimate, CHALLENGE_AGE);
    estimate = null;
    if (decision === "far_below") {
      const r = await call(deps, "record_dating_age_far_below", { p_user: caller.userId, p_session: session });
      if (r?.ok !== true) return refusal(r?.reason ?? "busy");
      return { ok: true, outcome: "far_below" };
    }
    if (decision === "pass") {
      const r = await call(deps, "record_dating_age_assurance", {
        p_user: caller.userId, p_age_method: "fae", p_age_result: "pass", p_challenge_age: CHALLENGE_AGE, p_vendor: s.providers.age.name,
      });
      if (r?.ok !== true) return refusal(r?.reason ?? "busy");
      if (!(await finish(deps, session, "passed", "verified"))) return refusal("busy");
      return { ok: true, outcome: "verified" };
    }
    // R-13 (owner ruling 2026-11-09): a failed or uncertain estimate never
    // ends the check: nothing is recorded, and the ID route opens next.
    const outcome = decision === "uncertain" ? "age_uncertain" : "needs_id";
    if (!(await finish(deps, session, "passed", outcome))) return refusal("busy");
    return { ok: true, outcome };
  } finally {
    frame.fill(0);
  }
}

/// start_id: an ID session for the chosen document, then the vendor's job.
async function startId(caller: Caller, body: Record<string, unknown>, deps: VerificationDeps): Promise<Answer> {
  const s = await setup(deps);
  if (isAnswer(s)) return s;
  const sc = scenarioFor(s.mode, body);
  if (!sc.ok) return refusal("invalid");
  const document = typeof body.document === "string" && /^[a-z0-9_]{1,40}$/.test(body.document) ? body.document : null;
  if (document === null) return refusal("invalid");
  const begun = await call(deps, "begin_dating_verification", {
    p_user: caller.userId, p_kind: "activation", p_step: "id", p_vendor: s.providers.id.name,
    p_device_hash: caller.deviceHash, p_document: document,
  });
  if (begun === null) return refusal("busy");
  if (begun.ok !== true) return refusal(begun.reason);
  const session = uuidOf(begun.session_id);
  if (session === null) return refusal("busy");
  const row = await call(deps, "get_dating_verification_session", { p_user: caller.userId, p_session: session });
  if (row?.ok !== true || typeof row.country !== "string") return refusal("busy");
  let ref: string;
  try {
    ref = (await s.providers.id.startJob({ document, country: row.country, sessionId: session, scenario: sc.scenario })).ref;
  } catch {
    return refusal("vendor_unavailable");
  }
  const set = await call(deps, "set_dating_verification_ref", { p_session: session, p_ref: ref });
  if (set === null) return refusal("busy");
  if (set.ok !== true) return refusal(set.reason);
  return { ok: true, session_id: session, vendor: s.providers.id.name, vendor_job: ref, resumed: begun.resumed === true };
}

/// complete_id: the vendor's result; the date of birth compared, dropped.
async function completeId(caller: Caller, body: Record<string, unknown>, deps: VerificationDeps): Promise<Answer> {
  const s = await setup(deps);
  if (isAnswer(s)) return s;
  const session = uuidOf(body.session_id);
  if (session === null) return refusal("invalid");
  const row = await call(deps, "get_dating_verification_session", { p_user: caller.userId, p_session: session });
  if (row === null) return refusal("busy");
  const waiting = row.state === "awaiting_review" && (row.outcome === "id_pending" || row.outcome === "dob_mismatch");
  if (row.ok !== true || row.step !== "id" || !(row.state === "started" || waiting)
      || (row.state === "started" && row.expired === true) || typeof row.vendor_session_ref !== "string") {
    return refusal("session_unavailable");
  }
  let r;
  try {
    r = await s.providers.id.result(row.vendor_session_ref);
  } catch {
    return refusal("vendor_unavailable");
  }
  if (r.status === "pending") {
    if (row.state === "started" && !(await finish(deps, session, "awaiting_review", "id_pending"))) return refusal("busy");
    return { ok: true, outcome: "id_pending" };
  }
  if (r.status === "fail" || r.faceMatch !== true) {
    const a = await call(deps, "record_dating_age_assurance", {
      p_user: caller.userId, p_age_method: "id", p_age_result: "fail", p_challenge_age: null, p_vendor: s.providers.id.name,
    });
    if (a?.ok !== true) return refusal(a?.reason ?? "busy");
    if (!(await finish(deps, session, "failed", "age_not_confirmed"))) return refusal("busy");
    return { ok: true, outcome: "age_not_confirmed" };
  }
  // Only the fake can answer "the declared date" (development); a real
  // vendor's date is compared by the database and forgotten.
  const check = s.providers.id.name === "fake" && r.dob === FAKE_DECLARED_DOB
    ? "match"
    : await scalar(deps, "check_dating_id_birth_date", { p_user: caller.userId, p_dob: r.dob });
  r = null;
  if (check === "minor") {
    const f = await call(deps, "record_dating_age_far_below", { p_user: caller.userId, p_session: session });
    if (f?.ok !== true) return refusal(f?.reason ?? "busy");
    return { ok: true, outcome: "far_below" };
  }
  if (check !== "match") {
    if (check !== "mismatch" && check !== "unknown") return refusal("busy");
    if (row.outcome !== "dob_mismatch" && !(await finish(deps, session, "awaiting_review", "dob_mismatch"))) return refusal("busy");
    return { ok: true, outcome: "dob_mismatch" };
  }
  const a = await call(deps, "record_dating_age_assurance", {
    p_user: caller.userId, p_age_method: "id", p_age_result: "pass", p_challenge_age: null, p_vendor: s.providers.id.name,
  });
  if (a?.ok !== true) return refusal(a?.reason ?? "busy");
  if (!(await finish(deps, session, "passed", "verified"))) return refusal("busy");
  return { ok: true, outcome: "verified" };
}

/// human_start: a human-review session with its two gestures and paths.
async function humanStart(caller: Caller, _body: Record<string, unknown>, deps: VerificationDeps): Promise<Answer> {
  const s = await setup(deps);
  if (isAnswer(s)) return s;
  const begun = await call(deps, "begin_dating_verification", {
    p_user: caller.userId, p_kind: "activation", p_step: "human", p_vendor: "attune",
    p_device_hash: caller.deviceHash, p_document: null,
  });
  if (begun === null) return refusal("busy");
  if (begun.ok !== true) return refusal(begun.reason);
  const session = uuidOf(begun.session_id);
  const gestures = Array.isArray(begun.gestures) ? begun.gestures.filter((g) => typeof g === "string") : [];
  if (session === null || gestures.length !== 2) return refusal("busy");
  return { ok: true, session_id: session, gestures, paths: [`${session}/1.jpg`, `${session}/2.jpg`], resumed: begun.resumed === true };
}

/// submit_human: both photos are there; a person checks.
async function submitHuman(caller: Caller, body: Record<string, unknown>, deps: VerificationDeps): Promise<Answer> {
  const s = await setup(deps);
  if (isAnswer(s)) return s;
  const session = uuidOf(body.session_id);
  if (session === null) return refusal("invalid");
  const r = await call(deps, "submit_dating_human_review", { p_user: caller.userId, p_session: session });
  if (r === null) return refusal("busy");
  if (r.ok !== true) return refusal(r.reason);
  return { ok: true, outcome: "human_pending" };
}

/// §3.3.4: the sha256 (hex) of the x-attune-device header when it is a
/// 128-bit id as 32 lowercase hex characters, the same value the database's
/// private.dating_request_device_hash() computes; else null. The id itself
/// is never stored or logged.
export async function deviceHashOf(header: string | null): Promise<string | null> {
  if (header === null || !/^[0-9a-f]{32}$/.test(header)) return null;
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(header)));
  return Array.from(digest, (b) => b.toString(16).padStart(2, "0")).join("");
}

const ACTIONS: Record<string, (c: Caller, b: Record<string, unknown>, d: VerificationDeps) => Promise<Answer>> = {
  start, complete, start_id: startId, complete_id: completeId, human_start: humanStart, submit_human: submitHuman,
};

export async function handleVerification(body: unknown, caller: Caller, deps: VerificationDeps): Promise<Answer> {
  const b = body !== null && typeof body === "object" ? body as Record<string, unknown> : {};
  const action = typeof b.action === "string" ? ACTIONS[b.action] : undefined;
  if (action === undefined) return refusal("invalid");
  try {
    return await action(caller, b, deps);
  } catch {
    return refusal("busy");
  }
}
```

Create `supabase/functions/dating-verification/index.ts` with exactly:

```ts
// supabase/functions/dating-verification/index.ts
// Spec 2 W4a (§4.7): the wiring for handler.ts. The caller is the signed-in
// person (their JWT); every write goes through the service functions. The
// x-attune-device header, sent only by the Dating-scoped client (S-7), is
// hashed here and only the hash is passed on (W4b's trusted devices).
// Errors answer fixed codes; only an error's code is ever logged.
import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { HttpError, jsonResponse, requireUser, serviceRoleClient } from "../_shared/attune_auth.ts";
import { errorCode } from "../_shared/error_code.ts";
import { providersFor } from "../_shared/age_assurance/providers.ts";
import { deviceHashOf, handleVerification } from "./handler.ts";

serve(async (req) => {
  if (req.method === "OPTIONS") return jsonResponse({ ok: true });
  if (req.method !== "POST") return jsonResponse({ ok: false, reason: "invalid" }, 405);
  try {
    const user = await requireUser(req);
    const supabase = serviceRoleClient();
    const body = await req.json().catch(() => ({}));
    const answer = await handleVerification(body, {
      userId: user.id,
      deviceHash: await deviceHashOf(req.headers.get("x-attune-device")),
    }, {
      rpc: (fn, args) => supabase.rpc(fn, args),
      download: async (key) => {
        const { data } = await supabase.storage.from("dating-profile-photos").download(key);
        return data ? new Uint8Array(await data.arrayBuffer()) : null;
      },
      providers: (mode, environment) => providersFor(mode, environment, (name) => Deno.env.get(name)),
    });
    return jsonResponse(answer);
  } catch (error) {
    if (error instanceof HttpError) return jsonResponse({ ok: false, reason: "unauthorized" }, error.status);
    console.error("dating-verification failed:", errorCode(error));
    return jsonResponse({ ok: false, reason: "busy" }, 500);
  }
});
```

```bash
cd supabase/functions && NO_COLOR=1 deno test --allow-read --allow-env --lock=../../.github/deno-w9.lock --frozen dating-verification/handler.test.ts _shared/age_assurance/providers.test.ts 2>&1 | grep -E '^(ok|FAILED) \|'
NO_COLOR=1 deno check --no-lock dating-verification/index.ts > /dev/null 2>&1; echo "check exit=$?"; cd ../..
```

Expected: `ok | 24 passed | 0 failed (…)`; `check exit=0` (`index.ts` imports `std/http/server.ts`, which the frozen W9 lock does not list, so the entry point is type-checked without the lock; CI runs only the tests, under it).

- [ ] **Step 4: Remove v1, join CI, require a signed-in caller**

Create `$D/edit_ci_T2.py` with exactly:

```python
# Spec 2 W4a Task 2: the new Deno tests join CI's deno line (frozen lock);
# dating-verification needs a signed-in caller.
import pathlib, sys
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from anchor import edit
edit('.github/workflows/tests.yml', [
    (" process-scheduled-notifications/privacy_allowlist.test.ts\n",
     " process-scheduled-notifications/privacy_allowlist.test.ts dating-verification/handler.test.ts _shared/age_assurance/providers.test.ts\n")],
    'T2 CI deno line')
edit('supabase/config.toml', [
    ("[functions.create-relationship-invite]\nverify_jwt = true\n",
     "[functions.create-relationship-invite]\nverify_jwt = true\n\n# Spec 2 W4a (§4.7): the verification flow; the caller is the signed-in person.\n[functions.dating-verification]\nverify_jwt = true\n")],
    'T2 config')
```

```bash
rm -r supabase/functions/verify-dating-profile
python3 -I .superpowers/sdd/2026-11-09-spec2-w4/edit_ci_T2.py
grep -rln 'verify-dating-profile' lib test supabase/functions scripts .github supabase/config.toml | wc -l
L=$(grep -A2 'name: Run Deno tests' .github/workflows/tests.yml | grep 'run: deno test' | sed 's/^ *run: //')
(cd supabase/functions && export NO_COLOR=1 && eval "$L" 2>&1 | grep -E '^(ok|FAILED) \|')
```

Expected: the two edit lines; `0`; `ok | 157 passed | 0 failed (…)` (the CI line in full under the frozen lock: the 133 already on it and these 24).

- [ ] **Step 5: Mutants**

Create `$D/denomut.py` with exactly:

```python
#!/usr/bin/env python3
"""Deno mutation runner. usage: denomut.py <spec.py> [name ...]
spec.py defines TESTS (paths under supabase/functions) and MUTS = {name:
(path, [(old, new), ...])}; each old occurs exactly once. Each mutant is
applied, the tests run under the frozen lock, the file restored byte for
byte. KILLED = a test failed; a type error is COMPILE (not a kill)."""
import pathlib, re, runpy, subprocess, sys
spec = runpy.run_path(sys.argv[1])
only = set(sys.argv[2:])
killed = total = 0
for name, (path, edits) in spec['MUTS'].items():
    if only and name not in only:
        continue
    p = pathlib.Path(path)
    orig = p.read_bytes()
    s = orig.decode()
    for a, b in edits:
        assert s.count(a) == 1, (name, a[:60], s.count(a))
        s = s.replace(a, b)
    p.write_text(s)
    try:
        r = subprocess.run(['deno', 'test', '--allow-read', '--allow-env', '--lock=../../.github/deno-w9.lock', '--frozen',
                            *spec['TESTS']], cwd='supabase/functions', capture_output=True, text=True, timeout=300)
    finally:
        p.write_bytes(orig)
    assert p.read_bytes() == orig, name
    out = re.sub(r'\x1b\[[0-9;]*m', '', r.stdout + r.stderr)
    total += 1
    if 'Type checking failed' in out or 'error: TS' in out or re.search(r'TS\d{4}', out):
        status, why = 'COMPILE', next((l for l in out.splitlines() if 'TS' in l), '')
    elif r.returncode != 0:
        killed += 1
        fails = re.findall(r'^(.+?) \.\.\. FAILED', out, re.M)
        status, why = 'KILLED', (fails[0] if fails else out.strip().splitlines()[-1])
    else:
        status, why = 'SURVIVED', ''
    print(f'{name}: {status}  {why[:140]}')
print(f'{killed}/{total} killed')
```

Create `$D/mut_T2.py` with exactly:

```python
# Spec 2 W4a Task 2: Deno mutants (denomut.py).
H = 'supabase/functions/dating-verification/handler.ts'
T = 'supabase/functions/_shared/age_assurance/types.ts'
A = 'supabase/functions/_shared/age_assurance/aws.ts'
S = 'supabase/functions/_shared/age_assurance/smile_id.ts'
P = 'supabase/functions/_shared/age_assurance/providers.ts'
TESTS = ['dating-verification/handler.test.ts', '_shared/age_assurance/providers.test.ts']
MUTS = {
 # §7.5 mutant 8, the edge function's half: a fae pass below 25.
 'm8_estimate_below_25_passes': (T, [('  return estimate.age >= challengeAge ? "pass" : "needs_id";', '  return "pass";')]),
 'm8_off_by_one': (T, [('  return estimate.age >= challengeAge ? "pass" : "needs_id";', '  return estimate.age > challengeAge ? "pass" : "needs_id";')]),
 'no_estimate_passes': (T, [('  if (estimate === null || !Number.isFinite(estimate.age) || estimate.uncertain === true) return "uncertain";', '  if (estimate === null) return "pass";')]),
 'far_below_ignored': (T, [('  if (estimate.under18HighConfidence) return "far_below";\n', '')]),
 'fake_in_production': (H, [('  if (mode === "fake" && environment !== "development") return refusal("unavailable");\n', '')]),
 'scenario_any_mode': (H, [('  if (mode !== "fake" || !isFakeScenario(body.scenario)) return { ok: false };', '  if (!isFakeScenario(body.scenario)) return { ok: false };')]),
 'vendor_down_counts': (H, [("""  try {
    result = await s.providers.liveness.results(row.vendor_session_ref);
  } catch {
    return refusal("vendor_unavailable");
  }""", """  try {
    result = await s.providers.liveness.results(row.vendor_session_ref);
  } catch {
    await call(deps, "record_dating_liveness_attempt", { p_session: session, p_passed: false });
    return refusal("vendor_unavailable");
  }""")]),
 'frame_kept': (H, [('  } finally {\n    frame.fill(0);\n  }', '  } finally {\n    // kept\n  }')]),
 'photo_bytes_kept': (H, [('      } finally {\n        bytes.fill(0);\n      }', '      } finally {\n        // kept\n      }')]),
 'logs_estimate': (H, [('    const decision = ageDecision(estimate, CHALLENGE_AGE);', '    console.log("estimate", estimate);\n    const decision = ageDecision(estimate, CHALLENGE_AGE);')]),
 'raw_reason_passed_on': (H, [('  return { ok: false, reason: typeof reason === "string" && FIXED_REASONS.has(reason) ? reason : "busy" };',
                              '  return { ok: false, reason: typeof reason === "string" ? reason : "busy" };')]),
 'mismatch_skips_photo': (H, [('      if (!same) {', '      if (!same && i === 0) {')]),
 'age_rechecked_after_pass': (H, [('    if (row.age === "pass") {', '    if (row.age === "never") {')]),
 'id_face_ignored': (H, [('  if (r.status === "fail" || r.faceMatch !== true) {', '  if (r.status === "fail") {')]),
 'id_minor_human_review': (H, [('  if (check === "minor") {', '  if (check === "never") {')]),
 'device_hash_any_case': (H, [('  if (header === null || !/^[0-9a-f]{32}$/.test(header)) return null;', '  if (header === null || !/^[0-9a-fA-F]{32}$/.test(header)) return null;')]),
 'aws_us_east_1': (A, [(' || region === "us-east-1"', '')]),
 'aws_audit_images': (A, [('payload: { Settings: { AuditImagesLimit: 0 } }', 'payload: { Settings: { AuditImagesLimit: 4 } }')]),
 'aws_low_confidence_passes': (A, [('          if (confidence < LIVENESS_MIN_CONFIDENCE || typeof bytes !== "string") return { status: "failed", reference: null };',
                                    '          if (typeof bytes !== "string") return { status: "failed", reference: null };')]),
 'smile_images_requested': (S, [('        image_links: false,', '        image_links: true,')]),
 'smile_fail_as_pass': (S, [('      const documentOk = r.job_success === true && actions.Verify_Document === "Passed";', '      const documentOk = r.job_success === true;')]),
 'estimation_fake_in_live': (P, [('    age: unconfiguredAgeEstimation,', '    age: fakeProviders.age,')]),
 # R-13 (owner ruling 2026-11-09): an estimate never ends the check.
 'uncertain_passes': (T, [('!Number.isFinite(estimate.age) || estimate.uncertain === true) return "uncertain";',
                           '!Number.isFinite(estimate.age)) return "uncertain";')]),
 'uncertain_ends_check': (H, [('const outcome = decision === "uncertain" ? "age_uncertain" : "needs_id";',
                               'const outcome = decision === "uncertain" ? "age_not_confirmed" : "needs_id";')]),
 'estimate_fail_recorded': (H, [('    if (!(await finish(deps, session, "passed", outcome))) return refusal("busy");',
                                 '    await call(deps, "record_dating_age_assurance", { p_user: caller.userId, p_age_method: "fae", p_age_result: "fail", p_challenge_age: CHALLENGE_AGE, p_vendor: s.providers.age.name });\n'
                                 '    if (!(await finish(deps, session, "passed", outcome))) return refusal("busy");')]),
}
```

```bash
D=.superpowers/sdd/2026-11-09-spec2-w4
python3 -I $D/denomut.py $D/mut_T2.py | tee $D/mut_T2.txt | tail -1
grep -E 'SURVIVED|COMPILE' $D/mut_T2.txt | wc -l
```

Expected: `25/25 killed`; `0`. Quote the lines in the report (e.g. `m8_estimate_below_25_passes: KILLED  the decision table: liveness x estimate x photos`). Do not commit; record the tree in the report.

### Task 3: The client's verification data, the capture seam, and the home's `verifying` state and `verification` pause (§3.1, §3.3.2 "During capture", §3.3.5, §4.10; carry 1; D8; R-10, R-11, R-29)

**Files:**
- Create: `lib/features/dating/verify/{dating_verification.dart, dating_verification_repository.dart, dating_verification_providers.dart, dating_capture.dart}`, `test/features/dating/support/dating_verify_fakes.dart`, `test/features/dating/verify/{dating_verification_data_test.dart, dating_capture_section_test.dart}`, `$D/{edit_T3.py, arb_fragment_T3.txt, mut_T3.py}`
- Modify: `lib/features/dating/data/dating_home.dart` (`verifying`; `DatingPauseReason.verification`), `lib/features/dating/section/dating_section.dart` (the verifying card; the verification pause's line and button), `test/features/dating/data/dating_home_test.dart` (two W3 pins that read `verifying` as unknown), `lib/i10n/app_en.arb` and the generated l10n

**Interfaces:**
- Consumes: Task 1's `get_my_dating_verification()` (through `DatingRpc` on the Dating client); Task 2's actions (through `functions.invoke('dating-verification')` on the Dating client); W3's `DatingRpc`, `datingAccountProvider`, `datingSupabaseClientProvider`, `DatingSection`.
- Produces: `DatingVerification.fromJson` (fail closed: anything not `ok` reads unavailable); `DatingVerificationGateway.act(action, [body]) → DatingVerifyAnswer`, `.status() → DatingVerification`, `.consent(key) → DatingWrite`, `.uploadReviewPhoto(path, jpeg) → bool`; `datingVerificationProvider(account)` (autoDispose family, D8) and `WidgetRef.rereadDatingVerification(account)` (fix round 1, I-2: after an answer whose `readStatusAgain` is true); `DatingCaptureLauncher.liveness(context, {vendor, vendorRef})` / `.idDocument(context, {vendor, vendorRef}) → DatingCaptureResult` (`done` with a scenario, `cancelled`, `unavailable`); `DatingCaptureVoice.prompt(context, text)`.

- [ ] **Step 1: Write the failing tests and the fakes**

Create `test/features/dating/support/dating_verify_fakes.dart` with exactly:

```dart
// Spec 2 W4a: in-memory verification gateway and capture for tests.
import 'dart:async';
import 'dart:typed_data';

import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:attune/features/dating/verify/dating_capture.dart';
import 'package:attune/features/dating/verify/dating_verification.dart';
import 'package:attune/features/dating/verify/dating_verification_repository.dart';
import 'package:flutter/widgets.dart';

class FakeDatingVerificationGateway implements DatingVerificationGateway {
  FakeDatingVerificationGateway({
    this.state = const DatingVerification(
      available: true,
      photosReady: true,
      idDocuments: [
        DatingIdDocument(code: 'ghana_card', nameKey: 'dating_id_ghana_card'),
        DatingIdDocument(code: 'passport', nameKey: 'dating_id_passport'),
      ],
    ),
  });

  DatingVerification state;
  Completer<DatingVerification>? hold;
  int reads = 0;
  DatingWrite consentAnswer = const DatingWrite(ok: true);
  final consents = <String>[];

  /// What each action answers next (the last one repeats).
  final answers = <String, List<DatingVerifyAnswer>>{};
  final actions = <(String, Map<String, Object?>)>[];
  final uploads = <String>[];
  bool uploadOk = true;

  /// Runs after each action is recorded (a test changes [state] here).
  void Function(String action)? onAct;

  @override
  Future<DatingVerification> status() async {
    reads++;
    final held = hold;
    if (held != null) return held.future;
    return state;
  }

  @override
  Future<DatingWrite> consent(String key) async {
    consents.add(key);
    return consentAnswer;
  }

  @override
  Future<DatingVerifyAnswer> act(
    String action, [
    Map<String, Object?> body = const {},
  ]) async {
    actions.add((action, body));
    onAct?.call(action);
    final list = answers[action];
    if (list == null || list.isEmpty) return DatingVerifyAnswer.failed;
    return list.length == 1 ? list.first : list.removeAt(0);
  }

  @override
  Future<bool> uploadReviewPhoto(String path, Uint8List jpeg) async {
    uploads.add(path);
    return uploadOk;
  }

  List<String> get actionNames => [for (final (a, _) in actions) a];
}

class FakeCaptureLauncher implements DatingCaptureLauncher {
  FakeCaptureLauncher({
    this.result = const DatingCaptureResult(DatingCaptureKind.done),
  });

  DatingCaptureResult result;
  final calls = <String>[];

  @override
  Future<DatingCaptureResult> liveness(
    BuildContext context, {
    required String vendor,
    required String vendorRef,
  }) async {
    calls.add('liveness:$vendor:$vendorRef');
    return result;
  }

  @override
  Future<DatingCaptureResult> idDocument(
    BuildContext context, {
    required String vendor,
    required String vendorRef,
  }) async {
    calls.add('id:$vendor:$vendorRef');
    return result;
  }
}

const datingTestSession = '11111111-2222-4333-8444-555555555555';

DatingVerifyAnswer datingStarted({String vendor = 'fake'}) =>
    DatingVerifyAnswer(
      ok: true,
      sessionId: datingTestSession,
      vendor: vendor,
      vendorRef: 'ref-1',
    );

DatingVerifyAnswer datingOutcome(DatingVerifyOutcome o, {int? position}) =>
    DatingVerifyAnswer(ok: true, outcome: o, position: position);

DatingVerifyAnswer datingRefused(DatingVerifyRefusal r) =>
    DatingVerifyAnswer(ok: false, refusal: r);
```

Create `test/features/dating/verify/dating_verification_data_test.dart` with exactly:

```dart
// Spec 2 W4a (§3.3, D8): the verification answers read fail-closed; the
// repository sends the action and the consent, never shows a server's
// text, and answers `failed` on any error; one status entry per account.
import 'dart:async';
import 'dart:typed_data';

import 'package:attune/features/dating/data/dating_home.dart';
import 'package:attune/features/dating/data/dating_providers.dart';
import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:attune/features/dating/verify/dating_verification.dart';
import 'package:attune/features/dating/verify/dating_verification_providers.dart';
import 'package:attune/features/dating/verify/dating_verification_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../support/dating_verify_fakes.dart';

void main() {
  group('the answers, fail closed', () {
    test('a status that is not ok, or not an object, runs nothing', () {
      for (final raw in [
        null,
        'x',
        <String, Object?>{},
        {'ok': false},
      ]) {
        final v = DatingVerification.fromJson(raw);
        expect(v.available, isFalse, reason: '$raw');
        expect(v.verified, isFalse, reason: '$raw');
      }
    });

    test('a full status reads every field; unknown codes are none', () {
      final v = DatingVerification.fromJson({
        'ok': true,
        'available': true,
        'device': 'trusted',
        'age': 'pass',
        'identity': 'review',
        'session': {
          'id': 's-1',
          'kind': 'activation',
          'step': 'human',
          'state': 'awaiting_review',
          'attempts': 0,
          'outcome': 'human_pending',
          'position': null,
          'open': true,
          'gestures': ['left_ear', 'thumbs_up'],
        },
        'id_documents': [
          {'code': 'ghana_card', 'name_key': 'dating_id_ghana_card'},
          {'code': 7},
        ],
        'photos_ready': true,
      });
      expect(v.available, isTrue);
      expect(v.trustedDevice, isTrue);
      expect(v.age, DatingCheck.pass);
      expect(v.identity, DatingCheck.review);
      expect(v.verified, isFalse);
      expect(v.waiting, isTrue);
      expect(v.session!.gestures, ['left_ear', 'thumbs_up']);
      expect(v.session!.outcome, DatingVerifyOutcome.humanPending);
      expect(v.idDocuments.map((d) => d.code), ['ghana_card']);
      expect(DatingCheck.of('passed'), DatingCheck.none);
      expect(DatingVerifyOutcome.of('you_are_in'), DatingVerifyOutcome.unknown);
      expect(DatingVerifyRefusal.of('server text'), DatingVerifyRefusal.failed);
    });

    test(
      'R-13: a failed or an uncertain estimate reads as its own outcome',
      () {
        expect(DatingVerifyOutcome.of('needs_id'), DatingVerifyOutcome.needsId);
        expect(
          DatingVerifyOutcome.of('age_uncertain'),
          DatingVerifyOutcome.ageUncertain,
        );
      },
    );

    test('an untrusted device reads as such (W4b)', () {
      final v = DatingVerification.fromJson({
        'ok': true,
        'device': 'untrusted',
        'available': true,
        'session': null,
      });
      expect(v.trustedDevice, isFalse);
      expect(v.session, isNull);
    });

    test('the home reads verifying, and a verification pause never offers '
        'Resume (carry 1)', () {
      final h = DatingHome.fromJson({'state': 'verifying', 'has_data': true});
      expect(h.state, DatingHomeState.verifying);
      expect(h.hasProfile, isTrue);
      final p = DatingHome.fromJson({
        'state': 'paused',
        'pause_reason': 'verification',
        'can_resume': true,
      });
      expect(p.pauseReason, DatingPauseReason.verification);
      expect(p.resumeOffered, isFalse);
    });
  });

  group('the repository', () {
    late List<(String, Map<String, dynamic>?)> rpcs;
    late List<Map<String, Object?>> invokes;
    late List<String> uploads;
    Object? rpcAnswer;
    Object? rpcError;
    Object? invokeAnswer;
    Object? invokeError;

    DatingVerificationRepository repo() => DatingVerificationRepository(
      DatingRpc.withCall((fn, params) async {
        rpcs.add((fn, params));
        if (rpcError != null) throw rpcError!;
        return rpcAnswer;
      }),
      (body) async {
        invokes.add(body);
        if (invokeError != null) throw invokeError!;
        return invokeAnswer;
      },
      (path, jpeg) async {
        if (path.contains('fail')) throw StateError('storage');
        uploads.add(path);
      },
    );

    setUp(() {
      rpcs = [];
      invokes = [];
      uploads = [];
      rpcAnswer = null;
      rpcError = null;
      invokeAnswer = null;
      invokeError = null;
    });

    test(
      'status: get_my_dating_verification; an error is unavailable',
      () async {
        rpcAnswer = {'ok': true, 'available': true};
        expect((await repo().status()).available, isTrue);
        expect(rpcs.single.$1, 'get_my_dating_verification');
        rpcError = StateError('network');
        expect((await repo().status()).available, isFalse);
      },
    );

    test(
      'consent: biometric_verification, granted; refusals by name',
      () async {
        expect((await repo().consent('k-1')).ok, isTrue);
        expect(rpcs.single.$1, 'record_dating_consent');
        expect(rpcs.single.$2, {
          'p_idempotency_key': 'k-1',
          'p_purpose': 'biometric_verification',
          'p_action': 'granted',
          'p_policy_version': datingBiometricPolicyVersion,
          'p_categories': ['face'],
        });
        rpcError = const PostgrestException(message: 'reverify_device');
        expect((await repo().consent('k-2')).reason, 'reverify_device');
        rpcError = const PostgrestException(message: 'invalid_consent_event');
        expect((await repo().consent('k-3')).reason, 'failed');
        rpcError = const PostgrestException(message: 'dating:busy');
        expect((await repo().consent('k-4')).reason, 'busy');
      },
    );

    test('act: the action and body to the edge function; any error is '
        'failed, never its text', () async {
      invokeAnswer = {
        'ok': true,
        'session_id': 's-1',
        'vendor': 'fake',
        'vendor_session': 'ref-1',
      };
      final a = await repo().act('start', {'scenario': 'pass'});
      expect(invokes.single, {'scenario': 'pass', 'action': 'start'});
      expect(
        [a.ok, a.sessionId, a.vendor, a.vendorRef],
        [true, 's-1', 'fake', 'ref-1'],
      );
      invokeAnswer = {'ok': false, 'reason': 'duplicate key value violates'};
      expect((await repo().act('start')).refusal, DatingVerifyRefusal.failed);
      invokeAnswer = {'ok': false, 'reason': 'rate_limited'};
      expect(
        (await repo().act('start')).refusal,
        DatingVerifyRefusal.rateLimited,
      );
      invokeError = StateError('FunctionException 500');
      expect(
        (await repo().act('complete')).refusal,
        DatingVerifyRefusal.failed,
      );
    });

    test('a review photo that did not land is false', () async {
      expect(
        await repo().uploadReviewPhoto('s/1.jpg', Uint8List.fromList([1])),
        isTrue,
      );
      expect(
        await repo().uploadReviewPhoto('fail/2.jpg', Uint8List.fromList([1])),
        isFalse,
      );
      expect(uploads, ['s/1.jpg']);
    });
  });

  test(
    'D8: the next account reads its own state, nothing of the last',
    () async {
      final gateway = FakeDatingVerificationGateway(
        state: const DatingVerification(available: true, age: DatingCheck.pass),
      );
      final account = StateProvider<String?>((ref) => 'ama');
      final c = ProviderContainer(
        overrides: [
          datingAccountProvider.overrideWith((ref) => ref.watch(account)),
          datingVerificationGatewayProvider.overrideWithValue(gateway),
        ],
      );
      addTearDown(c.dispose);
      final sub = c.listen(
        datingVerificationProvider(c.read(datingAccountProvider)),
        (_, __) {},
      );
      expect(
        (await c.read(datingVerificationProvider('ama').future)).age,
        DatingCheck.pass,
      );
      gateway.hold = Completer<DatingVerification>();
      c.read(account.notifier).state = 'kofi';
      final next = c.read(datingVerificationProvider('kofi'));
      expect(next.hasValue, isFalse, reason: 'nothing of the last account');
      gateway.hold!.complete(const DatingVerification(available: true));
      expect(
        (await c.read(datingVerificationProvider('kofi').future)).age,
        DatingCheck.none,
      );
      sub.close();
      expect(
        await c.read(datingVerificationProvider(null).future),
        same(DatingVerification.unavailable),
      );
    },
  );
}
```

Create `test/features/dating/verify/dating_capture_section_test.dart` with exactly:

```dart
// Spec 2 W4a (§3.1, §3.3.2, §3.15 D11; carry 1; R-10): the capture
// prompts are spoken through the screen reader and tick unless reduce
// motion is on; the practice capture runs for the fake vendor only; the
// section's verifying card and the verification pause open the check.
import 'package:attune/core/ui/feedback/haptics.dart';
import 'package:attune/features/dating/data/dating_home.dart';
import 'package:attune/features/dating/section/dating_section.dart';
import 'package:attune/features/dating/verify/dating_capture.dart';
import 'package:attune/features/onboarding/data/home_state_service.dart';
import 'package:attune/home/home_seams.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/fake_home_state.dart';
import '../../../helpers/flow_harness.dart';
import '../../../helpers/home_harness.dart';
import '../../../helpers/tap_in_reach.dart';
import '../support/dating_fakes.dart';
import '../support/dating_shell.dart';

Future<FakeHaptics> _practice(
  WidgetTester t, {
  bool screenReader = false,
  bool reduceMotion = false,
  List<DatingCaptureResult?>? results,
  String vendor = 'fake',
}) async {
  final haptics = FakeHaptics();
  await pumpFlowScreen(
    t,
    () => Builder(
      builder:
          (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  final r = await const DatingDevCaptureLauncher().liveness(
                    context,
                    vendor: vendor,
                    vendorRef: 'ref-1',
                  );
                  results?.add(r);
                },
                child: const Text('open'),
              ),
            ),
          ),
    ),
    reduceMotion: reduceMotion,
    overrides: [hapticsProvider.overrideWithValue(haptics)],
  );
  if (screenReader) {
    t
        .platformDispatcher
        .accessibilityFeaturesTestValue = FakeAccessibilityFeatures(
      accessibleNavigation: true,
      disableAnimations: reduceMotion,
    );
  }
  await tapInReach(t, find.text('open'));
  // The page, then its first prompt (a post-frame callback).
  await t.pump();
  await t.pump();
  return haptics;
}

void main() {
  testWidgets('the prompts in turn, spoken with a screen reader on, a tick '
      'each', (t) async {
    final haptics = await _practice(t, screenReader: true);
    expect(find.text('Move the phone a little closer'), findsOneWidget);
    await t.pump(kDatingPromptGap);
    expect(find.text('Hold still'), findsOneWidget);
    await t.pump(kDatingPromptGap);
    expect(find.text('Done'), findsOneWidget);
    await t.pumpAndSettle();
    expect(
      [for (final a in t.takeAnnouncements()) a.message],
      ['Move the phone a little closer', 'Hold still', 'Done'],
    );
    expect(haptics.selectionCount, 3);
  });

  testWidgets('no screen reader: shown, never announced; reduce motion: no '
      'ticks', (t) async {
    final haptics = await _practice(t, reduceMotion: true);
    await t.pump(kDatingPromptGap);
    await t.pump(kDatingPromptGap);
    await t.pumpAndSettle();
    expect(find.text('Done'), findsOneWidget);
    expect(t.takeAnnouncements(), isEmpty);
    expect(haptics.selectionCount, 0);
  });

  testWidgets('the practice capture answers the scenario picked, or '
      'cancelled', (t) async {
    final results = <DatingCaptureResult?>[];
    await _practice(t, results: results);
    await t.pumpAndSettle();
    await tapInReach(t, find.text('under_25'));
    await t.pump();
    await tapInReach(t, find.text('Continue'));
    await t.pumpAndSettle();
    expect(results.single!.kind, DatingCaptureKind.done);
    expect(results.single!.scenario, 'under_25');
    await tapInReach(t, find.text('open'));
    await t.pumpAndSettle();
    await tapInReach(t, find.text('Cancel'));
    await t.pumpAndSettle();
    expect(results.last!.kind, DatingCaptureKind.cancelled);
  });

  testWidgets('R-10: any vendor but the fake has no capture yet: unavailable, '
      'nothing opens', (t) async {
    final results = <DatingCaptureResult?>[];
    await _practice(t, results: results, vendor: 'aws_rekognition');
    await t.pumpAndSettle();
    expect(find.byType(DatingPracticeCaptureScreen), findsNothing);
    expect(results.single!.kind, DatingCaptureKind.unavailable);
  });

  group('the section', () {
    Future<void> section(WidgetTester t, DatingHome home) async {
      final s = await pumpDatingShell(
        t,
        initial: '/me',
        home: FakeDatingHomeGateway(home: home),
        extraRoutes: [
          GoRoute(
            path: '/me',
            builder:
                (_, __) => const Scaffold(
                  body: SingleChildScrollView(child: DatingSection()),
                ),
          ),
        ],
        overrides: [
          homeAuthProvider.overrideWithValue(FakeHomeAuth(testUser('ama'))),
          homeStateServiceProvider.overrideWithValue(
            HomeStateService(
              FakeHomeStateGateway(state: homeJson(path: 'dating')),
            ),
          ),
        ],
      );
      expect(s.location, '/me');
    }

    testWidgets('verifying: the waiting line, and its link opens the check', (
      t,
    ) async {
      await section(
        t,
        const DatingHome(state: DatingHomeState.verifying, hasData: true),
      );
      expect(
        find.text(
          "We're checking your video. This usually takes less than a day.",
        ),
        findsOneWidget,
      );
      expect(find.text('Dating settings'), findsOneWidget);
      await tapInReach(t, find.text('See where it is'));
      await t.pumpAndSettle();
      // (A push doesn't change the router's location: the screen shown.)
      expect(find.text('Step 10 of 12'), findsOneWidget);
    });

    testWidgets('carry 1: a verification pause offers the check, never '
        'Resume', (t) async {
      await section(
        t,
        const DatingHome(
          state: DatingHomeState.paused,
          pauseReason: DatingPauseReason.verification,
          canResume: true,
          hasData: true,
        ),
      );
      expect(
        find.text("Dating is paused until you verify it's you again."),
        findsOneWidget,
      );
      expect(find.text('Resume'), findsNothing);
      await tapInReach(t, find.text("Verify it's you"));
      await t.pumpAndSettle();
      // (A push doesn't change the router's location: the screen shown.)
      expect(find.text('Step 10 of 12'), findsOneWidget);
    });
  });
}
```

```bash
flutter test test/features/dating/verify/dating_verification_data_test.dart 2>&1 | tr '\r' '\n' | grep -m1 -o "Error: Error when reading '[^']*'"
```

Expected: `Error: Error when reading 'lib/features/dating/verify/dating_verification.dart'`.

- [ ] **Step 2: The data layer and the capture seam**

Create `lib/features/dating/verify/dating_verification.dart` with exactly:

```dart
// Spec 2 W4a (§3.3): what the verification calls answer, as the app reads
// them. Codes only: the app never shows a server's or a vendor's text, and
// a code it doesn't know is `unknown` / `failed` (fail closed: never
// "you're verified").

/// A check's state: passed, failed, being looked at, or not done.
enum DatingCheck {
  pass,
  fail,
  review,
  none;

  static DatingCheck of(Object? wire) => switch (wire) {
    'pass' => pass,
    'fail' => fail,
    'review' => review,
    _ => none,
  };
}

/// What a check step ended in (§3.3.2's outcome table).
enum DatingVerifyOutcome {
  verified('verified'),
  retry('retry'),
  anotherWay('another_way'),
  needsId('needs_id'),
  // R-13 (owner ruling 2026-11-09): the estimate was uncertain: the ID route.
  ageUncertain('age_uncertain'),
  photoMismatch('photo_mismatch'),
  farBelow('far_below'),
  idPending('id_pending'),
  dobMismatch('dob_mismatch'),
  ageNotConfirmed('age_not_confirmed'),
  humanPending('human_pending'),
  identityFailed('identity_failed'),
  askForId('ask_for_id'),
  pending('pending'),
  unknown('');

  const DatingVerifyOutcome(this.wire);

  final String wire;

  static DatingVerifyOutcome of(Object? wire) => values.firstWhere(
    (o) => o != unknown && o.wire == wire,
    orElse: () => unknown,
  );
}

/// Why a call was refused (dating-verification's fixed codes).
enum DatingVerifyRefusal {
  unavailable('unavailable'),
  invalid('invalid'),
  notEligible('not_eligible'),
  consentRequired('consent_required'),
  photosRequired('photos_required'),
  ageNotConfirmed('age_not_confirmed'),
  alreadyVerified('already_verified'),
  awaitingReview('awaiting_review'),
  rateLimited('rate_limited'),
  busy('busy'),
  sessionUnavailable('session_unavailable'),
  photosMissing('photos_missing'),
  reverifyDevice('reverify_device'),
  vendorUnavailable('vendor_unavailable'),
  failed('');

  const DatingVerifyRefusal(this.wire);

  final String wire;

  static DatingVerifyRefusal of(Object? wire) => values.firstWhere(
    (r) => r != failed && r.wire == wire,
    orElse: () => failed,
  );
}

/// The open, or the last, verification session (never a vendor reference).
class DatingVerifySession {
  const DatingVerifySession({
    required this.id,
    required this.step,
    required this.state,
    this.kind = 'activation',
    this.attempts = 0,
    this.outcome = DatingVerifyOutcome.unknown,
    this.position,
    this.open = false,
    this.gestures = const [],
  });

  final String id;
  final String kind;

  /// 'liveness', 'id' or 'human'.
  final String step;

  /// 'started', 'awaiting_review', 'passed', 'failed' or 'expired'.
  final String state;
  final int attempts;
  final DatingVerifyOutcome outcome;
  final int? position;
  final bool open;
  final List<String> gestures;

  bool get waiting => open && state == 'awaiting_review';

  static DatingVerifySession? fromJson(Object? raw) {
    if (raw is! Map || raw['id'] is! String || raw['step'] is! String) {
      return null;
    }
    final gestures = raw['gestures'];
    return DatingVerifySession(
      id: raw['id'] as String,
      kind: raw['kind'] is String ? raw['kind'] as String : 'activation',
      step: raw['step'] as String,
      state: raw['state'] is String ? raw['state'] as String : 'expired',
      attempts: raw['attempts'] is int ? raw['attempts'] as int : 0,
      outcome: DatingVerifyOutcome.of(raw['outcome']),
      position: raw['position'] is int ? raw['position'] as int : null,
      open: raw['open'] == true,
      gestures:
          gestures is List ? gestures.whereType<String>().toList() : const [],
    );
  }
}

/// One ID document the person's Dating country accepts.
class DatingIdDocument {
  const DatingIdDocument({required this.code, required this.nameKey});

  final String code;
  final String nameKey;
}

/// get_my_dating_verification(): the person's own verification state.
class DatingVerification {
  const DatingVerification({
    this.available = false,
    this.trustedDevice = true,
    this.age = DatingCheck.none,
    this.identity = DatingCheck.none,
    this.session,
    this.idDocuments = const [],
    this.photosReady = false,
  });

  /// Answered when the read itself fails or isn't an object: nothing runs.
  static const unavailable = DatingVerification();

  final bool available;

  /// false: this phone is not trusted (W4b's re-verification).
  final bool trustedDevice;
  final DatingCheck age;
  final DatingCheck identity;
  final DatingVerifySession? session;
  final List<DatingIdDocument> idDocuments;
  final bool photosReady;

  bool get verified => age == DatingCheck.pass && identity == DatingCheck.pass;

  /// A person or the ID vendor is checking (§3.1 'verifying').
  bool get waiting => session?.waiting ?? false;

  factory DatingVerification.fromJson(Object? raw) {
    if (raw is! Map || raw['ok'] != true) return unavailable;
    final docs = raw['id_documents'];
    return DatingVerification(
      available: raw['available'] == true,
      trustedDevice: raw['device'] != 'untrusted',
      age: DatingCheck.of(raw['age']),
      identity: DatingCheck.of(raw['identity']),
      session: DatingVerifySession.fromJson(raw['session']),
      idDocuments: [
        if (docs is List)
          for (final d in docs.whereType<Map>())
            if (d['code'] is String && d['name_key'] is String)
              DatingIdDocument(
                code: d['code'] as String,
                nameKey: d['name_key'] as String,
              ),
      ],
      photosReady: raw['photos_ready'] == true,
    );
  }
}

/// One dating-verification answer: a refusal, or what the step returned.
class DatingVerifyAnswer {
  const DatingVerifyAnswer({
    required this.ok,
    this.refusal,
    this.outcome = DatingVerifyOutcome.unknown,
    this.position,
    this.sessionId,
    this.vendor,
    this.vendorRef,
    this.gestures = const [],
    this.paths = const [],
    this.attempts = 0,
    this.resumed = false,
  });

  static const failed = DatingVerifyAnswer(
    ok: false,
    refusal: DatingVerifyRefusal.failed,
  );

  final bool ok;
  final DatingVerifyRefusal? refusal;
  final DatingVerifyOutcome outcome;
  final int? position;
  final String? sessionId;
  final String? vendor;

  /// The vendor's session or job for the device's capture view (never
  /// shown, never stored on the device).
  final String? vendorRef;
  final List<String> gestures;
  final List<String> paths;
  final int attempts;
  final bool resumed;

  factory DatingVerifyAnswer.fromJson(Object? raw) {
    if (raw is! Map) return failed;
    String? text(String key) => raw[key] is String ? raw[key] as String : null;
    List<String> list(String key) =>
        raw[key] is List
            ? (raw[key] as List).whereType<String>().toList()
            : const [];
    final ok = raw['ok'] == true;
    return DatingVerifyAnswer(
      ok: ok,
      refusal: ok ? null : DatingVerifyRefusal.of(raw['reason']),
      outcome: DatingVerifyOutcome.of(raw['outcome']),
      position: raw['position'] is int ? raw['position'] as int : null,
      sessionId: text('session_id'),
      vendor: text('vendor'),
      vendorRef: text('vendor_session') ?? text('vendor_job'),
      gestures: list('gestures'),
      paths: list('paths'),
      attempts: raw['attempts'] is int ? raw['attempts'] as int : 0,
      resumed: raw['resumed'] == true,
    );
  }
}
```

Create `lib/features/dating/verify/dating_verification_repository.dart` with exactly:

```dart
// Spec 2 W4a (§3.3, §4.7): the verification calls. The status read and the
// biometric consent go through the Dating RPC client; the check steps go
// to the dating-verification edge function; the human route's two photos
// go to the private review bucket under the paths the server named. Every
// call is bounded; a failure answers `failed` (never the error's text).
import 'dart:async';
import 'dart:typed_data';

import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:attune/features/dating/verify/dating_verification.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The policy version the D11 consent records (§3.3.2).
const datingBiometricPolicyVersion = 'dating-verify-1';

/// The human route's private bucket (§3.3.3).
const datingReviewBucket = 'dating-verification-review';

typedef DatingVerifyInvoke =
    Future<Object?> Function(Map<String, Object?> body);
typedef DatingReviewUpload = Future<void> Function(String path, Uint8List jpeg);

abstract class DatingVerificationGateway {
  /// The person's own state; [DatingVerification.unavailable] on a failure.
  Future<DatingVerification> status();

  /// Records the D11 consent (biometric_verification, granted).
  Future<DatingWrite> consent(String key);

  /// One dating-verification action ('start', 'complete', 'start_id',
  /// 'complete_id', 'human_start', 'submit_human').
  Future<DatingVerifyAnswer> act(String action, [Map<String, Object?> body]);

  /// One human-review photo; false when it did not land.
  Future<bool> uploadReviewPhoto(String path, Uint8List jpeg);
}

class DatingVerificationRepository implements DatingVerificationGateway {
  DatingVerificationRepository(this._rpc, this._invoke, this._upload);

  /// Through the Dating-scoped client (its edge calls and uploads carry
  /// the same headers as its RPCs).
  factory DatingVerificationRepository.of(DatingRpc rpc, SupabaseClient c) =>
      DatingVerificationRepository(
        rpc,
        (body) async =>
            (await c.functions.invoke('dating-verification', body: body)).data,
        (path, jpeg) async {
          await c.storage
              .from(datingReviewBucket)
              .uploadBinary(
                path,
                jpeg,
                fileOptions: const FileOptions(
                  contentType: 'image/jpeg',
                  upsert: false,
                ),
              );
        },
      );

  final DatingRpc _rpc;
  final DatingVerifyInvoke _invoke;
  final DatingReviewUpload _upload;

  static const timeout = Duration(seconds: 45);

  @override
  Future<DatingVerification> status() async {
    try {
      return DatingVerification.fromJson(
        await _rpc.call('get_my_dating_verification'),
      );
    } catch (_) {
      return DatingVerification.unavailable;
    }
  }

  @override
  Future<DatingWrite> consent(String key) async {
    try {
      await _rpc.call('record_dating_consent', {
        'p_idempotency_key': key,
        'p_purpose': 'biometric_verification',
        'p_action': 'granted',
        'p_policy_version': datingBiometricPolicyVersion,
        'p_categories': const ['face'],
      });
      return const DatingWrite(ok: true);
    } on DatingBusy {
      return DatingWrite.busy;
    } on PostgrestException catch (e) {
      return e.message == 'reverify_device'
          ? const DatingWrite(ok: false, reason: 'reverify_device')
          : DatingWrite.failed;
    } catch (_) {
      return DatingWrite.failed;
    }
  }

  @override
  Future<DatingVerifyAnswer> act(
    String action, [
    Map<String, Object?> body = const {},
  ]) async {
    try {
      return DatingVerifyAnswer.fromJson(
        await _invoke({...body, 'action': action}).timeout(timeout),
      );
    } catch (_) {
      return DatingVerifyAnswer.failed;
    }
  }

  @override
  Future<bool> uploadReviewPhoto(String path, Uint8List jpeg) async {
    try {
      await _upload(path, jpeg).timeout(timeout);
      return true;
    } catch (_) {
      return false;
    }
  }
}
```

Create `lib/features/dating/verify/dating_verification_providers.dart` with exactly:

```dart
// Spec 2 W4a (D8, C-5): the verification state, one entry per account,
// memory only; the camera is a seam (tests replace it) whose file the flow
// deletes as soon as it is read.
import 'package:attune/features/dating/data/dating_providers.dart';
import 'package:attune/features/dating/data/dating_supabase_client.dart';
import 'package:attune/features/dating/verify/dating_verification.dart';
import 'package:attune/features/dating/verify/dating_verification_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

final datingVerificationGatewayProvider = Provider<DatingVerificationGateway>(
  (ref) => DatingVerificationRepository.of(
    ref.watch(datingRpcProvider),
    ref.watch(datingSupabaseClientProvider),
  ),
);

/// The person's own verification state; the next account's entry starts
/// as a plain loading value, never holding the last one's (D8).
final datingVerificationProvider = FutureProvider.autoDispose
    .family<DatingVerification, String?>((ref, account) async {
      if (account == null) return DatingVerification.unavailable;
      return ref.read(datingVerificationGatewayProvider).status();
    });

/// The human route's camera (§3.3.3: camera only, never the gallery), the
/// front camera, no metadata; its file is deleted by the flow once read.
final datingReviewCameraProvider = Provider<Future<String?> Function()>(
  (ref) =>
      () async =>
          (await ImagePicker().pickImage(
            source: ImageSource.camera,
            preferredCameraDevice: CameraDevice.front,
            requestFullMetadata: false,
          ))?.path,
);
```

Create `lib/features/dating/verify/dating_capture.dart` with exactly:

```dart
// Spec 2 W4a (§3.3.2 "During capture", §3.3.5; R-10, R-11): the capture
// seam. The vendor's capture view runs the video and the ID document; the
// app adds its own prompts, spoken through the screen reader when one is
// on, with a haptic tick unless reduce motion is on. W4a's launcher runs
// the development capture for the fake vendor only (a practice screen that
// plays the prompts and lets a tester pick the fake's scenario); any other
// vendor answers `unavailable` until its native capture view lands with
// the vendor contract (R-10, owner checklist). Nothing here records,
// stores or uploads an image.
import 'dart:async';

import 'package:attune/core/ui/feedback/haptics.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_frame.dart';
import 'package:attune/features/dating/lock/dating_sheets.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum DatingCaptureKind { done, cancelled, unavailable }

class DatingCaptureResult {
  const DatingCaptureResult(this.kind, {this.scenario});

  static const cancelled = DatingCaptureResult(DatingCaptureKind.cancelled);
  static const unavailable = DatingCaptureResult(DatingCaptureKind.unavailable);

  final DatingCaptureKind kind;

  /// The fake's scenario a tester picked (development only).
  final String? scenario;
}

abstract class DatingCaptureLauncher {
  /// The video check for the vendor session [vendorRef].
  Future<DatingCaptureResult> liveness(
    BuildContext context, {
    required String vendor,
    required String vendorRef,
  });

  /// The ID document capture for the vendor job [vendorRef].
  Future<DatingCaptureResult> idDocument(
    BuildContext context, {
    required String vendor,
    required String vendorRef,
  });
}

/// The fake vendor's scenarios the practice screen offers (§3.3.5; the
/// server refuses a scenario outside fake mode).
const datingFakeVideoScenarios = [
  'pass',
  'liveness_fail',
  'under_25',
  'uncertain',
  'far_below',
  'photo_mismatch',
  'vendor_down',
];
const datingFakeIdScenarios = [
  'id_pass',
  'id_fail',
  'id_dob_mismatch',
  'id_minor',
  'id_pending',
];

class DatingDevCaptureLauncher implements DatingCaptureLauncher {
  const DatingDevCaptureLauncher();

  Future<DatingCaptureResult> _practice(
    BuildContext context,
    String vendor,
    List<String> scenarios,
    bool video,
  ) async {
    if (vendor != 'fake') return DatingCaptureResult.unavailable;
    final result = await Navigator.of(context).push<DatingCaptureResult>(
      MaterialPageRoute(
        settings: datingSheetSettings('capture'),
        fullscreenDialog: true,
        builder:
            (_) => DatingSheetTracker(
              child: DatingPracticeCaptureScreen(
                scenarios: scenarios,
                video: video,
              ),
            ),
      ),
    );
    return result ?? DatingCaptureResult.cancelled;
  }

  @override
  Future<DatingCaptureResult> liveness(
    BuildContext context, {
    required String vendor,
    required String vendorRef,
  }) => _practice(context, vendor, datingFakeVideoScenarios, true);

  @override
  Future<DatingCaptureResult> idDocument(
    BuildContext context, {
    required String vendor,
    required String vendorRef,
  }) => _practice(context, vendor, datingFakeIdScenarios, false);
}

final datingCaptureLauncherProvider = Provider<DatingCaptureLauncher>(
  (ref) => const DatingDevCaptureLauncher(),
);

/// Attune's own capture prompts (§3.3.2, §3.15 D11): spoken by the screen
/// reader when one is on (R-10: never twice, so the visible line is not a
/// live region), and a selection tick unless reduce motion is on.
class DatingCaptureVoice {
  const DatingCaptureVoice(this.haptics);

  final Haptics haptics;

  void prompt(BuildContext context, String text) {
    final media = MediaQuery.maybeOf(context);
    if (media?.accessibleNavigation ?? false) {
      SemanticsService.announce(text, Directionality.of(context));
    }
    if (!(media?.disableAnimations ?? false)) haptics.selection();
  }
}

final datingCaptureVoiceProvider = Provider<DatingCaptureVoice>(
  (ref) => DatingCaptureVoice(ref.watch(hapticsProvider)),
);

/// The time between two prompts on the practice screen.
const kDatingPromptGap = Duration(milliseconds: 1200);

/// The development capture (fake vendor only): the three prompts in turn,
/// the scenario the fake will play, Done or Cancel. No camera.
class DatingPracticeCaptureScreen extends ConsumerStatefulWidget {
  const DatingPracticeCaptureScreen({
    super.key,
    required this.scenarios,
    required this.video,
  });

  final List<String> scenarios;
  final bool video;

  @override
  ConsumerState<DatingPracticeCaptureScreen> createState() =>
      _DatingPracticeCaptureScreenState();
}

class _DatingPracticeCaptureScreenState
    extends ConsumerState<DatingPracticeCaptureScreen> {
  int _prompt = -1;
  late String _scenario = widget.scenarios.first;
  Timer? _timer;

  List<String> _prompts(AppLocalizations loc) => [
    loc.dating_capturePromptCloser,
    loc.dating_capturePromptHold,
    loc.dating_capturePromptDone,
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _next());
  }

  void _next() {
    if (!mounted) return;
    final prompts = _prompts(AppLocalizations.of(context)!);
    if (_prompt + 1 >= prompts.length) return;
    setState(() => _prompt++);
    ref.read(datingCaptureVoiceProvider).prompt(context, prompts[_prompt]);
    if (_prompt + 1 < prompts.length) {
      _timer = Timer(kDatingPromptGap, _next);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final prompts = _prompts(loc);
    return FlowFrame(
      title: loc.dating_capturePracticeTitle,
      onBack: () => Navigator.of(context).pop(DatingCaptureResult.cancelled),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _prompt < 0 ? '' : prompts[_prompt],
            key: const ValueKey('dating_capture_prompt'),
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: 16),
          Text(
            loc.dating_capturePracticeBody,
            style: theme.textTheme.bodyMedium,
          ),
          for (final s in widget.scenarios)
            RadioListTile<String>(
              value: s,
              groupValue: _scenario,
              contentPadding: EdgeInsets.zero,
              title: Text(s),
              onChanged: (v) => setState(() => _scenario = v ?? _scenario),
            ),
        ],
      ),
      actions: [
        FlowPrimaryButton(
          label: loc.dating_continue,
          onPressed:
              () => Navigator.of(context).pop(
                DatingCaptureResult(
                  DatingCaptureKind.done,
                  scenario: _scenario,
                ),
              ),
        ),
        FlowTextLink(
          label: loc.dating_captureCancel,
          alignment: AlignmentDirectional.centerStart,
          onPressed:
              () => Navigator.of(context).pop(DatingCaptureResult.cancelled),
        ),
      ],
    );
  }
}
```

- [ ] **Step 3: The copy, the home and the section**

Create `$D/arb_fragment_T3.txt` with exactly:

```text
  "dating_sectionVerifying": "We're checking your video. This usually takes less than a day.",
  "@dating_sectionVerifying": {"description": "Spec 2 §3.1 'verifying' (W4a)."},
  "dating_verifyStatusLink": "See where it is",
  "@dating_verifyStatusLink": {"description": "Spec 2 W4a plan copy: the verifying card's link to the check's status (reviewer list)."},
  "dating_sectionPausedVerification": "Dating is paused until you verify it's you again.",
  "@dating_sectionPausedVerification": {"description": "Spec 2 W4a plan copy (carry 1): paused because an age check was revoked or failed (reviewer list)."},
  "dating_capturePromptCloser": "Move the phone a little closer",
  "@dating_capturePromptCloser": {"description": "Spec 2 §3.3.2 spoken capture prompt."},
  "dating_capturePromptHold": "Hold still",
  "@dating_capturePromptHold": {"description": "Spec 2 §3.3.2 spoken capture prompt."},
  "dating_capturePromptDone": "Done",
  "@dating_capturePromptDone": {"description": "Spec 2 §3.3.2 spoken capture prompt."},
  "dating_capturePracticeTitle": "Practice check",
  "@dating_capturePracticeTitle": {"description": "Spec 2 W4a plan copy: the development-only capture (fake vendor); never in production (R-10)."},
  "dating_capturePracticeBody": "This is a practice check for testing. Nothing is recorded. Pick what the check should answer.",
  "@dating_capturePracticeBody": {"description": "Spec 2 W4a plan copy: development-only (R-10)."},
  "dating_captureCancel": "Cancel",
  "@dating_captureCancel": {"description": "Spec 2 W4a: leaves the capture."}
```

Create `$D/edit_T3.py` with exactly:

```python
# Spec 2 W4a Task 3: the home's 'verifying' state and the 'verification'
# pause reason (carry 1), and the section's cards for both. Exact anchors
# in the formatted W3 files; edits written in dart format style by hand.
import pathlib, sys
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from anchor import edit

edit('lib/features/dating/data/dating_home.dart', [
    ("""  reverifyDevice('reverify_device'),
  restricted('restricted'),""",
     """  reverifyDevice('reverify_device'),
  // Spec 2 W4a (§3.1): a person or the ID vendor is checking.
  verifying('verifying'),
  restricted('restricted'),"""),
    ("""  gates('gates'),
  unknown('');""",
     """  gates('gates'),
  // Spec 2 W4a (carry 1): an age check revoked or failed.
  verification('verification'),
  unknown('');"""),
    ("""      DatingPauseReason.away ||
      DatingPauseReason.accountParked ||
      DatingPauseReason.sameGenderSwitch => false,""",
     """      DatingPauseReason.away ||
      DatingPauseReason.accountParked ||
      DatingPauseReason.sameGenderSwitch ||
      // Spec 2 W4a (carry 1): the check first (resume refuses until then).
      DatingPauseReason.verification => false,"""),
    ("""    DatingHomeState.setupInProgress,
    DatingHomeState.gentleWait,""",
     """    DatingHomeState.setupInProgress,
    DatingHomeState.verifying, // Spec 2 W4a
    DatingHomeState.gentleWait,"""),
], 'T3 home')

edit('lib/features/dating/section/dating_section.dart', [
    ("""      case DatingHomeState.reverifyDevice:
        return _plain(loc, loc.dating_sectionReverify, settings);""",
     """      case DatingHomeState.reverifyDevice:
        return _plain(loc, loc.dating_sectionReverify, settings);
      // Spec 2 W4a (§3.1): the waiting screen of the check (§3.3 status).
      case DatingHomeState.verifying:
        return _SectionCard(
          title: loc.flow_slotDatingTitle,
          lines: [loc.dating_sectionVerifying],
          onTap: () => context.push(DatingPaths.step('verify')),
          children: [
            FlowTextLink(
              label: loc.dating_verifyStatusLink,
              alignment: AlignmentDirectional.centerStart,
              onPressed: () => context.push(DatingPaths.step('verify')),
            ),
            if (settings != null) settings,
          ],
        );"""),
    ("""      DatingPauseReason.away => loc.dating_sectionAway,
      _ => loc.dating_sectionPaused,
    };""",
     """      DatingPauseReason.away => loc.dating_sectionAway,
      // Spec 2 W4a (carry 1): paused until the check passes again.
      DatingPauseReason.verification => loc.dating_sectionPausedVerification,
      _ => loc.dating_sectionPaused,
    };"""),
    ("""        if (canResume)
          FlowPrimaryButton(
            label: loc.dating_resume,""",
     """        // Spec 2 W4a (carry 1): the way back is the check, not Resume.
        if (reason == DatingPauseReason.verification)
          FlowPrimaryButton(
            label: loc.dating_verifyTitle,
            onPressed: () => context.push(DatingPaths.step('verify')),
          ),
        if (canResume)
          FlowPrimaryButton(
            label: loc.dating_resume,"""),
], 'T3 section')

# W3's home test named 'verifying' as an unknown state, and listed the
# states with a profile: W4a adds verifying to both lists.
edit('test/features/dating/data/dating_home_test.dart', [
    ("""      DatingHome.fromJson({'state': 'verifying'}).state,
      DatingHomeState.unavailable,""",
     """      DatingHome.fromJson({'state': 'you_are_in'}).state, // Spec 2 W4a
      DatingHomeState.unavailable,"""),
    ("""    const withProfile = {
      DatingHomeState.setupInProgress,""",
     """    const withProfile = {
      DatingHomeState.setupInProgress,
      DatingHomeState.verifying, // Spec 2 W4a"""),
], 'T3 home test')
```

```bash
D=.superpowers/sdd/2026-11-09-spec2-w4
python3 -I .superpowers/sdd/2026-10-26-spec1-w3/arb_append.py $D/arb_fragment_T3.txt
flutter gen-l10n --arb-dir=lib/i10n --template-arb-file=app_en.arb --output-dir=lib/i10n/generated --output-localization-file=app_localizations.dart --no-synthetic-package > /dev/null 2>&1; echo "gen-l10n exit=$?"
python3 -I $D/edit_T3.py
dart format lib/features/dating/verify test/features/dating/support/dating_verify_fakes.dart test/features/dating/verify
flutter analyze --no-pub lib/features/dating test/features/dating 2>&1 | tail -1
flutter test test/features/dating/verify/dating_verification_data_test.dart test/features/dating/verify/dating_capture_section_test.dart test/features/dating/data/dating_home_test.dart test/features/dating/section 2>&1 | tail -1
```

Expected: `added 9 keys`; `gen-l10n exit=0`; three edit lines (`dating_home.dart`, `dating_section.dart`, `dating_home_test.dart`); `Formatted 7 files (0 changed)` (the blocks above are already formatter output; a changed file means a typo in the copy — compare it with the block); `No issues found!`; `All tests passed!`.

- [ ] **Step 4: Mutants**

Create `$D/mut_T3.py` with exactly:

```python
# Spec 2 W4a Task 3: Dart mutants (dmut.py). Anchors are the formatted text.
C = 'lib/features/dating/verify/dating_capture.dart'
V = 'lib/features/dating/verify/dating_verification.dart'
R = 'lib/features/dating/verify/dating_verification_repository.dart'
H = 'lib/features/dating/data/dating_home.dart'
S = 'lib/features/dating/section/dating_section.dart'
T_DATA = ['test/features/dating/verify/dating_verification_data_test.dart']
T_CAP = ['test/features/dating/verify/dating_capture_section_test.dart']
MUTS = {
 'voice_announces_always': (C, '    if (media?.accessibleNavigation ?? false) {', '    if (true) {', T_CAP),
 'voice_ticks_under_reduce_motion': (C, '    if (!(media?.disableAnimations ?? false)) haptics.selection();', '    haptics.selection();', T_CAP),
 'capture_any_vendor': (C, "    if (vendor != 'fake') return DatingCaptureResult.unavailable;", '', T_CAP),
 'refusal_unknown_is_busy': (V, '    (r) => r != failed && r.wire == wire,\n    orElse: () => failed,', '    (r) => r != failed && r.wire == wire,\n    orElse: () => busy,', T_DATA),
 'untrusted_ignored': (V, "      trustedDevice: raw['device'] != 'untrusted',", '      trustedDevice: true,', T_DATA),
 'consent_wrong_purpose': (R, "        'p_purpose': 'biometric_verification',", "        'p_purpose': 'dating_terms',", T_DATA),
 'verification_pause_resumes': (H, '      DatingPauseReason.verification => false,', '      DatingPauseReason.verification => true,', T_DATA),
 'verifying_no_link': (S, '              label: loc.dating_verifyStatusLink,\n              alignment: AlignmentDirectional.centerStart,\n              onPressed: () => context.push(DatingPaths.step(\'verify\')),',
                      '              label: loc.dating_verifyStatusLink,\n              alignment: AlignmentDirectional.centerStart,\n              onPressed: () {},', T_CAP),
 'verification_pause_plain_line': (S, '      DatingPauseReason.verification => loc.dating_sectionPausedVerification,\n', '', T_CAP),
}
```

```bash
D=.superpowers/sdd/2026-11-09-spec2-w4
python3 -I $D/dmut.py $D/mut_T3.py --check && python3 -I $D/dmut.py $D/mut_T3.py | tee $D/mut_T3.txt | tail -1
```

Expected: `9 anchors OK`; `9/9 killed`. Do not commit; record the tree in the report.

### Task 4: D11's whole flow, the manual passage, and the W4a gate (§3.3.1–§3.3.3, §3.15 row D11, §3.0, §7.2 S1/S5/S16; carries 3, 4; D8; R-10–R-13, R-22, R-25, R-33, R-35)

**Files:**
- Create: `lib/features/dating/verify/verify_flow.dart`, `test/features/dating/verify/verify_flow_test.dart` and `test/features/dating/verify/goldens/d11_{waiting,verified}.{scale1.0,scale1.3,scale2.0,rtl}.png`, `$D/{edit_T4.py, arb_fragment_T4.txt, mut_T4.py}`
- Replace: `lib/features/dating/setup/verify_step.dart` (the W3 shell becomes the flow)
- Modify: `lib/features/dating/setup/dating_list_names.dart` (the three document names), `lib/app/documentations/user_manual/data/dating_mode_docs.dart` (`dating_setup_verify`, carry 4), `test/features/dating/support/dating_shell.dart` (a verification fake, verified by default), `test/features/dating/setup/d11_d13_test.dart` (D11 is the flow now) and its `d11_verify` goldens, the ARB and generated l10n

**Interfaces:**
- Consumes: Task 3's gateway, providers, capture seam and voice; W3's `DatingStepFrame`, `datingPhotosProvider`, `DatingImagePreparer`, `datingOnlineProvider`, `datingRefusalLine`, `DatingPaths`.
- Produces: `DatingVerifyFlow({step, onBack, onDone, onChangePhotos})` (Task 7 adds `reverify`); stages `intro`, `another`, `capture`, `outcome`, `id`, `human`, `waiting`, `verified`; `kDatingVerifiedFade` (400 ms; zero under reduce motion).

- [ ] **Step 1: Write the failing test**

Create `test/features/dating/verify/verify_flow_test.dart` with exactly:

```dart
// Spec 2 W4a (§3.3.2, §3.3.3, §3.15 D11, §7.4; D8; R-10): D11's flow. The
// intro and its consent; the video check and every outcome; the ID route;
// the human route (camera only, temp files deleted); where a resumed or a
// waiting session opens; nothing of one account shown to the next; large
// text, the dark theme, goldens, guidelines; quick exit leaves nothing.
import 'dart:async';
import 'dart:io';

import 'package:attune/app/theme/app_theme.dart';
import 'package:attune/core/device/device_wipe_registry.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_text_field.dart'
    show FlowErrorLine;
import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:attune/features/dating/dating_device_wipes.dart';
import 'package:attune/features/dating/domain/services/dating_image_preparer.dart';
import 'package:attune/features/dating/photos/dating_photos_providers.dart';
import 'package:attune/features/dating/routes/dating_routes.dart';
import 'package:attune/features/dating/verify/dating_capture.dart';
import 'package:attune/features/dating/verify/dating_verification.dart';
import 'package:attune/features/dating/verify/dating_verification_providers.dart';
import 'package:attune/features/dating/verify/verify_flow.dart';
import 'package:attune/features/safety/domain/services/quick_exit_service.dart';
import 'package:attune/features/safety/presentation/widgets/quick_exit_zone.dart';
import 'package:attune/features/stories/data/story_device_wipe.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/flow_harness.dart';
import '../../../helpers/tap_in_reach.dart';
import '../support/dating_shell.dart';
import '../support/dating_verify_fakes.dart';

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

class _Run {
  _Run(this.gateway, this.capture, this.done, this.photos, this.dir);
  final FakeDatingVerificationGateway gateway;
  final FakeCaptureLauncher capture;
  final List<String> done;
  final List<String> photos;
  final Directory dir;
}

const _verified = DatingVerification(
  available: true,
  age: DatingCheck.pass,
  identity: DatingCheck.pass,
);

Future<_Run> _open(
  WidgetTester t, {
  DatingVerification? state,
  bool online = true,
  ThemeData? theme,
  double textScale = 1.0,
  DatingCaptureResult capture = const DatingCaptureResult(
    DatingCaptureKind.done,
  ),
  Future<String?> Function()? camera,
}) async {
  await t.pumpWidget(const SizedBox());
  final dir = Directory.systemTemp.createTempSync('d11');
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  final gateway =
      state == null
          ? FakeDatingVerificationGateway()
          : FakeDatingVerificationGateway(state: state);
  final launcher = FakeCaptureLauncher(result: capture);
  final done = <String>[];
  final photos = <String>[];
  Widget screen() => DatingVerifyFlow(
    step: 'verify',
    onBack: () => done.add('<back>'),
    onDone: () => done.add('done'),
    onChangePhotos: () => photos.add('photos'),
  );
  await pumpFlowScreen(
    t,
    () => theme == null ? screen() : Theme(data: theme, child: screen()),
    textScale: textScale,
    overrides: [
      ...datingShellOverrides(online: online, verification: gateway),
      datingCaptureLauncherProvider.overrideWithValue(launcher),
      datingImagePreparerProvider.overrideWithValue(_Prep(dir)),
      datingReviewCameraProvider.overrideWithValue(
        camera ??
            () async =>
                (File('${dir.path}/cam.jpg')
                  ..writeAsBytesSync(List.filled(10, 2))).path,
      ),
    ],
  );
  await t.pumpAndSettle();
  return _Run(gateway, launcher, done, photos, dir);
}

Future<void> _consentAndStart(WidgetTester t) async {
  await tapInReach(t, find.byKey(const ValueKey('dating_verify_consent')));
  await t.pump();
  await tapInReach(t, find.text('Start video check'));
  await t.pumpAndSettle();
}

/// Real file I/O (the human route) finishes outside the test clock.
Future<void> _settleIo(WidgetTester t, bool Function() until) async {
  final limit = DateTime.now().add(const Duration(seconds: 30));
  while (!until()) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await t.pump();
    if (DateTime.now().isAfter(limit)) fail('_settleIo: never settled');
  }
  await t.pumpAndSettle();
}

bool _shows(String text) => find.text(text).evaluate().isNotEmpty;

void main() {
  group('the intro', () {
    testWidgets('§3.3.2 copy; Start and the other way wait for the consent', (
      t,
    ) async {
      final r = await _open(t);
      for (final text in [
        "Verify it's you",
        'Step 10 of 12',
        "A short video selfie checks that you're a real person, that your "
            "photos are you, and that you're over 18. The video is deleted "
            'at once. We keep only whether it passed.',
        'Face a window or a lamp, not away from it.',
        'Take off sunglasses. Glasses are fine without glare.',
        'Hold the phone at eye level.',
        "This check flashes colours on your screen. If flashing lights "
            "affect you, choose 'Check another way'.",
        'I agree that Attune and its verification partner can use my face '
            'to check my age and match my photos. Nothing is kept after the '
            'check.',
      ]) {
        expect(find.text(text), findsOneWidget, reason: text);
      }
      await tapInReach(t, find.text('Start video check'));
      await tapInReach(t, find.text('Check another way'));
      await t.pumpAndSettle();
      expect(r.gateway.actions, isEmpty, reason: 'nothing without consent');
      expect(r.gateway.consents, isEmpty);
    });

    testWidgets('offline: both wait, and the step says why', (t) async {
      final r = await _open(t, online: false);
      await tapInReach(t, find.byKey(const ValueKey('dating_verify_consent')));
      await t.pump();
      await tapInReach(t, find.text('Start video check'));
      await t.pumpAndSettle();
      expect(r.gateway.actions, isEmpty);
      expect(find.text('Connect to save this answer.'), findsOneWidget);
    });

    testWidgets('unavailable (the flag off, or no read): a calm line and '
        'Try again', (t) async {
      final r = await _open(t, state: DatingVerification.unavailable);
      expect(
        find.text('Checking isn\'t available right now. Try again later.'),
        findsOneWidget,
      );
      r.gateway.state = const DatingVerification(available: true);
      await tapInReach(t, find.text('Try again'));
      await t.pumpAndSettle();
      expect(
        find.text('Checking isn\'t available right now. Try again later.'),
        findsNothing,
      );
    });
  });

  group('the video check', () {
    testWidgets('both pass: the consent once, start, the capture, complete; '
        '"You\'re verified." and Continue moves on', (t) async {
      final r = await _open(t);
      r.gateway.answers['start'] = [datingStarted()];
      r.gateway.answers['complete'] = [
        datingOutcome(DatingVerifyOutcome.verified),
      ];
      r.gateway.onAct = (a) {
        if (a == 'complete') r.gateway.state = _verified;
      };
      await _consentAndStart(t);
      expect(r.gateway.consents.length, 1);
      expect(r.gateway.actionNames, ['start', 'complete']);
      expect(r.gateway.actions.last.$2, {'session_id': datingTestSession});
      expect(r.capture.calls, ['liveness:fake:ref-1']);
      expect(find.text("You're verified."), findsOneWidget);
      await tapInReach(t, find.text('Continue'));
      expect(r.done, ['done']);
    });

    testWidgets('a scenario picked on the practice capture re-arms the '
        'session first', (t) async {
      final r = await _open(
        t,
        capture: const DatingCaptureResult(
          DatingCaptureKind.done,
          scenario: 'under_25',
        ),
      );
      r.gateway.answers['start'] = [datingStarted()];
      r.gateway.answers['complete'] = [
        datingOutcome(DatingVerifyOutcome.needsId),
      ];
      await _consentAndStart(t);
      expect(r.gateway.actionNames, ['start', 'start', 'complete']);
      expect(r.gateway.actions[1].$2, {'scenario': 'under_25'});
      expect(
        find.text(
          "We couldn't confirm your age from the video. That's common for "
          "people under 25. Let's check with your ID instead.",
        ),
        findsOneWidget,
      );
      await tapInReach(t, find.text('Check with my ID'));
      await t.pumpAndSettle();
      expect(find.text('Which ID do you have?'), findsWidgets);
      expect(find.text('Ghana Card'), findsOneWidget);
      expect(find.text('Passport'), findsOneWidget);
    });

    testWidgets('failed once: try again with the tips; twice: another way', (
      t,
    ) async {
      final r = await _open(t);
      r.gateway.answers['start'] = [datingStarted()];
      r.gateway.answers['complete'] = [
        datingOutcome(DatingVerifyOutcome.retry),
        datingOutcome(DatingVerifyOutcome.anotherWay),
      ];
      await _consentAndStart(t);
      expect(find.text("That didn't work. Let's try again."), findsOneWidget);
      expect(find.text('Hold the phone at eye level.'), findsOneWidget);
      await tapInReach(t, find.text('Start video check'));
      await t.pumpAndSettle();
      expect(
        find.text('Still not working? You can check another way.'),
        findsOneWidget,
      );
      expect(find.text('Check with my ID'), findsOneWidget);
      expect(find.text('Ask a person to review it'), findsOneWidget);
      await tapInReach(t, find.text('Try again'));
      await t.pumpAndSettle();
      expect(find.text('Start video check'), findsOneWidget);
    });

    testWidgets('a photo that doesn\'t match: named, and Change that photo '
        'opens D9', (t) async {
      final r = await _open(t);
      r.gateway.answers['start'] = [datingStarted()];
      r.gateway.answers['complete'] = [
        datingOutcome(DatingVerifyOutcome.photoMismatch, position: 2),
      ];
      await _consentAndStart(t);
      expect(
        find.text(
          "Photo 2 doesn't look like the video. Change that photo, or ask a "
          'person to review it.',
        ),
        findsOneWidget,
      );
      await tapInReach(t, find.text('Change that photo'));
      expect(r.photos, ['photos']);
    });

    testWidgets('far below 18: support copy only (Spec 1\'s hold)', (t) async {
      final r = await _open(t);
      r.gateway.answers['start'] = [datingStarted()];
      r.gateway.answers['complete'] = [
        datingOutcome(DatingVerifyOutcome.farBelow),
      ];
      await _consentAndStart(t);
      expect(
        find.text(
          'We need to check a few things on your account. Contact support if '
          'you have questions.',
        ),
        findsOneWidget,
      );
      expect(find.text('Contact support'), findsOneWidget);
      expect(find.text('Start video check'), findsNothing);
    });

    testWidgets('R-13: a failed or an uncertain estimate goes to the ID '
        'check, never an ending', (t) async {
      for (final (outcome, text) in [
        (
          DatingVerifyOutcome.needsId,
          "We couldn't confirm your age from the video. That's common for "
              "people under 25. Let's check with your ID instead.",
        ),
        (
          DatingVerifyOutcome.ageUncertain,
          "The video couldn't confirm your age this time. Let's check with "
              'your ID instead.',
        ),
      ]) {
        final r = await _open(t);
        r.gateway.answers['start'] = [datingStarted()];
        r.gateway.answers['complete'] = [datingOutcome(outcome)];
        await _consentAndStart(t);
        expect(find.text(text), findsOneWidget, reason: '$outcome');
        expect(find.text('Contact support'), findsNothing, reason: '$outcome');
        await tapInReach(t, find.text('Check with my ID'));
        await t.pumpAndSettle();
        expect(find.text('Ghana Card'), findsOneWidget, reason: '$outcome');
      }
    });

    testWidgets('the vendor can\'t answer: "That didn\'t go through. Try '
        'again." and nothing moves; a server\'s text never shows', (t) async {
      final r = await _open(t);
      r.gateway.answers['start'] = [
        datingRefused(DatingVerifyRefusal.vendorUnavailable),
      ];
      await _consentAndStart(t);
      expect(find.text("That didn't go through. Try again."), findsOneWidget);
      expect(find.text('Start video check'), findsOneWidget);
      expect(find.byType(FlowErrorLine), findsNothing, reason: 'calm');
      r.gateway.answers['start'] = [DatingVerifyAnswer.failed];
      await tapInReach(t, find.text('Start video check'));
      await t.pumpAndSettle();
      expect(find.text('Something went wrong. Try again.'), findsOneWidget);
    });

    testWidgets('R-10: no capture for this vendor: unavailable; cancelled: '
        'nothing completes', (t) async {
      final r = await _open(t, capture: DatingCaptureResult.unavailable);
      r.gateway.answers['start'] = [datingStarted(vendor: 'aws_rekognition')];
      await _consentAndStart(t);
      expect(
        find.text('Checking isn\'t available right now. Try again later.'),
        findsOneWidget,
      );
      r.capture.result = DatingCaptureResult.cancelled;
      await tapInReach(t, find.text('Start video check'));
      await t.pumpAndSettle();
      expect(r.gateway.actionNames, ['start', 'start']);
    });

    testWidgets('the consent: a failed record keeps its key, the retry '
        'sends the same one; a reverify answer is calm', (t) async {
      final r = await _open(t);
      r.gateway.consentAnswer = const DatingWrite(ok: false, reason: 'failed');
      await _consentAndStart(t);
      expect(r.gateway.actions, isEmpty);
      await tapInReach(t, find.text('Start video check'));
      await t.pumpAndSettle();
      expect(r.gateway.consents.toSet().length, 1, reason: 'same key');
      r.gateway.consentAnswer = const DatingWrite(
        ok: false,
        reason: 'reverify_device',
      );
      await tapInReach(t, find.text('Start video check'));
      await t.pumpAndSettle();
      expect(
        find.text("Confirm it's you on this phone to see Dating."),
        findsOneWidget,
      );
    });
  });

  group('where the flow opens', () {
    testWidgets('a session left open: "Let\'s pick up where you left off."', (
      t,
    ) async {
      await _open(
        t,
        state: const DatingVerification(
          available: true,
          session: DatingVerifySession(
            id: datingTestSession,
            step: 'liveness',
            state: 'started',
            open: true,
          ),
        ),
      );
      expect(find.text("Let's pick up where you left off."), findsOneWidget);
    });

    testWidgets('a person checking; an ID being checked; a date of birth '
        'that differs; an age not confirmed', (t) async {
      final cases = {
        const DatingVerifySession(
              id: datingTestSession,
              step: 'human',
              state: 'awaiting_review',
              open: true,
            ):
            "A person is checking. This usually takes less than a day. We'll "
            'show the result here.',
        const DatingVerifySession(
              id: datingTestSession,
              step: 'id',
              state: 'awaiting_review',
              outcome: DatingVerifyOutcome.idPending,
              open: true,
            ):
            'Thanks. Most checks finish in a few minutes. Some need a person, '
            'which takes up to 24 hours.',
        const DatingVerifySession(
              id: datingTestSession,
              step: 'id',
              state: 'awaiting_review',
              outcome: DatingVerifyOutcome.dobMismatch,
              open: true,
            ):
            "The date of birth on your ID doesn't match the one you gave us. "
            'A person will check this within 24 hours.',
      };
      for (final MapEntry(key: session, value: text) in cases.entries) {
        await _open(
          t,
          state: DatingVerification(available: true, session: session),
        );
        expect(find.text(text), findsOneWidget, reason: text);
        expect(find.text('Start video check'), findsNothing);
      }
      await _open(
        t,
        state: const DatingVerification(available: true, age: DatingCheck.fail),
      );
      expect(
        find.text(
          "We couldn't confirm your age, so Dating isn't available on this "
          'account. If you think this is wrong, contact support.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('R-13: a video check that ended on the estimate reopens on '
        'the ID offer', (t) async {
      await _open(
        t,
        state: const DatingVerification(
          available: true,
          session: DatingVerifySession(
            id: datingTestSession,
            step: 'liveness',
            state: 'passed',
            outcome: DatingVerifyOutcome.ageUncertain,
          ),
        ),
      );
      expect(
        find.text(
          "The video couldn't confirm your age this time. Let's check with "
          'your ID instead.',
        ),
        findsOneWidget,
      );
      expect(find.text('Check with my ID'), findsOneWidget);
      expect(find.text('Start video check'), findsNothing);
    });

    testWidgets('a pending ID check is read again on Check again', (t) async {
      final r = await _open(
        t,
        state: const DatingVerification(
          available: true,
          session: DatingVerifySession(
            id: datingTestSession,
            step: 'id',
            state: 'awaiting_review',
            outcome: DatingVerifyOutcome.idPending,
            open: true,
          ),
        ),
      );
      r.gateway.answers['complete_id'] = [
        datingOutcome(DatingVerifyOutcome.verified),
      ];
      r.gateway.onAct = (a) => r.gateway.state = _verified;
      await tapInReach(t, find.text('Check again'));
      await t.pumpAndSettle();
      // (A record holding a map compares by identity: one field at a time.)
      expect(r.gateway.actions.single.$1, 'complete_id');
      expect(r.gateway.actions.single.$2, {'session_id': datingTestSession});
      expect(find.text("You're verified."), findsOneWidget);
    });
  });

  group('the ID route', () {
    testWidgets('pick a document, the capture, then the outcome', (t) async {
      final r = await _open(t);
      r.gateway.answers['start_id'] = [datingStarted()];
      r.gateway.answers['complete_id'] = [
        datingOutcome(DatingVerifyOutcome.dobMismatch),
      ];
      await tapInReach(t, find.byKey(const ValueKey('dating_verify_consent')));
      await t.pump();
      await tapInReach(t, find.text('Check another way'));
      await t.pumpAndSettle();
      await tapInReach(t, find.text('Check with my ID'));
      await t.pumpAndSettle();
      await tapInReach(t, find.text('Passport'));
      await t.pump();
      await tapInReach(t, find.text('Continue'));
      await t.pumpAndSettle();
      expect(r.gateway.actions.first.$1, 'start_id');
      expect(r.gateway.actions.first.$2, {'document': 'passport'});
      expect(r.capture.calls, ['id:fake:ref-1']);
      expect(
        find.text(
          "The date of birth on your ID doesn't match the one you gave us. A "
          'person will check this within 24 hours.',
        ),
        findsOneWidget,
      );
      // R-12: once the date is corrected, Check again compares it again.
      r.gateway.answers['complete_id'] = [
        datingOutcome(DatingVerifyOutcome.verified),
      ];
      r.gateway.onAct = (a) {
        if (a == 'complete_id') r.gateway.state = _verified;
      };
      r.gateway.state = const DatingVerification(available: true);
      await tapInReach(t, find.text('Check again'));
      await t.pumpAndSettle();
      expect(r.gateway.actions.last.$1, 'complete_id');
      expect(r.gateway.actions.last.$2, {
        'session_id': datingTestSession,
      }, reason: 'the ID check this screen started');
      expect(find.text("You're verified."), findsOneWidget);
    });
  });

  group('R-13: the only endings', () {
    testWidgets('a failed ID check is final: support copy, nothing to try '
        'again', (t) async {
      final r = await _open(t);
      r.gateway.answers['start_id'] = [datingStarted()];
      r.gateway.answers['complete_id'] = [
        datingOutcome(DatingVerifyOutcome.ageNotConfirmed),
      ];
      await tapInReach(t, find.byKey(const ValueKey('dating_verify_consent')));
      await t.pump();
      await tapInReach(t, find.text('Check another way'));
      await t.pumpAndSettle();
      await tapInReach(t, find.text('Check with my ID'));
      await t.pumpAndSettle();
      await tapInReach(t, find.text('Passport'));
      await t.pump();
      await tapInReach(t, find.text('Continue'));
      await t.pumpAndSettle();
      expect(
        find.text(
          "We couldn't confirm your age, so Dating isn't available on this "
          'account. If you think this is wrong, contact support.',
        ),
        findsOneWidget,
      );
      expect(find.text('Contact support'), findsOneWidget);
      for (final none in [
        'Try again',
        'Start video check',
        'Check with my ID',
        'Check another way',
      ]) {
        expect(find.text(none), findsNothing, reason: none);
      }
    });
  });

  group('the human route (§3.3.3)', () {
    testWidgets('two gestures, two camera photos (temp files deleted), sent '
        'for review', (t) async {
      final r = await _open(t);
      r.gateway.answers['human_start'] = [
        const DatingVerifyAnswer(
          ok: true,
          sessionId: datingTestSession,
          gestures: ['left_ear', 'thumbs_up'],
          paths: ['$datingTestSession/1.jpg', '$datingTestSession/2.jpg'],
        ),
      ];
      r.gateway.answers['submit_human'] = [
        datingOutcome(DatingVerifyOutcome.humanPending),
      ];
      await tapInReach(t, find.byKey(const ValueKey('dating_verify_consent')));
      await t.pump();
      await tapInReach(t, find.text('Check another way'));
      await t.pumpAndSettle();
      await tapInReach(t, find.text('Ask a person to review it'));
      await t.pumpAndSettle();
      expect(find.text('Take two quick photos'), findsWidgets);
      expect(find.text('1. Touch your left ear'), findsOneWidget);
      expect(find.text('2. Give a thumbs up'), findsOneWidget);
      await tapInReach(t, find.text('Send for review'));
      await t.pump();
      expect(r.gateway.actionNames, [
        'human_start',
      ], reason: 'two photos first');
      await tapInReach(t, find.text('Take photo 1'));
      await _settleIo(t, () => r.gateway.uploads.length == 1);
      await tapInReach(t, find.text('Take photo 2'));
      await _settleIo(t, () => r.gateway.uploads.length == 2);
      expect(r.gateway.uploads, [
        '$datingTestSession/1.jpg',
        '$datingTestSession/2.jpg',
      ]);
      expect(r.dir.listSync(), isEmpty, reason: 'every temp file deleted');
      await tapInReach(t, find.text('Send for review'));
      await t.pumpAndSettle();
      expect(r.gateway.actions.last.$1, 'submit_human');
      expect(r.gateway.actions.last.$2, {'session_id': datingTestSession});
      expect(
        find.text(
          "A person is checking. This usually takes less than a day. We'll "
          'show the result here.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('a photo that did not land says so; a cancelled camera '
        'says nothing', (t) async {
      String? next;
      final r = await _open(t, camera: () async => next);
      r.gateway.answers['human_start'] = [
        const DatingVerifyAnswer(
          ok: true,
          sessionId: datingTestSession,
          gestures: ['left_ear', 'thumbs_up'],
          paths: ['a/1.jpg', 'a/2.jpg'],
        ),
      ];
      await tapInReach(t, find.byKey(const ValueKey('dating_verify_consent')));
      await t.pump();
      await tapInReach(t, find.text('Check another way'));
      await t.pumpAndSettle();
      await tapInReach(t, find.text('Ask a person to review it'));
      await t.pumpAndSettle();
      await tapInReach(t, find.text('Take photo 1'));
      await t.pumpAndSettle();
      expect(_shows("That photo didn't go through. Take it again."), isFalse);
      next = (File('${r.dir.path}/cam.jpg')..writeAsBytesSync([1, 2, 3])).path;
      r.gateway.uploadOk = false;
      await tapInReach(t, find.text('Take photo 1'));
      await _settleIo(t, () => r.gateway.uploads.length == 1);
      expect(
        find.text("That photo didn't go through. Take it again."),
        findsOneWidget,
      );
      expect(find.text('Take photo 1'), findsOneWidget);
    });
  });

  testWidgets('D8: another account sees nothing of the last one while its '
      'read is held', (t) async {
    final r = await _open(t);
    r.gateway.answers['start'] = [datingStarted()];
    r.gateway.answers['complete'] = [
      datingOutcome(DatingVerifyOutcome.photoMismatch, position: 2),
    ];
    await _consentAndStart(t);
    expect(find.textContaining('Photo 2'), findsOneWidget);
    r.gateway.hold = Completer<DatingVerification>();
    final c = ProviderScope.containerOf(t.element(find.byType(MaterialApp)));
    c.read(datingTestAccount.notifier).state = 'kofi';
    for (var i = 0; i < 4; i++) {
      await t.pump(const Duration(milliseconds: 40));
      expect(find.textContaining('Photo 2'), findsNothing);
      expect(find.text('Change that photo'), findsNothing);
    }
    r.gateway.hold!.complete(const DatingVerification(available: true));
    await t.pumpAndSettle();
    expect(find.text('Start video check'), findsOneWidget);
    final consent = t.widget<CheckboxListTile>(
      find.byKey(const ValueKey('dating_verify_consent')),
    );
    expect(consent.value, isFalse, reason: 'the consent is per account');
  });

  testWidgets('large text at 2.0: every stage in reach, nothing clipped', (
    t,
  ) async {
    final r = await _open(t, textScale: 2.0);
    r.gateway.answers['start'] = [datingStarted()];
    r.gateway.answers['complete'] = [
      datingOutcome(DatingVerifyOutcome.anotherWay),
    ];
    await _consentAndStart(t);
    expect(t.takeException(), isNull);
    await tapInReach(t, find.text('Ask a person to review it'));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });

  testWidgets('the dark theme: tokens only, contrast holds, the theme\'s '
      'error red', (t) async {
    final semantics = t.ensureSemantics();
    final dark = AppTheme.darkTheme;
    for (final (theme, red) in [
      (dark, dark.colorScheme.error),
      (AppTheme.lightTheme, const Color(0xFFC62828)),
    ]) {
      final r = await _open(t, theme: theme);
      expect(
        t.widget<Scaffold>(find.byType(Scaffold).first).backgroundColor,
        theme.colorScheme.surface,
      );
      await expectFlowGuidelines(t);
      r.gateway.answers['start'] = [DatingVerifyAnswer.failed];
      await _consentAndStart(t);
      final icon = find.descendant(
        of: find.byType(FlowErrorLine),
        matching: find.byType(Icon),
      );
      expect(t.widget<Icon>(icon).color, red);
      await expectFlowGuidelines(t);
    }
    semantics.dispose();
  });

  testWidgets('reduce motion: the verified check appears at once', (t) async {
    t.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    await _open(t, state: _verified);
    final tween = t.widget<TweenAnimationBuilder<double>>(
      find.byKey(const ValueKey('dating_verified_check')),
    );
    expect(tween.duration, Duration.zero);
    t.platformDispatcher.clearAccessibilityFeaturesTestValue();
    await _open(t, state: _verified);
    expect(
      t
          .widget<TweenAnimationBuilder<double>>(
            find.byKey(const ValueKey('dating_verified_check')),
          )
          .duration,
      kDatingVerifiedFade,
    );
  });

  for (final (name, state) in [
    (
      'd11_waiting',
      const DatingVerification(
        available: true,
        session: DatingVerifySession(
          id: datingTestSession,
          step: 'human',
          state: 'awaiting_review',
          open: true,
        ),
      ),
    ),
    ('d11_verified', _verified),
  ]) {
    testWidgets('$name goldens', (t) async {
      await expectFlowGoldens(
        t,
        name,
        () => DatingVerifyFlow(
          step: 'verify',
          onBack: () {},
          onDone: () {},
          onChangePhotos: () {},
        ),
        overrides: datingShellOverrides(
          verification: FakeDatingVerificationGateway(state: state),
        ),
        before: (t) => t.pumpAndSettle(),
      );
    });
  }

  group('quick exit', () {
    setUpAll(() => registerDatingDeviceWipes(DeviceWipeRegistry.instance));
    setUp(() {
      QuickExitService.clearStories = () async {};
      addTearDown(() => QuickExitService.clearStories = clearStoryDeviceCaches);
    });

    testWidgets('from D11 mid-check: the decoy, and nothing of the check '
        'left', (t) async {
      final gateway = FakeDatingVerificationGateway();
      gateway.answers['start'] = [datingStarted()];
      gateway.answers['complete'] = [
        datingOutcome(DatingVerifyOutcome.photoMismatch, position: 2),
      ];
      final s = await pumpDatingShell(
        t,
        initial: DatingPaths.step('verify'),
        locked: true,
        wrap: (router, child) => QuickExitZone(router: router, child: child),
        overrides: [
          datingVerificationGatewayProvider.overrideWithValue(gateway),
          datingCaptureLauncherProvider.overrideWithValue(
            FakeCaptureLauncher(),
          ),
        ],
      );
      await _consentAndStart(t);
      expect(find.textContaining('Photo 2'), findsOneWidget);
      for (var i = 0; i < 3; i++) {
        await t.tap(
          find.byKey(const Key('quick_exit_zone')),
          warnIfMissed: false,
        );
        await t.pump(const Duration(milliseconds: 50));
      }
      await t.pumpAndSettle(const Duration(milliseconds: 400));
      expect(find.text('DECOY'), findsOneWidget);
      expect(find.byType(DatingVerifyFlow, skipOffstage: false), findsNothing);
      expect(find.textContaining('Photo 2', skipOffstage: false), findsNothing);
      expect(s.lock.on, isTrue);
    });
  });
}
```

```bash
flutter test test/features/dating/verify/verify_flow_test.dart 2>&1 | tr '\r' '\n' | grep -m1 -o "Error: Error when reading '[^']*'"
```

Expected: `Error: Error when reading 'lib/features/dating/verify/verify_flow.dart'`.

- [ ] **Step 2: The flow and the step**

Create `lib/features/dating/verify/verify_flow.dart` with exactly:

```dart
// Spec 2 W4a (§3.3.2, §3.3.3, §3.15 D11): D11's whole flow on one route.
// The intro with the consent, the tips and the light warning; the video
// check through the capture seam; every outcome of §3.3.2; the ID route;
// the human route (two camera photos, never the gallery); the waiting
// screens. The flow opens where the person's own state says (a resumed
// session, a review in progress, an outcome to act on). Rules for every
// Dating screen hold: the step frame (offline banner, large text through
// FlowFrame), copy from the ARB only (never a server's or a vendor's
// text), one idempotency key per action settled once its answer is final,
// and nothing of one account shown to the next (D8). Motion: only the one
// "You're verified." check, a 400 ms fade, none under reduce motion.
import 'dart:io';

import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/utils/constants.dart';
import 'package:attune/core/utils/url_launcher_utils.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_text_field.dart'
    show FlowErrorLine;
import 'package:attune/features/dating/data/dating_providers.dart';
import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:attune/features/dating/gentle_wait/gentle_wait_providers.dart'
    show datingOnlineProvider;
import 'package:attune/features/dating/photos/dating_photos_providers.dart'
    show datingImagePreparerProvider;
import 'package:attune/features/dating/setup/dating_list_names.dart';
import 'package:attune/features/dating/setup/dating_step_frame.dart';
import 'package:attune/features/dating/verify/dating_capture.dart';
import 'package:attune/features/dating/verify/dating_verification.dart';
import 'package:attune/features/dating/verify/dating_verification_providers.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What the flow shows.
enum DatingVerifyStage {
  loading,
  intro,
  another,
  outcome,
  idChoose,
  human,
  verified,
}

/// The one "You're verified." check (§3.0, §3.15 D11).
const kDatingVerifiedFade = Duration(milliseconds: 400);

class DatingVerifyFlow extends ConsumerStatefulWidget {
  const DatingVerifyFlow({
    super.key,
    required this.step,
    required this.onBack,
    required this.onDone,
    required this.onChangePhotos,
  });

  /// 'verify' in setup ("Step 10 of 12"); anything else shows no step.
  final String step;
  final VoidCallback onBack;

  /// Both checks passed: D12 in setup, or back to where it was opened.
  final VoidCallback onDone;

  /// "Change that photo" (§3.3.2): D9.
  final VoidCallback onChangePhotos;

  @override
  ConsumerState<DatingVerifyFlow> createState() => _DatingVerifyFlowState();
}

class _DatingVerifyFlowState extends ConsumerState<DatingVerifyFlow> {
  DatingActionKeys _keys = DatingActionKeys();
  DatingVerifyStage _stage = DatingVerifyStage.loading;
  DatingVerification _state = DatingVerification.unavailable;
  DatingVerifyOutcome _outcome = DatingVerifyOutcome.unknown;
  DatingVerifyRefusal? _refusal;
  DatingWrite? _consentRefusal;
  int? _position;
  bool _consent = false;
  bool _consentRecorded = false;
  bool _resumed = false;
  bool _busy = false;
  bool _readFailed = false;
  String? _document;
  String? _humanSession;

  /// The ID check this screen started (Check again reads it).
  String? _idSession;
  List<String> _gestures = const [];
  List<String> _paths = const [];
  final Set<int> _taken = {};
  int? _taking;
  bool _photoFailed = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    ref.listenManual<String?>(datingAccountProvider, (previous, next) {
      if (previous == next || !mounted) return;
      // D8: another account starts from nothing.
      setState(_reset);
      _read();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _read());
  }

  void _reset() {
    _generation++;
    _keys = DatingActionKeys();
    _stage = DatingVerifyStage.loading;
    _state = DatingVerification.unavailable;
    _outcome = DatingVerifyOutcome.unknown;
    _refusal = null;
    _consentRefusal = null;
    _position = null;
    _consent = false;
    _consentRecorded = false;
    _resumed = false;
    _busy = false;
    _readFailed = false;
    _document = null;
    _humanSession = null;
    _idSession = null;
    _gestures = const [];
    _paths = const [];
    _taken.clear();
    _taking = null;
    _photoFailed = false;
  }

  bool _current(int gen, String? account) =>
      mounted &&
      gen == _generation &&
      ref.read(datingAccountProvider) == account;

  /// The person's own state decides where the flow opens.
  Future<void> _read() async {
    final gen = _generation;
    final account = ref.read(datingAccountProvider);
    ref.invalidate(datingVerificationProvider(account));
    DatingVerification v;
    try {
      v = await ref.read(datingVerificationProvider(account).future);
    } catch (_) {
      v = DatingVerification.unavailable;
    }
    if (!_current(gen, account)) return;
    setState(() {
      _state = v;
      _readFailed = !v.available && v.session == null && !v.verified;
      _stage = _stageFor(v);
    });
  }

  DatingVerifyStage _stageFor(DatingVerification v) {
    if (v.verified) return DatingVerifyStage.verified;
    if (v.age == DatingCheck.fail) {
      _outcome = DatingVerifyOutcome.ageNotConfirmed;
      return DatingVerifyStage.outcome;
    }
    final s = v.session;
    if (s != null && s.waiting) {
      _outcome =
          s.step == 'id'
              ? (s.outcome == DatingVerifyOutcome.dobMismatch
                  ? DatingVerifyOutcome.dobMismatch
                  : DatingVerifyOutcome.idPending)
              : DatingVerifyOutcome.humanPending;
      return DatingVerifyStage.outcome;
    }
    if (s != null && !s.open) {
      switch (s.outcome) {
        case DatingVerifyOutcome.photoMismatch:
          _outcome = s.outcome;
          _position = s.position;
          return DatingVerifyStage.outcome;
        case DatingVerifyOutcome.needsId:
        case DatingVerifyOutcome.ageUncertain:
          if (v.age != DatingCheck.pass) {
            _outcome = s.outcome;
            return DatingVerifyStage.outcome;
          }
        case DatingVerifyOutcome.askForId:
          if (v.age != DatingCheck.pass) return DatingVerifyStage.idChoose;
        default:
          break;
      }
    }
    _resumed = s != null && s.open && s.step == 'liveness';
    return DatingVerifyStage.intro;
  }

  Future<bool> _ensureConsent(String? account) async {
    if (_consentRecorded) return true;
    final key = _keys.keyFor('consent', account);
    final w = await ref.read(datingVerificationGatewayProvider).consent(key);
    _keys.settle('consent', reason: w.reason);
    if (!mounted) return false;
    if (!w.ok) {
      setState(() => _consentRefusal = w);
      return false;
    }
    _consentRecorded = true;
    _consentRefusal = null;
    return true;
  }

  /// Runs [body] once (a second tap while busy does nothing), for the
  /// account it started with only.
  Future<void> _run(
    Future<void> Function(int gen, String? account) body,
  ) async {
    if (_busy) return;
    final gen = _generation;
    final account = ref.read(datingAccountProvider);
    setState(() {
      _busy = true;
      _refusal = null;
      _consentRefusal = null;
      _photoFailed = false;
    });
    try {
      await body(gen, account);
    } finally {
      if (_current(gen, account)) setState(() => _busy = false);
    }
  }

  void _show(DatingVerifyAnswer a) {
    if (!a.ok) {
      final r = a.refusal ?? DatingVerifyRefusal.failed;
      if (r == DatingVerifyRefusal.alreadyVerified ||
          r == DatingVerifyRefusal.awaitingReview ||
          r == DatingVerifyRefusal.ageNotConfirmed) {
        _read();
        return;
      }
      setState(() => _refusal = r);
      return;
    }
    setState(() {
      _outcome = a.outcome;
      _position = a.position;
      _stage = switch (a.outcome) {
        DatingVerifyOutcome.verified => DatingVerifyStage.loading,
        DatingVerifyOutcome.retry => DatingVerifyStage.intro,
        _ => DatingVerifyStage.outcome,
      };
    });
    // Verified: read again; the flow shows what is left (or both done).
    if (a.outcome == DatingVerifyOutcome.verified) _read();
  }

  Future<void> _video() => _run((gen, account) async {
    if (!await _ensureConsent(account) || !_current(gen, account)) return;
    final gateway = ref.read(datingVerificationGatewayProvider);
    var started = await gateway.act('start');
    if (!_current(gen, account)) return;
    if (!started.ok || started.sessionId == null || started.vendorRef == null) {
      return _show(started);
    }
    if (!mounted) return;
    final capture = await ref
        .read(datingCaptureLauncherProvider)
        .liveness(
          context,
          vendor: started.vendor ?? '',
          vendorRef: started.vendorRef!,
        );
    if (!_current(gen, account)) return;
    if (capture.kind == DatingCaptureKind.cancelled) return;
    if (capture.kind == DatingCaptureKind.unavailable) {
      return setState(() => _refusal = DatingVerifyRefusal.unavailable);
    }
    if (capture.scenario != null) {
      started = await gateway.act('start', {'scenario': capture.scenario});
      if (!_current(gen, account)) return;
      if (!started.ok) return _show(started);
    }
    final done = await gateway.act('complete', {
      'session_id': started.sessionId,
    });
    if (!_current(gen, account)) return;
    _show(done);
  });

  Future<void> _idStart() => _run((gen, account) async {
    final document = _document;
    if (document == null) return;
    if (!await _ensureConsent(account) || !_current(gen, account)) return;
    final gateway = ref.read(datingVerificationGatewayProvider);
    var started = await gateway.act('start_id', {'document': document});
    if (!_current(gen, account)) return;
    if (!started.ok || started.sessionId == null || started.vendorRef == null) {
      return _show(started);
    }
    if (!mounted) return;
    final capture = await ref
        .read(datingCaptureLauncherProvider)
        .idDocument(
          context,
          vendor: started.vendor ?? '',
          vendorRef: started.vendorRef!,
        );
    if (!_current(gen, account)) return;
    if (capture.kind == DatingCaptureKind.cancelled) return;
    if (capture.kind == DatingCaptureKind.unavailable) {
      return setState(() => _refusal = DatingVerifyRefusal.unavailable);
    }
    if (capture.scenario != null) {
      started = await gateway.act('start_id', {
        'document': document,
        'scenario': capture.scenario,
      });
      if (!_current(gen, account)) return;
      if (!started.ok) return _show(started);
    }
    _idSession = started.sessionId;
    _show(await gateway.act('complete_id', {'session_id': started.sessionId}));
  });

  /// "Check again" on a pending ID check.
  Future<void> _idCheckAgain() => _run((gen, account) async {
    final session = _idSession ?? _state.session?.id ?? '';
    final a = await ref.read(datingVerificationGatewayProvider).act(
      'complete_id',
      {'session_id': session},
    );
    if (!_current(gen, account)) return;
    if (!a.ok && a.refusal == DatingVerifyRefusal.sessionUnavailable) {
      return _read();
    }
    _show(a);
  });

  Future<void> _humanStart() => _run((gen, account) async {
    if (!await _ensureConsent(account) || !_current(gen, account)) return;
    final a = await ref
        .read(datingVerificationGatewayProvider)
        .act('human_start');
    if (!_current(gen, account)) return;
    if (!a.ok ||
        a.sessionId == null ||
        a.gestures.length != 2 ||
        a.paths.length != 2) {
      return _show(a);
    }
    setState(() {
      _humanSession = a.sessionId;
      _gestures = a.gestures;
      _paths = a.paths;
      _taken.clear();
      _stage = DatingVerifyStage.human;
    });
  });

  /// One of the two gesture photos: the camera, prepared, the file
  /// deleted, uploaded under the server's path (§3.3.3, C-5).
  Future<void> _takePhoto(int n) async {
    if (_busy || _taking != null) return;
    final gen = _generation;
    final account = ref.read(datingAccountProvider);
    setState(() {
      _taking = n;
      _photoFailed = false;
    });
    String? picked;
    String? prepared;
    var ok = false;
    var cancelled = false;
    try {
      picked = await ref.read(datingReviewCameraProvider)();
      cancelled = picked == null;
      if (picked != null && _current(gen, account)) {
        final file =
            (await ref.read(datingImagePreparerProvider).prepare(picked)).file;
        prepared = file.path;
        final bytes = await file.readAsBytes();
        await _delete([picked, prepared]);
        picked = prepared = null;
        if (_current(gen, account)) {
          ok = await ref
              .read(datingVerificationGatewayProvider)
              .uploadReviewPhoto(_paths[n - 1], bytes);
        }
      }
    } catch (_) {
      ok = false;
    } finally {
      await _delete([picked, prepared]);
    }
    if (!_current(gen, account)) return;
    setState(() {
      _taking = null;
      if (ok) _taken.add(n);
      _photoFailed = !ok && !cancelled;
    });
  }

  Future<void> _delete(List<String?> paths) async {
    for (final p in paths) {
      if (p == null) continue;
      try {
        final f = File(p);
        if (await f.exists()) await f.delete();
      } catch (_) {
        // Best effort: a temp file the OS clears.
      }
    }
  }

  Future<void> _humanSubmit() => _run((gen, account) async {
    final a = await ref.read(datingVerificationGatewayProvider).act(
      'submit_human',
      {'session_id': _humanSession},
    );
    if (!_current(gen, account)) return;
    _show(a);
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final online = ref.watch(datingOnlineProvider).valueOrNull ?? true;
    return switch (_stage) {
      DatingVerifyStage.loading => _frame(
        loc,
        body: const SizedBox(height: 96),
      ),
      DatingVerifyStage.intro => _intro(loc, online),
      DatingVerifyStage.another => _another(loc, online),
      DatingVerifyStage.outcome => _outcomeScreen(loc, online),
      DatingVerifyStage.idChoose => _idChoose(loc, online),
      DatingVerifyStage.human => _human(loc, online),
      DatingVerifyStage.verified => _verified(loc),
    };
  }

  Widget _frame(
    AppLocalizations loc, {
    String? title,
    required Widget body,
    Widget? primary,
    List<Widget> more = const [],
  }) => DatingStepFrame(
    step: widget.step,
    title: title ?? loc.dating_verifyTitle,
    onBack: widget.onBack,
    body: body,
    primary: primary,
    more: more,
  );

  Widget _text(String text, {TextStyle? style}) =>
      Text(text, style: style ?? Theme.of(context).textTheme.bodyLarge);

  List<Widget> _lines(List<String> lines) => [
    for (final l in lines) ...[_text(l), const SizedBox(height: Spacing.md)],
  ];

  List<Widget> _tips(AppLocalizations loc) => [
    for (final tip in [
      loc.dating_verifyTip1,
      loc.dating_verifyTip2,
      loc.dating_verifyTip3,
    ])
      Padding(
        padding: const EdgeInsets.only(bottom: Spacing.xs),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ExcludeSemantics(child: Text('•  ')),
            Expanded(
              child: _text(tip, style: Theme.of(context).textTheme.bodyMedium),
            ),
          ],
        ),
      ),
  ];

  /// A refusal in words (never the server's): calm for busy and the
  /// vendor, error red otherwise.
  Widget? _refusalLine(AppLocalizations loc) {
    final c = _consentRefusal;
    if (c != null) return datingRefusalLine(loc, c);
    final r = _refusal;
    if (r == null) return null;
    final text = switch (r) {
      DatingVerifyRefusal.vendorUnavailable ||
      DatingVerifyRefusal.sessionUnavailable => loc.dating_verifyNetwork,
      DatingVerifyRefusal.unavailable => loc.dating_verifyUnavailable,
      DatingVerifyRefusal.busy => loc.dating_busy,
      DatingVerifyRefusal.rateLimited => loc.dating_errorRateLimited,
      DatingVerifyRefusal.notEligible => loc.dating_sectionUnavailable,
      DatingVerifyRefusal.reverifyDevice => loc.dating_sectionReverify,
      DatingVerifyRefusal.photosRequired ||
      DatingVerifyRefusal.photosMissing => loc.dating_verifyPhotosFirst,
      _ => loc.dating_errorGeneric,
    };
    final calm =
        r == DatingVerifyRefusal.busy ||
        r == DatingVerifyRefusal.vendorUnavailable ||
        r == DatingVerifyRefusal.sessionUnavailable ||
        r == DatingVerifyRefusal.unavailable ||
        r == DatingVerifyRefusal.reverifyDevice;
    return calm
        ? Semantics(liveRegion: true, child: Text(text))
        : FlowErrorLine(text: text, liveRegion: true);
  }

  Widget _intro(AppLocalizations loc, bool online) {
    final ready = _consent && online && !_busy && _state.available;
    final retry = _outcome == DatingVerifyOutcome.retry;
    final refusal = _refusalLine(loc);
    return _frame(
      loc,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_readFailed) ...[
            Semantics(
              liveRegion: true,
              child: _text(loc.dating_verifyUnavailable),
            ),
            FlowTextLink(
              label: loc.dating_verifyTryAgain,
              alignment: AlignmentDirectional.centerStart,
              onPressed: _read,
            ),
          ],
          if (retry)
            Semantics(liveRegion: true, child: _text(loc.dating_verifyRetry))
          else if (_resumed)
            _text(loc.dating_verifyResume),
          const SizedBox(height: Spacing.md),
          _text(loc.dating_verifyBody),
          const SizedBox(height: Spacing.md),
          ..._tips(loc),
          const SizedBox(height: Spacing.md),
          _text(
            loc.dating_verifyLightWarning,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: Spacing.md),
          CheckboxListTile(
            key: const ValueKey('dating_verify_consent'),
            value: _consent,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(loc.dating_verifyConsent),
            onChanged: (v) => setState(() => _consent = v ?? false),
          ),
          if (refusal != null) refusal,
        ],
      ),
      primary: FlowPrimaryButton(
        label: loc.dating_verifyStart,
        busy: _busy,
        onPressed: ready ? _video : null,
      ),
      more: [
        // §3.15 D11: as prominent as Start.
        FlowSecondaryButton(
          label: loc.dating_verifyAnotherWay,
          onPressed:
              _consent && online && !_busy && _state.available
                  ? () => setState(() {
                    _refusal = null;
                    _stage = DatingVerifyStage.another;
                  })
                  : null,
        ),
      ],
    );
  }

  Widget _another(AppLocalizations loc, bool online) {
    final refusal = _refusalLine(loc);
    return _frame(
      loc,
      title: loc.dating_verifyAnotherWay,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _text(loc.dating_verifyAnotherBody),
          if (refusal != null) refusal,
        ],
      ),
      primary: FlowPrimaryButton(
        label: loc.dating_verifyUseId,
        onPressed:
            online && !_busy
                ? () => setState(() {
                  _refusal = null;
                  _stage = DatingVerifyStage.idChoose;
                })
                : null,
      ),
      more: [
        FlowSecondaryButton(
          label: loc.dating_verifyAskPerson,
          busy: _busy,
          onPressed: online && !_busy ? _humanStart : null,
        ),
      ],
    );
  }

  Widget _outcomeScreen(AppLocalizations loc, bool online) {
    final refusal = _refusalLine(loc);
    final position = _position ?? 1;
    final (
      List<String> lines,
      Widget? primary,
      List<Widget> more,
    ) = switch (_outcome) {
      DatingVerifyOutcome.anotherWay => (
        [loc.dating_verifyStillNotWorking],
        FlowPrimaryButton(
          label: loc.dating_verifyUseId,
          onPressed:
              online && !_busy
                  ? () => setState(() => _stage = DatingVerifyStage.idChoose)
                  : null,
        ),
        [
          FlowSecondaryButton(
            label: loc.dating_verifyAskPerson,
            busy: _busy,
            onPressed: online && !_busy ? _humanStart : null,
          ),
          FlowTextLink(
            label: loc.dating_verifyTryAgain,
            alignment: AlignmentDirectional.centerStart,
            onPressed:
                () => setState(() {
                  _outcome = DatingVerifyOutcome.unknown;
                  _stage = DatingVerifyStage.intro;
                }),
          ),
        ],
      ),
      // R-13 (owner ruling 2026-11-09): an estimate below 25, or one the
      // video couldn't give, never ends the check: the ID route.
      DatingVerifyOutcome.needsId || DatingVerifyOutcome.ageUncertain => (
        [
          _outcome == DatingVerifyOutcome.ageUncertain
              ? loc.dating_verifyUncertain
              : loc.dating_verifyUnder25,
        ],
        FlowPrimaryButton(
          label: loc.dating_verifyUseId,
          onPressed:
              online
                  ? () => setState(() => _stage = DatingVerifyStage.idChoose)
                  : null,
        ),
        const <Widget>[],
      ),
      DatingVerifyOutcome.photoMismatch => (
        [loc.dating_verifyPhotoMismatch(position)],
        FlowPrimaryButton(
          label: loc.dating_verifyChangePhoto,
          onPressed: widget.onChangePhotos,
        ),
        [
          FlowSecondaryButton(
            label: loc.dating_verifyAskPerson,
            busy: _busy,
            onPressed: online && !_busy ? _humanStart : null,
          ),
        ],
      ),
      DatingVerifyOutcome.idPending => (
        [loc.dating_verifyIdThanks],
        FlowPrimaryButton(
          label: loc.dating_verifyCheckAgain,
          busy: _busy,
          onPressed: online && !_busy ? _idCheckAgain : null,
        ),
        const <Widget>[],
      ),
      // R-12: after a correction (Spec 1's path), the vendor's answer is
      // compared again.
      DatingVerifyOutcome.dobMismatch => (
        [loc.dating_verifyDobMismatch],
        FlowPrimaryButton(
          label: loc.dating_verifyCheckAgain,
          busy: _busy,
          onPressed: online && !_busy ? _idCheckAgain : null,
        ),
        const <Widget>[],
      ),
      DatingVerifyOutcome.humanPending => (
        [loc.dating_verifyWaiting],
        null,
        const <Widget>[],
      ),
      DatingVerifyOutcome.farBelow => (
        [loc.dating_verifyFarBelow],
        FlowPrimaryButton(
          label: loc.flow_holdContact,
          onPressed:
              () => UrlLauncherUtils.launchEmail(
                context: context,
                email: AppConstants.supportEmail,
              ),
        ),
        const <Widget>[],
      ),
      DatingVerifyOutcome.ageNotConfirmed => (
        [loc.dating_verifyAgeNotConfirmed],
        FlowPrimaryButton(
          label: loc.flow_holdContact,
          onPressed:
              () => UrlLauncherUtils.launchEmail(
                context: context,
                email: AppConstants.supportEmail,
              ),
        ),
        const <Widget>[],
      ),
      DatingVerifyOutcome.identityFailed => (
        [loc.dating_verifyRetry],
        FlowPrimaryButton(
          label: loc.dating_verifyTryAgain,
          onPressed: () => setState(() => _stage = DatingVerifyStage.intro),
        ),
        const <Widget>[],
      ),
      _ => (
        [loc.dating_verifyNetwork],
        FlowPrimaryButton(
          label: loc.dating_verifyTryAgain,
          onPressed: () {
            setState(() => _stage = DatingVerifyStage.loading);
            _read();
          },
        ),
        const <Widget>[],
      ),
    };
    return _frame(
      loc,
      body: Semantics(
        liveRegion: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [..._lines(lines), if (refusal != null) refusal],
        ),
      ),
      primary: primary,
      more: more,
    );
  }

  Widget _idChoose(AppLocalizations loc, bool online) {
    final refusal = _refusalLine(loc);
    final docs = [
      for (final d in _state.idDocuments)
        if (datingListName(loc, d.nameKey) case final name?) (d.code, name),
    ];
    return _frame(
      loc,
      title: loc.dating_verifyWhichId,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DatingChoiceGroup<String>(
            label: loc.dating_verifyWhichId,
            showLabel: false,
            options: docs,
            value: _document,
            onChanged: (v) => setState(() => _document = v),
          ),
          if (refusal != null) refusal,
        ],
      ),
      primary: FlowPrimaryButton(
        label: loc.dating_continue,
        busy: _busy,
        onPressed: _document != null && online && !_busy ? _idStart : null,
      ),
    );
  }

  Widget _human(AppLocalizations loc, bool online) {
    final refusal = _refusalLine(loc);
    String gesture(String code) => switch (code) {
      'three_fingers' => loc.dating_gestureThreeFingers,
      'left_ear' => loc.dating_gestureLeftEar,
      'thumbs_up' => loc.dating_gestureThumbsUp,
      _ => loc.dating_gestureThumbsUp,
    };
    return _frame(
      loc,
      title: loc.dating_humanTitle,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _text(loc.dating_humanBody),
          const SizedBox(height: Spacing.md),
          for (var n = 1; n <= 2; n++) ...[
            Semantics(
              container: true,
              label: loc.dating_humanPhotoLabel(
                n,
                _taken.contains(n)
                    ? loc.dating_humanDone
                    : loc.dating_humanToDo,
              ),
              child: ExcludeSemantics(
                child: _text(
                  '$n. ${gesture(_gestures[n - 1])}',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
            ),
            const SizedBox(height: Spacing.xs),
            if (_taken.contains(n))
              _text(loc.dating_humanDone)
            else
              FlowSecondaryButton(
                label: loc.dating_humanTake(n),
                busy: _taking == n,
                onPressed:
                    online && _taking == null && !_busy
                        ? () => _takePhoto(n)
                        : null,
              ),
            const SizedBox(height: Spacing.md),
          ],
          if (_photoFailed)
            FlowErrorLine(text: loc.dating_humanPhotoFailed, liveRegion: true),
          if (refusal != null) refusal,
        ],
      ),
      primary: FlowPrimaryButton(
        label: loc.dating_humanSend,
        busy: _busy,
        onPressed: _taken.length == 2 && online && !_busy ? _humanSubmit : null,
      ),
    );
  }

  Widget _verified(AppLocalizations loc) {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return _frame(
      loc,
      body: TweenAnimationBuilder<double>(
        key: const ValueKey('dating_verified_check'),
        tween: Tween(begin: reduce ? 1 : 0, end: 1),
        duration: reduce ? Duration.zero : kDatingVerifiedFade,
        builder:
            (context, opacity, child) =>
                Opacity(opacity: opacity, child: child),
        child: Semantics(
          liveRegion: true,
          child: Row(
            children: [
              Icon(
                Icons.check_circle_outline,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: _text(
                  loc.dating_verifyVerified,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
        ),
      ),
      primary: FlowPrimaryButton(
        label: loc.dating_continue,
        onPressed: widget.onDone,
      ),
    );
  }
}
```

Replace the whole of `lib/features/dating/setup/verify_step.dart` with exactly (formatter style; do not run `dart format` on it):

```dart
// Spec 2 §3.2 D11 (Step 10 of 12): the verification flow (W4a, §3.3).
// Both checks passed: D12 (or back to where it was opened, R-40). "Change
// that photo" opens D9.
import 'package:attune/features/dating/routes/dating_setup_steps.dart';
import 'package:attune/features/dating/verify/verify_flow.dart';
import 'package:flutter/material.dart';

class DatingVerifyStep extends StatelessWidget {
  const DatingVerifyStep({super.key, required this.nav});

  final DatingStepNav nav;

  @override
  Widget build(BuildContext context) => DatingVerifyFlow(
    step: 'verify',
    onBack: nav.back,
    onDone: () => nav.next('preview'),
    onChangePhotos:
        () => nav.next(nav.from == null ? 'photos' : 'photos?from=${nav.from}'),
  );
}
```

- [ ] **Step 3: The copy, the names, the manual, the shell and D11's W3 test**

Create `$D/arb_fragment_T4.txt` with exactly:

```text
  "dating_verifyTip1": "Face a window or a lamp, not away from it.",
  "@dating_verifyTip1": {"description": "Spec 2 §3.3.2 intro tip."},
  "dating_verifyTip2": "Take off sunglasses. Glasses are fine without glare.",
  "@dating_verifyTip2": {"description": "Spec 2 §3.3.2 intro tip."},
  "dating_verifyTip3": "Hold the phone at eye level.",
  "@dating_verifyTip3": {"description": "Spec 2 §3.3.2 intro tip."},
  "dating_verifyLightWarning": "This check flashes colours on your screen. If flashing lights affect you, choose 'Check another way'.",
  "@dating_verifyLightWarning": {"description": "Spec 2 §3.3.2 light warning, before capture."},
  "dating_verifyConsent": "I agree that Attune and its verification partner can use my face to check my age and match my photos. Nothing is kept after the check.",
  "@dating_verifyConsent": {"description": "Spec 2 §3.3.2 required consent (biometric_verification). Owner gate: true only with the vendors' deletion terms (DPIA)."},
  "dating_verifyStart": "Start video check",
  "@dating_verifyStart": {"description": "Spec 2 §3.3.2 primary."},
  "dating_verifyAnotherWay": "Check another way",
  "@dating_verifyAnotherWay": {"description": "Spec 2 §3.3.2 secondary, as prominent as Start (§3.15)."},
  "dating_verifyAnotherBody": "You can check with your ID, or a person can look at two quick photos of you.",
  "@dating_verifyAnotherBody": {"description": "Spec 2 W4a plan copy: the other ways (reviewer list)."},
  "dating_verifyUseId": "Check with my ID",
  "@dating_verifyUseId": {"description": "Spec 2 W4a plan copy (reviewer list)."},
  "dating_verifyAskPerson": "Ask a person to review it",
  "@dating_verifyAskPerson": {"description": "Spec 2 §3.3.2 (photo mismatch) and the human route's entry."},
  "dating_verifyResume": "Let's pick up where you left off.",
  "@dating_verifyResume": {"description": "Spec 2 §3.3.2: a resumed session."},
  "dating_verifyVerified": "You're verified.",
  "@dating_verifyVerified": {"description": "Spec 2 §3.3.2: both checks passed (one 400 ms fade, none under reduce motion)."},
  "dating_verifyRetry": "That didn't work. Let's try again.",
  "@dating_verifyRetry": {"description": "Spec 2 §3.3.2: liveness failed (1st)."},
  "dating_verifyStillNotWorking": "Still not working? You can check another way.",
  "@dating_verifyStillNotWorking": {"description": "Spec 2 §3.3.2: liveness failed (2nd)."},
  "dating_verifyUnder25": "We couldn't confirm your age from the video. That's common for people under 25. Let's check with your ID instead.",
  "@dating_verifyUnder25": {"description": "Spec 2 §3.3.2: estimate below 25."},
  "dating_verifyUncertain": "The video couldn't confirm your age this time. Let's check with your ID instead.",
  "@dating_verifyUncertain": {"description": "Spec 2 §3.3.2 (R-13, owner ruling 2026-11-09; plan copy): the estimate was uncertain or unavailable; the ID route next."},
  "dating_verifyPhotoMismatch": "Photo {n} doesn't look like the video. Change that photo, or ask a person to review it.",
  "@dating_verifyPhotoMismatch": {"description": "Spec 2 §3.3.2.", "placeholders": {"n": {"type": "int"}}},
  "dating_verifyChangePhoto": "Change that photo",
  "@dating_verifyChangePhoto": {"description": "Spec 2 §3.3.2 (photo mismatch): opens D9."},
  "dating_verifyWhichId": "Which ID do you have?",
  "@dating_verifyWhichId": {"description": "Spec 2 §3.3.2 ID route."},
  "dating_verifyIdThanks": "Thanks. Most checks finish in a few minutes. Some need a person, which takes up to 24 hours.",
  "@dating_verifyIdThanks": {"description": "Spec 2 §3.3.2 ID route."},
  "dating_verifyCheckAgain": "Check again",
  "@dating_verifyCheckAgain": {"description": "Spec 2 W4a plan copy: reads a pending ID check again (reviewer list)."},
  "dating_verifyDobMismatch": "The date of birth on your ID doesn't match the one you gave us. A person will check this within 24 hours.",
  "@dating_verifyDobMismatch": {"description": "Spec 2 §3.3.2."},
  "dating_verifyAgeNotConfirmed": "We couldn't confirm your age, so Dating isn't available on this account. If you think this is wrong, contact support.",
  "@dating_verifyAgeNotConfirmed": {"description": "Spec 2 §3.3.2."},
  "dating_verifyFarBelow": "We need to check a few things on your account. Contact support if you have questions.",
  "@dating_verifyFarBelow": {"description": "Spec 2 §3.3.2: far below 18 (Spec 1's age_review hold)."},
  "dating_verifyWaiting": "A person is checking. This usually takes less than a day. We'll show the result here.",
  "@dating_verifyWaiting": {"description": "Spec 2 §3.3.2: waiting for a person."},
  "dating_verifyNetwork": "That didn't go through. Try again.",
  "@dating_verifyNetwork": {"description": "Spec 2 §3.15 D11: the vendor's network failure (no attempt counted)."},
  "dating_verifyTryAgain": "Try again",
  "@dating_verifyTryAgain": {"description": "Spec 2 W4a plan copy."},
  "dating_verifyUnavailable": "Checking isn't available right now. Try again later.",
  "@dating_verifyUnavailable": {"description": "Spec 2 W4a plan copy: the check is switched off or has no capture yet (R-10) (reviewer list)."},
  "dating_verifyPhotosFirst": "Add two photos first, then check it's you.",
  "@dating_verifyPhotosFirst": {"description": "Spec 2 W4a plan copy (reviewer list)."},
  "dating_humanTitle": "Take two quick photos",
  "@dating_humanTitle": {"description": "Spec 2 §3.3.3 human route."},
  "dating_humanBody": "Do each one with your camera. A person checks they're you, then they're deleted.",
  "@dating_humanBody": {"description": "Spec 2 W4a plan copy, §3.3.3 (reviewer list)."},
  "dating_humanTake": "Take photo {n}",
  "@dating_humanTake": {"description": "Spec 2 W4a plan copy.", "placeholders": {"n": {"type": "int"}}},
  "dating_humanPhotoLabel": "Photo {n} of 2, {state}",
  "@dating_humanPhotoLabel": {"description": "Spec 2 W4a: a gesture photo's label for screen readers.", "placeholders": {"n": {"type": "int"}, "state": {"type": "String"}}},
  "dating_humanDone": "Done",
  "@dating_humanDone": {"description": "Spec 2 W4a: a gesture photo taken."},
  "dating_humanToDo": "not taken yet",
  "@dating_humanToDo": {"description": "Spec 2 W4a: a gesture photo not taken (screen readers)."},
  "dating_humanSend": "Send for review",
  "@dating_humanSend": {"description": "Spec 2 W4a plan copy (reviewer list)."},
  "dating_humanPhotoFailed": "That photo didn't go through. Take it again.",
  "@dating_humanPhotoFailed": {"description": "Spec 2 W4a plan copy (reviewer list)."},
  "dating_gestureThreeFingers": "Hold up three fingers next to your face",
  "@dating_gestureThreeFingers": {"description": "Spec 2 §3.3.3 gesture."},
  "dating_gestureLeftEar": "Touch your left ear",
  "@dating_gestureLeftEar": {"description": "Spec 2 §3.3.3 gesture."},
  "dating_gestureThumbsUp": "Give a thumbs up",
  "@dating_gestureThumbsUp": {"description": "Spec 2 §3.3.3 gesture."},
  "dating_id_ghana_card": "Ghana Card",
  "@dating_id_ghana_card": {"description": "Spec 2 §2.2 id_documents (GH)."},
  "dating_id_passport": "Passport",
  "@dating_id_passport": {"description": "Spec 2 §2.2 id_documents."},
  "dating_id_uk_driving_licence": "UK photocard driving licence",
  "@dating_id_uk_driving_licence": {"description": "Spec 2 §2.2 id_documents (GB)."}
```

Create `$D/edit_T4.py` with exactly:

```python
# Spec 2 W4a Task 4: D11 is the flow; the ID documents' names; the manual
# passage (carry 4); every Dating shell test gets a verification fake.
import pathlib, sys
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from anchor import edit

edit('lib/features/dating/setup/dating_list_names.dart', [
    ("""  'dating_denomination_orthodox' => loc.dating_denomination_orthodox,
  _ => null,""",
     """  'dating_denomination_orthodox' => loc.dating_denomination_orthodox,
  // Spec 2 W4a (§2.2 id_documents, §3.3.2 ID route).
  'dating_id_ghana_card' => loc.dating_id_ghana_card,
  'dating_id_passport' => loc.dating_id_passport,
  'dating_id_uk_driving_licence' => loc.dating_id_uk_driving_licence,
  _ => null,""")], 'T4 list names')

edit('lib/app/documentations/user_manual/data/dating_mode_docs.dart', [
    ("""              'Before your first introduction, a short video selfie checks your age and that your photos are you. The video is deleted straight away.',""",
     """              'Before your first introduction, a short video selfie checks that you\\'re a real person, that your photos are you, and that you\\'re over 18. The video is deleted straight away, and Attune keeps only whether the check passed. If the video can\\'t confirm your age, you can check with your ID instead. If the video check doesn\\'t work for you, a person can look at two quick photos to check it\\'s you.',""")],
    'T4 manual (carry 4)')

edit('test/features/dating/support/dating_shell.dart', [
    ("""import 'package:attune/features/safety/data/dating_lock_store.dart';""",
     """import 'package:attune/features/dating/verify/dating_verification.dart';
import 'package:attune/features/dating/verify/dating_verification_providers.dart';
import 'package:attune/features/safety/data/dating_lock_store.dart';"""),
    ("""import 'dating_fakes.dart';""",
     """import 'dating_fakes.dart';
import 'dating_verify_fakes.dart';

/// Spec 2 W4a: both checks passed, so D11 shows "You're verified." and
/// Continue moves on (the W3 tests walk through it).
const datingVerifiedState = DatingVerification(
  available: true,
  age: DatingCheck.pass,
  identity: DatingCheck.pass,
  photosReady: true,
);"""),
    ("""        gentleWaitGatewayProvider.overrideWithValue(wait),
        datingOnlineProvider.overrideWith((ref) => Stream.value(online)),
        ...overrides,""",
     """        gentleWaitGatewayProvider.overrideWithValue(wait),
        datingOnlineProvider.overrideWith((ref) => Stream.value(online)),
        datingVerificationGatewayProvider.overrideWithValue(
          FakeDatingVerificationGateway(state: datingVerifiedState),
        ),
        ...overrides,"""),
    ("""  gentleWaitGatewayProvider.overrideWithValue(wait ?? FakeWait()),
  datingOnlineProvider.overrideWith((ref) => Stream.value(online)),
];""",
     """  gentleWaitGatewayProvider.overrideWithValue(wait ?? FakeWait()),
  datingOnlineProvider.overrideWith((ref) => Stream.value(online)),
  datingVerificationGatewayProvider.overrideWithValue(
    verification ?? FakeDatingVerificationGateway(state: datingVerifiedState),
  ),
];"""),
    ("""  FakeWait? wait,
  bool online = true,
}) => [""",
     """  FakeWait? wait,
  bool online = true,
  DatingVerificationGateway? verification,
}) => ["""),
    ("""import 'package:attune/features/dating/verify/dating_verification.dart';
import 'package:attune/features/dating/verify/dating_verification_providers.dart';""",
     """import 'package:attune/features/dating/verify/dating_verification.dart';
import 'package:attune/features/dating/verify/dating_verification_providers.dart';
import 'package:attune/features/dating/verify/dating_verification_repository.dart';"""),
], 'T4 shell')

edit('test/features/dating/setup/d11_d13_test.dart', [
    ("""  testWidgets('D11 shell: the intro copy, Continue opens the preview (R-26)', (
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
  });""",
     """  // Spec 2 W4a: D11 is the flow (verify_flow_test.dart); here, its intro
  // as step 10, and with both checks passed Continue opens the preview.
  testWidgets('D11: the intro as step 10; verified, Continue opens the '
      'preview', (t) async {
    final n = (steps: <String>[], me: <String>[]);
    await pumpFlowScreen(
      t,
      () => DatingVerifyStep(nav: _nav(n)),
      overrides: datingShellOverrides(
        verification: FakeDatingVerificationGateway(),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text("Verify it's you"), findsOneWidget);
    expect(find.text('Step 10 of 12'), findsOneWidget);
    expect(
      find.textContaining('The video is deleted at once.'),
      findsOneWidget,
    );
    expect(find.text('Start video check'), findsOneWidget);
    await pumpFlowScreen(
      t,
      () => DatingVerifyStep(nav: _nav(n)),
      overrides: datingShellOverrides(),
    );
    await t.pumpAndSettle();
    expect(find.text("You're verified."), findsOneWidget);
    await tapInReach(t, find.text('Continue'));
    expect(n.steps, ['preview']);
  });"""),
    ("""      'd11_verify',
      () => DatingVerifyStep(nav: _nav((steps: <String>[], me: <String>[]))),
      overrides: datingShellOverrides(),""",
     """      'd11_verify',
      () => DatingVerifyStep(nav: _nav((steps: <String>[], me: <String>[]))),
      overrides: datingShellOverrides(
        verification: FakeDatingVerificationGateway(),
      ),"""),
    ("""import '../support/dating_shell.dart';""",
     """import '../support/dating_shell.dart';
import '../support/dating_verify_fakes.dart';"""),
], 'T4 d11 tests')
```

```bash
D=.superpowers/sdd/2026-11-09-spec2-w4
python3 -I .superpowers/sdd/2026-10-26-spec1-w3/arb_append.py $D/arb_fragment_T4.txt
flutter gen-l10n --arb-dir=lib/i10n --template-arb-file=app_en.arb --output-dir=lib/i10n/generated --output-localization-file=app_localizations.dart --no-synthetic-package > /dev/null 2>&1; echo "gen-l10n exit=$?"
python3 -I $D/edit_T4.py
dart format lib/features/dating/verify/verify_flow.dart test/features/dating/verify/verify_flow_test.dart
flutter analyze --no-pub lib/features/dating lib/app/documentations/user_manual/data/dating_mode_docs.dart test/features/dating 2>&1 | tail -1
```

Expected: `added 43 keys`; `gen-l10n exit=0`; four edit lines; `Formatted 2 files (0 changed)`; `No issues found!`.

- [ ] **Step 4: The goldens, the tests, the large-text audit**

```bash
flutter test --update-goldens test/features/dating/verify/verify_flow_test.dart test/features/dating/setup/d11_d13_test.dart 2>&1 | tail -1
flutter test test/features/dating/verify test/features/dating/setup test/features/dating/section test/features/dating/data test/app/documentations 2>&1 | tail -1
python3 scripts/large_text_audit.py --scale 2.0 test/features/dating/verify test/features/dating/setup/d11_d13_test.dart 2>&1 | tail -1
```

Expected: `All tests passed!` twice; goldens written for `d11_waiting` and `d11_verified` (×4) and `d11_verify` (×4, now the flow's intro) — open each `scale2.0.png`: the step counter, the consent, Start and "Check another way" reachable, nothing clipped; `SCALE 2.0: 0 site(s) to fix, 0 listed apart`.

- [ ] **Step 5: Mutants**

Create `$D/mut_T4.py` with exactly:

```python
# Spec 2 W4a Task 4: Dart mutants (dmut.py). Anchors are the formatted text.
F = 'lib/features/dating/verify/verify_flow.dart'
N = 'lib/features/dating/setup/dating_list_names.dart'
T = ['test/features/dating/verify/verify_flow_test.dart']
MUTS = {
 'no_consent_gate': (F, '    final ready = _consent && online && !_busy && _state.available;', '    final ready = online && !_busy && _state.available;', T),
 'scenario_ignored': (F, "    if (capture.scenario != null) {\n      started = await gateway.act('start', {'scenario': capture.scenario});",
                     "    if (false) {\n      started = await gateway.act('start', {'scenario': capture.scenario});", T),
 'd8_no_reset': (F, '      setState(_reset);', '      setState(() {});', T),
 'temp_kept': (F, '        await _delete([picked, prepared]);\n        picked = prepared = null;', '        picked = prepared = null;', T),
 'send_before_two': (F, '        onPressed: _taken.length == 2 && online && !_busy ? _humanSubmit : null,', '        onPressed: online && !_busy ? _humanSubmit : null,', T),
 'fade_under_reduce_motion': (F, '        duration: reduce ? Duration.zero : kDatingVerifiedFade,', '        duration: kDatingVerifiedFade,', T),
 'vendor_red': (F, '        r == DatingVerifyRefusal.vendorUnavailable ||\n', '', T),
 'cancel_is_failure': (F, '      _photoFailed = !ok && !cancelled;', '      _photoFailed = !ok;', T),
 'waiting_shows_intro': (F, '    if (s != null && s.waiting) {', '    if (s != null && s.waiting && s.attempts < 0) {', T),
 'passport_unnamed': (N, "  'dating_id_passport' => loc.dating_id_passport,\n", '', T),
 'idcheck_forgets_session': (F, '    _idSession = started.sessionId;\n', '', T),
 # R-13 (owner ruling 2026-11-09): an estimate never ends the check; a
 # failed ID check does.
 'uncertain_reopens_intro': (F, '        case DatingVerifyOutcome.ageUncertain:\n', '', T),
 'uncertain_is_final': (F, '      DatingVerifyOutcome.needsId || DatingVerifyOutcome.ageUncertain => (',
                        '      DatingVerifyOutcome.needsId => (', T),
 'id_fail_retry': (F, '      DatingVerifyOutcome.ageNotConfirmed => (\n        [loc.dating_verifyAgeNotConfirmed],\n        FlowPrimaryButton(\n          label: loc.flow_holdContact,',
                   '      DatingVerifyOutcome.ageNotConfirmed => (\n        [loc.dating_verifyAgeNotConfirmed],\n        FlowPrimaryButton(\n          label: loc.dating_verifyTryAgain,', T),
}
```

```bash
D=.superpowers/sdd/2026-11-09-spec2-w4
python3 -I $D/dmut.py $D/mut_T4.py --check && python3 -I $D/dmut.py $D/mut_T4.py | tee $D/mut_T4.txt | tail -1
```

Expected: `14 anchors OK`; `14/14 killed`. (A mutant that changes what a golden shows also writes a `failures/` folder beside the goldens; it is git-ignored.)

- [ ] **Step 6: The W4a gate**

```bash
D=.superpowers/sdd/2026-11-09-spec2-w4
$D/suite.sh attune_spec3a > $D/sql-W4a.txt; echo "$(grep -c '^PASS' $D/sql-W4a.txt) PASS, $(grep -c '^FAIL' $D/sql-W4a.txt) FAIL"
diff <(grep '^FAIL' $D/sql-baseline.txt) <(grep '^FAIL' $D/sql-W4a.txt) && echo "no new FAIL"
flutter analyze --no-pub lib test > $D/analyze-W4a.txt 2>&1; tail -1 $D/analyze-W4a.txt
diff <(grep -E '^ *(info|warning|error) ' $D/analyze-baseline.txt | sed -E 's/:[0-9]+:[0-9]+ / /' | sort) <(grep -E '^ *(info|warning|error) ' $D/analyze-W4a.txt | sed -E 's/:[0-9]+:[0-9]+ / /' | sort) && echo "no new issue"
flutter test --reporter compact > $D/flutter-W4a.txt 2>&1; tr '\r' '\n' < $D/flutter-W4a.txt | grep -E '^[0-9:]+ \+[0-9]+' | tail -1
shasum -c .superpowers/sdd/2026-11-04-spec1-w10-accessibility-docs/w10-1.0.sha | grep -vc ': OK$'
shasum -c .superpowers/sdd/2026-11-04-spec1-w9/flag_off.sha | grep -vc ': OK$'
shasum -c .superpowers/sdd/2026-11-07-spec2-w3/latch.sha
flutter test test/architecture/games_untouched_test.dart 2>&1 | tail -1
L=$(grep -A2 'name: Run Deno tests' .github/workflows/tests.yml | grep 'run: deno test' | sed 's/^ *run: //')
(cd supabase/functions && export NO_COLOR=1 && eval "$L" 2>&1 | grep -E '^(ok|FAILED) \|')
```

Expected: `160 PASS, 14 FAIL`; `no new FAIL`; `571 issues found.`; `no new issue`; `+8027: All tests passed!` (the baseline's 7975 and W4a's 52; a known flake outside Dating may fail on a given run: name it); `0`; `0`; `lib/home/home_screen.dart: OK`; `All tests passed!`; `ok | 157 passed | 0 failed`. The race script ran in Task 1 (28 PASS); W4a's later tasks change no SQL. Do not commit; record the tree in the report.

## Batch W4b — trusted devices and re-verification

### Task 5: Migration `dating_v2_trusted_devices`: the real device check, `trust_dating_device`, gate 8, the re-check kind (§4.9 W4b, §3.3.4, §2.1 gate 8, §4.3 `dating_trusted_devices`, §4.4, §7.1, §7.5 mutant 9; S-7, C-6, R15; carries 6, 7, 11; R-14–R-17, R-19, R-20)

**Files:**
- Create: `supabase/migrations/20261109110000_dating_v2_trusted_devices.sql`, `supabase/migrations/20261109110010_dating_v2_trusted_devices_grants.sql`, `$D/{before_w4b/, contract_T5.sql, mig_T5_head.sql, mig_T5_tail.sql, build_mig_T5.py, edit_tests_T5.py, edit_races_T5.py, mut_T5.py}`
- Modify: `supabase/tests/dating_v2_verification_contracts.sql` (sections Q–T), `supabase/tests/{dating_v2_setup,dating_v2_identity,dating_v2_home}_contracts.sql` (the W1c/W3 pass-through checks become "the real check"; the home's reverify pin carries the variant), `supabase/tests/dating_rls_canary.sql`, `supabase/tests/service_role_grants_test.sql`, `scripts/local_pg_grants.sql`, `scripts/concurrency/dating_kill_switch_races.sh`

**Interfaces:**
- Consumes: Task 1's sessions, `private.dating_request_device_hash()`, `begin_dating_verification`, `decide_dating_human_review`, `private.dating_exit_internal`, `get_dating_home()` (their post-W4a live bodies, saved in Step 1); W1c's `dating_require_trusted_device()` callers (every Dating read and writer but the exposure-reducing ones, carry 11); W2's `dating_eligibility(uuid, text)`; W3's `private.dating_setup_guard()`.
- Produces: the W4b SQL interfaces under "Interfaces this plan produces": `dating_require_trusted_device()` reads `unbound` or `trusted` as true and anything else as false, never NULL; `trust_dating_device(p_user, p_device_hash) → {ok:true}` | `{ok:false, reason:'invalid'|'busy'}`; `get_dating_home()` → `{state:'reverify_device', variant:'setup_restart'|'verified'}`; `begin_dating_verification(…, 'reverify', …)` refuses `invalid` without a device or for the ID step, `already_verified` on a trusted phone, `not_eligible` before a passed check; `begin…('activation', …)` on an untrusted phone answers `reverify_device`.

- [ ] **Step 1: Save the post-W4a live bodies**

```bash
D=.superpowers/sdd/2026-11-09-spec2-w4; mkdir -p $D/before_w4b
for sig in 'public.dating_require_trusted_device()' 'public.dating_eligibility(uuid,text)' 'private.dating_setup_guard()' 'public.get_dating_home()' 'public.begin_dating_verification(uuid,text,text,text,text,text)' 'public.decide_dating_human_review(uuid,text,uuid)' 'private.dating_exit_internal(uuid,boolean)'; do
  psql -X -d attune_spec3a -Atc "select pg_get_functiondef('$sig'::regprocedure)" > "$D/before_w4b/$sig.sql"
done
ls $D/before_w4b | wc -l
grep -c 'Spec 2 W4a' "$D/before_w4b/public.get_dating_home().sql"
```

Expected: `7`; a number above `0` (Task 1's migration is applied; if `0`, stop: W4a is not on `attune_spec3a`).

- [ ] **Step 2: Write the failing sections**

Create `$D/contract_T5.sql` with exactly (sections Q–T and their helpers):

```sql
-- =====================================================================
-- W4b (Task 5). The device helpers: [p] calls [p_sql] from the device
-- [p_device] (32 hex characters; NULL: no header).
-- =====================================================================
CREATE FUNCTION pg_temp.call_on(p uuid, p_device text, p_sql text) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
  v jsonb;
BEGIN
  PERFORM set_config('request.headers',
    CASE WHEN p_device IS NULL THEN '{}' ELSE json_build_object('x-attune-device', p_device)::text END, true);
  v := pg_temp.call(p, p_sql);
  PERFORM set_config('request.headers', '', true);
  RETURN v;
END $$;
CREATE FUNCTION pg_temp.err_on(p uuid, p_device text, p_sql text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE
  v text;
BEGIN
  PERFORM set_config('request.headers',
    CASE WHEN p_device IS NULL THEN '{}' ELSE json_build_object('x-attune-device', p_device)::text END, true);
  v := pg_temp.err(p, p_sql);
  PERFORM set_config('request.headers', '', true);
  RETURN v;
END $$;
-- The check itself, for [p] on [p_device] (no client may call it: as the
-- database, with the request's claims and headers set).
CREATE FUNCTION pg_temp.guard_on(p uuid, p_device text) RETURNS boolean LANGUAGE plpgsql AS $$
DECLARE
  v boolean;
BEGIN
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, true);
  PERFORM set_config('request.headers', json_build_object('x-attune-device', p_device)::text, true);
  v := public.dating_require_trusted_device();
  PERFORM set_config('request.jwt.claims', '', true);
  PERFORM set_config('request.headers', '', true);
  RETURN v;
END $$;
-- [p_who]'s setup eligibility, asked in [p]'s request from [p_device].
CREATE FUNCTION pg_temp.elig_on(p uuid, p_device text, p_who uuid) RETURNS text LANGUAGE plpgsql AS $$
DECLARE
  v text;
BEGIN
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, true);
  PERFORM set_config('request.headers', json_build_object('x-attune-device', p_device)::text, true);
  v := public.dating_eligibility(p_who, 'setup');
  PERFORM set_config('request.jwt.claims', '', true);
  PERFORM set_config('request.headers', '', true);
  RETURN v;
END $$;
CREATE FUNCTION pg_temp.dev(p_c text) RETURNS text LANGUAGE sql IMMUTABLE AS $$ SELECT repeat(p_c, 32) $$;
CREATE FUNCTION pg_temp.dev_hash(p_c text) RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT encode(extensions.digest(repeat(p_c, 32), 'sha256'), 'hex');
$$;

-- =====================================================================
-- Q. (§3.3.4, R-16, §7.1, mutant 9; carries 6, 11) Unbound, any device
--    reads; the first setup write binds its device; any other device then
--    reads reverify_device and no data, writes nothing, and the setup
--    starts again there; exposure-reducing writes never ask; leaving
--    unbinds, and the next device's first write binds it.
-- =====================================================================
DO $q$
DECLARE
  v_u constant uuid := pg_temp.person('40');
  v_photo uuid;
  v_got jsonb;
  v text;
BEGIN
  IF pg_temp.call_on(v_u, NULL, 'SELECT public.get_my_dating_profile()') ->> 'ok' IS DISTINCT FROM 'true'
     OR pg_temp.call_on(v_u, pg_temp.dev('b'), 'SELECT public.get_my_dating_profile()') ->> 'ok' IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an unbound person could not read from a device';
  END IF;
  -- D2's write from A binds A, for the setup (no verification yet).
  v_got := pg_temp.call_on(v_u, pg_temp.dev('a'),
    'SELECT public.save_dating_children(''w4b-q-children-01'', false, ''yes'', false, false)');
  IF v_got ->> 'ok' IS DISTINCT FROM 'true'
     OR (SELECT count(*) FROM public.dating_trusted_devices WHERE user_id = v_u) <> 1
     OR (SELECT verified_at FROM public.dating_trusted_devices WHERE user_id = v_u AND device_hash = pg_temp.dev_hash('a')) IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the first setup write did not bind its device for the setup: %', v_got;
  END IF;
  -- From B (and with no header): reverify_device, no data, no write.
  v_got := jsonb_build_array(
    pg_temp.call_on(v_u, pg_temp.dev('b'), 'SELECT public.get_my_dating_profile()'),
    pg_temp.call_on(v_u, pg_temp.dev('b'), 'SELECT public.get_dating_setup_lists()'),
    pg_temp.call_on(v_u, pg_temp.dev('b'), 'SELECT public.list_dating_profile_photos()'),
    pg_temp.call_on(v_u, pg_temp.dev('b'), 'SELECT public.save_dating_children(''w4b-q-children-02'', true, ''no'', false, false)'),
    pg_temp.call_on(v_u, NULL, 'SELECT public.get_my_dating_profile()'),
    pg_temp.call_on(v_u, pg_temp.dev('b'), 'SELECT public.get_dating_home()') - 'has_data');
  IF v_got IS DISTINCT FROM '[{"ok": false, "reason": "reverify_device"}, {"ok": false, "reason": "reverify_device"},
      {"ok": false, "reason": "reverify_device"}, {"ok": false, "reason": "reverify_device"},
      {"ok": false, "reason": "reverify_device"}, {"state": "reverify_device", "variant": "setup_restart"}]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: another device read or wrote: %', v_got;
  END IF;
  IF (SELECT children_have FROM public.dating_profiles WHERE user_id = v_u) IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: another device''s write landed';
  END IF;
  v := jsonb_build_array(
    pg_temp.err_on(v_u, pg_temp.dev('b'), 'SELECT public.activate_dating_profile(''w4b-q-activate-1'')'),
    pg_temp.err_on(v_u, pg_temp.dev('b'), 'SELECT public.begin_dating_enrollment(''2'', ''w4b-q-begin-0001'')'),
    pg_temp.err_on(v_u, pg_temp.dev('b'),
      'SELECT public.record_dating_consent(''w4b-q-consent-1'', ''dating_terms'', ''granted'', ''dating-2.0'', ''[]'')'))::text;
  IF v IS DISTINCT FROM '["22023:reverify_device", "22023:reverify_device", "22023:reverify_device"]' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a raising writer let another device through (a NULL check?): %', v;
  END IF;
  -- A still works; the check never answers NULL.
  IF pg_temp.call_on(v_u, pg_temp.dev('a'), 'SELECT public.get_my_dating_profile()') ->> 'ok' IS DISTINCT FROM 'true'
     OR pg_temp.guard_on(v_u, pg_temp.dev('b')) IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the bound device was refused, or the check answered NULL';
  END IF;
  -- Carry 11: exposure-reducing writes from B (never gated).
  SELECT id INTO v_photo FROM public.dating_profile_photos WHERE user_id = v_u AND position = 2;
  INSERT INTO public.dating_notify_requests (user_id, country_code) VALUES (v_u, 'NG');
  INSERT INTO public.dating_gentle_wait_reflections (user_id, answers, saved_at) VALUES (v_u, '{"q1": "a note"}', now());
  v_got := jsonb_build_array(
    pg_temp.call_on(v_u, pg_temp.dev('b'), 'SELECT public.cancel_dating_country_notice()') ->> 'ok',
    pg_temp.call_on(v_u, pg_temp.dev('b'), 'SELECT public.save_gentle_wait_reflection(''{}'')') ->> 'ok',
    pg_temp.call_on(v_u, pg_temp.dev('b'), format('SELECT public.delete_dating_profile_photo(%L)', v_photo)) ->> 'ok',
    pg_temp.call_on(v_u, pg_temp.dev('b'), 'SELECT public.clear_dating_faith(''w4b-q-faith-0001'')') ->> 'ok');
  IF v_got IS DISTINCT FROM '["true", "true", "true", "true"]'::jsonb
     OR EXISTS (SELECT 1 FROM public.dating_profile_photos WHERE id = v_photo)
     OR EXISTS (SELECT 1 FROM public.dating_notify_requests WHERE user_id = v_u) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an exposure-reducing write was refused on another device: %', v_got;
  END IF;
  -- Leaving from B (setup_restart's Start again): every device unbound;
  -- B's next setup write binds B. R-32 (owner ruling 2026-11-09): Start
  -- again keeps the 'Never introduce me' list, as exit does when its box is
  -- ticked; a later Leave can still delete it.
  INSERT INTO public.dating_never_introduce (owner_user_id, phone_hmac, last_two) VALUES (v_u, pg_temp.dev_hash('e'), '07');
  PERFORM pg_temp.call_on(v_u, pg_temp.dev('b'), 'SELECT to_jsonb(public.exit_dating_mode(''w4b-q-exit-00001'', true))');
  IF EXISTS (SELECT 1 FROM public.dating_trusted_devices WHERE user_id = v_u) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: leaving kept a trusted device';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.dating_never_introduce WHERE owner_user_id = v_u) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: Start again on a new phone lost the never-introduce list';
  END IF;
  INSERT INTO public.dating_profiles (user_id, display_name, country_code, region_code) VALUES (v_u, 'Verify', 'GB', 'TLI')
  ON CONFLICT (user_id) DO NOTHING;
  PERFORM pg_temp.call_on(v_u, pg_temp.dev('b'),
    'SELECT public.save_dating_children(''w4b-q-children-03'', false, ''open'', false, false)');
  IF (SELECT array_agg(device_hash) FROM public.dating_trusted_devices WHERE user_id = v_u) IS DISTINCT FROM ARRAY[pg_temp.dev_hash('b')] THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: after leaving, the next device''s first write did not bind it';
  END IF;
  PERFORM pg_temp.call_on(v_u, pg_temp.dev('b'), 'SELECT to_jsonb(public.exit_dating_mode(''w4b-q-exit-00002'', false))');
  IF EXISTS (SELECT 1 FROM public.dating_never_introduce WHERE owner_user_id = v_u) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a later Leave could not delete the kept list';
  END IF;
END $q$;

-- =====================================================================
-- R. (§3.3.4) After a passed check: another device needs a video check
--    ('verified'); up to 3 trusted devices (the least recently used goes);
--    one unused for 180 days no longer counts; seen again at most once a
--    day.
-- =====================================================================
DO $r$
DECLARE
  v_u constant uuid := pg_temp.person('41');
  v_seen timestamptz;
BEGIN
  IF public.trust_dating_device(v_u, 'nothex') IS DISTINCT FROM '{"ok": false, "reason": "invalid"}'::jsonb
     OR has_function_privilege('authenticated', 'public.trust_dating_device(uuid,text)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.trust_dating_device(uuid,text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: trust_dating_device takes bad input or is a client''s';
  END IF;
  PERFORM public.trust_dating_device(v_u, pg_temp.dev_hash('a'));
  UPDATE public.dating_trusted_devices SET last_seen_at = now() - interval '3 days' WHERE user_id = v_u;
  IF pg_temp.call_on(v_u, pg_temp.dev('b'), 'SELECT public.get_dating_home()') ->> 'variant' IS DISTINCT FROM 'verified' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a verified person''s new device is not asked for a video check';
  END IF;
  PERFORM public.trust_dating_device(v_u, pg_temp.dev_hash(c)) FROM unnest(ARRAY['b', 'c', 'd']) AS c;
  IF (SELECT array_agg(device_hash ORDER BY device_hash) FROM public.dating_trusted_devices WHERE user_id = v_u)
       IS DISTINCT FROM (SELECT array_agg(pg_temp.dev_hash(c) ORDER BY pg_temp.dev_hash(c)) FROM unnest(ARRAY['b', 'c', 'd']) AS c) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: more than 3 devices, or not the least recently used one dropped';
  END IF;
  -- Seen again: once a day at most.
  UPDATE public.dating_trusted_devices SET last_seen_at = now() - interval '2 days' WHERE user_id = v_u AND device_hash = pg_temp.dev_hash('b');
  PERFORM pg_temp.call_on(v_u, pg_temp.dev('b'), 'SELECT public.get_my_dating_profile()');
  SELECT last_seen_at INTO v_seen FROM public.dating_trusted_devices WHERE user_id = v_u AND device_hash = pg_temp.dev_hash('b');
  UPDATE public.dating_trusted_devices SET last_seen_at = now() - interval '2 hours' WHERE user_id = v_u AND device_hash = pg_temp.dev_hash('b');
  PERFORM pg_temp.call_on(v_u, pg_temp.dev('b'), 'SELECT public.get_my_dating_profile()');
  IF v_seen < now() - interval '1 minute'
     OR (SELECT last_seen_at FROM public.dating_trusted_devices WHERE user_id = v_u AND device_hash = pg_temp.dev_hash('b'))
          > now() - interval '1 hour' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a trusted device''s last use is not kept once a day';
  END IF;
  -- Unused for 180 days: no longer trusted.
  UPDATE public.dating_trusted_devices SET last_seen_at = now() - interval '181 days' WHERE user_id = v_u AND device_hash = pg_temp.dev_hash('c');
  IF pg_temp.call_on(v_u, pg_temp.dev('c'), 'SELECT public.get_my_dating_profile()') ->> 'reason' IS DISTINCT FROM 'reverify_device' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a device unused for 180 days is still trusted';
  END IF;
END $r$;

-- =====================================================================
-- S. (§2.1 gate 8, R-17) The person's own request from an untrusted
--    device fails gate 8; nobody else's check (a cron, another person's
--    request) reads a device.
-- =====================================================================
DO $s$
DECLARE
  v_u constant uuid := pg_temp.person('42');
  v_x constant uuid := pg_temp.person('43');
BEGIN
  PERFORM public.trust_dating_device(v_u, pg_temp.dev_hash('a'));
  IF pg_temp.elig_on(v_u, pg_temp.dev('b'), v_u) IS DISTINCT FROM 'reverify_device'
     OR pg_temp.elig_on(v_u, pg_temp.dev('a'), v_u) IS DISTINCT FROM 'eligible' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: gate 8 does not read the caller''s own device';
  END IF;
  IF public.dating_eligibility(v_u, 'setup') IS DISTINCT FROM 'eligible'
     OR pg_temp.elig_on(v_x, pg_temp.dev('b'), v_u) IS DISTINCT FROM 'eligible' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: gate 8 read a device for someone else''s check';
  END IF;
END $s$;

-- =====================================================================
-- T. (§3.3.4) The re-check: only on an untrusted device, only after a
--    passed identity check, never without the device or through an ID; the
--    first check never on an untrusted device; a person's pass on a
--    re-check trusts the device it ran on.
-- =====================================================================
DO $t$
DECLARE
  v_u constant uuid := pg_temp.person('44');
  v_got jsonb;
  v_s uuid;
BEGIN
  PERFORM public.trust_dating_device(v_u, pg_temp.dev_hash('a'));
  v_got := jsonb_build_array(
    public.begin_dating_verification(v_u, 'reverify', 'liveness', 'fake', NULL, NULL),
    public.begin_dating_verification(v_u, 'reverify', 'id', 'fake', pg_temp.dev_hash('b'), 'passport'),
    public.begin_dating_verification(v_u, 'reverify', 'liveness', 'fake', pg_temp.dev_hash('a'), NULL),
    public.begin_dating_verification(v_u, 'reverify', 'liveness', 'fake', pg_temp.dev_hash('b'), NULL),
    public.begin_dating_verification(v_u, 'activation', 'liveness', 'fake', pg_temp.dev_hash('b'), NULL));
  IF v_got IS DISTINCT FROM '[{"ok": false, "reason": "invalid"}, {"ok": false, "reason": "invalid"},
      {"ok": false, "reason": "already_verified"}, {"ok": false, "reason": "not_eligible"},
      {"ok": false, "reason": "reverify_device"}]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the re-check began wrongly: %', v_got;
  END IF;
  PERFORM public.record_dating_identity_check(v_u, 'liveness_compare', 'pass', 'fake', NULL);
  v_s := (public.begin_dating_verification(v_u, 'reverify', 'human', 'attune', pg_temp.dev_hash('b'), NULL) ->> 'session_id')::uuid;
  IF v_s IS NULL OR (SELECT kind || '/' || device_hash FROM public.dating_verification_sessions WHERE id = v_s)
                       IS DISTINCT FROM 'reverify/' || pg_temp.dev_hash('b') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the re-check session is not for this device';
  END IF;
  INSERT INTO storage.objects (bucket_id, name, owner) VALUES
    ('dating-verification-review', v_s || '/1.jpg', v_u), ('dating-verification-review', v_s || '/2.jpg', v_u);
  PERFORM public.submit_dating_human_review(v_u, v_s);
  -- The untrusted device reads only its own re-check.
  IF pg_temp.call_on(v_u, pg_temp.dev('b'), 'SELECT public.get_my_dating_verification()') #>> '{session,id}' IS DISTINCT FROM v_s::text
     OR pg_temp.call_on(v_u, pg_temp.dev('c'), 'SELECT public.get_my_dating_verification()') -> 'session' IS DISTINCT FROM 'null'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a device read a re-check that is not its own';
  END IF;
  PERFORM public.decide_dating_human_review(v_s, 'pass', pg_temp.id('99'));
  IF pg_temp.call_on(v_u, pg_temp.dev('b'), 'SELECT public.get_my_dating_profile()') ->> 'ok' IS DISTINCT FROM 'true'
     OR (SELECT verified_at FROM public.dating_trusted_devices WHERE user_id = v_u AND device_hash = pg_temp.dev_hash('b')) IS NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a person''s pass on a re-check did not trust the device';
  END IF;
  -- A stranger's failed re-check on yet another phone never unverifies
  -- the owner (the account's own result is not the re-check's to write).
  v_s := (public.begin_dating_verification(v_u, 'reverify', 'human', 'attune', pg_temp.dev_hash('c'), NULL) ->> 'session_id')::uuid;
  INSERT INTO storage.objects (bucket_id, name, owner) VALUES
    ('dating-verification-review', v_s || '/1.jpg', v_u), ('dating-verification-review', v_s || '/2.jpg', v_u);
  PERFORM public.submit_dating_human_review(v_u, v_s);
  PERFORM public.decide_dating_human_review(v_s, 'fail', pg_temp.id('99'));
  IF (SELECT identity_result FROM public.dating_age_verifications WHERE user_id = v_u) IS DISTINCT FROM 'pass'
     OR (SELECT verification_state FROM public.dating_profiles WHERE user_id = v_u) IS DISTINCT FROM 'verified'
     OR EXISTS (SELECT 1 FROM public.dating_trusted_devices WHERE user_id = v_u AND device_hash = pg_temp.dev_hash('c')) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a failed re-check changed the owner''s result or trusted the phone';
  END IF;
END $t$;

```

```bash
D=.superpowers/sdd/2026-11-09-spec2-w4
python3 -I - <<'PY'
import pathlib
p = pathlib.Path('supabase/tests/dating_v2_verification_contracts.sql')
s = p.read_text()
end = "DO $$ BEGIN RAISE NOTICE 'dating_v2_verification_contracts: all held'; END $$;\nROLLBACK;\n"
assert s.count(end) == 1 and s.endswith(end)
block = pathlib.Path('.superpowers/sdd/2026-11-09-spec2-w4/contract_T5.sql').read_text()
p.write_text(s[:-len(end)] + block + end)
print('sections Q-T inserted')
PY
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/dating_v2_verification_contracts.sql 2>&1 | grep -m1 ERROR
```

Expected: `sections Q-T inserted`; `psql:supabase/tests/dating_v2_verification_contracts.sql:979: ERROR:  relation "public.dating_trusted_devices" does not exist` (section Q's fixture).

- [ ] **Step 3: The migration's new objects, its builder, its twin**

Create `$D/mig_T5_head.sql` with exactly (sections 1–7 and section 8's heading):

```sql
-- Spec 2 W4b, migration 1 (§4.9 W4b; §3.3.4; §2.1 gate 8; §4.3
-- dating_trusted_devices; §4.4 dating_require_trusted_device,
-- trust_dating_device; S-7, C-6; R15; plan R-15..R-20): trusted devices.
-- A person with no device yet is unbound (nothing of theirs is tied to a
-- phone): the device of the first setup write is trusted for the setup
-- (R-16); the device that passes D11 is trusted (verified); any other
-- device reads reverify_device and no Dating data, until a liveness and
-- CompareFaces check (no age estimate) or a person trusts it. Up to 3
-- devices; one unused for 180 days no longer counts. Exposure-reducing
-- writes never ask (carry 11). Re-created from their live bodies (changed
-- lines marked -- Spec 2 W4b): dating_require_trusted_device (the real
-- check), dating_eligibility (gate 8, for the caller's own requests only:
-- R-17), private.dating_setup_guard (binds the first device),
-- get_dating_home (the reverify variant), begin_dating_verification (the
-- reverify kind), decide_dating_human_review (a person's pass trusts the
-- device), private.dating_exit_internal (the devices go).
-- Grants in 20261109110010_dating_v2_trusted_devices_grants.sql.
BEGIN;
SET LOCAL lock_timeout = '5s';

-- 1. The devices: a hash of the install's random id, never the id (§3.3.4).
CREATE TABLE IF NOT EXISTS public.dating_trusted_devices (
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  device_hash text NOT NULL CHECK (device_hash ~ '^[0-9a-f]{64}$'),
  -- NULL: trusted for the setup only (R-16); set: passed a check here.
  verified_at timestamptz,
  last_seen_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, device_hash)
);
ALTER TABLE public.dating_trusted_devices ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.dating_trusted_devices FROM PUBLIC, anon, authenticated, service_role;

-- 2. A device's standing for a person: unbound (no device yet), trusted
--    (this one, used in the last 180 days) or untrusted (any other, or
--    none named). NULL never counts as trusted.
CREATE OR REPLACE FUNCTION private.dating_device_state(p_user uuid, p_hash text)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT CASE
    WHEN p_user IS NULL THEN 'untrusted'
    WHEN NOT EXISTS (SELECT 1 FROM public.dating_trusted_devices AS d WHERE d.user_id = p_user) THEN 'unbound'
    WHEN p_hash IS NOT NULL AND EXISTS (SELECT 1 FROM public.dating_trusted_devices AS d
                                         WHERE d.user_id = p_user AND d.device_hash = p_hash
                                           AND d.last_seen_at > now() - interval '180 days') THEN 'trusted'
    ELSE 'untrusted'
  END;
$$;

-- 3. A trusted device seen again: at most one write a day, never waiting
--    and never failing the read it runs in (best effort).
CREATE OR REPLACE FUNCTION private.dating_touch_device(p_user uuid, p_hash text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
SET lock_timeout = '200ms'
AS $$
BEGIN
  UPDATE public.dating_trusted_devices AS d SET last_seen_at = now()
   WHERE d.user_id = p_user AND d.device_hash = p_hash AND d.last_seen_at < now() - interval '1 day';
EXCEPTION WHEN OTHERS THEN
  NULL;
END;
$$;

-- 4. The first setup write's device (R-16), under the caller's setup lock.
CREATE OR REPLACE FUNCTION private.dating_bind_setup_device(p_user uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_hash constant text := private.dating_request_device_hash();
BEGIN
  IF p_user IS NULL OR v_hash IS NULL
     OR EXISTS (SELECT 1 FROM public.dating_trusted_devices AS d WHERE d.user_id = p_user) THEN
    RETURN;
  END IF;
  INSERT INTO public.dating_trusted_devices (user_id, device_hash) VALUES (p_user, v_hash)
  ON CONFLICT (user_id, device_hash) DO NOTHING;
END;
$$;

-- 5. A device that passed a check (service role: dating-verification, the
--    review decision): trusted, and at most 3 kept (the least recently
--    used go first, never the one just trusted).
CREATE OR REPLACE FUNCTION public.trust_dating_device(p_user uuid, p_device_hash text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
SET lock_timeout = '2s'
AS $$
DECLARE
  v_try integer;
BEGIN
  IF p_user IS NULL OR coalesce(p_device_hash ~ '^[0-9a-f]{64}$', false) IS NOT TRUE THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'invalid');
  END IF;
  FOR v_try IN 1..3 LOOP
    BEGIN
      PERFORM private.dating_lock_setup(p_user);
      IF NOT EXISTS (SELECT 1 FROM public.users AS u WHERE u.id = p_user) THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'not_eligible');
      END IF;
      INSERT INTO public.dating_trusted_devices AS d (user_id, device_hash, verified_at, last_seen_at)
      VALUES (p_user, p_device_hash, now(), now())
      ON CONFLICT (user_id, device_hash) DO UPDATE SET verified_at = now(), last_seen_at = now();
      DELETE FROM public.dating_trusted_devices AS d
       WHERE d.user_id = p_user AND d.device_hash <> p_device_hash
         AND d.device_hash NOT IN (SELECT k.device_hash FROM public.dating_trusted_devices AS k
                                    WHERE k.user_id = p_user AND k.device_hash <> p_device_hash
                                    ORDER BY k.last_seen_at DESC, k.device_hash LIMIT 2);
      PERFORM private.bump_metric_internal('dating.device.trusted');
      RETURN jsonb_build_object('ok', true);
    EXCEPTION WHEN deadlock_detected OR lock_not_available OR serialization_failure THEN
      IF v_try = 3 THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'busy');
      END IF;
    END;
  END LOOP;
  RETURN jsonb_build_object('ok', false, 'reason', 'busy');
END;
$$;

-- 6. Gate 8 (§2.1; R-17): only for the caller's own requests (a request
--    carries its own device; generation and the crons have none).
CREATE OR REPLACE FUNCTION private.dating_device_gate(p_user uuid)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT CASE
    WHEN p_user IS DISTINCT FROM auth.uid() THEN 'eligible'
    WHEN public.dating_require_trusted_device() IS TRUE THEN 'eligible'
    ELSE 'reverify_device'
  END;
$$;

-- 7. Which re-verification an untrusted device needs (§3.3.4): after a
--    passed check, a video check here ('verified'); before one, the setup
--    starts again here ('setup_restart').
CREATE OR REPLACE FUNCTION private.dating_reverify_variant(p_user uuid)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT CASE
    WHEN EXISTS (SELECT 1 FROM public.dating_trusted_devices AS d WHERE d.user_id = p_user AND d.verified_at IS NOT NULL)
      OR EXISTS (SELECT 1 FROM public.dating_age_verifications AS v
                  WHERE v.user_id = p_user AND v.identity_result = 'pass' AND v.revoked_at IS NULL)
    THEN 'verified' ELSE 'setup_restart'
  END;
$$;

-- 8. Re-created from their live bodies (after W4a); every changed line is
--    marked -- Spec 2 W4b (Task 5 Step 7 diffs them).
```

Create `$D/mig_T5_tail.sql` with exactly:

```sql
-- 9. The server-only objects are closed in the migration itself (the twin
--    re-asserts them).
REVOKE ALL ON FUNCTION private.dating_device_state(uuid, text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_touch_device(uuid, text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_bind_setup_device(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_device_gate(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_reverify_variant(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.trust_dating_device(uuid, text) FROM PUBLIC, anon, authenticated;

COMMIT;
```

Create `$D/build_mig_T5.py` with exactly:

```python
#!/usr/bin/env python3
# Spec 2 W4b: builds supabase/migrations/20261109110000_dating_v2_trusted_devices.sql from
# mig_T5_head.sql (the new objects), the functions below re-created from
# their LIVE bodies (saved to before_w4b/ before the migration is applied) with
# only the lines marked "-- Spec 2 W4b" changed, and mig_T5_tail.sql (the
# revokes, COMMIT). Every anchor must occur exactly once.
import pathlib
D = pathlib.Path('.superpowers/sdd/2026-11-09-spec2-w4')
OUT = pathlib.Path('supabase/migrations/20261109110000_dating_v2_trusted_devices.sql')

def live(sig):
    return (D / 'before_w4b' / f'{sig}.sql').read_text().rstrip('\n')

M = '-- Spec 2 W4b'
FNS = []

# 1. The real device check (§3.3.4). Never NULL (callers use IF NOT x).
FNS.append(('public.dating_require_trusted_device()', [
  (" LANGUAGE sql\n", f" LANGUAGE plpgsql {M}\n"),
  ("""  -- W1c pass-through; W4b reads the x-attune-device header here.
  SELECT true;""",
   f"""DECLARE {M}
  v_user constant uuid := auth.uid(); {M}
  v_hash constant text := private.dating_request_device_hash(); {M}
  v_state text; {M}
BEGIN {M}
  -- Spec 2 W4b (§3.3.4): unbound (no device yet) or this trusted device;
  -- Spec 2 W4b never NULL, never true without a signed-in caller.
  IF v_user IS NULL THEN {M}
    RETURN false; {M}
  END IF; {M}
  v_state := private.dating_device_state(v_user, v_hash); {M}
  IF v_state = 'trusted' THEN {M}
    PERFORM private.dating_touch_device(v_user, v_hash); {M}
  END IF; {M}
  RETURN coalesce(v_state IN ('unbound', 'trusted'), false); {M}
END; {M}""")]))

# 2. dating_eligibility: gate 8, after gate 6, for the caller's own requests.
FNS.append(('public.dating_eligibility(uuid,text)', [
  ("    RETURN CASE WHEN p_scope = 'setup' THEN 'eligible' ELSE 'country_closed' END;",
   f"    RETURN CASE WHEN p_scope = 'setup' THEN private.dating_device_gate(p_user) ELSE 'country_closed' END; {M}: gate 8"),
  ("    RETURN CASE WHEN v_region IS NULL AND p_scope = 'setup' THEN 'eligible' ELSE 'region_closed' END;",
   f"    RETURN CASE WHEN v_region IS NULL AND p_scope = 'setup' THEN private.dating_device_gate(p_user) ELSE 'region_closed' END; {M}: gate 8"),
  ("  RETURN 'eligible';\nEND;",
   f"  -- 8. Spec 2 W4b (§2.1, R-17): a trusted device, for the caller's own requests.\n  RETURN private.dating_device_gate(p_user); {M}\nEND;")]))

# 3. The setup guard binds the first setup write's device (R-16).
FNS.append(('private.dating_setup_guard()', [
  ("""    RETURN 'not_eligible';
  END IF;
  RETURN NULL;""",
   f"""    RETURN 'not_eligible';
  END IF;
  PERFORM private.dating_bind_setup_device(v_user); {M} (§3.3.4, R-16): the first setup write's device
  RETURN NULL;""")]))

# 4. get_dating_home: which re-verification (§3.3.4).
FNS.append(('public.get_dating_home()', [
  ("""    RETURN coalesce(v_has, '{"has_data": true}') || jsonb_build_object('state', 'reverify_device'); -- Spec 2 W3a (C-2)""",
   f"""    RETURN coalesce(v_has, '{{"has_data": true}}') || jsonb_build_object('state', 'reverify_device', -- Spec 2 W3a (C-2); Spec 2 W4b
      'variant', private.dating_reverify_variant(v_user)); {M} (§3.3.4): setup_restart or verified""")]))

# 5. begin_dating_verification: the re-check kind (§3.3.4).
FNS.append(('public.begin_dating_verification(uuid,text,text,text,text,text)', [
  ("  v_has_open boolean;\nBEGIN", f"  v_has_open boolean;\n  v_device text; {M}\nBEGIN"),
  ("  IF p_user IS NULL OR p_kind IS DISTINCT FROM 'activation'",
   f"  IF p_user IS NULL OR (p_kind IN ('activation', 'reverify')) IS NOT TRUE {M}"),
  ("     OR (p_document IS NOT NULL AND p_document !~ '^[a-z0-9_]{1,40}$') THEN",
   f"     OR (p_document IS NOT NULL AND p_document !~ '^[a-z0-9_]{{1,40}}$') {M}\n"
   f"     OR (p_kind = 'reverify' AND (p_device_hash IS NULL OR p_step = 'id')) THEN {M}: a re-check needs the phone, and has no ID route"),
  ("      IF (p_step = 'id' AND v_state ->> 'age' = 'pass')",
   f"""      v_device := private.dating_device_state(p_user, p_device_hash); {M} (§3.3.4)
      IF p_kind = 'activation' AND v_device = 'untrusted' THEN {M}: the first check runs on the setup's own phone
        RETURN jsonb_build_object('ok', false, 'reason', 'reverify_device'); {M}
      END IF; {M}
      IF p_kind = 'reverify' AND v_device IS DISTINCT FROM 'untrusted' THEN {M}: nothing to re-check on this phone
        RETURN jsonb_build_object('ok', false, 'reason', 'already_verified'); {M}
      END IF; {M}
      IF p_kind = 'reverify' AND v_state ->> 'identity' IS DISTINCT FROM 'pass' THEN {M}: before a pass, the setup starts again instead
        RETURN jsonb_build_object('ok', false, 'reason', 'not_eligible'); {M}
      END IF; {M}
      IF p_kind = 'activation' AND ((p_step = 'id' AND v_state ->> 'age' = 'pass') {M}: activation only"""),
  ("""             AND (SELECT p.verification_state FROM public.dating_profiles AS p WHERE p.user_id = p_user) = 'verified') THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'already_verified');""",
   f"""             AND (SELECT p.verification_state FROM public.dating_profiles AS p WHERE p.user_id = p_user) = 'verified')) THEN {M}
        RETURN jsonb_build_object('ok', false, 'reason', 'already_verified');""")]))

# 6. decide: a person's pass on a re-check trusts the phone it ran on; a
#    re-check never writes the account's own result (a stranger's fail on a
#    new phone must not unverify the owner).
FNS.append(('public.decide_dating_human_review(uuid,text,uuid)', [
  ("""  IF p_outcome IN ('pass', 'fail') THEN
    v := public.record_dating_identity_check(""",
   f"""  IF p_outcome IN ('pass', 'fail') AND v_row.kind = 'activation' THEN {M}: a re-check never writes the owner's result
    v := public.record_dating_identity_check("""),
  ("""  ELSE
    UPDATE public.dating_profiles AS p SET verification_state = 'unverified'""",
   f"""  ELSIF p_outcome = 'ask_for_id' THEN {M}
    UPDATE public.dating_profiles AS p SET verification_state = 'unverified'"""),
  ("""  END IF;
  UPDATE public.dating_verification_sessions AS s
     SET state = CASE WHEN p_outcome = 'pass' THEN 'passed' ELSE 'failed' END,""",
   f"""  END IF;
  IF p_outcome = 'pass' AND v_row.kind = 'reverify' AND v_row.device_hash IS NOT NULL THEN {M} (§3.3.4): a person's pass trusts the phone
    v := public.trust_dating_device(v_row.user_id, v_row.device_hash); {M}
    IF (v ->> 'ok')::boolean IS NOT TRUE THEN {M}
      RETURN v; {M}
    END IF; {M}
  END IF; {M}
  UPDATE public.dating_verification_sessions AS s
     SET state = CASE WHEN p_outcome = 'pass' THEN 'passed' ELSE 'failed' END,""")]))

# 7. Exit unbinds every phone (setup_restart's Start again, §3.3.4).
FNS.append(('private.dating_exit_internal(uuid,boolean)', [
  ("  DELETE FROM public.dating_verification_sessions AS vs WHERE vs.user_id = p_user; -- Spec 2 W4a",
   f"  DELETE FROM public.dating_verification_sessions AS vs WHERE vs.user_id = p_user; -- Spec 2 W4a\n"
   f"  DELETE FROM public.dating_trusted_devices AS td WHERE td.user_id = p_user; {M} (§3.3.4): leaving unbinds every phone")]))

parts = []
for sig, pairs in FNS:
    body = live(sig)
    for old, new in pairs:
        n = body.count(old)
        assert n == 1, f'{sig}: anchor occurs {n} times: {old[:60]!r}'
        body = body.replace(old, new)
    parts.append(body + ';\n')
OUT.write_text((D / 'mig_T5_head.sql').read_text() + '\n'.join(parts) + '\n' + (D / 'mig_T5_tail.sql').read_text())
print(f'{OUT}: {len(FNS)} functions re-created')
```

Create `supabase/migrations/20261109110010_dating_v2_trusted_devices_grants.sql` with exactly:

```sql
-- Spec 2 W4b: grants for 20261109110000_dating_v2_trusted_devices.sql. The
-- device table is no API role's, the service role included (the device
-- check and the trust writer reach it). trust_dating_device is the service
-- role's (dating-verification). The helpers are the database's own; the
-- re-created functions keep their grants (dating_require_trusted_device:
-- no API role, as W1c).
BEGIN;
SET LOCAL lock_timeout = '5s';
REVOKE ALL ON public.dating_trusted_devices FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_device_state(uuid, text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_touch_device(uuid, text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_bind_setup_device(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_device_gate(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_reverify_variant(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.trust_dating_device(uuid, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.trust_dating_device(uuid, text) TO service_role;
REVOKE ALL ON FUNCTION public.dating_require_trusted_device() FROM PUBLIC, anon, authenticated, service_role;
COMMIT;
```

- [ ] **Step 4: Build and apply**

```bash
D=.superpowers/sdd/2026-11-09-spec2-w4
python3 -I $D/build_mig_T5.py
for f in supabase/migrations/20261109110000_dating_v2_trusted_devices.sql supabase/migrations/20261109110010_dating_v2_trusted_devices_grants.sql; do
  for run in 1 2; do psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f $f > /dev/null; echo "$(basename $f) run $run exit=$?"; done
done
```

Expected: `supabase/migrations/20261109110000_dating_v2_trusted_devices.sql: 7 functions re-created`; four `exit=0` lines; the second run's `NOTICE:  relation "dating_trusted_devices" already exists, skipping`.

- [ ] **Step 5: The existing contracts meet the real check**

Create `$D/edit_tests_T5.py` with exactly:

```python
# Spec 2 W4b Task 5: the contracts meet the real device check. The W1c/W3
# "stub rolled back" fixture checks ask whether the body is the real one
# (an unsigned caller is never trusted now); the home pins the reverify
# variant; the canary and the service-role test take the device table.
import pathlib, sys
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from anchor import edit

REAL = ("(SELECT p.prosrc FROM pg_proc AS p WHERE p.oid = 'public.dating_require_trusted_device()'::regprocedure)"
        " !~ 'dating_device_state'")
T = 'supabase/tests/'
p = pathlib.Path(T + 'dating_v2_setup_contracts.sql')
s = p.read_text()
old = "  IF public.dating_require_trusted_device() IS NOT TRUE THEN\n    RAISE EXCEPTION 'fixture: the device stub was not rolled back';"
new = f"  IF {REAL} THEN -- Spec 2 W4b: the real check is back\n    RAISE EXCEPTION 'fixture: the device stub was not rolled back';"
assert s.count(old) == 2, s.count(old)
s = s.replace(old, new)
old = "  IF public.dating_require_trusted_device() IS NOT TRUE OR public.dating_eligibility(v_u, 'setup') IS DISTINCT FROM 'eligible' THEN"
new = f"  IF {REAL} OR public.dating_eligibility(v_u, 'setup') IS DISTINCT FROM 'eligible' THEN -- Spec 2 W4b"
assert s.count(old) == 1
s = s.replace(old, new)
p.write_text(s)
print(f'{p}: 3 edit(s) (T5 setup fixtures)')

edit(T + 'dating_v2_identity_contracts.sql', [
    ("""  IF public.dating_require_trusted_device() IS NOT TRUE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the W1c trusted-device pass-through does not allow';""",
     f"""  -- Spec 2 W4b: the real check (W1c's pass-through is gone); a caller
  -- Spec 2 W4b who isn't signed in is never trusted.
  IF {REAL} OR public.dating_require_trusted_device() IS NOT FALSE THEN -- Spec 2 W4b
    RAISE EXCEPTION 'CONTRACT VIOLATED: the trusted-device check is not W4b''s, or trusts nobody signed in';"""),
    ("""     OR public.dating_require_trusted_device() IS NOT TRUE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: adding was gated""",
     f"""     OR {REAL} THEN -- Spec 2 W4b
    RAISE EXCEPTION 'CONTRACT VIOLATED: adding was gated"""),
], 'T5 identity fixtures')

edit(T + 'dating_v2_home_contracts.sql', [
    ("""  IF v IS DISTINCT FROM '{"state": "reverify_device"}' THEN""",
     """  IF v IS DISTINCT FROM '{"state": "reverify_device", "variant": "setup_restart"}' THEN -- Spec 2 W4b (§3.3.4)"""),
], 'T5 home')

CHECKS = """-- ---------------------------------------------------------------------
-- Checks (every batch adds its rows above this line)."""
edit(T + 'dating_rls_canary.sql', [(CHECKS, """-- ---------------------------------------------------------------------
-- W4b (migration 1): the device table is no API role's, the service role
-- included; the trust writer is the service role's (dating-verification);
-- the device helpers are the database's own.
INSERT INTO allowed_rel (name, authenticated, service_dml) VALUES
  ('dating_trusted_devices', '', '');
INSERT INTO allowed_fn (sig, clients, service) VALUES
  ('trust_dating_device(uuid,text)', '', 'service_role'),
  ('private.dating_device_state(uuid,text)', '', ''),
  ('private.dating_touch_device(uuid,text)', '', ''),
  ('private.dating_bind_setup_device(uuid)', '', ''),
  ('private.dating_device_gate(uuid)', '', ''),
  ('private.dating_reverify_variant(uuid)', '', '');
""" + CHECKS)], 'T5 canary')

p = pathlib.Path(T + 'service_role_grants_test.sql')
s = p.read_text()
old = """                          'dating_verification_sessions')"""
new = """                          'dating_verification_sessions',
                          -- Spec 2 W4b: device hashes; the device check and the
                          -- trust writer reach them.
                          'dating_trusted_devices')"""
assert s.count(old) == 2, s.count(old)
p.write_text(s.replace(old, new))
print(f'{p}: 2 edit(s) (T5 service_role_grants)')
```

```bash
python3 -I .superpowers/sdd/2026-11-09-spec2-w4/edit_tests_T5.py
```

Expected: one line per edited file, no `AssertionError`.

- [ ] **Step 6: The contract passes, and the whole suite**

```bash
D=.superpowers/sdd/2026-11-09-spec2-w4
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/dating_v2_verification_contracts.sql 2>&1 | grep -E 'ERROR|all held'
$D/suite.sh attune_spec3a > $D/sql-after-T5.txt; echo "$(grep -c '^PASS' $D/sql-after-T5.txt) PASS, $(grep -c '^FAIL' $D/sql-after-T5.txt) FAIL"
diff <(grep '^FAIL' $D/sql-baseline.txt) <(grep '^FAIL' $D/sql-after-T5.txt) && echo "no new FAIL"
```

Expected: `NOTICE:  dating_v2_verification_contracts: all held`; `160 PASS, 14 FAIL`; `no new FAIL` (W3's setup contracts, section N included, pass against the real check: carry 6).

- [ ] **Step 7: Every re-created line is marked; the grants harness line**

```bash
D=.superpowers/sdd/2026-11-09-spec2-w4
python3 -I $D/marked_diff.py $D/before_w4b attune_spec3a 'Spec 2 W4b'; echo "exit=$?"
python3 -I $D/grants_line.py supabase/migrations/20261109100010_dating_v2_age_assurance_grants.sql \
  "Spec 2 W4b: trusted devices are the service role's to write (trust_dating_device); the device check stays the app's." \
  supabase/migrations/20261109110010_dating_v2_trusted_devices_grants.sql
```

Expected: seven lines ending `OK` (`dating_require_trusted_device` also prints its header change, `LANGUAGE plpgsql`), `exit=0`; `local_pg_grants.sql: one \i block added`.

- [ ] **Step 8: Mutants (§7.5 mutant 9 and the W4b rules)**

Create `$D/mut_T5.py` with exactly:

```python
# Spec 2 W4b Task 5 mutants (mutate.py with the twin; LIVE re-creates a
# function from its body as it is now).
GUARD = "  IF public.dating_require_trusted_device() IS NOT TRUE THEN\n    RETURN jsonb_build_object('ok', false, 'reason', 'reverify_device');\n  END IF;\n"
MUTS = {
 # §7.5 mutant 9: one read RPC skips the device check.
 'm9_profile_read_unguarded': ('LIVE', ('public.get_my_dating_profile()', [(GUARD, '')])),
 # Carry 6: W3's lists_no_device, against the real check.
 'lists_no_device': ('LIVE', ('public.get_dating_setup_lists()', [(GUARD, '')])),
 'guard_null_when_untrusted': ("  RETURN coalesce(v_state IN ('unbound', 'trusted'), false); -- Spec 2 W4b",
                               "  RETURN CASE WHEN v_state IN ('unbound', 'trusted') THEN true END; -- Spec 2 W4b"),
 'guard_any_device': ("  RETURN coalesce(v_state IN ('unbound', 'trusted'), false); -- Spec 2 W4b",
                      "  RETURN v_state IS NOT NULL; -- Spec 2 W4b"),
 'no_bind': ("  PERFORM private.dating_bind_setup_device(v_user); -- Spec 2 W4b (§3.3.4, R-16): the first setup write's device", ''),
 'gate8_for_everyone': ("    WHEN p_user IS DISTINCT FROM auth.uid() THEN 'eligible'\n", ''),
 'gate8_missing': ("  RETURN private.dating_device_gate(p_user); -- Spec 2 W4b", "  RETURN 'eligible'; -- Spec 2 W4b"),
 'cap_not_enforced': ("""      DELETE FROM public.dating_trusted_devices AS d
       WHERE d.user_id = p_user AND d.device_hash <> p_device_hash""", """      DELETE FROM public.dating_trusted_devices AS d
       WHERE false AND d.user_id = p_user AND d.device_hash <> p_device_hash"""),
 'stale_still_trusted': ("                                           AND d.last_seen_at > now() - interval '180 days') THEN 'trusted'",
                         "                                           ) THEN 'trusted'"),
 'touch_every_read': ("   WHERE d.user_id = p_user AND d.device_hash = p_hash AND d.last_seen_at < now() - interval '1 day';",
                      "   WHERE d.user_id = p_user AND d.device_hash = p_hash;"),
 'exit_keeps_devices': ("  DELETE FROM public.dating_trusted_devices AS td WHERE td.user_id = p_user; -- Spec 2 W4b (§3.3.4): leaving unbinds every phone", ''),
 'variant_always_restart': ("    THEN 'verified' ELSE 'setup_restart'", "    THEN 'setup_restart' ELSE 'setup_restart'"),
 'reverify_on_trusted': ("      IF p_kind = 'reverify' AND v_device IS DISTINCT FROM 'untrusted' THEN -- Spec 2 W4b: nothing to re-check on this phone",
                         "      IF false THEN -- Spec 2 W4b: nothing to re-check on this phone"),
 'activation_on_untrusted': ("      IF p_kind = 'activation' AND v_device = 'untrusted' THEN -- Spec 2 W4b: the first check runs on the setup's own phone",
                             "      IF false THEN -- Spec 2 W4b: the first check runs on the setup's own phone"),
 'reverify_before_pass': ("      IF p_kind = 'reverify' AND v_state ->> 'identity' IS DISTINCT FROM 'pass' THEN -- Spec 2 W4b: before a pass, the setup starts again instead",
                          "      IF false THEN -- Spec 2 W4b: before a pass, the setup starts again instead"),
 'decide_no_trust': ("    v := public.trust_dating_device(v_row.user_id, v_row.device_hash); -- Spec 2 W4b",
                     "    v := jsonb_build_object('ok', true); -- Spec 2 W4b"),
 'reverify_fail_unverifies_owner': ("  IF p_outcome IN ('pass', 'fail') AND v_row.kind = 'activation' THEN -- Spec 2 W4b: a re-check never writes the owner's result",
                                    "  IF p_outcome IN ('pass', 'fail') THEN -- Spec 2 W4b: a re-check never writes the owner's result"),
 # R-32 (owner ruling 2026-11-09): Start again on a new phone drops the list.
 'restart_drops_list': ('LIVE', ('private.dating_exit_internal(uuid,boolean)',
                                 [('  IF NOT coalesce(p_keep_never_introduce, false) THEN', '  IF true THEN')])),
}
```

```bash
D=.superpowers/sdd/2026-11-09-spec2-w4
python3 -I $D/mutate.py supabase/migrations/20261109110000_dating_v2_trusted_devices.sql supabase/tests/dating_v2_verification_contracts.sql $D/mut_T5.py $D/mut supabase/migrations/20261109110010_dating_v2_trusted_devices_grants.sql | tee $D/mut_T5.txt | grep -c -E 'NO ERROR|anchor missing'
wc -l < $D/mut_T5.txt
```

Expected: `0` and `18`; every line `<name>: ERROR:  CONTRACT VIOLATED: …` (e.g. `m9_profile_read_unguarded: … another device read or wrote: …`, `lists_no_device: … another device read or wrote: …` (carry 6: the W3 mutant now dies against the real check), `guard_null_when_untrusted: … a raising writer let another device through (a NULL check?) …`, `reverify_fail_unverifies_owner: … a failed re-check changed the owner's result or trusted the phone`, `restart_drops_list: … Start again on a new phone lost the never-introduce list` (R-32)). Quote each line in the report.

- [ ] **Step 9: The race case (two phones trusted at once)**

Create `$D/edit_races_T5.py` with exactly:

```python
# Spec 2 W4b Task 5: one race case. Two devices trusted at once for one
# person: the setup lock serialises them, and at most three stay.
import pathlib, sys
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from anchor import edit
edit('scripts/concurrency/dating_kill_switch_races.sh', [
    ("""                           'dating_profile_photos', 'dating_photo_upload_intents'] LOOP -- Spec 2 W3c (Task 8)""",
     """                           'dating_profile_photos', 'dating_photo_upload_intents', -- Spec 2 W3c (Task 8)
                           'dating_trusted_devices'] LOOP -- Spec 2 W4b (Task 5)"""),
    ("""
$P -c "SELECT race.reset();" > /dev/null 2>&1
exit $fail""",
     """
# Spec 2 W4b (Task 5, §3.3.4): two new devices trusted at once for one
# person who has three already: the setup lock serialises the two trusts
# (the first sleeps in its cap delete, holding it), so the cap holds:
# three devices, the two new ones among them, no deadlock.
FX_DEVICES="SELECT race.reset(); ALTER SEQUENCE race.s1 RESTART;
SELECT race.person('06', 'GB', 'TLI', 'woman', ARRAY['man']);
INSERT INTO public.dating_trusted_devices (user_id, device_hash, verified_at, last_seen_at)
SELECT race.id('06'), repeat(c, 64), now(), now() - interval '2 days' FROM unnest(ARRAY['1', '2', '5']) AS c;"
run "two devices trusted at once: at most three stay" "$FX_DEVICES" \\
  "SET race.sleep_dating_trusted_devices_delete = '2:race.s1';
   SELECT public.trust_dating_device(race.id('06'), repeat('3', 64)) ->> 'ok';" \\
  "SELECT pg_sleep(0.5);
   SELECT public.trust_dating_device(race.id('06'), repeat('4', 64)) ->> 'ok';" \\
  "SELECT CASE WHEN NOT (SELECT is_called FROM race.s1) THEN 'the first trust never reached its delete (no race)'
               WHEN (SELECT count(*) FROM public.dating_trusted_devices WHERE user_id = race.id('06')) <> 3
               THEN 'devices kept: ' || (SELECT count(*) FROM public.dating_trusted_devices WHERE user_id = race.id('06'))
               WHEN (SELECT count(*) FROM public.dating_trusted_devices WHERE user_id = race.id('06')
                       AND device_hash IN (repeat('3', 64), repeat('4', 64))) <> 2 THEN 'a new device was dropped'
               ELSE 'ok' END;" serialised

$P -c "SELECT race.reset();" > /dev/null 2>&1
exit $fail"""),
], 'T5 races')
```

```bash
D=.superpowers/sdd/2026-11-09-spec2-w4
python3 -I $D/edit_races_T5.py
dropdb --if-exists w4_race; createdb w4_race
pg_dump -s attune_spec3a | psql -X -q -d w4_race > /dev/null 2>&1
pg_dump -a -t public.metric_key_prefixes -t public.feature_flags -t public.country_safety_config -t private.dating_calling_codes attune_spec3a | psql -X -q -d w4_race > /dev/null 2>&1
scripts/concurrency/dating_kill_switch_races.sh w4_race > $D/race_T5.txt 2>&1; echo "exit=$?"; grep -c '^PASS' $D/race_T5.txt; tail -1 $D/race_T5.txt
dropdb w4_race
```

Expected: `scripts/concurrency/dating_kill_switch_races.sh: 2 edit(s) (T5 races)`; `exit=0`; `29`; `PASS  two devices trusted at once: at most three stay (deadlocks detected and retried: 0)`; on a first run `dropdb --if-exists`'s `NOTICE`. Do not commit; record the tree in the report.

### Task 6: The install id, the Dating-scoped client that alone sends `x-attune-device`, and the edge function's re-check (§3.3.4, §4.7, §4.10, §7.2 S19, §7.4; S-7, C-6; carry 10; R-14, R-16, R-23, R-24)

**Files:**
- Create: `lib/core/device/install_id.dart`, `test/core/device/install_id_test.dart`, `test/features/dating/data/dating_supabase_client_test.dart`, `test/architecture/dating_device_header_test.dart`, `$D/{edit_edge_T6.py, edit_T6.py, mut_T6_deno.py, mut_T6.py}`
- Replace: `lib/features/dating/data/dating_supabase_client.dart` (formatter style; do not run `dart format` on it)
- Modify: `supabase/functions/dating-verification/{handler.ts, handler.test.ts}`, `lib/app/app.dart` (one import and one microtask, R-23)

**Interfaces:**
- Consumes: Task 5's `trust_dating_device`, `begin_dating_verification(…'reverify'…)`; Task 2's handler; Spec 1's `SafetyPinStore` keystore options; W3's `datingSupabaseClientProvider` (every Dating call already goes through it, carry 10).
- Produces: `InstallIdStore.ensure() → Future<String?>` (32 lowercase hex, `Random.secure`, key `attune.install_id`; a stored value that is not an id is replaced; a failing keystore answers `null`), `installIdStoreProvider`; `DatingDeviceHttpClient(inner, id)`, `datingDeviceHeader == 'x-attune-device'`; edge actions `reverify_start {scenario?}`, `reverify_complete {session_id}`, `human_start {reverify:true}`; the phone that passes D11 is trusted (`trust_dating_device`), with no header nothing is.

- [ ] **Step 1: The edge function's re-check, test first**

Create `$D/edit_edge_T6.py` with exactly (the handler's edits, then the test fake's one line and four tests appended):

```python
# Spec 2 W4b Task 6: dating-verification trusts the phone that passes, and
# runs the re-check (§3.3.4): reverify_start, reverify_complete, and the
# human route with {reverify: true}. A re-check never writes the account's
# own identity result: a stranger's failed check on a new phone must not
# unverify the owner. Exact anchors in Task 2's file.
import pathlib, sys
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from anchor import edit

H = 'supabase/functions/dating-verification/handler.ts'
edit(H, [
    ("""// - fake is refused unless the environment reads development (§3.3.5,
//   Q19b), and a scenario is accepted only in fake mode.""",
     """// - fake is refused unless the environment reads development (§3.3.5,
//   Q19b), and a scenario is accepted only in fake mode.
// - Spec 2 W4b (§3.3.4): the phone that passes D11 is trusted; a re-check
//   (reverify_start, reverify_complete, human_start with reverify) runs on
//   an untrusted phone of a person who passed, is liveness and CompareFaces
//   only (no age), trusts that phone on a pass and never writes the
//   account's own identity result (a stranger failing on a new phone must
//   not unverify the owner)."""),
    ("""    const id = await call(deps, "record_dating_identity_check", {
      p_user: caller.userId, p_method: "liveness_compare", p_result: "pass", p_vendor: s.providers.faceMatch.name, p_decided_by: null,
    });
    if (id?.ok !== true) return refusal(id?.reason ?? "busy");
    if (row.age === "pass") {""",
     """    const id = await call(deps, "record_dating_identity_check", {
      p_user: caller.userId, p_method: "liveness_compare", p_result: "pass", p_vendor: s.providers.faceMatch.name, p_decided_by: null,
    });
    if (id?.ok !== true) return refusal(id?.reason ?? "busy");
    // Spec 2 W4b (§3.3.4): the phone that passed D11 is trusted (best
    // effort: the setup's phone stays trusted for the setup without it).
    if (caller.deviceHash !== null) {
      await call(deps, "trust_dating_device", { p_user: caller.userId, p_device_hash: caller.deviceHash });
    }
    if (row.age === "pass") {"""),
    ("""async function humanStart(caller: Caller, _body: Record<string, unknown>, deps: VerificationDeps): Promise<Answer> {
  const s = await setup(deps);
  if (isAnswer(s)) return s;
  const begun = await call(deps, "begin_dating_verification", {
    p_user: caller.userId, p_kind: "activation", p_step: "human", p_vendor: "attune",""",
     """async function humanStart(caller: Caller, body: Record<string, unknown>, deps: VerificationDeps): Promise<Answer> {
  const s = await setup(deps);
  if (isAnswer(s)) return s;
  // Spec 2 W4b (§3.3.4): the re-check's "Check another way".
  const reverify = body.reverify === true;
  if (reverify && caller.deviceHash === null) return refusal("reverify_device");
  const begun = await call(deps, "begin_dating_verification", {
    p_user: caller.userId, p_kind: reverify ? "reverify" : "activation", p_step: "human", p_vendor: "attune","""),
    ("""const ACTIONS: Record<string, (c: Caller, b: Record<string, unknown>, d: VerificationDeps) => Promise<Answer>> = {
  start, complete, start_id: startId, complete_id: completeId, human_start: humanStart, submit_human: submitHuman,
};""",
     """/// Spec 2 W4b (§3.3.4): reverify_start: a re-check session on this phone.
async function reverifyStart(caller: Caller, body: Record<string, unknown>, deps: VerificationDeps): Promise<Answer> {
  const s = await setup(deps);
  if (isAnswer(s)) return s;
  if (caller.deviceHash === null) return refusal("reverify_device");
  const sc = scenarioFor(s.mode, body);
  if (!sc.ok) return refusal("invalid");
  const begun = await call(deps, "begin_dating_verification", {
    p_user: caller.userId, p_kind: "reverify", p_step: "liveness", p_vendor: s.providers.liveness.name,
    p_device_hash: caller.deviceHash, p_document: null,
  });
  if (begun === null) return refusal("busy");
  if (begun.ok !== true) return refusal(begun.reason);
  const session = uuidOf(begun.session_id);
  if (session === null) return refusal("busy");
  let ref: string;
  try {
    ref = (await s.providers.liveness.createSession({ scenario: sc.scenario })).ref;
  } catch {
    return refusal("vendor_unavailable");
  }
  const set = await call(deps, "set_dating_verification_ref", { p_session: session, p_ref: ref });
  if (set === null) return refusal("busy");
  if (set.ok !== true) return refusal(set.reason);
  return {
    ok: true, session_id: session, vendor: s.providers.liveness.name, vendor_session: ref,
    attempts: typeof begun.attempts === "number" ? begun.attempts : 0, resumed: begun.resumed === true,
  };
}

/// Spec 2 W4b (§3.3.4): reverify_complete: liveness, then every approved
/// photo; a pass trusts this phone. No age, and never the account's own
/// identity result.
async function reverifyComplete(caller: Caller, body: Record<string, unknown>, deps: VerificationDeps): Promise<Answer> {
  const s = await setup(deps);
  if (isAnswer(s)) return s;
  if (caller.deviceHash === null) return refusal("reverify_device");
  const session = uuidOf(body.session_id);
  if (session === null) return refusal("invalid");
  const row = await call(deps, "get_dating_verification_session", { p_user: caller.userId, p_session: session });
  if (row === null) return refusal("busy");
  if (row.ok !== true || row.kind !== "reverify" || row.step !== "liveness" || row.state !== "started"
      || row.expired === true || typeof row.vendor_session_ref !== "string" || row.device_hash !== caller.deviceHash) {
    return refusal("session_unavailable");
  }
  let result;
  try {
    result = await s.providers.liveness.results(row.vendor_session_ref);
  } catch {
    return refusal("vendor_unavailable");
  }
  if (result.status === "pending") return { ok: true, outcome: "pending" };
  if (result.status === "expired") return refusal("vendor_unavailable");
  if (result.status === "failed" || result.reference === null) {
    const r = await call(deps, "record_dating_liveness_attempt", { p_session: session, p_passed: false });
    if (r === null) return refusal("busy");
    if (r.ok !== true) return refusal(r.reason);
    return { ok: true, outcome: r.outcome === "another_way" ? "another_way" : "retry", attempts: r.attempts };
  }
  const frame = result.reference;
  try {
    const live = await call(deps, "record_dating_liveness_attempt", { p_session: session, p_passed: true });
    if (live === null) return refusal("busy");
    if (live.ok !== true) return refusal(live.reason);
    const photos = await scalar(deps, "get_dating_verification_photos", { p_user: caller.userId });
    if (!Array.isArray(photos)) return refusal("busy");
    if (photos.length < 2) return refusal("photos_required");
    for (let i = 0; i < photos.length; i++) {
      const p = photos[i] as { storage_key?: unknown };
      if (typeof p?.storage_key !== "string") return refusal("busy");
      let bytes: Uint8Array | null;
      try {
        bytes = await deps.download(p.storage_key);
      } catch {
        bytes = null;
      }
      if (bytes === null) return refusal("vendor_unavailable");
      let same: boolean;
      try {
        same = await s.providers.faceMatch.compare(frame, bytes, i);
      } catch {
        return refusal("vendor_unavailable");
      } finally {
        bytes.fill(0);
      }
      if (!same) {
        if (!(await finish(deps, session, "failed", "identity_failed"))) return refusal("busy");
        return { ok: true, outcome: "identity_failed" };
      }
    }
    const trusted = await call(deps, "trust_dating_device", { p_user: caller.userId, p_device_hash: caller.deviceHash });
    if (trusted?.ok !== true) return refusal(trusted?.reason ?? "busy");
    if (!(await finish(deps, session, "passed", "verified"))) return refusal("busy");
    return { ok: true, outcome: "verified" };
  } finally {
    frame.fill(0);
  }
}

const ACTIONS: Record<string, (c: Caller, b: Record<string, unknown>, d: VerificationDeps) => Promise<Answer>> = {
  start, complete, start_id: startId, complete_id: completeId, human_start: humanStart, submit_human: submitHuman,
  reverify_start: reverifyStart, reverify_complete: reverifyComplete, // Spec 2 W4b
};"""),
], 'T6 edge')

T = 'supabase/functions/dating-verification/handler.test.ts'
edit(T, [
    ("""        case "record_dating_identity_check":
        case "record_dating_age_assurance":""",
     """        case "record_dating_identity_check":
        case "trust_dating_device": // Spec 2 W4b
        case "record_dating_age_assurance":"""),
], 'T6 edge test fake')
p = pathlib.Path(T)
p.write_text(p.read_text() + '''
// Spec 2 W4b (Task 6, §3.3.4): the phone that passes is trusted; the
// re-check trusts a new phone on a pass, never writes the account's own
// result, and needs the phone.
const onPhone = { userId: "u-1", deviceHash: "a".repeat(64) };

Deno.test("W4b: the phone that passes D11 is trusted; with no header nothing is", async () => {
  const w = world();
  const d = deps(w, table(true, 30, true));
  await handleVerification({ action: "start" }, onPhone, d);
  eq((await handleVerification({ action: "complete", session_id: SESSION }, onPhone, d)).outcome, "verified");
  eq(args(w, "trust_dating_device"), [{ p_user: "u-1", p_device_hash: "a".repeat(64) }]);
  const w2 = world();
  const d2 = deps(w2, table(true, 30, true));
  await handleVerification({ action: "start" }, caller, d2);
  await handleVerification({ action: "complete", session_id: SESSION }, caller, d2);
  eq(args(w2, "trust_dating_device").length, 0);
});

Deno.test("W4b: a re-check passes: liveness and every photo, the phone trusted, no age, no identity written", async () => {
  const w = world();
  const estimates: number[] = [];
  const d = deps(w, table(true, 20, true, [], estimates));
  eq((await handleVerification({ action: "reverify_start" }, onPhone, d)).ok, true);
  eq(args(w, "begin_dating_verification")[0]?.p_kind, "reverify");
  w.calls.length = 0;
  const r = await handleVerification({ action: "reverify_complete", session_id: SESSION }, { ...onPhone }, {
    ...d,
    rpc: (fn, a) => fn === "get_dating_verification_session"
      ? Promise.resolve({ data: { ok: true, kind: "reverify", step: "liveness", state: "started", expired: false,
          vendor_session_ref: w.ref, device_hash: "a".repeat(64) }, error: null })
      : d.rpc(fn, a),
  });
  eq(r.outcome, "verified");
  eq(args(w, "trust_dating_device"), [{ p_user: "u-1", p_device_hash: "a".repeat(64) }]);
  eq(names(w).filter((n) => n.startsWith("record_dating_age") || n === "record_dating_identity_check"), []);
  eq(estimates.length, 0, "no age on a re-check");
});

Deno.test("W4b: a re-check that doesn't match never unverifies the owner; another phone's session is refused", async () => {
  const w = world();
  const d = deps(w, table(true, 30, false));
  await handleVerification({ action: "reverify_start" }, onPhone, d);
  const row = (hash: string) => (fn: string, a?: Record<string, unknown>) => fn === "get_dating_verification_session"
    ? Promise.resolve({ data: { ok: true, kind: "reverify", step: "liveness", state: "started", expired: false,
        vendor_session_ref: w.ref, device_hash: hash }, error: null })
    : d.rpc(fn, a);
  eq((await handleVerification({ action: "reverify_complete", session_id: SESSION }, onPhone, { ...d, rpc: row("a".repeat(64)) })).outcome,
    "identity_failed");
  eq(names(w).includes("record_dating_identity_check"), false);
  eq(names(w).includes("trust_dating_device"), false);
  eq(await handleVerification({ action: "reverify_complete", session_id: SESSION }, onPhone, { ...d, rpc: row("b".repeat(64)) }),
    { ok: false, reason: "session_unavailable" });
});

Deno.test("W4b: a re-check needs the phone's header", async () => {
  const w = world();
  const d = deps(w);
  for (const action of ["reverify_start", "reverify_complete"]) {
    eq(await handleVerification({ action, session_id: SESSION }, caller, d), { ok: false, reason: "reverify_device" }, action);
  }
  eq(await handleVerification({ action: "human_start", reverify: true }, caller, d), { ok: false, reason: "reverify_device" });
  eq(names(w).includes("begin_dating_verification"), false);
  await handleVerification({ action: "human_start", reverify: true }, onPhone, d);
  eq(args(w, "begin_dating_verification")[0]?.p_kind, "reverify");
});
''')
print(f'{T}: W4b tests appended')
```

```bash
python3 -I .superpowers/sdd/2026-11-09-spec2-w4/edit_edge_T6.py
cd supabase/functions && NO_COLOR=1 deno test --allow-read --allow-env --lock=../../.github/deno-w9.lock --frozen dating-verification/handler.test.ts 2>&1 | grep -E '^(ok|FAILED) \|'; cd ../..
```

Expected: `…/handler.ts: 4 edit(s) (T6 edge)`, `…/handler.test.ts: 1 edit(s) (T6 edge test fake)`, `…/handler.test.ts: W4b tests appended`; `ok | 22 passed | 0 failed (…)`. (To see these four fail first, run the test with the handler's edits reverted: `deno test` reads `FAILED | 18 passed | 4 failed`.)

- [ ] **Step 2: Write the failing Dart tests**

Create `test/core/device/install_id_test.dart` with exactly:

```dart
// Spec 2 W4b (§3.3.4, C-5): the install's id: 32 lowercase hex characters,
// made once and then the same; a value that isn't one is replaced; a
// keystore that fails answers null, and the next ask tries again.
import 'dart:math';

import 'package:attune/core/device/install_id.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

class _Broken extends FlutterSecureStorage {
  const _Broken();
  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) => Future.error(StateError('keystore'));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('made once, 32 hex characters, under the neutral key', () async {
    final store = InstallIdStore(random: Random(7));
    final id = await store.ensure();
    expect(id, matches(RegExp(r'^[0-9a-f]{32}$')));
    expect(await store.ensure(), id);
    expect(await InstallIdStore().ensure(), id, reason: 'read back');
    final all = await const FlutterSecureStorage().readAll();
    expect(all.keys, [InstallIdStore.key]);
    expect(InstallIdStore.key.toLowerCase(), isNot(contains('dating')));
  });

  test('a stored value that is not an id is replaced', () async {
    FlutterSecureStorage.setMockInitialValues({
      InstallIdStore.key: 'DATING-NOT-AN-ID',
    });
    final id = await InstallIdStore().ensure();
    expect(id, matches(RegExp(r'^[0-9a-f]{32}$')));
  });

  test('a keystore that fails answers null', () async {
    expect(await InstallIdStore(storage: const _Broken()).ensure(), isNull);
  });
}
```

Create `test/features/dating/data/dating_supabase_client_test.dart` with exactly:

```dart
// Spec 2 W4b (§3.3.4, S-7, C-6): the Dating client's requests carry the
// install's id as x-attune-device; without an id they go as they are.
import 'package:attune/features/dating/data/dating_supabase_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  Future<Map<String, String>> sent(String? id) async {
    late Map<String, String> headers;
    final client = DatingDeviceHttpClient(
      () async => id,
      MockClient((request) async {
        headers = request.headers;
        return http.Response('{}', 200);
      }),
    );
    await client.get(Uri.parse('https://example.test/rest/v1/rpc/x'));
    return headers;
  }

  test('the id rides on every request', () async {
    expect(
      (await sent('0123456789abcdef0123456789abcdef'))[datingDeviceHeader],
      '0123456789abcdef0123456789abcdef',
    );
  });

  test('no id: no header', () async {
    expect((await sent(null)).containsKey(datingDeviceHeader), isFalse);
  });
}
```

Create `test/architecture/dating_device_header_test.dart` with exactly:

```dart
// Spec 2 W4b (§3.3.4, §7.4, S-7, C-6, R15): only the Dating client sends
// the install's id: no other file in lib/ names the header, only the app's
// first-launch line and the Dating client read the id, and lib/main.dart
// knows nothing of it.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Iterable<File> _libDart() => Directory('lib')
    .listSync(recursive: true)
    .whereType<File>()
    .where(
      (f) => f.path.endsWith('.dart') && !f.path.contains('/i10n/generated/'),
    );

List<String> _filesWith(String text) => [
  for (final f in _libDart())
    if (f.readAsStringSync().contains(text)) f.path,
]..sort();

void main() {
  test('only the Dating client names x-attune-device', () {
    expect(_filesWith('x-attune-device'), [
      'lib/features/dating/data/dating_supabase_client.dart',
    ]);
  });

  test('only the first launch and the Dating client read the id', () {
    expect(_filesWith('installIdStoreProvider'), [
      'lib/app/app.dart',
      'lib/core/device/install_id.dart',
      'lib/features/dating/data/dating_supabase_client.dart',
    ]);
    expect(
      File('lib/main.dart').readAsStringSync(),
      isNot(contains('install_id')),
    );
  });
}
```

```bash
flutter test test/core/device/install_id_test.dart 2>&1 | tr '\r' '\n' | grep -m1 -o "Error: Error when reading '[^']*'"
```

Expected: `Error: Error when reading 'lib/core/device/install_id.dart'`.

- [ ] **Step 3: The install id, the Dating client, the first-launch line**

Create `lib/core/device/install_id.dart` with exactly:

```dart
// Spec 2 W4b (§3.3.4, §7.2 S19, C-5): this install's random 128-bit id, as
// 32 lowercase hex characters, created at first launch for everyone (so
// its presence says nothing about Dating) under the neutral key
// attune.install_id, in the safety keystore (Android Keystore, excluded
// from backups; iOS Keychain first_unlock_this_device, not migrated to a
// new phone). Neither sign-out nor quick exit clears it; a reinstall or a
// restored backup makes a new one, and that phone re-verifies for Dating.
// Only the Dating client sends it (S-7); the server keeps a hash. Never
// throws: a keystore that can't be read or written answers null.
import 'dart:math';

import 'package:attune/features/safety/data/safety_pin_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class InstallIdStore {
  InstallIdStore({FlutterSecureStorage? storage, Random? random})
    : _storage = storage ?? SafetyPinStore.defaultStorage,
      _random = random ?? Random.secure();

  final FlutterSecureStorage _storage;
  final Random _random;
  Future<String?>? _id;

  static const key = 'attune.install_id';
  static final _valid = RegExp(r'^[0-9a-f]{32}$');

  /// The id, created the first time; the same answer for the life of
  /// this store once one is known.
  Future<String?> ensure() => _id ??= _readOrCreate();

  Future<String?> _readOrCreate() async {
    try {
      final stored = await _storage.read(key: key);
      if (stored != null && _valid.hasMatch(stored)) return stored;
      final id =
          [
            for (var i = 0; i < 16; i++)
              _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
          ].join();
      await _storage.write(key: key, value: id);
      return id;
    } catch (_) {
      _id = null; // asked again next time
      return null;
    }
  }
}

final installIdStoreProvider = Provider<InstallIdStore>(
  (ref) => InstallIdStore(),
);
```

Replace the whole of `lib/features/dating/data/dating_supabase_client.dart` with exactly:

```dart
// Spec 2 W4b (§3.3.4, S-7, C-6, R15): the one Supabase client every Dating
// repository uses. Dating's own client: every request it makes (RPC,
// edge function, storage) carries this install's id as x-attune-device,
// and it signs in with the app's current session token. No other request
// carries the id, so Opinions and couples traffic can't be linked to the
// hash Dating stores; the app's own client and lib/main.dart are not
// changed. Without the project's config (a build with no backend) it is
// the app's own client, as before.
import 'package:attune/core/config/env.dart';
import 'package:attune/core/device/install_id.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// The trusted-device header (the server reads only this name).
const datingDeviceHeader = 'x-attune-device';

/// Adds the install's id to each request; without one, sends it as is
/// (the server then treats the phone as untrusted once Dating is bound).
class DatingDeviceHttpClient extends http.BaseClient {
  DatingDeviceHttpClient(this._deviceId, [http.Client? inner])
    : _inner = inner ?? http.Client();

  final Future<String?> Function() _deviceId;
  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final id = await _deviceId();
    if (id != null) request.headers[datingDeviceHeader] = id;
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}

final datingSupabaseClientProvider = Provider<SupabaseClient>((ref) {
  if (Environment.supabaseUrl.isEmpty || Environment.supabaseAnonKey.isEmpty) {
    return Supabase.instance.client;
  }
  final app = Supabase.instance.client;
  final client = SupabaseClient(
    Environment.supabaseUrl,
    Environment.supabaseAnonKey,
    authOptions: const AuthClientOptions(autoRefreshToken: false),
    httpClient: DatingDeviceHttpClient(
      ref.watch(installIdStoreProvider).ensure,
    ),
    accessToken: () async => app.auth.currentSession?.accessToken,
  );
  ref.onDispose(client.dispose);
  return client;
});
```

Create `$D/edit_T6.py` with exactly:

```python
# Spec 2 W4b Task 6: the install's id exists from the first launch (one
# microtask in lib/app/app.dart; lib/main.dart is not edited, R15).
import pathlib, sys
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from anchor import edit
edit('lib/app/app.dart', [
    ("""import 'package:attune/app/theme/app_theme.dart';
""", """import 'package:attune/app/theme/app_theme.dart';
import 'package:attune/core/device/install_id.dart';
"""),
    ("""    Future.microtask(() {
      if (!mounted) return;
      ref.read(localeNotifierProvider.notifier).initialize();
    });""",
     """    Future.microtask(() {
      if (!mounted) return;
      ref.read(localeNotifierProvider.notifier).initialize();
    });
    // Spec 2 W4b (§3.3.4): this install's id exists from the first launch,
    // for everyone (so its presence says nothing about Dating).
    Future.microtask(() {
      if (!mounted) return;
      unawaited(ref.read(installIdStoreProvider).ensure());
    });"""),
], 'T6 app')
```

```bash
python3 -I .superpowers/sdd/2026-11-09-spec2-w4/edit_T6.py
dart format lib/core/device/install_id.dart test/core/device/install_id_test.dart test/features/dating/data/dating_supabase_client_test.dart test/architecture/dating_device_header_test.dart
flutter analyze --no-pub lib/core/device lib/features/dating lib/app/app.dart test/core/device test/features/dating/data test/architecture 2>&1 | tail -1
flutter test test/core/device test/features/dating/data test/architecture/dating_device_header_test.dart test/architecture/games_untouched_test.dart 2>&1 | tail -1
```

Expected: `lib/app/app.dart: 2 edit(s) (T6 app)`; `Formatted 4 files (0 changed)`; `No issues found!`; `All tests passed!`.

- [ ] **Step 4: Mutants**

Create `$D/mut_T6_deno.py` with exactly:

```python
# Spec 2 W4b Task 6: Deno mutants (denomut.py).
H = 'supabase/functions/dating-verification/handler.ts'
TESTS = ['dating-verification/handler.test.ts']
MUTS = {
 'reverify_writes_owner_result': (H, [("""      if (!same) {
        if (!(await finish(deps, session, "failed", "identity_failed"))) return refusal("busy");""",
     """      if (!same) {
        await call(deps, "record_dating_identity_check", {
          p_user: caller.userId, p_method: "liveness_compare", p_result: "fail", p_vendor: "fake", p_decided_by: null,
        });
        if (!(await finish(deps, session, "failed", "identity_failed"))) return refusal("busy");""")]),
 'reverify_no_trust': (H, [("""    const trusted = await call(deps, "trust_dating_device", { p_user: caller.userId, p_device_hash: caller.deviceHash });
    if (trusted?.ok !== true) return refusal(trusted?.reason ?? "busy");""", "")]),
 'reverify_start_without_phone': (H, [("""  if (isAnswer(s)) return s;
  if (caller.deviceHash === null) return refusal("reverify_device");
  const sc = scenarioFor(s.mode, body);""", """  if (isAnswer(s)) return s;
  const sc = scenarioFor(s.mode, body);""")]),
 'reverify_other_phones_session': (H, [(' || row.device_hash !== caller.deviceHash', '')]),
 'activation_phone_not_trusted': (H, [("""    if (caller.deviceHash !== null) {
      await call(deps, "trust_dating_device", { p_user: caller.userId, p_device_hash: caller.deviceHash });
    }""", "")]),
 'human_reverify_as_activation': (H, [('p_kind: reverify ? "reverify" : "activation", p_step: "human"', 'p_kind: "activation", p_step: "human"')]),
}
```

Create `$D/mut_T6.py` with exactly:

```python
# Spec 2 W4b Task 6: Dart mutants (dmut.py).
I = 'lib/core/device/install_id.dart'
C = 'lib/features/dating/data/dating_supabase_client.dart'
A = 'lib/app/app.dart'
TI = ['test/core/device/install_id_test.dart']
TC = ['test/features/dating/data/dating_supabase_client_test.dart']
TA = ['test/architecture/dating_device_header_test.dart']
MUTS = {
 'invalid_id_kept': (I, '      if (stored != null && _valid.hasMatch(stored)) return stored;', '      if (stored != null) return stored;', TI),
 'short_id': (I, '        for (var i = 0; i < 16; i++)', '        for (var i = 0; i < 8; i++)', TI),
 'id_not_kept': (I, '      await _storage.write(key: key, value: id);\n', '', TI),
 'header_not_sent': (C, '    if (id != null) request.headers[datingDeviceHeader] = id;', '', TC),
 'header_without_id': (C, '    if (id != null) request.headers[datingDeviceHeader] = id;', "    request.headers[datingDeviceHeader] = id ?? '';", TC),
 'no_first_launch_id': (A, [("import 'package:attune/core/device/install_id.dart';\n", ''),
                            ("""    Future.microtask(() {
      if (!mounted) return;
      unawaited(ref.read(installIdStoreProvider).ensure());
    });
""", '')], None, TA),
}
```

```bash
D=.superpowers/sdd/2026-11-09-spec2-w4
python3 -I $D/denomut.py $D/mut_T6_deno.py | tee $D/mut_T6_deno.txt | tail -1
python3 -I $D/dmut.py $D/mut_T6.py --check && python3 -I $D/dmut.py $D/mut_T6.py | tee $D/mut_T6.txt | tail -1
L=$(grep -A2 'name: Run Deno tests' .github/workflows/tests.yml | grep 'run: deno test' | sed 's/^ *run: //')
(cd supabase/functions && export NO_COLOR=1 && eval "$L" 2>&1 | grep -E '^(ok|FAILED) \|')
```

Expected: `6/6 killed`; `6 anchors OK`; `6/6 killed`; `ok | 161 passed | 0 failed` (Task 2's 157 and these 4). Do not commit; record the tree in the report.

### Task 7: `/dating/verify`: the re-check, the setup-restart variant, every `reverify_device` answer leading there, and the W4b gate (§3.3.4, §3.14, §3.15 row D11, §3.8; carry 9; D8; R-14, R-32)

**Files:**
- Create: `lib/features/dating/verify/reverify_route.dart`, `test/features/dating/verify/reverify_test.dart` and `test/features/dating/verify/goldens/reverify_{restart,verified}.{scale1.0,scale1.3,scale2.0,rtl}.png`, `$D/{edit_T7.py, arb_fragment_T7.txt, mut_T7.py}`
- Modify: `lib/features/dating/data/dating_home.dart` (`DatingReverifyVariant`), `lib/features/dating/routes/dating_routes.dart` (`DatingPaths.verify` and its `datingRoute`), `lib/features/dating/verify/verify_flow.dart` (`reverify`), `lib/features/dating/setup/dating_step_frame.dart`, `lib/features/dating/section/{dating_lifecycle_errors,dating_section}.dart`, `lib/features/dating/gentle_wait/gentle_wait_screen.dart` (carry 9), `test/architecture/text_scale_routes_test.dart` (`datingVerify` audited), the ARB and generated l10n

**Interfaces:**
- Consumes: Task 6's edge actions; Task 4's `DatingVerifyFlow`; W3's `DatingLifecycleGateway.exit(key, {keepNeverIntroduce})`, `datingRoute()`, `DatingMotion.none`, `datingRefusalLine`, `datingLifecycleErrorRows`.
- Produces: `DatingPaths.verify == '/dating/verify'` (behind the lock, as every `datingRoute`); `DatingReverifyRoute`, `DatingStartAgainScreen`; `DatingVerifyFlow(reverify: true)` (the standing consent, `reverify_start`/`reverify_complete`, the person as the only other way).

- [ ] **Step 1: Write the failing test**

Create `test/features/dating/verify/reverify_test.dart` with exactly:

```dart
// Spec 2 W4b (§3.3.4, §3.14; carry 9; D8): a phone Dating doesn't trust.
// Before a passed check the setup starts again there (the draft deleted as
// exit, then D1); after one, a video check (no consent box, liveness and
// CompareFaces, a person as the other way, never an ID). Every
// reverify_device answer offers the way there, behind the Dating lock.
import 'package:attune/app/theme/app_theme.dart';
import 'package:attune/core/platform/sim_country.dart';
import 'package:attune/features/dating/data/dating_home.dart';
import 'package:attune/features/dating/data/dating_lifecycle_repository.dart';
import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:attune/features/dating/gentle_wait/gentle_wait_repository.dart';
import 'package:attune/features/dating/routes/dating_routes.dart';
import 'package:attune/features/dating/section/dating_lifecycle_errors.dart';
import 'package:attune/features/dating/section/dating_section.dart';
import 'package:attune/features/dating/setup/dating_setup_providers.dart';
import 'package:attune/features/dating/setup/dating_step_frame.dart';
import 'package:attune/features/dating/setup/how_step.dart';
import 'package:attune/features/dating/verify/dating_capture.dart';
import 'package:attune/features/dating/verify/dating_verification.dart';
import 'package:attune/features/dating/verify/dating_verification_providers.dart';
import 'package:attune/features/dating/verify/reverify_route.dart';
import 'package:attune/features/onboarding/data/home_state_service.dart';
import 'package:attune/home/home_seams.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/fake_home_state.dart';
import '../../../helpers/flow_harness.dart';
import '../../../helpers/home_harness.dart';
import '../../../helpers/tap_in_reach.dart';
import '../support/dating_fakes.dart';
import '../support/dating_setup_fakes.dart';
import '../support/dating_shell.dart';
import '../support/dating_verify_fakes.dart';

const _restart = DatingHome(
  state: DatingHomeState.reverifyDevice,
  reverifyVariant: DatingReverifyVariant.setupRestart,
  hasData: true,
);
const _verifiedPhone = DatingHome(
  state: DatingHomeState.reverifyDevice,
  reverifyVariant: DatingReverifyVariant.verified,
  hasData: true,
);

/// An untrusted phone's own status read: only the device answer.
const _untrusted = DatingVerification(available: true, trustedDevice: false);

Future<(DatingShell, FakeDatingVerificationGateway)> _shell(
  WidgetTester t, {
  required DatingHome home,
  String initial = '/me',
  DatingVerification state = _untrusted,
  bool locked = false,
  bool pinSet = false,
}) async {
  final verification = FakeDatingVerificationGateway(state: state);
  final s = await pumpDatingShell(
    t,
    initial: initial,
    locked: locked,
    pinSet: pinSet,
    home: FakeDatingHomeGateway(home: home),
    extraRoutes: [
      GoRoute(
        path: '/me',
        builder:
            (_, __) => const Scaffold(
              body: SingleChildScrollView(child: DatingSection()),
            ),
      ),
    ],
    overrides: [
      datingVerificationGatewayProvider.overrideWithValue(verification),
      datingCaptureLauncherProvider.overrideWithValue(FakeCaptureLauncher()),
      datingSetupGatewayProvider.overrideWithValue(FakeDatingSetupGateway()),
      deviceCountryProvider.overrideWith(
        (ref) async => (sim: 'GB', region: null),
      ),
      homeAuthProvider.overrideWithValue(FakeHomeAuth(testUser('ama'))),
      homeStateServiceProvider.overrideWithValue(
        HomeStateService(FakeHomeStateGateway(state: homeJson(path: 'dating'))),
      ),
    ],
  );
  return (s, verification);
}

void main() {
  test('the home reads the variant; anything else is a video check', () {
    expect(
      DatingHome.fromJson({
        'state': 'reverify_device',
        'variant': 'setup_restart',
      }).reverifyVariant,
      DatingReverifyVariant.setupRestart,
    );
    for (final v in ['verified', 'something_new', null]) {
      expect(
        DatingHome.fromJson({
          'state': 'reverify_device',
          'variant': v,
        }).reverifyVariant,
        DatingReverifyVariant.verified,
        reason: '$v',
      );
    }
  });

  group('before a passed check: start again here', () {
    testWidgets('the section says so; Start again leaves (keeping the list) '
        'and opens D1', (t) async {
      final (s, _) = await _shell(t, home: _restart);
      expect(
        find.text(
          'You started setting up Dating on another phone. To keep your '
          'answers private, start again here.',
        ),
        findsOneWidget,
      );
      await tapInReach(t, find.text('Start again'));
      await t.pumpAndSettle();
      expect(find.byType(DatingStartAgainScreen), findsOneWidget);
      expect(
        find.text(
          "Your 'Never introduce me' list stays. You can delete it from Leave "
          'Dating and delete my data.',
        ),
        findsOneWidget,
      );
      s.home.home = const DatingHome(state: DatingHomeState.notStarted);
      await tapInReach(t, find.text('Start again'));
      await t.pumpAndSettle();
      expect(s.life.calls, ['exit']);
      expect(s.life.keptList, isTrue, reason: 'R-32');
      expect(s.location, DatingPaths.step('how'));
      expect(find.byType(DatingHowStep), findsOneWidget);
    });

    testWidgets('a refused leave shows its words and stays', (t) async {
      final (s, _) = await _shell(
        t,
        home: _restart,
        initial: DatingPaths.verify,
      );
      s.life.result = const DatingLifecycleResult.refused(
        DatingLifecycleError.busy,
      );
      await tapInReach(t, find.text('Start again'));
      await t.pumpAndSettle();
      expect(
        find.text(
          'This is taking a little longer than usual. Try again in a moment.',
        ),
        findsOneWidget,
      );
      expect(find.byType(DatingStartAgainScreen), findsOneWidget);
    });
  });

  group('after a passed check: a video check here', () {
    testWidgets('no consent box; the re-check actions; verified, back to Me', (
      t,
    ) async {
      final (s, verification) = await _shell(t, home: _verifiedPhone);
      expect(
        find.text("Confirm it's you on this phone to see Dating."),
        findsOneWidget,
      );
      await tapInReach(t, find.text("Verify it's you"));
      await t.pumpAndSettle();
      expect(
        find.text(
          'Welcome back. Before we show Dating on this phone, please do a '
          "quick video check. It's how we keep your conversations yours.",
        ),
        findsOneWidget,
      );
      expect(find.byType(CheckboxListTile), findsNothing);
      verification.answers['reverify_start'] = [datingStarted()];
      verification.answers['reverify_complete'] = [
        datingOutcome(DatingVerifyOutcome.verified),
      ];
      verification.onAct = (a) {
        if (a == 'reverify_complete') {
          verification.state = const DatingVerification(
            available: true,
            age: DatingCheck.pass,
            identity: DatingCheck.pass,
          );
        }
      };
      await tapInReach(t, find.text('Start video check'));
      await t.pumpAndSettle();
      expect(verification.actionNames, ['reverify_start', 'reverify_complete']);
      expect(verification.consents, isEmpty, reason: 'the standing consent');
      expect(find.text("You're verified."), findsOneWidget);
      s.home.home = const DatingHome(state: DatingHomeState.active);
      await tapInReach(t, find.text('Continue'));
      await t.pumpAndSettle();
      expect(find.text('ME me'), findsOneWidget);
    });

    testWidgets('the other way is a person, never an ID', (t) async {
      final (_, verification) = await _shell(
        t,
        home: _verifiedPhone,
        initial: DatingPaths.verify,
      );
      verification.answers['reverify_start'] = [datingStarted()];
      verification.answers['reverify_complete'] = [
        datingOutcome(DatingVerifyOutcome.anotherWay),
      ];
      await tapInReach(t, find.text('Start video check'));
      await t.pumpAndSettle();
      expect(find.text('Check with my ID'), findsNothing);
      verification.answers['human_start'] = [
        const DatingVerifyAnswer(
          ok: true,
          sessionId: datingTestSession,
          gestures: ['left_ear', 'thumbs_up'],
          paths: ['$datingTestSession/1.jpg', '$datingTestSession/2.jpg'],
        ),
      ];
      await tapInReach(t, find.text('Ask a person to review it'));
      await t.pumpAndSettle();
      expect(verification.actions.last.$1, 'human_start');
      expect(verification.actions.last.$2, {'reverify': true});
      expect(find.text('Take two quick photos'), findsWidgets);
    });

    testWidgets('Check another way on the intro goes to a person directly', (
      t,
    ) async {
      final (_, verification) = await _shell(
        t,
        home: _verifiedPhone,
        initial: DatingPaths.verify,
      );
      verification.answers['human_start'] = [
        datingRefused(DatingVerifyRefusal.busy),
      ];
      await tapInReach(t, find.text('Check another way'));
      await t.pumpAndSettle();
      expect(verification.actions.single.$1, 'human_start');
      expect(verification.actions.single.$2, {'reverify': true});
    });

    testWidgets('a person is checking this phone: the waiting screen', (
      t,
    ) async {
      await _shell(
        t,
        home: _verifiedPhone,
        initial: DatingPaths.verify,
        state: const DatingVerification(
          available: true,
          trustedDevice: false,
          session: DatingVerifySession(
            id: datingTestSession,
            kind: 'reverify',
            step: 'human',
            state: 'awaiting_review',
            open: true,
          ),
        ),
      );
      expect(
        find.text(
          "A person is checking. This usually takes less than a day. We'll "
          'show the result here.',
        ),
        findsOneWidget,
      );
    });
  });

  testWidgets('behind the Dating lock (§3.14)', (t) async {
    final (s, _) = await _shell(
      t,
      home: _verifiedPhone,
      initial: DatingPaths.verify,
      locked: true,
      pinSet: true,
    );
    expect(s.location, startsWith('/dating/unlock?from='));
    expect(find.text('Enter your Safety PIN'), findsOneWidget);
    expect(find.textContaining('Welcome back'), findsNothing);
  });

  group('carry 9: every reverify_device answer leads here', () {
    for (final (name, build)
        in <(String, Widget Function(BuildContext, AppLocalizations))>[
          (
            'a setup writer',
            (c, loc) => datingRefusalLine(
              loc,
              const DatingWrite(ok: false, reason: 'reverify_device'),
            ),
          ),
          (
            'a lifecycle refusal',
            (c, loc) => Column(
              children: datingLifecycleErrorRows(
                c,
                loc,
                DatingLifecycleError.reverifyDevice,
              ),
            ),
          ),
        ]) {
      testWidgets(name, (t) async {
        final s = await pumpDatingShell(
          t,
          initial: '/rows',
          home: FakeDatingHomeGateway(home: _verifiedPhone),
          extraRoutes: [
            GoRoute(
              path: '/rows',
              builder:
                  (context, __) => Scaffold(
                    body: build(context, AppLocalizations.of(context)!),
                  ),
            ),
          ],
          overrides: [
            datingVerificationGatewayProvider.overrideWithValue(
              FakeDatingVerificationGateway(state: _untrusted),
            ),
          ],
        );
        expect(
          find.text("Confirm it's you on this phone to see Dating."),
          findsOneWidget,
        );
        await tapInReach(t, find.text("Verify it's you"));
        await t.pumpAndSettle();
        expect(find.byType(DatingReverifyRoute), findsOneWidget);
        expect(s.location, '/rows', reason: 'pushed over it');
      });
    }
  });

  testWidgets('carry 9: the gentle wait\'s refused save leads here too', (
    t,
  ) async {
    final s = await pumpDatingShell(
      t,
      initial: DatingPaths.step('wait'),
      home: FakeDatingHomeGateway(home: _verifiedPhone),
      overrides: [
        datingVerificationGatewayProvider.overrideWithValue(
          FakeDatingVerificationGateway(state: _untrusted),
        ),
      ],
    );
    s.wait.result = GentleWaitSave.reverifyDevice;
    await t.enterText(find.byKey(const ValueKey('gentle_wait_q2')), 'Kindness');
    await tapInReach(t, find.text('Save my answers'));
    await t.pumpAndSettle();
    expect(
      find.text("Confirm it's you on this phone to see Dating."),
      findsOneWidget,
    );
    await tapInReach(t, find.text("Verify it's you"));
    await t.pumpAndSettle();
    expect(find.byType(DatingReverifyRoute), findsOneWidget);
  });

  testWidgets('D8: the next account starts from nothing on Start again', (
    t,
  ) async {
    final (s, _) = await _shell(t, home: _restart, initial: DatingPaths.verify);
    s.life.result = const DatingLifecycleResult.refused(
      DatingLifecycleError.failed,
    );
    await tapInReach(t, find.text('Start again'));
    await t.pumpAndSettle();
    expect(find.text('Something went wrong. Try again.'), findsOneWidget);
    s.container.read(datingTestAccount.notifier).state = 'kofi';
    await t.pump();
    expect(find.text('Something went wrong. Try again.'), findsNothing);
    await t.pumpAndSettle();
  });

  testWidgets('large text at 2.0 and the dark theme', (t) async {
    final semantics = t.ensureSemantics();
    for (final home in [_restart, _verifiedPhone]) {
      for (final theme in [AppTheme.lightTheme, AppTheme.darkTheme]) {
        await pumpFlowScreen(
          t,
          () => Theme(data: theme, child: const DatingReverifyRoute()),
          textScale: 2.0,
          overrides: datingShellOverrides(
            home: FakeDatingHomeGateway(home: home),
            verification: FakeDatingVerificationGateway(state: _untrusted),
          ),
        );
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        expect(
          t.widget<Scaffold>(find.byType(Scaffold).first).backgroundColor,
          theme.colorScheme.surface,
        );
        await expectFlowGuidelines(t);
      }
    }
    semantics.dispose();
  });

  for (final (name, home) in [
    ('reverify_restart', _restart),
    ('reverify_verified', _verifiedPhone),
  ]) {
    testWidgets('$name goldens', (t) async {
      await expectFlowGoldens(
        t,
        name,
        () => const DatingReverifyRoute(),
        overrides: datingShellOverrides(
          home: FakeDatingHomeGateway(home: home),
          verification: FakeDatingVerificationGateway(state: _untrusted),
        ),
        before: (t) => t.pumpAndSettle(),
      );
    });
  }
}
```

```bash
flutter test test/features/dating/verify/reverify_test.dart 2>&1 | tr '\r' '\n' | grep -m1 -o "Error: Error when reading '[^']*'"
```

Expected: `Error: Error when reading 'lib/features/dating/verify/reverify_route.dart'`.

- [ ] **Step 2: The route, the copy and the edits**

Create `lib/features/dating/verify/reverify_route.dart` with exactly:

```dart
// Spec 2 W4b (§3.3.4; carry 9): /dating/verify, where every
// reverify_device answer leads. Before a passed check (setup_restart):
// "You started setting up Dating on another phone…" and Start again, which
// leaves Dating (the draft hard-deleted, as exit, §3.8) and opens D1 here,
// keeping the 'Never introduce me' list (R-32, owner ruling 2026-11-09).
// After one (verified): the video check on this phone (liveness and
// CompareFaces, no age), or a person checks two photos. What the person
// sees follows the home's answer, read again on every open (D8: nothing
// of one account shown to the next).
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/dating/data/dating_home.dart';
import 'package:attune/features/dating/data/dating_lifecycle_repository.dart';
import 'package:attune/features/dating/data/dating_providers.dart';
import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:attune/features/dating/gentle_wait/gentle_wait_providers.dart'
    show datingOnlineProvider;
import 'package:attune/features/dating/routes/dating_routes.dart';
import 'package:attune/features/dating/section/dating_lifecycle_errors.dart';
import 'package:attune/features/dating/setup/dating_step_frame.dart';
import 'package:attune/features/dating/verify/verify_flow.dart';
import 'package:attune/features/onboarding/domain/home_state.dart' show AppTab;
import 'package:attune/home/home_location.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class DatingReverifyRoute extends ConsumerWidget {
  const DatingReverifyRoute({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(datingAccountProvider);
    final home = ref.watch(datingHomeProvider(account));
    void toMe() => context.go(homeLocation(tab: AppTab.me));
    void back() => context.canPop() ? context.pop() : toMe();
    final h = home.valueOrNull;
    if (h == null) {
      return home.hasError
          ? DatingVerifyFlow(
            step: 'reverify',
            reverify: true,
            onBack: back,
            onDone: toMe,
            onChangePhotos: () {},
          )
          : const Scaffold(body: SizedBox.shrink());
    }
    if (h.state == DatingHomeState.reverifyDevice &&
        h.reverifyVariant == DatingReverifyVariant.setupRestart) {
      return DatingStartAgainScreen(onBack: back);
    }
    return DatingVerifyFlow(
      step: 'reverify',
      reverify: true,
      onBack: back,
      onDone: () {
        ref.invalidate(datingHomeProvider(account));
        toMe();
      },
      onChangePhotos: () {},
    );
  }
}

/// §3.3.4's setup_restart: the draft was started on another phone.
class DatingStartAgainScreen extends ConsumerStatefulWidget {
  const DatingStartAgainScreen({super.key, required this.onBack});

  final VoidCallback onBack;

  @override
  ConsumerState<DatingStartAgainScreen> createState() =>
      _DatingStartAgainScreenState();
}

class _DatingStartAgainScreenState
    extends ConsumerState<DatingStartAgainScreen> {
  // D8: nothing here outlives the account. The route reads the home per
  // account and shows nothing while the next one loads, so another
  // account always gets a new screen (keys, busy and the refusal with it).
  final DatingActionKeys _keys = DatingActionKeys();
  bool _busy = false;
  DatingLifecycleError? _error;

  Future<void> _startAgain() async {
    if (_busy) return;
    final account = ref.read(datingAccountProvider);
    setState(() {
      _busy = true;
      _error = null;
    });
    final DatingLifecycleResult r = await ref
        .read(datingLifecycleGatewayProvider)
        .exit(_keys.keyFor('start_again', account), keepNeverIntroduce: true);
    _keys.settle('start_again', error: r.error);
    if (!mounted || ref.read(datingAccountProvider) != account) return;
    setState(() {
      _busy = false;
      _error = r.error;
    });
    if (r.ok) {
      ref.invalidate(datingHomeProvider(account));
      context.go(DatingPaths.step('how'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final online = ref.watch(datingOnlineProvider).valueOrNull ?? true;
    final error = _error;
    return DatingStepFrame(
      step: 'reverify',
      title: loc.flow_slotDatingTitle,
      onBack: widget.onBack,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            loc.dating_reverifyRestart,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: Spacing.sm),
          Text(
            loc.dating_reverifyRestartKeeps,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: Spacing.md),
          if (error != null) ...datingLifecycleErrorRows(context, loc, error),
        ],
      ),
      primary: FlowPrimaryButton(
        label: loc.dating_startAgain,
        busy: _busy,
        onPressed: online && !_busy ? _startAgain : null,
      ),
    );
  }
}
```

Create `$D/arb_fragment_T7.txt` with exactly:

```text
  "dating_reverifyBody": "Welcome back. Before we show Dating on this phone, please do a quick video check. It's how we keep your conversations yours.",
  "@dating_reverifyBody": {"description": "Spec 2 §3.3.4 re-verification on a new phone."},
  "dating_reverifyRestart": "You started setting up Dating on another phone. To keep your answers private, start again here.",
  "@dating_reverifyRestart": {"description": "Spec 2 §3.3.4 setup_restart."},
  "dating_startAgain": "Start again",
  "@dating_startAgain": {"description": "Spec 2 §3.3.4 setup_restart: deletes the draft (as exit, keeping the 'Never introduce me' list, R-32) and opens D1."},
  "dating_reverifyRestartKeeps": "Your 'Never introduce me' list stays. You can delete it from Leave Dating and delete my data.",
  "@dating_reverifyRestartKeeps": {"description": "Spec 2 §3.3.4 setup_restart (R-32, owner ruling 2026-11-09; plan copy)."}
```

Create `$D/edit_T7.py` with exactly:

```python
# Spec 2 W4b Task 7: the re-verification UI (§3.3.4) and every
# reverify_device answer leading to it (carry 9). Exact anchors in the
# formatted files; each edit written in dart format style.
import pathlib, sys
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from anchor import edit

edit('lib/features/dating/data/dating_home.dart', [
    ("""/// "Tell me when it's here" (§2.7): whether it can be asked for here, and""",
     """/// Spec 2 W4b (§3.3.4): which re-check an untrusted phone needs. Before a
/// passed check the setup starts again there; after one, a video check
/// (anything else reads as that).
enum DatingReverifyVariant {
  setupRestart('setup_restart'),
  verified('verified');

  const DatingReverifyVariant(this.wire);

  final String wire;

  static DatingReverifyVariant fromWire(Object? value) =>
      value == setupRestart.wire ? setupRestart : verified;
}

/// "Tell me when it's here" (§2.7): whether it can be asked for here, and"""),
    ("""    this.notice = const DatingNotice(),
  });""",
     """    this.notice = const DatingNotice(),
    this.reverifyVariant = DatingReverifyVariant.verified,
  });"""),
    ("""  final DatingNotice notice;
""",
     """  final DatingNotice notice;

  /// reverify_device only (Spec 2 W4b).
  final DatingReverifyVariant reverifyVariant;
"""),
    ("""      notice: DatingNotice.fromJson(json['notify']),
""",
     """      notice: DatingNotice.fromJson(json['notify']),
      reverifyVariant: DatingReverifyVariant.fromWire(json['variant']),
"""),
], 'T7 home')

edit('lib/features/dating/routes/dating_routes.dart', [
    ("""import 'package:attune/features/dating/settings/dating_settings_screen.dart';""",
     """import 'package:attune/features/dating/settings/dating_settings_screen.dart';
import 'package:attune/features/dating/verify/reverify_route.dart';"""),
    ("""  static const leave = '/dating/leave';""",
     """  static const leave = '/dating/leave';

  /// Spec 2 W4b (§3.3.4, §3.14): where every reverify_device answer leads.
  static const verify = '/dating/verify';"""),
    ("""  datingRoute(
    DatingPaths.leave,
    'datingLeave',
    signedIn,
    (s) => const DatingLeaveScreen(),
    motion: (s) => DatingMotion.none,
  ),
];""",
     """  datingRoute(
    DatingPaths.leave,
    'datingLeave',
    signedIn,
    (s) => const DatingLeaveScreen(),
    motion: (s) => DatingMotion.none,
  ),
  // Spec 2 W4b: the check's outcomes are never animated (§3.0).
  datingRoute(
    DatingPaths.verify,
    'datingVerify',
    signedIn,
    (s) => const DatingReverifyRoute(),
    motion: (s) => DatingMotion.none,
  ),
];"""),
], 'T7 routes')

F = 'lib/features/dating/verify/verify_flow.dart'
edit(F, [
    ("""    required this.onChangePhotos,
  });""",
     """    required this.onChangePhotos,
    this.reverify = false,
  });"""),
    ("""  /// "Change that photo" (§3.3.2): D9.
  final VoidCallback onChangePhotos;
""",
     """  /// "Change that photo" (§3.3.2): D9.
  final VoidCallback onChangePhotos;

  /// Spec 2 W4b (§3.3.4): the re-check on an untrusted phone: the
  /// standing consent, liveness and CompareFaces only, the human route as
  /// the other way (no ID route).
  final bool reverify;
"""),
    ("""    if (_consentRecorded) return true;""",
     """    if (_consentRecorded || widget.reverify) return true;"""),
    ("""    var started = await gateway.act('start');""",
     """    final start = widget.reverify ? 'reverify_start' : 'start';
    var started = await gateway.act(start);"""),
    ("""      started = await gateway.act('start', {'scenario': capture.scenario});""",
     """      started = await gateway.act(start, {'scenario': capture.scenario});"""),
    ("""    final done = await gateway.act('complete', {
      'session_id': started.sessionId,
    });""",
     """    final done = await gateway.act(
      widget.reverify ? 'reverify_complete' : 'complete',
      {'session_id': started.sessionId},
    );"""),
    ("""    final a = await ref
        .read(datingVerificationGatewayProvider)
        .act('human_start');""",
     """    final a = await ref.read(datingVerificationGatewayProvider).act(
      'human_start',
      {if (widget.reverify) 'reverify': true},
    );"""),
    ("""    final ready = _consent && online && !_busy && _state.available;""",
     """    final ready =
        (_consent || widget.reverify) && online && !_busy && _state.available;"""),
    ("""          _text(loc.dating_verifyBody),""",
     """          _text(
            widget.reverify ? loc.dating_reverifyBody : loc.dating_verifyBody,
          ),"""),
    ("""          CheckboxListTile(
            key: const ValueKey('dating_verify_consent'),
            value: _consent,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(loc.dating_verifyConsent),
            onChanged: (v) => setState(() => _consent = v ?? false),
          ),""",
     """          // Spec 2 W4b: a re-check runs on the standing consent.
          if (!widget.reverify)
            CheckboxListTile(
              key: const ValueKey('dating_verify_consent'),
              value: _consent,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(loc.dating_verifyConsent),
              onChanged: (v) => setState(() => _consent = v ?? false),
            ),"""),
    ("""          onPressed:
              _consent && online && !_busy && _state.available
                  ? () => setState(() {
                    _refusal = null;
                    _stage = DatingVerifyStage.another;
                  })
                  : null,""",
     """          onPressed:
              !ready
                  ? null
                  : widget.reverify
                  ? _humanStart
                  : () => setState(() {
                    _refusal = null;
                    _stage = DatingVerifyStage.another;
                  }),"""),
    ("""      DatingVerifyOutcome.anotherWay => (""",
     """      // Spec 2 W4b: a re-check's other way is a person, never an ID.
      DatingVerifyOutcome.anotherWay when widget.reverify => (
        [loc.dating_verifyStillNotWorking],
        FlowPrimaryButton(
          label: loc.dating_verifyAskPerson,
          busy: _busy,
          onPressed: online && !_busy ? _humanStart : null,
        ),
        [
          FlowTextLink(
            label: loc.dating_verifyTryAgain,
            alignment: AlignmentDirectional.centerStart,
            onPressed:
                () => setState(() {
                  _outcome = DatingVerifyOutcome.unknown;
                  _stage = DatingVerifyStage.intro;
                }),
          ),
        ],
      ),
      DatingVerifyOutcome.anotherWay => ("""),
], 'T7 flow')

# Carry 9: every reverify_device answer offers the way on.
edit('lib/features/dating/setup/dating_step_frame.dart', [
    ("""    'path_not_dating' => (loc.dating_openHowYouUse, RouteNames.howYouUseAttune),
    _ => (null, null),""",
     """    'path_not_dating' => (loc.dating_openHowYouUse, RouteNames.howYouUseAttune),
    // Spec 2 W4b (carry 9): the re-check on this phone.
    'reverify_device' => (loc.dating_verifyTitle, DatingPaths.verify),
    _ => (null, null),"""),
], 'T7 step frame')
edit('lib/features/dating/section/dating_lifecycle_errors.dart', [
    ("""    DatingLifecycleError.reverifyDevice => [
      DatingCalmLine(loc.dating_sectionReverify),
    ],""",
     """    DatingLifecycleError.reverifyDevice => [
      DatingCalmLine(loc.dating_sectionReverify),
      // Spec 2 W4b (carry 9): the re-check on this phone.
      link(loc.dating_verifyTitle, () => context.push(DatingPaths.verify)),
    ],"""),
], 'T7 lifecycle errors')
edit('lib/features/dating/section/dating_section.dart', [
    ("""      DatingLifecycleError.reverifyDevice => [
        _Calm(loc.dating_sectionReverify),
      ],""",
     """      DatingLifecycleError.reverifyDevice => [
        _Calm(loc.dating_sectionReverify),
        // Spec 2 W4b (carry 9): the re-check on this phone.
        link(loc.dating_verifyTitle, DatingPaths.verify),
      ],"""),
    ("""      case DatingHomeState.reverifyDevice:
        return _plain(loc, loc.dating_sectionReverify, settings);""",
     """      // Spec 2 W4b (§3.3.4): the re-check, or the setup again, here.
      case DatingHomeState.reverifyDevice:
        final restart = h.reverifyVariant == DatingReverifyVariant.setupRestart;
        return _SectionCard(
          title: loc.flow_slotDatingTitle,
          lines: [
            restart ? loc.dating_reverifyRestart : loc.dating_sectionReverify,
          ],
          onTap: () => context.push(DatingPaths.verify),
          children: [
            FlowSecondaryButton(
              label: restart ? loc.dating_startAgain : loc.dating_verifyTitle,
              onPressed: () => context.push(DatingPaths.verify),
            ),
            if (settings != null) settings,
          ],
        );"""),
], 'T7 section')
edit('lib/features/dating/gentle_wait/gentle_wait_screen.dart', [
    ("""import 'package:attune/features/dating/gentle_wait/gentle_wait_repository.dart';""",
     """import 'package:attune/features/dating/gentle_wait/gentle_wait_repository.dart';
import 'package:attune/features/dating/routes/dating_routes.dart'
    show DatingPaths;"""),
    ("""  Widget _unavailable(AppLocalizations loc) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _CalmLine(text: loc.dating_sectionReverify),""",
     """  Widget _unavailable(AppLocalizations loc) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _CalmLine(text: loc.dating_sectionReverify),
      // Spec 2 W4b (carry 9): the re-check on this phone.
      FlowTextLink(
        label: loc.dating_verifyTitle,
        alignment: AlignmentDirectional.centerStart,
        onPressed: () => context.push(DatingPaths.verify),
      ),"""),
    ("""        if (_status == _Status.reverify) ...[
          const SizedBox(height: Spacing.sm),
          _CalmLine(text: loc.dating_sectionReverify),
        ],""",
     """        if (_status == _Status.reverify) ...[
          const SizedBox(height: Spacing.sm),
          _CalmLine(text: loc.dating_sectionReverify),
          // Spec 2 W4b (carry 9): the re-check on this phone.
          FlowTextLink(
            label: loc.dating_verifyTitle,
            alignment: AlignmentDirectional.centerStart,
            onPressed: () => context.push(DatingPaths.verify),
          ),
        ],"""),
], 'T7 gentle wait')

# The W10 route audit (W-m2): /dating/verify is audited (reverify_test's
# large-text audit at 2.0 and the D11 flow's).
edit('test/architecture/text_scale_routes_test.dart', [
    ("""  'datingLeave',
  'aboutUs',""",
     """  'datingLeave',
  // Spec 2 W4b (§3.3.4): the re-check on a new phone.
  'datingVerify',
  'aboutUs',"""),
], 'T7 route audit')
```

```bash
D=.superpowers/sdd/2026-11-09-spec2-w4
python3 -I .superpowers/sdd/2026-10-26-spec1-w3/arb_append.py $D/arb_fragment_T7.txt
flutter gen-l10n --arb-dir=lib/i10n --template-arb-file=app_en.arb --output-dir=lib/i10n/generated --output-localization-file=app_localizations.dart --no-synthetic-package > /dev/null 2>&1; echo "gen-l10n exit=$?"
python3 -I $D/edit_T7.py
dart format lib/features/dating/verify/reverify_route.dart test/features/dating/verify/reverify_test.dart
dart format --output=none --set-exit-if-changed lib/features/dating/verify/verify_flow.dart; echo "verify_flow unchanged by the formatter: exit=$?"
flutter analyze --no-pub lib/features/dating test/features/dating test/architecture 2>&1 | tail -1
```

Expected: `added 4 keys`; `gen-l10n exit=0`; eight edit lines (`dating_home.dart: 4`, `dating_routes.dart: 3`, `verify_flow.dart: 12`, `dating_step_frame.dart: 1`, `dating_lifecycle_errors.dart: 1`, `dating_section.dart: 2`, `gentle_wait_screen.dart: 3`, `text_scale_routes_test.dart: 1`); `Formatted 2 files (0 changed)`; `Formatted 1 file (0 changed)` and `exit=0` (Task 7's edits to Task 4's file are formatter style already); `No issues found!`.

- [ ] **Step 3: The goldens, the tests, the large-text audit**

```bash
flutter test --update-goldens test/features/dating/verify/reverify_test.dart 2>&1 | tail -1
flutter test test/features/dating test/architecture 2>&1 | tail -1
python3 scripts/large_text_audit.py --scale 2.0 test/features/dating/verify 2>&1 | tail -1
```

Expected: `All tests passed!` twice; goldens written for `reverify_restart` and `reverify_verified` (×4) — open each `scale2.0.png`: the line, Start again or Start video check and "Check another way" reachable, nothing clipped; `SCALE 2.0: 0 site(s) to fix, 0 listed apart`.

- [ ] **Step 4: Mutants**

Create `$D/mut_T7.py` with exactly:

```python
# Spec 2 W4b Task 7: Dart mutants (dmut.py). Anchors are the formatted text.
S = 'lib/features/dating/section/dating_section.dart'
R = 'lib/features/dating/verify/reverify_route.dart'
F = 'lib/features/dating/verify/verify_flow.dart'
P = 'lib/features/dating/setup/dating_step_frame.dart'
L = 'lib/features/dating/section/dating_lifecycle_errors.dart'
H = 'lib/features/dating/data/dating_home.dart'
G = 'lib/features/dating/gentle_wait/gentle_wait_screen.dart'
T = ['test/features/dating/verify/reverify_test.dart']
MUTS = {
 'section_ignores_variant': (S, '            restart ? loc.dating_reverifyRestart : loc.dating_sectionReverify,', '            loc.dating_sectionReverify,', T),
 'start_again_drops_list': (R, "        .exit(_keys.keyFor('start_again', account), keepNeverIntroduce: true);",
                            "        .exit(_keys.keyFor('start_again', account), keepNeverIntroduce: false);", T),
 'start_again_stays': (R, "      context.go(DatingPaths.step('how'));", '', T),
 'reverify_as_activation': (F, "    final start = widget.reverify ? 'reverify_start' : 'start';", "    final start = 'start';", T),
 'consent_box_on_reverify': (F, '          if (!widget.reverify)\n', '          if (true)\n', T),
 'reverify_offers_id': (F, '      DatingVerifyOutcome.anotherWay when widget.reverify => (', '      DatingVerifyOutcome.anotherWay when false => (', T),
 'reverify_another_stage': (F, '                  : widget.reverify\n', '                  : false\n', T),
 'writer_refusal_no_link': (P, "    'reverify_device' => (loc.dating_verifyTitle, DatingPaths.verify),\n", '', T),
 'lifecycle_refusal_no_link': (L, '      link(loc.dating_verifyTitle, () => context.push(DatingPaths.verify)),\n', '', T),
 'variant_unknown_restarts': (H, '      value == setupRestart.wire ? setupRestart : verified;', '      value == verified.wire ? verified : setupRestart;', T),
 'gentle_wait_no_link': (G, """          _CalmLine(text: loc.dating_sectionReverify),
          // Spec 2 W4b (carry 9): the re-check on this phone.
          FlowTextLink(""", """          _CalmLine(text: loc.dating_sectionReverify),
          // Spec 2 W4b (carry 9): the re-check on this phone.
          if (false) FlowTextLink(""", T),
}
```

```bash
D=.superpowers/sdd/2026-11-09-spec2-w4
python3 -I $D/dmut.py $D/mut_T7.py --check && python3 -I $D/dmut.py $D/mut_T7.py | tee $D/mut_T7.txt | tail -1
```

Expected: `11 anchors OK`; `11/11 killed`.

- [ ] **Step 5: The W4b gate**

```bash
D=.superpowers/sdd/2026-11-09-spec2-w4
$D/suite.sh attune_spec3a > $D/sql-W4b.txt; echo "$(grep -c '^PASS' $D/sql-W4b.txt) PASS, $(grep -c '^FAIL' $D/sql-W4b.txt) FAIL"
diff <(grep '^FAIL' $D/sql-baseline.txt) <(grep '^FAIL' $D/sql-W4b.txt) && echo "no new FAIL"
flutter analyze --no-pub lib test > $D/analyze-W4b.txt 2>&1; tail -1 $D/analyze-W4b.txt
diff <(grep -E '^ *(info|warning|error) ' $D/analyze-baseline.txt | sed -E 's/:[0-9]+:[0-9]+ / /' | sort) <(grep -E '^ *(info|warning|error) ' $D/analyze-W4b.txt | sed -E 's/:[0-9]+:[0-9]+ / /' | sort) && echo "no new issue"
flutter test --reporter compact > $D/flutter-W4b.txt 2>&1; tr '\r' '\n' < $D/flutter-W4b.txt | grep -E '^[0-9:]+ \+[0-9]+' | tail -1
shasum -c .superpowers/sdd/2026-11-04-spec1-w10-accessibility-docs/w10-1.0.sha | grep -vc ': OK$'
shasum -c .superpowers/sdd/2026-11-04-spec1-w9/flag_off.sha | grep -vc ': OK$'
shasum -c .superpowers/sdd/2026-11-07-spec2-w3/latch.sha
flutter test test/architecture/games_untouched_test.dart 2>&1 | tail -1
L=$(grep -A2 'name: Run Deno tests' .github/workflows/tests.yml | grep 'run: deno test' | sed 's/^ *run: //')
(cd supabase/functions && export NO_COLOR=1 && eval "$L" 2>&1 | grep -E '^(ok|FAILED) \|')
git status --short supabase/migrations | sort
```

Expected: `160 PASS, 14 FAIL`; `no new FAIL`; `571 issues found.`; `no new issue`; `+8049: All tests passed!` (W4a's 8027 and W4b's 22: Task 6's 7, Task 7's 15; a known flake outside Dating may fail on a given run: name it); `0`; `0`; `lib/home/home_screen.dart: OK`; `All tests passed!`; `ok | 161 passed | 0 failed`; the four new migration files as `??`. The race script ran in Task 5 (29 PASS). Do not commit; record the tree in the report.

---

## Owner checklist (nothing here is done by an implementer)

1. **W4's production gate (spec §8 W4; the flag `dating_age_assurance` cannot turn on in production until each is recorded in `private.flag_production_gates`).**
   - A **signed facial age estimation vendor contract**: a method recognised as highly effective for UK age assurance, with error data across skin tones including West African faces, and deletion terms (nothing kept after the call). Until then everyone in production takes the ID route (R-9); the estimation adapter goes behind `providers.ts`'s seam.
   - A **signed Smile ID (or equivalent) contract** for the ID route (Ghana Card, passport, UK driving licence), with no images returned or kept beyond the job (the function asks for none).
   - The **DPIA's biometric section**: the face frame, photo bytes, the estimate and the ID's date of birth live only inside one call (zeroed after use), no S3 output, no audit images, no vendor reference in the app's status read (only a start's answer carries the vendor's session id, which the capture needs); sessions 30 days, review photos 72 hours, the pass/fail result kept while the account is on Dating (§4.8). It must back D11's consent line "Nothing is kept after the check." and the manual's "Attune keeps only whether the check passed" (R-22), and the international-transfer basis for each vendor (§6.8).
   - The **AWS region** for Rekognition recorded (an EU or UK region; the function refuses `us-east-1` and a missing region).
   - The **UK Online Safety Act highly effective age assurance** method documented (estimation with the challenge age 25 and the ID fallback; the human route never confirms age).
2. **§7.7 device checks for W4 (release builds; after the native capture batch for real vendors, R-10; with `fake` on the development project before that).**
   - Liveness in daylight, glare, low light and with glasses; the challenge prompts' timing (1.2 s) and haptics; the light-flash warning shown before the check.
   - The app killed mid-capture and opened again: "Let's pick up where you left off.", the same session, no extra attempt used.
   - The human route end to end: two gestures, two camera photos (nothing left in the gallery or the app's files afterwards), a decision with `supabase/sql/dev_dating_review_decide.sql` (pass, fail, ask for ID), the result on the phone.
   - The ID route with Smile ID's sandbox and a Ghana Card (and a passport): pass, a date-of-birth mismatch then a Settings → Date of birth correction and Check again, a pending check read again.
   - A new phone and a restored backup on a verified account (the video check only; the old phone keeps working; a fourth phone drops the least recently used), and a setup started on one phone continued on another (Start again).
   - TalkBack and VoiceOver through D11 and `/dating/verify`: every stage named, the prompts announced, the outcome read once; 200% text on every stage; quick exit from D11 mid-check (the decoy; back in the app nothing of the check is left).
3. **Deploy (owner only; Dating stays off in production).**
   - `supabase db push` after the earlier undeployed waves (Spec 1 W1–W10, Spec 2 W1–W3), in order: `20261109100000_dating_v2_age_assurance.sql`, `20261109100010_dating_v2_age_assurance_grants.sql`, `20261109110000_dating_v2_trusted_devices.sql`, `20261109110010_dating_v2_trusted_devices_grants.sql`. Before the first: `SELECT count(*) FROM public.dating_age_verifications` on production (R-1 deletes v1 rows; expect 0).
   - Ship the W4b app build **with or before** the W4b push (R-16: a build without the header reads `reverify_device` once an account is bound).
   - Deploy `dating-verification`; delete the hosted `verify-dating-profile`.
   - Secrets for `dating-verification` (names only): `AWS_REKOGNITION_ACCESS_KEY_ID`, `AWS_REKOGNITION_SECRET_ACCESS_KEY`, `AWS_REKOGNITION_REGION` (not `us-east-1`); `SMILE_ID_PARTNER_ID`, `SMILE_ID_API_KEY`. The vault setting `age_assurance_mode` (`off` until gate 1; `sandbox` on the development project — `supabase/sql/dev_enable_spec2_dating_flags.sql` sets it there only when unset).
   - Check the cron `dating-verification-sweep` (every 15 minutes) exists after the push, and add an alert on `get_dating_operational_health()`'s `verification_oldest_waiting_hours` above 20 (the 24-hour promise, R-28).
   - Re-run `supabase/sql/dev_enable_spec2_dating_flags.sql` on the development project (it adds `dating_age_assurance` and the mode).
4. **Plan copy for the reviewers** (each marked "plan copy" in its ARB description): D11's light-flash warning, the "Check another way" sheet line, the ID thanks line, the waiting line, the far-below support line "We need to check a few things on your account. Contact support if you have questions.", the uncertain-estimate line "The video couldn't confirm your age this time. Let's check with your ID instead." (R-13), the age-not-confirmed line, the photos-first line, the re-check copy ("Welcome back. Before we show Dating on this phone…", "You started setting up Dating on another phone…", "Your 'Never introduce me' list stays…" (R-32), "Start again"), the section's verifying and verification-pause lines. The DV reviewer reads the far-below, age-not-confirmed and re-check lines (a controlling partner may see them); the cultural reviewer the document names (Ghana Card); counsel the consent line with the DPIA (R-22).
5. **Still open from W2 and W3 (unchanged by W4).**
   - The clinician's note (W2 packet §7: the 30-day length, the deleted-ex rule, the sock closure, "if you both close it sooner").
   - The DV reviewer's read of every W2 and W3 string (D0, the busy-clear and no-shortcut lines, the section states, the lock row, Clear my answers, D13's shared-phone question, the Leave copy, the neutral push).
   - The Ghanaian cultural reviewer (intention, attestation, region, side and faith lists, the card strings), the LGBTQ+ safety reviewer (off-country lines, "Why?", the country note; the plain-icon line true only after W8b), the Ghana legal opinion before any production `publish_country_config`, counsel on the Dating terms text and the DPIA reflection row.
   - W3's deploy list: `dating_push_key`, `GOOGLE_VISION_API_KEY`, `CSAM_MATCHER` and its key; deploy `process-dating-photo`, delete `upload-dating-photo`; the crons `sweep-dating-photo-orphans` and `recover-stale-dating-photo-jobs`; the alert routes (`csam_scan_stuck`, `csam_record_stuck`, `csam_unrecorded`, `vision_unavailable`, `orphan_scan_stuck`); the bucket limits; production GH/GB `dating_enabled = false` checked before W3b; ship the W3 app build.
   - W3's device checks: the Android Crop screen, iOS limited and denied photos, keyboard learning off on the sensitive text fields.
6. **Owner decisions.** Decided 2026-11-09: R-9 and R-10 approved as written; R-13 changed (a failed or uncertain estimate sends the person to the ID check; only a failed ID check and Spec 1's under-18 hold are final); R-32 changed (Start again keeps the never-introduce list). Still asked for (one line each, the rest are recorded rulings): R-35 ("failed face match" read as the ID's face match), R-12 (DOB mismatch: review, Spec 1's correction, Check again), R-14 (a re-check never writes the owner's result), R-16 (unbound until the first setup write; ship the app first), R-17 (gate 8 only for the caller's own requests), R-8 (an ID under 18 takes the far-below hold), R-22 (the "nothing kept" copy waits on the DPIA), R-23 (one line in `lib/app/app.dart`).
7. **Carried to later waves (recorded, not built here):** the native capture views and speech (R-10, a W4 follow-up batch, before §7.7's real-vendor device checks); the estimation vendor adapter (R-9, after the contract); W5: a new photo after the check needs the video again (`needs_review`, already read by `begin_dating_verification`), the card's verified mark; W7: the reviewer console over `decide_dating_human_review` (R-26) and the appeal route for an age fail (R-13); W8b: the country note's location variant (R-18).

---

## Spec coverage (self-review)

| Spec | Where |
|---|---|
| §3.3.1 the rule (live person, every photo, 18+ by estimate at 25 or ID, no typed DOB) | Task 1 (B, C, D; mutants `m8_*`, `gate_typed_dob`), Task 2 (the decision table; mutant 8) |
| §3.3.2 D11 (intro, consent, capture, outcomes, the ID route, waiting) | Task 4; Task 2 (outcomes); Task 1 (H, J, K, L) |
| §3.3.2 "During capture" (prompts, speech, haptics, light warning) | Task 3 (`DatingCaptureVoice`; R-10, R-11), Task 4 (the warning) |
| §3.3.3 the human route | Task 1 (I; the bucket and policy), Task 2 (`human_start`, `submit_human`), Task 4 (camera only, files deleted) |
| §3.3.4 trusted devices and re-verification | Task 5 (Q–T, race), Task 6 (install id, header, re-check), Task 7 (`/dating/verify`) |
| §3.3.5 the vendor seam, `fake` refused in production, `us-east-1` refused | Task 1 (P, `fake_in_production`), Task 2 (`providers.ts`, `aws.ts`, `smile_id.ts`) |
| §3.1 `verifying`, `reverify_device`, the verification pause | Task 1 (K), Task 3, Task 5 (home variant), Task 7 |
| §3.14 `/dating/verify` | Task 7 (behind the lock: `behind the Dating lock (§3.14)`) |
| §3.15 row D11 (motion, accessibility, errors) | Task 4 (fade 400 ms, none under reduce motion; large text; dark theme; the vendor's calm line) |
| §2.1 gate 8 | Task 5 (S; R-17) |
| §4.3 tables | Task 1 (`dating_age_verifications`, `dating_verification_sessions`), Task 5 (`dating_trusted_devices`) |
| §4.4 functions | Tasks 1 and 5 |
| §4.5 the review bucket | Task 1 (bucket, policy, canary, `storage_bucket_policies.sql`) |
| §4.7 `dating-verification`; `verify-dating-profile` removed | Tasks 2 and 6 |
| §4.8 retention | Task 1 (M: the sweep; N: exit) |
| §4.9 W4a, W4b | Tasks 1 and 5 |
| §4.10 W4 rows | Tasks 3, 4, 6, 7 (client files), Task 4 (manual, carry 4) |
| §6.2–§6.3 `age_review` | Task 1 (F, G; R-8, R-30) |
| §6.8 biometric data and transfers | Task 2 (nothing kept or logged; tests), Owner checklist 1 |
| §7.1 contracts | `dating_v2_verification_contracts.sql` A–T, `storage_bucket_policies.sql`, the canary |
| §7.2 S1, S2, S5, S7, S16, S19 | Task 4 (S1 copy, S5 D8, S16 quick exit), Task 1 (S2), Task 6 (S7 header, S19 the one key) |
| §7.3 Deno | Tasks 2 and 6 (frozen lock, CI line) |
| §7.4 the header architecture test | Task 6 |
| §7.5 mutants 8 and 9 | Task 1 (`m8_fae_below_challenge`, `m8a_writer_only`), Task 2 (`m8_*`), Task 5 (`m9_profile_read_unguarded`) |
| §7.6 gates | Tasks 4 and 7 |
| §7.7 W4 device checks | Owner checklist 2 |
| §8 W4 gate | Owner checklist 1 |
| §9 R8, R15 | Task 1 (R8: far below → Spec 1's hold), Task 6 (R15: `lib/main.dart` untouched; one line in `app.dart`) |
| I-7, S-7, C-6, R-6, W-3 | Task 1 (I-7), Task 6 (S-7, C-6), Task 1 sweep (R-6), Task 4 (W-3: D11 behind the lock through `datingRoute`) |
| carries 1–11 | the Carries table |

Placeholder scan: no "TBD"/"TODO"/"fill in" in a step; every step gives its exact file, code, command and expected line. Type consistency checked by name across tasks: `DatingVerification` (`available`, `trustedDevice`, `age`, `identity`, `session`, `idDocuments`, `photosReady`), `DatingVerifySession` (`id`, `kind`, `step`, `state`, `attempts`, `outcome`, `position`, `open`, `gestures`), `DatingVerifyAnswer` (`ok`, `refusal`, `outcome`, `position`, `sessionId`, `vendor`, `vendorRef`, `gestures`, `paths`, `attempts`, `resumed`), `DatingCaptureResult` (`kind`, `scenario`), `DatingHome.reverifyVariant`. Where a step says an anchor misses, the instruction is to stop and report.

---

## Replay record (2026-11-09)

The plan was replayed twice from the repo's tree at `7ddbe9c2` (plus the owner's two uncommitted files) in a fresh scratch copy, on a fresh clone of `attune_spec3a`, by a script that writes every "Create … with exactly" / "Replace the whole of … with exactly" block and runs every `bash` block in order (Tasks 1–7), with the database name swapped for the clone's. The first replay found only Expected-line and output-filter fixes (the error lines Step 6 and Task 5 Step 2 print, the ARB tool's `added N keys`, the formatter's file counts, the Deno summary line read with `NO_COLOR=1` and `grep` instead of `tail -1`, `deno check` without the frozen lock for `index.ts`, the analyzer scope for the manual's one file, the real counts); the second replay, after those fixes, matched every Expected line below. Its one gap was the four "run it to see it fail" Flutter steps, whose compile-error line the replay script's progress filter hid; those four commands were then tightened to `grep -o "Error: Error when reading '…'"` and each was run by hand against a tree without the new file, printing exactly its Expected line. Both clones and the scratch copies were dropped afterwards.

**Revision 2026-11-09 (owner rulings on R-9/R-10, R-13 and R-32).** Tasks 1, 2, 3, 4, 5 and 7 changed (Task 6's files did not; it was replayed as downstream). The whole plan was replayed a third time from Task 1 in a fresh scratch copy on a fresh clone of `attune_spec3a`; every Expected line matched except two numbers the plan then took from that run (Task 5 Step 2's error line moved to `:979`, and the full-suite counts below). Clone and copy dropped afterwards.



| Check | W4a (after Task 4) | W4b (after Task 7) |
|---|---|---|
| Migration + twin, applied twice | 4 × `exit=0` | 4 × `exit=0` |
| `marked_diff.py` | 9 functions `OK` | 7 functions `OK` |
| SQL suite (wrapped) | 160 PASS / 14 FAIL, no new FAIL | 160 PASS / 14 FAIL, no new FAIL |
| `dating_v2_verification_contracts.sql` | `all held` (A–P with C2) | `all held` (A–T) |
| SQL mutants | 25 / 25 RED | 18 / 18 RED |
| Race script (idle scratch DB) | 28 / 28 PASS | 29 / 29 PASS |
| Deno (CI line, frozen lock) | 157 passed, 0 failed | 161 passed, 0 failed |
| Deno mutants | 25 / 25 killed | 6 / 6 killed |
| Dart mutants | T3 9 / 9, T4 14 / 14 | T6 6 / 6, T7 11 / 11 |
| `flutter analyze --no-pub lib test` | 571, no new issue | 571, no new issue |
| Full `flutter test` | +8027, all passed (baseline +7975) | +8049, all passed |
| Large-text audit at 2.0 | 0 sites | 0 sites |
| W10 / W9 golden shas, latch, Games guard | 0 / 0 / OK / passed | 0 / 0 / OK / passed |

(Before the revision: +8023 / +8045 in the earlier replays; one run saw the `story_outbox_notices_test` "Discard asks first…" timing flake outside Dating, which passed 3/3 alone.)

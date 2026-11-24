# Spec 2 W10 (Pilot readiness and switch-on: launch guards) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Summary (one paragraph).** W10 is **one batch, five tasks** and one migration (with its grants twin and a self-revoke), plus one edge-function change, three console pages, one app line and the launch docs. **Task 1** → `20261124100000_dating_v2_launch_guards.sql` (+ `20261124100010_dating_v2_launch_guards_grants.sql`): the production-mode guards (a `DEV-` reference anywhere in a country's `legal_checklist` is refused; a gated flag's `DEV-` evidence is no evidence; a publish that opens a place is refused while any launch gate for that country is red, a reduction never), `get_dating_launch_readiness(p_country)` (every machine-checkable gate of §8; red until the project reads `production`, R-6) and the console's readiness, metrics (n ≥ 50) and fairness reads, with the new contract `dating_v2_launch_contracts.sql` (L1–L6). **Task 2**: `dating-moderation` gains `readiness`, `metrics`, `fairness` and passes `config:launch_not_ready`. **Task 3**: the console's Launch readiness, Metrics and Fairness pages (the safety owner's). **Task 4**: the old `dating_mutual_match` case leaves `notification_config.dart` (A-7). **Task 5**: the two replaced launch docs, the runbook's drills, the design spec's notes, every W10 mutant again and the W10 gate. W10 builds **after W9's migration is in the tree** (W9 interface table). No flag is created and nothing turns on anywhere; `supabase/sql/dev_enable_spec2_dating_flags.sql` is not changed.

**Replayed.** Every task below was built in a scratch copy of the repo at `cbf7b30b` on a clone of `attune_spec3a`, then replayed from this text on a fresh copy and a fresh clone (Replay record, end of plan). W9 did not exist yet: its one object W10 reads (the flag gate row of `dating_couple_link`) is stubbed by the contract inside its own rolled-back transaction when missing, and nowhere else.

**Goal:** Make Spec 2's Dating safe to switch on in production (§8 W10): nothing that is only good enough for development (a `DEV-` reference, fake or sandbox age assurance, missing people, keys, evidence or resources) can open a country in production; one read tells the owner and the safety owner exactly which gate is red; the console shows the §6.9 counters and the §5.9 fairness reports; Dating stays off in production.

**Architecture:** One SQL function computes every gate (`private.dating_launch_gates(countries, row)`): the readiness reads it for Ghana and the UK, and the publisher reads it for the one row it is about to publish, so the check that refuses an opening and the report that names what is red are the same code. Re-created functions start from their LIVE body (saved to `$D/before_w10/`) with only lines marked `-- Spec 2 W10` changed (`marked_diff.py`). W9 is read only as a string (its flag's gate row), never as a function, so W10 applies with or without W9 and never names a decrypting function (the canary's S-4 scan follows names). The console's pages are a new file and three enum entries after Audit, so every earlier page keeps its place.

**Tech Stack:** Supabase Postgres 17 (RLS, `SECURITY DEFINER`), psql, Python 3 (edit, build and mutation scripts), Deno 2.8.1 (`dating-moderation` and its tests, frozen lock `.github/deno-w9.lock`), Flutter 3.29.1 / Dart 3.7 (the console, a Flutter web build; the app's notification router). No new package.

**Spec:** `docs/superpowers/specs/2026-10-24-dating-mode-design.md` — §8 W10 (Contents, Depends on, Tests, Gate) and the §8 wave table row W10 (`dating_v2_launch_guards`); §4.10 rows tagged W10 (`notification_config.dart`, A-7; `DATING_MODE_REVIEW_AND_GATES.md`, `DATING_MODE_RELEASE_READINESS_CHECKLIST.md`); §1.3 Q19b and R-6 (production mode is the owner's alone; readiness red until it reads `production`); §2.2 (`publish_country_config`'s production checks, `legal_checklist`, 90-day resources); §3.3.5 (provider mode); §5.9 (fairness flags to the safety owner in the console); §6.4 (the console); §6.9 (metrics at n ≥ 50); §7.6 8.1 (the rollback drill); §7.7 (the device matrix, the owner's); R2, A-7. Every earlier wave's "Gate before production switch-on" line (W1–W9) for what is machine-checkable. Carries: `.superpowers/sdd/2026-11-23-spec2-w10/carries.md` (every item mapped below). Format reference: `docs/superpowers/plans/2026-11-22-spec2-w8-device.md`. W8's owner list (`.superpowers/sdd/2026-11-22-spec2-w8-device/w8-owner-list.md`) and the W7 and W8 status memories.

## Global Constraints

- **Where and how.** Work in the main working tree on `main` (`/Users/user/attune`). HEAD is `cbf7b30b` plus whatever W9 commits first. The owner may have uncommitted edits (`docs/superpowers/specs/2026-10-24-dating-mode-design.md` — the W11 status line —, `supabase/.temp/cli-latest`, `backup-before-planning-p2.sql`): never revert, stash, stage, checkout, reformat or read them into anything; Task 5's spec notes anchor elsewhere and keep the owner's line. Every edit to an existing file is an exact replacement made by a script that asserts each anchor occurs once (`$D/anchor.py`). If an anchor moved because the live code changed after this plan was written (W9 lands first), make the same change to the current text and say so in the task report (live code is the truth).
- **W9 first.** Task 1 starts only when W9's migration and twin are in `supabase/migrations/` and applied to `attune_spec3a` (W9 interface table). Re-check every row of that table before Task 1 Step 1.
- **NO commits.** No `git add`, `git commit`, `git stash`, `git checkout`, `git reset`, `git rm` (delete files with `rm`). Where a skill says "commit", instead: **do not commit; record the tree in the report** with `T=$(mktemp -u); GIT_INDEX_FILE=$T git read-tree HEAD && GIT_INDEX_FILE=$T git add -A && GIT_INDEX_FILE=$T git write-tree; rm -f $T` (a private index; the real index is untouched). The controller commits after the batch's final review.
- **Formatting.** Never `dart format` a pre-existing file. `dart format` only the files a task creates (`lib/console/screens/launch_screens.dart`, `test/console/console_launch_test.dart`).
- **SQL target.** Contracts run only on `attune_spec3a`, from the repo root. A file with a top-level `BEGIN;` runs as `psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f F`; one without runs wrapped (`suite.sh` does both). Confirm the target first (`psql -X -d attune_spec3a -Atc 'select current_database()'` prints `attune_spec3a`). **NEVER `attune_test`. NEVER run `scripts/local_pg_setup.sh` or `scripts/local_pg_grants.sql`** — but DO append the twin's `\i` line to `scripts/local_pg_grants.sql` (`grants_line.py`). SQL mutants run inside one transaction the contract's own `ROLLBACK` ends (`mutate.py`, the twin applied after each migration mutant; `W10_DB` names the database). Every negative assertion checks the specific message (`raise_exception` only, never `WHEN OTHERS`).
- **Migrations.** `20261124100000_dating_v2_launch_guards.sql` and `20261124100010_dating_v2_launch_guards_grants.sql`, later than every file in `supabase/migrations/` (W9's are `20261123…`; the newest at `cbf7b30b` is `20261122100010_dating_v2_traveller_grants.sql`). If `ls supabase/migrations | sort | tail -1` shows anything at or after `20261124100000` when Task 1 starts, shift both to the next free hour keeping their order and change every header, `\i` line and command. The migration is one `BEGIN; … COMMIT;`, idempotent (applied twice, `exit=0` both times), with `SET LOCAL lock_timeout = '5s'`, and **ends by revoking everything it creates from PUBLIC, anon, authenticated and service_role** (the W6 final pattern: a push that stops between the migration and its twin fails closed); the twin grants. The five re-created functions keep their grants (`CREATE OR REPLACE`). New functions: `SECURITY DEFINER SET search_path = ''` (the two reference helpers are `IMMUTABLE` SQL with no definer), fully-qualified names; `service_role` only for `get_dating_launch_readiness`, `moderation_launch_readiness`, `moderation_metrics`, `moderation_fairness`; the helpers nobody's. Answers are fixed `{ok, reason}` codes; NULL never counts as green.
- **Production stays off (R-6).** No migration, script or edge function sets `attune_environment` (the CI job "Nothing sets attune_environment" stays green: the migration only calls `private.attune_environment()`; the contract's `set_config` lines are under `supabase/tests/`, which CI does not scan). No flag is created or turned on; no country is opened. `supabase/sql/dev_enable_spec2_dating_flags.sql` is **not** changed (W10 adds no flag; W9 adds `dating_couple_link` there). The readiness is red in development by construction.
- **S-4.** No W10 function names a decrypting function or `dating_export_for_job`, even in a comment inside a body: `dating_rls_canary.sql`'s scan follows names, and a service-role readiness that named one would read as a decrypt path.
- **Console.** The console imports only `lib/console`, Flutter and the Supabase client (`test/console/console_test.dart` pins it). The three pages come after Audit (every earlier rail position unchanged). A state is said in words ("Green"/"Red"), never colour alone. Busy and offline are calm lines with Try again; a refusal is its `consoleReason` line.
- **Off limits.** Games (`test/architecture/games_untouched_test.dart` stays green), Opinions, `ATTUNE_SOUL.md`, `ATTUNE_THESIS.md`, `lib/home/home_screen.dart` and its latch (`shasum -c .superpowers/sdd/2026-11-07-spec2-w3/latch.sha`), `quick_exit_service.dart`, `auth_provider.dart`, `lib/main.dart`, `lib/app/**`, every applied migration (W9's included), every edge function but `dating-moderation`, `supabase/sql/dev_enable_spec2_dating_flags.sql`, `backup-before-planning-p2.sql`, `supabase/.temp`. In `notification_config.dart` only the `dating_mutual_match` line and its comment change (R2: "no other line changes"). Voice calls (W11) are out: `dating_voice_calls` is neither created nor read. **No deploys** (`supabase db push`, function deploys, console hosting are the owner's; Owner checklist). No `.env*`, credentials or keychain. Opus for every implementer and reviewer.
- **Fixture ids.** The launch contract's people are `8aa00000-0000-0000-0000-` + the 12-digit code (`pg_temp.id('nn')`) with phones `+1555982nn`, `01–04` (swept: no other file uses `8aa00000-` or `1555982`).
- **Gates (Task 5; `$D/gate.sh`).** (1) The wrapped SQL suite on `attune_spec3a`: no new FAIL against `$D/sql-baseline.txt` recorded in Task 1 Step 1 after W9 (at `cbf7b30b`: **163 PASS / 14 FAIL**; W9 adds its own files; W10 adds one: `dating_v2_launch_contracts.sql`); `quiet_hours_contracts.sql` reads the real clock (run by day, 08:00–22:00 UTC). (2) `dating_v2_launch_contracts.sql` and `dating_rls_canary.sql` print `all held`. (3) The Deno CI line (`.github/workflows/tests.yml` job `deno-w9`, frozen lock) passes in full (**279 at `cbf7b30b`, +2 from Task 2**, plus W9's) and its `deno check` line is clean. (4) `flutter analyze --no-pub lib test`: **571 issues, 0 new** (plus W9's, if any). (5) `shasum -c` of the W10 and W9 sha lists: every line `OK`; the latch `OK`; the Games guard passes. (6) `flutter test test/console`: all pass (**128 at `cbf7b30b`, +9**); the console's web build (the CI line) exits 0. (7) `scripts/concurrency/dating_kill_switch_races.sh` on an **idle** scratch database built from `pg_dump -s attune_spec3a` plus the config tables' data, dropped after: **58** PASS (plus W9's), 0 FAIL. (8) Full `flutter test`: no failure beyond the known three (`healing_journal_large_text` goldens; at `cbf7b30b` **+9621 −3**; W10: **+7**, plus W9's) and the known flakes (`chat_controller_test:259`, `chat_screen_list_anchor` D<0, `reflection_journal` at a date boundary, `planning_recent`, `story_outbox_notices_test` "Discard asks first…", `chat_upload_progress_cancel_test`, `story_review_test` "final review #1"; re-run a failing file alone before calling it a flake). (9) Each task's named mutants all RED (`CONTRACT VIOLATED`, or `KILLED`), the RED line quoted in the report; a `COMPILE` or an `anchor missing` is a broken mutant to fix, never a kill. (10) The feature flags: the same rows and the same number on as after W9 (W10 adds none).

## Review Focus

Five things a real person will meet that this wave must survive. Each is pinned to tests that fail if it regresses.

1. **The owner flips the development project itself to production**, with Dating already open there from testing: introductions and chat configs active with `DEV-` references, flags on with no or `DEV-` evidence, passes made by the fake providers. Expect: nothing of it counts; the readiness names each one red; a gated flag with `DEV-` evidence can't be turned on again; the owner's checklist has the clean-up steps. Tests: Task 1 L2 "DEV- introductions ref", "DEV- chat ref", "flag violation", "fake pass", L4 (mutants `intro_dev_ok`, `chat_dev_ok`, `violations_dev_ok`, `fake_age_ignored`, `flag_guard_dev_ok`).
2. **The safety owner opens Ghana from the console while one gate is still red** (age assurance still `sandbox`, the moderator's row inactive, the UK's resources 91 days old). Expect: refused, no version published, the console says to read Launch readiness, which names the red gate. Tests: Task 1 L3 "Ghana opened while a gate was red", L2 "stale resource"; Task 3 "a publish refused for the launch gates…" (mutants `opening_unguarded`, `region_opening_unguarded`, `opening_reads_current_row`, `launch_code_busy`, `launch_reason_generic`).
3. **An emergency reduction in production while a gate is red** (closing a country, narrowing its regions, the same-gender kill switch, at 03:00 with the resources lapsed). Expect: never refused (W1d's rule). Tests: Task 1 L3 "narrowing was refused", "closing was refused" (mutant `reduction_refused`).
4. **A `DEV-` reference typed another way** (`dev-x`, ` DEV-x`, a tab first, inside the same-gender reconsideration). Expect: refused in production, never evidence, recorded freely in development. Tests: Task 1 L3 "padded dev- reference", L2 "nested DEV- reference", L4 "padded dev- evidence" and "development refused DEV- evidence" (mutants `dev_rule_case_and_padding`, `checklist_dev_nested_ok`, `record_dev_refused_everywhere`).
5. **A moderator (not the safety owner), or someone who is no moderator, opens the launch pages; a small counter.** Expect: a moderator's console asks nothing and says the pages are the safety owner's; the server answers `safety_owner_only` / `not_moderator` (counted); a counter under 50 is never named. Tests: Task 1 L5; Task 3 "a moderator's console asks nothing…" (mutants `readiness_for_moderators`, `metrics_for_moderators`, `fairness_for_moderators`, `metrics_at_49`, `moderator_asks`).

## Pre-flight (read before Task 1)

`D=.superpowers/sdd/2026-11-23-spec2-w10` throughout. The tool folder holds `carries.md` and W10's tools, copied from W8's folder `.superpowers/sdd/2026-11-22-spec2-w8/`: `suite.sh`, `anchor.py`, `splice.py`, `mirror.py`, `marked_diff.py`, `grants_line.py` (unchanged), and `mutate.py` (`W10_DB`), `dmut.py`, `denomut.py` (temporary folder prefixes `w10…`). Task 1 Step 0 copies them.

### Shared files and interfaces between tasks

| File or interface | Tasks | Rule |
|---|---|---|
| `supabase/migrations/20261124100000_dating_v2_launch_guards.sql` | 1 (built by `build_mig.py` from `mig_head.sql` and `before_w10/`) | never hand-edited; rebuild |
| `lib/console/console_app.dart` | 3 (import, five anchored edits) | shared console shell (W7's); flag regression risk: rail order, `consoleReason` |
| `supabase/functions/dating-moderation/handler.ts`, `handler.test.ts` | 2 | `ACTIONS` and `REASONS` only grow |
| `supabase/tests/dating_rls_canary.sql`, `dating_v2_setup_contracts.sql`, `country_safety_config_contracts.sql` | 1 | rows added; one pin extended; one rolled-back stub; never a loosened check |
| `lib/core/notifications/config/notification_config.dart` | 4 | shared app router: only the one case and its comment |
| `docs/superpowers/specs/2026-10-24-dating-mode-design.md` | 5 | five `amended S2 W10` notes; the owner's uncommitted W11 line kept |

### W9 interface (re-check every row before Task 1 Step 1)

W9 is planned in parallel (`docs/superpowers/plans/2026-11-23-spec2-w9-couple-link.md`). W10 was built before that plan existed; once it appeared, every row was checked against its text (2026-11-23): its migration is `20261123100000_dating_v2_couple_link.sql` (+ `…100010_…_grants.sql`); it inserts `dating_couple_link` (off) with its production gate row; it re-creates none of W10's five functions nor `get_dating_operational_health`; it extends the setup contract's photo pin elsewhere in the string (`public.dating_export_for_job(uuid):service_role`) and a different comment line, so W10's two anchors there still occur once. Re-check every row at build time anyway (live code is the truth); if W9 built a different name, change W10 to match and say so.

| W9 name (spec §8 W9, §4.4, §4.10) | Used by W10 | How to re-check | If it differs |
|---|---|---|---|
| Migration timestamps `20261123…` (+ twin) | W10's `20261124100000` sorts after | `ls supabase/migrations \| sort \| tail -2` | shift W10 to the next free hour after W9's |
| Flag `dating_couple_link` with a row in `private.flag_production_gates` | the readiness's `flag_evidence` list (a string) | `psql -X -d attune_spec3a -Atc "select flag_key from private.flag_production_gates where flag_key = 'dating_couple_link'"` prints it | rename in `mig_head.sql`'s `v_flags`, the contract's stub and the checklist doc |
| No function named exactly `dating_couple_link` | the canary's S-4 scan reads names in bodies | `psql -X -d attune_spec3a -Atc "select count(*) from pg_proc where proname = 'dating_couple_link'"` prints `0` | write the flag name as `'dating_couple' \|\| '_link'` with a comment |
| `dating_export_for_job` (S-4) | **not named** by W10 (R-88) | — | — |
| W9's twin is the last `\i` in `scripts/local_pg_grants.sql` | `grants_line.py` reads the last line | Task 1 Step 6 reads it | — |
| W9 re-creates `get_dating_operational_health` (if it does) | readiness reads its keys `exclusion_key_fingerprint_ok`, `field_key_fingerprint_ok`, `kill_switch_pending`, `log_settings_safe` | `psql … -Atc "select public.get_dating_operational_health() ?& array['exclusion_key_fingerprint_ok','field_key_fingerprint_ok','kill_switch_pending','log_settings_safe']"` prints `t` | read the renamed keys |
| W9 re-creates `publish_country_config`, `country_config_checks` or a Spec 1 flag function (it should not) | W10 re-creates all five from LIVE (saved after W9 is applied) | Task 1 Step 1 saves the live bodies; `build_mig.py` asserts each anchor once | make the same edit to W9's text |
| W9's rows in `dating_rls_canary.sql` | Task 1 adds rows above `-- Checks (every batch adds its rows above this line).` | the anchor occurs once | — |
| W9 functions that read Dating photos (`dating_v2_setup_contracts.sql` pin) | Task 1 extends the pin at `private.dating_has_data(uuid):; private.dating_next_step(uuid):;` | anchor occurs once | extend W9's new pin text the same way |
| W9's `supabase/sql/dev_enable_spec2_dating_flags.sql` line for `dating_couple_link` | W10 does not touch the file | — | — |

### Carries → tasks

| # | Carry (`carries.md`) | Where |
|---|---|---|
| 1 | W10 depends on W1–W9; readiness covers W9's flag/gate rows and export by name; W9 interface table | W9 interface table; Task 1 (`flag_evidence` includes `dating_couple_link`). **The export by name is ruled out (R-88):** naming `dating_export_for_job` in a service-role function's body trips the canary's S-4 scan (the export decrypts); W9's flag gate row stands for "W9 applied", and the export's own gate (counsel on its scope) is that row's evidence. |
| 2 | W11 voice out; `dating_voice_calls` not created or checked | Global Constraints; the flag list (R-87) has no voice flag. |
| 3 | Machine-checkable hard gates from W8's owner list (`DEV-` refs, `age_assurance_mode = 'live'`, resources ≤ 90 days, safety owner + moderator active, `dating_chat_v1` with a real `review_ref`); owner-only items to the Owner checklist | Task 1 (gates `age_assurance_live`, `safety_owner`, `moderator`, `chat_config`, `introductions_config`, `resources:*`, `checklist:*`, `flag_evidence`, `no_flag_violations`, `no_test_verifications`); legal, pen test, DPC, sign-offs, the launcher-alias build before 10 Dec: Owner checklist. |
| 4 | W4b trusted-device-before-locks deadlock; per-user rate limit on `dating-device-check` | **Both ruled out of W10 (R-91), owner follow-ups.** The deadlock resolves in about 1 s as `busy` with a retry and loses nothing; fixing it means re-ordering locks in every W4b RPC (broad, regression-prone, not launch-guard work). The rate limit: writes are already capped at one per 15 minutes; `check_dating_rate_limit` reads `auth.uid()` (null for the service role), so it needs a per-user variant, and a counting row would add a write to every call (more load than it saves). The pen test decides; Owner checklist 12. |
| 5 | Remove `dating_mutual_match` from `notification_config.dart` (A-7) | Task 4 (R-90). |
| 6 | Build after W9's migration; W10's timestamp later | Global Constraints; W9 interface table. |

### Rulings (the spec wins over this plan; each records its cost if wrong)

- **Ruling R-85:** "production-mode guards (checklist, `DEV-` refs, provider mode)" as built: (1) checklist — `country_config_checks` also reports `dev_reference` for a `DEV-` reference at any level of `legal_checklist` (W5a's rule: any case, after any padding), so a production publish refuses it through the existing `config:production_checks_failed` path, and a reduction is still published (W1d); (2) `DEV-` refs — Spec 1's flag gate treats a `DEV-` evidence reference as none in production (`guard_flag_production_gate`), `production_flag_violations()` lists a flag that is on with one (in any environment: it is a report), and `record_flag_gate_evidence` refuses one in production (`flag:dev_reference`); (3) provider mode — W4a already makes verification unavailable outside development for `fake` and `sandbox`, and the readiness's `age_assurance_live` gate plus the opening gate (R-86) make `live` a precondition of opening. The configs' own `DEV-` triggers (W5a, W6b) already refuse activation in production; a config left active with `DEV-` references from development is caught by the readiness (the flip fires no trigger). Cost if wrong: one function each.
- **Ruling R-86 ⚑ (owner decision):** in production, `publish_country_config` refuses a publish that opens a place (the country, or a region newly open) unless every launch gate for that country is green for the row being published (`config:launch_not_ready`, with the red gate names; the edge function passes only the code). Closing, narrowing, a tier tightening and the same-gender switch-off never reach it. Cost if wrong: one `IF` block.
- **Ruling R-87:** the readiness's gates are every machine-checkable gate line of W1–W10 (Global: `environment`, `age_assurance_live`, `safety_owner`, `moderator`, `keys`, `introductions_config`, `chat_config`, `flag_evidence`, `no_flag_violations`, `no_test_verifications`, `kill_switch_clear`, `log_settings_safe`, `sla_alerts`; per country: `checklist:CC`, `resources:CC`); Ghana and the UK by default, one country on request. The launch flags are Dating's eight (W11's excluded) plus Spec 1's `support_resources_v2` (Get help) and `csam_hash_matching` (inline CSAM, the W7 gate). `no_test_verifications` counts unrevoked passes whose vendor is `fake`; a sandbox pass can't be told apart from a live one (same vendor names), so a launch on the development project needs the owner's clean-up (Owner checklist 3). `resources:CC` reads both the row's `resources_verified_at` and Spec 1's `support_resources` (every active entry for the country within 90 days, at least one). Cost if wrong: one gate each.
- **Ruling R-88:** W9 is read only through the gate row of its flag `dating_couple_link` (a missing row reads red, never an error); the export is never named (carry 1). Cost if wrong: one gate.
- **Ruling R-89:** the console's Launch readiness, Metrics and Fairness are the safety owner's (a moderator gets `safety_owner_only`; the console asks nothing). Metrics sums every `dating.` key over 7, 28 or 90 UTC days and names only those at 50 or more (§6.9), the rest counted (`suppressed`); the operational counters stay in `get_dating_operational_health`. Fairness reads 1–12 weeks (default 4), flagged cohorts first; rows exist only for n ≥ 50 (W5c). Reads are not audited (as the other lists). Cost if wrong: one `IF` each.
- **Ruling R-90:** with the `dating_mutual_match` case gone, a stale push of that type falls to the router's `default` and opens Home (no tab), as any type the app doesn't know; no server writer sends it (the W8a push audit, contract A). Cost if wrong: one line.
- **Ruling R-91:** carry 4's two follow-ups stay the owner's (carries table). Cost if wrong: one W11-or-later task each.
- **Ruling R-92:** no new race case (the opening gate reads under `publish_country_config`'s existing advisory lock and row lock; two publishes serialise as before) and no dev-script change (W10 creates no flag). Cost if wrong: one race case.
- **Ruling R-93:** `country_safety_config_contracts.sql` pins the publisher's own rules, so it reads the launch gates green inside its own transaction (a rolled-back `CREATE OR REPLACE` of `private.dating_launch_gates`, only when it exists); `dating_v2_launch_contracts.sql` pins the gates. `dating_v2_setup_contracts.sql`'s photo-reader pin gains `private.dating_launch_gates` (its body names the flag `dating_profile_photos`, the table's own name; it reads no photo). Cost if wrong: a test edit.

## Interfaces this plan consumes (read from the current code)

- **Spec 1:** `private.attune_environment()`, `private.flag_production_gates`, `private.guard_flag_production_gate()`, `public.record_flag_gate_evidence(text, text)`, `public.production_flag_violations()`, `public.app_setting(text)`, `public.metric_counters`, `private.bump_metric_internal`, `public.support_resources` (`country_code`, `active`, `verified_at date`).
- **S2 W1–W8 (live):** `public.country_safety_config`, `public.dating_country_config(text)`, `private.country_config_checks(public.country_safety_config)`, `public.publish_country_config(text, jsonb)` (W1d's `v_closing`, `v_open_old`, `v_open_new`), `private.dating_iso_country(text)`, `private.dating_verification_mode()`, `public.dating_age_verifications` (`age_vendor`, `identity_vendor`, `revoked_at`), `public.dating_algorithm_configs` (four review refs), `public.dating_safety_configs` (`review_ref`), `public.dating_moderators`, `private.dating_moderator(uuid)`, `public.dating_fairness_reports`, `private.dating_kill_switch_pending`, `public.get_dating_operational_health()` (keys above), `private.seed_dating_exclusion_key_fingerprint()`, `private.seed_dating_field_key_fingerprint()`; the edge function's `ACTIONS`, `REASONS`, `limit`, `handleModeration`; the console's `ConsoleApi`, `ConsoleAnswer`, `ConsoleMe`, `ConsoleFrame`, `ConsoleLoading`, `ConsoleRetry`, `ConsoleStatus`, `ConsoleLine`, `consoleReason`, `ConsolePage`, `pumpHome`, `consoleOwner`, `consoleMe`, `tapConfirm`, `FakeConsoleApi`.
- **W9:** the W9 interface table.

## Interfaces this plan produces

- **SQL:** `private.is_dev_reference(text) → boolean`, `private.is_real_reference(text) → boolean` (IMMUTABLE); `private.dating_launch_gates(p_countries text[], p_row public.country_safety_config DEFAULT NULL) → jsonb` (array of `{gate, ok[, detail]}`); `public.get_dating_launch_readiness(p_country text DEFAULT NULL) → {ok: true, ready, environment, countries, open, gates}` | `{ok: false, reason: 'invalid'}` (service role); `public.moderation_launch_readiness(p_actor uuid, p_country text DEFAULT NULL)`, `public.moderation_metrics(p_actor uuid, p_days integer) → {ok, days, from, to, min_count: 50, metrics: [{key, count}], suppressed}`, `public.moderation_fairness(p_actor uuid, p_weeks integer) → {ok, weeks, flagged, reports: [{week, country, cohort, active, introductions_per_active, mutual_rate, flagged}]}` (service role; `not_moderator` counted, `safety_owner_only`, `invalid`); `country_config_checks` check `dev_reference`; `publish_country_config` reason `config:launch_not_ready` (+ `gates`); `record_flag_gate_evidence` error `flag:dev_reference`.
- **Edge:** `dating-moderation` actions `readiness` (`{country?}`: `^[A-Z]{2}$` or none), `metrics` (`{days}`: 7, 28 or 90), `fairness` (`{weeks?}`: 1–12, else 4); `METRIC_DAYS`; reason `config:launch_not_ready`.
- **Console:** `lib/console/screens/launch_screens.dart` (`ReadinessScreen`, `MetricsScreen`, `FairnessScreen`, `consoleGateLabel`, `consoleGateDetail`, `consoleReadinessLine`, `consoleDay`, `kConsoleLaunchOwnerOnly`); `ConsolePage.readiness`, `.metrics`, `.fairness`.

## File map

Task 1 creates `$D/{tools copied, sql-baseline.txt, before_w10/, mig_head.sql, build_mig.py, edit_tests_T1.py, mut_T1.py}`, `supabase/migrations/20261124100000_dating_v2_launch_guards.sql` (built), `…100010_…_grants.sql`, `supabase/tests/dating_v2_launch_contracts.sql`; modifies `dating_rls_canary.sql`, `dating_v2_setup_contracts.sql`, `country_safety_config_contracts.sql`, `scripts/local_pg_grants.sql`. Task 2 creates `$D/{edit_edge_T2.py, mut_T2.py}`; modifies `dating-moderation/handler.ts`, `handler.test.ts`. Task 3 creates `lib/console/screens/launch_screens.dart`, `test/console/console_launch_test.dart`, `$D/{edit_console_T3.py, mut_T3_dart.py}`; modifies `lib/console/console_app.dart`. Task 4 creates `$D/{edit_app_T4.py, mut_T4_dart.py}`; modifies `notification_config.dart`, `test/core/notifications/me_update_routing_test.dart`, `test/features/dating/device/dating_lock_entry_test.dart`, the device contract's header comment. Task 5 creates `$D/{edit_runbook_T5.py, edit_docs_T5.py, gate.sh}`; replaces `lib/architecture/DATING_MODE_REVIEW_AND_GATES.md`, `lib/architecture/DATING_MODE_RELEASE_READINESS_CHECKLIST.md`; modifies `DATING_MODERATION_RUNBOOK.md` and the design spec.

**Not edited:** `supabase/sql/dev_enable_spec2_dating_flags.sql`, `lib/main.dart`, `lib/app/**`, `lib/home/home_screen.dart`, `quick_exit_service.dart`, `auth_provider.dart`, `lib/features/games/**`, `lib/features/chat/**`, Opinions, every applied migration, every edge function but `dating-moderation`, `scripts/local_pg_setup.sh`, `ATTUNE_SOUL.md`, `ATTUNE_THESIS.md`, `DATING_MODE_SPEC.md`.

---

## Batch W10 — launch guards, readiness, the console's launch pages

### Task 1: Migration `dating_v2_launch_guards`: the guards, the gates, the readiness, the console's reads, and contract L1–L6 (§8 W10; §2.2, §3.3.5, §5.9, §6.4, §6.9; R-6; R-85–R-89, R-92, R-93)

**Files:**
- Create: `$D/{suite.sh, anchor.py, splice.py, mirror.py, marked_diff.py, grants_line.py, mutate.py, dmut.py, denomut.py}` (copied), `$D/{sql-baseline.txt, before_w10/, mig_head.sql, build_mig.py, edit_tests_T1.py, mut_T1.py}`, `supabase/migrations/20261124100000_dating_v2_launch_guards.sql` (built), `supabase/migrations/20261124100010_dating_v2_launch_guards_grants.sql`, `supabase/tests/dating_v2_launch_contracts.sql`
- Modify: `supabase/tests/dating_rls_canary.sql`, `supabase/tests/dating_v2_setup_contracts.sql`, `supabase/tests/country_safety_config_contracts.sql`, `scripts/local_pg_grants.sql` (one `\i` block)
- Test: `dating_v2_launch_contracts.sql` L1–L6; the canary; the whole suite

**Interfaces:**
- Consumes: the live bodies of `private.guard_flag_production_gate()`, `public.record_flag_gate_evidence(text,text)`, `public.production_flag_violations()`, `private.country_config_checks(public.country_safety_config)`, `public.publish_country_config(text,jsonb)` (saved in Step 1, after W9 is applied); the rest as listed above.
- Produces: the SQL interfaces above, for Tasks 2 and 3.

- [ ] **Step 0: The tool folder**

```bash
D=.superpowers/sdd/2026-11-23-spec2-w10; W=.superpowers/sdd/2026-11-22-spec2-w8
cp $W/{suite.sh,anchor.py,splice.py,mirror.py,marked_diff.py,grants_line.py} $D/
sed 's/W8_DB/W10_DB/g; s/Spec 2 W8 mutation runner/Spec 2 W10 mutation runner (W8'"'"'s, W10_DB)/' $W/mutate.py > $D/mutate.py
sed "s/w8dmut-/w10dmut-/; s/Spec 2 W8 Dart mutation runner/Spec 2 W10 Dart mutation runner (W8's)/" $W/dmut.py > $D/dmut.py
sed "s/w8denomut-/w10denomut-/; s/Spec 2 W8 Deno mutation runner/Spec 2 W10 Deno mutation runner (W8's)/" $W/denomut.py > $D/denomut.py
chmod +x $D/suite.sh
grep -c W10_DB $D/mutate.py
```

Expected: `2`.

- [ ] **Step 1: The baseline and the live bodies (after W9 is applied, before anything of W10)**

```bash
D=.superpowers/sdd/2026-11-23-spec2-w10
psql -X -d attune_spec3a -Atc 'select current_database()'
ls supabase/migrations | sort | tail -1
bash $D/suite.sh attune_spec3a > $D/sql-baseline.txt
echo "$(grep -c '^PASS' $D/sql-baseline.txt) PASS $(grep -c '^FAIL' $D/sql-baseline.txt) FAIL"
mkdir -p $D/before_w10
for sig in "private.guard_flag_production_gate()" "public.record_flag_gate_evidence(text,text)" "public.production_flag_violations()" "private.country_config_checks(public.country_safety_config)" "public.publish_country_config(text,jsonb)"; do
  psql -X -d attune_spec3a -Atc "select pg_get_functiondef('$sig'::regprocedure)" > "$D/before_w10/$sig.sql"
done
ls $D/before_w10 | wc -l | tr -d ' '
```

Expected (replay, at `cbf7b30b` with no W9): `attune_spec3a`; `20261122100010_dating_v2_traveller_grants.sql` (after W9: W9's twin, `20261123…`); `163 PASS 14 FAIL` (by day; after W9 more PASS); `5`.

- [ ] **Step 2: Write the contract**

Create `supabase/tests/dating_v2_launch_contracts.sql` with exactly:

````sql
-- supabase/tests/dating_v2_launch_contracts.sql
-- Spec 2 W10 (§8 W10 tests; §2.2, §3.3.5, §5.9, §6.4, §6.9; R-6, Q19b):
-- the launch guards and get_dating_launch_readiness().
--   L1 (R-6): with every other gate green, the readiness is red while the
--      project reads development, and the environment is its only red gate.
--   L2: in production mode it is green, and each gate turns it red alone.
--   L3: in production, opening a place needs the launch gates green;
--      a reduction is never refused; a DEV- reference in the checklist is
--      refused (dev_reference), and only reported in development.
--   L4: a gated flag's DEV- evidence is no evidence in production.
--   L5: the console's readiness, metrics (n >= 50) and fairness, the
--      safety owner's alone; L6: grants.
-- W9 is read by the readiness only through the gate row of its flag
-- dating_couple_link. Until W9 lands this file stubs that row inside its
-- own transaction (rolled back); once W9 is applied, W9's row is used.
-- Fixture ids 8aa00000-0000-0000-0000-0000000000nn, phones +1555982nn.
-- One BEGIN ... ROLLBACK. Run only on attune_spec3a:
--   psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/dating_v2_launch_contracts.sql
BEGIN;

CREATE FUNCTION pg_temp.id(p_n text) RETURNS uuid LANGUAGE sql IMMUTABLE AS $$
  SELECT ('8aa00000-0000-0000-0000-' || lpad(p_n, 12, '0'))::uuid;
$$;
-- The project's environment for the rest of the transaction ('' reads development).
CREATE FUNCTION pg_temp.env(p_env text) RETURNS void LANGUAGE sql AS $$
  SELECT set_config('app.settings.attune_environment', p_env, true);
$$;
CREATE FUNCTION pg_temp.err(p_sql text) RETURNS text LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE p_sql;
  RETURN NULL;
EXCEPTION WHEN raise_exception THEN
  RETURN SQLERRM;
END;
$$;
-- The red gates of a readiness answer, sorted.
CREATE FUNCTION pg_temp.red(v jsonb) RETURNS text[] LANGUAGE sql IMMUTABLE AS $$
  SELECT coalesce(array_agg(g ->> 'gate' ORDER BY g ->> 'gate'), ARRAY[]::text[])
    FROM jsonb_array_elements(v -> 'gates') AS g WHERE (g ->> 'ok')::boolean IS NOT TRUE;
$$;
CREATE FUNCTION pg_temp.detail(v jsonb, p_gate text) RETURNS jsonb LANGUAGE sql IMMUTABLE AS $$
  SELECT g -> 'detail' FROM jsonb_array_elements(v -> 'gates') AS g WHERE g ->> 'gate' = p_gate;
$$;
-- The server's log settings can't be set from a test (superuser only):
-- where they are unsafe, that gate stays red and every check allows it.
CREATE FUNCTION pg_temp.logs_ok() RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT (public.get_dating_operational_health() ->> 'log_settings_safe')::boolean;
$$;
CREATE FUNCTION pg_temp.expect(p_label text, p_got text[], p_want text[]) RETURNS void LANGUAGE plpgsql AS $$
DECLARE
  v_want text[] := p_want;
BEGIN
  IF NOT pg_temp.logs_ok() THEN
    v_want := ARRAY(SELECT DISTINCT x FROM unnest(p_want || ARRAY['log_settings_safe']) AS x ORDER BY x);
  END IF;
  IF p_got IS DISTINCT FROM v_want THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: %: red gates % (expected %)', p_label, p_got, v_want;
  END IF;
END;
$$;
CREATE FUNCTION pg_temp.ready_red(p_country text DEFAULT NULL) RETURNS text[] LANGUAGE sql STABLE AS $$
  SELECT pg_temp.red(public.get_dating_launch_readiness(p_country));
$$;
CREATE FUNCTION pg_temp.person(p_n text) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE
  v_u constant uuid := pg_temp.id(p_n);
BEGIN
  INSERT INTO auth.users (id, phone, phone_confirmed_at, created_at)
  VALUES (v_u, '1555982' || p_n, now(), now() - interval '40 days');
  INSERT INTO public.users (id, phone, display_name, path, created_at, eula_accepted_at, eula_version)
  VALUES (v_u, '+1555982' || p_n, 'Launch ' || p_n, 'dating', now() - interval '40 days', now(), '2');
  RETURN v_u;
END;
$$;
-- The country's current checklist with [p_patch] over it (a publish
-- replaces the whole object, and the checklist only grows).
CREATE FUNCTION pg_temp.checklist(p_country text, p_patch jsonb) RETURNS jsonb LANGUAGE sql STABLE AS $$
  SELECT jsonb_build_object('legal_checklist', (public.dating_country_config(p_country)).legal_checklist || p_patch);
$$;
CREATE FUNCTION pg_temp.resource(p_country text, p_verified date) RETURNS void LANGUAGE sql AS $$
  INSERT INTO public.support_resources (id, country_code, category, name, phone, verified_at, verified_by, catalogue_version)
  VALUES (gen_random_uuid(), p_country, 'dv', 'Launch fixture line ' || p_country, '+1 555 0100', p_verified,
          'w10-fixture', 'w10');
$$;

-- =====================================================================
-- The green world (every gate but the environment), in development.
-- =====================================================================
DO $$
BEGIN
  -- Vault is read first; a value there would shadow the settings below.
  BEGIN
    DELETE FROM vault.secrets WHERE name IN ('attune_environment', 'age_assurance_mode', 'dating_push_key',
      'moderation_alert_webhook', 'dating_exclusion_key', 'dating_field_key', 'supabase_url');
  EXCEPTION WHEN insufficient_privilege OR undefined_table THEN NULL;
  END;
  PERFORM pg_temp.env('');
  PERFORM set_config('app.settings.dating_exclusion_key', 'spec2-w10-launch-key', true);
  -- The field key from Vault: production mode reads it nowhere else (W1d).
  PERFORM vault.create_secret('spec2-w10-field-key-0123456789abcdef-0123', 'dating_field_key');
  PERFORM set_config('app.settings.dating_push_key', 'spec2-w10-push-key', true);
  PERFORM set_config('app.settings.age_assurance_mode', 'live', true);
  PERFORM set_config('app.settings.moderation_alert_webhook', 'https://alerts.example.invalid/w10', true);
END $$;
SELECT private.seed_dating_exclusion_key_fingerprint() AS seeded \gset
SELECT private.seed_dating_field_key_fingerprint() AS seeded_field \gset

SELECT pg_temp.person('01') AS owner_id, pg_temp.person('02') AS mod_id, pg_temp.person('03') AS stranger_id,
       pg_temp.person('04') AS tester_id \gset
INSERT INTO public.dating_moderators (user_id, role, sensitive_routing_allowed, languages)
VALUES (pg_temp.id('01'), 'safety_owner', true, '{en}'), (pg_temp.id('02'), 'moderator', false, '{en,tw}');

UPDATE public.dating_algorithm_configs SET state = 'retired', retired_at = now()
 WHERE state = 'active' AND version <> 'introductions_v2';
UPDATE public.dating_algorithm_configs
   SET state = 'active', activated_at = coalesce(activated_at, now()), product_review_ref = 'W5-PRODUCT-2026-12',
       clinical_review_ref = 'W5-CLINICAL-2026-12', fairness_review_ref = 'W5-FAIRNESS-2026-12',
       safety_review_ref = 'W5-SAFETY-2026-12'
 WHERE version = 'introductions_v2';
UPDATE public.dating_safety_configs SET state = 'active', review_ref = 'W6-SAFETY-2026-12', activated_at = coalesce(activated_at, now())
 WHERE version = 'dating_chat_v1';

-- W9's flag (a stub only where W9 isn't applied yet).
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM private.flag_production_gates WHERE flag_key = 'dating_couple_link') THEN
    INSERT INTO public.feature_flags (key, enabled) VALUES ('dating_couple_link', false) ON CONFLICT (key) DO NOTHING;
    INSERT INTO private.flag_production_gates (flag_key, gate) VALUES ('dating_couple_link', 'W10 contract stub (W9 not applied)');
    RAISE NOTICE 'dating_v2_launch_contracts: W9''s flag gate row stubbed for this transaction';
  END IF;
END $$;
UPDATE private.flag_production_gates SET review_ref = 'W10-REVIEW-' || flag_key WHERE review_ref IS NULL OR private.is_dev_reference(review_ref);

SELECT public.publish_country_config('GH', '{"resources_verified_at": "now", "legal_checklist": {
  "ghana_legal_opinion": "GH-COUNSEL-2026-12", "dpc_registration": "DPC-REG-0001", "dpia": "DPIA-v3-SIGNED",
  "pen_test": "PENTEST-2026-12-CLEAN", "safety_owner_and_moderator": "MOD-ROTA-2026-12",
  "reviewer_signoffs": "SIGNOFFS-2026-12"}}') AS gh_fill \gset
SELECT public.publish_country_config('GB', '{"resources_verified_at": "now", "legal_checklist": {
  "osa_illegal_harms_assessment": "OSA-IH-2026", "osa_childrens_access_assessment": "OSA-CA-2026",
  "highly_effective_age_assurance": "HEAA-2026", "dpia": "DPIA-v3-SIGNED", "pen_test": "PENTEST-2026-12-CLEAN",
  "safety_owner_and_moderator": "MOD-ROTA-2026-12", "reviewer_signoffs": "SIGNOFFS-2026-12"}}') AS gb_fill \gset
DO $$ BEGIN PERFORM pg_temp.resource('GH', current_date - 10); PERFORM pg_temp.resource('GB', current_date); END $$;

-- =====================================================================
-- L1 (R-6): development reads red, the environment its only red gate.
-- =====================================================================
DO $$
DECLARE
  v jsonb := public.get_dating_launch_readiness();
BEGIN
  IF (v ->> 'ok')::boolean IS NOT TRUE OR (v ->> 'ready')::boolean IS NOT FALSE
     OR v ->> 'environment' IS DISTINCT FROM 'development'
     OR v -> 'countries' IS DISTINCT FROM '["GH", "GB"]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: L1 development did not read red: %', v;
  END IF;
  PERFORM pg_temp.expect('L1 development', pg_temp.red(v), ARRAY['environment']);
  -- An unrecognised environment value is production (Spec 1's rule), so it
  -- is never a way round the gate.
  PERFORM pg_temp.env('staging');
  IF public.get_dating_launch_readiness() ->> 'environment' IS DISTINCT FROM 'production' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: L1 a typo did not read production';
  END IF;
  PERFORM pg_temp.env('');
END $$;

-- =====================================================================
-- L2: production reads green; each gate alone turns it red.
-- =====================================================================
DO $$
DECLARE
  v jsonb;
BEGIN
  PERFORM pg_temp.env('production');
  v := public.get_dating_launch_readiness();
  PERFORM pg_temp.expect('L2 all green', pg_temp.red(v), ARRAY[]::text[]);
  IF pg_temp.logs_ok() AND (v ->> 'ready')::boolean IS NOT TRUE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: L2 every gate green but not ready: %', v;
  END IF;
  IF (v ->> 'environment') IS DISTINCT FROM 'production' OR v -> 'open' IS DISTINCT FROM '[]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: L2 environment or open countries wrong: %', v;
  END IF;

  -- Provider mode: only live counts.
  PERFORM set_config('app.settings.age_assurance_mode', 'sandbox', true);
  PERFORM pg_temp.expect('L2 sandbox', pg_temp.ready_red(), ARRAY['age_assurance_live']);
  PERFORM set_config('app.settings.age_assurance_mode', 'fake', true);
  PERFORM pg_temp.expect('L2 fake', pg_temp.ready_red(), ARRAY['age_assurance_live']);
  PERFORM set_config('app.settings.age_assurance_mode', 'live', true);

  -- The people.
  UPDATE public.dating_moderators SET active = false WHERE role = 'safety_owner';
  PERFORM pg_temp.expect('L2 no safety owner', pg_temp.ready_red(), ARRAY['safety_owner']);
  UPDATE public.dating_moderators SET active = true WHERE role = 'safety_owner';
  UPDATE public.dating_moderators SET active = false WHERE role = 'moderator';
  PERFORM pg_temp.expect('L2 no moderator', pg_temp.ready_red(), ARRAY['moderator']);
  UPDATE public.dating_moderators SET active = true WHERE role = 'moderator';

  -- The keys.
  PERFORM set_config('app.settings.dating_push_key', '', true);
  PERFORM pg_temp.expect('L2 no push key', pg_temp.ready_red(), ARRAY['keys']);
  PERFORM set_config('app.settings.dating_push_key', 'spec2-w10-push-key', true);
  PERFORM vault.update_secret((SELECT s.id FROM vault.secrets AS s WHERE s.name = 'dating_field_key'),
                              'spec2-w10-another-field-key-0123456789ab');
  PERFORM pg_temp.expect('L2 rotated field key', pg_temp.ready_red(), ARRAY['keys']);
  PERFORM vault.update_secret((SELECT s.id FROM vault.secrets AS s WHERE s.name = 'dating_field_key'),
                              'spec2-w10-field-key-0123456789abcdef-0123');

  -- DEV- references left active from development (the flip doesn't fire
  -- the configs' triggers): the introductions and chat configs.
  PERFORM pg_temp.env('');
  UPDATE public.dating_algorithm_configs SET fairness_review_ref = ' dev-fairness' WHERE state = 'active';
  PERFORM pg_temp.env('production');
  PERFORM pg_temp.expect('L2 DEV- introductions ref', pg_temp.ready_red(), ARRAY['introductions_config']);
  PERFORM pg_temp.env('');
  UPDATE public.dating_algorithm_configs SET fairness_review_ref = 'W5-FAIRNESS-2026-12' WHERE state = 'active';
  UPDATE public.dating_algorithm_configs SET state = 'retired', retired_at = now() WHERE state = 'active';
  PERFORM pg_temp.env('production');
  PERFORM pg_temp.expect('L2 no introductions config', pg_temp.ready_red(), ARRAY['introductions_config']);
  PERFORM pg_temp.env('');
  UPDATE public.dating_algorithm_configs SET state = 'active', retired_at = NULL WHERE version = 'introductions_v2';
  UPDATE public.dating_safety_configs SET review_ref = 'DEV-safety' WHERE state = 'active';
  PERFORM pg_temp.env('production');
  PERFORM pg_temp.expect('L2 DEV- chat ref', pg_temp.ready_red(), ARRAY['chat_config']);
  PERFORM pg_temp.env('');
  UPDATE public.dating_safety_configs SET review_ref = 'W6-SAFETY-2026-12' WHERE state = 'active';
  PERFORM pg_temp.env('production');

  -- Flag evidence: a DEV- or missing reference, and a launch flag with no
  -- gate row at all.
  UPDATE private.flag_production_gates SET review_ref = 'DEV-couple' WHERE flag_key = 'dating_couple_link';
  v := public.get_dating_launch_readiness();
  PERFORM pg_temp.expect('L2 DEV- flag evidence', pg_temp.red(v), ARRAY['flag_evidence']);
  IF pg_temp.detail(v, 'flag_evidence') IS DISTINCT FROM '["dating_couple_link"]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: L2 flag_evidence detail: %', pg_temp.detail(v, 'flag_evidence');
  END IF;
  UPDATE private.flag_production_gates SET review_ref = 'W9-COUNSEL-EXPORT' WHERE flag_key = 'dating_couple_link';
  DELETE FROM private.flag_production_gates WHERE flag_key = 'csam_hash_matching';
  PERFORM pg_temp.expect('L2 no gate row', pg_temp.ready_red(), ARRAY['flag_evidence']);
  INSERT INTO private.flag_production_gates (flag_key, gate, review_ref) VALUES ('csam_hash_matching', 'restored', 'S1-W7B-2026');

  -- A gated flag on with DEV- evidence (switched on in development).
  PERFORM pg_temp.env('');
  UPDATE private.flag_production_gates SET review_ref = 'DEV-text' WHERE flag_key = 'text_scale_v2';
  UPDATE public.feature_flags SET enabled = true WHERE key = 'text_scale_v2';
  PERFORM pg_temp.env('production');
  v := public.get_dating_launch_readiness();
  PERFORM pg_temp.expect('L2 flag violation', pg_temp.red(v), ARRAY['no_flag_violations']);
  IF pg_temp.detail(v, 'no_flag_violations') IS DISTINCT FROM '["text_scale_v2"]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: L2 violation detail: %', pg_temp.detail(v, 'no_flag_violations');
  END IF;
  PERFORM pg_temp.env('');
  UPDATE public.feature_flags SET enabled = false WHERE key = 'text_scale_v2';
  UPDATE private.flag_production_gates SET review_ref = 'W10-REVIEW-text_scale_v2' WHERE flag_key = 'text_scale_v2';
  PERFORM pg_temp.env('production');

  -- A pass the fake providers made still stands.
  INSERT INTO public.dating_age_verifications (user_id, age_method, age_result, challenge_age, age_vendor, age_decided_at)
  VALUES (pg_temp.id('04'), 'fae', 'pass', 25, 'fake', now());
  v := public.get_dating_launch_readiness();
  PERFORM pg_temp.expect('L2 fake pass', pg_temp.red(v), ARRAY['no_test_verifications']);
  IF pg_temp.detail(v, 'no_test_verifications') IS DISTINCT FROM '1'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: L2 fake pass count: %', pg_temp.detail(v, 'no_test_verifications');
  END IF;
  UPDATE public.dating_age_verifications SET revoked_at = now(), revoke_reason = 'w10_fixture' WHERE user_id = pg_temp.id('04');
  PERFORM pg_temp.expect('L2 fake pass revoked', pg_temp.ready_red(), ARRAY[]::text[]);

  -- A same-gender purge left pending.
  INSERT INTO private.dating_kill_switch_pending (scope, last_sqlstate) VALUES ('GH', '40P01');
  PERFORM pg_temp.expect('L2 kill switch pending', pg_temp.ready_red(), ARRAY['kill_switch_clear']);
  DELETE FROM private.dating_kill_switch_pending WHERE scope = 'GH';

  -- The SLA alerts have nowhere to go.
  PERFORM set_config('app.settings.moderation_alert_webhook', '', true);
  PERFORM pg_temp.expect('L2 no SLA webhook', pg_temp.ready_red(), ARRAY['sla_alerts']);
  PERFORM set_config('app.settings.moderation_alert_webhook', 'https://alerts.example.invalid/w10', true);

  -- Support resources: one entry past 90 days, or none at all.
  UPDATE public.support_resources SET verified_at = current_date - 91 WHERE country_code = 'GH' AND verified_by = 'w10-fixture';
  PERFORM pg_temp.expect('L2 stale resource', pg_temp.ready_red(), ARRAY['resources:GH']);
  PERFORM pg_temp.expect('L2 one country asked', pg_temp.ready_red('gb'), ARRAY[]::text[]);
  UPDATE public.support_resources SET verified_at = current_date - 90 WHERE country_code = 'GH' AND verified_by = 'w10-fixture';
  PERFORM pg_temp.expect('L2 a resource at 90 days', pg_temp.ready_red(), ARRAY[]::text[]);
  UPDATE public.support_resources SET active = false WHERE country_code = 'GB';
  PERFORM pg_temp.expect('L2 no resource', pg_temp.ready_red(), ARRAY['resources:GB']);
  UPDATE public.support_resources SET active = true WHERE country_code = 'GB' AND verified_by = 'w10-fixture';

  -- An invalid country is refused, never read as Ghana and the UK.
  IF public.get_dating_launch_readiness('XX') IS DISTINCT FROM '{"ok": false, "reason": "invalid"}'::jsonb
     OR public.get_dating_launch_readiness('GHA') IS DISTINCT FROM '{"ok": false, "reason": "invalid"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: L2 an invalid country was read';
  END IF;
  PERFORM pg_temp.env('');
END $$;

-- The checklist as a row the gates read (p_row), each gap alone.
DO $$
DECLARE
  r public.country_safety_config := public.dating_country_config('GH');
  v jsonb;
BEGIN
  PERFORM pg_temp.env('production');
  r.legal_checklist := r.legal_checklist || '{"ghana_legal_opinion": "dev-opinion"}';
  v := jsonb_build_object('gates', private.dating_launch_gates(ARRAY['GH'], r));
  PERFORM pg_temp.expect('L2 DEV- checklist', pg_temp.red(v), ARRAY['checklist:GH']);
  IF pg_temp.detail(v, 'checklist:GH') IS DISTINCT FROM '["dev_reference"]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: L2 checklist detail: %', pg_temp.detail(v, 'checklist:GH');
  END IF;
  r := public.dating_country_config('GB');
  r.legal_checklist := r.legal_checklist || '{"same_gender_reconsideration": {"legal_opinion": "DEV-opinion"}}';
  v := jsonb_build_object('gates', private.dating_launch_gates(ARRAY['GB'], r));
  PERFORM pg_temp.expect('L2 nested DEV- reference', pg_temp.red(v), ARRAY['checklist:GB']);
  IF pg_temp.detail(v, 'checklist:GB') IS DISTINCT FROM '["dev_reference"]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: L2 nested checklist detail: %', pg_temp.detail(v, 'checklist:GB');
  END IF;
  r := public.dating_country_config('GH');
  r.legal_checklist := r.legal_checklist || '{"dpc_registration": null}';
  v := jsonb_build_object('gates', private.dating_launch_gates(ARRAY['GH'], r));
  PERFORM pg_temp.expect('L2 missing evidence', pg_temp.red(v), ARRAY['checklist:GH']);
  r := public.dating_country_config('GH');
  r.resources_verified_at := now() - interval '91 days';
  v := jsonb_build_object('gates', private.dating_launch_gates(ARRAY['GH'], r));
  PERFORM pg_temp.expect('L2 row resources old', pg_temp.red(v), ARRAY['resources:GH']);
  PERFORM pg_temp.env('');
END $$;

-- =====================================================================
-- L3: opening a place in production; reductions; DEV- in the checklist.
-- =====================================================================
DO $$
DECLARE
  v jsonb;
  v_version integer := (public.dating_country_config('GH')).version;
BEGIN
  PERFORM pg_temp.env('production');
  PERFORM set_config('app.settings.age_assurance_mode', 'sandbox', true);
  v := public.publish_country_config('GH', '{"dating_enabled": true}');
  IF v IS DISTINCT FROM '{"ok": false, "reason": "config:launch_not_ready", "gates": ["age_assurance_live"]}'::jsonb
     AND pg_temp.logs_ok() THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: L3 Ghana opened while a gate was red: %', v;
  END IF;
  IF (public.dating_country_config('GH')).version <> v_version OR (public.dating_country_config('GH')).dating_enabled THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: L3 a refused opening published a version';
  END IF;
  PERFORM set_config('app.settings.age_assurance_mode', 'live', true);
  IF NOT pg_temp.logs_ok() THEN
    RAISE NOTICE 'dating_v2_launch_contracts: the server''s log settings are unsafe; the green opening is not checked here';
  ELSE
    -- The publish that opens may bring the last piece of evidence itself:
    -- the gates read the row it publishes, not the current one.
    PERFORM pg_temp.env('');
    PERFORM public.publish_country_config('GH', pg_temp.checklist('GH', '{"dpc_registration": null}'));
    PERFORM pg_temp.env('production');
    v := public.publish_country_config('GH', '{"dating_enabled": true}'
                                             || pg_temp.checklist('GH', '{"dpc_registration": "DPC-REG-0001"}'));
    IF (v ->> 'ok')::boolean IS NOT TRUE OR (v ->> 'dating_enabled')::boolean IS NOT TRUE THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: L3 Ghana did not open with every gate green: %', v;
    END IF;
    IF public.get_dating_launch_readiness() -> 'open' IS DISTINCT FROM '["GH"]'::jsonb THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: L3 open countries: %', public.get_dating_launch_readiness() -> 'open';
    END IF;
    -- A region newly open is an opening too.
    PERFORM set_config('app.settings.age_assurance_mode', 'sandbox', true);
    v := public.publish_country_config('GH', '{"open_regions": ["AA", "AH", "CP"]}');
    IF v ->> 'reason' IS DISTINCT FROM 'config:launch_not_ready' THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: L3 a region opened while a gate was red: %', v;
    END IF;
    -- A reduction is never refused: a region closed, then the country.
    v := public.publish_country_config('GH', '{"open_regions": ["AA"]}');
    IF (v ->> 'ok')::boolean IS NOT TRUE THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: L3 narrowing was refused: %', v;
    END IF;
    v := public.publish_country_config('GH', '{"dating_enabled": false}');
    IF (v ->> 'ok')::boolean IS NOT TRUE OR (v ->> 'dating_enabled')::boolean IS NOT FALSE THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: L3 closing was refused: %', v;
    END IF;
    PERFORM set_config('app.settings.age_assurance_mode', 'live', true);
  END IF;

  -- A DEV- reference in the checklist: refused in production...
  v := public.publish_country_config('GH', '{"dating_enabled": true}' || pg_temp.checklist('GH', '{"dpia": "DEV-dpia"}'));
  IF v ->> 'reason' IS DISTINCT FROM 'config:production_checks_failed'
     OR NOT (v -> 'checks') ? 'dev_reference' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: L3 a DEV- checklist reference was not refused in production: %', v;
  END IF;
  v := public.publish_country_config('GB', '{"dating_enabled": true}' || pg_temp.checklist('GB', '{"tier_review": " Dev-tier"}'));
  IF v ->> 'reason' IS DISTINCT FROM 'config:production_checks_failed' OR NOT (v -> 'checks') ? 'dev_reference' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: L3 a padded dev- reference was not refused: %', v;
  END IF;
  -- ...reported, not enforced, in development.
  PERFORM pg_temp.env('');
  v := public.publish_country_config('GH', pg_temp.checklist('GH', '{"dpia": "DEV-dpia"}'));
  IF (v ->> 'ok')::boolean IS NOT TRUE OR NOT (v -> 'checks') ? 'dev_reference' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: L3 development did not publish and report the DEV- reference: %', v;
  END IF;
  v := public.publish_country_config('GH', pg_temp.checklist('GH', '{"dpia": "DPIA-v3-SIGNED"}'));
  IF (v ->> 'ok')::boolean IS NOT TRUE OR (v -> 'checks') ? 'dev_reference' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: L3 a real reference still reads as DEV-: %', v;
  END IF;
END $$;

-- =====================================================================
-- L4: a gated flag's DEV- evidence is no evidence in production.
-- =====================================================================
DO $$
DECLARE
  v_msg text;
BEGIN
  PERFORM pg_temp.env('production');
  v_msg := pg_temp.err($q$SELECT public.record_flag_gate_evidence('dating_mode_enabled', 'DEV-launch')$q$);
  IF v_msg IS DISTINCT FROM 'flag:dev_reference' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: L4 DEV- evidence was recorded in production (got %)', coalesce(v_msg, 'no error');
  END IF;
  v_msg := pg_temp.err($q$SELECT public.record_flag_gate_evidence('dating_mode_enabled', E'\t dev-launch')$q$);
  IF v_msg IS DISTINCT FROM 'flag:dev_reference' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: L4 padded dev- evidence was recorded (got %)', coalesce(v_msg, 'no error');
  END IF;
  -- In development it is recorded (the dev project's own testing) ...
  PERFORM pg_temp.env('');
  v_msg := pg_temp.err($q$SELECT public.record_flag_gate_evidence('dating_mode_enabled', 'DEV-launch')$q$);
  IF v_msg IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: L4 development refused DEV- evidence (got %)', v_msg;
  END IF;
  -- ... and in production it never lets the flag on.
  PERFORM pg_temp.env('production');
  v_msg := pg_temp.err($q$UPDATE public.feature_flags SET enabled = true WHERE key = 'dating_mode_enabled'$q$);
  IF v_msg IS DISTINCT FROM 'flag:gate_evidence_required' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: L4 a flag went on in production on DEV- evidence (got %)', coalesce(v_msg, 'no error');
  END IF;
  -- Real evidence still lets it on (Spec 1's rule unchanged).
  PERFORM public.record_flag_gate_evidence('dating_mode_enabled', 'W10-LAUNCH-2026-12');
  UPDATE public.feature_flags SET enabled = true WHERE key = 'dating_mode_enabled';
  IF EXISTS (SELECT 1 FROM public.production_flag_violations() AS x WHERE x = 'dating_mode_enabled') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: L4 real evidence still reads as a violation';
  END IF;
  UPDATE public.feature_flags SET enabled = false WHERE key = 'dating_mode_enabled';
  PERFORM pg_temp.env('');
END $$;

-- =====================================================================
-- L5: the console's readiness, metrics and fairness (the safety owner's).
-- =====================================================================
DO $$
DECLARE
  v jsonb;
  v_before bigint;
BEGIN
  v_before := coalesce((SELECT sum(c.count) FROM public.metric_counters AS c
                         WHERE c.key = 'dating.moderation.not_moderator'), 0);
  IF public.moderation_launch_readiness(pg_temp.id('03'), NULL) IS DISTINCT FROM '{"ok": false, "reason": "not_moderator"}'::jsonb
     OR public.moderation_metrics(pg_temp.id('03'), 7) IS DISTINCT FROM '{"ok": false, "reason": "not_moderator"}'::jsonb
     OR public.moderation_fairness(pg_temp.id('03'), 4) IS DISTINCT FROM '{"ok": false, "reason": "not_moderator"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: L5 someone who is not a moderator was answered';
  END IF;
  IF coalesce((SELECT sum(c.count) FROM public.metric_counters AS c
                WHERE c.key = 'dating.moderation.not_moderator'), 0) <> v_before + 3 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: L5 a not_moderator refusal was not counted';
  END IF;
  IF public.moderation_launch_readiness(pg_temp.id('02'), NULL) IS DISTINCT FROM '{"ok": false, "reason": "safety_owner_only"}'::jsonb
     OR public.moderation_metrics(pg_temp.id('02'), 7) IS DISTINCT FROM '{"ok": false, "reason": "safety_owner_only"}'::jsonb
     OR public.moderation_fairness(pg_temp.id('02'), 4) IS DISTINCT FROM '{"ok": false, "reason": "safety_owner_only"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: L5 a moderator read the safety owner''s pages';
  END IF;
  v := public.moderation_launch_readiness(pg_temp.id('01'), 'gh');
  IF v -> 'countries' IS DISTINCT FROM '["GH"]'::jsonb OR (v ->> 'ready')::boolean IS NOT FALSE
     OR pg_temp.red(v) IS DISTINCT FROM (CASE WHEN pg_temp.logs_ok() THEN ARRAY['environment']
                                              ELSE ARRAY['environment', 'log_settings_safe'] END) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: L5 the owner''s readiness: %', v;
  END IF;
  IF public.moderation_launch_readiness(pg_temp.id('01'), 'XX') IS DISTINCT FROM '{"ok": false, "reason": "invalid"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: L5 an invalid country was read';
  END IF;

  -- Metrics: dating.* keys summed over the window, shown at n >= 50.
  DELETE FROM public.metric_counters;
  INSERT INTO public.metric_counters (day, key, count) VALUES
    ((now() AT TIME ZONE 'utc')::date, 'dating.mutual', 30),
    ((now() AT TIME ZONE 'utc')::date - 6, 'dating.mutual', 20),
    ((now() AT TIME ZONE 'utc')::date - 7, 'dating.mutual', 1000),
    ((now() AT TIME ZONE 'utc')::date, 'dating.block', 49),
    ((now() AT TIME ZONE 'utc')::date, 'dating.activated', 75),
    ((now() AT TIME ZONE 'utc')::date, 'stories.viewed', 500);
  v := public.moderation_metrics(pg_temp.id('01'), 7);
  IF v -> 'metrics' IS DISTINCT FROM '[{"key": "dating.activated", "count": 75}, {"key": "dating.mutual", "count": 50}]'::jsonb
     OR (v ->> 'suppressed')::int IS DISTINCT FROM 1 OR (v ->> 'min_count')::int IS DISTINCT FROM 50
     OR (v ->> 'days')::int IS DISTINCT FROM 7
     OR (v ->> 'from')::date IS DISTINCT FROM (now() AT TIME ZONE 'utc')::date - 6
     OR (v ->> 'to')::date IS DISTINCT FROM (now() AT TIME ZONE 'utc')::date THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: L5 the 7-day metrics: %', v;
  END IF;
  v := public.moderation_metrics(pg_temp.id('01'), 28);
  IF v -> 'metrics' -> 1 IS DISTINCT FROM '{"key": "dating.mutual", "count": 1050}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: L5 the 28-day metrics: %', v;
  END IF;
  IF public.moderation_metrics(pg_temp.id('01'), 30) IS DISTINCT FROM '{"ok": false, "reason": "invalid"}'::jsonb
     OR public.moderation_metrics(pg_temp.id('01'), NULL) IS DISTINCT FROM '{"ok": false, "reason": "invalid"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: L5 a window other than 7, 28 or 90 days was read';
  END IF;

  -- Fairness: the last weeks' reports, flagged cohorts first.
  DELETE FROM public.dating_fairness_reports;
  INSERT INTO public.dating_fairness_reports (week, country_code, cohort_key, active_bucket, introductions_per_active,
                                              mutual_rate, flagged) VALUES
    (current_date - 3, 'GH', 'gender:woman', '100–499', 2.10, 0.12, false),
    (current_date - 3, 'GH', 'region:AA', '100–499', 1.40, 0.09, true),
    (current_date - 10, 'GB', 'age:25_34', '50–99', 2.00, NULL, false),
    (current_date - 90, 'GH', 'top_decile', '500+', 9.00, 0.20, true);
  v := public.moderation_fairness(pg_temp.id('01'), 4);
  IF jsonb_array_length(v -> 'reports') <> 3 OR (v ->> 'flagged')::int <> 1
     OR v -> 'reports' -> 0 ->> 'cohort' IS DISTINCT FROM 'region:AA'
     OR v -> 'reports' -> 1 ->> 'cohort' IS DISTINCT FROM 'gender:woman'
     OR v -> 'reports' -> 2 ->> 'country' IS DISTINCT FROM 'GB'
     OR v -> 'reports' -> 2 -> 'mutual_rate' IS DISTINCT FROM 'null'::jsonb
     OR v -> 'reports' -> 0 ->> 'active' IS DISTINCT FROM '100–499' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: L5 the fairness reports: %', v;
  END IF;
  IF public.moderation_fairness(pg_temp.id('01'), 0) IS DISTINCT FROM '{"ok": false, "reason": "invalid"}'::jsonb
     OR public.moderation_fairness(pg_temp.id('01'), 13) IS DISTINCT FROM '{"ok": false, "reason": "invalid"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: L5 a window outside 1-12 weeks was read';
  END IF;
END $$;

-- =====================================================================
-- L6: grants. The readiness and the console's reads are the service
-- role's alone; the helpers nobody's.
-- =====================================================================
DO $$
DECLARE
  f text;
BEGIN
  FOREACH f IN ARRAY ARRAY['public.get_dating_launch_readiness(text)', 'public.moderation_launch_readiness(uuid,text)',
                           'public.moderation_metrics(uuid,integer)', 'public.moderation_fairness(uuid,integer)'] LOOP
    IF has_function_privilege('anon', f, 'EXECUTE') OR has_function_privilege('authenticated', f, 'EXECUTE')
       OR NOT has_function_privilege('service_role', f, 'EXECUTE') THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: L6 % is granted wrongly', f;
    END IF;
  END LOOP;
  FOREACH f IN ARRAY ARRAY['private.is_dev_reference(text)', 'private.is_real_reference(text)',
                           'private.dating_launch_gates(text[],public.country_safety_config)'] LOOP
    IF has_function_privilege('anon', f, 'EXECUTE') OR has_function_privilege('authenticated', f, 'EXECUTE')
       OR has_function_privilege('service_role', f, 'EXECUTE') THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: L6 % is granted to an API role', f;
    END IF;
  END LOOP;
  IF has_function_privilege('authenticated', 'public.record_flag_gate_evidence(text,text)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.record_flag_gate_evidence(text,text)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.publish_country_config(text,jsonb)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: L6 a re-created function lost or gained a grant';
  END IF;
  RAISE NOTICE 'dating_v2_launch_contracts: all held';
END $$;

ROLLBACK;
````

- [ ] **Step 3: Run it to see it fail**

```bash
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/dating_v2_launch_contracts.sql 2>&1 | grep -m1 ERROR
```

Expected: `psql:supabase/tests/dating_v2_launch_contracts.sql:63: ERROR:  function public.get_dating_launch_readiness(text) does not exist` (the helper `pg_temp.ready_red` is SQL, so its body is checked when it is created: the first W10 name the file reaches).

- [ ] **Step 4: The new functions, the builder and the twin**

Create `.superpowers/sdd/2026-11-23-spec2-w10/mig_head.sql` with exactly:

````sql
-- ---------------------------------------------------------------------
-- 1. A development reference (W5a's rule, fix round 1 M-7: 'DEV-' in any
--    case, after any padding) and a reference that counts as evidence.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.is_dev_reference(p_ref text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $$
  SELECT coalesce(pg_catalog.upper(pg_catalog.btrim(p_ref, E' \t\r\n')) LIKE 'DEV-%', false);
$$;

CREATE OR REPLACE FUNCTION private.is_real_reference(p_ref text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $$
  SELECT coalesce(pg_catalog.btrim(p_ref, E' \t\r\n') <> '', false) AND NOT private.is_dev_reference(p_ref);
$$;

-- ---------------------------------------------------------------------
-- 2. The launch gates (§8 W10's gate line and every earlier wave's
--    machine-checkable one). One row per gate: {gate, ok} and, where it
--    helps the owner, detail (what is red). p_row, when given, stands in
--    for the current row of its country (publish_country_config checks the
--    row it is about to publish). W9 is read only through its flag's gate
--    row (dating_couple_link, a string), so W9 not applied reads red,
--    never an error; the export function is never named (the canary's S-4
--    scan follows names, and it decrypts).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.dating_launch_gates(p_countries text[],
                                                       p_row public.country_safety_config DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  -- Every flag Dating's launch turns on (W11's dating_voice_calls is not
  -- created yet and is not a launch flag), and the Spec 1 flags Dating
  -- needs on with it (Get help's directory, inline CSAM hashing).
  v_flags constant text[] := ARRAY['dating_mode_enabled', 'dating_candidate_generation', 'dating_match_messaging',
    'dating_profile_photos', 'dating_same_gender_matching', 'dating_age_assurance', 'dating_traveller_detection',
    'dating_couple_link', 'support_resources_v2', 'csam_hash_matching'];
  v_h constant jsonb := public.get_dating_operational_health();
  v_gates jsonb := '[]'::jsonb;
  v_red text[];
  v_n integer;
  v_code text;
  v_row public.country_safety_config;
BEGIN
  v_gates := v_gates || pg_catalog.jsonb_build_array(
    -- R-6: red until the owner has set the project to production mode.
    pg_catalog.jsonb_build_object('gate', 'environment', 'ok', private.attune_environment() = 'production'),
    -- §3.3.5: real verification (never fake, never sandbox).
    pg_catalog.jsonb_build_object('gate', 'age_assurance_live', 'ok', private.dating_verification_mode() = 'live'),
    -- W7: a safety owner and a moderator, both active.
    pg_catalog.jsonb_build_object('gate', 'safety_owner', 'ok',
      EXISTS (SELECT 1 FROM public.dating_moderators AS m WHERE m.active AND m.role = 'safety_owner')),
    pg_catalog.jsonb_build_object('gate', 'moderator', 'ok',
      EXISTS (SELECT 1 FROM public.dating_moderators AS m WHERE m.active AND m.role = 'moderator')),
    -- W1, W5, W6: the three keys set and their fingerprints seeded.
    pg_catalog.jsonb_build_object('gate', 'keys', 'ok',
      coalesce((v_h ->> 'exclusion_key_fingerprint_ok')::boolean, false)
      AND coalesce((v_h ->> 'field_key_fingerprint_ok')::boolean, false)
      AND coalesce(public.app_setting('dating_push_key'), '') <> ''),
    -- W5 gate: the introductions config active with real review references.
    pg_catalog.jsonb_build_object('gate', 'introductions_config', 'ok',
      EXISTS (SELECT 1 FROM public.dating_algorithm_configs AS c WHERE c.state = 'active')
      AND NOT EXISTS (SELECT 1 FROM public.dating_algorithm_configs AS c
                       WHERE c.state = 'active'
                         AND NOT (private.is_real_reference(c.product_review_ref)
                                  AND private.is_real_reference(c.clinical_review_ref)
                                  AND private.is_real_reference(c.fairness_review_ref)
                                  AND private.is_real_reference(c.safety_review_ref)))),
    -- W6 gate: the chat's lexicon active with the reviewers' reference.
    pg_catalog.jsonb_build_object('gate', 'chat_config', 'ok',
      EXISTS (SELECT 1 FROM public.dating_safety_configs AS c WHERE c.state = 'active')
      AND NOT EXISTS (SELECT 1 FROM public.dating_safety_configs AS c
                       WHERE c.state = 'active' AND NOT private.is_real_reference(c.review_ref))));

  -- Each launch flag has its production gate row with real evidence.
  v_red := ARRAY(SELECT f.key FROM unnest(v_flags) AS f(key)
                  WHERE NOT EXISTS (SELECT 1 FROM private.flag_production_gates AS g
                                     WHERE g.flag_key = f.key AND private.is_real_reference(g.review_ref))
                  ORDER BY f.key);
  v_gates := v_gates || pg_catalog.jsonb_build_array(
    pg_catalog.jsonb_build_object('gate', 'flag_evidence', 'ok', cardinality(v_red) = 0, 'detail', to_jsonb(v_red)));
  -- No gated flag (any spec's) is on without real evidence.
  v_red := ARRAY(SELECT v FROM public.production_flag_violations() AS v ORDER BY v);
  v_gates := v_gates || pg_catalog.jsonb_build_array(
    pg_catalog.jsonb_build_object('gate', 'no_flag_violations', 'ok', cardinality(v_red) = 0, 'detail', to_jsonb(v_red)));
  -- No age or identity pass made by the fake providers still stands.
  SELECT count(*) INTO v_n FROM public.dating_age_verifications AS v
   WHERE v.revoked_at IS NULL AND (v.age_vendor = 'fake' OR v.identity_vendor = 'fake');
  v_gates := v_gates || pg_catalog.jsonb_build_array(
    pg_catalog.jsonb_build_object('gate', 'no_test_verifications', 'ok', v_n = 0, 'detail', v_n),
    -- W1d: no same-gender purge left pending.
    pg_catalog.jsonb_build_object('gate', 'kill_switch_clear', 'ok',
      coalesce(pg_catalog.jsonb_array_length(v_h -> 'kill_switch_pending'), 1) = 0),
    -- W1d (§2.4): nothing can write an RPC's parameters to the log.
    pg_catalog.jsonb_build_object('gate', 'log_settings_safe', 'ok', coalesce((v_h ->> 'log_settings_safe')::boolean, false)),
    -- W7: the SLA alerts have somewhere to go.
    pg_catalog.jsonb_build_object('gate', 'sla_alerts', 'ok',
      coalesce(public.app_setting('moderation_alert_webhook'), '') <> ''));

  -- Per country: the checklist complete with real references (§2.2, as
  -- the publisher checks a row with Dating on; never its name here: the
  -- canary's S-4 scan follows names), and the support
  -- resources verified within 90 days (the row's date and every active
  -- entry of Spec 1's directory for the country, at least one).
  FOREACH v_code IN ARRAY coalesce(p_countries, ARRAY[]::text[]) LOOP
    v_row := CASE WHEN (p_row).country_code IS NOT DISTINCT FROM v_code THEN p_row
                  ELSE public.dating_country_config(v_code) END;
    v_row.dating_enabled := true;
    -- (the resources and the keys are gates of their own)
    v_red := ARRAY(SELECT c FROM unnest(private.country_config_checks(v_row)) AS c
                    WHERE c NOT IN ('resources_not_verified', 'exclusion_key_not_ready', 'field_key_not_ready')
                    ORDER BY c);
    v_gates := v_gates || pg_catalog.jsonb_build_array(
      pg_catalog.jsonb_build_object('gate', 'checklist:' || v_code, 'ok', cardinality(v_red) = 0,
                                    'detail', to_jsonb(v_red)),
      pg_catalog.jsonb_build_object('gate', 'resources:' || v_code, 'ok',
        coalesce(v_row.resources_verified_at >= now() - interval '90 days', false)
        AND EXISTS (SELECT 1 FROM public.support_resources AS s WHERE s.country_code = v_code AND s.active)
        AND NOT EXISTS (SELECT 1 FROM public.support_resources AS s
                         WHERE s.country_code = v_code AND s.active
                           AND (s.verified_at IS NULL OR s.verified_at < current_date - 90))));
  END LOOP;
  RETURN v_gates;
END;
$$;

-- ---------------------------------------------------------------------
-- 3. The readiness (service role: the owner from the SQL editor, the
--    console through moderation_launch_readiness). ready only when every
--    gate is green, so never while the project reads development (R-6).
--    Ghana and the UK unless one country is asked for.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_dating_launch_readiness(p_country text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_code constant text := upper(btrim(coalesce(p_country, '')));
  v_countries text[];
  v_gates jsonb;
BEGIN
  IF p_country IS NULL THEN
    v_countries := ARRAY['GH', 'GB'];
  ELSIF v_code ~ '^[A-Z]{2}$' AND private.dating_iso_country(v_code) IS NOT NULL THEN
    v_countries := ARRAY[v_code];
  ELSE
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid');
  END IF;
  v_gates := private.dating_launch_gates(v_countries);
  RETURN pg_catalog.jsonb_build_object('ok', true,
    'ready', NOT EXISTS (SELECT 1 FROM pg_catalog.jsonb_array_elements(v_gates) AS g
                          WHERE (g ->> 'ok')::boolean IS NOT TRUE),
    'environment', private.attune_environment(),
    'countries', to_jsonb(v_countries),
    'open', to_jsonb(ARRAY(SELECT c FROM unnest(v_countries) AS c
                            WHERE (public.dating_country_config(c)).dating_enabled ORDER BY c)),
    'gates', v_gates);
END;
$$;

-- ---------------------------------------------------------------------
-- 4. The console's readiness and dashboards (§6.4, §6.9, §5.9): the safety
--    owner's (a moderator gets safety_owner_only; anyone else
--    not_moderator, counted). Reads, never audited, as the other lists.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.moderation_launch_readiness(p_actor uuid, p_country text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_mod public.dating_moderators := private.dating_moderator(p_actor);
BEGIN
  IF v_mod.user_id IS NULL THEN
    PERFORM private.bump_metric_internal('dating.moderation.not_moderator');
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_moderator');
  END IF;
  IF v_mod.role <> 'safety_owner' THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'safety_owner_only');
  END IF;
  RETURN public.get_dating_launch_readiness(p_country);
END;
$$;

-- §6.9: every dating.* counter summed over the last 7, 28 or 90 UTC days,
-- shown only at n >= 50 (the rest are counted, never named).
CREATE OR REPLACE FUNCTION public.moderation_metrics(p_actor uuid, p_days integer)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_mod public.dating_moderators := private.dating_moderator(p_actor);
  v_to constant date := (now() AT TIME ZONE 'utc')::date;
  v_from date;
  v jsonb;
BEGIN
  IF v_mod.user_id IS NULL THEN
    PERFORM private.bump_metric_internal('dating.moderation.not_moderator');
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_moderator');
  END IF;
  IF v_mod.role <> 'safety_owner' THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'safety_owner_only');
  END IF;
  IF p_days IS NULL OR p_days NOT IN (7, 28, 90) THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid');
  END IF;
  v_from := v_to - (p_days - 1);
  SELECT pg_catalog.jsonb_build_object('ok', true, 'days', p_days, 'from', v_from, 'to', v_to, 'min_count', 50,
           'metrics', coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('key', x.key, 'count', x.n)
                                                    ORDER BY x.key) FILTER (WHERE x.n >= 50), '[]'::jsonb),
           'suppressed', count(*) FILTER (WHERE x.n < 50))
    INTO v
    FROM (SELECT c.key, sum(c.count) AS n
            FROM public.metric_counters AS c
           WHERE c.day BETWEEN v_from AND v_to AND left(c.key, 7) = 'dating.'
           GROUP BY c.key) AS x;
  RETURN v;
END;
$$;

-- §5.9: the weekly fairness reports of the last 1-12 weeks (rows exist
-- only for n >= 50), flagged cohorts first.
CREATE OR REPLACE FUNCTION public.moderation_fairness(p_actor uuid, p_weeks integer)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_mod public.dating_moderators := private.dating_moderator(p_actor);
BEGIN
  IF v_mod.user_id IS NULL THEN
    PERFORM private.bump_metric_internal('dating.moderation.not_moderator');
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_moderator');
  END IF;
  IF v_mod.role <> 'safety_owner' THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'safety_owner_only');
  END IF;
  IF p_weeks IS NULL OR p_weeks NOT BETWEEN 1 AND 12 THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid');
  END IF;
  RETURN pg_catalog.jsonb_build_object('ok', true, 'weeks', p_weeks,
    'flagged', (SELECT count(*) FROM public.dating_fairness_reports AS r
                 WHERE r.flagged AND r.week > current_date - 7 * p_weeks),
    'reports', coalesce((
      SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('week', r.week, 'country', r.country_code,
               'cohort', r.cohort_key, 'active', r.active_bucket,
               'introductions_per_active', r.introductions_per_active, 'mutual_rate', r.mutual_rate,
               'flagged', r.flagged)
             ORDER BY r.flagged DESC, r.week DESC, r.country_code, r.cohort_key)
        FROM public.dating_fairness_reports AS r
       WHERE r.week > current_date - 7 * p_weeks), '[]'::jsonb));
END;
$$;
````

Create `.superpowers/sdd/2026-11-23-spec2-w10/build_mig.py` with exactly:

````python
#!/usr/bin/env python3
"""Spec 2 W10: builds supabase/migrations/20261124100000_dating_v2_launch_guards.sql
from the header below, mig_head.sql (the new functions), the five
functions re-created from their LIVE bodies (saved to before_w10/ before
the migration is first applied) with only the lines marked
"-- Spec 2 W10" changed, and the self-revoke tail. Every anchor must
occur exactly once. usage (repo root): build_mig.py [migration path]"""
import pathlib, sys

D = pathlib.Path('.superpowers/sdd/2026-11-23-spec2-w10')
B = D / 'before_w10'
T = 'Spec 2 W10'
OUT = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else 'supabase/migrations/20261124100000_dating_v2_launch_guards.sql')

EDITS = {
    # DEV- refs: a gated flag's DEV- evidence is no evidence in production.
    'private.guard_flag_production_gate()': [
        ("""                  WHERE g.flag_key = NEW.key AND g.review_ref IS NULL) THEN
""", f"""                  WHERE g.flag_key = NEW.key -- {T}
                    AND (g.review_ref IS NULL OR private.is_dev_reference(g.review_ref))) THEN -- {T}: a DEV- reference is none
"""),
    ],
    'public.record_flag_gate_evidence(text,text)': [
        ("""    RAISE EXCEPTION 'flag:review_ref_required';
  END IF;
""", f"""    RAISE EXCEPTION 'flag:review_ref_required';
  END IF;
  -- {T} (§8 W10): in production a DEV- reference is no evidence.
  IF private.attune_environment() = 'production' AND private.is_dev_reference(p_review_ref) THEN -- {T}
    RAISE EXCEPTION 'flag:dev_reference'; -- {T}
  END IF; -- {T}
"""),
    ],
    'public.production_flag_violations()': [
        ("""   WHERE f.enabled AND g.review_ref IS NULL
""", f"""   WHERE f.enabled AND (g.review_ref IS NULL OR private.is_dev_reference(g.review_ref)) -- {T}
"""),
    ],
    # The checklist: no DEV- reference counts, at any level.
    'private.country_config_checks(public.country_safety_config)': [
        ("""    v_checks := array_append(v_checks, 'same_gender_reconsideration_missing');
  END IF;
  RETURN v_checks;
""", f"""    v_checks := array_append(v_checks, 'same_gender_reconsideration_missing');
  END IF;
  -- {T} (§8 W10): a DEV- reference is never evidence, at any level of the
  -- {T} checklist (the same-gender reconsideration's too).
  IF EXISTS (SELECT 1 FROM jsonb_each(coalesce(p_row.legal_checklist, '{{}}'::jsonb)) AS e -- {T}
              WHERE (jsonb_typeof(e.value) = 'string' AND private.is_dev_reference(e.value #>> '{{}}')) -- {T}
                 OR (jsonb_typeof(e.value) = 'object' -- {T}
                     AND EXISTS (SELECT 1 FROM jsonb_each(e.value) AS s -- {T}
                                  WHERE jsonb_typeof(s.value) = 'string' -- {T}
                                    AND private.is_dev_reference(s.value #>> '{{}}')))) THEN -- {T}
    v_checks := array_append(v_checks, 'dev_reference'); -- {T}
  END IF; -- {T}
  RETURN v_checks;
"""),
    ],
    # Opening a place in production needs its launch gates green.
    'public.publish_country_config(text,jsonb)': [
        ("""  v_told integer; -- Spec 2 W3a
""", f"""  v_told integer; -- Spec 2 W3a
  v_red text[]; -- {T}
"""),
        ("""    RETURN jsonb_build_object('ok', false, 'reason', 'config:production_checks_failed',
                              'checks', to_jsonb(v_checks));
  END IF;
""", f"""    RETURN jsonb_build_object('ok', false, 'reason', 'config:production_checks_failed',
                              'checks', to_jsonb(v_checks));
  END IF;
  -- {T} (§8 W10): in production a publish that opens a place (the country,
  -- {T} or a region newly open) needs the launch gates green for the row it
  -- {T} publishes; a reduction opens nothing, so it is never refused here.
  IF private.attune_environment() = 'production' AND v_new.dating_enabled -- {T}
     AND NOT coalesce(v_open_new <@ v_open_old, false) THEN -- {T}
    v_red := ARRAY(SELECT g ->> 'gate' FROM jsonb_array_elements(private.dating_launch_gates(ARRAY[v_code], v_new)) AS g -- {T}
                    WHERE (g ->> 'ok')::boolean IS NOT TRUE ORDER BY 1); -- {T}
    IF cardinality(v_red) > 0 THEN -- {T}
      RETURN jsonb_build_object('ok', false, 'reason', 'config:launch_not_ready', 'gates', to_jsonb(v_red)); -- {T}
    END IF; -- {T}
  END IF; -- {T}
"""),
    ],
}

HEADER = """-- Spec 2 W10, migration 1 (§8 W10, §4.9 W10, §2.2, §3.3.5, §5.9, §6.4,
-- §6.9; R-6, Q19b): dating_v2_launch_guards.
--   * private.is_dev_reference(text) and private.is_real_reference(text):
--     the one rule for a DEV- reference (W5a's) and for real evidence.
--   * Production-mode guards. They apply only while
--     private.attune_environment() reads 'production'; nothing here sets
--     it (R-6), and no flag or country is turned on.
--     - checklist: country_config_checks also reports dev_reference for a
--       DEV- reference anywhere in legal_checklist, so publish_country_config
--       refuses it in production (a reduction is still published, W1d);
--     - DEV- refs: a gated flag's DEV- evidence is no evidence there (the
--       gate trigger, production_flag_violations), and
--       record_flag_gate_evidence refuses one (flag:dev_reference);
--     - provider mode and the rest: a publish that opens a place (the
--       country, or a region newly open) is refused with
--       config:launch_not_ready and the red gates unless the launch gates
--       for that country are green (age_assurance_mode 'live', the safety
--       owner and a moderator active, no DEV- reference active, ...).
--   * get_dating_launch_readiness(p_country) (service role): every gate,
--     ready only when all are green, so never in development.
--   * The console's readiness and dashboards, the safety owner's:
--     moderation_launch_readiness, moderation_metrics (dating.* counters at
--     n >= 50, §6.9) and moderation_fairness (§5.9).
-- Re-created from their LIVE bodies, changed lines marked -- Spec 2 W10:
-- private.guard_flag_production_gate, public.record_flag_gate_evidence,
-- public.production_flag_violations, private.country_config_checks,
-- public.publish_country_config (their grants are kept).
-- Grants in 20261124100010_dating_v2_launch_guards_grants.sql. Ends by
-- revoking everything it creates from every API role (the W6 final
-- pattern: a push that stops between this file and its twin fails closed).
BEGIN;
SET LOCAL lock_timeout = '5s';

"""

TAIL = """
-- ---------------------------------------------------------------------
-- Self-revoke (the W6 final pattern); the twin grants.
-- ---------------------------------------------------------------------
REVOKE ALL ON FUNCTION
  private.is_dev_reference(text), private.is_real_reference(text),
  private.dating_launch_gates(text[], public.country_safety_config),
  public.get_dating_launch_readiness(text),
  public.moderation_launch_readiness(uuid, text), public.moderation_metrics(uuid, integer),
  public.moderation_fairness(uuid, integer)
  FROM PUBLIC, anon, authenticated, service_role;

COMMIT;
"""


def recreated(sig, edits):
    src = (B / f'{sig}.sql').read_text().rstrip('\n') + '\n'
    for old, new in edits:
        n = src.count(old)
        assert n == 1, f'{sig}: anchor occurs {n} times: {old[:70]!r}'
        src = src.replace(old, new)
    return src + ';\n'


parts = [HEADER, (D / 'mig_head.sql').read_text(), '\n-- ---------------------------------------------------------------------\n'
         '-- 5. Re-created from their LIVE bodies (changed lines marked -- Spec 2 W10).\n'
         '-- ---------------------------------------------------------------------\n']
for sig, edits in EDITS.items():
    parts.append(f'\n-- {sig}\n' + recreated(sig, edits))
parts.append(TAIL)
OUT.write_text(''.join(parts))
print(f'{OUT}: {len(EDITS)} re-created, {sum(map(len, EDITS.values()))} edit(s)')
````

Create `supabase/migrations/20261124100010_dating_v2_launch_guards_grants.sql` with exactly:

````sql
-- Spec 2 W10: grants for 20261124100000_dating_v2_launch_guards.sql. The
-- readiness and the console's reads are the service role's alone (the
-- owner's SQL editor, dating-moderation); the helpers are the database's
-- own. The five re-created functions keep their grants.
BEGIN;
SET LOCAL lock_timeout = '5s';
REVOKE ALL ON FUNCTION private.is_dev_reference(text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.is_real_reference(text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_launch_gates(text[], public.country_safety_config) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.get_dating_launch_readiness(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_dating_launch_readiness(text) TO service_role;
REVOKE ALL ON FUNCTION public.moderation_launch_readiness(uuid, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.moderation_launch_readiness(uuid, text) TO service_role;
REVOKE ALL ON FUNCTION public.moderation_metrics(uuid, integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.moderation_metrics(uuid, integer) TO service_role;
REVOKE ALL ON FUNCTION public.moderation_fairness(uuid, integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.moderation_fairness(uuid, integer) TO service_role;
COMMIT;
````

- [ ] **Step 5: Build, apply twice, check the marked lines and the split push**

```bash
D=.superpowers/sdd/2026-11-23-spec2-w10
M=supabase/migrations/20261124100000_dating_v2_launch_guards.sql; G=supabase/migrations/20261124100010_dating_v2_launch_guards_grants.sql
python3 -I $D/build_mig.py
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f $M > /dev/null; echo "migration alone exit=$?"
psql -X -d attune_spec3a -Atc "select has_function_privilege('service_role','public.get_dating_launch_readiness(text)','EXECUTE'), has_function_privilege('service_role','public.moderation_metrics(uuid,integer)','EXECUTE'), has_function_privilege('service_role','public.publish_country_config(text,jsonb)','EXECUTE')"
for i in 1 2; do psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f $M -f $G > /dev/null; echo "exit=$?"; done
python3 -I $D/marked_diff.py $D/before_w10 attune_spec3a 'Spec 2 W10'
psql -X -d attune_spec3a -Atc "select has_function_privilege('service_role','public.get_dating_launch_readiness(text)','EXECUTE'), (public.get_dating_launch_readiness() ->> 'ready'), (public.get_dating_launch_readiness() ->> 'environment')"
```

Expected:

```text
supabase/migrations/20261124100000_dating_v2_launch_guards.sql: 5 re-created, 6 edit(s)
migration alone exit=0
f|f|t
exit=0
exit=0
private.country_config_checks(public.country_safety_config): 10 added line(s), 0 removed OK
private.guard_flag_production_gate(): 2 added line(s), 1 removed OK
public.production_flag_violations(): 1 added line(s), 1 removed OK
public.publish_country_config(text,jsonb): 12 added line(s), 0 removed OK
public.record_flag_gate_evidence(text,text): 4 added line(s), 0 removed OK
t|false|development
```

(The migration alone leaves the new functions to nobody and keeps the re-created ones' grants: a split push fails closed.)

- [ ] **Step 6: The other contracts, the canary and the grants harness**

Create `.superpowers/sdd/2026-11-23-spec2-w10/edit_tests_T1.py` with exactly:

````python
#!/usr/bin/env python3
# Spec 2 W10 Task 1: the canary's rows for the new functions; W3's photo
# reader pin learns that the launch gates name the flag
# dating_profile_photos (the table's own name; they read no photo); the
# country contract's production publishes read the launch gates green (they
# pin the publisher's own rules; dating_v2_launch_contracts.sql pins the
# gates).
import runpy
edit = runpy.run_path('.superpowers/sdd/2026-11-23-spec2-w10/anchor.py')['edit']
edit('supabase/tests/dating_rls_canary.sql', [
    ("""
-- ---------------------------------------------------------------------
-- Checks (every batch adds its rows above this line).
""", """-- Spec 2 W10: the launch readiness and the console's readiness and
-- dashboards are the service role's alone (the owner's SQL editor,
-- dating-moderation); the gates are the database's own.
INSERT INTO allowed_fn (sig, clients, service) VALUES
  ('get_dating_launch_readiness(text)', '', 'service_role'),
  ('private.dating_launch_gates(text[],country_safety_config)', '', ''),
  ('moderation_launch_readiness(uuid,text)', '', 'service_role'),
  ('moderation_metrics(uuid,integer)', '', 'service_role'),
  ('moderation_fairness(uuid,integer)', '', 'service_role');

-- ---------------------------------------------------------------------
-- Checks (every batch adds its rows above this line).
"""),
], 'T1 canary')
edit('supabase/tests/dating_v2_setup_contracts.sql', [
    ("""  -- Spec 2 W7b dating-moderation edge function, which signs them).
""", """  -- Spec 2 W7b dating-moderation edge function, which signs them).
  -- Spec 2 W10: the launch gates name the flag dating_profile_photos (the
  -- Spec 2 W10 table's own name); they read no photo (the database's own).
"""),
    ("""private.dating_has_data(uuid):; private.dating_next_step(uuid):;""",
     """private.dating_has_data(uuid):; private.dating_launch_gates(text[], country_safety_config):; private.dating_next_step(uuid):;"""),
], 'T1 photo readers')
edit('supabase/tests/country_safety_config_contracts.sql', [
    ("""BEGIN;
""", """BEGIN;
-- Spec 2 W10: in production, opening a place also needs the launch gates
-- green (dating_v2_launch_contracts.sql pins them). This file pins the
-- publisher's own rules, so here the gates read green (rolled back).
DO $$
BEGIN
  IF to_regprocedure('private.dating_launch_gates(text[],public.country_safety_config)') IS NOT NULL THEN
    CREATE OR REPLACE FUNCTION private.dating_launch_gates(p_countries text[], p_row public.country_safety_config DEFAULT NULL)
    RETURNS jsonb LANGUAGE sql STABLE AS 'SELECT ''[]''::jsonb';
  END IF;
END $$;
"""),
], 'T1 country contract')
````

```bash
D=.superpowers/sdd/2026-11-23-spec2-w10
python3 -I $D/edit_tests_T1.py
P=$(grep '^\\i ' scripts/local_pg_grants.sql | tail -1 | cut -c4-)
python3 -I $D/grants_line.py "$P" 'Spec 2 W10: the launch guards (twin of 20261124100000)' supabase/migrations/20261124100010_dating_v2_launch_guards_grants.sql
for f in dating_v2_launch_contracts dating_rls_canary country_safety_config_contracts dating_v2_setup_contracts; do
  if grep -q '^BEGIN;' supabase/tests/$f.sql; then psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/$f.sql > /dev/null 2>&1; else psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -c BEGIN -f supabase/tests/$f.sql -c ROLLBACK > /dev/null 2>&1; fi; echo "$f exit=$?"
done
```

Expected: `…dating_rls_canary.sql: 1 edit(s) (T1 canary)`, `…dating_v2_setup_contracts.sql: 2 edit(s) (T1 photo readers)`, `…country_safety_config_contracts.sql: 1 edit(s) (T1 country contract)`, `local_pg_grants.sql: one \i block added`; each of the four `exit=0`.

- [ ] **Step 7: The whole suite, and the mutants**

Create `.superpowers/sdd/2026-11-23-spec2-w10/mut_T1.py` with exactly:

````python
# Spec 2 W10 Task 1 mutants (mutate.py, against dating_v2_launch_contracts.sql;
# the twin runs after each migration mutant). Each must print a CONTRACT
# VIOLATED line (or the contract's own ERROR), never "NO ERROR".
MUTS = {
    # R-6: the environment gate always green.
    'env_gate_green': ("""'ok', private.attune_environment() = 'production'),""", """'ok', true),"""),
    'readiness_ignores_red': ("""                          WHERE (g ->> 'ok')::boolean IS NOT TRUE),
    'environment'""", """                          WHERE false),
    'environment'"""),
    # Provider mode.
    'sandbox_is_live': ("""private.dating_verification_mode() = 'live'),""", """private.dating_verification_mode() IN ('live', 'sandbox')),"""),
    # People.
    'inactive_owner_counts': ("""WHERE m.active AND m.role = 'safety_owner')),""", """WHERE m.role = 'safety_owner')),"""),
    'owner_is_moderator': ("""WHERE m.active AND m.role = 'moderator')),""", """WHERE m.active AND m.role IN ('moderator', 'safety_owner'))),"""),
    # Keys.
    'push_key_ignored': ("""      AND coalesce(public.app_setting('dating_push_key'), '') <> ''),""", """      ),"""),
    'field_key_ignored': ("""      AND coalesce((v_h ->> 'field_key_fingerprint_ok')::boolean, false)
""", "\n"),
    # DEV- references in the configs and the flags.
    'intro_dev_ok': ("""                                  AND private.is_real_reference(c.fairness_review_ref)""",
                     """                                  AND c.fairness_review_ref IS NOT NULL"""),
    'intro_none_ok': ("""      EXISTS (SELECT 1 FROM public.dating_algorithm_configs AS c WHERE c.state = 'active')
      AND NOT EXISTS""", """      NOT EXISTS"""),
    'chat_dev_ok': ("""WHERE c.state = 'active' AND NOT private.is_real_reference(c.review_ref))));""",
                    """WHERE c.state = 'active' AND c.review_ref IS NULL)));"""),
    'flag_evidence_dev_ok': ("""WHERE g.flag_key = f.key AND private.is_real_reference(g.review_ref))""",
                             """WHERE g.flag_key = f.key AND g.review_ref IS NOT NULL)"""),
    'flag_list_without_w9': ("""    'dating_couple_link', 'support_resources_v2', 'csam_hash_matching'];""",
                             """    'support_resources_v2', 'csam_hash_matching'];"""),
    'violations_ignored': ("""'gate', 'no_flag_violations', 'ok', cardinality(v_red) = 0,""", """'gate', 'no_flag_violations', 'ok', true,"""),
    'fake_age_ignored': ("""(v.age_vendor = 'fake' OR v.identity_vendor = 'fake')""", """v.identity_vendor = 'fake'"""),
    'kill_switch_ignored': ("""coalesce(pg_catalog.jsonb_array_length(v_h -> 'kill_switch_pending'), 1) = 0),""", """true),"""),
    'sla_ignored': ("""      coalesce(public.app_setting('moderation_alert_webhook'), '') <> ''));""", """      true));"""),
    # The countries.
    'resources_91_days_ok': ("""s.verified_at < current_date - 90))));""", """s.verified_at < current_date - 91))));"""),
    'resources_none_ok': ("""        AND EXISTS (SELECT 1 FROM public.support_resources AS s WHERE s.country_code = v_code AND s.active)
""", ""),
    'row_resources_ignored': ("""        coalesce(v_row.resources_verified_at >= now() - interval '90 days', false)
        AND EXISTS""", """        EXISTS"""),
    'checklist_ignored': ("""      pg_catalog.jsonb_build_object('gate', 'checklist:' || v_code, 'ok', cardinality(v_red) = 0,""",
                          """      pg_catalog.jsonb_build_object('gate', 'checklist:' || v_code, 'ok', true,"""),
    'p_row_ignored': ("""    v_row := CASE WHEN (p_row).country_code IS NOT DISTINCT FROM v_code THEN p_row
                  ELSE public.dating_country_config(v_code) END;""", """    v_row := public.dating_country_config(v_code);"""),
    'invalid_country_read': ("""  ELSIF v_code ~ '^[A-Z]{2}$' AND private.dating_iso_country(v_code) IS NOT NULL THEN""",
                             """  ELSIF true THEN"""),
    # The checklist's DEV- rule (country_config_checks).
    'checklist_dev_top_ok': ("""              WHERE (jsonb_typeof(e.value) = 'string' AND private.is_dev_reference(e.value #>> '{}')) -- Spec 2 W10""",
                             """              WHERE false -- Spec 2 W10"""),
    'checklist_dev_nested_ok': ("""                                    AND private.is_dev_reference(s.value #>> '{}')))) THEN -- Spec 2 W10""",
                                """                                    AND false))) THEN -- Spec 2 W10"""),
    'dev_rule_case_and_padding': ("""  SELECT coalesce(pg_catalog.upper(pg_catalog.btrim(p_ref, E' \\t\\r\\n')) LIKE 'DEV-%', false);""",
                                  """  SELECT coalesce(p_ref LIKE 'DEV-%', false);"""),
    # Opening a place in production.
    'opening_unguarded': ("""  IF private.attune_environment() = 'production' AND v_new.dating_enabled -- Spec 2 W10""",
                          """  IF false AND v_new.dating_enabled -- Spec 2 W10"""),
    'region_opening_unguarded': ("""     AND NOT coalesce(v_open_new <@ v_open_old, false) THEN -- Spec 2 W10""",
                                 """     AND v_old.dating_enabled IS NOT TRUE THEN -- Spec 2 W10"""),
    'reduction_refused': ("""     AND NOT coalesce(v_open_new <@ v_open_old, false) THEN -- Spec 2 W10""", """     THEN -- Spec 2 W10"""),
    'opening_reads_current_row': ("""private.dating_launch_gates(ARRAY[v_code], v_new)""", """private.dating_launch_gates(ARRAY[v_code])"""),
    # The flags (Spec 1's gate).
    'flag_guard_dev_ok': ("""                    AND (g.review_ref IS NULL OR private.is_dev_reference(g.review_ref))) THEN -- Spec 2 W10: a DEV- reference is none""",
                          """                    AND g.review_ref IS NULL) THEN -- Spec 2 W10: a DEV- reference is none"""),
    'record_dev_ok': ("""  IF private.attune_environment() = 'production' AND private.is_dev_reference(p_review_ref) THEN -- Spec 2 W10""",
                      """  IF false THEN -- Spec 2 W10"""),
    'record_dev_refused_everywhere': ("""  IF private.attune_environment() = 'production' AND private.is_dev_reference(p_review_ref) THEN -- Spec 2 W10""",
                                      """  IF private.is_dev_reference(p_review_ref) THEN -- Spec 2 W10"""),
    'violations_dev_ok': ("""   WHERE f.enabled AND (g.review_ref IS NULL OR private.is_dev_reference(g.review_ref)) -- Spec 2 W10""",
                          """   WHERE f.enabled AND g.review_ref IS NULL -- Spec 2 W10"""),
    # The console's reads.
    'readiness_for_moderators': ('LIVE', ('public.moderation_launch_readiness(uuid,text)', [
        ("""  IF v_mod.role <> 'safety_owner' THEN""", """  IF false THEN""")])),
    'metrics_for_moderators': ('LIVE', ('public.moderation_metrics(uuid,integer)', [
        ("""  IF v_mod.role <> 'safety_owner' THEN""", """  IF false THEN""")])),
    'fairness_for_moderators': ('LIVE', ('public.moderation_fairness(uuid,integer)', [
        ("""  IF v_mod.role <> 'safety_owner' THEN""", """  IF false THEN""")])),
    'fairness_refusal_uncounted': ('LIVE', ('public.moderation_fairness(uuid,integer)', [
        ("""    PERFORM private.bump_metric_internal('dating.moderation.not_moderator');
""", "")])),
    'metrics_at_49': ("""ORDER BY x.key) FILTER (WHERE x.n >= 50), '[]'::jsonb),""", """ORDER BY x.key) FILTER (WHERE x.n >= 49), '[]'::jsonb),"""),
    'metrics_every_key': ("""AND left(c.key, 7) = 'dating.'""", ""),
    'metrics_window_8_days': ("""  v_from := v_to - (p_days - 1);""", """  v_from := v_to - p_days;"""),
    'metrics_any_window': ("""  IF p_days IS NULL OR p_days NOT IN (7, 28, 90) THEN""", """  IF p_days IS NULL THEN"""),
    'fairness_all_weeks': ("""       WHERE r.week > current_date - 7 * p_weeks), '[]'::jsonb));""", """       ), '[]'::jsonb));"""),
    'fairness_flagged_not_first': ("""ORDER BY r.flagged DESC, r.week DESC, r.country_code, r.cohort_key)""",
                                   """ORDER BY r.week DESC, r.country_code, r.cohort_key)"""),
}
````

```bash
D=.superpowers/sdd/2026-11-23-spec2-w10
bash $D/suite.sh attune_spec3a > $D/sql-T1.txt
echo "$(grep -c '^PASS' $D/sql-T1.txt) PASS $(grep -c '^FAIL' $D/sql-T1.txt) FAIL"
comm -13 <(grep FAIL $D/sql-baseline.txt | sort) <(grep FAIL $D/sql-T1.txt | sort)
M=supabase/migrations/20261124100000_dating_v2_launch_guards.sql; C=supabase/tests/dating_v2_launch_contracts.sql; G=supabase/migrations/20261124100010_dating_v2_launch_guards_grants.sql
W10_DB=attune_spec3a python3 -I $D/mutate.py $M $C $D/mut_T1.py $D/mut $G > $D/mut_T1.txt 2>&1
grep -c 'CONTRACT VIOLATED' $D/mut_T1.txt; grep -vc 'CONTRACT VIOLATED' $D/mut_T1.txt
psql -X -d attune_spec3a -Atc "select count(*) || ' rows, ' || count(*) filter (where enabled) || ' on' from public.feature_flags"
```

Expected: `164 PASS 14 FAIL` (by day, at `cbf7b30b` + W10; after W9, the baseline's PASS + 1); no new FAIL line; `43`; `0`; the flags exactly as in the baseline (`45 rows, 6 on` at `cbf7b30b`; W9 adds `dating_couple_link`, off).

- [ ] **Step 8: Record the tree (do not commit).**

### Task 2: `dating-moderation`: readiness, metrics, fairness, and `config:launch_not_ready` (§6.4; R-86, R-89)

**Files:**
- Create: `$D/{edit_edge_T2.py, mut_T2.py}`
- Modify: `supabase/functions/dating-moderation/handler.ts`, `supabase/functions/dating-moderation/handler.test.ts`
- Test: `handler.test.ts` (two W10 tests; the config-codes test gains the new code)

**Interfaces:**
- Consumes: `moderation_launch_readiness(p_actor, p_country)`, `moderation_metrics(p_actor, p_days)`, `moderation_fairness(p_actor, p_weeks)` (Task 1).
- Produces: actions `readiness`, `metrics`, `fairness` for Task 3; `config:launch_not_ready` passes through.

- [ ] **Step 1: The edits and the tests (one script)**

Create `.superpowers/sdd/2026-11-23-spec2-w10/edit_edge_T2.py` with exactly:

````python
#!/usr/bin/env python3
# Spec 2 W10 Task 2: dating-moderation gains the launch readiness, the
# metrics and the fairness reports (one function each, the safety owner's
# by the database's rule) and passes config:launch_not_ready through (its
# red gates never leave: the console reads them from readiness).
import runpy
edit = runpy.run_path('.superpowers/sdd/2026-11-23-spec2-w10/anchor.py')['edit']
H = 'supabase/functions/dating-moderation/handler.ts'
edit(H, [
    ("""  "config:production_checks_failed",
""", """  "config:production_checks_failed",
  // Spec 2 W10 (§8 W10): opening a place in production needs the launch
  // gates green; which are red is read from readiness, never from here.
  "config:launch_not_ready",
"""),
    ("""const DAY = /^\\d{4}-\\d{2}-\\d{2}$/;
""", """const DAY = /^\\d{4}-\\d{2}-\\d{2}$/;
/// Spec 2 W10 (§6.9): the metrics' windows, in days.
export const METRIC_DAYS: ReadonlySet<number> = new Set([7, 28, 90]);
"""),
    ("""  csam_holds: { fn: "moderation_csam_holds", args: () => ({}) },
""", """  csam_holds: { fn: "moderation_csam_holds", args: () => ({}) },
  // Spec 2 W10 (§8 W10, §6.9, §5.9): the launch readiness (Ghana and the
  // UK, or one country), the dating.* counters at n >= 50 over 7, 28 or 90
  // days, and the fairness reports of the last 1-12 weeks. The safety
  // owner's (the database refuses anyone else: safety_owner_only).
  readiness: {
    fn: "moderation_launch_readiness",
    args: (b) =>
      b.country === undefined || b.country === null
        ? { p_country: null }
        : typeof b.country === "string" && /^[A-Z]{2}$/.test(b.country)
        ? { p_country: b.country }
        : null,
  },
  metrics: {
    fn: "moderation_metrics",
    args: (b) => (typeof b.days === "number" && METRIC_DAYS.has(b.days) ? { p_days: b.days } : null),
  },
  fairness: {
    fn: "moderation_fairness",
    args: (b) => ({ p_weeks: limit(b.weeks, 4, 12) }),
  },
"""),
], 'T2 handler')
T = 'supabase/functions/dating-moderation/handler.test.ts'
edit(T, [
    ("""    "config:checklist_keys_removed", "config:invalid_regions", "config:no_calling_code", "config:production_checks_failed",
  ]) {""", """    "config:checklist_keys_removed", "config:invalid_regions", "config:no_calling_code", "config:production_checks_failed",
    "config:launch_not_ready", // Spec 2 W10
  ]) {"""),
], "T2 handler tests")
with open(T, 'a') as f:
    f.write('''
Deno.test("W10: readiness, metrics and fairness are one function each, bad input before any call", async () => {
  eq(ACTIONS.readiness?.fn, "moderation_launch_readiness");
  eq(ACTIONS.metrics?.fn, "moderation_metrics");
  eq(ACTIONS.fairness?.fn, "moderation_fairness");
  const seen = fresh();
  const ok = deps({ ok: true }, seen);
  await handleModeration({ action: "readiness" }, MOD, ok);
  await handleModeration({ action: "readiness", country: "GH", p_actor: "someone-else" }, MOD, ok);
  await handleModeration({ action: "metrics", days: 28 }, MOD, ok);
  await handleModeration({ action: "fairness" }, MOD, ok);
  await handleModeration({ action: "fairness", weeks: 12 }, MOD, ok);
  eq(seen.rpc, [
    ["moderation_launch_readiness", { p_country: null, p_actor: ME }],
    ["moderation_launch_readiness", { p_country: "GH", p_actor: ME }],
    ["moderation_metrics", { p_days: 28, p_actor: ME }],
    ["moderation_fairness", { p_weeks: 4, p_actor: ME }],
    ["moderation_fairness", { p_weeks: 12, p_actor: ME }],
  ]);
  const none = fresh();
  for (const body of [
    { action: "readiness", country: "gh" },
    { action: "readiness", country: "GHA" },
    { action: "readiness", country: 233 },
    { action: "metrics" },
    { action: "metrics", days: 30 },
    { action: "metrics", days: "7" },
  ]) {
    eq(await handleModeration(body, MOD, deps({ ok: true }, none)), { ok: false, reason: "invalid" }, JSON.stringify(body));
  }
  eq(none.rpc.length, 0);
  // An out-of-range week count reads the default window, as the lists' limits do.
  const weeks = fresh();
  await handleModeration({ action: "fairness", weeks: 13 }, MOD, deps({ ok: true }, weeks));
  eq(weeks.rpc, [["moderation_fairness", { p_weeks: 4, p_actor: ME }]]);
});

Deno.test("W10: the answers pass through; a moderator's refusal is safety_owner_only; no aal2, no call", async () => {
  const ready = { ok: true, ready: false, environment: "development", countries: ["GH", "GB"], open: [],
    gates: [{ gate: "environment", ok: false }, { gate: "flag_evidence", ok: false, detail: ["dating_couple_link"] }] };
  eq(await handleModeration({ action: "readiness" }, MOD, deps(ready, fresh())), ready);
  const metrics = { ok: true, days: 7, from: "2026-11-17", to: "2026-11-23", min_count: 50,
    metrics: [{ key: "dating.mutual", count: 50 }], suppressed: 3 };
  eq(await handleModeration({ action: "metrics", days: 7 }, MOD, deps(metrics, fresh())), metrics);
  for (const body of [{ action: "readiness" }, { action: "metrics", days: 7 }, { action: "fairness" }]) {
    eq(await handleModeration(body, MOD, deps({ ok: false, reason: "safety_owner_only" }, fresh())),
      { ok: false, reason: "safety_owner_only" }, body.action);
    const seen = fresh();
    eq(await handleModeration(body, { userId: ME, aal: "aal1" }, deps({ ok: true }, seen)),
      { ok: false, reason: "mfa_required" }, body.action);
    eq(seen.rpc.length, 0);
  }
  // A publish refused for the launch gates passes only its code.
  eq(await handleModeration({ action: "publish_country", country: "GH", values: { dating_enabled: true } }, MOD,
    deps({ ok: false, reason: "config:launch_not_ready", gates: ["age_assurance_live"] }, fresh())),
    { ok: false, reason: "config:launch_not_ready" });
});
''')
print(f'{T}: 2 tests appended (T2)')
````

- [ ] **Step 2: Run the tests before the handler change, to see them fail**

```bash
D=.superpowers/sdd/2026-11-23-spec2-w10
cp supabase/functions/dating-moderation/handler.ts /tmp/w10_handler_before.ts
python3 -I $D/edit_edge_T2.py
cp supabase/functions/dating-moderation/handler.ts /tmp/w10_handler_after.ts
cp /tmp/w10_handler_before.ts supabase/functions/dating-moderation/handler.ts
(cd supabase/functions && deno test --allow-read --allow-env --lock=../../.github/deno-w9.lock --frozen dating-moderation/handler.test.ts 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -E '^(ok|FAILED) \|')
cp /tmp/w10_handler_after.ts supabase/functions/dating-moderation/handler.ts; rm -f /tmp/w10_handler_before.ts /tmp/w10_handler_after.ts
```

Expected: `…handler.ts: 3 edit(s) (T2 handler)`, `…handler.test.ts: 1 edit(s) (T2 handler tests)`, `…handler.test.ts: 2 tests appended (T2)`; then `FAILED | 27 passed | 3 failed` (the two W10 tests and the config-codes test, against the old handler).

- [ ] **Step 3: Run them with the change, the CI line, and the mutants**

Create `.superpowers/sdd/2026-11-23-spec2-w10/mut_T2.py` with exactly:

````python
# Spec 2 W10 Task 2 Deno mutants (denomut.py): each must be KILLED.
H = 'supabase/functions/dating-moderation/handler.ts'
TESTS = ['dating-moderation/handler.test.ts']
MUTS = {
    'launch_code_busy': (H, [('''  "config:launch_not_ready",
''', '')]),
    'readiness_any_country': (H, [('''        : typeof b.country === "string" && /^[A-Z]{2}$/.test(b.country)
        ? { p_country: b.country }''', '''        : typeof b.country === "string"
        ? { p_country: b.country }''')]),
    'readiness_null_dropped': (H, [('''      b.country === undefined || b.country === null
        ? { p_country: null }''', '''      b.country === undefined || b.country === null
        ? {}''')]),
    'metrics_any_days': (H, [('''typeof b.days === "number" && METRIC_DAYS.has(b.days) ? { p_days: b.days } : null''',
                             '''typeof b.days === "number" ? { p_days: b.days } : null''')]),
    'metrics_string_days': (H, [('''typeof b.days === "number" && METRIC_DAYS.has(b.days) ? { p_days: b.days } : null''',
                                '''METRIC_DAYS.has(Number(b.days)) ? { p_days: Number(b.days) } : null''')]),
    'fairness_unbounded': (H, [('''args: (b) => ({ p_weeks: limit(b.weeks, 4, 12) }),''', '''args: (b) => ({ p_weeks: limit(b.weeks, 4, 52) }),''')]),
    'fairness_wrong_fn': (H, [('''    fn: "moderation_fairness",''', '''    fn: "moderation_metrics",''')]),
}
````

```bash
D=.superpowers/sdd/2026-11-23-spec2-w10
(cd supabase/functions && deno test --allow-read --allow-env --lock=../../.github/deno-w9.lock --frozen dating-moderation/handler.test.ts 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -E '^(ok|FAILED) \|')
(cd supabase/functions && eval "$(grep -m1 -oE 'deno test --allow-read [^"]*' ../../.github/workflows/tests.yml)" 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -E '^(ok|FAILED) \|' | tail -1)
(cd supabase/functions && eval "$(grep -m1 -oE 'deno check --lock[^"]*' ../../.github/workflows/tests.yml)" > /dev/null 2>&1; echo "check exit=$?")
python3 -I $D/denomut.py $D/mut_T2.py | tail -1
```

Expected: `ok | 30 passed | 0 failed`; `ok | 281 passed | 0 failed` (279 + 2 at `cbf7b30b`; plus W9's); `check exit=0`; `7/7 killed`.

- [ ] **Step 4: Record the tree (do not commit).**

### Task 3: The console's Launch readiness, Metrics and Fairness pages (§6.4, §6.9, §5.9; R-89)

**Files:**
- Create: `lib/console/screens/launch_screens.dart`, `test/console/console_launch_test.dart`, `$D/{edit_console_T3.py, mut_T3_dart.py}`
- Modify: `lib/console/console_app.dart` (header lines, one import, one `consoleReason` line, three `ConsolePage` values after `audit`, three `_body` cases)
- Test: `test/console/console_launch_test.dart` (9 tests); all of `test/console`

**Interfaces:**
- Consumes: Task 2's actions; `ConsoleFrame(title, onRefresh, child)`, `ConsoleLoading(text)`, `ConsoleRetry(answer, onRetry)`, `ConsoleStatus(line, textKey)`, `ConsoleLine(text)`, `ConsoleMe.owner`, `ConsoleAnswer.list(key)`.
- Produces: the console interfaces above.

- [ ] **Step 1: Write the test**

Create `test/console/console_launch_test.dart` with exactly:

````dart
// Spec 2 W10 (§8 W10, §6.4, §6.9, §5.9): the console's launch pages.
// Launch readiness lists every gate in words (Green or Red, never colour
// alone) with what is red, and says why development is never ready;
// Metrics reads 7, 28 or 90 days and names only counters of 50 or more;
// Fairness reads 4 or 12 weeks, flagged cohorts first and marked; a
// moderator's console asks nothing on these pages; a failed read offers
// Try again; a publish refused for the launch gates says to read Launch
// readiness.
import 'package:attune/console/console_api.dart';
import 'package:attune/console/screens/launch_screens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'console_fakes.dart';

const _ready = ConsoleAnswer(
  ok: true,
  data: {
    'ok': true,
    'ready': false,
    'environment': 'development',
    'countries': ['GH', 'GB'],
    'open': <String>[],
    'gates': [
      {'gate': 'environment', 'ok': false},
      {'gate': 'age_assurance_live', 'ok': true},
      {
        'gate': 'flag_evidence',
        'ok': false,
        'detail': ['dating_couple_link', 'csam_hash_matching'],
      },
      {'gate': 'no_test_verifications', 'ok': false, 'detail': 3},
      {'gate': 'checklist:GH', 'ok': true, 'detail': <String>[]},
      {'gate': 'resources:GB', 'ok': false},
      {'gate': 'w11_something_new', 'ok': true},
    ],
  },
);

const _metrics = ConsoleAnswer(
  ok: true,
  data: {
    'ok': true,
    'days': 7,
    'from': '2026-11-17',
    'to': '2026-11-23',
    'min_count': 50,
    'metrics': [
      {'key': 'dating.activated', 'count': 75},
      {'key': 'dating.mutual', 'count': 50},
    ],
    'suppressed': 4,
  },
);

const _fairness = ConsoleAnswer(
  ok: true,
  data: {
    'ok': true,
    'weeks': 4,
    'flagged': 1,
    'reports': [
      {
        'week': '2026-11-16',
        'country': 'GH',
        'cohort': 'region:AA',
        'active': '100–499',
        'introductions_per_active': 1.4,
        'mutual_rate': 0.09,
        'flagged': true,
      },
      {
        'week': '2026-11-16',
        'country': 'GB',
        'cohort': 'age:25_34',
        'active': '50–99',
        'introductions_per_active': 2.0,
        'mutual_rate': null,
        'flagged': false,
      },
    ],
  },
);

Future<void> _open(WidgetTester t, String page) async {
  await t.ensureVisible(find.text(page));
  await t.pumpAndSettle();
  await t.tap(find.text(page));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('Launch readiness lists every gate in words, with what is red', (
    t,
  ) async {
    final api = await pumpHome(
      t,
      me: consoleOwner,
      answers: {'readiness': _ready},
    );
    await _open(t, 'Launch readiness');
    expect(api.of('readiness'), [<String, Object?>{}]);
    expect(
      find.text(
        'Not ready: 4 of 7 gates are red. This project reads development, '
        'so it is never ready here.',
      ),
      findsOneWidget,
    );
    expect(
      find.text('Production mode is set (only the owner sets it)'),
      findsOneWidget,
    );
    expect(find.text('Red: dating_couple_link, csam_hash_matching'), findsOne);
    expect(find.text('Red: 3'), findsOneWidget);
    expect(
      find.text('GH: the legal checklist is complete with real references'),
      findsOneWidget,
    );
    expect(
      find.text('GB: support resources verified within 90 days'),
      findsOneWidget,
    );
    // A gate the console doesn't know yet reads as its key.
    expect(find.text('w11_something_new'), findsOneWidget);
    expect(find.text('Green'), findsNWidgets(3));
    // Read again reads again.
    await t.tap(find.byKey(const ValueKey('console_refresh')));
    await t.pumpAndSettle();
    expect(api.of('readiness'), hasLength(2));
  });

  testWidgets('every gate green reads ready', (t) async {
    await pumpHome(
      t,
      me: consoleOwner,
      answers: {
        'readiness': const ConsoleAnswer(
          ok: true,
          data: {
            'ok': true,
            'ready': true,
            'environment': 'production',
            'gates': [
              {'gate': 'environment', 'ok': true},
            ],
          },
        ),
      },
    );
    await _open(t, 'Launch readiness');
    expect(
      find.text('Every gate is green. Dating may be switched on.'),
      findsOneWidget,
    );
  });

  testWidgets("the server's ready decides, never the console's count", (
    t,
  ) async {
    await pumpHome(
      t,
      me: consoleOwner,
      answers: {
        'readiness': const ConsoleAnswer(
          ok: true,
          data: {
            'ok': true,
            'ready': false,
            'environment': 'production',
            'gates': [
              {'gate': 'environment', 'ok': true},
            ],
          },
        ),
      },
    );
    await _open(t, 'Launch readiness');
    expect(find.text('Not ready: 0 of 1 gates are red.'), findsOneWidget);
  });

  testWidgets('Metrics names only counters of 50 or more, by window', (
    t,
  ) async {
    final api = await pumpHome(
      t,
      me: consoleOwner,
      answers: {'metrics': _metrics},
    );
    await _open(t, 'Metrics');
    expect(api.of('metrics'), [
      {'days': 7},
    ]);
    expect(
      find.text(
        '17 Nov 2026 to 23 Nov 2026 (UTC). Counters under 50 are not '
        'shown: 4.',
      ),
      findsOneWidget,
    );
    expect(find.text('dating.activated'), findsOneWidget);
    expect(find.text('75'), findsOneWidget);
    await t.tap(find.text('28 days'));
    await t.pumpAndSettle();
    expect(api.of('metrics').last, {'days': 28});
    await t.tap(find.text('90 days'));
    await t.pumpAndSettle();
    expect(api.of('metrics').last, {'days': 90});
  });

  testWidgets('Metrics with nothing at 50 says so', (t) async {
    await pumpHome(
      t,
      me: consoleOwner,
      answers: {
        'metrics': const ConsoleAnswer(
          ok: true,
          data: {'ok': true, 'metrics': <Object>[], 'suppressed': 9},
        ),
      },
    );
    await _open(t, 'Metrics');
    expect(find.text('No counter reached 50 in this window.'), findsOneWidget);
  });

  testWidgets('Fairness: flagged cohorts first and marked, by window', (
    t,
  ) async {
    final api = await pumpHome(
      t,
      me: consoleOwner,
      answers: {'fairness': _fairness},
    );
    await _open(t, 'Fairness');
    expect(api.of('fairness'), [
      {'weeks': 4},
    ]);
    expect(
      find.text('Flagged · GH · region:AA · week of 16 Nov 2026'),
      findsOneWidget,
    );
    expect(
      find.text(
        '2.0 introductions per active person · mutual rate - · 50–99 active',
      ),
      findsOneWidget,
    );
    final first = t.getTopLeft(
      find.byKey(const ValueKey('console_fairness_0')),
    );
    final second = t.getTopLeft(
      find.byKey(const ValueKey('console_fairness_1')),
    );
    expect(first.dy, lessThan(second.dy));
    await t.tap(find.text('12 weeks'));
    await t.pumpAndSettle();
    expect(api.of('fairness').last, {'weeks': 12});
  });

  testWidgets("a moderator's console asks nothing on the launch pages", (
    t,
  ) async {
    final api = await pumpHome(t);
    for (final page in ['Launch readiness', 'Metrics', 'Fairness']) {
      await _open(t, page);
      expect(find.text(kConsoleLaunchOwnerOnly), findsOneWidget, reason: page);
    }
    expect(api.of('readiness'), isEmpty);
    expect(api.of('metrics'), isEmpty);
    expect(api.of('fairness'), isEmpty);
  });

  testWidgets('a failed read offers Try again, and a refusal reads as its '
      'line', (t) async {
    final api = await pumpHome(
      t,
      me: consoleOwner,
      answers: {
        'readiness': ConsoleAnswer.busy,
        'metrics': const ConsoleAnswer(ok: false, reason: 'safety_owner_only'),
      },
    );
    await _open(t, 'Launch readiness');
    expect(
      find.text('The server is busy. Try again in a moment.'),
      findsOneWidget,
    );
    await t.tap(find.byKey(const ValueKey('console_retry')));
    await t.pumpAndSettle();
    expect(api.of('readiness'), hasLength(2));
    await _open(t, 'Metrics');
    expect(find.text('Only the safety owner can do this.'), findsOneWidget);
  });

  testWidgets('a publish refused for the launch gates says to read Launch '
      'readiness', (t) async {
    await pumpHome(
      t,
      me: consoleOwner,
      answers: {
        'countries': const ConsoleAnswer(
          ok: true,
          data: {'ok': true, 'countries': <Object>[]},
        ),
        'publish_country': const ConsoleAnswer(
          ok: false,
          reason: 'config:launch_not_ready',
        ),
      },
    );
    await _open(t, 'Countries');
    await t.enterText(find.byKey(const ValueKey('console_country_code')), 'GH');
    await t.enterText(
      find.byKey(const ValueKey('console_country_values')),
      '{"dating_enabled": true}',
    );
    await t.tap(find.byKey(const ValueKey('console_publish')));
    await t.pumpAndSettle();
    await tapConfirm(t);
    expect(
      find.text(
        'This would open Dating somewhere while a launch gate is red, so '
        'nothing was published. Launch readiness shows which.',
      ),
      findsOneWidget,
    );
  });
}
````

- [ ] **Step 2: Run it to see it fail**

```bash
flutter test --no-pub test/console/console_launch_test.dart 2>&1 | grep -m1 -oE "Error: Couldn't resolve the package 'attune' in 'package:attune/console/screens/launch_screens.dart'|Error when reading '[^']*launch_screens.dart'"
```

Expected: `Error when reading 'lib/console/screens/launch_screens.dart'` (the file doesn't exist yet).

- [ ] **Step 3: The pages and the shell's lines**

Create `lib/console/screens/launch_screens.dart` with exactly:

````dart
// Spec 2 W10 (§8 W10, §6.4, §6.9, §5.9): the safety owner's launch pages.
// Launch readiness lists every gate of get_dating_launch_readiness() with
// its state in words (never colour alone) and what is red; it is never
// green while the project reads development (R-6). Metrics shows the
// dating.* counters at n >= 50 over 7, 28 or 90 days (smaller ones are
// counted, never named). Fairness shows the weekly reports, flagged
// cohorts first; a flag goes to a person and nothing re-weights by itself.
// A moderator's console asks nothing here: the pages say they are the
// safety owner's.
import 'package:attune/console/console_api.dart';
import 'package:attune/console/console_app.dart';
import 'package:flutter/material.dart';

const kConsoleLaunchOwnerOnly =
    "The launch pages are the safety owner's. Ask the safety owner.";

/// A gate's name in words; an unknown gate reads as its key.
String consoleGateLabel(String gate) {
  final country = gate.contains(':') ? gate.split(':').last : '';
  return switch (gate) {
    'environment' => 'Production mode is set (only the owner sets it)',
    'age_assurance_live' => 'Age assurance runs live (not fake or sandbox)',
    'safety_owner' => 'An active safety owner',
    'moderator' => 'An active moderator',
    'keys' => 'The Dating keys are set and match their fingerprints',
    'introductions_config' =>
      'The introductions config is active with real review references',
    'chat_config' =>
      'The chat safety config is active with a real review reference',
    'flag_evidence' => 'Every launch flag has real gate evidence',
    'no_flag_violations' => 'No gated flag is on without real evidence',
    'no_test_verifications' => 'No pass from the fake providers still stands',
    'kill_switch_clear' => 'No same-gender switch-off is pending',
    'log_settings_safe' => 'The database logs keep no request values',
    'sla_alerts' => 'The SLA alerts have somewhere to go',
    final g when g.startsWith('checklist:') =>
      '$country: the legal checklist is complete with real references',
    final g when g.startsWith('resources:') =>
      '$country: support resources verified within 90 days',
    _ => gate,
  };
}

/// What a gate's detail says: the red flags or checks, or a count.
String consoleGateDetail(Object? detail) => switch (detail) {
  final List<Object?> l when l.isNotEmpty => l.join(', '),
  final int n when n > 0 => '$n',
  _ => '',
};

/// The readiness answer's first line.
String consoleReadinessLine(ConsoleAnswer r) {
  final gates = r.list('gates');
  final red = gates.where((g) => g['ok'] != true).length;
  if (r.data['ready'] == true) {
    return 'Every gate is green. Dating may be switched on.';
  }
  return [
    'Not ready: $red of ${gates.length} gates are red.',
    if (r.data['environment'] == 'development')
      'This project reads development, so it is never ready here.',
  ].join(' ');
}

/// One read, again on demand or when its window changes.
abstract class _LaunchState<T extends StatefulWidget> extends State<T> {
  ConsoleAnswer? read;
  ConsoleAnswer? good;

  ConsoleApi get api;
  ConsoleMe get me;
  String get action;
  String get title;
  String get loading;
  Map<String, Object?> get params => const {};

  @override
  void initState() {
    super.initState();
    if (me.owner) load();
  }

  Future<void> load() async {
    final r = await api(action, params);
    if (!mounted) return;
    setState(() {
      read = r;
      if (r.ok) good = r;
    });
  }

  Widget page(List<Widget> Function(ConsoleAnswer read) rows) {
    if (!me.owner) {
      return ConsoleFrame(
        title: title,
        onRefresh: null,
        child: const Padding(
          padding: EdgeInsets.all(16),
          child: Text(kConsoleLaunchOwnerOnly),
        ),
      );
    }
    final r = read;
    final kept = good;
    return ConsoleFrame(
      title: title,
      onRefresh: r == null ? null : load,
      child: switch (r) {
        null => ConsoleLoading(loading),
        ConsoleAnswer(ok: false) when kept == null => Align(
          alignment: Alignment.topLeft,
          child: ConsoleRetry(
            answer: r,
            onRetry: () {
              setState(() => read = null);
              load();
            },
          ),
        ),
        _ => SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!r.ok) ConsoleRetry(answer: r, onRetry: load),
              ...rows(r.ok ? r : kept!),
            ],
          ),
        ),
      },
    );
  }
}

class ReadinessScreen extends StatefulWidget {
  const ReadinessScreen({super.key, required this.api, required this.me});

  final ConsoleApi api;
  final ConsoleMe me;

  @override
  State<ReadinessScreen> createState() => _ReadinessScreenState();
}

class _ReadinessScreenState extends _LaunchState<ReadinessScreen> {
  @override
  ConsoleApi get api => widget.api;

  @override
  ConsoleMe get me => widget.me;

  @override
  String get action => 'readiness';

  @override
  String get title => 'Launch readiness (Ghana and the UK)';

  @override
  String get loading => 'Loading the launch gates.';

  @override
  Widget build(BuildContext context) => page(
    (r) => [
      ConsoleStatus(
        ConsoleLine(consoleReadinessLine(r)),
        textKey: const ValueKey('console_readiness_line'),
      ),
      const SizedBox(height: 8),
      for (final g in r.list('gates'))
        _GateTile(
          gate: '${g['gate']}',
          ok: g['ok'] == true,
          detail: consoleGateDetail(g['detail']),
        ),
    ],
  );
}

class _GateTile extends StatelessWidget {
  const _GateTile({required this.gate, required this.ok, required this.detail});

  final String gate;
  final bool ok;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final state = ok ? 'Green' : 'Red';
    return MergeSemantics(
      child: ListTile(
        key: ValueKey('console_gate_$gate'),
        dense: true,
        leading: ExcludeSemantics(
          child: Icon(
            ok ? Icons.check_circle_outline : Icons.cancel_outlined,
            color: ok ? scheme.primary : scheme.error,
          ),
        ),
        title: Text(consoleGateLabel(gate)),
        subtitle: Text(detail.isEmpty ? state : '$state: $detail'),
      ),
    );
  }
}

class MetricsScreen extends StatefulWidget {
  const MetricsScreen({super.key, required this.api, required this.me});

  final ConsoleApi api;
  final ConsoleMe me;

  @override
  State<MetricsScreen> createState() => _MetricsScreenState();
}

class _MetricsScreenState extends _LaunchState<MetricsScreen> {
  int _days = 7;

  @override
  ConsoleApi get api => widget.api;

  @override
  ConsoleMe get me => widget.me;

  @override
  String get action => 'metrics';

  @override
  String get title => 'Metrics (counts of 50 or more)';

  @override
  String get loading => 'Loading the metrics.';

  @override
  Map<String, Object?> get params => {'days': _days};

  @override
  Widget build(BuildContext context) => page(
    (r) => [
      Align(
        alignment: Alignment.centerLeft,
        child: SegmentedButton<int>(
          key: const ValueKey('console_metrics_days'),
          segments: const [
            ButtonSegment(value: 7, label: Text('7 days')),
            ButtonSegment(value: 28, label: Text('28 days')),
            ButtonSegment(value: 90, label: Text('90 days')),
          ],
          selected: {_days},
          onSelectionChanged: (s) {
            setState(() => _days = s.first);
            load();
          },
        ),
      ),
      const SizedBox(height: 8),
      Text(
        '${consoleDay(r.data['from'])} to ${consoleDay(r.data['to'])} (UTC). '
        'Counters under ${r.data['min_count'] ?? 50} are not shown: '
        '${r.data['suppressed'] ?? 0}.',
      ),
      if (r.list('metrics').isEmpty)
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text('No counter reached 50 in this window.'),
        ),
      for (final m in r.list('metrics'))
        ListTile(
          key: ValueKey('console_metric_${m['key']}'),
          dense: true,
          title: Text('${m['key']}'),
          trailing: Text('${m['count']}'),
        ),
    ],
  );
}

/// A day the server sent ("2026-11-17" → "17 Nov 2026"); '-' if none.
String consoleDay(Object? day) {
  final d = day is String ? DateTime.tryParse(day) : null;
  if (d == null) return '-';
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${d.day} ${months[d.month - 1]} ${d.year}';
}

class FairnessScreen extends StatefulWidget {
  const FairnessScreen({super.key, required this.api, required this.me});

  final ConsoleApi api;
  final ConsoleMe me;

  @override
  State<FairnessScreen> createState() => _FairnessScreenState();
}

class _FairnessScreenState extends _LaunchState<FairnessScreen> {
  int _weeks = 4;

  @override
  ConsoleApi get api => widget.api;

  @override
  ConsoleMe get me => widget.me;

  @override
  String get action => 'fairness';

  @override
  String get title => 'Fairness (weekly, cohorts of 50 or more)';

  @override
  String get loading => 'Loading the fairness reports.';

  @override
  Map<String, Object?> get params => {'weeks': _weeks};

  @override
  Widget build(BuildContext context) => page(
    (r) => [
      Align(
        alignment: Alignment.centerLeft,
        child: SegmentedButton<int>(
          key: const ValueKey('console_fairness_weeks'),
          segments: const [
            ButtonSegment(value: 4, label: Text('4 weeks')),
            ButtonSegment(value: 12, label: Text('12 weeks')),
          ],
          selected: {_weeks},
          onSelectionChanged: (s) {
            setState(() => _weeks = s.first);
            load();
          },
        ),
      ),
      const SizedBox(height: 8),
      Text(
        '${r.data['flagged'] ?? 0} flagged. A flag is for you to review; '
        'nothing re-weights by itself. A change is a new config version '
        'with a fairness review reference.',
      ),
      if (r.list('reports').isEmpty)
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text('No fairness report in this window yet.'),
        ),
      for (final (i, f) in r.list('reports').indexed)
        ListTile(
          key: ValueKey('console_fairness_$i'),
          dense: true,
          title: Text(
            '${f['flagged'] == true ? 'Flagged · ' : ''}'
            '${f['country']} · ${f['cohort']} · week of ${consoleDay(f['week'])}',
          ),
          subtitle: Text(
            '${f['introductions_per_active']} introductions per active '
            'person · mutual rate ${f['mutual_rate'] ?? '-'} · '
            '${f['active']} active',
          ),
        ),
    ],
  );
}
````

Create `.superpowers/sdd/2026-11-23-spec2-w10/edit_console_T3.py` with exactly:

````python
#!/usr/bin/env python3
# Spec 2 W10 Task 3: the console's three launch pages (after Audit, so
# every earlier page keeps its place) and config:launch_not_ready's line.
import runpy
edit = runpy.run_path('.superpowers/sdd/2026-11-23-spec2-w10/anchor.py')['edit']
edit('lib/console/console_app.dart', [
    ("""// have worked (Check my sign-in), never "That code didn't work."; the
// copied key is cleared by writing an empty clipboard, never by reading it
// (a read can raise the browser's permission prompt), and only when this
// console copied it.
""", """// have worked (Check my sign-in), never "That code didn't work."; the
// copied key is cleared by writing an empty clipboard, never by reading it
// (a read can raise the browser's permission prompt), and only when this
// console copied it.
//
// Spec 2 W10 (§8 W10): Launch readiness, Metrics and Fairness, the safety
// owner's, after Audit (screens/launch_screens.dart); a publish refused for
// the launch gates says to read Launch readiness.
"""),
    ("""import 'package:attune/console/screens/law_enforcement_screen.dart';
""", """import 'package:attune/console/screens/launch_screens.dart';
import 'package:attune/console/screens/law_enforcement_screen.dart';
"""),
    ("""  'config:production_checks_failed' =>
    "The production checks didn't pass, so nothing was published.",
""", """  'config:production_checks_failed' =>
    "The production checks didn't pass, so nothing was published.",
  // Spec 2 W10 (§8 W10).
  'config:launch_not_ready' =>
    "This would open Dating somewhere while a launch gate is red, so "
        'nothing was published. Launch readiness shows which.',
"""),
    ("""  audit('Audit', Icons.history_outlined);
""", """  audit('Audit', Icons.history_outlined),
  // Spec 2 W10 (§8 W10): the safety owner's.
  readiness('Launch readiness', Icons.flag_outlined),
  metrics('Metrics', Icons.query_stats_outlined),
  fairness('Fairness', Icons.balance_outlined);
"""),
    ("""    ConsolePage.audit => AuditScreen(api: widget.api),
""", """    ConsolePage.audit => AuditScreen(api: widget.api),
    ConsolePage.readiness => ReadinessScreen(api: widget.api, me: widget.me),
    ConsolePage.metrics => MetricsScreen(api: widget.api, me: widget.me),
    ConsolePage.fairness => FairnessScreen(api: widget.api, me: widget.me),
"""),
], 'T3 console')
````

```bash
D=.superpowers/sdd/2026-11-23-spec2-w10
python3 -I $D/edit_console_T3.py
dart format lib/console/screens/launch_screens.dart test/console/console_launch_test.dart
flutter analyze --no-pub lib/console test/console 2>&1 | tail -1
flutter test --no-pub test/console/console_launch_test.dart 2>&1 | tr '\r' '\n' | grep -E '^[0-9:]+ \+[0-9]+' | tail -1 | grep -oE '\+[0-9]+.*'
flutter test --no-pub test/console 2>&1 | tr '\r' '\n' | grep -E '^[0-9:]+ \+[0-9]+' | tail -1 | grep -oE '\+[0-9]+.*'
```

Expected: `lib/console/console_app.dart: 5 edit(s) (T3 console)`; `Formatted 2 files (0 changed) …`; `No issues found! …`; `+9: All tests passed!`; `+137: All tests passed!` (128 at `cbf7b30b` + 9).

- [ ] **Step 4: The mutants (a private copy of the tree)**

Create `.superpowers/sdd/2026-11-23-spec2-w10/mut_T3_dart.py` with exactly:

````python
# Spec 2 W10 Task 3 Dart mutants (dmut.py): each must be KILLED.
L = 'lib/console/screens/launch_screens.dart'
A = 'lib/console/console_app.dart'
T = ['test/console/console_launch_test.dart']
MUTS = {
    'moderator_asks': (L, """    if (me.owner) load();""", """    load();""", T),
    'moderator_sees_page': (L, """    if (!me.owner) {
      return ConsoleFrame(""", """    if (false) {
      return ConsoleFrame(""", T),
    'state_colour_only': (L, """        subtitle: Text(detail.isEmpty ? state : '$state: $detail'),""",
                          """        subtitle: Text(detail),""", T),
    'detail_dropped': (L, """  final List<Object?> l when l.isNotEmpty => l.join(', '),""", """  final List<Object?> l when l.isNotEmpty => '',""", T),
    'count_dropped': (L, """  final int n when n > 0 => '$n',""", """  final int n when n > 0 => '',""", T),
    'dev_line_dropped': (L, """    if (r.data['environment'] == 'development')
      'This project reads development, so it is never ready here.',""", """""", T),
    'ready_from_gates_ignored': (L, """  if (r.data['ready'] == true) {""", """  if (red == 0) {""", T),
    'metrics_window_ignored': (L, """  Map<String, Object?> get params => {'days': _days};""", """  Map<String, Object?> get params => {'days': 7};""", T),
    'metrics_no_reload': (L, """            setState(() => _days = s.first);
            load();""", """            setState(() => _days = s.first);""", T),
    'fairness_window_ignored': (L, """  Map<String, Object?> get params => {'weeks': _weeks};""", """  Map<String, Object?> get params => {'weeks': 4};""", T),
    'flag_unmarked': (L, """            '${f['flagged'] == true ? 'Flagged · ' : ''}'""", """            ''""", T),
    'retry_dropped': (L, """            onRetry: () {
              setState(() => read = null);
              load();
            },""", """            onRetry: () {},""", T),
    'launch_reason_generic': (A, """  'config:launch_not_ready' =>""", """  'config:launch_not_ready_x' =>""", T),
    'page_unrouted': (A, """    ConsolePage.readiness => ReadinessScreen(api: widget.api, me: widget.me),""",
                      """    ConsolePage.readiness => AuditScreen(api: widget.api),""", T),
}
````

```bash
python3 -I .superpowers/sdd/2026-11-23-spec2-w10/dmut.py .superpowers/sdd/2026-11-23-spec2-w10/mut_T3_dart.py | tail -1
```

Expected: `14/14 killed`.

- [ ] **Step 5: Record the tree (do not commit).**

### Task 4: The old `dating_mutual_match` case removed (§4.10 `notification_config.dart` [W10], R2, A-7; R-90)

**Files:**
- Create: `$D/{edit_app_T4.py, mut_T4_dart.py}`
- Modify: `lib/core/notifications/config/notification_config.dart` (the one case and its comment; **shared router: no other line changes**), `test/core/notifications/me_update_routing_test.dart`, `test/features/dating/device/dating_lock_entry_test.dart` (the header and the one tuple), `supabase/tests/dating_v2_device_contracts.sql` (its header comment)
- Test: `me_update_routing_test.dart` (`me_update opens HOME me`, `dating_mutual_match opens HOME null`); `dating_lock_entry_test.dart`

**What is NOT changed and why:** every other notification type's routing (the router is shared by every feature); `me_update` and `me_checkin` (still Dating's two pushes); the server's push writers (none sends `dating_mutual_match`: W8a's contract A).

- [ ] **Step 1: The edits**

Create `.superpowers/sdd/2026-11-23-spec2-w10/edit_app_T4.py` with exactly:

````python
#!/usr/bin/env python3
# Spec 2 W10 Task 4 (A-7, R2): the old dating_mutual_match case goes from
# notification_config.dart (one line and its comment; no other line
# changes). A stale push of that type now opens Home, as any type the app
# doesn't know. The tests follow; the device contract's comment says so.
import runpy
edit = runpy.run_path('.superpowers/sdd/2026-11-23-spec2-w10/anchor.py')['edit']
edit('lib/core/notifications/config/notification_config.dart', [
    ("""        // row while the Dating lock is on. The old match push opens Me too
        // for one release (A-7; W10 removes it).
        case 'me_update':
        case 'dating_mutual_match':
""", """        // row while the Dating lock is on. Spec 2 W10 (A-7): the old match
        // push's case is gone; a stale one opens Home, as any unknown type.
        case 'me_update':
"""),
], 'T4 notification_config')
edit('test/core/notifications/me_update_routing_test.dart', [
    ("""// Spec 2 W3a (§3.13, I-9, A-7): the neutral Dating push opens Me; the old
// match push opens Me too for one release.
""", """// Spec 2 W3a (§3.13, I-9, A-7): the neutral Dating push opens Me. Spec 2
// W10 (A-7): the old match push's case is gone; a stale one opens Home
// (no tab), as any type the app doesn't know.
"""),
    ("""  for (final type in ['me_update', 'dating_mutual_match']) {
    testWidgets('$type opens Me (/home?tab=me)', (tester) async {""",
     """  for (final (type, shown) in [
    ('me_update', 'HOME me'),
    ('dating_mutual_match', 'HOME null'),
  ]) {
    testWidgets('$type opens $shown', (tester) async {"""),
    ("""      expect(find.text('HOME me'), findsOneWidget);""", """      expect(find.text(shown), findsOneWidget);"""),
], 'T4 routing test')
edit('test/features/dating/device/dating_lock_entry_test.dart', [
    ("""// Every Dating push the server can send (me_update, me_checkin; the old
// dating_mutual_match for one release) opens Me or the check-in, the
// check-in behind the PIN.""", """// Every Dating push the server can send (me_update, me_checkin) opens Me
// or the check-in, the check-in behind the PIN (Spec 2 W10, A-7: the old
// dating_mutual_match is no Dating push any more).""",),
    ("""    ('dating_mutual_match', 'me', '/home?tab=me', '/home?tab=me'),
""", ""),
], 'T4 lock test')
edit('supabase/tests/dating_v2_device_contracts.sql', [
    ("""--      to a fixpoint. The app routes exactly those (and the old
--      dating_mutual_match, to Me, for one release: A-7).""", """--      to a fixpoint. The app routes exactly those (Spec 2 W10, A-7: the
--      old dating_mutual_match case is gone).""",),
], 'T4 device contract comment')
````

```bash
python3 -I .superpowers/sdd/2026-11-23-spec2-w10/edit_app_T4.py
grep -rn "dating_mutual_match" lib | wc -l | tr -d ' '
flutter test --no-pub test/core/notifications/me_update_routing_test.dart test/features/dating/device/dating_lock_entry_test.dart 2>&1 | tr '\r' '\n' | grep -E '^[0-9:]+ \+[0-9]+' | tail -1 | grep -oE '\+[0-9]+.*'
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/dating_v2_device_contracts.sql 2>&1 | grep -oE 'all held|CONTRACT VIOLATED.*' | head -1
```

Expected: `…notification_config.dart: 1 edit(s) (T4 notification_config)`, `…me_update_routing_test.dart: 3 edit(s) (T4 routing test)`, `…dating_lock_entry_test.dart: 2 edit(s) (T4 lock test)`, `…dating_v2_device_contracts.sql: 1 edit(s) (T4 device contract comment)`; `0`; `+24: All tests passed!`; `all held`.

- [ ] **Step 2: The mutants**

Create `.superpowers/sdd/2026-11-23-spec2-w10/mut_T4_dart.py` with exactly:

````python
# Spec 2 W10 Task 4 Dart mutants (dmut.py): each must be KILLED.
N = 'lib/core/notifications/config/notification_config.dart'
T = ['test/core/notifications/me_update_routing_test.dart']
MUTS = {
    'old_case_back': (N, """        case 'me_update':
          GoRouter.of(context).go(homeLocation(tab: AppTab.me));""", """        case 'me_update':
        case 'dating_mutual_match':
          GoRouter.of(context).go(homeLocation(tab: AppTab.me));""", T),
    'me_update_to_home': (N, """        case 'me_update':
          GoRouter.of(context).go(homeLocation(tab: AppTab.me));""", """        case 'me_update':
          GoRouter.of(context).go(RouteNames.home);""", T),
}
````

```bash
python3 -I .superpowers/sdd/2026-11-23-spec2-w10/dmut.py .superpowers/sdd/2026-11-23-spec2-w10/mut_T4_dart.py | tail -1
```

Expected: `2/2 killed` (`old_case_back` reads Me for the stale push; `me_update_to_home` loses the tab).

- [ ] **Step 3: Record the tree (do not commit).**

### Task 5: The launch docs, the runbook's drills, the design spec's notes, every W10 mutant again, and the W10 gate (§4.10 docs [W10]; §7.6 8.1; §1.5 pattern; Owner checklist)

**Files:**
- Create: `$D/{edit_runbook_T5.py, edit_docs_T5.py, gate.sh}`
- Replace: `lib/architecture/DATING_MODE_REVIEW_AND_GATES.md`, `lib/architecture/DATING_MODE_RELEASE_READINESS_CHECKLIST.md`
- Modify: `lib/architecture/DATING_MODERATION_RUNBOOK.md` (§13 one line, §14 added), `docs/superpowers/specs/2026-10-24-dating-mode-design.md` (five `amended S2 W10` notes)

- [ ] **Step 1: The two replaced docs**

Replace the whole of `lib/architecture/DATING_MODE_REVIEW_AND_GATES.md` with exactly:

````markdown
# Dating Mode review and gates

**Status:** replaced in Spec 2 W10 (2026-11-24). The gates are now those of
`docs/superpowers/specs/2026-10-24-dating-mode-design.md` §8: each wave's
"Gate before production switch-on" line, and W10's. Where this file and the
design spec differ, the spec wins.

## How a gate is kept

- **Machine-checkable gates** are read by `get_dating_launch_readiness()`
  (the owner, from the SQL editor, or the console's Launch readiness page;
  the safety owner's). It is red while the project reads development, and
  green only when every gate is (R-6). See
  `DATING_MODE_RELEASE_READINESS_CHECKLIST.md` for the list.
- **Human gates** (legal opinions, registrations, assessments, sign-offs,
  the pen test, drills, the device matrix) are recorded as evidence
  references: per country in `country_safety_config.legal_checklist`
  (published from the console's Countries page) and per flag in
  `private.flag_production_gates` (`record_flag_gate_evidence`). A
  reference is the place the signed document lives, never `DEV-…`: in
  production a `DEV-` reference is refused and never counts.
- **Production mode is the owner's alone** (`attune_environment`). No
  migration, script or edge function sets it; CI fails one that names it.

## Production-mode guards (Spec 2 W10)

While the project reads production:

- `publish_country_config` refuses a checklist with a `DEV-` reference
  (`dev_reference`), and refuses to open a place (the country, or a region
  newly open) while any launch gate for that country is red
  (`config:launch_not_ready`). Closing, narrowing and switching same-gender
  off are never refused.
- A gated flag whose evidence is a `DEV-` reference can't be turned on, and
  `production_flag_violations()` lists it; `record_flag_gate_evidence`
  refuses a `DEV-` reference.
- The introductions and chat configs can't be activated with a `DEV-`
  reference (W5a, W6b); verification refuses the fake and sandbox
  providers (W4a); the CSAM matcher refuses its stub (Spec 1 W7b).

## Decision rule

If a question needs a licensed clinical judgment, a Ghanaian or West
African cultural judgment, an LGBTQ+ or DV safety judgment, a legal or
privacy decision, or a moderation commitment, the answer is recorded by the
relevant reviewer and its reference entered as above. Engineering never
invents it.
````

Replace the whole of `lib/architecture/DATING_MODE_RELEASE_READINESS_CHECKLIST.md` with exactly:

````markdown
# Dating Mode release readiness checklist

**Status:** replaced in Spec 2 W10 (2026-11-24). Source:
`docs/superpowers/specs/2026-10-24-dating-mode-design.md` §8 (every wave's
gate line and W10's), §7.7 (the device matrix). The spec wins.

## 1. What `get_dating_launch_readiness()` checks

Run `select public.get_dating_launch_readiness();` (Ghana and the UK) or
`select public.get_dating_launch_readiness('GH');` as the owner, or open
Launch readiness in the console. `ready` is true only when every gate is
green; it is never true while the project reads development.

| Gate | Green when |
|---|---|
| `environment` | the project reads production (the owner set it) |
| `age_assurance_live` | `age_assurance_mode` is `live` |
| `safety_owner`, `moderator` | an active safety owner and an active moderator |
| `keys` | the exclusion and field keys match their fingerprints; the push key is set |
| `introductions_config` | an introductions config is active, every active one with four real review references |
| `chat_config` | a chat safety config is active with a real review reference |
| `flag_evidence` | every launch flag (`dating_mode_enabled`, `dating_candidate_generation`, `dating_match_messaging`, `dating_profile_photos`, `dating_same_gender_matching`, `dating_age_assurance`, `dating_traveller_detection`, `dating_couple_link`, `support_resources_v2`, `csam_hash_matching`) has its gate row with real evidence |
| `no_flag_violations` | no gated flag is on without real evidence |
| `no_test_verifications` | no age or identity pass from the fake providers still stands |
| `kill_switch_clear` | no same-gender switch-off is pending |
| `log_settings_safe` | the database logs keep no request values |
| `sla_alerts` | `moderation_alert_webhook` is set |
| `checklist:GH`, `checklist:GB` | every checklist key has a real reference (none `DEV-`, none blank) |
| `resources:GH`, `resources:GB` | the country's resources were verified within 90 days, and every active support resource for it too (at least one) |

## 2. What only people can do (record each as a reference)

- [ ] Ghana: the legal opinion on the reconsidered bill (`ghana_legal_opinion`); DPC registration (`dpc_registration`).
- [ ] UK: the OSA illegal-harms and children's-access assessments (`osa_illegal_harms_assessment`, `osa_childrens_access_assessment`); highly effective age assurance (`highly_effective_age_assurance`); a UK representative if the controller is outside the UK.
- [ ] Both: the DPIA signed (`dpia`); the external penetration test passed with no open High or Critical (`pen_test`); the safety owner and moderator named, trained and live (`safety_owner_and_moderator`); the clinician, cultural (with faith advisers), LGBTQ+ and DV reviewers' sign-offs (`reviewer_signoffs`).
- [ ] Each flag's gate line (`private.flag_production_gates.gate`) met, then `record_flag_gate_evidence`.
- [ ] The §7.7 device matrix on release builds; the runbook drills (`DATING_MODERATION_RUNBOOK.md` §14).
- [ ] The store listing and Welcome copy "Dating open in Ghana and the UK" (with Spec 1).
- [ ] Smoke tests on the production project with test accounts: introductions, chat, report, appeal, exit, export.

## 3. Switch-on order (the owner's)

1. Every item in §2 recorded; every deploy done.
2. Set the project to production mode.
3. `select public.get_dating_launch_readiness();` and
   `select * from public.production_flag_violations();`: fix anything red.
4. Turn the flags on (each needs its evidence).
5. Open each country from the console (Countries → Publish
   `{"dating_enabled": true}`); a red gate refuses the opening.
````

- [ ] **Step 2: The runbook's drills and the spec's notes**

Create `.superpowers/sdd/2026-11-23-spec2-w10/edit_runbook_T5.py` with exactly:

````python
#!/usr/bin/env python3
# Spec 2 W10 Task 5: the runbook's weekly launch-page review (§13) and the
# launch drills (§14: a P0 at 03:00, a CSAM hash hit, a law-enforcement
# request, the same-gender kill switch, Dating off for a country). The
# runbook must still end where W7 left it.
import pathlib
p = pathlib.Path('lib/architecture/DATING_MODERATION_RUNBOOK.md')
s = p.read_text()
END = """  counts before anything is published (counsel sets the threshold).
"""
assert s.endswith(END), 'the runbook no longer ends with section 13 as W7 left it'
p.write_text(s + """- Weekly (Spec 2 W10): the console's Fairness page (flagged cohorts go to
  the safety owner; nothing re-weights by itself, a change is a new config
  version with a fairness review reference) and Metrics page (counters of
  50 or more only).

## 14. Launch drills (Spec 2 W10)

Run each drill on the development project before switch-on, then once a
quarter. Record who ran it, when, how long each step took and what broke,
and keep the record with the `safety_owner_and_moderator` evidence.

1. **A P0 report at 03:00.** A tester files a `threat_to_life` report at
   03:00 GMT. Check the SLA alert arrives where `moderation_alert_webhook`
   points, the out-of-hours cover sees it, places the interim hold (§5) and
   escalates (§7) inside the P0 time. Note the minutes from report to hold.
2. **A CSAM hash hit.** Upload the vendor's test image from a test account
   (never real material). Check the CSAM hold appears on the CSAM holds
   page, the report goes to the hash vendor's route, and only the safety
   owner can lift it, with a written reason.
3. **A law-enforcement request.** Log a mock request on the Law
   enforcement page: legal process, then an emergency one. Follow
   `DATING_LAW_ENFORCEMENT_POLICY.md` to a decision and check the
   transparency summary counts both.
4. **The same-gender kill switch.** Publish `{"same_gender_enabled": false}`
   for a test country from the Countries page. Check the answer's
   `switched` and `affected`, that same-gender introductions and
   conversations close neutrally, and that
   `select public.get_dating_launch_readiness();` shows
   `kill_switch_clear` green afterwards.
5. **Dating off for a country (rollback, §7.6 8.1).** Publish
   `{"dating_enabled": false}` for a test country. Check nobody there gets
   new introductions and the app shows the country as not open; then open
   it again.
""")
print(f'{p}: section 13 line and section 14 added (T5 runbook)')
````

Create `.superpowers/sdd/2026-11-23-spec2-w10/edit_docs_T5.py` with exactly:

````python
#!/usr/bin/env python3
# Spec 2 W10 Task 5: the design spec says what W10 built where it adds to
# it (five amendment notes, the W7/W8 pattern). The owner's own uncommitted
# edits to the spec (the W11 status line) are left as they are.
import runpy
edit = runpy.run_path('.superpowers/sdd/2026-11-23-spec2-w10/anchor.py')['edit']
S = 'docs/superpowers/specs/2026-10-24-dating-mode-design.md'
edit(S, [
    ("""at launch, **the owner** sets the launch project to production mode and then turns production flags on per country.
""", """at launch, **the owner** sets the launch project to production mode and then turns production flags on per country. *(amended S2 W10: the guards as built: in production a `DEV-` reference anywhere in a country's `legal_checklist` is refused (`dev_reference`); a gated flag's `DEV-` evidence is no evidence (the gate trigger, `production_flag_violations()`, and `record_flag_gate_evidence` refuses one); and `publish_country_config` refuses to open a place (the country, or a region newly open) while any launch gate for that country is red (`config:launch_not_ready`), a reduction never. `get_dating_launch_readiness(p_country)` (service role; Ghana and the UK by default) lists every machine-checkable gate of §8 (the environment, `age_assurance_mode = 'live'`, an active safety owner and moderator, the keys, both configs and every launch flag's evidence without `DEV-`, no flag violation, no fake-provider pass standing, no pending kill switch, safe log settings, the SLA webhook, each country's checklist and its support resources within 90 days); W9 is read only through `dating_couple_link`'s gate row. The console's Launch readiness, Metrics and Fairness pages are the safety owner's (R-85–R-90).)*
"""),
    ("""smoke tests on the production project with test accounts (introductions, chat, report, appeal, exit, export).
""", """smoke tests on the production project with test accounts (introductions, chat, report, appeal, exit, export). *(amended S2 W10: `dating_v2_launch_contracts.sql` L1–L6; the smoke tests, the drills and the device matrix are the owner's.)*
"""),
    ("""Flags go to the safety owner in the console; there is no automatic re-weighting.""",
     """Flags go to the safety owner in the console; there is no automatic re-weighting. *(amended S2 W10: the console's Fairness page, the safety owner's: the last 4 or 12 weeks, flagged cohorts first.)*"""),
    ("""- Anti-metrics (watched, never optimised): sessions a day, time in Dating, introductions viewed.
""", """- Anti-metrics (watched, never optimised): sessions a day, time in Dating, introductions viewed.
- *(amended S2 W10: the console's Metrics page, the safety owner's, sums every `dating.` key over 7, 28 or 90 UTC days and names only those at 50 or more; the rest are counted, never named.)*
"""),
    ("""| `DATING_MODE_REVIEW_AND_GATES.md`, `DATING_MODE_RELEASE_READINESS_CHECKLIST.md` | Replace [W10] | this spec's §8 gates and `get_dating_launch_readiness()` |
""", """| `DATING_MODE_REVIEW_AND_GATES.md`, `DATING_MODE_RELEASE_READINESS_CHECKLIST.md` | Replace [W10] | this spec's §8 gates and `get_dating_launch_readiness()` *(amended S2 W10: replaced; the checklist lists every readiness gate and the owner's switch-on order; the runbook gains the launch drills, §14)* |
"""),
], 'T5 design spec')
````

```bash
D=.superpowers/sdd/2026-11-23-spec2-w10
python3 -I $D/edit_runbook_T5.py
python3 -I $D/edit_docs_T5.py
grep -c 'amended S2 W10' docs/superpowers/specs/2026-10-24-dating-mode-design.md
grep -c 'Spec 2 W10' supabase/sql/dev_enable_spec2_dating_flags.sql
```

Expected: `lib/architecture/DATING_MODERATION_RUNBOOK.md: section 13 line and section 14 added (T5 runbook)`; `…dating-mode-design.md: 5 edit(s) (T5 design spec)`; `5`; `0` (the dev script is untouched; `git diff --stat -- supabase/sql/dev_enable_spec2_dating_flags.sql` prints nothing of W10's).

- [ ] **Step 3: Every W10 mutant set again, on the finished tree**

```bash
D=.superpowers/sdd/2026-11-23-spec2-w10
M=supabase/migrations/20261124100000_dating_v2_launch_guards.sql; C=supabase/tests/dating_v2_launch_contracts.sql; G=supabase/migrations/20261124100010_dating_v2_launch_guards_grants.sql
echo "T1 $(W10_DB=attune_spec3a python3 -I $D/mutate.py $M $C $D/mut_T1.py $D/mut $G | grep -c 'CONTRACT VIOLATED')"
echo "T2 $(python3 -I $D/denomut.py $D/mut_T2.py | tail -1)"
for s in T3 T4; do echo "$s $(python3 -I $D/dmut.py $D/mut_${s}_dart.py | tail -1)"; done
```

Expected: `T1 43`, `T2 7/7 killed`, `T3 14/14 killed`, `T4 2/2 killed`.

- [ ] **Step 4: The W10 gate (wait for an idle machine for the race script)**

Create `.superpowers/sdd/2026-11-23-spec2-w10/gate.sh` with exactly:

````bash
#!/bin/bash
# Spec 2 W10 gate (W8's gate.sh, for W10). usage (repo root): gate.sh [db]
# db defaults to attune_spec3a (the replay passes its clone). Writes
# $D/gate-W10.txt, one line per check. The race script runs on an idle
# scratch database built from <db> (dropped after).
DB=${1:-attune_spec3a}
D=.superpowers/sdd/2026-11-23-spec2-w10
O=$D/gate-W10.txt; : > $O
[ "$(psql -X -d "$DB" -Atc 'select current_database()')" = "$DB" ] || { echo "no database $DB" >> $O; exit 1; }
H=$(date -u +%H)
$D/suite.sh "$DB" > $D/sql-W10.txt
echo "SQL $(grep -c '^PASS' $D/sql-W10.txt) PASS, $(grep -c '^FAIL' $D/sql-W10.txt) FAIL" >> $O
echo "SQL-NEW-FAILS: $(comm -13 <(grep FAIL $D/sql-baseline.txt | sort) <(grep FAIL $D/sql-W10.txt | sort) | tr '\n' ' ')" >> $O
if (( 10#$H >= 22 || 10#$H < 8 )); then
  echo "SQL-NOTE: suite run at ${H}h UTC (22:00-08:00): a quiet_hours_contracts.sql FAIL is the real clock (W8 R-T3-5); re-run it by day" >> $O
fi
echo "LAUNCH $(psql -X -q -v ON_ERROR_STOP=1 -d "$DB" -f supabase/tests/dating_v2_launch_contracts.sql 2>&1 | grep -oE 'all held|CONTRACT VIOLATED.*' | head -1)" >> $O
echo "CANARY $(psql -X -q -v ON_ERROR_STOP=1 -d "$DB" -f supabase/tests/dating_rls_canary.sql 2>&1 | grep -oE 'all held|CONTRACT VIOLATED.*' | head -1)" >> $O
(cd supabase/functions && eval "$(grep -m1 -oE 'deno test --allow-read [^"]*' ../../.github/workflows/tests.yml)" 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -E '^ok \||^FAILED' | tail -1) | sed 's/^/DENO /' >> $O
(cd supabase/functions && eval "$(grep -m1 -oE 'deno check --lock[^"]*' ../../.github/workflows/tests.yml)" > /dev/null 2>&1; echo "DENO-CHECK exit=$?") >> $O
flutter analyze --no-pub lib test > $D/analyze-W10.txt 2>&1; echo "ANALYZE $(tail -1 $D/analyze-W10.txt)" >> $O
echo "W10SHA $(shasum -c .superpowers/sdd/2026-11-04-spec1-w10-accessibility-docs/w10-1.0.sha | grep -vc ': OK$')" >> $O
echo "W9SHA $(shasum -c .superpowers/sdd/2026-11-04-spec1-w9/flag_off.sha | grep -vc ': OK$')" >> $O
echo "LATCH $(shasum -c .superpowers/sdd/2026-11-07-spec2-w3/latch.sha)" >> $O
flutter test --no-pub test/architecture/games_untouched_test.dart 2>&1 | tr '\r' '\n' | grep -oE 'All tests passed!|Some tests failed\.' | tail -1 | sed 's/^/GAMES /' >> $O
echo "CONSOLE $(flutter test --no-pub test/console 2>&1 | tr '\r' '\n' | grep -E '^[0-9:]+ \+[0-9]+' | tail -1 | grep -oE '\+[0-9]+( -[0-9]+)?: (All tests passed!|Some tests failed\.)')" >> $O
flutter build web -t lib/console/main_console.dart -o "$PWD/build/console" --pwa-strategy=none --no-web-resources-cdn --no-pub > $D/console-web-W10.txt 2>&1
echo "CONSOLE-WEB exit=$?" >> $O
echo "FLAGS $(psql -X -d "$DB" -Atc "select count(*) || ' rows, ' || count(*) filter (where enabled) || ' on' from public.feature_flags")" >> $O
R=w10race_$$
dropdb --if-exists $R 2>/dev/null; createdb $R
pg_dump -s "$DB" | psql -X -q -d $R > /dev/null 2>&1
pg_dump -a -t public.metric_key_prefixes -t public.feature_flags -t public.country_safety_config -t private.dating_calling_codes \
  -t private.dating_phone_trunk_rules -t private.flag_production_gates -t public.dating_algorithm_configs \
  -t public.dating_safety_configs "$DB" | psql -X -q -d $R > /dev/null 2>&1
echo "LOAD-BEFORE-RACES $(uptime | sed 's/.*load averages*: //')" >> $O
bash scripts/concurrency/dating_kill_switch_races.sh $R > $D/race-W10.txt 2>&1
echo "RACES $(grep -c '^PASS' $D/race-W10.txt) PASS, $(grep -c '^FAIL' $D/race-W10.txt) FAIL" >> $O
dropdb $R
flutter test --no-pub --reporter compact > $D/flutter-W10.txt 2>&1
echo "FLUTTER $(tr '\r' '\n' < $D/flutter-W10.txt | grep -E '^[0-9:]+ \+[0-9]+' | tail -1 | grep -oE '\+[0-9]+( ~[0-9]+)?( -[0-9]+)?: (All tests passed!|Some tests failed\.)')" >> $O
echo "FLUTTER-FAILS:" >> $O
tr '\r' '\n' < $D/flutter-W10.txt | grep -E '\[E\][[:space:]]*$' | sed -E 's/^[0-9:]+ \+[0-9]+( ~[0-9]+)?( -[0-9]+)?: //; s#.*/test/#test/#; s/ \[E\][[:space:]]*$//' | sort -u | sed 's/^/  /' >> $O
echo DONE >> $O
cat $O
````

```bash
uptime
bash .superpowers/sdd/2026-11-23-spec2-w10/gate.sh attune_spec3a
```

Expected (the replay's, at `cbf7b30b` + W10, no W9):

```text
SQL 164 PASS, 14 FAIL
SQL-NEW-FAILS: 
LAUNCH all held
CANARY all held
DENO ok | 281 passed | 0 failed (2s)
DENO-CHECK exit=0
ANALYZE 571 issues found. (ran in 20.1s)
W10SHA 0
W9SHA 0
LATCH lib/home/home_screen.dart: OK
GAMES All tests passed!
CONSOLE +137: All tests passed!
CONSOLE-WEB exit=0
FLAGS 45 rows, 6 on
LOAD-BEFORE-RACES 7.75 10.65 12.06
RACES 58 PASS, 0 FAIL
FLUTTER +9628 -3: Some tests failed.
FLUTTER-FAILS:
  test/accessibility/w10/healing_journal_large_text_test.dart: journal list and entry, 390 wide, text 1.0
  test/accessibility/w10/healing_journal_large_text_test.dart: journal list and entry, 390 wide, text 1.3
  test/accessibility/w10/healing_journal_large_text_test.dart: journal list and entry, 390 wide, text 2.0
DONE
```

After W9 every count moves by W9's own additions; `SQL-NEW-FAILS` stays empty and `FLUTTER-FAILS` lists only the three `healing_journal_large_text` goldens.

- [ ] **Step 5: Record the tree (do not commit).**

---

## Owner checklist (nothing here is done by an implementer)

1. **⚑ R-86, the opening gate.** In production, opening a place (a country, or a region) is refused while any launch gate for that country is red. Approve, or say which gates may be red at an opening (each is one name in a list).
2. **Deploys, in order, after every earlier undeployed wave (Spec 1 W1–W10, Spec 2 W1–W9):** `supabase db push` (one migration and its twin; the self-revoke means a push that stops between them fails closed); deploy `dating-moderation` (Task 2); rebuild and host the console's web build (CI's `console-web` line) so the three pages appear; the app build (Task 4) whenever the next one ships. Nothing turns on.
3. **⚑ Which project launches (R-87).** Recommended: a separate production project, created clean, so no test account, `DEV-` reference, fake or sandbox pass, test report or test metric comes with it. If the current project (`mrgjtyacrzfylawyzabm`) is flipped instead, **before** setting production mode: turn Dating off (`update public.feature_flags set enabled = false where key = 'dating_mode_enabled';` from the SQL editor — **not** a `like 'dating%'` update: switching `dating_same_gender_matching` off runs the same-gender purge through its trigger), close Ghana and the UK from the console (Countries → Publish `{"dating_enabled": false}`), revoke every verification made before the flip (`select public.revoke_dating_age_verification(v.user_id, 'pre_launch') from public.dating_age_verifications as v where v.revoked_at is null;` — sandbox passes can't be told from live ones), exit or delete every test account, and replace every `DEV-` reference (configs, flag evidence, checklists). Never run `supabase/sql/dev_enable_spec2_dating_flags.sql` there again (it refuses in production mode anyway).
4. **Switch-on, in order (`DATING_MODE_RELEASE_READINESS_CHECKLIST.md` §3):** every human gate recorded as a reference (item 5); set the project to production mode (`attune_environment`, Vault or `ALTER DATABASE`, the owner's alone); run `select public.get_dating_launch_readiness();` and `select * from public.production_flag_violations();` and fix every red line; record each flag's evidence (`select public.record_flag_gate_evidence('<flag>', '<where the signed document lives>');`); turn the flags on; open each country from the console. The console's Launch readiness page shows the same gates.
5. **The human gates (spec §8 W10 and every wave's gate line), each recorded as a reference — never `DEV-…`:** Ghana's legal opinion on the reconsidered bill (`ghana_legal_opinion`); Ghana DPC registration (`dpc_registration`); the UK OSA illegal-harms and children's-access assessments (`osa_illegal_harms_assessment`, `osa_childrens_access_assessment`) and highly effective age assurance (`highly_effective_age_assurance`); **⚑ a UK representative if the controller is outside the UK** (add a `uk_representative` key to GB's checklist from the console if it applies; the checklist only grows); the DPIA signed (`dpia`); the external penetration test passed with no open High or Critical (`pen_test`); the safety owner and a moderator who reads Twi, Ga and Pidgin named, trained and live, with out-of-hours P0 cover (`safety_owner_and_moderator`; their `dating_moderators` rows active); clinician, cultural (with faith advisers), LGBTQ+ and DV reviewers' sign-offs (`reviewer_signoffs`); counsel's signature on the law-enforcement policy (W7's gate row on `dating_match_messaging`); `age_assurance_mode = 'live'` with the vendors contracted (W4); the introductions config activated with real references (W5); the chat config with the reviewers' reference (W6); `support_resources` verified within 90 days for Ghana and the UK (and the row's `resources_verified_at`); the SLA webhook (`moderation_alert_webhook`).
6. **The runbook drills** (`DATING_MODERATION_RUNBOOK.md` §14): a P0 at 03:00, a CSAM hash hit, a law-enforcement request, the same-gender kill switch, Dating off for a country — on the development project, recorded with the `safety_owner_and_moderator` evidence.
7. **The §7.7 device matrix on release builds** (F-4), with W8's 33 checks (`w8-owner-list.md` §4) and **the hard release gate: the Android launcher-alias build ships before the 10 Dec public launch (W8 device check 21)**. Data use measured (D1's 15 MB and D9's figures; correct the copy if off by more than 25%) decides W5's lazy photo loading (W8 R-82).
8. **The store listing and the Welcome copy** "Dating open in Ghana and the UK" (Spec 1 §3, store listing; the Welcome preview reads the open countries already).
9. **Smoke tests on the production project** with test accounts (introductions, chat, report, appeal, exit, export), then those accounts exited.
10. **The console's new pages** are the safety owner's: check the rail shows Launch readiness, Metrics and Fairness after Audit, and that a moderator's console says they are the safety owner's.
11. **Copy reviewers (console only, Plan copy):** the gate labels (`consoleGateLabel`), `kConsoleLaunchOwnerOnly`, the readiness, metrics and fairness lines, and `config:launch_not_ready`'s line. No app string is added.
12. **Carried, not built (R-91):** W4b's trusted-device-before-locks deadlock (busy + retry, no data lost); a per-user rate limit on `dating-device-check` (decide after the pen test).
13. **The production precondition stands (W7, W8):** Dating is never on in production without an active moderator and safety owner; W10's gates now enforce it at every opening.

## Owner questions (each with this plan's recommended default)

1. **Opening gate (R-86):** should `publish_country_config` refuse to open a country in production while any launch gate is red? — **Default: yes, as built.**
2. **Launch project (R-87):** a separate production project, or flip the current one? — **Default: a separate production project** (the clean-up in Owner checklist 3 is the fallback).
3. **Launch flags (R-87):** Dating's eight plus Spec 1's `support_resources_v2` and `csam_hash_matching`; add `platform_age_signals`? — **Default: no** (it is Spec 1's worldwide gate, not Dating's).
4. **UK representative:** add a `uk_representative` checklist key for GB? — **Default: only if counsel says the controller is outside the UK; the owner adds it from the console (no code).**
5. **Console pages (R-89):** safety owner only, or moderators too? — **Default: safety owner only.**
6. **Metrics threshold (R-89):** n ≥ 50 for every `dating.` key, operational counters included? — **Default: yes** (operational counters stay visible in `get_dating_operational_health`).
7. **Stale `dating_mutual_match` push (R-90):** opens Home (the router's default) rather than Me? — **Default: Home.**
8. **Carry 4 (R-91):** leave the W4b deadlock and the device-check rate limit as follow-ups? — **Default: yes; the pen test decides the rate limit.**

## Spec coverage (self-review)

| Spec | Where |
|---|---|
| §8 W10 Contents: migration 1, production-mode guards (checklist, `DEV-` refs, provider mode), `get_dating_launch_readiness()` | Task 1 (R-85–R-88) |
| §8 wave table W10 `dating_v2_launch_guards`: red unless `private.attune_environment()` returns `'production'` (R-6) | Task 1 L1 (mutants `env_gate_green`, `readiness_ignores_red`) |
| §8 W10 Tests: every gate green, red while not production | Task 1 L1, L2 |
| §8 W10 Tests: smoke tests on the production project | Owner checklist 9 |
| §8 W10 Contents: the per-country checklist filled in `legal_checklist` | Owner checklist 5 (values); Task 1 (`checklist:CC`, `dev_reference`) |
| §8 W10 Contents: dashboards over `metric_counters` and the fairness reports in the console; §6.9 n ≥ 50; §5.9 flags to the safety owner | Tasks 1 (L5), 2, 3 (R-89) |
| §8 W10 Contents: a runbook drill (P0 at 03:00, CSAM hash hit, LE request, same-gender kill switch); §7.6 8.1 rollback drill | Task 5 (runbook §14); Owner checklist 6 |
| §8 W10 Contents: store listing and Welcome copy | Owner checklist 8 |
| §8 W10 Contents / §4.10 / R2 / A-7: the old `dating_mutual_match` case removed | Task 4 (R-90) |
| §8 W10 Contents: the full §7.7 device matrix; the penetration test | Owner checklist 5, 7 |
| §8 W10 Contents: the owner sets production mode, then flags per country | Owner checklist 4; the opening gate (R-86) |
| §8 W10 Gate line (every item) | Owner checklist 5; machine-checkable parts in Task 1's gates |
| §4.10 `DATING_MODE_REVIEW_AND_GATES.md`, `DATING_MODE_RELEASE_READINESS_CHECKLIST.md`: Replace [W10] | Task 5 Step 1 |
| §1.3 Q19b, R-6: no script sets `attune_environment` | Global Constraints; CI's "Nothing sets attune_environment" job |
| §4.9: dev script extended by every batch | Not changed: W10 adds no flag (R-92) |
| §1.5 pattern: amendment notes | Task 5 Step 2 |
| §2.2 Seeds: "in production, W10 publishes them [GH, GB] with their checklists" | Owner checklist 4–5: the safety owner publishes from the console (no script; the opening gate checks the published row, R-86) |
| §3.2 D1: the 15 MB figure measured on the W10 device matrix, the copy corrected if off by more than 25% | Owner checklist 7 |
| §6.6 law-enforcement policy counsel-final at W10; §6.8 DPIA signed at W10 | Owner checklist 5 (`dpia`; W7's gate row) |
| Carries 1–6 | Pre-flight table |

## Replay record (2026-11-23)

The plan was built in a scratch copy of the repo at `cbf7b30b` (`git archive`, so no checkout of the main tree; the W8 tool folder, the W10 and W9 sha lists, the latch and `carries.md` copied in) on a clone of `attune_spec3a` (`w10build`, `createdb -T`). **W9 did not exist**: every W9 name W10 reads is in the W9 interface table, and the only stub is the contract's own (the gate row of `dating_couple_link`, inserted inside its rolled-back transaction only when missing). The build found and fixed five things this text now carries:

1. **The canary's S-4 scan follows names, even in comments.** A comment naming `publish_country_config` inside the gates' body, and the first design's gate on `dating_export_for_job(uuid)` (W9's decrypting export), made the service-role readiness read as a decrypt path. The comment was reworded, and the export gate was dropped (R-88; carry 1).
2. **`country_config_checks` reports the keys too.** `exclusion_key_not_ready` and `field_key_not_ready` are the `keys` gate's, so the checklist gate leaves them out.
3. **In production the field key is read from Vault only** (W1d): the contract puts it there (`vault.create_secret`, rolled back), not in a setting.
4. **A publish replaces the whole checklist** (it only grows): the contract builds each one from the current row (`pg_temp.checklist`).
5. **Three existing contracts met the new rules:** `dating_rls_canary.sql` (five rows), `dating_v2_setup_contracts.sql` (the photo-reader pin: the gates name the flag `dating_profile_photos`) and `country_safety_config_contracts.sql` (a production opening now needs the launch gates: R-93). Two mutants survived the first contract (`opening_reads_current_row`; the console's `ready_from_gates_ignored`): the contract now opens Ghana with the publish that brings its last piece of evidence, and the console test has a "server's ready decides" case.

The full W10 gate ran on the build (`gate.sh w10build`; Task 5 Step 4's Expected). Its first race run, at load 3.7 while another agent ran Flutter, failed one case not W10's ("two generation ticks claim one run…: the second tick did not run while the first held its claim (no race)" — a timing case; W10 touches no generation); the race script alone on a fresh scratch database from the same clone then read **58 PASS, 0 FAIL**, which is the line above.

Then the plan was **replayed from this text**: a fresh scratch copy at `cbf7b30b`, a fresh clone (`w10replay`), and a script that wrote every "Create/Replace … with exactly" block (19 files) and ran every `bash` block in order (16), with the database name swapped for the clone's. The gate's own block was skipped (the build ran it on the same commands). Every Expected line matched except two, fixed here: Task 1 Step 3's first error is `get_dating_launch_readiness(text)` at line 63 (a SQL helper's body is checked at creation), and Task 5 Step 2's dev-script check used `git diff`, which a scratch copy (not a repository) can't run (now `grep -c`). The replayed tree equals the built tree file for file (`diff -rq`, build output and tool logs aside).

| Check | Build (`w10build`) | Replay (`w10replay`) |
|---|---|---|
| Migration + twin, applied twice | `exit=0` ×4 | `exit=0` ×4 |
| Migration alone (split push) | new functions nobody's, re-created ones keep grants (`f|f|t`) | same |
| `marked_diff.py` | 5 functions `OK` | 5 `OK` |
| SQL suite (wrapped) | 163 / 14 → 164 / 14, the baseline's 14 fails only | 163 / 14 → 164 / 14 |
| `dating_v2_launch_contracts.sql`, canary | `all held`, `all held` | exit 0, exit 0 |
| SQL mutants (T1) | 43 / 43 RED | 43 / 43 (twice: Task 1, Task 5) |
| Deno (CI line, frozen lock) | 281 passed, 0 failed; `deno check` clean | same |
| Deno mutants (T2) | 7 / 7 killed | 7 / 7 (twice) |
| Console tests | +137 (128 + 9); web build exit 0 | +137 |
| Dart mutants | T3 14 / 14, T4 2 / 2 | same (twice) |
| `flutter analyze --no-pub lib test` | 571, no new issue | `lib/console test/console`: no issues |
| Full `flutter test` | +9628 −3 (+9621 −3 at `cbf7b30b`; +9 console, −2 lock-entry tuples), the three journal goldens | (the build's run) |
| Races (idle scratch DB) | 58 / 58 | (the build's run) |
| W10 / W9 golden shas, latch, Games guard | 0 / 0 / OK / passed | (the build's run) |
| Feature flags | 45 rows, 6 on (unchanged) | 45 rows, 6 on |

The clones (`w10build`, `w10replay`) and the race databases were dropped afterwards; `attune_spec3a` holds no W10 object (it was only read and cloned); the main tree changed only by this file and the tool folder `.superpowers/sdd/2026-11-23-spec2-w10/` (Step 0's tools and the replay script; every other tool file is written by the steps above).

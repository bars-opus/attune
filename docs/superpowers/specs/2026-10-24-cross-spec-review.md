# Cross-spec review — Spec 1 (app flow, identity), Spec 2 (Dating Mode), Spec 3 (forum removal)

**Date:** 2026-10-24 · **Reviewer:** cross-spec review (read-only; nothing fixed) · **Repo:** `main` at `a7b07e79` + working tree
**Specs:** S1 = `2026-10-24-app-flow-identity-design.md` · S2 = `2026-10-24-dating-mode-design.md` · S3 = `2026-10-24-forum-removal-design.md`
**Authority:** `research/2026-10-24-flow-dating-research/11-synthesis-decisions.md` §12 (binding), then §11.
**Build order checked:** S3 W1–W2 → S1 (W1–W7, W9, W10) → S2 W1–W10 → S3 W3 → S2 W11.
**Line refs** are to the spec files as written today (`l.` = line).

**Totals:** 1 Critical · 23 Important · 40 Minor.

Repo facts checked for this review (not taken from the specs): `profiles` grants (`20260713120000:80`) and `confirmed_violation_count` (`20260722120000:23`); `public.users` grants (no client DELETE); `relationship_chat_open` (checks membership); the archive sweep in `20261018100000`; the `auth.users` trigger precedent (`20260705162000:111`); no `storage.objects` trigger anywhere; 8 migrations with explicit `BEGIN;`; no `CREATE INDEX CONCURRENTLY`; 55 `_grants.sql` twins; `config.toml` holds only `project_id`; CLI 2.75.0; no `attune_environment` setting and no documented dev/staging project; 35 manual modules; `quick_exit_service.dart` and `auth_provider.dart` `signOut`; `auth_exports.dart` → `export_screens.dart:43` exports `login_screen_options.dart`; `local_pg_setup.sh` runs `dropdb`/`createdb`.

---

## 1. Ruling compliance (§12)

| Ruling | Where | Verdict |
|---|---|---|
| Q1 app worldwide; Dating GH (Accra + Ashanti, men–women) + UK; "not open" + "Tell me when it's here" elsewhere | S1 §1.3, W6/W7 not country-gated; S2 §2.2 seeds (GH tier 1, `open_regions {GA,AH}`, same-gender off; GB tier 3), §3.10 | Honoured (see R-4) |
| Q2 same-gender off in Tier 1/2, on in UK | S2 §2.4, D5/D6, kill switch, `publish_country_config` refusal | Honoured |
| Q13 4 intentions; married in any form or separated excluded | S2 D2, intention CHECK, attestation, `hiding_relationship` report; faith, 18–99, +7, day-30 photos | Honoured |
| Q9 redesign deferred; no spec removes reposts, follows, handles, quotes, dislikes | S1 §1.2 non-goals, W8 held empty, W9 re-creates `create_opinion_with_quote` unchanged; S3 §1 "Opinions stays exactly as it is"; S2 non-goal | Honoured |
| Q10 filter + Unicode normaliser + "Need support now?" + at-risk reason + Journal Gemini pause until `self_disclosure` runs first | S1 W9 (filter, link, reason, check), W1 (pause flag, D12) | Honoured (see R-3) |
| Q6 two tabs; Me with Dating inside; optional Dating lock | S1 §3.10–3.11, §3.9 lock; S2 §3.1, §3.14 | Honoured (see C-2) |
| Q3 liveness + estimate (25) + ID + human review within 24 h | S2 §3.3 (FAE, ID, human for identity only, CompareFaces) | Honoured |
| Q19 everything ON in dev, production gated | S1 `dev_enable_spec1_flags.sql`; S2 `dev_enable_dating.sql`, W10 guards | **Deviation risk** (R-6) |
| Q18 phone-only sign-in | S1 §6.8 seam only; S2 non-goal | Honoured |
| Q4, Q5, Q7, Q8, Q11, Q12, Q14–Q18, Q20 accepted | S1 W1–W5, W10; S2 W1–W9 | Honoured (see R-1, R-2, R-5, C-9) |

| # | Severity | Spec §/line | Issue | Required fix |
|---|---|---|---|---|
| R-1 | Minor | S1 §1.4 D2 (l.62) | Q8 was accepted as "Changed by Yaw · 12 Nov". S1 renders "Changed by Yaw - Tue, 12 Nov" (house date standard, weekday added). Same words, different separator. | Owner confirms D2 at sign-off. No other change. |
| R-2 | Minor | S2 §1.4 (l.73), §3.8 (l.664–666), §4.8 (l.905) | Q17 says "Exit hard-deletes everything in Dating". S2 keeps three survivors after exit: messages sealed 30 days (reconciled with Q15's evidence window), the never-introduce list **kept by default** (pre-ticked), and consent events for account life + 1 year. | List the three survivors as explicit Q17 exceptions in §1.3 for owner sign-off. Make "Keep my 'Never introduce me' list" opt-in (unticked) unless the owner prefers otherwise. |
| R-3 | Minor | S1 D17 (l.64), §4.3 W9 (l.602) | Restoring the two Opinions moderation notices isn't in Q10's list. It's a bug fix (live behaviour lost in `20260802120000`), not the deferred rule-and-appeal redesign. | Owner nod on D17. No spec change. |
| R-4 | Minor | S1 §3.1 S0 (l.161), §6.10 | "The Ghana listing goes live only after the Ghanaian legal opinion" (from 11 §7.2). Under Q1 "worldwide from day one", day one therefore excludes Ghana, and the UK until its OSA assessments clear. Consistent with the §7.2 gates, but not stated next to Q1. | State in S1 §1.3's Q1 row that the day-one worldwide listing waits on the GH and UK country gates (or ask counsel for a faster non-dating Ghana opinion). |
| R-5 | Minor | S1 §3.8 R3 (l.308) vs S2 §4.10 (l.1103) | Q7 "never shows Dating": S2 says S1 W3 removes `chat_couples_locked_screen.dart:379` "Meet someone in Dating mode". S1 only supersedes that screen under `flow_paths_v2` and doesn't list the file in §5.2, so the button survives with the flag off. | S1 §5.2 W3: list `chat_couples_locked_screen.dart` and remove the button unconditionally (not behind the flag). |
| R-6 | Important | S1 §2.5 (l.133); S2 §4.9 (l.946), §2.2 (l.136), W10 | Q19 needs "ON in development, gated in production". Neither spec names the development project. The repo has one `project_id`, no `attune_environment` marker and no documented staging project. S2's dev script **sets `attune_environment = 'development'` itself**, which switches off S2's own production guards (`publish_country_config` checks, the `fake`-provider refusal, `DEV-` refs) wherever it runs. S1's dev script turns on the hook-dependent flags the same way. If "development" is the single hosted project, ON in dev means ON in the project store builds use. | Name the dev project (separate project or branch). The marker is set once per project by the owner, never by a script. Both dev scripts `RAISE` unless the marker already reads `development`. S2 W10's readiness check fails unless the launch project reads `production`. |
| R-7 | Minor | S1 §2.5, §8 gates | S1's production gates are process only. `journal_ai_insights` (clinician gate) and `opinions_safety_v1` (reviewed lists) have no technical guard, unlike S2's W10 guards. | Optional: a `feature_flags` trigger or readiness RPC that refuses those two flags `true` in production without a recorded review reference. |

---

## 2. Interface consistency (names, signatures, waves, migrations, dependencies)

**Migration order — verified, no collisions.** Newest existing file: `20261024100800`. S3 W2 `20261025100000–100300` (reserved to `…100999`) < S1 `20261101100000 … 20261109100110` (each with its `…10_grants` twin) < S2 `20261201100000 … 20261210100010` < S3 W3 `20261230100000–100500`. All filenames are unique and the stated order holds. **Dependencies:** every cross-spec "depends on" is satisfiable in the build order and there is no cycle, except the gaps below (I-1, I-3, I-4, I-6, I-9).

**Names checked and matching:** `set_user_path_internal(uuid,text)`, `account_age(uuid)`, `get_my_age()`, `set_my_birth_date`, `account_birthdates`, `metric_counters` / `metric_key_prefixes` / key pattern, `users.path`, `dating_slot.dart` path, `dating_lock_store.dart` path, `support_resources` / `get_support_resources`, `_shared/csam_matcher.ts`, `safety-quarantine`, `media_scan_status`, `get_dating_home()`, `get_dating_availability()`, `dating_notify_requests`, `dating_gentle_wait_opens_at`, `pause_dating_for_relationship_user`, `couple_profiles`, `relationship_invite_acceptances`, `private.content_filter_verdict`, `admin_list_priority_reports`, `forum_reports`, `enqueue_forum_notification`, notification types `forum_content_removed` / `forum_posting_banned`.

| # | Severity | Spec §/line | Issue | Required fix |
|---|---|---|---|---|
| I-1 | Important | S1 §8 order (l.917), §4.7, §4.6 (l.639) | S1 lets W6 run "after W2" and W7 "after W1", alongside W3–W5. Migration timestamps are fixed by wave number (W4 `20261104` < W6 `20261106`), so landing W6 or W7 first makes W4/W5 sort before applied files. `supabase db push` then refuses them without `--include-all`, and local replay order differs from production. `otp_purge()` is also re-created by W4 and by W6 from their own bodies: out of order, W4 drops W6's fresh-start delete. | Fix S1's order to W1→W2→W3→W4→W5→W6→W7→W9→W10. Or assign timestamps at build time in landing order and always re-create shared functions (`otp_purge`) from the live body. |
| I-2 | Important | S1 §4.7 (l.647), S2 §4.9 (l.925), S3 §6.3 | The future-dated blocks will collide with ordinary `supabase migration new` hotfixes made in real time during the program. For example, a stories fix created 2026-11-03 sorts before an applied `20261105…` S1 file, so `db push` refuses it. Only S3 states a "sort after the newest applied" rule, and only for W3. | Put one shared rule in all three specs: any migration written while the program runs takes a timestamp after the newest applied migration. Reserved blocks are re-based at build time, keeping their order. |
| I-3 | Important | S1 §3.1 W1 preview (l.175), D15 (l.76); S2 header (l.17), W1 (l.1613) | S2 W1 deletes `app_public_config.dating_open_countries` and re-points only the A6 card and `dating_slot.dart`. A third reader isn't re-pointed: the **pre-auth Welcome Dating preview** ("Dating is open in {open countries}", fed by anon `get_public_app_config()` plus its prefs cache). S2 never re-creates `get_public_app_config()` (0 mentions), which still selects the deleted key. | S2 W1 re-creates `get_public_app_config()` to read `dating_open_countries` from `country_safety_config`, or drops the key and re-points the Welcome sheet to anon `get_dating_availability()`. Add the Welcome sheet to D15's reader list. |
| I-4 | Important | S1 §3.9 (l.350); S2 §4.10 (l.1020), W2 (l.1620), W3 | S1's Me Dating slot calls `get_dating_eligibility()`. S2 W2 "Replace"s it (Replace = dropped) with `get_dating_home()`, but the slot only becomes `DatingSection` in W3. Between S2 W2 and W3 the slot calls a dropped RPC. | S2 W2 keeps `get_dating_eligibility()` as a wrapper over `dating_eligibility()` until W3 drops it, or W2 re-points `dating_slot.dart` to `get_dating_home()`. |
| I-5 | Important | S1 §4.3 (l.526), §3.12; S2 W2 (l.1620), R13 (l.1717) | Two owners pause Dating on a path change. S1's `set_user_path_internal` calls `pause_dating_for_relationship_user` whenever the path **leaves** Dating, including Dating → Just for me, so the pause gets the relationship reason. S2 W2 adds an `AFTER UPDATE OF path` trigger with `pause_reason = 'path_change'`. Result: a double pause, and the wrong `pause_reason` on Dating → Just for me. | One owner. S2's trigger owns pauses on a path change. S1 W1 keeps `pause_dating_for_relationship_user` only for the → `relationship` transition (or removes it), and notes that the trigger lands in S2 W2. |
| I-6 | Important | S1 §4.3 (l.526) vs S1 §4.6 rule (l.639), §4.7 #10 | `set_user_path_internal` (W1) deletes from `couple_profile_drafts`, a **W5** table. That breaks S1's own rule ("a function never names a table a later wave creates"): every switch to Dating fails with 42P01 from W3 until W5. Migration 10 doesn't list re-creating it. | Drop the delete from the W1 body. Migration 10 (W5) re-creates `set_user_path_internal` from its live body with the draft delete added. |
| I-7 | Minor | S1 §4.3 W6 (l.576) vs S2 §3.3.2 (l.516), §6.3 (l.1382), W4 | S1 defines `place_account_hold(p_user uuid, p_kind text, p_ref text)` with no default. S2 calls `place_account_hold(user, 'age_review')` (3 places), so the 2-argument call fails. | S1: `p_ref text DEFAULT NULL`. |
| I-8 | Minor | S2 header (l.15), W9 (l.1670) | S2 says `set_user_path_internal` comes from S1 **W3**. S1 creates it in **W1**. | Correct to S1 W1. |
| I-9 | Important | S2 §3.13 (l.716–719), W5/W6 vs W8 (l.942, 1662) | Dating pushes start in W5 (daily digest) and W6 (message pushes, `me_checkin`), but the neutral type `me_update`, its `notification_config.dart` case and the Me tap are W8. Between W5 and W8 these pushes have no neutral type or tap route. `me_checkin` never gets a tap route: only the quiet-hours exemption is specified. | Move `me_update` (type, copy, routing) into W5, the first producer. Add a `me_checkin` → `/dating/checkin` case (behind the lock) to W6's `notification_config.dart` change. |
| I-10 | Important | S1 §4.3 (l.589), §4.4 (l.613), §4.5 (l.629); S2 D9 (l.431), §4.7 | CSAM checks on dating photos read two ways. S1 offers `media_scan_status()` "for Spec 2's synchronous photo approval" (the async queue) and also says `process-dating-photo` calls the matcher inline. S2 does inline first. S1's storage trigger also enqueues `dating-profile-photos`, so every dating photo is scanned twice, and a hit opens two holds and two escalations. The inline path has no service function to record a match (`complete_media_scan` needs a job id). | Choose inline (S2). S1 W7 removes `dating-profile-photos` from the trigger's bucket list and adds a service function for an inline match (same quarantine, `safety_review` hold, escalation and deletion path). Drop `media_scan_status` or keep it read-only. |
| I-11 | Important | S1 §4.5 `start-fresh-account` (l.627); S2 §6.3 (l.1383–1389) | Parking a dormant account rewrites `auth.users.phone` to `+999…`. At the 180-day purge, S2's `prepare_account_deletion` computes enforcement-record and block-pair HMACs from `auth.users.phone`, i.e. the `+999` number. Carry-over is lost, and `dating_block_hmacs` keyed to the real number never get `purge_after` (kept indefinitely). | S1 W6 stores the pre-park phone HMAC server-side (e.g. `users.parked_phone_hmac`). S2's `dating_phone_hmac_for_user` prefers it for parked accounts. Owner decides whether live Dating restrictions follow the number to the fresh account (it's assumed to be a new person). |
| I-12 | Minor | S1 §4.3 W5 (l.562), §5.3 (l.772); S2 §3.9 step 5 (l.676), W9 | Two mechanisms for the AU2 "The day you matched" chip: server `suggested_dates` in `get_couple_profile` ("Spec 2 W9 adds the match date") vs a client override of `aboutUsDateSuggestionsProvider` fed by `get_dating_link_origin`. S2 W9 lists neither explicitly. | Use the client override via `get_dating_link_origin` (keeps `couple_profiles` functions Spec 1-only and the never-typed contract intact). Delete `suggested_dates` from S1. |
| I-13 | Minor | S2 §4.3 `couple_how_we_met` (l.839), §4.7, W9 | "In the relationship export" requires re-creating `export_relationship` (last re-created by S1 W5) and wiring `dating_export_for_user` into the `build-data-exports` worker. Migration 15 and §4.7 list neither. | Add both to W9 with S1 R9's "re-create from the latest body" rule. |
| I-14 | Minor | S2 §2.1 (l.95, 108), §4.9 #5 (l.933) | W1's setup writers "check gates 1–4, 6 and 8" through `dating_eligibility`, which is created in W2 (gate 8 in W4). | State that W2 and W4 re-create the writers, or create `dating_eligibility` in W1. |
| I-15 | Minor | S1 §2.5 (l.133) vs S2 §4.9 (l.946) | The repo pattern is `supabase/sql/dev_enable_specN_flags.sql` (spec5/7/8 exist). S2 uses `scripts/dev_enable_dating.sql`. | S2: `supabase/sql/dev_enable_spec2_dating_flags.sql`. |
| I-16 | Minor | S2 §4.3 `enforcement_records.scope` (l.821) | `'opinions'` is reserved for "Spec 1 may write", but S1 never writes it. An Opinions ban therefore doesn't survive delete + re-register, while Q5 speaks of enforcement records generally. | Owner decides. If yes, S1 W9 writes `opinions`-scope records for a live ban in `prepare_account_deletion`. If no, drop the value. |
| I-17 | Minor | S1 §4.3 `normalize_for_filter` (l.595), W9 "goldens file shared with Spec 2" (l.964); S2 §6.1 normaliser (l.1334–1340) | Two new Unicode normalisers with different rules. S1 keeps ɛ/ɔ/ŋ and folds `$→s`. S2 folds ɛ→e, ɔ→o, ŋ→ng and `1→i/l`. S2 also never references the "shared" `unicode_normaliser_goldens.json`. A Twi term then matches in chat but not in D10 prompts (which use S1's filter), or the reverse. | One fold table and one goldens file, owned by S1 W9, with S2 W6 importing both. Or state why they differ and require reviewed lists in both spellings. |

---

## 3. Shared-file collisions

| File | Owners and order | Status |
|---|---|---|
| `app_router.dart` | S3 W1 forum block → S1 W2–W7 auth/onboarding/settings/safety blocks → S2 W3 dating block | Clear (C-8) |
| `home_screen.dart` | S1 W3 only (latch untouched) | Clear (N-2) |
| Onboarding (`profile_setup_step.dart`, `onboarding_gate.dart`, `onboarding_flow.dart`, `onboarding_store.dart`) | S3 W1 line 22 only; S1 W1/W3/W4 | Clear |
| `notification_config.dart` | S3 W1 forum cases → S1 W3 `journal_reminder` → S2 `me_update` | Distinct cases; ordering gap I-9 |
| Manual registry | S3 W1 unregisters `ForumDocs` → S1 W3/W5/W7/W9 register topics → S2 W3 Dating flags | **C-1** |
| Opinions files | S3 W1: `opinions_tab`, chooser, FAB, tag browse/search. S1 W9: compose, edit, quote, thread, `opinion_more_data` | Disjoint (C-7) |
| `auth_provider.dart` | none listed; both need it | **C-3** |
| `quick_exit_service.dart` | S2 W8 listed; S1 needs it but doesn't list it | **C-2** |
| Safety (`dating_lock_store.dart`, `MainActivity` `attune/safety`) | S1 W3 creates the store, S2 consumes it; S2 W8 the channel | Clear (C-2, C-5) |
| `main.dart` | S1 W2/W4/W10; S2 header injection unlisted | C-6 |

| # | Severity | Spec §/line | Issue | Required fix |
|---|---|---|---|---|
| C-1 | Important | S3 §7.4 (l.651) vs S1 §5.2 manual row (l.760), S2 W3 | S3's architecture test pins `getAllModules().length == 34` (35 today). S1 W3 registers "How you use Attune" (then About us, Support v2, Opinions safety), so S3's test goes red at S1 W3. | S3 asserts `getById('forums') == null` and `length >= 33` (the guard's floor), never an exact count. |
| C-2 | Important | S1 §4.8 (l.678–679); `quick_exit_service.dart`; S2 W8 (l.1095) | S1 promises "Ask 2 progress … cleared on quick exit" and "Dating lock … cleared on sign-out, quick exit", but doesn't list `quick_exit_service.dart`. S2 W8 edits it too. Worse, quick exit doesn't sign out: it sets `safety_requires_unlock`, wipes caches and exits. Clearing the Dating lock there removes the protection exactly when someone is looking over the person's shoulder. | S1: the Dating lock survives quick exit (cleared on sign-out only). List `quick_exit_service.dart` in §5.2 W4 for the Ask 2 wipe (one fire-and-forget call, like Together and Stories). S2 W8 appends its call after it. |
| C-3 | Important | S1 §4.8 (l.674–679); `lib/features/auth/providers/auth_provider.dart` (`signOut`, `SignOutHooks`) | S1 promises sign-out deletion of the partner first name, Ask 2 progress, the Dating lock and the home-state cache, but no spec lists `auth_provider.dart` (re-exported to Games through `auth_exports.dart`) or a `SignOutHooks` registration. The work is orphaned and the shared file is touched without a regression note. | S1 §5.2 W3/W4: register the wipes through the existing `signOutHooksProvider.beforeSignOut` from a new file (no edit to `auth_provider.dart`). Add a sign-out test and an entry in §5.6. |
| C-4 | Important | S2 §3.9 step 6 (l.677), §9 (l.1696) | S2 W9 adds "one card slot on Spec 1's Relationship home". For a linked couple that home is `ChatHomeScreen` (`lib/features/chat/presentation/screens/chat_home_screen.dart`), which neither spec owns or lists. S1 defines no such slot, and S2 §9 says couples chat is untouched. | S1 W3 adds a named, empty Relationship-home card slot (R3 states and the top of `ChatHomeScreen`), listed in §5.2 with a regression note. S2 W9 fills it. Or put the 30-day offer in Dating settings instead. |
| C-5 | Important | S1 §5.5 (l.787), §3.9 (l.353); S2 §3.0 (l.215), S19 (l.1512) | S1 caches `{path: 'dating', …}` in SharedPreferences and writes a `dating_lock_enabled` key. S2's S19 test asserts that no Dating data is in prefs or files after use. Either S2's test fails, or it must ignore S1's keys, and on a searched phone the cache reveals Dating use (10 S19). | S1 stores the path as an opaque code and uses neutral key names (no "dating" in keys or values). S2's S19 test allow-lists those keys. |
| C-6 | Minor | S2 §3.3.4 (l.525), R15 (l.1716) | The `x-attune-device` header is "added in the shared Supabase client set-up", i.e. `lib/main.dart`, which S1 edits in W2, W4 and W10. S2 doesn't list it. | Add `main.dart` (W4) to S2 §4.10 "Outside the feature folder" with a regression note, or use a Dating-scoped client (S-7). |
| C-7 | Minor | S3 §1 (l.43), §9 (l.712–713, 720), §10 F-1 (l.727) | S3 expects S1 W9 to add drafts / keep private, tag mute / new tags, thresholds, notice + appeal, renames, and forum-branch removal. S1 builds none of these (Q10; S1 §1.2, §5.7 "no rename, no forum-branch removal"). Harmless, since S3 W3 handles both cases, but stale. | Align S3 §1, §9 and §10 with S1 §5.7. |
| C-8 | Minor | S1 §5.4 (l.783) | S1 cites game-route line ranges in `app_router.dart` (`1003-1392` etc.) that move about 55 lines after S3 W1. | Cite game blocks by route name, or re-baseline after S3 W1. |
| C-9 | Minor | S1 W10 (l.970); S2 §1.5; S3 W1 FORUM.md banners | Q20 amendment ownership overlaps: the Dating docs (S2 W2–W7 vs S1 W10 "approved doc amendments") and FORUM.md §5 (S3 banners vs S1 W10). | S1 W10 covers Master Spec, AUTH_ONBOARDING_ENGINE, CR-06, the SOUL proposal and the "Forums retired" line. Dating docs belong to S2, FORUM.md to S3. |

---

## 4. Never-touch list

Games (`lib/features/games/**`), `ChatScreen` game entry points, `UniversalBubble` / `ChatTextField` parameters, the `auth_exports.dart` bytes, the `home_screen.dart` latch block and the `profiles.display_name` public read are **not edited by any spec**. All three carry CI or architecture guards (S1 R15, S2 §7.4, S3 §3.11).

| # | Severity | Spec §/line | Issue | Required fix |
|---|---|---|---|---|
| N-1 | Minor | S1 W10 (l.970) | Deleting `LoginScreenOptions` means editing `lib/core/utils/exports/export_screens.dart:43`, which `auth_exports.dart` re-exports to Games (`custom_truth_or_dare_list_screen.dart` imports the barrel). Deleting `UsernameCreationScreen` means editing `supabase_profile_repository.dart`. Neither is listed. `auth_exports.dart` stays byte-identical, but its export surface changes. | List both files in W10. Assert that no Games file uses the removed symbols, and run the Games tests. |
| N-2 | Minor | S1 §5.6 R1 (l.796) | The latch block isn't edited, but under v2 `_gateData.isComplete` changes meaning (`needs.isEmpty`), which changes the latch's input. Compliant in letter, and tests come first. | Add a test that the latch fires exactly once for a legacy account with `needs = [birth_date]`. |

---

## 5. Placeholders, contradictions, ambiguities

No `TBD` or `TODO` in any spec. Owner-supplied values (support and child-safety emails, `[DRAFT]` lists, vendors) are named and gated.

| # | Severity | Spec §/line | Issue | Required fix |
|---|---|---|---|---|
| A-1 | Important | S3 house rules (l.27), R22 vs S1 §7.1 (l.850), S2 §7.1 (l.1474) | S3: "Never run `scripts/local_pg_setup.sh` … against `attune_spec3a`" (the script runs `dropdb`/`createdb`). S1 and S2 tell implementers to run exactly `ATTUNE_TEST_DB=attune_spec3a scripts/local_pg_setup.sh`. One reading wipes the scratch database the other relies on. | Write one procedure into all three specs, e.g. a full rebuild only on a fresh `attune_specN`, per-file `psql -f` on `attune_spec3a`. |
| A-2 | Minor | S1 §3.1 (l.164–166), §5.1 (l.709) | The screen ids "W0 · Native splash" and "W1 · Welcome" collide with wave ids ("W2 … W1 screen"). | Rename the screens (e.g. WL0, WL1). |
| A-3 | Minor | S2 §3.9 step 3 (l.674) | "The first 50 messages (as each saw them)": masked or unmasked? This matters when the pair never swapped. | State: masked unless both swapped. |
| A-4 | Minor | S1 §4.5 (l.623) | `detectSelfDisclosure(…, {victimisation: <DRAFT flag>})` is an undefined parameter. | Name the flag and its default, or remove it. |
| A-5 | Minor | S1 §8 W1 gate (l.923) vs D12 (l.73) | The W1 gate says "no visible change", but the Journal pause (default off) stops live Gemini insights in production from W1. | Say so in the W1 gate and the release note. |
| A-6 | Minor | S1 §2.5 (l.135–147) | Flag combinations are unspecified. `flow_paths_v2` on with `flow_signin_v2` off leaves new legacy sign-ups without a DOB or EULA v2. W3's production gate is "none" while W2's is heavy, so W3 could plausibly be switched on first. | Declare the dependencies (paths ⇒ signin, couples ⇒ paths, couple_profile ⇒ couples) and compute effective flags in the providers. |
| A-7 | Minor | S2 R2 (l.1703) | "Keep the old `dating_mutual_match` case for one release, then remove": no wave owns the removal. | Assign it (S2 W10 or the S3 W3 release). |
| A-8 | Minor | all three headers | "Spec 1/2/3" reuse names from the earlier launch program (old Spec 2 = Safety PIN and quick exit; Spec 3a/3b/3c = lifecycle, deletion, export), and code comments cite them ("Spec 2 review C2"). | Add one disambiguation line to each header. |
| A-9 | Minor | S2 §2.1 gate 5 (l.103) vs D0 open date (l.268) | The gate tests `status = 'ended'`, but the window is closed by the archive sweep. For up to one sweep interval after `ended_at + 30 d`, D0 says "open" while the gate still returns `gentle_wait`. | The gate uses the window predicate (`ended_at > now() - 30 days`), not status alone. |
| A-10 | Minor | S1 §3.9 (l.353) | "Dating lock … shown when … a Dating enrollment exists", but the client can't read `dating_enrollments` after S2 W3 (direct SELECT revoked). | Expose a boolean through `get_my_home_state()` or `get_dating_home()`. |
| A-11 | Minor | S2 W3 (l.1627) | The D13 plain-icon offer "opens Settings" until W8, but Settings → App icon only exists from W8. | Hide the offer until W8. |

---

## 6. Security

Checked: every SECURITY DEFINER function's caller binding, every anon grant, and every client-writable column on the known list. `relationship_chat_open` (used by `couple_profiles` RLS) **does** check membership (`20261018100000:65-89`). `public.users` has no client DELETE, so a DOB or `created_at` reset by deleting the row isn't possible. `users.phone` and `users.mode` are closed by S1 W1's column grants, sync trigger and contract. `banned_until` is closed by the S1 W1 guard. Anon grants: `get_public_app_config`, `get_support_resources` and `get_dating_availability` expose public data (OK); `get_post_poll` keeps its existing grant (OK, S3 V3); `start-fresh-account` is OK (single-use 32-byte nonce, 15 min). Exceptions below.

| # | Severity | Spec §/line | Issue | Required fix |
|---|---|---|---|---|
| S-1 | **Critical** | S1 D5 (l.66), §4.2 (l.446), §4.4 (l.610); S3 §3.11 (l.294) | **`profiles.confirmed_violation_count` is client-writable** (`GRANT SELECT, INSERT, UPDATE, DELETE ON public.profiles TO authenticated`, `20260713120000:80`; column from `20260722120000:23`; no guard). S1's guard covers only `banned_until`, and S3 explicitly leaves the column alone. Any author can reset their strike count to 0 and never reach the 3-strike ban. After a ban ends, DELETE + re-INSERT of the profile resets it too. | The W1 guard also refuses client changes to `confirmed_violation_count` (INSERT forces 0) and refuses client DELETE of a profile with a count above 0 or a future ban. Add both to `identity_foundation_contracts.sql` with a mutant. |
| S-2 | Important | S1 §4.3 `bump_metric` (l.530); S2 §4.1, §6.9 | Granted to **anon** and authenticated, and accepts any key under a registered prefix (free text up to 80 characters). Anyone can inflate `signup_`, `invite_` or `dating.` counters and create unbounded rows (one per distinct key per day). S2 routes its `dating.*` keys through this function. | An exact-key allow-list for client-callable keys. Server events are bumped only by definer callers (no client grant). A daily row cap. Anon gets only a fixed set of pre-auth funnel keys. |
| S-3 | Important | S1 §4.5 `otp-delivery-intent` (l.625), §4.3 W2 (l.540), §7.1 (l.855) | The intent call is unauthenticated, keyed only by the phone HMAC, and "latest intent wins". Anyone who knows a number can switch that person's code to WhatsApp or voice (10 per hour per IP, any number of IPs). For a DV target without WhatsApp, that blocks sign-in. | Bind the intent to the requesting device: a client nonce sent with the intent and matched by the hook within a short window. Cap intents per number, and fall back to SMS when a non-SMS route fails. |
| S-4 | Important | S2 §4.4 (l.863), §4.2 (l.780) | §4.2 says service_role "sees nothing" of the special-category fields, but service-role `dating_export_for_user(uuid)` decrypts identity, seeking, faith and marital history for **any** user id, with no binding to an export request. Any edge function holding the service key can decrypt everyone. | Bind it to an export job (`…_for_job(p_job_id)`, which checks a pending export request for that user and marks it consumed). Correct §4.2's claim. |
| S-5 | Important | S2 §4.3 `dating_moderation_cases.sensitive_routing` (l.832), §6.4 (l.1408); `dating_introductions` / `dating_matches` | `sensitive_routing bool` means "this pair is not man–woman": a stored, unencrypted orientation signal that service_role can read. Introduction and match rows between two users disclose orientation the same way, and they're kept while both stay in Dating. Neither is listed as special-category data in §4.1 or §6.8. | Don't store the bit: compute routing inside the console's definer at read time. Revoke service_role on introductions and matches (access through functions, as with `dating_messages`). List both in the DPIA as derived special-category data. |
| S-6 | Minor | S2 §4.4 `get_dating_link_origin(p_relationship_id)` (l.861) | No membership check is stated (unlike `get_how_we_met`). | Members only, with the opaque `*_unavailable` error. |
| S-7 | Minor | S2 §3.3.4 (l.525) | A stable device id is sent on **every** request, Opinions included. That links anonymous Opinions activity to an id Dating stores (hashed), and API logs may keep the header. | Send it only from a Dating-scoped client. |
| S-8 | Minor | S1 §4.4 hook (l.612) | Fail-open: an internal error lets a held account (`age_review`, CSAM `safety_review`) receive tokens. This is a documented trade-off. | Keep it, but count each fail-open and alert on any. |
| S-9 | Minor | S1 D14 (l.75) | `profiles.relationship_status` stays client-writable, so "written once at the first path choice" only binds the server. | Note it, or add it to the guard. |

---

## 7. Feasibility (Flutter 3.29 · Riverpod 2.6 · Supabase PG17 · CLI 2.75)

No blockers found in: `normalize(…, NFKC)`, `pgp_sym_*` with `compress-algo=0`, temp tables inside definers, `FOR UPDATE SKIP LOCKED`, `request.headers` for `x-attune-device`, the `auth.users` trigger (precedent `20260705162000:111`), CLI `[auth.hook.*]` config, `supabase functions delete`, `db dump --data-only`, `SemanticsService.announce`, `Durations.*` and `Easing.*` tokens, Riverpod AsyncNotifier families. No `CREATE INDEX CONCURRENTLY` anywhere.

| # | Severity | Spec §/line | Issue | Required fix |
|---|---|---|---|---|
| F-1 | Important | S1 §4.4 `enqueue_media_scan` (l.613), W7 | This would be the first trigger on `storage.objects` in the repo (none exists). Hosted Supabase restricts `postgres` DDL on the storage schema, so the TRIGGER privilege on `storage.objects` isn't guaranteed, and the local bootstrap has no storage stub for it. | Spike on the hosted project before W7 (create and drop a no-op trigger). Fallback: enqueue from each pipeline's existing upload-intent or insert RPC, or a 1-minute sweep of `storage.objects` by `created_at`. |
| F-2 | Minor | S1 §4.4, §4.5 (l.631) | Both hooks (Send SMS, Custom Access Token) are available on Free and Pro per Supabase docs (the MFA and password hooks are the Team-only ones). The plan can't be confirmed from the repo, and `config.toml` has no `[auth]` section yet. On a background refresh refusal, supabase_flutter just signs the person out, so H1 appears at the next OTP sign-in, not "at the next refresh". | Confirm the plan in the dashboard. Add two checks to the W6 staging run: the hook error text reaches the client, and phone verify reports `authentication_method = 'otp'`. Reword H1's trigger. |
| F-3 | Minor | S1 §4.7, S2 §4.9 | S3 requires each atomic migration to carry its own `BEGIN; … COMMIT;` (the repo does this in 8 recent files). S1 and S2 are silent, yet multi-object files (e.g. S1 #1: five function re-creations, a trigger and grants) would half-apply under local `psql -f`. | Adopt S3's rule in S1 and S2. Forbid `CONCURRENTLY` in those files. |
| F-4 | Minor | S1 §5.1 (l.707), W6; S2 §6.7 (l.1433) | Apple Declared Age Range needs the iOS 26 SDK (Xcode 26) and an `#available(iOS 26, *)` guard. Debug on iOS 26 devices needs a newer Flutter than 3.29 (release builds are fine). `UIScreen.isCaptured` is deprecated in favour of `sceneCaptureState`. | Weak-link the framework, state the toolchain, and run device checks in release mode. Use `sceneCaptureState` where available. |
| F-5 | Minor | S1 §3.6 X1 (l.270) | "Survives reinstall" holds for the iOS Keychain. Android Auto Backup restores only if a backup has run (about daily, on Wi-Fi and charging). | Soften the claim to "usually survives". |
| F-6 | Minor | S2 §6.4 (l.1393) | The Flutter web console in the same package builds only if it never imports mobile-only plugins (Mapbox, OneSignal, platform channels). | The console imports only `lib/console/**` plus a web-safe Supabase client. CI runs `flutter build web -t lib/console/main_console.dart`. |

---

## 8. Wave counts and sizing

**Counts:** S1 = **9** (W1–W7, W9, W10; W8 held empty, per Q9). S2 = **10 + W11 later**. S3 = **3**. These match 11 §11 with Q9 applied.

| # | Severity | Spec §/line | Issue | Required fix |
|---|---|---|---|---|
| W-1 | Important | S1 §8 (l.919–973) | Too big for one batch of 3–4 tasks: **W1** (6 migrations, client, 3 edge changes), **W2** (Welcome/G1/X1, A1–A5/N1, OTP server + hook, code field + autofill, motion and large-text foundations, EULA v2, router), **W3** (home state, keyed shell, A6, Relationship space, Me, Dating slot and lock, switching, push asks, reminders), **W6** (hook, dormancy, fresh start, native age signals, DOB correction, child report, CSAE), **W9** (filter, 6 writers, at-risk reason, review queue, notices, Journal check), **W10** (audit, clamp, motion, RTL, first frame, size, dead code, docs). | Split with letter suffixes so "S1 W9" and "S1 W10" citations stay valid (table below). |
| W-2 | Important | S2 §8 (l.1611–1680) | Too big: **W1** (7 migrations), **W3** (all of D1–D13, section, routes, repository, photo pipeline), **W5** (generation, Today, digest, never-introduce UI, signals, fairness), **W6** (chat, worker, lexicon, guided conversation, meeting kit), **W7** (reports, appeals, console web app, runbook, LE policy). | Split as below. |
| W-3 | Minor | S1 W4, W7; S2 W4, W8; S3 W1 | Borderline (4–5 tasks). S3 W1 has 10 ordered steps but they're mechanical. | Split S1 W4 and W7, S2 W4 and W8 as below. Run S3 W1 as 4 tasks: (1) push routing + router; (2) Opinions shell + chooser/FAB + tags; (3) manual, copy, l10n, FORUM.md; (4) deletions + tests. |

**Suggested splits**

| Spec · wave | Split |
|---|---|
| S1 W1 | **W1a** users/profiles lockdown (incl. S-1), dating-function re-creation, client upsert + `ensureUserRow` (one release) · **W1b** birthdates, paths, home state, withdraw v2, `HomeState` model/store · **W1c** metrics (S-2), flags + public config, health + purge, Journal pause, scoped invite key, dev script |
| S1 W2 | **W2a** motion tokens, `SharedAxisStep`, `AllowLargeText`, router allow-list, Welcome + previews, G1, X1 · **W2b** A1–A5, N1, draft store, validators, EULA v2, `PendingSignUp`, LoginProfile · **W2c** migration 7, `otp-delivery-intent` (S-3), `send-sms-hook`, code field + autofill |
| S1 W3 | **W3a** `homeStateProvider`, keyed `HomeScreen` (tests first), A6 · **W3b** `RelationshipSpaceScreen`, `MeHomeScreen`, Dating slot + lock, Relationship-home card slot (C-4) · **W3c** How you use Attune, contextual push asks, journal reminders, manual topic |
| S1 W4 | **W4a** migration 9, `accept-invite` rewrite, inviter age check, contracts · **W4b** R1/R2/R4, RI-1–RI-4, day 7/30, Install Referrer, Ask 2 save-as-you-go |
| S1 W6 | **W6a** holds, access-token hook, dormancy, fresh start, DM1/DM2/H1 · **W6b** native age signals, under-18 hardening, DOB correction · **W6c** child-safety report, real addresses, CSAE content |
| S1 W7 | **W7a** resources v2, grief branch, youth link, release check · **W7b** CSAM scan (after the F-1 spike) |
| S1 W9 | **W9a** normaliser, verdict, 6 writers, client errors · **W9b** at-risk reason, support link, review queue v0, restored notices · **W9c** Journal `self_disclosure`-first check + writer card |
| S1 W10 | **W10a** large-text audit + goldens, clamp · **W10b** reduce motion, RTL, first frame, app size · **W10c** dead code (N-1), doc amendments |
| S2 W1 | **W1a** HMAC from `auth.users`, enforcement survival, deletion carry-over, canaries · **W1b** country config, session context, availability, S1 re-points (I-3) · **W1c** encryption, profile fields, writers, own reader · **W1d** lifecycle v2, never-introduce data, dev script |
| S2 W3 | **W3a** RPC-only repository + grant revoke, route group + lock, `DatingSection`, not-open/notify · **W3b** D1–D8 · **W3c** D9 photos (CSAM-first, child labels), D10, D12/D13, settings, docs |
| S2 W4 | **W4a** migration 10, `dating-verification` seam, D11 · **W4b** trusted devices, header, re-verification |
| S2 W5 | **W5a** drops, config v2, hard filters, generation tick, determinism · **W5b** Today, card, photo URLs, match moment, digest + `me_update` (I-9) · **W5c** never-introduce UI, other countries, signals, fairness |
| S2 W6 | **W6a** messages, send/read, masking, swap, chat screen · **W6b** outbox worker, normaliser (I-17), lexicon, cards · **W6c** guided conversation, timebox cards, meeting kit + `me_checkin`, close kindly, purge |
| S2 W7 | **W7a** reports v2, evidence, corroboration, restrictions, appeals, carry-over, restricted screens · **W7b** console + `dating-moderation` + audit + SLA · **W7c** runbook, LE policy, escalations, transparency |
| S2 W8 | **W8a** quick exit, `FLAG_SECURE`, capture blur, lock on taps and links · **W8b** plain icon, traveller detection |

---

## Controller rulings for the fix pass (2026-10-24)

- **R-6 (owner):** the current project is the dev/testing project until launch, with everything ON. A server-side `app.settings.attune_environment` defaults to `'development'` now, and only the owner sets it to `'production'` at launch; production mode enforces the gates. **No spec script sets it.**
- **I-1 / I-2, migration timestamps:** specs list each migration by **name, purpose and order within its wave only**. The implementer assigns the real timestamp when the wave is built, in the actual build order (always later than every applied migration). Waves may then run in any dependency-valid order.
- **I-6:** `set_user_path_internal` (S1 W1) must not reference tables that only exist from a later wave. Guard it with `to_regclass(...)` checks, or move the clean-up into the wave that creates the table.
- **C-2 / C-3, ownership:**
  - **Spec 1 owns `quick_exit_service.dart` and the `auth_provider.dart` sign-out path.** It adds a generic, ordered "device wipe registry" (bounded, with its own try per entry, as in the stories Wave 2/4 wipes).
  - **Spec 2 registers its Dating wipe entries in that registry**, and never edits those files directly.
  - **Quick exit never clears protective settings:** the Dating lock, the Safety PIN and the discreet icon.
- **C-4:** the `ChatHomeScreen` card slot for the couple link belongs to Spec 2 W9, which may add a card to the conversations home cards list. The Games entry points stay untouched.
- **C-5 / S19:** the on-device path cache never stores `'dating'`. It stores the tab layout (`chat` or `me`); Dating state is always read from the server.
- **A-1:** never run `local_pg_setup.sh` (it drops the database) on `attune_spec3a`. Use the non-destructive harness steps. S1 and S2 must stop instructing it.
- **C-1:** S3's manual-module count test asserts *forum topics are absent*, not an exact total of 34.
- **Wave splits:** apply the letter-suffix split table (W-1/W-2). Each wave is ≤ ~3–4 tasks, and existing "S1 W9" / "S1 W10" citations survive.
- **All Critical and Important findings are fixed, plus every Minor that applies to your spec.**

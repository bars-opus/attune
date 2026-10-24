# Spec 2: Dating Mode — design

**Date:** 2026-10-24 (fix pass after the cross-spec review, same day) · **Status:** design for owner review (not a plan, not code) · **Size:** 10 waves, built as 23 batches with letter suffixes (W1a–W1d, W2, W3a–W3c, W4a–W4b, W5a–W5c, W6a–W6c, W7a–W7c, W8a–W8b, W9, W10; §8), plus voice calls later (W11). A citation of a wave number alone ("W3") means all of its batches.

**Which "Spec 2".** This is Spec 2 of the 2026-10-24 flow and dating program (Spec 1 = app flow and identity, Spec 3 = forum removal). It is not the earlier launch program's "Spec 2" (the Safety PIN and quick exit). Code comments such as "Spec 2 review C2" refer to that earlier program.

**Sources, in precedence order**
1. `docs/superpowers/research/2026-10-24-flow-dating-research/11-synthesis-decisions.md` **§12 owner rulings** (override everything), then §0–§1, §3.3, §3.5–§3.7, §4, §7–§11.
2. The research it cites: 01, 02, 03, 04, 08 (corrections win over the originals), 09, 10.
3. Today's code and docs: `lib/features/dating/**` (15 files), the 20 `supabase/migrations/*dating*` files plus the dating parts of `20261018100300_lifecycle_hardening.sql`, `20261018110000_chapters_deletion.sql`, `20260931120000_vault_backed_settings.sql` and `20260907120000_register_scheduled_jobs.sql`; `supabase/functions/{upload,process}-dating-photo`, `verify-dating-profile`; `lib/architecture/DATING_*.md`; `docs/reviews/DATING_REVIEW_FABLE.md`.

**Conventions.** `11 §4.6` = file 11, that section. `10 S8` = risk scenario 8. `S1 W3b` = Spec 1, batch W3b (`S1 W3` = all of Spec 1's W3). `W5` alone = this spec's wave 5. "Dating chat" always means the new, separate chat in §3.6, never `ChatScreen`. Copy in quotation marks is the exact English string; `{Name}` style tokens are filled at runtime. Every displayed date uses `MyDateFormat` (date and info joined with `MyDateFormat.join`). Copy uses names, never pronouns. All new strings go into `lib/i10n/app_en.arb` under the `dating_` prefix; other locales fall back to English until translated.

**Depends on Spec 1** (`docs/superpowers/specs/2026-10-24-app-flow-identity-design.md`). The whole of Spec 1 is built before this spec's W1 (build order 11 §11), so a Spec 1 wave cited below says which Spec 1 batch owns an object, not a scheduling constraint inside this spec. Spec 1's waves use letter suffixes too (W1a–c, W2a–c, W3a–c, W4a–b, W5, W6a–c, W7a–b, W8 empty, W9a–c, W10a–c); a bare "S1 Wn" means the whole group. This spec uses Spec 1's objects by their names and does not redefine them:
- **S1 W1a (lockdown):** `users` column grants with `phone` written only from `auth.users`; `users.path`, `path_previous`, `path_chosen_at` and `phone_released_at` columns; `users.mode` retired with all of its writers, including the five dating functions that write it today.
- **S1 W1b (metrics, birthdates, holds, paths, home state):** `metric_counters`, `metric_key_prefixes` (server prefixes; this spec inserts `dating.`), `metric_client_keys` (exact client keys; this spec inserts none), `private.bump_metric_internal` (definer callers) and `bump_metric_server` (edge functions, service role); `account_birthdates` with `set_my_birth_date`, `get_my_age()` and the ungranted `account_age(uuid)`; `account_holds` with `place_account_hold(p_user, p_kind, p_ref DEFAULT NULL)` (this spec always passes all three arguments); `set_my_path` and the ungranted internal path setter `set_user_path_internal(p_user uuid, p_path text)`, which makes the one Dating pause on a change to `relationship` (Spec 1 D18); `get_my_home_state()` with `dating {enabled, enrolled}` from the seam `private.dating_home_summary(p_user)`, which this spec re-creates (W1b).
- **S1 W1c (environment, flags, public config):** `private.attune_environment()`, `get_attune_environment()` (service role, for edge functions) and `private.assert_development_project()` (for dev scripts); `app_public_config`, the open-country seam `private.dating_open_countries()` (re-created here in W1b) and `get_public_app_config()`.
- **S1 W2a:** the `AllowLargeText` wrapper and the motion tokens of 11 §2.0. **S1 W2b:** EULA v2.
- **S1 W3a:** the keyed home shell and **Spec 1's device wipe registry** (Spec 1 §5.8: `lib/core/device/device_wipe_registry.dart`, `DeviceWipeRegistry.instance.register(DeviceWipeEntry(id, order, moments, run, bound))`, `WipeMoment { signOut, quickExit }`, each entry in its own `try` with its own time bound, as in the stories Wave 2/4 wipes). This spec **registers its Dating entry there, adding exactly one line (`registerDatingDeviceWipes()`) to `lib/app/device_wipes.dart`, and never edits `quick_exit_service.dart` or `auth_provider.dart`** (§6.7). Quick exit never clears protective settings: the Dating lock, the Safety PIN and the plain app icon. The on-device home cache stores only the tab layout (`chat` or `me`) and never the word "dating" (C-5, Spec 1 D20).
- **S1 W3b (Relationship space and Me):** Tab 2 = **Me** on the Dating and Just-for-me paths; **Dating is a section inside Me** (`lib/features/me/presentation/widgets/dating_slot.dart`, which calls no Dating RPC); the optional **Dating lock** setting (`lib/features/safety/data/dating_lock_store.dart`, stored under the neutral key `me_section_lock`, shown in Settings when the path is Dating or `get_my_home_state().dating.enrolled` is true; a sign-out-only wipe entry). **S1 W3c:** Settings → How you use Attune and the confirmation before an invite pauses Dating.
- **S1 W5 (About us):** `couple_profiles`, `update_couple_profile`, the AU2 chip slot and `aboutUsDateSuggestionsProvider(relationshipId)`, which W9 overrides on the client (I-12).
- **S1 W6a (holds enforced, recycled numbers):** the dormancy rule and the access-token hook that enforces `age_review` and `safety_review` holds across the whole app; `users.parked_phone_hmac`, the real number's HMAC that `consume_fresh_start` writes before a dormant account is parked (I-11, §6.3). **S1 W6b:** the protected DOB correction path.
- **S1 W7a:** `support_resources` with `get_support_resources`. **S1 W7b:** `_shared/csam_matcher.ts`, the `safety-quarantine` path and Spec 1's inline-match path: the shared helper `_shared/csam_match_path.ts` `quarantineAndRecord()` with the service function `record_inline_csam_match` in place of `complete_media_scan` (same quarantine, `safety_review` hold, escalation and deletion). Dating photos are scanned **once, inline**, by `process-dating-photo` (I-10); `dating-profile-photos` is not in the bucket list of Spec 1's `storage.objects` trigger (or its sweep fallback), and Spec 1 has dropped `media_scan_status`.
- **S1 W9a:** the pre-post content filter (`private.content_filter_verdict`, which D10 calls for prompts) and the one shared normaliser (I-17): `supabase/functions/_shared/unicode_normaliser.ts` (`baseForm`, `matchForm`), the shared fold table `_shared/unicode_fold_table.json` and `supabase/tests/fixtures/unicode_normaliser_goldens.json`. The Dating chat imports them; it has no fold table of its own. **S1 W9b:** review queue v0.
- **Public config (I-3, Spec 1 D15).** Spec 1's interim `app_public_config.dating_open_countries` row is read only through one seam, `private.dating_open_countries() → text[]`, exposed as `config.dating_open_countries` in anon `get_public_app_config()`. Its readers are the pre-auth **Welcome Dating preview** (and its prefs cache), the A6 path card, and Me's `dating_slot.dart` until W3a. W1b re-creates the seam from its live body to read `country_safety_config` (same shape: sorted ISO alpha-2 codes), then deletes the row. `get_public_app_config()` itself and every client reader stay unchanged.

**Repo rules that apply to every wave.**
- Games are not touched. Only new files are formatted (`dart format` never runs on an existing file).
- **Local SQL (A-1):** only against the scratch database `attune_spec3a`, never `attune_test`, and **never with `scripts/local_pg_setup.sh` or `scripts/local_pg_grants.sql`** (the setup script runs `dropdb` / `createdb`). Apply each new migration and then its grants twin with `psql -X -v ON_ERROR_STOP=1 -d attune_spec3a -f <file>`, and run each test file the same way. CI does the full rebuild.
- **Migrations by name and order only (I-1, I-2).** §4.9 lists each migration by name, purpose and order within its wave. The implementer assigns the real timestamp when the wave is built, in the actual build order, always later than every migration already applied (including hotfixes written meanwhile). Waves may then run in any dependency-valid order. Each migration has a grants twin `<next version>_<name>_grants.sql` (§4.9); every grant and revoke goes in the twin (the local harness and Supabase grant every table to `authenticated` after migrations), and the twin gets an `\i` line in `scripts/local_pg_grants.sql` for CI.
- **Atomic and replay-safe (F-3).** A migration that must be atomic carries its own `BEGIN; … COMMIT;`. No `CREATE INDEX CONCURRENTLY`. A function never names a table that a later wave creates (guard with `to_regclass(…)` or move the step into that wave). A shared function (`prepare_account_deletion`, Spec 1's seams `private.dating_open_countries` and `private.dating_home_summary`, `export_relationship`, `scheduled_notifications_quiet_guard`, `dating_eligibility`, `publish_country_config`) is always re-created from its **live** body plus this wave's change, never from the body printed in an older migration.
- **Environment (R-6, Q19b).** The current Supabase project (`mrgjtyacrzfylawyzabm`) is the development and testing project until launch, with everything ON. The server setting `app.settings.attune_environment`, read only through Spec 1's `private.attune_environment()` (and `get_attune_environment()` for edge functions), reads `'development'` while unset, and `'production'` when set to `production` or to any unrecognised value (a typo fails closed). **Only the owner sets it to `'production'`**, at launch (`ALTER DATABASE postgres SET app.settings.attune_environment = 'production'` on whichever project becomes production). Production mode is when this spec's technical gates are enforced. **No script, migration or edge function in this spec ever sets it.**

---

## 1. Goal, non-goals, owner rulings

### 1.1 Goal

Attune helps single adults meet a few well-filtered, verified people, reach a first meeting soon where both feel responded to, and then *decide* (not slide) into what comes next. Success is leaving Dating together, or leaving it well (11 §4; 03 (e)). Concretely, this spec delivers:
- Dating open in **Ghana** (Greater Accra and Ashanti first, men–women introductions only) and the **United Kingdom**, behind a country-aware configuration that can open any country later with a checklist. Everywhere else: "Dating isn't open in {country} yet" and "Tell me when it's here". The rest of the app is worldwide (Spec 1).
- A setup of one question per screen (D0–D13), a real age and identity check for every Dating user, up to 3 introductions a day matched on what people can do together and what they say they value, double opt-in, a separate text-only chat with contact masking and deterministic scam and sextortion support, explainable enforcement with one human appeal, device discretion, and a mutual "Become a couple" link into the Relationship path.
- Everything behind flags. **All flags are ON in development** (the current project, Q19b) for full testing; production switch-on waits for the owner to set the project to production mode and for the §8 W10 gates.

### 1.2 Non-goals

Not built in this spec, on purpose (11 §8 unless noted):
- Swipe decks, browsing or searching the pool, "likes you" lists, profile-view counts, admirer counts, rewind.
- Paywalls of any kind (replying, matching, being introduced, safety), boosts, per-introduction fees.
- Compatibility percentages, bands, trait distance, attachment, personality, communication-style, conflict-style or love-language matching. Quiz answers are never read by Dating.
- Ranking on popularity, activity, reply speed, attractiveness, or anything derived from photos.
- Read receipts, typing indicators, "online now" or last-active in the dating chat.
- Streaks, match counters, "It's a match!" bursts, confetti, urgency timers, countdowns.
- Media, links that open, voice notes or video in the dating chat in v1. **Voice calls are W11, later.**
- Stored face templates, kept selfie videos, kept ID images.
- Fields for ethnicity, tribe, caste, income, job, education, politics, height, body type, weight, health, HIV or zodiac; GPS, distance or neighbourhood.
- Casual or non-monogamous intentions; guardian or wali accounts; a duress PIN.
- Same-gender introductions in Ghana or any Tier 1 or Tier 2 country (reconsidered only after the gates in §2.4).
- LLM safety detection, AI-written messages, AI onboarding. Dating chat is never fed to any AI pipeline.
- Apple or Google sign-in (Q18: phone only). Opinions changes (Q9 deferred). Forum removal (Spec 3).
- Any "is my partner on Dating?" lookup, partner signal, or answer that confirms an account exists.

### 1.3 Owner rulings that bind this spec

| Ruling (11 §12 / §10) | What it means here |
|---|---|
| **Q1 Launch** | Dating opens in Ghana (Greater Accra + Ashanti first, men–women) and the UK. Everywhere else: "Dating isn't open in {country} yet" + "Tell me when it's here". Country-aware config with tiers, per-country region lists and per-country switches (§2.2). |
| **Q2 Same-gender** | Off in Ghana and every Tier 1/2 country: server-enforced, nothing sent, logged or stored, an honest note and resources. On in the UK and other safe countries (§2.4). |
| **Q3 Age check** | Liveness + facial age estimation (challenge age 25) + CompareFaces against the photos + ID fallback (Ghana Card) + human review within 24 h, for every Dating user. A UK-recognised estimation vendor plus Smile ID or equivalent, behind a vendor seam (§3.3, §4.7). |
| **Q4, Q5** (accepted) | The typed DOB (Spec 1) never unlocks Dating. Enforcement records, blocks and anonymised reports survive deletion as phone HMACs computed from `auth.users`, kept 2 years (§6.3). |
| **Q6 Navigation** | Dating is a section inside **Me**, with the optional Dating lock (Spec 1 owns the shell and the setting; this spec fills the section and makes every Dating route honour the lock). |
| **Q12** (accepted) | The gentle wait applies only after a relationship ended inside Attune; it lasts the 30-day ending window (shorter if both seal) plus a private 3-question reflection; Healing offered, never required; no score. The ex-exclusion is mandatory. The Healing predicates are replaced everywhere they occur (§2.1, §4.10). A clinical note is recorded (W2 gate). |
| **Q13 Dating rules** | Four intentions: Marriage / A committed relationship / Companionship, at my own pace / Not sure yet. No casual. Anyone currently married in any form, or separated and not divorced, is excluded (attestation + a "hiding a relationship" report). Faith optional and region-aware with a "must share" dealbreaker. Age range 18–99; default at most +7 years for ages 18–20. Photos after mutual interest available from account day 30. |
| **Q14** (accepted) | At most 3 introductions a day at a chosen time; at most 6 waiting; new introductions pause at 3 open pre-date chats; 7-day lifetime with no countdown; 72 h cool-off from account creation; cross-border only for verified accounts 14+ days old; honest empty days. |
| **Q15** (accepted) | Text-only chat; masking until **both** tap Swap (offered from 72 h); 30-day evidence window; joint "Keep our first messages"; voice later. |
| **Q16** (accepted) | The restricted person sees the category and gets one appeal to a different human; interim holds only for corroborated P0 reports; no automatic bans. |
| **Q17** (accepted) | Exit hard-deletes Dating data; the export includes your own Dating data. **Exceptions for owner sign-off (R-2)**, each stated on the Leave screen (§3.8): (1) conversation messages stay sealed for the 30-day evidence window, then are deleted (reconciles Q17 with Q15); (2) the "Never introduce me" list is kept **only if the person ticks** "Keep my 'Never introduce me' list" (unticked by default); (3) consent events are kept for the account's life + 1 year after exit, as proof of consent and withdrawal (counsel confirms the minimum, W1 gate). Safety records about the person (live restrictions, blocks, reports) follow Q5 and Q16, not Q17. |
| **Q19 People / switch-on** | Built and switched ON in development; production waits for the gates: Ghana legal opinion on the reconsidered bill, DPC registration, UK OSA assessments + highly effective age assurance, DPIA, pen test, named moderator and safety owner, clinician / cultural / LGBTQ+ / DV reviewers. |
| **Q19b Test project** (after the cross-spec review) | The current project `mrgjtyacrzfylawyzabm` is development until launch: everything ON, Dating included. `attune_environment` reads `'development'` unless the owner has set it to `'production'`; no script sets it. Production-mode guards (`publish_country_config` checks, the `fake`-provider refusal, the `DEV-` review-ref refusal) apply only once the owner flips it, and W10's readiness check is red until the launch project reads `'production'`. |
| **Q20** (accepted) | The amendments to `DATING_MODE_SPEC.md` §2, §2.1, §3.1, §4.1, §6.1, §6.4, §8 and `DATING_CHAT_SAFETY_SPEC.md` §4.1, §5.1 are approved; §1.5 lists them with this spec's consequential edits. |

### 1.4 Where sources differ, and what this spec does

| Difference | This spec | Why (one sentence) |
|---|---|---|
| Brief says "prefill 'together since'"; 11 §2.5 AU2 and §4.7 say a match-date **chip, never pre-filled** | A tappable match-date chip in About us (Spec 1's slot); W9 supplies the date | 05 §5.0 forbids pre-filling profile answers from app data, and one tap is no real cost. |
| "Exit hard-deletes … messages" (11 §4.8.5) vs reports that survive unmatch, block and deletion with a 30-day evidence window | Exit and account deletion hard-delete the profile, preferences, sensitive fields, photos, prompts and settings at once; **conversation messages stay sealed for the 30-day evidence window, then are deleted** | Otherwise leaving becomes an evidence-destruction tool, which is exactly 10 S1 step 10 and S8 step 7. |
| 01 Impl 4 suggests a "Photo verified" mark | **No public badge** | 11 §3.5 and 04 §2.7 #6: a badge invites over-trust. |
| 01 proposes "Long-term, taking it slowly" | **"Companionship, at my own pace"** | Owner ruling Q13. |
| 11 §4.6 lists `meet_private_pressure` and `child_access` as "later (P1)" | Built in **W6** with the rest of the lexicon | Everything ships before production, and S21/S22 are pre-launch P1 items. |
| `DATING_CHAT_SAFETY_SPEC.md` §2.4 shares the couples transport, including receipts, typing and presence | Dating chat has **its own screen, widgets, table, outbox and worker**; no receipts, typing or presence | 11 §8 bans them in dating chat, and sharing `ChatScreen` code risks Games (06 §2.8). |
| `DATING_CHAT_SAFETY_SPEC.md` §3.4 reuses the couples normaliser | Dating gets **its own** Unicode-safe normaliser module; `chat_safety.ts` (couples) is untouched | The couples normaliser drops every non-ASCII letter (10 F-5); fixing it in place would change couples detection, which is out of scope. |
| Day-21 card "with no plan" (11 §4.6) | Suppressed once **either person taps "We met"**; meeting plans are never stored on the server | Storing a plan's time and place is unnecessary location data; "We met" is the signal that matters. |
| `dating_age_verifications.birth_date` holds a DOB today | The DOB lives **only** in Spec 1's `account_birthdates`; the verification table keeps methods and pass/fail | 04 C3: the sign-up DOB is a declaration, and the assurance record must never become a second DOB store. |
| Mutual match pushed at once today ("New mutual match") | One neutral **daily digest** at the person's drop time | 03 (d): at most one dating notification a day; the lock screen must never say "match". |

### 1.5 Doc amendments this spec applies (W2–W7, approved under Q20)

- `DATING_MODE_SPEC.md`: §2 (eligibility row, launch gate, profile row); §2.1 (the gate-erosion clause now names the gentle wait and the trust friction instead of the readiness threshold; the clinical note is linked); §3.1 (eligibility source: ended-in-Attune window, no Healing path); §3.2 (decisions: terms, opt-in, special-category consent, age assurance result; no age checkbox, no historical-data consent); §4.1 (profile fields = §3.2 of this spec); §4.2 ("Why you two were introduced" replaces "Alignment preview"); §6.1–§6.5 (stated-values ranking, §5 of this spec); §6.4 (daily per-country cohorts); §7 (neutral digest); §8 (category shown + one human appeal; corroborated P0 holds); §13.2 (retention table §4.8); §17 (blocking decisions updated). Version 2.0.
- `DATING_CHAT_SAFETY_SPEC.md`: §1.4 and §2.4 (own screen, no receipts/typing/presence, no shared transport); §3.1 (new families); §3.4 (own normaliser); §4.1 (masking and the swap card are server-decided presentation rules; delivery stays fail-open); §5.1 (report-driven interim holds for corroborated P0 only; phrase triggers still never restrict); §5.2 (new categories); §7 (30-day evidence window). Version 2.0.
- Ownership (C-9): the Dating docs listed here belong to this spec; Spec 1 W10c's doc amendments don't touch them.
- `DATING_MODE_REVIEW_AND_GATES.md`, `DATING_MODE_RELEASE_READINESS_CHECKLIST.md`: replaced by §8's gates. `DATING_MODE_CULTURAL_REVIEW_PACKET.md`: per-country, plus LGBTQ+ and DV reviewers. `DATING_MODE_CLINICAL_REVIEW_PACKET.md`: the gentle-wait note. `DATING_MODE_REVIEWER_OUTREACH_TEMPLATES.md`: adds the LGBTQ+ (West African context) and DV templates. `DATING_MODE_DATING_CHAT_SAFETY_PLAN.md`: marked superseded by the chat spec v2.

---

## 2. Eligibility and country model

### 2.1 Eligibility (one server predicate)

`public.dating_eligibility(p_user uuid, p_scope text DEFAULT 'candidate') returns text` returns the **first failing reason** or `'eligible'`, checked in this order. Every RPC that gates Dating calls it; the client only ever sees the opaque reason through `get_dating_home()` (§4.4). `p_scope = 'setup'` skips gates 5 and 7 (below).

**Built in steps (I-14).** W1b creates it with gates 1–4 and 6, so W1c's setup writers can call it. W2 re-creates it from its live body adding gate 5, W4b adds gate 8 and W8b adds gate 7. Until a gate's wave lands, the function simply doesn't check it.

| # | Gate | Rule | Reason code | Replaces |
|---|---|---|---|---|
| 1 | Feature | `dating_mode_enabled` flag | `feature_unavailable` | — |
| 2 | Account | `account_age(p_user) >= 18` (Spec 1); `auth.users.phone_confirmed_at IS NOT NULL`; EULA v2 accepted | `account_unavailable` | the "I confirm I am 18" checkbox |
| 3 | Standing | `dating_account_in_good_standing` v2: not banned in Auth; no live `dating_account_restrictions` row; no active `enforcement_records` row for the phone HMAC; no unresolved Spec 1 `account_holds` row (`age_review`, `safety_review`) | `account_unavailable` | — |
| 4 | Relationship guard | `dating_has_relationship` (pending, active or paused) is false (kept as is) | `relationship_active` | — |
| 5 | Gentle wait | No relationship of theirs is inside its ending window: `status = 'ended' AND ended_at > now() - interval '30 days'` (the window of `20261018100000`; it becomes `archived` early when both seal or either starts a new relationship). The predicate uses the window, not the status alone, so the gate opens on the D0 date even before the archive sweep runs (A-9) | `gentle_wait` | `dating_healing_gates_hold` (score > 70, every Healing stage, 8 weeks) |
| 6 | Country | The profile's Dating country has `dating_enabled`; the region is in `open_regions` (or `open_regions` is null) | `country_closed` / `region_closed` | the 6-city Ghana list |
| 7 | Here and now (added in W8b) | The latest session context (§2.3) says Dating is allowed where the person is | `away` | — |
| 8 | Device (added in W4b) | The request carries a trusted-device header (§3.3.4) | `reverify_device` | — |

**Which gates apply where.** The setup writers and `activate_dating_profile` call `dating_eligibility(p_user, 'setup')` (gates 1–4, 6 and 8), so a person in the gentle wait can set up and activate, and their first drop is the later of the open date and the cool-off. Being a candidate for introductions (generation, `act_on_dating_introduction`, every read of another person) uses the default scope and checks all eight.

Not gates, but checked where they apply: the 72 h cool-off (introductions only, §2.8); age assurance and photo verification (activation, §3.3); profile completeness (`dating_profile_ready` v2, §4.3).

**Where the Healing predicates go.** `dating_healing_gates_hold` is called in five places in `20260705210000_dating_mode_v1_2_hardening.sql` (`get_dating_eligibility`, `begin_dating_enrollment`, `activate_dating_profile`, `dating_candidate_is_current`, `enforce_dating_lifecycle_gates`); all five move to `dating_eligibility` and the function is dropped (W2). **`get_dating_eligibility()` stays as a compatible shim (I-4):** today's `dating_repository.dart` and `dating_feature_flags.dart` call it (Spec 1's Me slot calls no Dating RPC), so W2 re-creates it as a thin wrapper over `dating_eligibility(auth.uid(), 'setup')` returning the same `{is_eligible, reason, message}` shape (`feature_unavailable` and `relationship_active` unchanged, every other failure `account_unavailable`). W3a drops it, in the same release that moves those callers to `get_dating_home()`, and only after a test that greps `lib/` for `get_dating_eligibility` finds nothing. Healing itself stops granting Dating: `_healing_refresh_status` no longer sets `eligible_for_dating_opt_in` (a ready journey becomes `completed`), and `submit_healing_readiness` returns a message with no Dating date. The client's `ReadinessScoringService.isEligibleForDating`, `getEligibilityDate`, the Dating sentences in `getResultMessage`, `HealingJourney.isEligibleForDating`, the `healing_journey_screen.dart:169-190` block, and the Dating topics in `healing_docs.dart` (`healing_dating_readiness`, `healing_dating_consent_separate`, `faq_healing_dating_automatic`) are removed or rewritten (§4.10). The readiness score stays inside Healing as Healing's own private reflection; nothing in Dating reads it.

### 2.2 Country model: `country_safety_config`

A versioned server table. A row is immutable once published; a change publishes a new version and takes effect at the next generation run and at the next `get_dating_home()` call.

| Column | Type | Meaning |
|---|---|---|
| `country_code` | `char(2)` | ISO 3166-1 alpha-2 |
| `version` | `int` | 1, 2, … |
| `is_current` | `bool` | one current row per country (unique partial index) |
| `tier` | `smallint` 1/2/3 | 04 §2.1.6 criteria |
| `dating_enabled` | `bool` | per-country Dating kill switch |
| `open_regions` | `text[]` or null | the pilot subset; null = every region in `region_list` |
| `same_gender_enabled` | `bool` | per-country same-gender kill switch |
| `region_list` | `jsonb` | `[{code, name_key, sides:[{code, name_key}]}]` |
| `faith_list` | `jsonb` | `[{code, name_key, denominations:[{code, name_key}]}]` |
| `id_documents` | `jsonb` | documents offered at the ID fallback |
| `generation_hour_utc` | `smallint` | the hour the daily cohort runs |
| `reference_tz` | `text` | IANA zone for the cohort date and default drop time |
| `resources_verified_at` | `timestamptz` | the country's `support_resources` review date (S1 W7a) |
| `legal_checklist` | `jsonb` | evidence references, §8 W10 |
| `source_url`, `reviewed_at`, `reviewed_by`, `published_at`, `published_by` | — | provenance |

**Writers.** `publish_country_config(p_country, p_values jsonb)` is service-role only (called from the console by the safety owner, and in development by the dev script). It merges `p_values` over the current row and publishes the next version. In **production mode** (`private.attune_environment() = 'production'`; Q19b) it refuses `dating_enabled = true` unless every `legal_checklist` key has an evidence reference and `resources_verified_at` is within 90 days, and it refuses `same_gender_enabled = true` for a Tier 1 or Tier 2 row unless `legal_checklist.same_gender_reconsideration` carries the Ghanaian (or local) legal opinion, the LGBTQ+ consultation and the Tier 1 protections reference (§2.4). In development the checks are reported in the result, not enforced. W1b creates it without the same-gender-off path (turning `same_gender_enabled` from true to false returns `config:kill_switch_pending` and publishes nothing); W1d re-creates it from its live body with `apply_same_gender_switch` wired in, once the encrypted fields and `pause_reason` exist.

**Seeds (W1b).** Every seeded row has `dating_enabled = false`: a migration never switches anything on (R-6). In development, `supabase/sql/dev_enable_spec2_dating_flags.sql` publishes GH and GB with `dating_enabled = true` through `publish_country_config`; in production, W10 publishes them with their checklists.
- **GH**: tier 1; `open_regions` `{GA, AH}` (Greater Accra, Ashanti); `same_gender_enabled` false; all 16 regions (Ahafo, Ashanti, Bono, Bono East, Central, Eastern, Greater Accra, North East, Northern, Oti, Savannah, Upper East, Upper West, Volta, Western, Western North); sides for Greater Accra (`accra` "Accra", `tema` "Tema and Ashaiman") and Ashanti (`kumasi` "Kumasi", `outside_kumasi` "Outside Kumasi"); `id_documents` Ghana Card, passport; `generation_hour_utc` 3; `reference_tz` `Africa/Accra`.
- **GB**: tier 3; `open_regions` null; `same_gender_enabled` true; the 12 ITL1 regions (North East, North West, Yorkshire and the Humber, East Midlands, West Midlands, East of England, London, South East, South West, Wales, Scotland, Northern Ireland), no sides; `id_documents` passport, UK photocard driving licence; `generation_hour_utc` 3; `reference_tz` `Europe/London`.
- **Every Tier 1 and Tier 2 country in 04 §2.1.6**: a row with its tier, `dating_enabled` false, `same_gender_enabled` false. Niger is Tier 1 (the ordinance number is unconfirmed, 08 04-8; the tier does not depend on it).
- **Every other country** has no row and resolves to the default: tier 3, Dating closed, same-gender allowed for travellers' visibility (it never opens introductions, because Dating is closed there).

The seed lists (regions, sides, faiths, denominations) are content for the cultural reviewer at the W3 gate. The 04 §2.1.6 tier list is re-reviewed quarterly; the Ghana row is re-reviewed after the bill's second consideration, not on assent (08 A1).

**Public config.** W1b re-creates Spec 1's seam `private.dating_open_countries()` from its live body so that it returns the sorted codes of the countries whose current row has `dating_enabled = true` (the shape Spec 1 defined, e.g. `{GB,GH}`), and deletes the `app_public_config.dating_open_countries` row in the same migration (I-3). `get_public_app_config()` is not touched; the Welcome preview, the A6 card and the Me slot therefore always agree with `get_dating_availability()`.

**Faith lists (W3b seed).** GH: Christian (Catholic, Anglican, Methodist, Presbyterian, Pentecostal or Charismatic, Seventh-day Adventist, Other Christian), Muslim, Traditional, Other, None, Prefer not to say. GB: Christian (Catholic, Church of England or Anglican, Orthodox, Pentecostal or Charismatic, Other Christian), Muslim, Hindu, Sikh, Jewish, Buddhist, Other, None, Prefer not to say.

### 2.3 Effective tier and the session context

**Sources**, each processed in the moment:
- the phone country, from the E.164 prefix of `auth.users.phone`;
- the Dating country, from the profile;
- the IP country, resolved in the edge function `dating-device-check` from the request's client IP with a bundled DB-IP Lite Country database (CC BY 4.0, refreshed monthly; behind an `IpCountryResolver` seam). The IP address is never stored or logged;
- on Android only, the SIM country and the network country (`TelephonyManager.getSimCountryIso` / `getNetworkCountryIso`), sent by the client. iOS sends none.

**Computation** (server, `dating_effective_context`):
- `effective_tier` = the highest tier among the phone, Dating, IP and network countries (Tier 1 is highest). It drives notes and offers (PIN, plain icon), never a block by itself.
- `dating_allowed_here` = false when the IP country (or, if present, the network country) has `dating_enabled = false` **and** tier 1 or 2. Travel to a closed Tier 3 country (for example France) changes nothing.
- `same_gender_allowed_here` = the global flag `dating_same_gender_matching` AND `same_gender_enabled` for the Dating country AND for the IP country AND for the network country when present.
- `away_from_home` = the IP country differs from the Dating country.
- An unresolvable IP (VPN, unknown range) falls back to the phone and network countries. A VPN can hide a traveller (10 S4 step 2); the note and the plain-icon offer still use the phone country.

**Storage.** `dating_session_context` keeps **one overwritten row per user**: `effective_tier`, `dating_allowed_here`, `same_gender_allowed_here`, `away_from_home`, `ip_resolved`, `mismatch_streak` (consecutive checks where IP country ≠ Dating country, a moderation signal at 7 in a row), `checked_at`. No country codes and no history. It is refreshed on every app open and resume that shows Me, at most once per 15 minutes.

**Freshness.** A person is a candidate for introductions only if `checked_at` is within 14 days, and for same-gender introductions only within 7 days. This keeps people who have not opened Dating for two weeks out of other people's days, and means a same-gender introduction is never made while the server cannot know where the person is.

### 2.4 Same-gender rules

**Definitions.** A person's `identity` is `woman`, `man` or `non_binary` (plus an optional specific term, which never changes matching). Their **pools** are the groups they can be introduced as: `{woman}`, `{man}`, or `{non_binary}` plus any of `woman` / `man` they opt into (§3.2 D5). Their **seeking** set is `{man}`, `{woman}` or `{man, woman, non_binary}` ("Everyone", stored as the explicit full set). A pair is admissible on gender only if each person's seeking set meets the other's pools. A pair is **man–woman** when one identity is `woman`, the other `man`. Every other admissible pair, including any pair with a non-binary person, needs same-gender permission.

**Where it is off (Ghana, every Tier 1/2 country, and anywhere `same_gender_enabled` is false):**
- D5 offers only "Woman" and "Man", with the honest line and resources in §3.2. D6 offers no choice: it shows "You'll be introduced to men." (or women) with "Why?".
- The client never sends a same-gender combination, because the UI cannot produce one. If a modified client sends one, `save_dating_identity` / `save_dating_who_to_meet` return `{"ok": false, "reason": "not_available"}` **without raising** (a raised error can put the statement into the Postgres log), store nothing, and write no counter. The W1 health check confirms the project's logging (`log_statement`, `log_min_duration_statement`, `log_parameter_max_length`, `log_parameter_max_length_on_error`) cannot capture RPC parameters.
- No RPC response, log line, push payload, analytics counter or console view carries a gender/preference pair from that country. The "Why?" sheet is static bundled content; opening it calls nothing.
- Changing the Dating country to one where same-gender is off deletes any disallowed `seeking` value and pool in the same transaction, and D5/D6 are asked again.
- **Kill switch.** Turning `same_gender_enabled` off for a country (or the global flag off) runs `apply_same_gender_switch(p_country)` in the publishing transaction: same-gender introductions involving people whose Dating country is that country are invalidated, the disallowed values are deleted, those people are paused, and each sees an in-app note on next open: "Introductions between people of the same gender aren't available in {country} now. We've removed that choice from your profile. Why?" No push.

**Where it is on (UK):** D5 and D6 as in §3.2. A same-gender introduction additionally needs both people's `same_gender_allowed_here` true and fresh (§2.3).

**Reconsidering Ghana or any Tier 1/2 country** needs all of: a Ghanaian (or local) legal opinion on the reconsidered bill text; consultation with local LGBTQ+ groups; and every Tier 1 protection built and tested — name and photos withheld until mutual interest for same-gender introductions, verified accounts at least 30 days old only, a weekly cap for new accounts, the dragnet throttle (§5.10), and the LGBTQ+ block of the first-date guide (11 §4.8.2). None of those protections is in this spec's waves; they are a future spec.

### 2.5 Travellers (W8)

- Entering a place where `dating_allowed_here` is false (for example a Ghana-based user in the UAE): the Dating section hides on the device, nobody new is introduced to the person, and the person's card is hidden from others' Today. Conversations stay on the server.
- Entering a place where `same_gender_allowed_here` is false while the person has any non-man–woman pool or seeking value (for example a UK user who meets men, visiting Accra): new same-gender introductions stop, existing same-gender introductions and conversations are hidden on that device and from the other person's Today, and man–woman introductions continue against the home pool.
- The in-app note (§3.11) shows once per trip (a trip ends after 7 days back home). **Never a push** (10 S4).
- The person may choose "Show it on this phone anyway"; that only changes what the device displays. The server still makes no same-gender introduction while the context forbids it.
- Going the other way (a Ghana SIM visiting London) never switches same-gender on: it keys on the Dating country too.

### 2.6 Cross-border introductions

Off by default. A pair from different Dating countries is admissible only when: each person's `open_abroad` lists the other's Dating country; both countries are `dating_enabled`; both people have passed age assurance and photo verification; both accounts are at least 14 days old (`users.created_at`); and §2.4 allows the pair in both countries. The first time someone turns on a country, they see the cross-border card (§3.12). Region scope does not apply across borders.

### 2.7 Not-open countries and regions

- A person whose phone, device region or chosen country has Dating closed sees §3.10 at D1 (and Spec 1's path card says "Not open in {country} yet").
- In Ghana, a person whose region is outside `open_regions` sees the region variant at D3 and cannot activate.
- "Tell me when it's here" writes one `dating_notify_requests` row (user, country, optional region; the table exists from W1b, the RPCs and screens from W3a). When the country or region opens, `publish_country_config` queues one neutral push per row (type `me_update`, "Something you asked about is ready in Attune.") and deletes the rows. This is the first Dating push that can be sent, so `me_update` lands in W3a (I-9), and W3a re-creates `publish_country_config` from its live body to add this queueing step (before W3a no request can exist). Counts by country are visible in the console only at n ≥ 50. No queue position, no waitlist.

### 2.8 Trust friction and one-person rules

- **Cool-off:** no introduction is visible earlier than `users.created_at + 72 h` (Spec 1 sets `created_at` at A5; clients cannot write it under S1 W1a's column grants).
- **Caps and same country by default:** §5.3 and §2.6.
- **One person, one account:** the D2 attestation, the Dating terms, and a duplicate-account signal (two or more Dating activations from one trusted device within 30 days) that goes to the moderation queue, never to a partner and never as an automatic action.
- **Behaviour-only signals:** nationality, network, phone country, name and region are never risk signals (02 Impl 5). This rule is written into the runbook and asserted by a contract test that no signal function reads those columns.

---

## 3. Screens and flows

### 3.0 Rules for every Dating screen

- **Motion** (11 §2.0 tokens from S1 W2a): step forward = shared-axis X, 30 dp, `Durations.medium2` (300 ms), emphasized curves; back = reversed at 250 ms; selection 150 ms with `HapticFeedback.selectionClick`; step dots update without motion. **Never animated:** consent (D4), country and safety notes, the gentle wait (D0), the verification outcome screens except the single "You're verified" check, restricted and hold screens, report sheets, safety cards, "not open" screens, endings. Reduce motion (`MediaQuery.disableAnimations`) replaces every transition with a 150 ms opacity cross-fade. No Lottie, no confetti, no "It's a match".
- **Accessibility:** every screen is wrapped in `AllowLargeText` (up to 2.0×) and golden-tested at 1.0, 1.3 and 2.0; every control has a semantic label (`Semantics(container: true, label: …)`); touch targets ≥ 44 dp; contrast ≥ 4.5:1; errors are announced as live regions; focus order follows reading order; right-to-left flips the shared axis. Undo lasts until the next action, and at least 20 s while a screen reader is on (WCAG 2.2.1).
- **No local persistence of Dating content, and no "dating" on disk (C-5, 10 S19).** Answers, introductions, photos, messages and match lists live in memory only (Riverpod state that is disposed when Dating is left). Nothing Dating-related is written to `SharedPreferences`, files, the image disk cache or the gallery, and no key, value or file name this app writes contains "dating" (any case). Dating state is always read from the server; Spec 1's home cache stores only the tab layout (`chat` / `me`), the Dating lock is `me_section_lock`, and the device id this spec keeps (§3.3.4) uses the neutral key `attune.install_id` and is created at first launch on every install, so its presence says nothing about Dating. Setup progress is saved on the server after each step.
- **Offline:** a banner "You're offline. Dating needs a connection." Continue buttons are disabled with the hint "Connect to save this answer." What was typed stays on screen (memory only) until the person leaves.
- **Lock:** when Spec 1's Dating lock is on (a device setting in `lib/features/safety/data/dating_lock_store.dart`), every `/dating/*` route, notification tap and deep link asks for the existing Safety PIN first (§3.14). Quick exit never turns the lock off (it is cleared on sign-out only, by Spec 1).
- **Discretion (W8):** Android `FLAG_SECURE` on every Dating route; no long-press "save image"; the app-switcher cover is the existing `AppPrivacyCover` (§6.7).
- **Errors:** server failure "Something went wrong. Try again." with a Retry button; rate limit "You've done this a lot today. Try again tomorrow."; a gone object "This isn't available any more." Errors never reveal another person's state.
- **Progress:** setup steps D2–D13 show "Step {n} of 12" as text plus dots; Skip, where allowed, sits bottom-left on every screen.

### 3.1 Entry: the Dating section inside Me

Spec 1 W3b provides the Me home with a Dating section slot at the top (`lib/features/me/presentation/widgets/dating_slot.dart`, Dating path only). W3a of this spec fills it with `DatingSection` (the slot's body renders `DatingSection`; nothing else in Spec 1's Me files changes), driven by one RPC, `get_dating_home()`, which returns a `state` and only the data that state needs. Spec 1's Settings → Safety decides whether to show the Dating lock from `get_my_home_state().dating.enrolled`, which comes from Spec 1's seam `private.dating_home_summary(p_user)`. W1b re-creates that seam from its live body over this spec's eligibility (`enabled`) and enrolment states (`enrolled`), keeping its `{enabled, enrolled}` shape; any later batch that changes the enrolment states re-creates it again. It is a definer read, so W3a's revoke of client `SELECT` on `dating_enrollments` doesn't affect it (A-10); the contract test checks it after the revoke.

| `state` | The section shows | Tap goes to |
|---|---|---|
| `feature_unavailable`, `country_closed` | "Dating isn't open in {country} yet." + "Tell me when it's here" | §3.10 |
| `region_closed` | "Dating is open in Greater Accra and Ashanti for now." + "Tell me when it's open in {region}" | §3.10 |
| `gentle_wait` | "Dating opens for you on {date}." | D0 |
| `not_started` | "Meet a few people a day. Only when it's mutual." + "Set up Dating" | D1 |
| `setup_in_progress` | "Finish setting up Dating" (one quiet card, no banner) | the saved next step |
| `verifying` | "We're checking your video. This usually takes less than a day." | §3.3 status |
| `reverify_device` | "Confirm it's you on this phone to see Dating." | §3.3.4 |
| `cool_off` / `ready` | "Your first introductions arrive {weekday date} at {time}." | §3.4 |
| `active` | Today (up to 3 cards or the day's state), then "Conversations" | §3.4, §3.5 |
| `paused` | "Dating is paused. Nobody new sees you." + "Resume" | §3.8 |
| `restricted` / `hold` / `age_review` | the restricted card | §3.7 |
| `away` | "Dating is hidden while you're away." | §3.11 |
| `locked` (client-side) | "Dating" with a lock glyph | PIN, then the state above |

Under the Dating section, Spec 1's "Your space" (journal, quizzes, Healing) always stays one tap away (09 P9 fix 1).

### 3.2 Setup, D0–D13

Order: wait → how it works → what you're looking for → where → consent → you → who → children → faith → photos → prompts → verify → preview → ready. "You" comes before "who" because the off-country rule needs the person's own gender; "where" comes before both because the tier and the same-gender switch depend on the Dating country (09 P16 variant).

Each step saves on Continue through its own idempotent RPC (§4.4) and returns the next step; reopening the app resumes at `next_step` from `get_dating_home()`.

#### D0 — Gentle wait (only when `state = gentle_wait`)

| Element | Copy / behaviour |
|---|---|
| Title | "Before you begin" |
| Body | "Your relationship on Attune ended on {end date}. Dating opens for you on {open date}, when your shared space closes. If you both close it sooner, Dating opens then." |
| Line | "This pause is because your relationship ended here. It isn't a judgement about you." |
| Section | "Three questions, just for you" — "Only you can see these, and nothing is scored." |
| Q1 | "What do you want to carry into your next relationship?" |
| Q2 | "What are you hoping for now?" |
| Q3 | "How will you know if you need more time?" |
| Button | "Save my answers" (secondary) |
| Card | "Healing is here if you want it. It's there to help, and it's never required." → Healing |
| Button | "Set up Dating now" (primary): setup runs normally; introductions start on {open date} |

- **Fields:** three optional text fields, 0–500 characters each.
- **Validation:** length only.
- **Storage:** `dating_gentle_wait_reflections` (own row only; readable only by the author through `get_my_gentle_wait_reflection()`; deleted on exit).
- **Open date** = the ended relationship's `ended_at + 30 days`, or now if its status is already `archived`. The copy is clinician-reviewed (W2 gate).
- **Motion:** none. **Accessibility:** each question is a labelled field; the date is read in full words. **Offline:** the banner; Save is disabled.

#### D1 — How Dating works

| Element | Copy |
|---|---|
| Title | "How Dating works" |
| 1 | "Up to 3 introductions a day, at a time you choose." |
| 2 | "Saying 'Interested' is private. You only match when you're both interested." |
| 3 | "Dating chats are separate from the rest of Attune. Phone numbers stay hidden until you both choose to swap." |
| 4 | "Before your first introduction, a short video selfie checks your age and that your photos are you. The video is deleted straight away." |
| 5 | "You'll add at least 2 photos and answer 2 short questions." |
| 6 | "Your first introductions can arrive from {weekday date}." (the later of now and `users.created_at + 72 h`, at the default 7 pm) |
| 7 | "Dating is open in Ghana (Greater Accra and Ashanti) and the United Kingdom." (built from `get_dating_availability()`) |
| 8 | "Setting up uses about 15 MB of data, mostly for the video check." |
| Primary | "Set up Dating" |
| Secondary | "Not ready? Use Attune just for me" → `set_my_path('just_me')`, snackbar "You're on 'Just for me'. Undo" |
| Tertiary | "Set up later" → Me, with one quiet "Finish setting up Dating" card |

- **Fields:** none. **Storage:** none until Continue. **Motion:** shared-axis on Continue. **Accessibility:** the list is a semantic list of 8 items. **Errors:** if the country is closed, §3.10 replaces this screen. The 15 MB figure is measured on the W10 device matrix, and the copy is corrected if it is off by more than 25%.

#### D2 — What are you looking for? (Step 1 of 12)

| Element | Copy |
|---|---|
| Title | "What are you looking for?" |
| Options | "Marriage" · "A committed relationship" · "Companionship, at my own pace" · "Not sure yet" |
| If Marriage | "When would you like to marry?" "In the next year or two" · "In a few years" · "No set time" + toggle "Show this on my profile" (on) |
| Attestation (required) | ☐ "I'm not married in any form (customary, religious or civil), I'm not separated from a spouse, and I'm not in a relationship." |
| Helper | "Dating on Attune is for people who are free to start a relationship." |
| Link | "I'm separated but not divorced" → sheet: "Dating isn't open to you yet. Once your divorce is final, you're welcome here. Attune just for me is open to you now." |
| Expandable | "Married before? (optional)" "Never" · "Divorced" · "Widowed" + toggle "Show on my profile" (off) |

- **Validation:** intention required; attestation required ("Please confirm you're free to start a relationship."). The timeline only with Marriage.
- **Storage:** `dating_profiles.intention`, `marriage_timeline`, `timeline_visible`, `not_married_attested_at`, `attestation_version` ('2026-10-v1'); marital history encrypted in `dating_profile_sensitive.marital_enc`, `dating_profiles.marital_visible`. Any later change to intention or marital history asks the attestation again.
- **Accessibility:** radio group semantics; the attestation is a labelled checkbox with its full sentence.
- **Cultural review (W3 gate):** intention wording and the married / polygamy wording.

#### D3 — Where are you? (Step 2 of 12)

| Element | Copy |
|---|---|
| Title | "Where are you?" |
| Country | Picker of open countries, preselected from the SIM or device region (never hard-coded); last row "My country isn't listed" → §3.10 |
| Region | "Region" — the country's `region_list` |
| Closed region | inline: "Dating is open in Greater Accra and Ashanti for now. We're opening other regions as soon as we can look after them well." + "Tell me when it's open in {region}" |
| Side (only where defined) | "Which side of {region}? (optional)" e.g. "Accra" · "Tema and Ashaiman" |
| Scope | "How far would you like to meet people?" "My side" (only with a side) · "My region" (default) · "Anywhere in {country}" |
| Abroad | "Also open to people in other countries" — disabled, with "Available once you're verified and your account is 14 days old." |
| Helper | "We never use your exact location. Others see your region only." |

- **Validation:** country and region required; the region must be open to continue.
- **Storage:** `dating_profiles.country_code`, `region_code`, `side_code`; `dating_preferences.region_scope`. Changing country later is allowed once per 30 days and re-runs D5 and D6 (§2.4).
- **Accessibility:** pickers are searchable lists with labels; the disabled abroad row explains itself to screen readers.

#### D4 — Your answers stay private (Step 3 of 12; consent)

| Element | Copy |
|---|---|
| Title | "Your answers stay private" |
| Why we ask | "The next questions are about you and who you'd like to meet. We use your answers only to introduce you to people who'd like to meet you too." |
| Who sees what | "Nobody ever sees who you'd like to meet. Your gender, faith and marriage history appear on your profile only if you choose. We never collect your exact location." |
| What we never do | "Nothing from your journal, quizzes or Healing is used to introduce you. Your answers are never used for ads, never sold, and never read by AI." |
| How it's protected | "These answers are stored encrypted. The people who review reports can't see them." |
| Leaving | "You can leave Dating at any time, and these answers are deleted." |
| Consent (required) | ☐ "I agree that Attune can use my answers about my gender and who I'd like to meet to introduce me." |
| Links | "Dating terms" · "Privacy notice" |
| Primary | "Agree and continue" |

- **Storage:** three `dating_consent_events` rows with policy version `dating-2.0`: `dating_terms`, `dating_opt_in`, `special_category_profile`; then `begin_dating_enrollment` sets `opted_in_at`. D2 and D3 hold no special-category data: `save_dating_intention` creates the enrolment row in `profile_draft` if it is missing, under the D1 disclosure and EULA v2. Every special-category writer (D5, D6, D8) refuses without the `special_category_profile` consent (and D8 without `special_category_faith`). Withdrawing any of them later = exit (§3.8).
- **Motion:** none. **Accessibility:** headings are semantic headers; the checkbox carries the full sentence.

#### D5 — Which best describes you? (Step 4 of 12)

Where same-gender is **on**:

| Element | Copy |
|---|---|
| Title | "Which best describes you?" |
| Options | "Woman" · "Man" · "Non-binary" |
| Link | "Add something more specific" → "Trans woman" · "Trans man" · "Genderfluid" · "Genderqueer" · "Agender" · "Intersex" · "In my own words" (30 characters) |
| If Non-binary | "Should we also introduce you to people looking for:" ☐ "Women" ☐ "Men" — helper: "People open to everyone can always be introduced to you." |
| Pronouns | "Pronouns (optional)" with suggestions "she/her", "he/him", "they/them" (20 characters) |
| Visibility | toggle "Show my gender on my profile" (off; nothing preselected) |
| Helper | "We use this only to introduce you to people who want to meet someone like you." |

Where same-gender is **off** (Ghana and every Tier 1/2 country):

| Element | Copy |
|---|---|
| Options | "Woman" · "Man" |
| Line | "In {country}, Dating introduces men and women to each other for now. If neither of these fits you, Dating can't introduce you safely here yet." |
| Links | "Why?" → static sheet (below) · "Support for you" → `support_resources` for the country, categories `lgbtq_legal` and `crisis` |
| Why? sheet | "In {country}, relationships between people of the same gender can carry legal risk, and people have been targeted through dating apps, including by people they know. Until we can protect people properly here, Attune only introduces men and women to each other. Nothing you choose here is stored unless you continue. We'll look at this again after legal advice and talking with local groups." |

- **Validation:** an identity is required; the write-in is 1–30 letters (`\p{L}`, spaces, hyphens).
- **Storage:** `dating_profile_sensitive.identity_enc` (identity, specific term, pronouns, pools), `dating_profiles.gender_visible`. Nothing is written in an off country unless the person continues with Woman or Man.
- **Accessibility:** radio group; the off-country line is read before the options. **Copy review:** LGBTQ+ safety reviewer (W3 gate).

#### D6 — Who would you like to meet? (Step 5 of 12)

| Element | Copy |
|---|---|
| Title | "Who would you like to meet?" |
| On-country options | "Men" · "Women" · "Everyone" + "Only you can see this. It's never on your profile." |
| Off-country | "You'll be introduced to {men / women}." + "In {country}, Attune introduces men and women to each other for now. Why?" |
| Ages | "Ages {min} to {max}" — a two-thumb slider 18–99 |
| Default ages | 18–20: from 18 to own age + 7. 21 and over: from max(18, age − 5) to min(99, age + 5). |
| Country note (before saving) | shown when the effective tier is 1 or 2 and the choice includes the person's own gender, or the person is non-binary (below) |

**Country note** (full screen, no animation, never logged; shown on the device only):
- Title: "Before you save this"
- Phone-country variant: "Your phone number is from {country}, where relationships between people of the same gender can carry legal risk, and people have been targeted through dating apps, including by people they know."
- Location variant (when the higher tier comes from the IP or network country): "You're in {country} now, where relationships between people of the same gender can carry legal risk, and people have been targeted through dating apps, including by people they know."
- Then: "Attune never shows who you'd like to meet, never shows distance, and keeps Dating out of your notifications. You can also set a PIN, use a plain app icon, and leave Dating at any time to delete these answers."
- Buttons: "Save" · "Set a PIN first" · "Go back".

- **Validation:** a choice and a range with min ≤ max.
- **Storage:** `dating_profile_sensitive.seeking_enc`; `dating_preferences.min_age`, `max_age`. Server-side the off-country rule of §2.4 applies.
- **Accessibility:** the slider exposes both values ("Youngest 25, oldest 35") and supports increment/decrement actions.

#### D7 — Children (Step 6 of 12)

| Element | Copy |
|---|---|
| Title | "Children" |
| Q1 | "Do you have children?" "Yes" · "No" |
| Q2 | "Do you want children (or more children)?" "Yes" · "No" · "Open to it" |
| Toggle | "Only introduce me to people whose answer fits mine" (for Q2) |
| Toggle | "I'd rather not meet people who have children" |
| Helper | "We never ask for your children's names or ages, and photos with children can't be used." |

- **Validation:** Q1 and Q2 required. There is no option to *seek* parents (10 S22).
- **Storage:** `dating_profiles.children_have`, `children_want`; `dating_preferences.want_must_match`, `exclude_parents`.

#### D8 — Faith (Step 7 of 12; optional)

| Element | Copy |
|---|---|
| Title | "Faith" · "Optional" |
| My faith | the country's `faith_list`; a Christian choice opens "Denomination (optional)" |
| Importance | "How much does sharing a faith matter to you?" "It doesn't matter" · "Nice if we share" · "We must share it" |
| Visibility | toggle "Show my faith on my profile" (off) |
| Consent (required to save) | ☐ "Faith is sensitive information. I agree that Attune can use it to introduce me." |
| Skip | "Skip" (bottom-left) — nothing is stored |

- **Validation:** with a faith chosen, importance and the consent are required.
- **Storage:** `dating_profile_sensitive.faith_enc` (faith, denomination, importance), `dating_profiles.faith_visible`; consent event `special_category_faith`. "We must share it" becomes a dealbreaker (§5.2).

#### D9 — Photos (Step 8 of 12)

| Element | Copy |
|---|---|
| Title | "Add your photos" |
| Body | "Add 2 to 6 photos. Clear, recent photos of just you work best." |
| Slot states | "Add photo" · "Checking…" · "Ready" · "Needs a person to check it. That usually takes less than a day." |
| Rejections (name the slot) | "Photo {n}: we couldn't see your face clearly." · "Photo {n} is too small." · "Photo {n}: photos with children can't be used on Dating. Crop to just you?" [Crop] · "Photo {n} can't be used." |
| Toggle | "Show my photos only after we're both interested" — before account day 30: disabled, with "Available from {date}. New accounts show their photos for the first 30 days, which helps stop fake profiles." |
| Data | "Each photo uses about 300 KB." |

- **Fields:** 2–6 photos through the system picker; reorder by drag or by "Move earlier" / "Move later" actions (accessible alternative).
- **Client:** `DatingImagePreparer` resizes to at most 1600 px on the long side, re-encodes JPEG at quality 80 (about 300 KB) and strips EXIF before the upload intent is requested; the prepared temporary file is deleted as soon as the upload finishes or fails.
- **Server:** private bucket `dating-profile-photos`; positions 1–6; `_shared/csam_matcher.ts` (S1 W7b) **inline first, and only here** (the bucket is not in Spec 1's scan queue, so each photo is scanned once, I-10); a match calls Spec 1's `_shared/csam_match_path.ts` `quarantineAndRecord()` with `record_inline_csam_match` (copy to `safety-quarantine`, `safety_review` account hold, one `csam_match` escalation, deletion of the original through `queue_media_deletion`), then adds a Dating `moderation_hold` with category `csam` (§6.2) and sets `csam_state = 'hit'`; a matcher error sets `csam_state = 'error'` and the photo stays unapproved until a retry clears it; then Vision (face present, size, SafeSearch, and child labels `Child`, `Baby`, `Toddler`, `Infant` at score ≥ 0.7 → reject; 0.5–0.7 → needs review).
- **Validation:** at least 2 approved photos to activate.
- **Accessibility:** each slot is "Photo {n} of 6, {state}"; optional captions the person writes (for screen-reader users, 09 P12) are shown only to the person.

#### D10 — A little about you (Step 9 of 12)

| Element | Copy |
|---|---|
| Title | "A little about you" |
| Body | "Answer 2 of these. Short is fine." |
| Prompts | "A perfect Sunday for me looks like…" · "I feel most at home when…" · "My friends would say I'm…" · "I'm looking for someone who…" · "A small thing that makes my day…" · "The way to win me over is…" · "I'm learning to…" · "My family would describe me as…" · "A kind of place I love spending time…" · "Ask me about…" |
| Contact filter | "Contact details can't go on your profile. You can swap them in a chat when you're both ready." |
| Kindness filter | "Please rephrase this so it's kind to everyone." |

- **Fields:** 2 required, a third optional; 10–200 characters each.
- **Validation:** the §6.1 contact mask (any match blocks saving) and S1 W9a's pre-post filter (`private.content_filter_verdict`: slurs, explicit content).
- **Storage:** `dating_prompts` (prompt id + answer). Prompts are approved automatically when both filters pass; reports and moderation can remove one later.

#### D11 — Verify it's you (Step 10 of 12)

Full flow in §3.3.

#### D12 — This is what others see (Step 11 of 12)

| Element | Copy / behaviour |
|---|---|
| Title | "This is what others see" |
| Card | exactly the §3.4 introduction card, built from `get_dating_profile_preview()` |
| Edit links | per section; "First name" editor: "Use your first name or what friends call you." (1–30 characters; default from `users.display_name`) |
| Never shown | "Never shown: who you'd like to meet, your exact location, your date of birth." |
| Notification ask | "Tell me about new introductions and matches, at most once a day." [Turn on] (OS prompt in context) · "Tell me when someone messages me" (toggle, on once permission is granted) |

- **Storage:** `dating_profiles.display_name`; `dating_settings.digest_push`, `chat_push`.
- **Motion:** 200 ms cross-fade into the preview.

#### D13 — Ready (Step 12 of 12)

| Element | Copy |
|---|---|
| Title | "You're all set" |
| Time | "Your first introductions arrive {weekday date} at {time}." [Change time] → "Pick a time when you have a few quiet minutes." (07:00–22:00, 30-minute steps; default 19:00 in `users.timezone`) |
| While you wait | one item: "Read the first-date guide" · "Write in your journal" · "Take a 3-minute quiz" |
| Shared phone | "Does anyone else use this phone?" "Yes" · "No" → Yes: "Lock Dating with your PIN" (turns on Spec 1's Dating lock; creates the Safety PIN if none) · "Ask for my PIN every time Attune opens" (the existing every-open PIN) |
| Plain icon (effective tier 1/2; shown from W8b, when Settings → App icon exists, A-11) | "Some people like their apps to look plain." [Choose an app icon] |
| Primary | "Done" → `activate_dating_profile`, then Me |

- **Storage:** `dating_settings.drop_time`; Dating lock via Spec 1; icon choice is device-only.

### 3.3 Verification and age assurance (D11, W4)

#### 3.3.1 The two checks

Verification proves two separate things and stores both results in `dating_age_verifications` (one row per person):
1. **Identity:** a live person whose face matches every approved photo. Methods: `liveness_compare` (vendor liveness, then AWS Rekognition `CompareFaces` against each photo) or `human_gesture` (§3.3.3).
2. **Age 18+:** methods `fae` (facial age estimation on the liveness reference frame; passes only when the estimate is at or above the challenge age 25) or `id` (a document check that also matches the face and confirms the document's date of birth equals the declared one). **A human cannot pass age;** human review resolves identity problems and mismatches only.

Dating activates only with both passed. The DOB from Spec 1 is never written here.

#### 3.3.2 Screens

**Intro**

| Element | Copy |
|---|---|
| Title | "Verify it's you" |
| Body | "A short video selfie checks that you're a real person, that your photos are you, and that you're over 18. The video is deleted at once. We keep only whether it passed." |
| Tips | "Face a window or a lamp, not away from it." · "Take off sunglasses. Glasses are fine without glare." · "Hold the phone at eye level." |
| Light warning | "This check flashes colours on your screen. If flashing lights affect you, choose 'Check another way'." |
| Consent (required) | ☐ "I agree that Attune and its verification partner can use my face to check my age and match my photos. Nothing is kept after the check." |
| Primary / secondary | "Start video check" · "Check another way" |

**During capture:** the vendor's capture view, plus Attune's own spoken prompts (platform TTS) and haptics: "Move the phone a little closer", "Hold still", "Done". Resumable: the session lives on the server for 30 minutes; if the app is killed, reopening shows "Let's pick up where you left off."

**Outcomes**

| Result | Copy | Next |
|---|---|---|
| Both pass | "You're verified." (one calm check, 400 ms fade; none under reduce motion) | D12 |
| Liveness failed (1st) | "That didn't work. Let's try again." + the tips | retry |
| Liveness failed (2nd) | "Still not working? You can check another way." | ID or human route |
| Estimate below 25 | "We couldn't confirm your age from the video. That's common for people under 25. Let's check with your ID instead." | ID route |
| A photo doesn't match | "Photo {n} doesn't look like the video. Change that photo, or ask a person to review it." | D9 or human review |
| ID route | "Which ID do you have?" (the country's `id_documents`) → vendor capture → "Thanks. Most checks finish in a few minutes. Some need a person, which takes up to 24 hours." | status |
| ID date of birth differs from the one you gave | "The date of birth on your ID doesn't match the one you gave us. A person will check this within 24 hours." | human review; a correction goes through Spec 1's protected correction path |
| Age not confirmed | "We couldn't confirm your age, so Dating isn't available on this account. If you think this is wrong, contact support." | — |
| Estimate far below 18 for a declared adult | "We need to check a few things on your account. Contact support if you have questions." | `place_account_hold(user, 'age_review', <verification session id>)` (Spec 1; always three arguments, I-7; §6.3) |
| Waiting for a person | "A person is checking. This usually takes less than a day. We'll show the result here." | status |

#### 3.3.3 Human review route

"Take two quick photos" (camera only, no gallery): two randomised gestures from a reviewed list ("Hold up three fingers next to your face", "Touch your left ear", "Give a thumbs up"). The two photos go to the private bucket `dating-verification-review` through an upload intent, are visible only in the console's verification queue, and are deleted at the decision or after 72 hours, whichever comes first. The reviewer decides identity (pass / fail / ask for ID). Target: 24 hours.

#### 3.3.4 New-device re-verification

Every install keeps a random 128-bit device id, created at first launch whether or not the person ever uses Dating, in `flutter_secure_storage` under the neutral key `attune.install_id` (Android Keystore with backup excluded; iOS Keychain `first_unlock_this_device`, not migrated to new phones). **Only the Dating repository sends it (S-7, C-6):** a Dating-scoped `SupabaseClient` (`lib/features/dating/data/dating_supabase_client.dart`, new) is built with `headers: {'x-attune-device': id}` and an `accessToken` callback that returns the main client's current session token (supported by `supabase` 2.12), and Dating's edge-function calls pass the same header per call. No other request carries it, so Opinions and couples traffic can't be linked to the stored hash, and `lib/main.dart` and the shared client set-up are not edited. `dating_require_trusted_device()` reads `request.headers` and checks `sha256(device id)` against `dating_trusted_devices`.
- **Before verification:** the device that makes the first setup write (D2) is trusted for the setup. On any other device, `get_dating_home()` returns `reverify_device` with the variant `setup_restart`: "You started setting up Dating on another phone. To keep your answers private, start again here." [Start again] hard-deletes the draft (as exit, §3.8) and opens D1.
- **After verification:** the device that passed D11 is trusted; any other device gets `state = reverify_device` and no Dating data until it passes liveness + CompareFaces against the approved photos (no age estimate):
- Copy: "Welcome back. Before we show Dating on this phone, please do a quick video check. It's how we keep your conversations yours." → "Start video check" · "Check another way" (human route).
- Up to 3 trusted devices; a device unused for 180 days drops off. This covers recycled numbers and SIM swaps for Dating (10 S5, S7) without storing any face template.

#### 3.3.5 Vendor seam

`supabase/functions/_shared/age_assurance/` defines four interfaces with a `fake` and a real implementation each: `LivenessProvider` (default AWS Rekognition Face Liveness, in an EU/UK region that offers it, chosen and recorded in the DPIA at W4; `us-east-1`, today's default in `verify-dating-profile`, is not used for UK or EU users), `AgeEstimationProvider` (a UK-recognised facial age estimation vendor), `IdDocumentProvider` (Smile ID or equivalent: Ghana Card, passports, UK driving licence), `FaceMatchProvider` (the existing `_shared/aws_rekognition.ts` `compareFaces`). `app_setting('age_assurance_mode')` is `fake`, `sandbox` or `live`; production refuses `fake` (W10 guard). Vendors must supply skin-tone and West African error data before the W4 gate. Reference frames are held in memory in the edge function only; no S3 output is configured for liveness sessions.

### 3.4 Daily introductions (Today, W5)

**The card** (person first, photo after; also D12's preview):

| Part | Content |
|---|---|
| Heading | "{First name}, {age}" · "{Region}" (age from Spec 1's DOB; never the DOB; side never shown) |
| Intention | "Looking for marriage, in the next year or two" (timeline only if visible) / "Looking for a committed relationship" / "Looking for companionship, at their own pace" / "Not sure yet" |
| Why you two | "Why you two were introduced" + 2–3 reasons (§5.8) + always "Attune can't predict chemistry; meeting is how you find out." |
| Prompts | the person's 2–3 prompts and answers |
| Children | "Has children" / "No children" · "Wants children" / "Doesn't want children" / "Open to children" |
| Optional, only if shown | gender (and specific term), pronouns, faith (and denomination), "Widowed" / "Divorced" |
| Photos | carousel from short-lived signed URLs; or "Photos appear after you're both interested."; with data saver on: "Show photos (about 1 MB)" |
| Actions | "Interested" (filled) · "Not for me" (outlined) · overflow "More": "Report", "Block" |

- **After "Interested":** the card shows "Noted. If {Name} is interested too, you'll both see it here." **After "Not for me":** the card fades out (200 ms size transition) with a snackbar "Not for me. Undo". The action is held on the device and sent when the undo window ends, the next action happens, or the screen closes (5 s; at least 20 s with a screen reader). No rewind after that.
- **Day states** (from `get_my_dating_today()`):

| `today_state` | Copy |
|---|---|
| `before_drop` | "Your introductions arrive at {time}." |
| `delivered` | the cards |
| `empty` | "No good fit today. Attune is still small in {region}. We'll introduce you when there's a good fit." + "Widen who I meet" |
| `queue_full` | "You have introductions waiting. New ones arrive after you've looked at these." |
| `paused_open_chats` | "You have 3 conversations going. New introductions start again when one ends or you meet." |
| `cool_off` | "Your first introductions arrive {weekday date} at {time}." |

- **"Widen who I meet"** sheet: three rows, each opening its editor, nothing changed automatically: "Ages: {min}–{max}", "How far: {scope}", "Other countries" (only when eligible, §2.6).
- **Waiting introductions** from earlier days appear under "Still waiting for you". No dates, how long a card has waited, or expiry are ever shown (no countdown, Fable M8).
- **Family question** (once, after the first introduction): "One more question, if you like: How involved would you like family to be?" "Involved early" · "Involved once it's serious" · "Our decision first" · "Skip" → `dating_profiles.family_involvement` (shared ground only, never shown as a field).
- **Payload rules:** introductions are never cached on disk; photos are fetched as bytes from signed URLs that live 60 seconds and are held in a 20-image in-memory cache that is cleared when Dating is left, and on quick exit and sign-out through Dating's entry in Spec 1's device wipe registry (§6.7).
- **Accessibility:** a card reads in order; photos are announced as "3 photos" with any captions the person wrote; the two actions are full-width buttons ≥ 48 dp.

### 3.5 The match moment and conversations (W5, W6)

**Match moment** (shown once to each person, the next time they open Dating):
- "You and {Name} are both interested." · "There's no rush. Say hello when you're ready." · [Say hello] · [Later]
- Motion: the two first-letter avatars settle together, at most 600 ms, once, with one light haptic; reduce motion → fade. No counter, no burst, no "It's a match".
- `mark_dating_match_moment_seen(match_id)` records it per side.

**Conversations list:** "Conversations" — each row: first name, age, the last message (masked as in §6.1), and a dot (not a count) for something new. Section "Ended in the last 30 days" — "You can still report a problem for 30 days." with only a Report action. Empty: "When you and someone are both interested, your conversation appears here."

### 3.6 Dating chat (W6)

Its own screen (`lib/features/dating/presentation/chat/dating_chat_screen.dart`) with its own widgets; it imports nothing from `lib/features/chat/**` or `lib/features/games/**` (an architecture test enforces this, §7.4).

| Element | Copy / behaviour |
|---|---|
| Header | "{Name}, {age}" + a "Safety" button (shield icon, label "Safety options for this conversation") → sheet: "Report", "Block", "Unmatch", "Close kindly", "Safety resources", "Plan a meet", "We met", and once either has tapped "We met": "Become a couple on Attune" |
| Composer | hint "Write a message"; text only, 1–1,000 characters; no attachment, camera, voice or GIF buttons |
| Links | never clickable; URLs are masked until swap, plain text after |
| Status | own messages show "Sending…", then nothing; a failure shows "Not sent. Tap to try again." No read receipts, typing indicators, presence or last seen |
| Masked span | "•••" — tap: "Hidden until you both tap Swap contacts. This keeps your number private while you get to know each other." |
| Swap (from 72 h) | header chip "Swap contacts" → sheet: "When you both tap Swap, phone numbers, emails and usernames in this chat stop being hidden. You can't undo it once you've both swapped." + one-time card: "On WhatsApp, Attune can't help inside the chat. Sextortion often starts with a video call." [Swap] [Not yet] |
| Swap states | "You offered to swap. {Name} hasn't yet." [Cancel] · "{Name} offered to swap contacts." · "Contacts are visible now." |
| Before 72 h | the chip reads "Swap contacts (from {weekday time})" and is disabled |
| Closed | banner "This conversation has ended." — read-only; Report stays available for 30 days |

**Guided first conversation** (top card until finished or skipped):
- "Start with a question?" — the current question, "Answer", "Skip this one".
- After answering: "{Name} will see your answer once {Name} answers too." When both have answered, both answers appear together, then the next question.
- After the first reveal, once: "Tip: ask a follow-up about something {Name} said."
- Questions, in order (reviewed templates; nothing written by AI): light — "What does a good Saturday look like for you?", "What's a food you could eat every week?", "What are you looking forward to this month?"; middle — "What's something you're proud of that people don't usually ask about?", "Who do you laugh with most?", "What did you learn from the place you grew up?"; deeper — "What does a good relationship look like to you, day to day?", "How do you like to spend time with family?", "What would you want someone to know before a first meeting?"
- Either person may skip a question; it is skipped for both. Free chat is always possible alongside.

**Safety cards** (recipient only, shown under the message that triggered them, never to the sender; §6.1 lists the families and exact copy). Each card has "Report", "Block" and "Dismiss"; dismissing never weakens later detection.

**Timebox cards** (no countdowns):
- Day 7 of the match, once, to each person: "Plan a first meet?" [Plan a meet] [Not yet].
- Day 21, once, if neither has tapped "We met": "Keep chatting, or close kindly?" [Keep chatting] [Close kindly].

**Meeting kit** ("Plan a meet"):
- Checklist (static, reviewed): "Meet in a public place you both know." · "Get there and back on your own." · "Tell someone you trust where you'll be." · "Keep chatting here until you're sure." · "Never send money to someone you haven't met."
- "When?" date and time; "Where?" free text ("A public place you both know"); the text is held in memory only.
- [Share my plan] → system share sheet with: "I'm meeting someone from Attune on {date} at {time} at {place}. I'll check in by {time + 3 h}." Never the match's name or photo. [Send as text message] → `sms:` with the same body.
- [Check on me] → schedules one neutral push at the check-in time: "A quick check-in from Attune." Tapping opens the check-in. This is the only server row: `scheduled_notifications` with the time and a route, no place, no match.
- **Check-in:** "How did it go?" [I'm OK] [Get help] [We met] [Not now].
- **Get help:** confirmation "Show emergency numbers?" → the country's `support_resources` (emergency first) and [Message someone you trust] → a text the person sends themselves: "I need help. I'm at {place}. Please call me." Nothing is ever sent automatically.

**Close kindly:** sheet "Send this and end the conversation?" with the reviewed message "Thank you for chatting with me. I don't think we're a match, and I wish you well." [Send and end] [Cancel]. The match closes (`closed_kindly`); both see the banner. Unmatch stays available for safety, with no message.

**Unmatch:** "Unmatch {Name}? You won't be introduced again. {Name} will see that the conversation has ended." **Block:** "Block {Name}? {Name} won't be told. You won't be introduced again, even if {Name} makes a new account with the same number."

**Offline:** messages can't be sent offline (nothing is queued on disk): "You're offline. Your message is still here; send it when you're back." **Accessibility:** messages are a semantic list with sender names; masked spans are read as "hidden contact detail"; the composer has a send button ≥ 48 dp.

### 3.7 Report, restricted, appeal (W7)

**Report sheet** (from a card, a chat, or the "Ended" list):

| Label | Category | Priority |
|---|---|---|
| "They might be under 18" | `underage_risk` | P0 |
| "Sexual content involving a child" | `csam` | P0 |
| "Asked about or for access to children" | `child_safety` | P0 |
| "Threatened to kill or seriously hurt someone" | `threat_to_life` | P0 |
| "Threatening to share images of me" | `sextortion` | P1 |
| "Asked me for money" | `romance_scam` | P1 |
| "Threatened me" | `threats` | P1 |
| "I think it's a fake profile set up to trap people" | `entrapment` | P1 |
| "Harassing me" | `harassment` | P2 |
| "Sent sexual messages I didn't want" | `explicit_content` | P2 |
| "Using someone else's photos or identity" | `impersonation` | P2 |
| "Married or in a relationship" | `hiding_relationship` | P2 |
| "Spam or selling something" | `spam` | P3 |
| "Something else" | `other` | P3 |

- "Tell us more (optional)" (500 characters) · toggle "Also block {Name}" (on for P0–P2) · [Send report].
- Sent: "Thanks for telling us. A person reviews every report, and we aim to look at reports like this within {SLA in words}. If you're in danger now, call {emergency number}." The SLA sentence is shown only once the moderator is named (W7 gate); until then in development it reads "In testing, reports go to the test review queue."
- After `romance_scam`: "You did the right thing. Scammers are skilled; this isn't on you." [Pause Dating] [Close] (09 P7 fix 3).

**Restricted card and screen** (`get_my_dating_restriction()`):

| Type | Copy |
|---|---|
| Interim hold (P0, corroborated) | "Your Dating profile is paused while we look into a report. This isn't a decision yet. We aim to finish within 24 hours." Category line: "About: {category label}". |
| Age check | "We need to confirm your age before you can use Dating." [Verify with ID] |
| Suspended (temporary) | "Your Dating account is restricted until {date}." "Reason: {category label}." "What this means: you can't be introduced or send Dating messages until then. The rest of Attune works as usual." |
| Suspended (permanent) | "Your Dating account has been closed." "Reason: {category label}." |
| Actions | [Appeal] (once) · [Contact support] |

- **Appeal:** "Tell us what happened (optional, 500 characters)" → [Send appeal] → "Appeal sent. A different person from the one who made the first decision will look at it within 7 days." Outcome in-app: "Your appeal was accepted. Dating is open again." / "We looked again and the decision stands." (with the category).
- **Never shown:** who reported, what they wrote, or the evidence.

### 3.8 Pause, exit, delete (W1 data, W3 screens)

- **Pause** (Dating settings): "Pause Dating" → immediately "Dating is paused. Nobody new sees you, and your conversations stay open." Silent to everyone. [Resume Dating] resumes without re-running activation gates beyond eligibility (fixes Fable L3).
- **Leave Dating and delete my data:**
  - Title "Leave Dating?"
  - "Deleted now: your Dating profile, photos, prompts, who you'd like to meet, your gender and faith answers, your settings and your private notes."
  - "Kept for 30 days, then deleted: your conversations, so either of you can still report a problem."
  - "Kept for safety, for up to 2 years, only if your account is restricted or you've blocked someone: a code made from your phone number, never the number itself."
  - "Kept as a record: when you agreed to Dating's terms and when you left."
  - ☐ "Keep my 'Never introduce me' list in case I come back. It holds codes, not numbers." (**off by default**; ticked → the list is kept until the account is deleted; R-2)
  - [Leave and delete] · [Pause instead]
  - Done: "You've left Dating. You can set it up again any time." The path stays Dating until the person changes it (Spec 1 Settings).

### 3.9 Couple link (W9)

1. **Request** (Safety sheet → "Become a couple on Attune", available once either has tapped "We met"): the private "What are we agreeing to?" sheet: "Your Dating profiles pause for both of you. You'll share a private space for the two of you. Either of you can end it at any time." ☐ "Keep our first messages as a 'How we met' card (only if {Name} agrees too)" [Ask {Name}] [Not now].
2. **The other person** sees in the chat: "{Name} would like to become a couple on Attune." [See what this means] → the same sheet → [Yes, let's] [Not right now]. "Not right now" shows the requester: "{Name} isn't ready yet." The request lapses after 14 days with no copy.
3. **On the second "Yes"** (one transaction, §4.4 `confirm_dating_couple_link`): the relationship is created through the same row transitions as the invite exchange (a `pending` row with a generated code, then `active` with both members, and a `relationship_invite_acceptances` row), so every existing trigger fires as it does for invites; the relationship guard pauses Dating for both; every other open conversation of either person closes with the neutral "This conversation has ended."; both paths become Relationship (`set_user_path_internal`); the linking match closes (`couple_linked`); if both ticked the box, the first 50 messages are copied into `couple_how_we_met`, **masked unless both had swapped** (the `body_masked` text otherwise, exactly as both saw it; A-3).
4. **Both see** (once): "You decided together." with the settle (≤ 600 ms, once) → the Relationship home.
5. **About us:** "When did you two get together?" offers a chip "The day you matched: {date}" (Spec 1's AU2 slot; never pre-filled). The date comes from `get_dating_link_origin(relationship_id)` (members only) through a **client override** of Spec 1's `aboutUsDateSuggestionsProvider(relationshipId)`; Spec 1's `couple_profiles` functions are not touched and carry no `suggested_dates` from Dating (I-12).
6. **30 days after linking**, once, on the Relationship home: "Delete your Dating profile and preferences? You can set up Dating again later." [Delete my Dating data] [Keep for now]. "Keep for now" never asks again. **Where (C-4):** for a linked couple the Relationship home is `ChatHomeScreen` → `ConversationsScreen`; W9 appends one `HomeCard` (id `link_offer`, label "Your Dating profile") to the `ReorderableHomeCards` list in `lib/features/chat/presentation/screens/conversations_screen.dart`, included only while `get_dating_post_link_offer()` reports an offer. The card's widget lives in `lib/features/dating/presentation/link/`. Nothing else in that file changes; the chat card, the Journals and Together cards and every Games entry point are untouched.

### 3.10 Not in your country (W3)

| Element | Copy |
|---|---|
| Title | "Dating isn't open in {country} yet" |
| Body | "Attune opens Dating one country at a time, so we can keep it safe and well looked after. It's open in Ghana and the United Kingdom now." |
| Primary | "Tell me when it's here" → "We'll let you know. You can turn this off in Settings." |
| Secondary | "Use Attune just for me" (only on the Dating path) |
| Region variant | Title "Dating is open in Greater Accra and Ashanti for now" · Body "We're opening other regions as soon as we can look after them well." · Primary "Tell me when it's open in {region}" |

No animation, no waitlist number. Store copy and the Welcome preview say the same (Spec 1).

### 3.11 Traveller (W8)

| Case | Copy (in-app, once per trip, never a push) |
|---|---|
| Dating not allowed where the person is | Title "Dating is hidden while you're away" · "While you're in {country}, your Dating section is hidden on this phone and nobody new is introduced to you. Your conversations are safe and come back when you leave." |
| Same-gender not allowed where the person is | Title "Some introductions are paused while you're away" · "While you're in {country}, introductions between people of the same gender are switched off for you, and the ones you have are hidden on this phone. They come back when you leave." |
| Actions | [Keep it hidden] (default) · [Show it on this phone anyway] · [Pause Dating] · [Set a PIN] |

### 3.12 Dating settings and "Never introduce me"

**Dating settings:** Introduction time · Who I'd like to meet · Ages · How far · Other countries (when eligible) · Photos after mutual interest (from day 30) · Data saver ("Show photos only when I tap") · Notifications (digest, messages) · Never introduce me to these numbers · App icon · Dating lock (opens Spec 1's setting) · Pause Dating · Leave Dating and delete my data.

**Other countries** (first time): "Scams often start with someone abroad: a soldier, an oil-rig worker, a crypto 'mentor'. Never send money to someone you haven't met. Cross-border introductions are only with verified people whose accounts are at least 14 days old." [Turn on for {country}].

**Never introduce me to these numbers:**
- Title "Never introduce me to these numbers"
- "Add a phone number and Attune will never introduce you to the person who uses it, now or later. They're never told."
- "We keep a code made from the number, not the number itself."
- Fields: country code + number; "A name only you'll see (optional)" (20 characters).
- List rows: "{label} · ending {last two digits}" [Remove]. Up to 50.
- Adding gives the same "Added." whatever the number, so it can't be used to test whether someone uses Attune. It affects introductions not yet matched; an existing conversation is ended with Block.
- Copy review: DV specialist (W5 gate).

### 3.13 Notifications (W3a, W5b, W6b, W6c)

Every Dating push uses the title "Attune" and the body "You have something new in Attune." The payload carries only `{"route": "me"}` and notification type `me_update` (no "dating" anywhere), and the tap opens Me (`/home?tab=me`, where the Dating section shows its locked state if the Dating lock is on).

**The neutral types exist before anything sends them (I-9).** `me_update` (the server type, its neutral copy, the `notification_config.dart` case and the tap to Me) lands in **W3a**, the first wave that can queue a Dating push (a notify request, §2.7); W5b's digest and W6b's message pushes reuse it. `me_checkin` lands in **W6c** with the check-in itself: its `notification_config.dart` case opens `/dating/checkin` behind the Dating lock (the payload is `{"route": "me_checkin"}`; the `/dating/…` path exists only in the client's route table).
- **Daily digest:** at most one a day, at the person's drop time, only if they turned it on, and only when there are new introductions today or a match since the last digest.
- **Messages:** at most one per 15 minutes per person, while something is unread, if "messages" is on.
- **Check-in:** "A quick check-in from Attune." at the time the person chose; not folded by quiet hours, because the person set it (W6c adds type `me_checkin` next to `safety_resources` in the exemption of `scheduled_notifications_quiet_guard`, re-created from its live body). Tapping it opens the check-in (`/dating/checkin`), behind the Dating lock.
- **"Tell me when it's here":** "Something you asked about is ready in Attune."
- Quiet hours apply to digest and message pushes through the existing push queue.
- Push source keys are opaque (`sha256(user id || purpose || day || server secret)`), never a match id (Fable M4).

### 3.14 Routes (W3, in `app_router.dart`'s dating block only)

`/dating/setup/:step` (`wait`, `how`, `looking-for`, `where`, `privacy`, `you`, `meet`, `children`, `faith`, `photos`, `prompts`, `verify`, `preview`, `ready`) · `/dating/verify` · `/dating/today` · `/dating/introduction/:id` · `/dating/match/:id` · `/dating/chats` · `/dating/chat/:matchId` · `/dating/chat/:matchId/plan` · `/dating/checkin` · `/dating/restricted` · `/dating/settings` · `/dating/never-introduce` · `/dating/leave` · `/dating/not-open` · `/dating/away` · `/dating/link/:matchId`.
- One `redirect` on this route group sends to the PIN screen when the Dating lock is on and the PIN has not been entered in this foreground session. Push taps (`me_checkin` → `/dating/checkin`) and deep links enter through the same redirect.
- Removed: `/datingConsent`, `/datingProfile`, `/datingMatches`, `/datingGuidedDate`, `/datingPhotos`, `/datingVerification`, and the `/dating-mode` feature-intro route (its copy promised the Healing gate). Game routes and every other route block are untouched.

### 3.15 Motion, accessibility and errors, screen by screen

§3.0's rules apply everywhere; this table lists what each screen adds.

| Screen | Motion | Accessibility | Errors and offline |
|---|---|---|---|
| Dating section (§3.1) | 200 ms cross-fade between states | the section is a semantic region "Dating"; the lock state reads "Dating, locked" | stale state: the last server state is not cached, so offline shows "You're offline. Dating needs a connection." |
| D0 gentle wait | none | dates read in full words; three labelled fields | Save disabled offline; typed text kept in memory |
| D1 how it works | shared-axis on Continue | an 8-item semantic list | closed country → §3.10 instead |
| D2 looking for | shared-axis; the timeline expands with a 200 ms size transition (none under reduce motion) | radio group; the attestation checkbox carries the full sentence | "Please confirm you're free to start a relationship." announced as a live region |
| D3 where | shared-axis | searchable labelled pickers; the disabled abroad row explains why | closed region → inline notice, Continue disabled |
| D4 consent | **none** | semantic headings; checkbox with the full sentence | Agree disabled offline |
| D5 you | shared-axis | radio group; the off-country line is read before the options | a modified-client refusal shows "This choice isn't available here." |
| D6 who | shared-axis; the country note has **none** | the age slider exposes both values and increment actions | min > max is impossible by construction |
| D7 children | shared-axis | radio groups; toggles labelled with their full sentence | — |
| D8 faith | shared-axis | the denomination list is a nested labelled group | the consent checkbox error is announced |
| D9 photos | upload progress in words ("Uploading photo 2, 60%"); no spinners without text | "Photo {n} of 6, {state}"; Move earlier / Move later actions; captions | each failure names the photo and its reason; offline: "You're offline. Add photos when you're connected." |
| D10 prompts | shared-axis | each prompt is a labelled field with a character count read on focus | filter messages announced |
| D11 verify | one 400 ms check on success, none otherwise | spoken prompts and haptics during capture; "Check another way" as prominent as "Start"; the photosensitivity warning before capture | resumable from the server session; the vendor's network failure → "That didn't go through. Try again." without counting an attempt |
| D12 preview | 200 ms cross-fade | the card reads in the same order as for others | — |
| D13 ready | none | the time picker is a labelled list of times | — |
| Today (§3.4) | cards cross-fade in at 200 ms; acted cards collapse at 200 ms | full-width actions ≥ 48 dp; undo ≥ 20 s with a screen reader | offline: the banner, actions disabled; an introduction gone meanwhile shows "This isn't available any more." |
| Match moment (§3.5) | one settle ≤ 600 ms, once; fade under reduce motion | announced as "You and {Name} are both interested" | — |
| Chat (§3.6) | new messages appear without animation; cards slide in at 150 ms (none under reduce motion) | messages are a list with sender names; masked spans read "hidden contact detail" | "Not sent. Tap to try again."; offline: nothing queued on disk |
| Meeting kit | none | the checklist is a semantic list | Share works offline (system share sheet); Check on me needs a connection |
| Report sheet (§3.7) | **none** | categories are a radio group with full labels | sending offline: "You're offline. Your report will need a connection; nothing has been sent." |
| Restricted, hold, appeal | **none** | the category label is read first | appeal offline disabled |
| Pause, leave (§3.8) | none | the leave screen lists deleted and kept items as semantic lists | Leave disabled offline |
| Couple link (§3.9) | one settle ≤ 600 ms on "You decided together." only | the "What are we agreeing to?" sheet is read in full before the buttons | the second confirmation offline: "You're offline. Nothing has changed yet." |
| Not open, traveller (§3.10, §3.11) | **none** | headings and buttons labelled | notify-me offline disabled |
| Settings, never-introduce (§3.12) | standard list | the phone field has a labelled country-code picker; list rows read "{label}, ending {digits}" | adding offline disabled |

---

## 4. Data model

### 4.1 Principles (from 11 §3.1, applied)

- Every Dating table has RLS on and `REVOKE ALL … FROM PUBLIC, anon, authenticated`. Clients read and write **only** through `SECURITY DEFINER SET search_path = ''` functions that take the actor from `auth.uid()`. From W3 the client has no direct `SELECT` on any Dating table (today `dating_repository.dart` selects `dating_profiles`, `dating_preferences` and `dating_enrollments` directly; those reads move to RPCs and the grants from `20260811120000_dating_owner_read_grants.sql` are revoked in the same release).
- Fully qualified names everywhere; pgcrypto is called as `extensions.hmac`, `extensions.digest`, `extensions.pgp_sym_encrypt` (`20260951020000` explains why).
- Special-category data (gender identity, pools, who you'd like to meet, faith, marital history, pronouns) lives only in `dating_profile_sensitive`, encrypted (§4.2), and never in logs, counters, push payloads, console views, exports to anyone else, or AI prompts.
- Every phone HMAC is computed from `auth.users.phone`, never `public.users.phone`.
- Deletion deletes, with three named survivors keyed by phone HMAC: enforcement records, block pairs, anonymised reports (2 years).
- No analytics SDK; Dating writes only aggregate keys into Spec 1's `metric_counters`, after registering the prefix `dating.` in `metric_key_prefixes`, and **only server-side**: Dating definer functions call `private.bump_metric_internal` and Dating edge functions call `bump_metric_server`. W1a inserts the server prefix `dating.` into `metric_key_prefixes` and adds no `metric_client_keys` row, so no client can bump a Dating key (S-2, §6.9).
- Derived special-category data: who was introduced to whom, who matched whom, and whether a moderation case involves a pair that is not man–woman can each reveal orientation. Introductions, interest actions, matches and couple-link requests are revoked from `service_role` too (read only through definer functions), and case routing is computed at read time, never stored (S-5, §6.4, §6.8).
- Error results are uniform and opaque (`*_unavailable`), and a membership check never branches before the validity checks (Fable H2).

### 4.2 Encryption at rest for special-category fields

- **Where:** table `dating_profile_sensitive` (one row per person) holds four ciphertext columns: `identity_enc` (identity, specific term, pronouns, pools), `seeking_enc`, `faith_enc` (faith, denomination, importance), `marital_enc`. Plus `key_version smallint`.
- **How:** `extensions.pgp_sym_encrypt(p_plain::text, v_key, 'cipher-algo=aes256, compress-algo=0')` (compression off, so ciphertext length does not leak content), decrypted with `pgp_sym_decrypt`. The key is the Vault secret `dating_field_key` (32 random bytes, base64), read through `public.app_setting('dating_field_key')`. Supabase Vault encrypts secrets with a root key held outside the database, so a leaked dump or backup holds ciphertext and an encrypted key only.
- **Who can decrypt:** two internal functions, `dating_field_encrypt(jsonb) → bytea` and `dating_field_decrypt(bytea) → jsonb`, owned by `postgres`, with `EXECUTE` revoked from `PUBLIC`, `anon`, `authenticated` **and** `service_role`. They are called only inside other definer functions: the own-profile reader, the setup writers, generation, the introduction reader (for fields the owner chose to show), the export builder, the fairness job, the kill-switch job and the console's routing check (which returns only a yes/no for "may this moderator see this case"). `dating_profile_sensitive` is also revoked from `service_role`, so the console, the Supabase table editor and edge functions cannot read it.
- **The one service-role path to plaintext (S-4).** The export builder is `dating_export_for_job(p_job_id uuid)`, the only decrypting function granted to `service_role` (used by the `build-data-exports` worker). It takes **no user id**: it reads `public.data_export_jobs` for that job, refuses unless the job is `building`, takes the user from the job row (created by the person's own `request_my_export()`), decrypts only that person's fields and own sent messages, records the call in `dating_export_reads` (job id, time; no content), and refuses a fourth call for the same job (the worker's three-attempt rule). So an edge function holding the service key can decrypt one person's data only by running an export that person asked for; it can never decrypt an arbitrary user id.
- **Generation** decrypts the candidates of one partition into a `CREATE TEMP TABLE … ON COMMIT DROP` inside its transaction. Temporary tables are not WAL-logged, so plaintext never reaches WAL, replicas or point-in-time backups.
- **Missing key = fail closed:** writers return `{"ok": false, "reason": "unavailable"}`, generation refuses to run, and `get_dating_operational_health()` reports `field_key_present = false`.
- **Rotation:** a new secret `dating_field_key_v2`; `rotate_dating_field_key()` (service role, batched) re-encrypts rows and bumps `key_version`; the old secret is deleted after the run reports zero rows on version 1.
- **What this does not protect against:** an attacker with live `postgres`-level SQL access (DPIA §6.8 states this; permanent constraint 9 already accepts Supabase-level encryption rather than end-to-end encryption).

### 4.3 Tables

**Changed existing tables**

| Table | Change |
|---|---|
| `dating_enrollments` | drop `adults_only_confirmed_at`; add `pause_reason text` (`user`, `relationship`, `path_change`, `same_gender_switch`, `away`, `account_parked`); keep the state machine (`ineligible`, `eligible_to_opt_in`, `profile_draft`, `active`, `paused`, `exited`, `suspended`) and `state_version` |
| `dating_consent_events` | purposes become `dating_terms`, `dating_opt_in`, `special_category_profile`, `special_category_faith`, `biometric_verification`; `historical_data` and `age_gate` removed (fresh start: old rows deleted) |
| `dating_profiles` | drop `city_region_code`, `relationship_intention`, `bio`, `gender_identity`; add `country_code char(2)`, `region_code text`, `side_code text`, `intention text CHECK (intention IN ('marriage','committed','companionship','not_sure'))`, `marriage_timeline text CHECK (… IN ('within_two_years','few_years','no_set_time'))`, `timeline_visible bool DEFAULT true`, `not_married_attested_at timestamptz`, `attestation_version text`, `children_have bool`, `children_want text CHECK (… IN ('yes','no','open'))`, `family_involvement text CHECK (… IN ('early','when_serious','our_decision'))`, `faith_visible bool DEFAULT false`, `marital_visible bool DEFAULT false`, `photos_after_mutual bool DEFAULT false`, `country_changed_at timestamptz`; `display_name` becomes 1–30 characters; keep `gender_visible`, `profile_state`, `moderation_state`, `profile_version`, `verification_state`, `verification_method`, `verified_at` |
| `dating_preferences` | age CHECK becomes 18–99; drop `gender_preferences`, `region_preferences`, `intention_preferences`; add `region_scope text CHECK (… IN ('side','region','country')) DEFAULT 'region'`, `intention_open text[]` (subset of the config matrix row; default = the row), `open_abroad char(2)[] DEFAULT '{}'`, `want_must_match bool DEFAULT false`, `exclude_parents bool DEFAULT false` |
| `dating_introductions` | drop `display_band`, `explanation_features`, `low_summary`, `high_summary`, `internal_score`, `snapshot_low_id`, `snapshot_high_id`; add `cohort_window date`, `partition_key char(2)`, `visible_from_low timestamptz`, `visible_from_high timestamptz`, `reasons text[]` (≤ 3 reason ids), `rank_detail jsonb` (internal: F, V, exposure, jitter; never returned); restore `UNIQUE (pair_key)` (dropped in `20260703203000`; no pair is ever introduced twice); `expires_at = greatest(visible_from_low, visible_from_high) + 7 days` |
| `dating_matches` | add `pair_key text NOT NULL` (generation already queries `dm.pair_key`, which does not exist today), `chat_started_at`, `low_moment_seen_at`, `high_moment_seen_at`, `low_we_met_at`, `high_we_met_at`, `low_swap_at`, `high_swap_at`, `closed_reason text CHECK (… IN ('unmatched','blocked','closed_kindly','exit','account_restricted','age_review','age_verification_invalid','couple_linked','other_linked','account_deleted'))`, `evidence_until timestamptz`; `user_low_id` / `user_high_id` become `ON DELETE SET NULL` with the order/self CHECKs rewritten to allow NULL |
| `dating_blocks` | unchanged shape; `block_dating_user` also writes `dating_block_hmacs` and closes the match |
| `dating_reports` | `reporter_user_id`, `target_user_id` → `ON DELETE SET NULL`; add `target_phone_hmac text` (filled whenever the key is present; health counts NULLs), `match_id` / `introduction_id` (SET NULL), `priority text CHECK (… IN ('P0','P1','P2','P3'))`, `reporter_tripped_family text` (family name only), `counts_for_corroboration bool`, `state text CHECK (… IN ('open','in_review','upheld','not_upheld','closed_no_action'))`, `sla_due_at`, `case_id`; categories = §3.7 |
| `dating_profile_photos` | position CHECK 1–6; add `caption text` (≤ 100, shown only to the owner), `csam_state text CHECK (… IN ('pending','clear','hit','error'))`; `rejection_reason` values `face_unclear`, `too_small`, `contains_child`, `unsafe`, `needs_review` |
| `dating_photo_moderation_config` | add `child_label_reject numeric DEFAULT 0.7`, `child_label_review numeric DEFAULT 0.5` |
| `dating_age_verifications` | reshaped: drop `birth_date`, `verification_method`, `expires_at`, `verified_by`; columns `user_id PK`, `age_method text CHECK (… IN ('fae','id'))`, `age_result text CHECK (… IN ('pass','fail'))`, `challenge_age smallint`, `identity_method text CHECK (… IN ('liveness_compare','human_gesture'))`, `identity_result text CHECK (… IN ('pass','fail'))`, `age_vendor text`, `identity_vendor text`, `decided_by uuid` (reviewer or NULL), `decided_at`, `revoked_at`, `revoke_reason text`. No images, no estimate value, no template |
| `dating_account_restrictions` | add `category text`, `source text CHECK (… IN ('report','moderator','csam_hash','age_assurance','carried_over'))`, `case_id uuid`, `decided_by uuid`, `appealable bool DEFAULT true`; keep the four types (`suspended`, `under_review`, `age_review`, `moderation_hold`) |
| `dating_algorithm_configs` | keep; seed `introductions_v2` (§5.11); retire `alignment_v1`; in production a trigger refuses `state = 'active'` when any review ref starts with `DEV-` |
| `dating_generation_runs` | `partition_key` = country code; `cohort_window` = the country's local date |
| `dating_former_partner_exclusions` | unchanged shape; recomputed from `auth.users` (W1) |

**New tables**

| Table | Columns (all with RLS on, revoked from clients) |
|---|---|
| `country_safety_config` | §2.2 |
| `dating_session_context` | `user_id PK`, `effective_tier`, `dating_allowed_here`, `same_gender_allowed_here`, `away_from_home`, `ip_resolved`, `mismatch_streak`, `trip_note_shown_at`, `checked_at` |
| `dating_profile_sensitive` | §4.2 (also revoked from `service_role`) |
| `dating_prompts` | `user_id`, `position smallint CHECK (1..3)`, `prompt_id text`, `answer text CHECK (char_length BETWEEN 10 AND 200)`, `moderation_state`, `updated_at`; PK (`user_id`, `position`) |
| `dating_settings` | `user_id PK`, `drop_time time DEFAULT '19:00'`, `data_saver bool`, `digest_push bool DEFAULT false`, `chat_push bool DEFAULT true`, `show_when_away bool DEFAULT false`, `updated_at` |
| `dating_gentle_wait_reflections` | `user_id PK`, `answers jsonb` (3 strings ≤ 500), `saved_at` |
| `dating_notify_requests` | `user_id PK`, `country_code`, `region_code`, `created_at` |
| `dating_never_introduce` | `id`, `owner_user_id → users ON DELETE CASCADE`, `phone_hmac`, `label text (≤ 20)`, `last_two char(2)`, `created_at`; UNIQUE (`owner_user_id`, `phone_hmac`); at most 50 per owner |
| `dating_block_hmacs` | `blocker_hmac`, `blocked_hmac`, `created_at`, `purge_after timestamptz` (NULL while both accounts exist); PK (`blocker_hmac`, `blocked_hmac`) |
| `enforcement_records` | `id`, `phone_hmac`, `scope text CHECK (… IN ('dating','opinions'))`, `source_restriction_id uuid UNIQUE` (NULL for none; makes the parking and deletion writes idempotent), `restriction_type`, `category`, `confirmed_report_count int`, `effect_until timestamptz` (NULL = permanent within retention), `purge_after timestamptz`, `created_at`; index on `phone_hmac`. This spec writes only `dating`. `opinions` is reserved for Spec 1's open item O4 (I-16): if the owner rules yes, Spec 1's later W9d (built after this spec's W1a) writes `opinions` records in `prepare_account_deletion` and restores them in `complete_sign_up`; if the owner rules no, the next Dating migration drops the value from the CHECK (§10 item 9) |
| `dating_trusted_devices` | `user_id`, `device_hash`, `verified_at`, `last_seen_at`; PK (`user_id`, `device_hash`); ≤ 3 per user |
| `dating_verification_sessions` | `id`, `user_id`, `kind ('activation','reverify')`, `step ('liveness','id','human')`, `vendor`, `vendor_session_ref`, `attempts smallint`, `state ('started','awaiting_review','passed','failed','expired')`, `created_at`, `expires_at` |
| `dating_messages` | `id`, `match_id → dating_matches ON DELETE CASCADE`, `sender_side text CHECK (… IN ('low','high'))`, `sender_user_id → users ON DELETE SET NULL`, `kind ('text','guided_answer','close_kindly')`, `question_id text`, `body text CHECK (char_length BETWEEN 1 AND 1000)`, `body_masked text`, `mask_version smallint`, `idempotency_key text`, `created_at`; UNIQUE (`match_id`, `sender_side`, `idempotency_key`); index (`match_id`, `created_at DESC`); revoked from `service_role` too (the worker reads bodies only through its claim function) |
| `dating_guided_skips` | `match_id`, `question_id`, `skipped_by_side`, `created_at`; PK (`match_id`, `question_id`) |
| `dating_chat_signals` | `user_id`, `match_id`, `bumped_at`; PK (`user_id`, `match_id`); in the `supabase_realtime` publication; `SELECT` granted to `authenticated` with policy `user_id = auth.uid()`; no content |
| `dating_message_safety_outbox` | `message_id PK`, `state ('pending','processing','done','dead_letter')`, `attempts`, `last_error_code`, `processing_started_at`, `completed_at` |
| `dating_safety_configs` | `version PK`, `state ('draft','active','retired')`, `config jsonb`, `config_hash`, `review_ref`, `activated_at` |
| `dating_safety_events` | `id`, `match_id`, `message_id`, `at_risk_user_id`, `rule_id`, `family`, `tier`, `config_version`, `source_event_key UNIQUE`, `dismissed_at`, `created_at` — never message text |
| `dating_opener_hashes` | `sender_user_id`, `match_id`, `hash`, `created_at`; purged after 30 days |
| `dating_report_evidence` | `report_id PK`, `snapshot_enc bytea` (the last 50 messages of both sides, encrypted with the field key), `message_count`, `created_at`, `purge_after` |
| `dating_moderation_cases` | `id`, `kind ('report','photo','verification','signal','appeal','csam_hit')`, `priority`, `target_user_id (SET NULL)`, `target_phone_hmac`, `report_id`, `match_id (SET NULL)`, `signal_kind`, `state ('open','in_review','decided','closed')`, `assigned_to`, `sla_due_at`, `created_at`, `decided_at`, `outcome`. **No routing column (S-5):** whether a case needs a sensitive-routing reviewer is computed at read time inside the console's definer functions (§6.4) and never stored |
| `dating_moderators` | `user_id PK`, `role ('moderator','safety_owner')`, `sensitive_routing_allowed bool`, `languages text[]`, `active bool` |
| `dating_moderation_actions` | append-only audit: `id`, `case_id`, `actor_id`, `action`, `target_user_id`, `detail jsonb` (no special-category values), `created_at`; UPDATE/DELETE blocked by trigger |
| `dating_appeals` | `id`, `restriction_id UNIQUE`, `user_id`, `text (≤ 500)`, `submitted_at`, `state ('open','accepted','rejected')`, `decided_by`, `decided_at`; CHECK in the decide function: `decided_by` ≠ the restriction's `decided_by`, unless `decided_by` is a `safety_owner` and `decided_at ≥ submitted_at + 24 h` |
| `dating_escalations` | `id`, `case_id`, `kind ('police','ncmec','iwf','csa','csa_292_with_consent')`, `recorded_by`, `recorded_at`, `reference` — a record of what a human did, never an automatic send |
| `law_enforcement_requests` | `id`, `received_at`, `jurisdiction`, `legal_basis`, `scope`, `target_user_id (SET NULL)`, `decision`, `disclosed_categories text[]`, `user_notified_at`, `decided_by` |
| `dating_couple_link_requests` | `id`, `match_id`, `requested_by_side`, `low_confirmed_at`, `high_confirmed_at`, `low_keep_messages bool`, `high_keep_messages bool`, `state ('open','linked','declined','cancelled','expired')`, `relationship_id`, `created_at`, `expires_at`; one open request per match |
| `couple_how_we_met` | `relationship_id PK → relationships ON DELETE CASCADE`, `items jsonb`, `created_at`; read through `get_how_we_met(relationship_id)` (members only); in the relationship export (W9 re-creates `export_relationship` from its live body to add it, I-13); purged with the relationship |
| `dating_export_reads` | `job_id → data_export_jobs ON DELETE CASCADE`, `read_at`; at most 3 rows per job; no content (S-4) |
| `dating_fairness_reports` | `week date`, `country_code`, `cohort_key`, `active_bucket text` (`50–99`, `100–499`, `500+`), `introductions_per_active numeric`, `mutual_rate numeric`, `flagged bool`; rows only for n ≥ 50 |

### 4.4 Functions

**Client RPCs** (granted to `authenticated`; each calls `dating_require_trusted_device()` except the device and availability calls; W1c creates that function as a pass-through that always allows, and W4b re-creates it with the real check, so no RPC has to be re-created to add the call; each mutation takes an idempotency key validated as in `claim_dating_idempotency`, claimed after the authorisation and validity checks):

| Group | RPCs |
|---|---|
| Home | `get_dating_home()`, `get_dating_availability()` (also `anon`) |
| Country notice | `request_dating_country_notice(p_country, p_region)`, `cancel_dating_country_notice()` |
| Gentle wait | `save_gentle_wait_reflection(p_answers jsonb)`, `get_my_gentle_wait_reflection()` |
| Consent, enrolment | `record_dating_consent(...)` (purposes changed), `begin_dating_enrollment(p_terms_version, p_key)` |
| Setup writers | `save_dating_intention(p_key, p_intention, p_timeline, p_timeline_visible, p_attested, p_marital, p_marital_visible)` · `save_dating_location(p_key, p_country, p_region, p_side, p_scope)` · `save_dating_identity(p_key, p_identity, p_specific, p_pronouns, p_extra_pools text[], p_visible)` · `save_dating_who_to_meet(p_key, p_seeking text[], p_min_age, p_max_age)` · `save_dating_children(p_key, p_have, p_want, p_must_match, p_exclude_parents)` · `save_dating_faith(p_key, p_faith, p_denomination, p_importance, p_visible)` / `clear_dating_faith(p_key)` · `save_dating_prompts(p_key, p_items jsonb)` · `save_dating_display_name(p_key, p_name)` · `save_dating_family_involvement(p_key, p_value)` · `save_dating_settings(p_key, p_values jsonb)` · `set_dating_open_abroad(p_key, p_countries char(2)[])` · `set_dating_photos_after_mutual(p_key, p_on)` |
| Photos | `create_dating_photo_upload_intent` (keep), `insert_dating_profile_photo` (positions 1–6), `delete_dating_profile_photo` (keep), `reorder_dating_photos(p_key, p_order uuid[])`, `list_dating_profile_photos` (keep, + caption) |
| Profile reads | `get_my_dating_profile()` (own, decrypted), `get_dating_profile_preview()` |
| Lifecycle | `activate_dating_profile(p_key)` (v2), `pause_dating_mode(p_key)`, `resume_dating_mode(p_key)` (new), `exit_dating_mode(p_key, p_keep_never_introduce bool)` (v2) |
| Introductions | `get_my_dating_today()`, `get_my_dating_introductions()` (v2), `act_on_dating_introduction(p_key, p_id, p_action)` (signature kept), `report_dating_introduction` (v2), `block_dating_introduction` (keep) |
| Matches, chat | `get_my_dating_matches(p_include_ended bool)` (v2), `mark_dating_match_moment_seen(p_match_id)`, `send_dating_message(p_key, p_match_id, p_body, p_kind, p_question_id)`, `get_dating_messages(p_match_id, p_before timestamptz, p_limit int)`, `get_dating_guided_state(p_match_id)`, `skip_dating_guided_question(p_match_id, p_question_id)`, `offer_dating_contact_swap(p_match_id)`, `withdraw_dating_contact_swap(p_match_id)`, `mark_dating_we_met(p_match_id)`, `close_dating_match_kindly(p_key, p_match_id)`, `unmatch_dating_match` (keep), `block_dating_match` (keep), `get_my_dating_safety_cards(p_match_id)`, `dismiss_dating_safety_card(p_event_id)`, `schedule_dating_checkin(p_at timestamptz)`, `cancel_dating_checkin()` |
| Reports, appeals | `report_dating_match(p_key, p_match_id, p_category, p_details, p_also_block)` (v2), `get_my_dating_restriction()`, `submit_dating_appeal(p_key, p_restriction_id, p_text)` |
| Never introduce | `add_dating_never_introduce(p_key, p_phone_e164, p_label)`, `remove_dating_never_introduce(p_id)`, `list_dating_never_introduce()` |
| Reflections | `save_private_date_reflection`, `record_dating_date_reflection`, `delete_private_date_reflection` (keep) |
| Couple link | `request_dating_couple_link(p_key, p_match_id, p_keep_messages)`, `confirm_dating_couple_link(p_key, p_request_id, p_keep_messages)`, `decline_dating_couple_link(p_request_id)`, `cancel_dating_couple_link(p_request_id)`, `get_dating_link_origin(p_relationship_id)` (members of that relationship only; anyone else, and a relationship with no Dating origin, gets the same opaque `link_origin_unavailable`, S-6), `get_dating_post_link_offer()`, `dismiss_dating_post_link_offer()` |
| Compatibility (W2 → W3a only) | `get_dating_eligibility()` shim (§2.1, I-4) |

**Internal and service-role functions** (never granted to clients; every production-mode check calls Spec 1's `private.attune_environment()`, and edge functions call `get_attune_environment()`, never an edge env var): `dating_eligibility(uuid, text)` (§2.1), `dating_pause_on_path_change()` (W2 trigger function, §4.9), `dating_on_account_parked()` (W1d trigger function, §6.3), `dating_candidate_is_current(uuid)` (v2), `dating_profile_ready(uuid)` (v2: active, approved, ≥ 2 approved photos, ≥ 2 approved prompts, identity and age passed, intention + attestation set, sensitive row present), `dating_age_gate_holds(uuid)` (v2), `dating_gentle_wait_opens_at(uuid)`, `dating_cool_off_ends_at(uuid)`, `dating_phone_canonical(text)` (`'+' || digits`), `dating_phone_hmac(text)` (keep), `dating_phone_hmac_for_user(uuid)` (reads `auth.users.phone`, or Spec 1's `users.parked_phone_hmac` for a parked account, I-11), `dating_pair_passes_hard_filters(uuid, uuid)` (v2), `dating_pair_is_man_woman(...)`, `dating_mask_contacts(text) → text`, `dating_field_encrypt/decrypt`, `dating_require_trusted_device()`, `dating_effective_context(...)`, `record_dating_session_context(p_user, …)` (service), `trust_dating_device(p_user, p_device_hash)` (service), `record_dating_age_assurance(p_user, p_age_method, p_age_result, p_challenge_age, p_vendor)` (service; replaces `verify_dating_age`), `record_dating_identity_check(p_user, p_method, p_result, p_vendor, p_decided_by)` (service), `revoke_dating_age_verification(p_user, p_reason)` (service, kept with a reason), `run_dating_generation_tick()` (service/cron), `send_dating_digests()` (cron), `claim_dating_safety_jobs(p_limit)` / `complete_dating_safety_job(...)` (service), `apply_same_gender_switch(p_country)`, `publish_country_config(p_country, p_values)` (service), `dating_photo_keys_for_viewer(p_viewer, p_kind, p_id)` (service, used by `dating-photo-urls`), `dating_export_for_job(p_job_id uuid)` (service, used by the `build-data-exports` worker; bound to a building export job, §4.2, S-4; there is no `dating_export_for_user(uuid)`), `dating_fairness_weekly()`, `purge_dating_retention()`, `moderation_*` functions (service, called only by the `dating-moderation` edge function with the moderator's id; the queue and case readers call the internal `dating_case_needs_sensitive_routing(case_id)` at read time, S-5), `get_dating_operational_health()` (v2), `rotate_dating_field_key()`.

### 4.5 RLS, grants and canaries

- All tables in §4.3: `ENABLE ROW LEVEL SECURITY`; `REVOKE ALL FROM PUBLIC, anon, authenticated`; `service_role` gets only what an edge function needs (sessions, cases, moderators, evidence via functions), and nothing on `dating_profile_sensitive`, `dating_messages`, `dating_introductions`, `dating_interest_actions`, `dating_matches` or `dating_couple_link_requests` (S-5; no edge function reads them today, and every later reader goes through a definer function). The revokes sit in the grants twins, after `20260931140000`'s default privileges, and the RLS canary asserts them.
- `dating_messages` additionally has an INSERT policy (defence in depth, even though the grant is revoked): the sender is a member of an `active` match, the match has no block in either direction (UUID or HMAC), and the sender has no live restriction. `send_dating_message` repeats the same checks, so a stale client cannot send after a block (chat spec §4.4).
- Every new function: `REVOKE ALL … FROM PUBLIC, anon`; `GRANT EXECUTE … TO authenticated` only for the client RPCs in §4.4. Grants live in the paired `*_grants.sql` files: applied locally with `psql -f` right after their migration, and replayed in CI through an `\i` line in `scripts/local_pg_grants.sql`.
- Storage: `dating-profile-photos` (exists, private; owner SELECT policy kept; counterparts get 60 s signed URLs only); `dating-verification-review` (new, private; INSERT by upload intent; no client SELECT; service role reads in the console; objects deleted at decision or 72 h by `purge_dating_retention`'s sweep, not by a trigger).
- **No `storage.objects` trigger (F-1).** This spec adds none. Dating photos are scanned inline (§3.2 D9), so Spec 1's F-1 spike on the hosted project and its fallback (enqueue from upload RPCs or a sweep) don't change anything here. If a later Dating change ever needs a `storage.objects` trigger, it is created and dropped as a no-op on the hosted development project first.
- **CI canaries** (W1): `supabase/tests/dating_rls_canary.sql` enumerates every relation and function whose name starts with `dating_` (plus `country_safety_config`, `enforcement_records`, `couple_how_we_met`, `law_enforcement_requests`) and fails when any has a grant not in its allow-list, so a new Dating table cannot ship readable; `supabase/tests/storage_bucket_policies.sql` asserts both buckets are private and lists their policies exactly; a gitleaks job in `.github/workflows/tests.yml`.

### 4.6 Crons

| Job | Schedule | Function | Change |
|---|---|---|---|
| `dating-candidate-generation` | `17 * * * *` (was weekly `17 3 * * 0`) | `run_dating_generation_tick()` — runs each country whose `generation_hour_utc` is the current hour and whose cohort is not done | replace |
| `dating-digest` | `5 * * * *` | `send_dating_digests()` — people whose drop time fell in the last hour | new |
| `expire-dating-introductions` | `17 * * * *` | `expire_dating_introductions()` (per-side lifetime) | keep, body changed |
| `revalidate-dating-lifecycle-gates` | `*/15 * * * *` | `enforce_dating_lifecycle_gates()` (v2 gates) | keep, body changed |
| `process-dating-safety-outbox` | `* * * * *` | edge function `process-dating-safety-outbox` | new |
| `purge-dating-retention` | `47 2 * * *` | `purge_dating_retention()` (§4.8) | new |
| `dating-moderation-sla` | `*/15 * * * *` | `dating_moderation_sla_check()` — content-free alert to `app_setting('moderation_alert_webhook')` ("P0 case waiting 3 h 40 m") | new |
| `dating-fairness-weekly` | `17 4 * * 1` | `dating_fairness_weekly()` | new |
| `recover-stale-dating-workers` | `*/5 * * * *` | resets `processing` outbox rows older than 10 minutes | new |

### 4.7 Edge functions and storage

| Function | Status | What it does |
|---|---|---|
| `dating-verification` | **new** (replaces `verify-dating-profile`) | `start`, `complete`, `start_id`, `complete_id`, `submit_human`, `reverify_start`, `reverify_complete` through the §3.3.5 seam; writes results through the service functions; rate limit 5 sessions a day; never logs images, estimates or vendor payloads; refuses `age_assurance_mode = 'fake'` when `get_attune_environment()` returns `'production'` |
| `dating-device-check` | new | resolves the IP country (never logged), takes the Android SIM/network country, calls `record_dating_session_context`, returns `{trusted, away, note}` |
| `dating-photo-urls` | new | user JWT → `dating_photo_keys_for_viewer` → `createSignedUrls` (60 s) |
| `process-dating-photo` | change | `csam_matcher.ts` inline first, the only CSAM scan for this bucket (S1 W7b; a match is copied to `safety-quarantine` and recorded through Spec 1's inline-match service function, I-10), then Vision with label detection for children; positions 1–6; slot-named rejection reasons |
| `build-data-exports` | change [W9] | one added step in the data phase: calls `dating_export_for_job(job id)` and writes the `dating` part; the existing parts are unchanged (I-13) |
| `process-dating-safety-outbox` | new | claims jobs, runs `_shared/dating_chat_safety.ts` (own normaliser and config), writes safety events and moderation signals; fail-open; dead-letter after 5 attempts |
| `dating-moderation` | new | the console API; requires a `dating_moderators` row and `aal2` (TOTP MFA) in the JWT; writes every action to `dating_moderation_actions` |
| `upload-dating-photo` | **remove** | a diagnostic wrapper the client never calls |
| `verify-dating-profile` | **remove** after W4 | replaced; it accepted a client-supplied base64 selfie (no liveness) and used `us-east-1` |

### 4.8 Retention

| Data | Kept | Then |
|---|---|---|
| Profile, preferences, sensitive row, prompts, settings, photos, gentle-wait reflection, date reflections | while Dating is set up | hard-deleted at exit or account deletion |
| Consent events | for the life of the account + 1 year after exit (proof of consent and withdrawal) | deleted; counsel confirms the minimum (W1 gate) |
| Introductions | while both people stay in Dating, so no pair is introduced twice | 30 days after an introduction is resolved (passed, matched, expired, invalidated), its `dating_interest_actions` rows are deleted and `low_action`, `high_action`, `reasons` and `rank_detail` are cleared, leaving ids, `pair_key`, `state` and dates; deleted when either person exits or deletes the account |
| Matches | while active; closed: 30 days (`evidence_until`) | row deleted after the window unless a report holds it |
| Dating messages | while the match is active; after close: 30 days | hard-deleted by `purge_dating_retention`, unless an open case holds the match |
| Report evidence snapshots | until the case closes + 180 days, or as long as a resulting enforcement record lasts (≤ 2 years after deletion) | deleted |
| Reports (anonymised after either side's deletion) | 2 years | deleted |
| Enforcement records, block HMAC pairs | 2 years after the account's deletion | deleted |
| Never-introduce list | while the owner is in Dating; at exit, deleted unless the person ticked "Keep" (unticked by default, R-2) | deleted with the account |
| Verification sessions | 30 days | deleted |
| Human-review photos | until decision, at most 72 h | deleted |
| Age assurance result | while the account exists | deleted with the account |
| Session context | overwritten; deleted after 30 days without a check | — |
| Safety events | 90 days, then anonymised per `SAFETY_SYSTEM_SPEC.md` §4.2 | — |
| Moderation cases and actions | 2 years | deleted |
| Law-enforcement request log | 2 years | deleted |
| Notify requests | until sent or cancelled | deleted |
| How-we-met card | with the relationship | purged with it |

### 4.9 Migrations, by wave and order (names only; timestamps at build time)

Each migration is listed by **name, purpose and order within its wave**. The implementer gives it a timestamp when the wave is built, in the actual build order and always later than every migration already applied (I-1, I-2). The file is `<timestamp>_<name>.sql`; its grants twin takes the next version in the repo's `…10` pattern (for example `…100000_<name>.sql` and `…100010_<name>_grants.sql`), so the two never share a version. Within a wave, files land in the order shown; batches land in letter order. Every shared function a migration touches is re-created from its live body (repo rules). No file names a table that a later wave creates.

| Wave | Order | Name | Contents |
|---|---|---|---|
| W1a | 1 | `dating_v2_phone_hmac` | `dating_phone_canonical`, `dating_phone_hmac_for_user` (prefers `users.parked_phone_hmac` when `users.phone_released_at` is set, I-11); exclusion recorder and predicate read `auth.users`; existing exclusions recomputed from ended and archived relationships; relationship guard trigger rewired from `handle_relationship_dating_guard` to `sync_dating_pause_on_relationship` (covers `paused`, null-safe; today it is orphaned) and the old function dropped |
| W1a | 2 | `dating_v2_enforcement_survival` | `enforcement_records`, `dating_block_hmacs`; reports and matches `SET NULL` + HMAC columns, `closed_reason` (first values) and `evidence_until`; `block_dating_user` writes HMAC pairs; standing check reads both; grants twin revokes `service_role` on introductions, interest actions and matches (S-5) |
| W1a | 3 | `dating_v2_account_deletion` | `prepare_account_deletion` re-created from its live body with the Dating steps (§6.3); the `metric_key_prefixes` row `dating.` (owner `spec2`); no `metric_client_keys` row |
| W1b | 1 | `dating_v2_country_config` | `country_safety_config` with seeds (all `dating_enabled` false), `publish_country_config` (no same-gender-off path and no notify queueing yet), `get_dating_availability`, `dating_session_context`, `record_dating_session_context`, `dating_effective_context`, `dating_notify_requests` (table only), flag `dating_same_gender_matching`; Spec 1's seam `private.dating_open_countries()` re-created from its live body over the table, then the `app_public_config.dating_open_countries` row deleted (I-3) |
| W1b | 2 | `dating_v2_eligibility_base` | `dating_eligibility(uuid, text)` with gates 1–4 and 6 (I-14); Spec 1's seam `private.dating_home_summary(p_user)` re-created from its live body, same `{enabled, enrolled}` shape: `enabled` = `dating_eligibility(p_user, 'setup') <> 'feature_unavailable'`, `enrolled` unchanged (an enrolment in `profile_draft`, `active`, `paused` or `suspended`) (I-4, A-10) |
| W1c | 1 | `dating_v2_profile_fields` | `dating_require_trusted_device()` as a pass-through (real check in W4b); profile and preference columns, `dating_profile_sensitive`, `dating_prompts`, `dating_settings`, encryption functions, setup writers, `get_my_dating_profile`, `get_dating_profile_preview` |
| W1d | 1 | `dating_v2_never_introduce` | table + three RPCs + hard-filter helper |
| W1d | 2 | `dating_v2_lifecycle` | `pause_reason`; `dating_profile_ready` v2, `activate_dating_profile` v2, `pause`/`resume`/`exit` v2 (hard delete; `p_keep_never_introduce` defaults false), `delete_dating_profile` dropped, consent purposes, no `users.mode` reference anywhere; the parked-account trigger `dating_on_account_parked` (§6.3); `apply_same_gender_switch` and `publish_country_config` re-created with it; generation refuses without either key; health v2 |
| W2 | 1 | `dating_v2_gentle_wait` | `dating_eligibility` re-created with gate 5 (window predicate, A-9); the Healing gate removed in five places and `dating_healing_gates_hold` dropped; `get_dating_eligibility()` re-created as the compatible shim (I-4); Healing status and message changed; the `users.path` trigger `dating_pause_on_path_change`, the only pauser for a change from Dating to anything but Relationship (`pause_reason = 'path_change'`; Spec 1's `set_user_path_internal` keeps the one → Relationship pause, D18, I-5); `get_dating_home` v1 |
| W3a | 1 | `dating_v2_client_reads` | notify-request RPCs; neutral push type `me_update` (I-9); `publish_country_config` re-created from its live body with the notify queueing (§2.7); the "owner read" policies dropped; grants twin revokes the `20260811120000` client `SELECT` grants; `get_dating_eligibility()` dropped (after the `lib/` grep test is green) |
| W3b | 1 | `dating_v2_setup_lists` | faith and denomination lists (and any reviewed region-list edits) published through `publish_country_config`, which keeps each row's `dating_enabled` |
| W3c | 1 | `dating_v2_photos` | photo positions 1–6, reorder, captions, `csam_state`, child-label config |
| W4a | 1 | `dating_v2_age_assurance` | `dating_age_verifications` reshaped, verification sessions, service writers (and the three-argument `place_account_hold` call for a far-below-18 estimate), match-closing reasons `age_review` / `age_verification_invalid`, `dating-verification-review` bucket and its INSERT policy |
| W4b | 1 | `dating_v2_trusted_devices` | `dating_trusted_devices`, `dating_require_trusted_device()` re-created with the real check, `trust_dating_device`; `dating_eligibility` re-created with gate 8 |
| W5a | 1 | `dating_v2_matching` | alignment and snapshot objects dropped, introduction and match columns, `UNIQUE (pair_key)`, config v2, hard filters v2, generation v2, generation cron |
| W5b | 1 | `dating_v2_today` | today/introductions/act v2, `dating_photo_keys_for_viewer`, match-moment marks, `send_dating_digests` and its cron |
| W5c | 1 | `dating_v2_signals` | `dating_moderation_cases` (signals; no routing column), dragnet throttle and the other §5.10 signals, `dating_fairness_reports`, `dating_fairness_weekly` and its cron |
| W6a | 1 | `dating_v2_chat` | `dating_messages`, `dating_chat_signals`, send/read RPCs, `dating_mask_contacts`, swap, `get_my_dating_matches` v2, RLS and block enforcement |
| W6b | 1 | `dating_v2_chat_safety` | outbox, safety configs and events, opener hashes, claim/complete, the outbox and stale-worker crons |
| W6c | 1 | `dating_v2_chat_guided` | guided skips, close kindly, we met, check-in RPCs, `scheduled_notifications_quiet_guard` re-created from its live body with `me_checkin` (R17), `purge_dating_retention` and its cron |
| W7a | 1 | `dating_v2_reports` | reports v2, evidence, cases extended (reports, appeals), restrictions v2, appeals, holds, carry-over at re-registration, `submit_dating_report` dropped |
| W7b | 1 | `dating_v2_moderation_console` | `dating_moderators`, `dating_moderation_actions` (append-only), `moderation_*` functions with read-time routing (S-5), SLA job and its cron |
| W7c | 1 | `dating_v2_escalations` | `dating_escalations`, `law_enforcement_requests`, the transparency summary query |
| W8b | 1 | `dating_v2_traveller` | `dating_eligibility` re-created with gate 7, traveller filtering in reads, mismatch signal, flag `dating_traveller_detection` |
| W9 | 1 | `dating_v2_couple_link` | link requests, confirm transaction, `couple_how_we_met`, link origin (members only, S-6), post-link offer, `dating_export_reads`, `dating_export_for_job` (S-4), `export_relationship` re-created from its live body with the how-we-met card (I-13), flag `dating_couple_link` |
| W10 | 1 | `dating_v2_launch_guards` | production-mode guards (checklist, `DEV-` refs, provider mode), `get_dating_launch_readiness()` (red unless `private.attune_environment()` returns `'production'`, R-6) |

W8a has no migration. Screens and other client work need none.

**Development switch-on is not a migration (R-6, I-15).** `supabase/sql/dev_enable_spec2_dating_flags.sql` (created in W1a, extended by every later batch) first runs Spec 1's guard `SELECT private.assert_development_project();`, which raises `env:not_development` (and so stops the script) unless the project reads `development` and, when `app.settings.supabase_url` is set, names the development project. In development it turns every Dating flag on, publishes GH and GB with `dating_enabled = true` (from W1b), activates the `introductions_v2` config with `DEV-` review refs (from W5a), and sets `age_assurance_mode = 'sandbox'` (`fake` on a local database, from W4a). **It never sets `attune_environment`**; nothing in this spec does. Migrations never turn a flag on (`20260705210000` forces them off on replay, and stays as it is).

### 4.10 Keep / change / replace / remove: every existing Dating object

Verdicts: **Keep** (no change) · **Change** (same object, edited) · **Replace** (a new object takes over; the old one is dropped) · **Remove** (dropped, nothing takes over). Wave in brackets.

**Two latent faults found while auditing (both fixed by W5's rewrite):**
- `dating_pair_passes_hard_filters` (`20260933170000:75`) queries `dating_matches.pair_key`, a column that does not exist (`20260712130000:82` says so), so the first run with the flag on fails with SQLSTATE 42703.
- `generate_dating_candidates_for_user` inserts with `ON CONFLICT (pair_key)`, but `20260703203000:188` dropped the only unique constraint on `pair_key` (42P10), and the insert omits the NOT NULL `algorithm_version`, `internal_score`, `snapshot_low_id` and `snapshot_high_id` (23502).
The contract tests only ever exercise generation with the flag off, which is why neither surfaced.

**A third:** the live trigger `relationship_dating_guard` still calls `handle_relationship_dating_guard()` (pending and active only). The newer null-safe `sync_dating_pause_on_relationship()` that Spec 3a extended to `paused` is attached to no trigger. Eligibility still blocks paused couples through `dating_has_relationship`, so the effect is limited, but W1 rewires the trigger.

**Tables**

| Object | Verdict | Detail |
|---|---|---|
| `dating_enrollments` | Change [W1] | drop `adults_only_confirmed_at`; add `pause_reason` |
| `dating_consent_events` | Change [W1] | new purposes; old `historical_data` / `age_gate` rows deleted |
| `dating_profiles` | Change [W1, W3] | §4.3 |
| `dating_preferences` | Change [W1] | 18–99; arrays → `region_scope`, `intention_open`, `open_abroad`, children toggles; gender sets move to the encrypted table |
| `dating_introductions` | Change [W5] | §4.3; `UNIQUE (pair_key)` restored |
| `dating_interest_actions` | Keep | audit of each person's action |
| `dating_matches` | Change [W1, W5, W6] | `pair_key`, chat and swap columns, `closed_reason`, `evidence_until`, FKs `SET NULL` |
| `dating_blocks` | Keep | plus `dating_block_hmacs` alongside |
| `dating_reports` | Change [W1, W7] | FKs `SET NULL`, HMAC, priority, state, categories |
| `dating_date_reflections` | Keep | private; deleted at exit |
| `dating_profile_photos` | Change [W3] | positions 1–6, caption, CSAM state |
| `dating_feature_snapshots` | Remove [W5] | trait features are no longer used |
| `dating_rpc_idempotency` | Keep | — |
| `dating_age_verifications` | Change [W4] | reshaped (§4.3); no DOB |
| `dating_account_restrictions` | Change [W7] | category, source, case, decider, appealable |
| `dating_algorithm_configs` | Change [W5] | `introductions_v2` seeded; `alignment_v1` retired; `DEV-` guard in production |
| `dating_generation_runs` | Keep | partition = country, cohort = local date |
| `dating_rate_limits` | Keep | pruned daily by `purge_dating_retention` (Fable M2) |
| `dating_former_partner_exclusions` | Change [W1] | recomputed from `auth.users` |
| `dating_photo_upload_intents` | Keep | — |
| `dating_photo_moderation_outbox` | Keep | — |
| `dating_photo_moderation_config` | Change [W3] | child-label thresholds |
| `scheduled_notifications.source_key` (added by a Dating migration) | Keep | shared column; Dating keys become opaque |

**Functions**

| Object | Verdict | Detail |
|---|---|---|
| `act_on_dating_introduction` | Change [W5] | v2 gates, per-side visibility, no push (the "New mutual match" insert is removed), viewer-scoped state kept |
| `activate_dating_profile` | Change [W1] | assurance + `dating_profile_ready` v2; no checkbox; no `users.mode` |
| `backfill_dating_former_partner_exclusions` | Change [W1] | reads `auth.users` |
| `begin_dating_enrollment` | Change [W2] | `dating_eligibility`; enforcement records checked |
| `block_dating_introduction`, `block_dating_match` | Keep | wrappers |
| `block_dating_user` | Change [W1, W6] | writes HMAC pair; closes the match (`blocked`); self-target is a silent no-op |
| `build_dating_feature_snapshot`, `dating_has_historical_consent`, `dating_normalize_scalar` | Remove [W5] | no trait or quiz inputs |
| `dating_alignment_score`, `dating_alignment_reasons`, `dating_component_similarity`, `dating_set_similarity` | Remove [W5] | no trait scoring, no bands |
| `bump_dating_enrollment_version`, `bump_dating_profile_version` | Keep | — |
| `check_dating_rate_limit`, `claim_dating_idempotency` | Keep | — |
| `claim_dating_photo_jobs`, `recover_stale_dating_photo_jobs`, `enqueue_dating_photo_processing` (Vault version) | Keep | — |
| `create_dating_photo_upload_intent`, `delete_dating_profile_photo` | Keep | — |
| `insert_dating_profile_photo`, `list_dating_profile_photos` | Change [W3] | positions 1–6; caption |
| `dating_account_in_good_standing` | Change [W1, W4] | enforcement records, age reviews |
| `dating_age_gate_holds` | Change [W4] | assurance result + `account_age ≥ 18`; no DOB table |
| `dating_candidate_is_current` | Change [W2, W5] | `dating_eligibility` + readiness + freshness |
| `dating_flag_enabled`, `dating_pair_key`, `dating_phone_hmac`, `dating_has_relationship` | Keep | — |
| `dating_former_partner_excluded`, `record_dating_former_partner_exclusion` | Change [W1] | HMAC from `auth.users` |
| `dating_healing_gates_hold` | Remove [W2] | replaced by the gentle wait inside `dating_eligibility` |
| `dating_pair_passes_hard_filters` | Change [W5] | rewritten (§5.2); fixes the `pair_key` fault |
| `dating_profile_ready` | Change [W1] | explicit sets, ≥ 2 photos, ≥ 2 prompts, both checks passed |
| `dating_photos_queue_media_before_delete` | Keep | — |
| `delete_dating_profile` | Remove [W1] | merged into `exit_dating_mode` (one hard delete) |
| `enforce_dating_age_verification_change` | Change [W4] | new shape; revocation closes matches (`age_verification_invalid`, fixes 04 G14) |
| `enforce_dating_lifecycle_gates` | Change [W2] | v2 gates |
| `enforce_dating_restriction_change` | Change [W7] | per type: hold hides and stops sending; `age_review` and `suspended` close matches |
| `exit_dating_mode` | Change [W1] | hard delete (§3.8); messages sealed 30 days |
| `expire_dating_introductions` | Change [W5] | per-side lifetime |
| `generate_dating_candidates_for_user`, `run_dating_candidate_generation` | Replace [W5] | `run_dating_generation_tick` (§5); W1 adds the key guard to the old one first |
| `get_dating_eligibility` | Change [W2], Remove [W3a] | W2: a compatible shim over `dating_eligibility(auth.uid(), 'setup')`, same return shape; W3a: dropped once no file in `lib/` calls it (I-4); `get_dating_home` takes over |
| `get_dating_operational_health` | Change [W1, each wave] | adds `environment` (from `private.attune_environment()`), `field_key_present`, `log_settings_safe`, enabled countries, verification backlog and oldest age, open P0 and oldest, SLA breaches, outbox dead letters, today's generation per country, `age_assurance_mode` |
| `get_my_dating_introductions` | Change [W5] | v2 payload (§3.4), no band, no explanation JSON |
| `get_my_dating_matches` | Change [W6] | ended-in-30-days section, swap and we-met state |
| `handle_relationship_dating_guard` | Remove [W1] | trigger rewired to `sync_dating_pause_on_relationship` |
| `sync_dating_pause_on_relationship` | Change [W1] | attached to `relationship_dating_guard` |
| `invalidate_dating_for_user` | Change [W4, W5] | no snapshots; new match-closing reasons (`age_review`, `age_verification_invalid`) |
| `invalidate_dating_on_photo_change`, `invalidate_dating_on_profile_change` | Keep | — |
| `pause_dating_for_relationship_user`, `pause_dating_mode` | Change [W1d] | no `users.mode`; `pause_reason`. `pause_dating_for_relationship_user` (reason `relationship`) is called by the relationship guard and by Spec 1's `set_user_path_internal` for a change to Relationship only; every other change away from Dating is paused by W2's `users.path` trigger with `path_change` (D18, I-5) |
| `record_dating_consent` | Change [W1] | purposes |
| `record_dating_date_reflection`, `save_private_date_reflection`, `delete_private_date_reflection` | Keep | — |
| `report_dating_introduction`, `report_dating_match` | Change [W7] | v2 categories, evidence snapshot, automatic steps |
| `resolve_dating_introduction_target`, `resolve_dating_match_target` | Keep | match states now include ended-in-window |
| `resolve_dating_verification_review` | Replace [W4] | `record_dating_identity_check` |
| `revoke_dating_age_verification` | Change [W4] | takes a reason |
| `save_dating_profile_draft` | Replace [W3] | the per-step writers in §4.4 |
| `submit_dating_report` | Remove [W7] | the raw-target foot-gun (Fable M1); v2 report RPCs write directly |
| `unmatch_dating_match` | Change [W6] | `closed_reason`, `evidence_until` |
| `verify_dating_age` | Replace [W4] | `record_dating_age_assurance` (no DOB argument) |

**Triggers, policies, grants, flags, crons, storage**

| Object | Verdict | Detail |
|---|---|---|
| `relationship_dating_guard` trigger | Change [W1] | calls `sync_dating_pause_on_relationship` |
| `private.dating_open_countries()` (Spec 1's seam) | Change [W1b] | re-created from its live body over `country_safety_config`; `get_public_app_config()` unchanged (I-3) |
| `private.dating_home_summary(p_user)` (Spec 1's seam) | Change [W1b] | re-created from its live body; `enabled` from `dating_eligibility`, `enrolled` unchanged; shape `{enabled, enrolled}` kept (I-4, A-10) |
| `app_public_config` row `dating_open_countries` (Spec 1) | Remove [W1b] | replaced by the derivation |
| `prepare_account_deletion` | Change [W1a] | Dating steps (§6.3), re-created from its live body |
| `export_relationship` | Change [W9] | re-created from its live body with the how-we-met card (I-13) |
| `scheduled_notifications_quiet_guard` | Change [W6c] | `me_checkin` exemption, re-created from its live body |
| `users` triggers `dating_pause_on_path_change` [W2] and `dating_on_account_parked` [W1d] | New | no-op unless their column changes in the stated way; never raise (R13, R19) |
| `set_dating_*_updated_at`, `bump_dating_*_version`, `invalidate_dating_on_*`, `enforce_dating_*_change`, `trigger_enqueue_dating_photo_processing`, `dating_photos_queue_media_before_delete` triggers | Keep | functions change as listed |
| Policies "dating enrollments/consent/profiles/preferences owner read", `dating_profile_photos_select_own` | Remove [W3] | reads move to RPCs |
| `20260811120000` `GRANT SELECT` to `authenticated` on the five tables | Remove [W3] | revoked in the W3 grants file |
| Storage policies `dating_profile_photos_insert_by_intent`, `dating_profile_photos_select_owner` | Keep | — |
| `feature_flags_authenticated_read` (hides `dating_%`) | Keep | — |
| Flags `dating_mode_enabled`, `dating_candidate_generation`, `dating_match_messaging` (now gates the dating chat), `dating_profile_photos` | Keep | — |
| Flag `dating_alignment_algorithm_v1` | Remove [W5] | — |
| New flags | — | `dating_same_gender_matching` [W1], `dating_age_assurance` [W4], `dating_traveller_detection` [W8], `dating_couple_link` [W9], `dating_voice_calls` [W11] |
| Cron `dating-candidate-generation` (weekly) | Replace [W5] | hourly tick (§4.6) |
| Crons `expire-dating-introductions`, `revalidate-dating-lifecycle-gates` | Keep | bodies change |
| Bucket `dating-profile-photos` | Keep | — |
| Vault secret `dating_exclusion_key` | Keep | **provision it** (W5 gate) |

**Edge functions and shared modules**

| Object | Verdict | Detail |
|---|---|---|
| `process-dating-photo` | Change [W3] | CSAM first, child labels, 1–6, slot reasons |
| `upload-dating-photo` | Remove [W3] | unused diagnostic wrapper |
| `verify-dating-profile` | Replace [W4] | `dating-verification` |
| `_shared/aws_rekognition.ts` | Keep | used by `FaceMatchProvider` |
| `_shared/google_vision.ts` | Change [W3] | adds label detection |
| `_shared/chat_safety.ts` (couples) | Keep, untouched | Dating gets `_shared/dating_chat_safety.ts` |
| `build-data-exports` | Change [W9] | adds the `dating` part through `dating_export_for_job` (S-4, I-13) |

**Client (`lib/features/dating/**`, 15 files)**

| File | Verdict | Becomes |
|---|---|---|
| `data/models/dating_enrollment.dart` | Change [W3] | states, no adults flag |
| `data/models/dating_introduction.dart` | Replace [W5] | `DatingIntroductionCard` model (age, reasons, photos policy; no band, no colours) |
| `data/models/dating_match.dart` | Change [W6] | ended state, swap, we met |
| `data/models/dating_profile_photo.dart` | Change [W3] | positions 1–6, caption, reason |
| `data/repositories/dating_repository.dart` | Replace [W3] | RPC-only repository; keeps an idempotency key per action until the widget is disposed (Fable H3c) |
| `domain/services/dating_feature_flags.dart` | Change [W3] | availability from `get_dating_home`; the no-op `DatingMonitoring` stub removed (Fable L4) |
| `domain/services/dating_image_preparer.dart` | Keep | 1600 px / ~300 KB / EXIF strip (existing EXIF test kept) |
| `presentation/providers/dating_providers.dart` | Replace [W3] | per-state providers, disposed on leaving Dating |
| `presentation/screens/dating_dashboard_screen.dart` | Replace [W3, W5] | `DatingSection` (§3.1) and Today (§3.4) |
| `presentation/screens/dating_consent_screen.dart` | Replace [W3] | D4; the "I am 18" and historical-data checkboxes removed |
| `presentation/screens/dating_profile_screen.dart` | Replace [W3] | step screens D2, D3, D5–D8, D10 (6 Ghana cities, free-text intention, 18–70 removed) |
| `presentation/screens/dating_photos_screen.dart` | Change [W3] | D9 |
| `presentation/screens/dating_verification_screen.dart` | Replace [W4] | §3.3 |
| `presentation/screens/dating_matches_screen.dart` | Change [W6] | conversations list; "chat safety review is still a production gate" copy removed |
| `presentation/screens/dating_guided_date_screen.dart` | Change [W6] | the meeting kit; keeps the private reflection |

**Outside the feature folder**

| Object | Verdict | Detail |
|---|---|---|
| `app_router.dart` Dating route block and `RouteNames.dating*` | Replace [W3] | §3.14; the `/dating-mode` FeatureIntro route removed; nothing else in the file changes |
| `notification_config.dart` | Change [W3a, W6c, W10] | W3a: case `me_update` → `/home?tab=me`; W6c: case `me_checkin` → `/dating/checkin` behind the Dating lock (I-9); the old `dating_mutual_match` case routes to Me for one release and is removed in W10 (A-7). Distinct cases only |
| `quick_exit_service.dart`, `lib/features/auth/providers/auth_provider.dart` | **Not edited** | Spec 1 owns both and the device wipe registry behind them; W8a registers Dating's entries there from a Dating file (C-2, C-3) |
| `lib/app/device_wipes.dart` (Spec 1) | Change [W8a] | exactly one added line, `registerDatingDeviceWipes()` (Spec 1 §5.8) |
| `lib/main.dart` and the shared Supabase client set-up | **Not edited** | the device header comes from the Dating-scoped client (C-6, S-7) |
| `lib/features/me/presentation/widgets/dating_slot.dart` (Spec 1) | Change [W3a] | the slot body renders `DatingSection`; nothing else in Spec 1's Me files |
| `lib/features/chat/presentation/screens/conversations_screen.dart` | Change [W9] | one `HomeCard` (`link_offer`) appended to the `ReorderableHomeCards` list while an offer exists (C-4); the chat card, the other cards and Games entry points untouched |
| `android/.../MainActivity.kt` channel `attune/safety` | Change [W8] | adds `setSecure(bool)` |
| `AndroidManifest.xml`, iOS `Info.plist` / asset catalogue | Change [W8] | plain-icon activity-alias and alternate icon |
| `dating_mode_docs.dart` | Replace [W3] | rewritten manual topic (no Healing gate, the new rules) |
| `healing_docs.dart` Dating topics | Change [W2] | rewritten: "Healing is there for you; it never decides when you can date" |
| `about_attune_docs.dart:74` | Change [W2] | "matched on who you actually are in relationships" → "introduced on what you both say you want" |
| `manual_documentation_registry.dart` | Change [W3] | Dating topic declares its flags (the guard test stays green) |
| `readiness_scoring_service.dart`, `healing_journey.dart`, `healing_journey_screen.dart`, `healing_repository.dart` (`eligible_for_dating_opt_in` in its status list) | Change [W2] | Dating eligibility removed (§2.1) |
| `chat_couples_locked_screen.dart` "Meet someone in Dating mode" | — | removed by S1 W3b unconditionally (listed in S1 §5.2, not behind `flow_paths_v2`; R-5); this spec relies on it and doesn't edit the file |

**Docs and tests**

| Object | Verdict | Detail |
|---|---|---|
| `DATING_MODE_SPEC.md`, `DATING_CHAT_SAFETY_SPEC.md` | Change [W2–W7] | §1.5 |
| `DATING_MODE_REVIEW_AND_GATES.md`, `DATING_MODE_RELEASE_READINESS_CHECKLIST.md` | Replace [W10] | this spec's §8 gates and `get_dating_launch_readiness()` |
| `DATING_MODE_CULTURAL_REVIEW_PACKET.md`, `DATING_MODE_CLINICAL_REVIEW_PACKET.md`, `DATING_MODE_REVIEWER_OUTREACH_TEMPLATES.md` | Change [W2, W3] | §1.5 |
| `DATING_MODE_DATING_CHAT_SAFETY_PLAN.md` | Change [W6] | marked superseded |
| `docs/reviews/DATING_REVIEW_FABLE.md` | Keep | historical; its open items are closed here: M3 (reasons from ids only), M4 (opaque keys), M5 (appeals), M6 (separate consents), M7 (caps at generation), M8 (no countdown), L1 (no colour bands), L3 (resume), L4, L5 (honest report copy) |
| `supabase/tests/dating_mode_contracts.sql` | Change [W1–W7] | rewritten for v2; the four-account non-enumeration proof (C1) is kept and extended |
| `supabase/tests/dating_alignment_contracts.sql` | Replace [W5] | `dating_v2_matching_contracts.sql` |
| `supabase/tests/dating_exclusion_wiring_test.sql` | Change [W1] | `auth.users` source + the tamper case |
| `supabase/tests/data_export_contracts.sql:229-233` | Change [W9] | asserts the own-data `dating` section |
| `test/features/dating/*` (4 files), `test/app/routing/feature_intro_route_wiring_test.dart`, `test/core/intro/seen_feature_intro_store_test.dart` (`datingMode` key), `test/features/healing/readiness_scoring_service_test.dart` | Change [W2–W4] | follow the replaced screens and the removed eligibility |

---

## 5. Matching and ranking

Profiles cannot predict chemistry between two particular people (Joel 2017; Dyrenforth 2010; 03 §2.1). So matching does two things only: it introduces people who **can** be together (feasibility) and who **say** they want the same things (stated values), and it spreads introductions fairly. Nothing else is an input.

### 5.1 Inputs (per person, read at generation)

| Input | Source | Used for |
|---|---|---|
| Age | `account_age(user)` (Spec 1 DOB; assured by §3.3) | filter |
| Age range | `dating_preferences.min_age`, `max_age` | filter |
| Identity, pools, seeking | `dating_profile_sensitive` (decrypted in the run) | filter |
| Dating country, region, side, scope | `dating_profiles`, `dating_preferences.region_scope` | filter, feasibility |
| Open abroad | `dating_preferences.open_abroad` | filter |
| Intention, timeline | `dating_profiles` | filter (matrix), feasibility, values |
| Intentions open to | `dating_preferences.intention_open` | filter |
| Children have / want, must match, exclude parents | `dating_profiles`, `dating_preferences` | filter, feasibility |
| Faith, importance | `dating_profile_sensitive` | filter (must share), values |
| Family involvement | `dating_profiles` | values |
| Visibility toggles | `dating_profiles` | which reasons may be shown |
| Session context | `dating_session_context` | filter (allowed here, freshness) |
| Phone HMAC | `dating_phone_hmac_for_user` | blocks, exclusions, never-introduce |
| Recent exposure | count of introductions the person was in during the last 7 days | ordering only |
| Capacity | today's count, waiting count, open pre-date chats | caps |

**Never inputs:** quiz results (attachment, communication, conflict, love language), Healing, journal, reflections, photos or anything derived from them, popularity, interest received, reply speed, activity beyond the freshness rule, reports, safety events, location history, nationality, phone network.

### 5.2 Hard filters (all must pass, in both directions)

`dating_pair_passes_hard_filters(a, b)` returns true only if every row holds for (a, b) **and** for (b, a):

| # | Filter |
|---|---|
| 1 | Both are current candidates: `dating_eligibility = 'eligible'`, enrolment `active`, `dating_profile_ready`, both checks passed, `checked_at` within 14 days, not traveller-hidden (§2.5), cool-off over at the person's next drop time |
| 2 | a's age is within b's range |
| 3 | a's seeking set meets b's pools |
| 4 | If the pair is not man–woman: the global flag, both Dating countries' `same_gender_enabled`, and both people's `same_gender_allowed_here` (checked within 7 days) |
| 5 | Same Dating country; or cross-border per §2.6 |
| 6 | Same country: b is inside a's scope (`side` = same region and side; `region` = same region; `country` = same country) |
| 7 | b's intention is in the config matrix row for a's intention **and** in a's `intention_open` |
| 8 | If a's `want_must_match`: not (a wants `yes` and b wants `no`) and not (a wants `no` and b wants `yes`); `open` fits everything |
| 9 | If a's `exclude_parents`: b has no children |
| 10 | If a's faith importance is "must share": b stated the same faith tradition (not "Prefer not to say", not skipped) |
| 11 | No block either way, by UUID (`dating_blocks`) or by phone HMAC pair (`dating_block_hmacs`) |
| 12 | Not former partners (`dating_former_partner_excluded`, both directions) |
| 13 | b's phone HMAC is not on a's never-introduce list |
| 14 | Never introduced before (`UNIQUE (pair_key)`; this also covers any earlier match, which always had an introduction) |
| 15 | Neither has an open moderation removal from generation (P1 step, uncorroborated P0 step, dragnet throttle at 0) |

The intention matrix (config, symmetric by construction and by contract test):

| a's intention | b may be |
|---|---|
| Marriage | Marriage, A committed relationship |
| A committed relationship | Marriage, A committed relationship, Companionship, Not sure yet |
| Companionship, at my own pace | A committed relationship, Companionship, Not sure yet |
| Not sure yet | A committed relationship, Companionship, Not sure yet |

### 5.3 Capacity and cadence

For each person p at generation time:
- `today(p)` = introductions p is in that were created in the last 20 hours (one run per country per day; 20 h stops a second partition counting twice).
- `waiting(p)` = introductions visible to p (or becoming visible at the next drop), not acted on by p, not expired.
- `open_chats(p)` = active matches where neither tapped "We met" and either a message was sent in the last 14 days or the match is under 7 days old.
- `capacity(p)` = 0 if `open_chats(p) ≥ 3`; otherwise `min(3 − today(p), 6 − waiting(p))`, floored at 0; and at most 1 while a dragnet throttle applies (§5.10).
- Creating an introduction uses one unit of capacity for **both** people.
- `visible_from` for each side = that person's next drop time (`dating_settings.drop_time` in `users.timezone`, default the country's `reference_tz`) after the run, and not before `users.created_at + 72 h`. `expires_at` = the later of the two `visible_from` values + 7 days. Missed days don't stack and there is no refresh.

### 5.4 Ranking

Run per country partition (§5.5). Within it:

1. **Order the people** by recent exposure ascending (fewest introductions in the last 7 days first), ties broken by `md5(seed || user_id)`. People new to Dating therefore go first.
2. For each person U with capacity, take every candidate c with capacity that passes §5.2 against U.
3. **Feasibility F(U, c)**, 0–3: +1 same intention; +1 children-want both `yes` or both `no`; +1 same region (or same side where both set one).
4. **Stated values V(U, c)**, 0–4: +1 same marriage timeline (both Marriage); +1 same faith importance; +1 same faith tradition (both stated); +1 same family involvement (both answered).
5. **Base** = 10·F + 3·V.
6. **Band:** keep candidates with base ≥ (best base − 3). This keeps the same feasibility and at most one stated value less than the best.
7. **Order within the band** by `exposure_7d(c) + jitter(U, c)`, where `jitter` = (the first 3 bytes of `md5(seed || U || c)` as an integer, mod 1000) / 1000 × 2.0. Lower is first. This is the bounded randomisation: it can reorder people whose exposure differs by less than 2, and never lifts someone outside the band.
8. Pick candidates in that order until U's capacity is used. Each pick inserts the introduction (`ON CONFLICT (pair_key) DO NOTHING`), lowers both capacities, raises c's exposure by 1 for the rest of the run, and stores `rank_detail = {F, V, exposure, jitter}` and `reasons` (§5.8).

Not used, at any step: popularity, attractiveness, interest received, activity or reply speed, traits, photos.

### 5.5 Cohorts, partitions, schedule

- The cron tick runs hourly at :17 and processes each country whose `generation_hour_utc` equals the current UTC hour (both GH and GB: 03). Partition key = the Dating country; cohort window = that country's local date in `reference_tz`.
- Runs are claimed in `dating_generation_runs` with `UNIQUE (algorithm_version, cohort_window, partition_key)`; a failed run retries up to 3 times, then dead-letters and shows in health.
- The candidate set of a partition is its own people plus people from other countries who opted into it and pass §2.6.
- **Refusals before any work** (each returns `{"skipped": reason}` and writes a health event): either flag off; no active config; `dating_exclusion_key` or `dating_field_key` missing; `country_safety_config` row not current.
- The run's people and candidates are decrypted into `CREATE TEMP TABLE dating_gen_people (...) ON COMMIT DROP` once per partition (§4.2).
- Bounds: at most 5,000 people per partition run and 500 candidates scanned per person (config); a partition larger than that splits by region automatically (partition key `GH:GA`), keeping the same cohort.

### 5.6 Thin pools

- Filters are never relaxed to fill a day, and no one is padded in.
- An empty day writes `dating.empty_day.{country}.{region}` to `metric_counters` and shows the honest copy (§3.4).
- Widening is only ever the person's choice, through the "Widen who I meet" sheet.
- People with no candidates for 14 days in a row see, once: "It's quiet in {region} right now. Widening your ages or area can help, or you can pause and come back later." [Widen who I meet] [Pause Dating].

### 5.7 Determinism and replay

- `seed = encode(extensions.digest(algorithm_version || cohort_window || partition_key, 'sha256'), 'hex')`, stored on the run row.
- Given the same config, seed and inputs, the run produces the same introductions in the same order (contract test runs the same partition twice into two scratch schemas and compares).
- `rank_detail` and `reasons` are stored on each introduction for replay and audits; neither contains special-category values (`V` is a count; faith reasons are stored only when both people show faith, §5.8). Neither is ever returned to a client.
- The config is hashed (`config_hash`) and versioned; a change of weights is a new version with review references (the CHECK from `20260705210000` stays).

### 5.8 "Why you two were introduced"

Reasons are reason ids chosen at generation from what both people stated **and may be shown**: a field contributes only if it is always visible (intention, region, children) or both people turned it on (timeline, faith). Family involvement is shared ground only and may be cited. At most 3, in this priority order, then always the closing line.

| Reason id | Copy |
|---|---|
| `same_intention_timeline` | "You both said marriage, {timeline phrase}." |
| `same_intention` | "You're both looking for {intention phrase}." |
| `compatible_intention` | "You both want something committed." |
| `children_want_yes` / `children_want_no` | "You both want children." / "Neither of you wants children." |
| `children_have_both` | "You both have children." |
| `same_faith` (both visible) | "You're both {faith}." |
| `faith_matters` (both visible) | "Faith matters a lot to you both." |
| `family_same` | "You both want family involved early." / "…once it's serious." / "You'd both make the decision yourselves first." |
| `same_side` / `same_region` | "You're both in {side} / {region}." |
| (always) | "Attune can't predict chemistry; meeting is how you find out." |

If no reason applies (every hard filter passed, nothing shared beyond them), the card shows `same_region` or, across borders, "You're both open to meeting across borders." The phrase table lives in the ARB file; reviewed copy only; nothing is generated per pair or by an LLM (fixes Fable M3: the client renders ids, never free text).

### 5.9 Fairness checks

- `dating_fairness_weekly()` (Mondays) computes, per country and per audited cohort, introductions per active person and the mutual-interest rate over the last 4 weeks. Cohorts: region; age band (18–24, 25–34, 35–44, 45–54, 55+); gender group (woman, man, and non-binary-or-specific together). Gender is decrypted inside the job and only aggregates leave it.
- A cohort is reported only at n ≥ 50 active people; smaller cohorts are suppressed, not merged into "other".
- **Flag** when a cohort's introductions per active person or mutual-interest rate is below 0.8× the country's rate, or when the top 10% of people receive more than 25% of a country's introductions. Flags go to the safety owner in the console; there is no automatic re-weighting. A change in response is a new config version with a `fairness_review_ref`.
- No race, ethnicity or skin-tone data is collected, so those cohorts cannot be audited; the vendor's demographic error data covers verification (§3.3.5). This limit is stated in the DPIA.

### 5.10 Behaviour signals (to the moderation queue, never automatic bans)

| Signal | Rule | Effect |
|---|---|---|
| Dragnet | ≥ 15 introductions in 14 days, "Interested" on ≥ 90% of them, and a first message in ≤ 20% of the resulting matches | case `signal`; capacity throttled to 1 a day until a moderator decides |
| Duplicate opener | the same normalised first message (`dating_opener_hashes`) in ≥ 3 matches within 7 days | case `signal` |
| Repeated money asks | `financial_request` events against ≥ 2 different recipients within 7 days | case `signal` (P1 priority) |
| Repeated sexual pressure | `sexual_pressure` events against ≥ 2 recipients within 7 days | case `signal` |
| Location mismatch | `mismatch_streak` reaches 7 | case `signal` (low priority) |
| Several Dating accounts on one device | ≥ 2 Dating activations from one trusted-device hash within 30 days | case `signal` |

Country, network, phone prefix, name and region are never inputs to any signal.

### 5.11 Configuration `introductions_v2`

```json
{
  "daily_new_max": 3,
  "waiting_max": 6,
  "open_chat_pause_at": 3,
  "open_chat_active_days": 14,
  "lifetime_days": 7,
  "cool_off_hours": 72,
  "cross_border_min_account_days": 14,
  "photos_after_mutual_min_account_days": 30,
  "context_fresh_days": 14,
  "same_gender_context_fresh_days": 7,
  "rank": { "feasibility_weight": 10, "values_weight": 3, "band_width": 3,
            "exposure_window_days": 7, "jitter": 2.0 },
  "intention_matrix": {
    "marriage": ["marriage", "committed"],
    "committed": ["marriage", "committed", "companionship", "not_sure"],
    "companionship": ["committed", "companionship", "not_sure"],
    "not_sure": ["committed", "companionship", "not_sure"]
  },
  "default_ages": { "young_until": 20, "young_plus": 7, "minus": 5, "plus": 5 },
  "dragnet": { "min_intros": 15, "window_days": 14, "interested_ratio": 0.9,
               "first_message_ratio": 0.2, "throttled_daily_max": 1 },
  "reasons_max": 3,
  "partition_people_max": 5000,
  "scan_limit": 500,
  "max_attempts": 3
}
```

The pilot may lower `daily_new_max` to 2 by publishing a new config version (Q14 "pilot 2 vs 3"); it can never exceed 3 (a CHECK on the config).

---

## 6. Safety, moderation and privacy

### 6.1 Dating chat safety (W6)

**Pipeline.** `send_dating_message` stores the message, computes `body_masked`, enqueues `dating_message_safety_outbox`, bumps `dating_chat_signals` for the recipient and returns. The worker `process-dating-safety-outbox` (every minute) runs the deterministic engine in `_shared/dating_chat_safety.ts` against the active `dating_safety_configs` row and writes `dating_safety_events` for the **recipient only**. Delivery never waits on safety (fail-open); a config that fails to load means no detection, never the couples config (chat spec §9). No LLM anywhere.

**Families** (chat spec §3.1 plus the additions; tiers as in its §3.2: tier 1 = recipient card; tier 2 = card + moderation case; tier 3 = case only):

| Family | Tier | Recipient card (exact copy) |
|---|---|---|
| `sexual_pressure` | 1 | "Messages like this can feel like pressure. You don't have to reply. You can block or report {Name} at any time." |
| `harassment_abuse` | 1 | "Nobody should talk to you like this. You can block or report {Name}." |
| `contact_migration_pressure` | 1 (more sensitive in the first 14 days) | "It's safer to keep talking here until you've met. Your number stays hidden until you both tap Swap contacts." |
| `meet_private_pressure` (new) | 1 | "For a first meeting, choose a public place and get there and back on your own. Someone who's right for you will understand." [Plan a meet] |
| `threat_intimidation` | 2 | "If someone threatens you, your safety comes first. Keep the messages and report here. If you're in danger now, call {emergency number}." |
| `financial_request` | 2 (more sensitive in the first 14 days) | "Asking for money early is the most common scam pattern. You don't owe anyone money, airtime or mobile money to meet. Never send money to someone you haven't met." [Report as a scam] |
| `sextortion` (new) | 2 | "If someone threatens to share pictures or videos of you: don't pay, keep the messages, and report here. You can also contact {sextortion resource}. This isn't your fault." |
| `child_access` (new) | 2 | "Questions about someone's children this early can be a warning sign. You don't have to share anything about your children." |
| `age_signal` | 3 | — |
| `identity_inconsistency` | 3 | — |

`{emergency number}` and `{sextortion resource}` come from S1 W7a's `support_resources` for the recipient's country (Ghana's sextortion entry is CSA 292, call or text, 04 §2.4.1; the UK entry is the Revenge Porn Helpline and StopNCII, as verified in `support_resources`). Every card has [Report] [Block] [Dismiss]; dismissing never lowers later sensitivity.

**Lexicon** (versioned in `dating_safety_configs`; English, Ghanaian and Nigerian English and Pidgin are written here; Twi, Ga and Ewe entries and spellings are written by the Ghanaian cultural reviewer with golden fixtures at the W6 gate; every entry is stored in Spec 1's match form, see the normaliser below):
- `financial_request`: "momo", "mobile money", "momo number", "send me momo", "airtime", "credit me", "top me up", "recharge card", "data bundle", "buy me data", "send me small", "small money", "transport fare", "t-fare", "money for transport", "school fees", "hospital bill", "on admission", "customs fee", "clearing fee", "release fee", "gift card", "itunes card", "steam card", "western union", "moneygram", "bitcoin", "btc", "usdt", "crypto", "forex", "investment platform", "trading account", "double your money", "I sent it by mistake", "send it back", "wrong transfer", "reverse the money", "abeg send", "dash me", "help me with small", "my account is blocked", "my card is blocked", and the Twi "sika" (money); first-14-days rule from chat spec §3.3 kept.
- `sextortion`: "video call naked", "I have your video", "I will post your pictures", "I'll send it to your family", "send to your contacts", "expose you", "make it viral", "leak your", "pay or I", "unless you pay".
- `contact_migration_pressure`: "add me on whatsapp", "my whatsapp is", "let's move to telegram", "text me on", "call me on", "snap me", "dm me on ig", "this app is not safe", "I don't use this app much".
- `meet_private_pressure`: "come to my place", "come to my house", "I'm home alone", "come over tonight", "my room", "I'll send my location", "meet me at my hotel".
- `child_access`: "send a picture of your daughter", "send a picture of your son", "how old are your kids", "what school do your children attend", "when are the kids alone", "can I meet your children alone", "do you leave them with".
- `age_signal` (tier 3): "I'm in form 2", "SHS", "JHS", "after BECE", "my WASSCE", "housemistress", "my class teacher", "year 10", "year 11", "GCSEs", "sixth form", "I'm 15", "I'm 16", "I'm 17".
- `threat_intimidation`, `sexual_pressure`, `harassment_abuse`, `identity_inconsistency`: the chat spec v1 phrase sets, plus Pidgin variants from the cultural reviewer.

**Normaliser: Spec 1's, imported (I-17).** `_shared/dating_chat_safety.ts` (new; the couples `chat_safety.ts` is not touched) imports Spec 1 W9a's `supabase/functions/_shared/unicode_normaliser.ts` and has **no fold table of its own**; Spec 1 W9a owns the rules, `_shared/unicode_fold_table.json` and the goldens file, so a Twi or Pidgin term normalises the same way in a Dating chat as in a D10 prompt (which uses S1's `private.content_filter_verdict`). Any rule change is made once, in Spec 1's table and goldens, and both suites re-run. The two forms it provides:
- **Base form** (`baseForm`): NFKC, lowercase, zero-width, soft-hyphen and bidi controls removed, the confusables map, separators to single spaces; letters kept as typed (ɛ, ɔ, ŋ stay), digits and `$` keep their meaning.
- **Match form** (`matchForm`): the base form plus the West African fold (ɛ→e, ɔ→o, ŋ→ng and the rest of Spec 1's table) and leetspeak (0→o, 1→i, 3→e, 4→a, 5→s, 7→t, @→a, $→s). Distinctive terms also match in the separator-free (squashed) match form, which catches zero-width splits.

**Which form each family matches.** Lexicon terms are stored in the match form, so one spelling covers a Twi word typed with or without ɛ/ɔ. `financial_request`, `sextortion`, `contact_migration_pressure`, `meet_private_pressure`, `child_access`, `threat_intimidation`, `sexual_pressure`, `harassment_abuse` and `identity_inconsistency` match in the **match form** (`m0m0` → `momo`, `a1rtime` → `airtime`); any amount pattern the reviewer adds to `financial_request` (`$`, `₵`, `£` with digits) matches in the base form. `age_signal` matches in the **base form only**, because leetspeak would turn "I'm 16" into letters.

**Contact masking** (`dating_mask_contacts(text)`, SQL, `IMMUTABLE`, versioned by `mask_version`; applied at insert to fill `body_masked`; also used on prompts in D10). Each span becomes "•••":
- Phone numbers: 7 or more digits allowing spaces, dots, dashes, slashes and brackets, with or without `+` (covers Ghana `024 123 4567`, UK `07…`, Nigerian `080…`, 10-digit NUBAN, mobile-money numbers); letters O/o between digits count as 0. Calendar dates (`dd/mm/yyyy`, `yyyy-mm-dd`, `dd.mm.yy`) are excluded first.
- Numbers in words: 7 or more consecutive tokens from zero, oh, o, one … nine, double, triple (and the reviewer's Twi number words).
- Emails, including "name at gmail dot com".
- URLs and bare domains (`www.`, a scheme, or a name with a common TLD: .com .net .org .gh .ng .uk .co .io .me .app .link .ly), including "dot com" spelled out.
- Handles: `@name`, and a platform word (snap, snapchat, ig, insta, instagram, telegram, tg, tiktok, fb, facebook, whatsapp, wa, signal, x, twitter) followed by a handle.
- Crypto addresses (`0x` + 40 hex; `T` + 33 base58; `bc1` + 25–62).
- If the function raises, the message is stored with every digit run and `@`/URL-like token masked (fail closed for presentation, never blocking delivery).
- `get_dating_messages` returns `body_masked` until both `low_swap_at` and `high_swap_at` are set, then `body`. Masking never lifts by itself (10 F-11).

**Swap** is offered only from 72 h after the match; either person may withdraw an offer until both have swapped; after both, it cannot be undone.

### 6.2 Reports

| Priority | Categories | Automatic step on one report (never a ban) | Human target |
|---|---|---|---|
| **P0** | `underage_risk`, `csam`, `child_safety`, `threat_to_life` | The reporter's match closes. The target is removed from new generation. **Interim hold only when corroborated** (below). A CSAM hash hit holds at once. | ≤ 4 h in staffed hours (08:00–22:00 GMT, every day); ≤ 24 h at most |
| **P1** | `sextortion`, `romance_scam`, `threats`, `entrapment` | Removed from new generation | ≤ 24 h |
| **P2** | `harassment`, `explicit_content`, `impersonation`, `hiding_relationship` | The reporter blocks the target (the toggle defaults on) | ≤ 48 h |
| **P3** | `spam`, `other` | — | ≤ 72 h |

- **Corroboration** for an interim hold (`moderation_hold`): two independent P0 reports about the same target (different reporters, different phone HMACs, each reporter's account ≥ 72 h old, neither reporter matching the other through the device signal), **or** one P0 report plus a tier-3 `age_signal` event in that match for `underage_risk`. Otherwise: priority review without a hold.
- **Credibility:** a report whose reporter's own messages to the target tripped `sexual_pressure` or `financial_request` in that match never triggers an automatic step and never counts for corroboration; the moderator sees "The reporter's messages in this chat triggered: {family}".
- **Reports about someone's gender identity never trigger action.** The automatic steps above apply to categories, not claims; `impersonation` gets no automatic step beyond the reporter's own block, and the runbook closes any report whose substance is the target's gender identity with no action.
- **Evidence:** every report snapshots the last 50 messages of both sides into `dating_report_evidence` (encrypted). Reports can be filed for 30 days after unmatch, block, close or the other side's deletion.
- **Reporter protection:** the target never learns who reported or what they wrote; the reporter sees no outcome beyond "We've looked into your report." (the target's restriction is the target's business).
- **Rate limit:** 10 reports a day (exists).

### 6.3 Enforcement

| Restriction | When | Effect on the person | Matches | Appeal |
|---|---|---|---|---|
| `moderation_hold` | corroborated P0, or a CSAM hit | hidden from introductions; cannot send Dating messages | stay open (counterparts see no change except silence) | not until decided |
| `age_review` | `underage_risk` hold, or an age-estimate gap (§3.3) | Dating closed; "Verify with ID" | **all closed** (`age_review`) | via the ID route |
| `suspended` (with `ends_at`) | moderator decision | no introductions or messages until the date | closed (`account_restricted`) | once |
| `suspended` (no `ends_at`) | moderator decision | Dating closed | closed | once |
| `under_review` | moderator marks a profile for a closer look | none visible; excluded from generation | unchanged | — |

- **Category shown:** every restriction stores `category`; the person sees its plain label (§3.7). Never the reporter, never the evidence.
- **Appeal:** one per restriction, decided by a different human than the original decider, or by the safety owner at least 24 h after the appeal when the owner made the first decision while working alone (enforced in `moderation_decide_appeal`). Target 7 days.
- **Account-level age review** (W4): when the estimate is far below 18 for a declared adult (the vendor's under-18 band with high confidence), or when a moderator confirms a minor on an `underage_risk` case, Dating calls Spec 1's `place_account_hold(user, 'age_review', <verification session or case id>)` (three arguments, I-7). Spec 1's access-token hook then refuses the account's tokens at the next refresh, so the whole app (invites, Opinions, chat) is closed, not only Dating. Cleared by an ID check through support (Spec 1's `support_corrected` path).
- **Deletion and carry-over** (W1a, in `prepare_account_deletion`, before the cascade; every HMAC below comes from `dating_phone_hmac_for_user`, which uses the pre-park HMAC for a parked account):
  1. For each live `dating_account_restrictions` row: write `enforcement_records {phone_hmac, scope 'dating', source_restriction_id, restriction_type, category, confirmed_report_count, effect_until = ends_at, purge_after = now() + 2 years}` (`ON CONFLICT (source_restriction_id) DO NOTHING`, so a record already written at parking isn't duplicated).
  2. Set `purge_after = now() + 2 years` on every `dating_block_hmacs` row involving the person's HMAC.
  3. Close the person's matches (`account_deleted`), set `evidence_until = now() + 30 days`, and keep their messages sealed (the FK on `sender_user_id` is `SET NULL`, `sender_side` keeps who said what).
  4. Reports by and about the person lose their user ids (`SET NULL`) and keep `target_phone_hmac`.
  5. The cascade then removes everything else (profile, sensitive row, photos via the media queue, prompts, settings, introductions, never-introduce list, devices, sessions).
- **Parked accounts (I-11, W1a + W1d).** Spec 1's fresh start parks a dormant account by rewriting `auth.users.phone` to a `+999…` number and setting `users.phone_released_at`; first, Spec 1 W6a's `consume_fresh_start` writes `users.parked_phone_hmac` with the existing `public.dating_phone_hmac(text)` over the canonical number (`'+' || digits` of the real `auth.users.phone`), the exact input `dating_phone_hmac_for_user` uses, so the two always agree (a contract test computes both for an unparked fixture). Then:
  - `dating_phone_hmac_for_user(uuid)` returns `parked_phone_hmac` whenever `phone_released_at` is set (W1a), and NULL when that column is NULL (the key was missing at parking); it never returns the HMAC of the `+999…` placeholder. Spec 1's identity health counts parked accounts without the column. The 180-day purge's `prepare_account_deletion` therefore writes enforcement records and sets `purge_after` on block pairs keyed to the **real** number, not the `+999` one.
  - The W1d trigger `dating_on_account_parked` (`AFTER UPDATE OF phone_released_at ON public.users`, no-op unless it goes from NULL to a value, never raises) pauses the parked account's enrolment (`pause_reason = 'account_parked'`), so it leaves everyone's Today at once. The account's own data and its restrictions stay with it (it can be recovered within Spec 1's 180 days) until the purge, which carries the restrictions over under the real number's HMAC (§6.3 step 1).
  - Whether **live** Dating restrictions should also follow the number to the fresh account while the old one is parked is an **owner decision** (Spec 1 §10 O3; §10 item 8 here). Built default, matching Spec 1: **no**, because the fresh account is assumed to be a new person; the restrictions reach the number only at the purge. If the owner rules yes, the same trigger also writes `enforcement_records` from each live restriction keyed to `parked_phone_hmac` (idempotent on `source_restriction_id`), so the fresh account gets a `carried_over` restriction with its category and one appeal; nothing else changes. The risk of the default: a restricted person could wait out dormancy and start fresh. Either way, blocks, never-introduce entries and former-partner exclusions keyed to the number apply to the fresh account (harmless: they only stop two people being introduced; Spec 1 §6 accepts the same for exclusions).
- **At a new account** with the same phone: `begin_dating_enrollment` finds the enforcement record and copies it into a new restriction with `source = 'carried_over'` and the same category, so the person sees the reason and can appeal (once). The no-repeat-pair history is **not** kept for deleted accounts (11 §3.3: it can reveal orientation).

### 6.4 Moderation console (W7)

A separate Flutter web entry point, `lib/console/main_console.dart`, built to `build/console`. It imports only `lib/console/**` and a web-safe Supabase client (no Mapbox, OneSignal or platform-channel plugins), and CI runs `flutter build web -t lib/console/main_console.dart` (F-6). It is hosted as a private static site behind an access gate (Cloudflare Access or equivalent) and signing in with the moderator's Attune phone account plus TOTP (`aal2`). Every call goes through the `dating-moderation` edge function.

| Screen | Shows | Actions |
|---|---|---|
| Queue | open cases by priority and time to SLA; cases that need sensitive routing only to people with `sensitive_routing_allowed` (decided at read time, never stored) | claim |
| Case | category, priority, report text, evidence snapshot, the target's profile as others see it (name, age, region, prompts, approved photos), prior cases on the same UUID or phone HMAC, safety-event families in the match (names only), the credibility note | dismiss · hold · lift hold · restrict (type, end date, category) · ask for ID · record an escalation · add a note |
| Photos | `needs_review` photos with the reason | approve · reject (reason) |
| Verifications | human-review gesture photos beside the approved photos; ID mismatches | identity pass · fail · ask for ID |
| Appeals | the restriction, the original decision, the appeal text | accept · reject |
| Signals | §5.10 signals | open a case · dismiss · lift throttle |
| Opinions queue | S1 W9b's review queue v0, embedded through its own RPC | as S1 W9b defines |
| Countries | `country_safety_config` rows and the publish form | publish (safety owner only) |
| Law-enforcement log | requests and decisions | record (safety owner only) |
| Audit | `dating_moderation_actions` | read |

The console never shows gender, who someone would like to meet, faith or marital history (it cannot read them), and never shows CSAM: a hash hit holds the account and goes to the safety owner's reporting path without displaying the image. **Sensitive routing (S-5):** nothing about routing is stored. Each time the queue or a case is read, the console's definer function calls `dating_case_needs_sensitive_routing(case_id)`, which decrypts the two identities of the case's match (or the target and reporter) inside the transaction and returns only true or false; a case that returns true is left out of the list, and refused on open with the ordinary `case_unavailable`, for any reviewer without `sensitive_routing_allowed` (initially only the owner). The reason is never shown, logged or written to `dating_moderation_actions`. So a Ghana-based moderator never handles a same-gender case, and no table holds a bit that says a pair is not man–woman.

### 6.5 Moderation runbook (W7 deliverable: `lib/architecture/DATING_MODERATION_RUNBOOK.md`)

- **Roles:** the owner is the safety owner; one contracted moderator who reads Twi, Ga and Pidgin; named out-of-hours P0 cover. Staffed hours 08:00–22:00 GMT daily. The pilot's size (people enabled) is set so the measured P0 load fits this capacity.
- **Triage per category:** what to look at (evidence, prior cases, credibility note), the decision options, and the category label to record. Each step is written for one person working alone.
- **Never:** ban on one report or one phrase; use nationality, network, name or region as a signal; act on a report about someone's gender identity; contact police automatically.
- **Escalation, always a human decision, recorded in `dating_escalations`:** imminent threat to life → police in the user's country (numbers from `support_resources`); CSAM → NCMEC CyberTipline, the IWF, or Ghana's Cyber Security Authority, through S1 W7b's runbook; sextortion → CSA 292 (Ghana) or Report Fraud / the Revenge Porn Helpline (UK), **only with the victim's consent**.
- **SLA breaches** raise content-free alerts every 15 minutes to the on-call channel.
- **Moderator wellbeing:** no exposure to CSAM; rotation off the queue after any P0 involving violence.
- **Review cadence:** weekly look at overturned decisions by country (the overturned-enforcement metric).

### 6.6 Law-enforcement policy and transparency (W7 draft, counsel-final at W10)

Published policy, points it states:
- Attune discloses user data only in response to valid legal process from a competent authority in the user's jurisdiction, reviewed by the safety owner and counsel, or in an emergency involving imminent risk to life (a human decision, recorded).
- Attune can disclose only what it keeps (§4.8). It never holds GPS, location history, selfie videos, ID images or face templates. Special-category answers are deleted when someone leaves Dating.
- Attune does not volunteer, and will contest where the law allows, any request whose purpose is to identify people by sexual orientation or gender identity.
- Users are told about a request unless the law forbids it or telling them would put someone in danger.
- Every request is logged in `law_enforcement_requests` and counted in a quarterly transparency summary: requests by country and type, how many were met in whole or part, reports by category, actions taken, appeals and how many were overturned.

### 6.7 Device discretion (W8)

- **Neutral pushes everywhere** (§3.13); `notification_config.dart` routes `me_update` to Me; the old "New mutual match" text is gone from every function.
- **Quick exit and sign-out wipe Dating caches, through Spec 1's device wipe registry (C-2, C-3):** W8a adds `registerDatingDeviceWipes()` in `lib/features/dating/data/dating_device_wipe.dart` (new) and one line calling it in Spec 1's `lib/app/device_wipes.dart`. It registers one entry: `DeviceWipeEntry(id: 'spec2.section_caches', order: 20, moments: {WipeMoment.quickExit, WipeMoment.signOut}, run: clearDatingDeviceData, bound: 1 s)` (an order after Spec 1's own entries; not `protective`). **This spec never edits `quick_exit_service.dart` or `auth_provider.dart`**; Spec 1 owns them and runs each entry in its own `try` with its bound. The entry invalidates every Dating provider through a static reset hook, clears the in-memory photo cache and the Flutter `ImageCache` entries tagged Dating, drops any pending Dating deep link, and clears the Dating route stack. It awaits no I/O, touches no `SharedPreferences` and needs no platform channel. It **never clears protective settings**: the Dating lock, the Safety PIN and the plain app icon all survive quick exit (the lock is cleared on sign-out only, by Spec 1). It does not cancel a scheduled check-in (safety).
- **`FLAG_SECURE`:** a route observer on the Dating route group calls `setSecure(true)` on the existing `attune/safety` channel (`MainActivity.kt`) when a Dating route is on top and `setSecure(false)` when none is. iOS cannot block screenshots; the existing `AppPrivacyCover` hides the app switcher, and Dating screens blur while the screen is being captured (recording or mirroring): `UIWindowScene.sceneCaptureState == .active` where available (iOS 17+), and the deprecated `UIScreen.isCaptured` only as the fallback on older systems (F-4).
- **No gallery saves:** Dating photos are rendered from bytes held in memory (no `cached_network_image`, no disk cache, no long-press menu, no share action).
- **Dating lock:** Spec 1's setting; this spec makes every Dating route, push tap and deep link honour it (§3.14).
- **Plain icon for everyone:** Settings → App icon → "Attune" / "Plain". Android: an `activity-alias` (`.IconPlain`, no "dating" in any component name) with a plain abstract icon (not another app's icon) and the label "Attune"; iOS: an alternate icon set through `setAlternateIconName` (iOS shows a system alert on change; the copy says so). Prompted at D13 when the effective tier is 1 or 2.
- **Traveller detection and auto-hide:** §2.5 and §3.11, behind `dating_traveller_detection`.

### 6.8 Privacy: DPIA points (W1 starts the DPIA; W10 needs it signed)

| Point | This spec's answer |
|---|---|
| Purposes | introductions between consenting adults; safety and enforcement; legal compliance |
| Categories | identity and contact (phone, first name, age); profile; **special category**: gender identity, who you'd like to meet (reveals orientation, CJEU C-184/20), faith, marital history; **derived special category (S-5)**: introduction, interest-action, match and couple-link rows between two people (who was introduced to or matched with whom can reveal orientation), and a moderation case's routing (computed at read time, never stored); **biometric** at verification (transient); messages; safety and moderation records |
| Lawful basis | explicit consent for special-category and biometric processing (GDPR / UK GDPR Art. 9(2)(a); Ghana Act 843 s.37 consent); contract for the service; legitimate interests and legal obligation for safety and enforcement records |
| Minimisation | §3.7 of the decision doc's not-collected list; no GPS, no ethnicity, no income, no health, no templates; side and region only; resolved introductions lose their actions, reasons and ranking detail after 30 days and are deleted when either person leaves; no stored routing bit; no repeat-pair history kept for deleted accounts |
| Storage | encryption at rest in the application layer (§4.2); RPC-only access; no client table reads; `service_role` cannot read the sensitive table, messages, introductions, interest actions, matches or link requests; the console cannot read special-category fields; the only service-role path to decrypted fields is `dating_export_for_job`, bound to an export the person asked for, capped at 3 calls per job and logged (S-4) |
| Retention | §4.8; survivors after deletion named in the privacy policy (enforcement records, block pairs, anonymised reports; 2 years) |
| Transfers | Supabase project region; AWS Rekognition in an EU/UK region; the estimation and ID vendors' processing regions and retention, recorded per contract |
| Risks | outing and entrapment (same-gender off in Tier 1/2; nothing stored there); compelled disclosure (minimal retention, LE policy); breach (encryption, canaries, bucket test, secret scanning, pen test); insider (no console access to sensitive fields, sensitive routing, audit log); re-identification in thin pools (no side shown, no counts, n ≥ 50); minors (assurance, holds, CSAM hashing); biometric misuse (no templates, vendor deletion terms); unfair exposure (fairness job) |
| Residual risks stated | a live `postgres`-level attacker can decrypt; VPNs hide travellers; a real person can pass liveness and act in bad faith; third parties can relay what they see |
| Rights | export of one's own Dating data (W9); deletion (exit, account deletion); correction (DOB through Spec 1; everything else in Dating settings); withdrawal of consent = exit |
| Registrations | Ghana DPC; UK representative if the controller is outside the UK; EU Art. 27 representative before any EU country opens |
| US (later) | BIPA written release and a public retention and destruction schedule before any US user verifies; CUBI consent (not written, 08 04-38) |

### 6.9 Metrics (aggregate only, through Spec 1's `metric_counters`, shown at n ≥ 50)

Keys (no user ids, no gender, preference, faith or age-signal values; country and region codes are lowercased to fit Spec 1's key pattern `^[a-z0-9_:>.-]{1,80}$`). **Every Dating key is bumped server-side** where the event happens: Dating definer functions (a setup writer, `activate_dating_profile`, generation, `report_dating_match`, and so on) call `private.bump_metric_internal`, and Dating edge functions call `bump_metric_server`. The client sends no Dating metric, so Dating adds no `metric_client_keys` row, and dynamic parts (`{country}`, `{region}`, `{category}`) come only from server values checked against their lists (S-2):
- Funnel: `dating.setup.started` (the first D2 write), `dating.setup.step.{d2…d13}` (each step's writer), `dating.activated`, `dating.first_intro_hours.{bucket}`.
- Verification: `dating.verify.first_try_pass`, `dating.verify.route.{fae|id|human}`, `dating.verify.id_route.age_{18_24|25_34|35_plus}` (declared age band), `dating.verify.hours_to_decision.{bucket}`.
- Pool: `dating.empty_day.{country}.{region}`, `dating.not_open.{country}`, `dating.intros_delivered.{country}`.
- Outcomes: `dating.mutual`, `dating.we_met`, `dating.close_kindly`, `dating.unmatch`, `dating.couple_link`.
- Safety: `dating.report.{category}`, `dating.block`, `dating.mask_hit`, `dating.card.{family}`, `dating.signal.{kind}`, `dating.hold.p0`, `dating.appeal.{accepted|rejected}`, `dating.overturned.{country}`.
- Gentle wait: `dating.gentle_wait.seen`, `dating.gentle_wait.account_deleted_7d` (the evasion proxy).
- Harm: `dating.pause`, `dating.exit`. (Quick exit sends nothing to the server, so Dating doesn't count it; any quick-exit count is Spec 1's.)
- Anti-metrics (watched, never optimised): sessions a day, time in Dating, introductions viewed.

---

## 7. Testing

### 7.1 SQL contract tests (local `attune_spec3a`)

Run each file locally with `psql -X -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/<file>.sql`, after applying the wave's migrations and grants twins the same way. **Never run `scripts/local_pg_setup.sh` or `scripts/local_pg_grants.sql` against `attune_spec3a`** (A-1; the setup script drops the database). CI runs the same files in the SQL contract job on its own fresh database. Record the suite's pass/fail baseline before W1a; no batch may add a failure. Rules for every file (from the repo's verification lessons): each file is one transaction ending in `ROLLBACK`; every negative assertion checks the **specific** SQLSTATE and message, never `WHEN OTHERS`; consent events written in one block use `clock_timestamp()`; fixtures use unique phones and UUIDs swept against the whole suite; deny tests use a replacement member, never a nulled one; every guard has a mutant that makes its test fail (§7.5).

| File | Wave | Proves |
|---|---|---|
| `dating_rls_canary.sql` | W1a (extended every batch) | every Dating relation and function has exactly its allow-listed grants; `dating_profile_sensitive`, `dating_messages`, `dating_introductions`, `dating_interest_actions`, `dating_matches` and `dating_couple_link_requests` are unreadable by `anon`, `authenticated` and `service_role` (S-5); the only function `service_role` can execute that calls `dating_field_decrypt` is `dating_export_for_job` (a `pg_proc` scan, S-4); no table has a column named like `%routing%` except `dating_moderators.sensitive_routing_allowed` |
| `storage_bucket_policies.sql` | W1a, W4a | both Dating buckets private; policy list exact; no Dating trigger on `storage.objects`, and `dating-profile-photos` absent from Spec 1's scan-trigger bucket list (I-10) |
| `dating_v2_identity_contracts.sql` | W1a, W1c, W1d | HMACs come from `auth.users`; **parked accounts (I-11):** `parked_phone_hmac` equals `dating_phone_hmac_for_user` computed before parking; after parking, `dating_phone_hmac_for_user` returns the pre-park value (NULL, never the `+999` HMAC, when `parked_phone_hmac` is NULL), the account is paused with `account_parked` and leaves generation, and no `enforcement_records` row is written at parking (built default, O3); the 180-day purge writes the record under the real number once (`source_restriction_id`) and sets `purge_after` on the real-number block pairs, and a fresh account on the same number then gets the `carried_over` restriction; changing `public.users.phone` changes nothing; **delete → re-register (same SIM) → tamper `public.users.phone` → still excluded, blocked and restricted**; reports survive either side's deletion with `target_phone_hmac`; block pairs survive; never-introduce is symmetric and silent; generation returns `skipped: missing_key` without either key; ciphertext contains no plaintext marker (`position('woman' in encode(identity_enc, 'escape')) = 0`); writers return `unavailable` without the field key; exit leaves zero rows in profile, sensitive, prompts, settings, photos, preferences and reflections, keeps messages sealed with `evidence_until`, and deletes the never-introduce list unless `p_keep_never_introduce` is true (default false, R-2); activation succeeds with explicit "Everyone"; no Dating function body mentions `users.mode`; the relationship guard covers `paused` |
| `country_safety_config_contracts.sql` | W1b, W1d | one current row per country; every seeded row has `dating_enabled = false`; **environment (R-6):** with `app.settings.attune_environment` unset, `private.attune_environment()` returns `'development'` and the checks are reported, not enforced; with `set_config('app.settings.attune_environment', 'production', true)` production mode refuses `dating_enabled` without evidence refs and Tier 1/2 `same_gender_enabled` without the reconsideration refs, and running the dev script raises `env:not_development` before it changes anything; no file under `supabase/migrations`, `supabase/sql`, `scripts` or `supabase/functions` writes `attune_environment` (a CI grep step); **public config (I-3):** anon `get_public_app_config()` returns `config.dating_open_countries` (through the re-created seam) equal to the enabled countries, drops a country in the same transaction as a publish that closes it, every other key of `get_public_app_config()` is unchanged, and the `app_public_config` row is gone; turning same-gender off before W1d returns `config:kill_switch_pending` and changes nothing; the kill switch invalidates same-gender introductions and deletes disallowed values in one transaction; effective tier = the highest of the sources |
| `dating_v2_eligibility_contracts.sql` | W1b, W2 | the W1b base returns the gate 1–4 and 6 reasons; eligible with a Healing readiness score of 10 and no journey (the Healing gate is gone); `gentle_wait` while an Attune relationship is `ended` and inside the window; open once `ended_at + 30 days` has passed even if the sweep hasn't archived it yet (A-9); open the moment it is `archived` by both seals; **shim (I-4):** `get_dating_eligibility()` returns the old shape with `feature_unavailable` when the flag is off and `relationship_active` with a pending relationship; **one writer per pause reason (I-5, Spec 1 D18):** Dating → Just for me pauses exactly once, by the path trigger, with `path_change`; Dating → Relationship pauses exactly once, by Spec 1's `set_user_path_internal`, with `relationship`, and the trigger does nothing; an already-paused enrolment keeps its first reason; no other function body calls `pause_dating_for_relationship_user` or writes `pause_reason = 'path_change'` (a `pg_proc` scan); **A-10:** the re-created `private.dating_home_summary` keeps exactly the keys `enabled` and `enrolled`; `enabled` is false with `dating_mode_enabled` off; after W3a's revoke, `get_my_home_state().dating.enrolled` still reads true for an enrolled person and false after exit; no wait for someone whose only relationship ended outside Attune or long ago; the 72 h cool-off from `users.created_at`; leaving the Dating path pauses Dating; `dating_healing_gates_hold` does not exist |
| `dating_v2_setup_contracts.sql` | W3b, W3c | in an off country, a same-gender identity or seeking set returns `not_available`, raises nothing and changes no row; intention enum enforced; attestation required; ages 18–99 and the 18–20 default; must-share stored; prompts reject contact details; 2–6 photos; notify requests aggregate only |
| `dating_v2_verification_contracts.sql` | W4a, W4b | a typed DOB alone never makes `dating_age_gate_holds` true; only `service_role` can record assurance; an estimate below the challenge age can never set `age_result = 'pass'` with `age_method = 'fae'`; `underage_risk` hold → `age_review` → every match closed; revocation closes matches (`age_verification_invalid`); without the trusted-device header every Dating RPC returns `reverify_device` and no data; a far-below-18 estimate calls `place_account_hold(user, 'age_review', <session id>)` exactly once, with all three arguments |
| `dating_v2_matching_contracts.sql` | W5a–W5c, W8b | `admits(a,b) = admits(b,a)` over a fixture grid; each of the 15 hard filters has a passing and a failing fixture; the intention matrix is symmetric; caps 3 / 6 / 3 open chats; the 7-day lifetime per side; a second run of the same cohort creates 0; same seed → same introductions in the same order; a thin pool yields 0 (never a relaxed filter); cross-border needs mutual opt-in, both verified, both 14+ days; same-gender needs both countries and fresh contexts; reasons only from fields both may show; no payload contains seeking, pools or hidden fields; viewer-scoped state kept (no "they liked you" oracle); the four-account non-enumeration proof (Fable C1) on every new read RPC |
| `dating_v2_chat_contracts.sql` | W6a–W6c | dating messages never enter `public.messages`, `relationship_message_counters` or the couples safety outbox; a blocked or unmatched pair cannot send through a stale client; masking holds until both swap; one-sided swap unmasks nothing; swap refused before 72 h; close-kindly closes for both; purge deletes 30 days after close unless a case holds the match; safety events visible only to the at-risk user; no message text in `scheduled_notifications` or `dating_safety_events` |
| `dating_v2_moderation_contracts.sql` | W7a, W7b | one P0 report → no hold; two independent → hold; a reporter whose own messages tripped a family doesn't count; a CSAM hit holds at once; the target sees the category but never the reporter; the appeal decider must differ (solo-owner 24 h rule); a restricted person cannot activate; re-registration carries the restriction with `source = 'carried_over'`; `impersonation` triggers no automatic step beyond the reporter's block; no signal function reads country, network, phone prefix, name or region; **routing (S-5):** a case whose match is not man–woman is absent from the queue of a moderator without `sensitive_routing_allowed` and opening it returns `case_unavailable`, a man–woman case is visible to both, and `dating_moderation_actions.detail` never holds a routing value |
| `dating_v2_link_contracts.sql` | W9 | no `relationships` row before both confirm; the second confirmation creates an active relationship, pauses both, closes every other open match with the neutral reason, sets both paths; first messages copied only when both chose it, masked unless both swapped (A-3); `get_dating_link_origin` returns `link_origin_unavailable` to a non-member and for a relationship with no Dating origin, identically (S-6); **export binding (S-4):** `dating_export_for_job` with a `building` job for A returns only A's data and A's own sent messages (none of B's, though A and B matched), refuses a `queued`, `ready`, `failed` or unknown job with `export:not_building`, refuses a fourth call for one job, is not executable by `anon` or `authenticated`, and no function named `dating_export_for_user` exists; `export_relationship` includes the how-we-met card |
| `dating_exclusion_wiring_test.sql`, `data_export_contracts.sql`, `dating_mode_contracts.sql` | W1, W9 | updated as §4.10 says |

### 7.2 Adversarial cases from `10-scenarios-risk.md`, as tests

| Scenario | Test (file or suite) | Asserts |
|---|---|---|
| S1 scam crew, AI photos | `dating_v2_verification` + `dating-verification` Deno | stolen photos fail CompareFaces → `needs_review`; liveness required before any introduction; a deleted-and-re-registered restricted account is carried over; `financial_request` fixtures fire (incl. "m0m0", ɛ/ɔ spellings, zero-width splits); duplicate opener → signal |
| S2 16-year-old, false DOB | `dating_v2_verification` | DOB alone never passes; estimate < 25 forces ID; `underage_risk` + `age_signal` corroborates a hold; the hold closes matches; a far-below-18 estimate places Spec 1's `age_review` account hold |
| S3 gay man in Ghana; entrapment gang | `dating_v2_setup`, `dating_v2_matching`, `country_safety_config` | no same-gender row can exist for a GH Dating country; GH users are never same-gender candidates; the kill switch purges; the "Why?" sheet makes no call (widget test with a mock client asserting zero requests) |
| S4 traveller | `dating-device-check` Deno + `dating_v2_matching` | UK user with IP Ghana → `same_gender_allowed_here` false → no same-gender introductions, hidden in reads; IP UAE → `dating_allowed_here` false; Ghana SIM in London never turns same-gender on; the note is in-app (no push row) |
| S5 controlling partner | `dating_v2_identity`, `dating_v2_verification` | never-introduce excludes before the next run and returns the same "Added." for any number; a new device without re-verification sees nothing; no "account exists" signal from any RPC |
| S6 ex in introductions | `dating_v2_identity` | the delete → re-register → tamper test; generation refuses without the key |
| S7 recycled number | `dating_v2_verification` | a new device id gets `reverify_device`; Dating data stays hidden until liveness + CompareFaces pass |
| S8 sextortion after swap | `dating_v2_chat`, `dating_v2_moderation` | report from the "Ended" list after unmatch and after the other's deletion; evidence snapshot exists; `sextortion` is P1 and removes from generation; card copy pulls the country resource |
| S9 MoMo / airtime ask | Deno lexicon fixtures | English, Pidgin, Twi spellings fire; "sent by mistake, send it back" fires; split-fare negatives ("let's split the trotro fare") produce at most an education card and never a case |
| S10 Interested to everyone | `dating_v2_matching` | the dragnet rule throttles to 1 a day and opens a case; HMAC blocks survive re-registration |
| S11 malicious report | `dating_v2_moderation` | one report never holds; a retaliatory `underage_risk` from a reporter whose messages tripped `sexual_pressure` doesn't count; the category is shown; the appeal goes to someone else |
| S12, S13 (Opinions, journal) | — | Spec 1 W9 (W9a–W9c) owns them |
| S14 breakup, both date | `dating_v2_eligibility`, `dating_v2_identity` | gentle wait during the window; exclusion both ways; new accounts can't hide photos before day 30 |
| S15 every trace gone | `dating_v2_identity` | exit row counts; quick-exit widget test shows empty Dating caches while the Dating lock, Safety PIN and icon choice are unchanged; export contains own data |
| S16 minor invited to a couple | Spec 1 W4a (`accept_relationship_invite_v2` age checks) and W6a (hold hook); `dating_v2_verification` | a Dating-placed `age_review` hold ends the account's sessions at the next token refresh (Spec 1's hook test) |
| S17 family phone | widget | D13 shared-phone question sets the lock; lock-screen copy is neutral |
| S18 secretly partnered | `dating_v2_setup`, `dating_v2_moderation` | attestation required and re-asked on change; `hiding_relationship` is P2; no partner-facing signal exists anywhere (grep test: no Dating function writes to any Relationship-path table except W9's link) |
| S19 phone searched | widget + device | no Dating data on disk after use: a test lists every `SharedPreferences` key and value, every secure-storage key and every file name under the app's documents, support and cache directories, and fails if any contains "dating" in any case, or if any key exists that isn't on the list of keys a person who never used Dating also has (Spec 1 §5.5's allow-list: `attune.home.<scope>.state`, `attune.flow.<uid>.country_override`, `me_section_lock` and Spec 1's other keys; plus this spec's `attune.install_id`, created at first launch for everyone) (C-5); `FLAG_SECURE` set on Dating routes |
| S20 state demand / breach | `dating_rls_canary`, `storage_bucket_policies`, CI secret scan | the canaries; `service_role` cannot read the sensitive table |
| S21 first meeting at a home | Deno fixtures + widget | `meet_private_pressure` fires; Share my plan text contains no name or photo; Get help sends nothing automatically |
| S22 single parent targeted | `dating_v2_setup`, Deno | no "seek parents" option exists in RPC or UI; `child_access` fires; child-label photos rejected |

### 7.3 Edge function tests (Deno, `supabase/functions/**/index.test.ts`)

- `dating_chat_safety.ts`: it imports Spec 1 W9a's `_shared/unicode_normaliser.ts` (no second fold table; a test asserts the module has none, I-17); golden positive and near-miss negative fixtures per family in English, Ghanaian and Nigerian Pidgin and Twi (typed with ɛ/ɔ and with e/o), each matched in the form its family states; zero-width splits caught through the squashed match form; `I'm 16` fires `age_signal` in the base form and isn't folded to letters.
- `dating_mask_contacts` parity: the SQL function and a TS mirror run the same fixture file (`supabase/tests/fixtures/dating_mask_cases.json`): phones in GH/UK/NG formats, NUBAN, numbers in words, emails with "at"/"dot", bare domains, handles, crypto addresses; negatives: dates, times, prices ("GH₵200"), years.
- `dating-verification`: a decision table over the fake providers (liveness pass/fail × estimate ≥ / < 25 × photos match/mismatch × ID pass/fail/DOB mismatch); images never logged (a console spy); `fake` mode refused when `get_attune_environment()` returns `'production'`, and allowed when the setting is unset (development).
- `dating-device-check`: tier computation; the IP never appears in logs or responses.
- `dating-photo-urls`: a viewer gets URLs only for an introduction or match they are in, only when photos are not withheld, and only for approved photos; 60 s expiry.
- `process-dating-photo`: CSAM check runs first and exactly once per photo; a hit copies to `safety-quarantine`, calls Spec 1's inline-match service function once (one hold, one escalation), stops Vision and adds the Dating hold; a matcher error leaves the photo unapproved; child labels reject or route to review.
- `build-data-exports`: the `dating` part comes only from `dating_export_for_job` with the job being built; the other parts' contents are unchanged.
- `dating-moderation`: refuses without a moderator row or without `aal2`; every action writes an audit row.

### 7.4 Widget and unit tests (Flutter)

- Every screen in §3 for each state it can show, with `Semantics` labels, `labeledTapTargetGuideline`, `androidTapTargetGuideline` and `textContrastGuideline`; goldens at text scale 1.0, 1.3 and 2.0; reduce-motion goldens.
- The undo window lasts ≥ 20 s with `MediaQuery.accessibleNavigation` true and 5 s otherwise; the action is sent once.
- No countdown: no Dating widget renders `expires_at`.
- No burst: the match moment has one animation ≤ 600 ms and none under reduce motion.
- **Architecture test:** no file under `lib/features/dating/**` imports from `lib/features/chat/**` or `lib/features/games/**`; `ChatScreen` is not referenced; only `dating_supabase_client.dart` sets the `x-attune-device` header (S-7); Dating's wipe is reached only through Spec 1's device wipe registry (no Dating symbol appears in `quick_exit_service.dart` or `auth_provider.dart`, C-2/C-3).
- No Dating provider or repository writes to `SharedPreferences`, files or the image disk cache (fake platform channels record every write).
- Quick exit and sign-out, through the registry, clear every Dating cache (provider containers empty, photo cache empty, `ImageCache` Dating keys gone); after quick exit the Dating lock is still on, the Safety PIN still set and the icon choice unchanged (C-2); a throwing or slow Dating entry doesn't stall the exit (the registry's bound).
- `FLAG_SECURE` is set when a Dating route is pushed and cleared when the last one pops (mock channel).
- Push routing: `me_update` opens Me (`/home?tab=me`); `me_checkin` opens `/dating/checkin`; with the Dating lock on, the PIN screen comes first for `me_checkin` and Me shows the locked Dating row for `me_update` (I-9).
- Relationship home: the `link_offer` card appears in `ConversationsScreen`'s card list only while an offer exists and disappears after either action; the chat card and the Journals and Together cards render and reorder as before (C-4).
- The off-country D5/D6 screens never call `save_dating_identity` with a same-gender set (the mock client fails the test if they try).
- Repository keeps one idempotency key per action until disposal (double tap → one server action).

### 7.5 Mutation checks

Each mutant is applied inside a rolled-back transaction by the repo's non-destructive `mutant.sh` (prepends the mutation to the test file and pipes it to `psql` on `attune_spec3a`; it never rebuilds the database) and must make the named test fail:

| # | Mutant | Must fail |
|---|---|---|
| 1 | `dating_phone_hmac_for_user` reads `public.users.phone` | identity: tamper case |
| 2 | drop the `(b, a)` direction from any hard filter | matching: symmetry grid |
| 3 | remove the same-gender check (filter 4) | matching + setup |
| 4 | `save_dating_identity` stores before checking the country | setup: off-country row unchanged |
| 5 | generation runs without `dating_exclusion_key` | identity: missing key |
| 6 | remove `ON COMMIT DROP` from the temp table | matching: no temp table survives the run |
| 7 | raise instead of returning `not_available` | setup: no exception |
| 8 | allow `fae` pass with estimate < 25 | verification |
| 9 | skip `dating_require_trusted_device` in one read RPC | verification: device guard |
| 10 | unmask when one side swaps | chat |
| 11 | allow swap before 72 h | chat |
| 12 | send RPC skips the block check | chat: stale client |
| 13 | hold on one uncorroborated P0 | moderation |
| 14 | count a tripped reporter for corroboration | moderation |
| 15 | allow the same decider on an appeal | moderation |
| 16 | `prepare_account_deletion` skips the enforcement record | identity: carry-over |
| 17 | exit keeps `dating_profile_sensitive` | identity: exit row counts |
| 18 | return `seeking` in `get_my_dating_introductions` | matching: payload |
| 19 | cite `same_faith` when one side hides faith | matching: reasons |
| 20 | `daily_new_max` CHECK removed and set to 5 | matching: config CHECK |
| 21 | link creates the relationship on the first confirmation | link |
| 22 | export includes the counterpart's messages | link: export |
| 23 | `dating_export_for_job` accepts a job that isn't `building` (or takes the user id as an argument) | link: export binding (S-4) |
| 24 | the path trigger also pauses on a change to Relationship, or uses `relationship` for Dating → Just for me | eligibility: one writer per pause reason (I-5) |
| 25 | the dev script's `private.assert_development_project()` line removed | country config: dev-script refusal in production mode (R-6) |
| 26 | the queue shows a not-man–woman case to a reviewer without `sensitive_routing_allowed` | moderation: routing (S-5) |
| 27 | `dating_phone_hmac_for_user` ignores `parked_phone_hmac` (or falls back to the `+999` number) | identity: parked account (I-11) |
| 28 | `get_dating_link_origin` skips the membership check | link: origin (S-6) |
| 29 | the gentle-wait gate tests `status = 'ended'` only | eligibility: window predicate (A-9) |
| 30 | `exit_dating_mode` keeps the never-introduce list by default | identity: exit (R-2) |

### 7.6 Algorithm Quality Review Checklist v3.1 evidence map (generation, verification, chat worker, masking)

| Item | Evidence |
|---|---|
| 1.4 / 1.5 authorisation and authentication at every access | RLS canary; four-account proof; device guard tests |
| 1.1 / 2.18 idempotency | `claim_dating_idempotency` on every mutation; second-run-creates-0 test |
| 1.6 / 6.3 concurrency | two concurrent `act_on_dating_introduction` calls create one match (concurrency script checks each session's exit code); two generation ticks claim one run |
| 1.10 compensating steps | the couple link is one transaction; generation dead-letters a partition without partial publish |
| 1.11 data privacy | §6.8 DPIA table; encryption tests |
| 2.1 input validation | every writer's CHECKs and RPC validation; Deno fixtures |
| 2.4 / 5.5 opaque errors | uniform `*_unavailable` results; four-account proof includes timing-path order |
| 2.5 / 2.15 resource limits | `partition_people_max`, `scan_limit`, message 1,000 chars, 50 never-introduce entries, rate limits |
| 2.7 / 2.8 / 7.3 secrets | Vault keys; gitleaks job |
| 3.10 retries | outbox max 5 attempts → dead letter; generation 3 → dead letter |
| 4.4 sensitive data out of logs | logging-settings health check; IP and image console spies |
| 6.1 / 6.4 edge and negative cases | §7.1 files and §7.5 mutants |
| 7.4 least privilege | `service_role` revoked from sensitive tables; console via edge function with `aal2` |
| 8.1 rollback | each wave's flags off returns the previous behaviour; the W10 runbook drill rehearses turning Dating off per country |

### 7.7 Device checklist (W10, before production switch-on; parts run at the end of each wave)

- Device checks run on **release** builds (F-4: debug on iOS 26 devices needs a newer Flutter than 3.29; the Declared Age Range parts are Spec 1's).
- TalkBack (Android) and VoiceOver (iOS) through D1–D13, a full introduction, a chat, a report and an appeal.
- 200% text on every Dating screen; RTL smoke test.
- Android Go / 2 GB RAM (Tecno or Itel), a mid Samsung, a Pixel, an iPhone SE and a current iPhone.
- Liveness in daylight, glare, low light, with glasses; the app killed mid-capture and resumed; the human route end to end; the ID route with Smile ID's Ghana Card sandbox.
- Offline and EDGE: every step's offline state; no Dating file or prefs key on disk after use.
- Data use measured for setup, a day of introductions with and without photos (the D1 and D9 figures corrected if off by more than 25%).
- Lock screen on Android and iOS: only "Attune" / "You have something new in Attune."; tapping with the Dating lock on asks for the PIN.
- Quick exit from Today, a chat and the meeting kit: caches gone on return; the Dating lock, the Safety PIN and the plain icon unchanged.
- Android screenshots and screen recording blocked on Dating screens; iOS app switcher covered and Dating blurred while recording (`sceneCaptureState` on iOS 17+, `isCaptured` on older).
- Plain icon on Android (alias) and iOS (alternate icon, system alert).
- Traveller: a VPN set to Ghana and to the UAE on a UK account; the in-app note, no push.
- New device and restored-backup device: re-verification required.
- Real carriers: MTN, Telecel and AirtelTigo (Ghana), a UK carrier; the digest at the chosen drop time; the check-in push not folded by quiet hours.

---

## 8. The waves (10, built as 23 batches, plus voice later)

Build order (11 §11): Spec 3 W1–W2 → Spec 1 → **Spec 2 W1–W10** → Spec 3 W3 → Spec 2 W11. Within this spec, batches run in the order below (letter order inside a wave); each batch is about 3–4 tasks (W-2, W-3). A citation of a wave number alone ("W3") means all of its batches, so earlier citations stay valid. Migration timestamps are given when a batch is built (§4.9).

Each batch ends with its tests green on `attune_spec3a` (migrations, grants twins and tests applied with `psql -f`; never `local_pg_setup.sh`) and in CI, `supabase/sql/dev_enable_spec2_dating_flags.sql` extended so every Dating flag that exists is ON in development, and the batch's device checks done. **No batch turns anything on in production.** The gate line under each wave is what must be true before that wave's behaviour may be switched on in production mode; the human gates start on day one, in parallel (Q19).

### W1 — Dating data, identity, deletion, configuration, encryption

**Gate before production switch-on (all of W1):** counsel signs the 2-year retention of enforcement records and block pairs, the consent-event minimum kept after exit, the Q17 exceptions (§1.3) and the privacy-policy line naming what survives deletion. `dating_field_key` provisioned in Vault. The logging-settings health field is green on the production project.

#### W1a — Identity, enforcement survival, deletion carry-over, canaries
- **Contents:** W1a migrations 1–3 (§4.9): HMACs from `auth.users` (pre-park HMAC for parked accounts) and recomputed exclusions; the relationship guard rewired; `enforcement_records`, `dating_block_hmacs`, reports and matches surviving deletion; `service_role` revoked on introductions, interest actions and matches; `prepare_account_deletion` Dating steps; the server metric prefix `dating.`; CI canaries (RLS, bucket, gitleaks); the dev script created (`private.assert_development_project()` first); the DPIA started.
- **Depends on:** S1 W1a (column grants, `phone` from `auth.users`, `users.path`, `users.phone_released_at`, `users.mode` writers removed); S1 W1b (`account_age`, `metric_counters` and `metric_key_prefixes`, `account_holds`); S1 W6a (`users.parked_phone_hmac`, written by `consume_fresh_start`).
- **Tests:** `dating_rls_canary`, `storage_bucket_policies`, `dating_v2_identity_contracts` (HMAC, tamper, carry-over and parked-HMAC rows), updated `dating_exclusion_wiring_test`; mutants 1, 16, 27.

#### W1b — Country configuration, availability, public config
- **Contents:** W1b migrations 1–2: `country_safety_config` with seeds (all closed), `publish_country_config` (same-gender-off path and notify queueing pending), session context and `dating_effective_context`, `get_dating_availability`, the `dating_notify_requests` table; Spec 1's seam `private.dating_open_countries()` re-created over the table and the interim row deleted (I-3; `get_public_app_config()`, the Welcome preview, the A6 card and the Me slot are unchanged); `dating_eligibility` with gates 1–4 and 6 (I-14); Spec 1's seam `private.dating_home_summary` re-created over it (A-10); the dev script publishes GH and GB open.
- **Depends on:** W1a; S1 W1b (`account_holds` for gate 3, `private.dating_home_summary`); S1 W1c (`app_public_config`, `private.dating_open_countries`, `get_public_app_config`, the environment helpers); S1 W2b (EULA v2, read by gate 2).
- **Tests:** `country_safety_config_contracts` (seeds, environment default, production-mode refusals, dev-script refusal, public-config parity); `dating_v2_eligibility_contracts` base rows; mutant 25.

#### W1c — Encryption, profile fields, setup writers
- **Contents:** W1c migration 1: the field-key functions and `dating_profile_sensitive`; new profile and preference columns; prompts; settings; the per-step writers (each calls `dating_eligibility(…, 'setup')`); own-profile reader and preview.
- **Depends on:** W1b.
- **Tests:** `dating_v2_identity_contracts` encryption rows (no plaintext marker, `unavailable` without the key, `service_role` can't read the table).

#### W1d — Lifecycle v2, never-introduce data, kill switch
- **Contents:** W1d migrations 1–2: `dating_never_introduce` (data and RPCs; UI in W5c); `dating_profile_ready` v2 and activation that works with explicit "Everyone"; pause / resume / exit v2 (hard delete; never-introduce kept only if ticked); `delete_dating_profile` dropped; `pause_reason`; consent purposes; the parked-account trigger; `apply_same_gender_switch` and `publish_country_config` re-created with it; the key guard on today's generation; health v2.
- **Depends on:** W1c.
- **Tests:** `dating_v2_identity_contracts` (exit, activation, never-introduce, parked pause), `country_safety_config_contracts` (kill switch); mutants 5, 17, 30.

### W2 — Eligibility and the gentle wait

- **Contents:** W2 migration 1: `dating_eligibility` with the gentle wait (window predicate); the Healing gate removed from its five SQL call sites and dropped; `get_dating_eligibility()` kept as a compatible shim until W3a (I-4); Healing's status and message no longer mention Dating; `get_dating_home` (first version); the `users.path` trigger that pauses a change from Dating to anything but Relationship with `path_change`, while Spec 1's `set_user_path_internal` keeps the one → Relationship pause with `relationship` (one writer per reason, Spec 1 D18, I-5); client changes in Healing (`ReadinessScoringService`, `HealingJourney`, `healing_journey_screen.dart`, `healing_repository.dart`) and docs (`healing_docs.dart`, `about_attune_docs.dart:74`); D0 screen and its reflection; the `DATING_MODE_SPEC.md` §2, §2.1, §3.1, §3.2 amendments with the clinical note recorded in `DATING_MODE_CLINICAL_REVIEW_PACKET.md`.
- **Depends on:** W1d; S1 W1a (`users.path`); S1 W1b (`set_user_path_internal` with its one → Relationship pause, `account_age`).
- **Tests:** `dating_v2_eligibility_contracts`; `readiness_scoring_service_test.dart` updated; D0 widget and golden tests; mutants 24, 29.
- **Gate before production switch-on:** the clinician's recorded note on the gentle wait's length (the 30-day window, shorter on both seals) and its copy, under the spec §2.1 gate-erosion clause; DV reviewer read of the D0 copy.

### W3 — Dating setup UI

**Gate before production switch-on (all of W3):** the Ghanaian cultural reviewer (with faith advisers) signs the intention wording, the married / polygamy attestation, the region, side and faith lists; the LGBTQ+ safety reviewer (West African context) signs the off-country copy, the "Why?" sheet and the country note; the Ghanaian legal opinion on the reconsidered bill confirms Ghana's switch state (Dating on, same-gender off).

#### W3a — Section, routes, repository, neutral push type
- **Contents:** W3a migration 1: notify-request RPCs, the neutral push type `me_update`, client `SELECT` grants and owner-read policies revoked, the `get_dating_eligibility()` shim dropped; the RPC-only repository on the Dating-scoped Supabase client, and per-state providers; `DatingSection` rendered by Spec 1's `dating_slot.dart` (§3.1); the Dating route group (§3.14) with the lock redirect; §3.10 not-open screens and "Tell me when it's here"; `notification_config.dart` case `me_update` → Me (I-9); `dating_feature_flags.dart` on `get_dating_home`; old routes and screens removed.
- **Depends on:** W2; S1 W3b (Me shell, Dating slot, Dating lock setting); S1 W1b (`set_my_path`); S1 W2a (`AllowLargeText`, motion tokens).
- **Tests:** section-state widget tests and goldens; the lock redirect; push routing for `me_update`; the `lib/` grep tests (`.from('dating_` and `get_dating_eligibility` find nothing, R11); the architecture import test; the no-disk-writes test.

#### W3b — Setup D1–D8
- **Contents:** W3b migration 1 (faith and denomination lists); D1–D8 with per-country region and side lists, region-aware faith lists, off-country D5/D6 with the "Why?" sheet and resources, and the country note; "Not ready? Use Attune just for me"; the "Set up later" card.
- **Depends on:** W3a; S1 W7a (`support_resources`).
- **Tests:** `dating_v2_setup_contracts` (off-country `not_available`, intention, attestation, ages, must-share); widget tests and goldens for D1–D8; the off-country no-call test; mutants 4, 7.

#### W3c — Photos, prompts, preview, ready, settings, docs
- **Contents:** W3c migration 1; D9 with 2–6 photos, the CSAM-first inline pipeline (the only scan for this bucket, I-10), child labels and slot-named rejections; `process-dating-photo` and `_shared/google_vision.ts` changes; `upload-dating-photo` removed; D10 with the contact and kindness filters; D11's screen shell (its flow is W4a); D12; D13 with the shared-phone question (the plain-icon offer stays hidden until W8b, A-11); Dating settings (§3.12) except never-introduce and other countries; `dating_mode_docs.dart` rewritten and the registry flags declared.
- **Depends on:** W3b; S1 W7b (the CSAM matcher, `_shared/csam_match_path.ts` and `record_inline_csam_match`; the F-1 spike outcome doesn't affect this batch); S1 W9a (the pre-post filter used for prompts).
- **Tests:** setup-contract photo and prompt rows; `process-dating-photo` Deno tests; widget tests and goldens for D9–D13 and settings.

### W4 — Verification and age assurance

**Gate before production switch-on (all of W4):** signed contracts with the estimation vendor (one UK regulators recognise as highly effective, with skin-tone and West African error data) and with Smile ID or equivalent (Ghana Card); the DPIA's biometric section; the AWS region recorded; for the UK, the method documented in the OSA children's-access assessment as highly effective age assurance.

#### W4a — Verification seam and D11
- **Contents:** W4a migration 1; the `dating-verification` edge function with the vendor seam (fake, sandbox, live; `fake` refused in production mode) and the liveness, estimation, ID and face-match providers; D11 (§3.3) with spoken prompts and haptics, resumable sessions, the ID route and the human gesture route (until W7b's console, reviewers use the service function from a development script); the far-below-18 path into Spec 1's `place_account_hold` with three arguments; `underage_risk` and `age_verification_invalid` closing matches; `verify-dating-profile` removed; flag `dating_age_assurance`.
- **Depends on:** W3c; S1 W1b (`place_account_hold`); S1 W6a (the hook that enforces the hold; the dormancy rule runs before re-verification so the two screens never stack); S1 W6b (the DOB correction path for an ID mismatch).
- **Tests:** `dating_v2_verification_contracts` assurance rows; the `dating-verification` Deno decision table; mutant 8.

#### W4b — Trusted devices and re-verification
- **Contents:** W4b migration 1: trusted devices, `dating_require_trusted_device()`, `dating_eligibility` re-created with gate 8; the device id under the neutral key, sent as `x-attune-device` by the Dating-scoped client only (S-7, C-6); new-device re-verification and the setup-restart variant.
- **Depends on:** W4a.
- **Tests:** device-guard contract rows; the device-guard widget test; the header architecture test; mutant 9.

### W5 — Matching and introductions

**Gate before production switch-on (all of W5):** `dating_exclusion_key` provisioned and `exclusion_key_present` green; DV specialist signs the never-introduce copy; the config activated with real review references (product, clinical, fairness, safety), none starting `DEV-`.

#### W5a — Generation
- **Contents:** W5a migration 1: alignment, snapshot and band objects dropped; the `introductions_v2` config; hard filters v2; the hourly generation tick per country with temp-table decryption, caps, ranking and reasons; determinism; the cron replaced.
- **Depends on:** W4b.
- **Tests:** `dating_v2_matching_contracts` (filters, symmetry, caps, determinism, second run creates 0); mutants 2, 3, 6, 20.

#### W5b — Today, card, match moment, digest
- **Contents:** W5b migration 1; Today (§3.4) with honest day states, "Widen who I meet", the family question and the accessible undo; the introduction card with "Why you two were introduced"; counterpart photos through `dating-photo-urls`; photos after mutual interest from day 30; data-saver cards; the match moment (§3.5); the daily digest (neutral, on W3a's `me_update`).
- **Depends on:** W5a.
- **Tests:** matching-contract payload and reasons rows; the concurrency script for simultaneous interest; Today widget tests; mutants 18, 19.

#### W5c — Never-introduce UI, other countries, signals, fairness
- **Contents:** W5c migration 1; "Never introduce me to these numbers" UI; the "Other countries" setting with the cross-border card; the dragnet throttle and the other §5.10 signals (written to `dating_moderation_cases`, which this batch creates and W7 extends); the fairness job.
- **Depends on:** W5b.
- **Tests:** matching-contract cross-border, dragnet and fairness rows; widget tests.

### W6 — Dating chat

**Gate before production switch-on (all of W6):** the safety owner checks every box in `DATING_CHAT_SAFETY_SPEC.md` §12 (v2); the DV specialist signs the sextortion card, the Get help copy and the meeting kit; the cultural reviewer's Twi, Ga, Ewe and Pidgin lexicon entries (stored in Spec 1's match form) and golden fixtures are in and passing.

#### W6a — Messages, masking, swap, chat screen
- **Contents:** W6a migration 1; `dating_messages`; `DatingChatScreen` and its own widgets (§3.6); text only; masking until both swap; swap offered from 72 h with the one-time card; RLS and RPC block enforcement; the conversations list.
- **Depends on:** W5c.
- **Tests:** `dating_v2_chat_contracts` (separation, stale-client block, masking, swap); masking parity fixtures; chat widget tests; mutants 10, 11, 12.

#### W6b — Safety worker, normaliser, lexicon, cards
- **Contents:** W6b migration 1; the outbox and `process-dating-safety-outbox`; `_shared/dating_chat_safety.ts` on S1 W9a's shared `_shared/unicode_normaliser.ts` and fold table (I-17); the lexicon (Ghana, Nigeria and diaspora money scripts, sextortion, contact migration, `meet_private_pressure`, `child_access`, age cues); recipient-only cards; message pushes (neutral `me_update`, collapsed).
- **Depends on:** W6a; S1 W7a (`support_resources` for the cards); S1 W9a (normaliser, fold table and goldens).
- **Tests:** Deno lexicon fixtures and S1's goldens; chat-contract safety-event rows.

#### W6c — Guided conversation, timebox cards, meeting kit, close kindly, purge
- **Contents:** W6c migration 1 (including the `me_checkin` quiet-hours exemption, R17); the guided first conversation; the day-7 and day-21 cards; "We met"; the meeting kit (Plan a meet, Share my plan, Check on me, Get help); `notification_config.dart` case `me_checkin` → `/dating/checkin` behind the lock (I-9); Close kindly; the 30-day evidence window and purge; `DATING_CHAT_SAFETY_SPEC.md` v2.
- **Depends on:** W6b; S1 W7a (`support_resources` for Get help).
- **Tests:** chat-contract close, purge and check-in rows; the 23:30 check-in quiet-hours case; `me_checkin` push-routing widget test.

### W7 — Reporting, enforcement and moderation

**Gate before production switch-on (all of W7):** the safety owner, the moderator who reads Twi, Ga and Pidgin, and out-of-hours P0 cover are named and trained on the runbook; counsel signs the law-enforcement policy; the report copy's SLA sentence matches the staffed hours.

#### W7a — Reports, restrictions, appeals
- **Contents:** W7a migration 1; report categories and priorities (§3.7, §6.2); evidence snapshots; reports from the 30-day "Ended" list; corroborated P0 holds; credibility weighting; the restricted, hold and age-check screens with the category; one appeal to a different human; enforcement carry-over at re-registration; `submit_dating_report` removed.
- **Depends on:** W6c.
- **Tests:** `dating_v2_moderation_contracts` (holds, corroboration, credibility, category, carry-over, appeal decider); report and appeal widget tests; mutants 13, 14, 15.

#### W7b — Console and moderation API
- **Contents:** W7b migration 1; the console (§6.4) as a separate web entry point with TOTP, built in CI (F-6); the `dating-moderation` edge function; read-time sensitive routing (S-5); the audit log; the SLA alerts.
- **Depends on:** W7a; S1 W9b (its Opinions review queue appears inside the console).
- **Tests:** console API Deno tests; moderation-contract routing rows; the CI web build; mutant 26.

#### W7c — Runbook, law enforcement, escalations, transparency
- **Contents:** W7c migration 1; escalation records; the law-enforcement request log; the transparency summary query; `DATING_MODERATION_RUNBOOK.md`; the law-enforcement policy draft; `DATING_MODE_SPEC.md` §8 and chat spec §5.1 / §5.2 amendments.
- **Depends on:** W7b.
- **Tests:** moderation-contract escalation rows (never an automatic send); transparency query counts on fixtures.

### W8 — Device discretion and travel

**Gate before production switch-on (all of W8):** none beyond the device checks in §7.7 (lock screen, screenshots, icon, traveller with a VPN).

#### W8a — Quick exit, screen protection, lock on taps and links
- **Contents:** no migration. `registerDatingDeviceWipes()` and its one line in Spec 1's `lib/app/device_wipes.dart`, registering Dating's entry for quick exit and sign-out (never the lock, the PIN or the icon; C-2, C-3); `FLAG_SECURE` through the `attune/safety` channel; the iOS capture blur (`sceneCaptureState`, F-4); no gallery saves; every Dating route, push tap and deep link honours the Dating lock.
- **Depends on:** W6c (every Dating push type and route exists); S1 W3a (the device wipe registry and `lib/app/device_wipes.dart`); S1 W3b (the Dating lock, `me_section_lock`).
- **Tests:** quick-exit and sign-out widget tests (caches empty; lock, PIN and icon unchanged), `FLAG_SECURE`, lock and push-routing tests.

#### W8b — Plain icon and traveller detection
- **Contents:** W8b migration 1; the plain icon for everyone (Android alias, iOS alternate icon), prompted in Tier 1/2 and now offered at D13; `dating-device-check` with the bundled IP database and the Android SIM/network country; traveller auto-hide and the in-app note (§3.11); `dating_eligibility` gate 7; flag `dating_traveller_detection`.
- **Depends on:** W8a.
- **Tests:** `dating-device-check` Deno tests; traveller rows in `dating_v2_matching_contracts`; icon widget test.

### W9 — Couple link and export

- **Contents:** W9 migration 1; "Become a couple on Attune" (§3.9) with the private "What are we agreeing to?" step; both confirm; one transaction creates the relationship through the invite exchange's row transitions, pauses Dating for both, closes other chats neutrally and sets both paths to Relationship through `set_user_path_internal`; "Keep our first messages" into `couple_how_we_met` (masked unless both swapped), with a row on About us that opens it; the match-date chip through the client override of `aboutUsDateSuggestionsProvider` (I-12); the 30-day "Delete your Dating profile and preferences?" card as one `HomeCard` in `ConversationsScreen`'s list (C-4); the export's own-data `dating` part through `dating_export_for_job` in `build-data-exports`, `export_relationship` re-created with the how-we-met card (S-4, I-13), and the updated export contract test; flag `dating_couple_link`.
- **Depends on:** W6c; S1 W1b (`set_user_path_internal`); S1 W5 (`couple_profiles`, the AU2 chip slot and `aboutUsDateSuggestionsProvider`, About us); S1 W3b (the Relationship space; the card itself goes on the existing `ConversationsScreen`).
- **Tests:** `dating_v2_link_contracts`, `data_export_contracts`; link widget tests; the Relationship-home card test; mutants 21, 22, 23, 28.
- **Gate before production switch-on:** counsel confirms the export scope (own data only, own sent messages, no counterpart data) and the "How we met" copy rule (both consent).

### W10 — Pilot readiness and switch-on

- **Contents:** W10 migration 1 (production-mode guards and `get_dating_launch_readiness()`); the per-country checklist filled in `legal_checklist`; dashboards over `metric_counters` and the fairness reports in the console; a runbook drill (P0 at 03:00, a CSAM hash hit, a law-enforcement request, a same-gender kill switch); the store listing and Welcome copy "Dating open in Ghana and the UK" (with Spec 1); the old `dating_mutual_match` case removed from `notification_config.dart` (A-7); the full §7.7 device matrix; the penetration test; at launch, **the owner** sets the launch project to production mode and then turns production flags on per country.
- **Depends on:** W1–W9.
- **Tests:** the readiness RPC reports every gate green, and reports red while `private.attune_environment()` isn't `'production'` (R-6); smoke tests on the production project with test accounts (introductions, chat, report, appeal, exit, export).
- **Gate before production switch-on:** the owner has set `attune_environment = 'production'` on the launch project (or on a separate production project; no script does this); the Ghanaian legal opinion on the reconsidered bill; Ghana DPC registration; the UK OSA illegal-harms and children's-access assessments and highly effective age assurance in place (and a UK representative if the controller is outside the UK); the DPIA signed; the external penetration test passed with no open High or Critical finding; the safety owner and moderator live; clinician, cultural (with faith advisers), LGBTQ+ and DV reviewers' sign-offs on file; `age_assurance_mode = 'live'`; no `DEV-` reference active; `support_resources` verified within 90 days for Ghana and the UK.

### W11 (later) — Voice calls

- **Contents:** in-app voice calls between matched people, both opting in per call, with a one-time safety card before the first call ("Calls stay inside Attune and your number stays hidden. You can end a call or block at any time. Never share intimate images or video."); no video; calls never recorded; call events (start, end, duration bucket) only; report and block reachable during a call; flag `dating_voice_calls`.
- **Depends on:** pilot data on moderation load (P0/P1 reports per 1,000 matches, time to review) and the chat's first-meeting conversion; a check of whether the Sendbird contract covers calls.
- **Tests:** call permission and opt-in contracts; no call metadata beyond the events; widget tests for the safety card and in-call controls.
- **Gate before production switch-on:** moderation capacity measured in the pilot and shown sufficient; DV reviewer signs the call safety card; DPIA updated for calls.

---

## 9. Regression risks

**Not changed by any wave** (and why):
- **Games:** no file under `lib/features/games/**` or `lib/features/community/**`, no game route, `ChatScreen`'s game entry points, `UniversalBubble`, the `auth_exports.dart` barrel, `profiles.display_name` or its public read. The dating chat imports none of them (architecture test).
- **Couples chat and its Safety System:** `ChatScreen`, `public.messages`, the couples outboxes and workers, and `_shared/chat_safety.ts` (its ASCII-only normaliser has the same 10 F-5 bug; fixing it is a separate couples change, recommended but not part of this spec).
- **The `relationships` grants model:** no column is added; the couple link writes the same row transitions as the invite exchange; `couple_how_we_met` is its own table.
- **`home_screen.dart`**, its redirect latch, `_HomeGateData` and the `ModalRoute.isCurrent` guard: Spec 1 owns them; this spec only fills the Me section slot (W3a) and appends one card to `ConversationsScreen`'s home-cards list (W9, C-4).
- **`quick_exit_service.dart`, `auth_provider.dart` (and the `auth_exports.dart` barrel that re-exports it to Games), `lib/main.dart`, `set_user_path_internal`, `get_public_app_config()`:** not edited. Dating registers its wipe in Spec 1's device wipe registry with one line in `lib/app/device_wipes.dart` (C-2, C-3), sends its device header from its own client (C-6), pauses only the path changes Spec 1 leaves to it (I-5), and re-creates only Spec 1's open-country seam (I-3).
- **The existing Safety PIN and quick exit:** used, never rewritten; quick exit never clears the Dating lock, the PIN or the plain icon.
- **Games entry points on the Relationship home:** untouched by the W9 card (C-4).
- **Spec 1's identity objects:** used, never redefined.

| # | Shared file or object | Risk | Mitigation |
|---|---|---|---|
| R1 | `app_router.dart` | the Dating route block sits in the file that hosts every game route; the first-launch redirect forces `/intro` for every route | edit only the Dating block; keep `RouteNames` for game routes untouched; a router test opens every game route after the change |
| R2 | `notification_config.dart` | stale `dating_mutual_match` pushes on test devices route nowhere; new cases could collide with Spec 1's and Spec 3's | W3a adds `me_update`, W6c adds `me_checkin`; the old case routes to Me for one release and **W10 removes it** (A-7); distinct cases only, no other line changes |
| R3 | Spec 1's device wipe registry (quick exit and sign-out) and `lib/app/device_wipes.dart` | a Dating entry could stall exit or sign-out (the 2026-10-14 lesson: an unmocked `SharedPreferences` call never completes in tests), or clear a protective setting | the entry awaits no I/O, touches no prefs and is not `protective`; Spec 1's registry runs each entry in its own `try` with its 1 s bound and the whole run within 3 s; this spec adds one line to `device_wipes.dart` and never edits `quick_exit_service.dart` or `auth_provider.dart`; tests mock every channel and assert the Dating lock (`me_section_lock`), PIN and icon survive quick exit |
| R4 | `MainActivity.kt` `attune/safety` channel | adding `setSecure` could break quick exit's existing method | new method name only; the existing handler's cases unchanged; Android instrumentation smoke test |
| R5 | `prepare_account_deletion` | extra steps could fail account deletion | each Dating step runs inside its own `BEGIN … EXCEPTION` block that logs a warning code and continues, except the enforcement-record write, which must succeed (a deletion that would drop a ban is retried, not completed) |
| R6 | `relationship_dating_guard` trigger rewire | pausing Dating on `paused` relationships now actually fires | `dating_has_relationship` already blocked them; the contract test covers active → paused → active |
| R7 | Healing (`_healing_refresh_status`, `submit_healing_readiness`, client service and screen) | removing the Dating outcome changes what Healing shows when a journey completes | Healing's own copy is rewritten in W2; `readiness_scoring_service_test.dart` keeps the score tests and drops only the eligibility ones; Healing statuses keep `eligible_for_dating_opt_in` in the CHECK for old rows but nothing writes it |
| R8 | Spec 1's `account_holds` (W4 places `age_review`) | a Dating-placed hold closes the whole app at the next token refresh, so a wrong estimate would lock an adult out of their couple space | only the vendor's high-confidence under-18 band or a moderator's confirmation places it; the person sees support copy first; support clears it through Spec 1's path; contract test asserts no other Dating path calls `place_account_hold` |
| R9 | Data export (`build-data-exports`, `export_relationship`, `data_export_contracts.sql`) | the export gains a part, and `export_relationship` is re-created | the part is built only by `dating_export_for_job` (bound to the job, S-4); `export_relationship` is re-created from its live body (the latest re-creation, whichever spec made it) plus the how-we-met card; the existing parts and their test lines are unchanged |
| R10 | `20260705210000` replays `ON CONFLICT DO UPDATE SET enabled = false` on the Dating flags | a re-run of migrations turns development flags off | development switch-on is `supabase/sql/dev_enable_spec2_dating_flags.sql`, re-run after any migration replay; it refuses to run in production mode and never sets `attune_environment` (R-6); the dev README line says so |
| R11 | Revoking direct table `SELECT` (W3) | any leftover direct read in the client breaks | the repository rewrite and the revoke ship in the same release; a test greps `lib/` for `.from('dating_` and fails on any hit |
| R12 | Dropping `dating_feature_snapshots` and the alignment functions (W5) | functions still referencing them fail at runtime | the same migration rewrites `act_on_dating_introduction` and `get_my_dating_introductions`; a contract test lists every function body and fails on any reference to dropped objects |
| R13 | `users` trigger on `path` (W2) next to Spec 1's `set_user_path_internal` | a trigger on a shared table; a double pause or the wrong reason | `AFTER UPDATE OF path` only, no-op unless the path leaves `dating` for something other than `relationship`, never raises; one writer per reason (Spec 1 D18): the trigger writes `path_change`, Spec 1's one call writes `relationship`; `set_user_path_internal` is not edited by this spec; the contract test and mutant 24 cover both directions (I-5) |
| R14 | Text scaling | Dating screens opt in to 2.0× while the root clamp is still 1.0 (Spec 1 W10a raises it later) | `AllowLargeText` on each Dating screen; goldens at 1.0 / 1.3 / 2.0 |
| R15 | The `x-attune-device` header | a missing header after an app update would lock people out of Dating; a global header would link Opinions activity to a stored id | the header is sent only by the Dating-scoped client, in the same release as the guard (W4b); `lib/main.dart` is not edited; the guard returns `reverify_device` (a flow, not an error) |
| R16 | Formatting | repo rule | only new files are formatted |
| R17 | `scheduled_notifications_quiet_guard` (W6c) | adding the `me_checkin` exemption edits a shared trigger function | one added type next to `safety_resources`; the quiet-hours contract tests run unchanged plus one case proving a 23:30 check-in is not deferred |
| R18 | Spec 1's seam `private.dating_open_countries()` behind anon `get_public_app_config()` and its prefs cache | the Welcome preview, the A6 card or the Me slot could show a stale or empty list | only the seam is re-created (same shape), `get_public_app_config()` is untouched; the row is deleted only after the seam reads the table; the contract test compares every other key of `get_public_app_config()` before and after (I-3) |
| R19 | `users` trigger on `phone_released_at` (W1d) | a trigger on a shared table, fired by Spec 1's fresh start | no-op unless the column goes from NULL to a value; never raises; one contract test runs Spec 1's park path end to end (I-11) |
| R20 | `conversations_screen.dart` (`ReorderableHomeCards`) | a new card could disturb the saved card order or the chat card above it | one `HomeCard` appended only while an offer exists; `resolveHomeCardOrder` already drops cards that disappear; widget test of order and of the chat card; no Games file or entry point touched (C-4) |
| R21 | Dropping `get_dating_eligibility()` (W3a) | a caller left in Spec 1's Me slot or another file breaks | W2 keeps a compatible shim; W3a drops it only after the `lib/` grep test finds no caller (I-4) |
| R22 | Revoking `service_role` on introductions, interest actions and matches (W1a) | an edge function that reads them would get no rows | none does today (grep); every later reader is a definer function; the RLS canary asserts the revoke (S-5) |

---

## 10. Genuinely open items

These need a person this spec cannot stand in for. Everything else is decided above.

1. **Vendors.** Which facial age estimation vendor (UK-recognised, with West African error data) and which ID vendor (Smile ID or an equivalent with Ghana Card support). The seam, the flow and the result storage don't change with the choice; prices and contract lead time do.
2. **Counsel's numbers.** Whether 2 years is the right retention for enforcement records and block pairs in Ghana and the UK; the minimum consent record kept after exit (this spec proposes the account's life + 1 year); the export scope (this spec proposes own data and own sent messages only); the final law-enforcement policy text.
3. **The clinician's ruling** on the gentle wait (this spec builds the owner's ruling: the 30-day window, shorter on both seals, with the reflection) and on the D0 copy.
4. **Reviewer content.** The cultural reviewer's Twi, Ga and Ewe lexicon entries, the region and side lists, the faith and denomination lists, and the intention and attestation wording; the LGBTQ+ reviewer's off-country copy; the DV specialist's never-introduce, sextortion, Get help and meeting-kit copy.
5. **Pilot daily count.** 3 (built default) or 2 for the Ghana pilot; a config change either way.
6. **The moderator's hours.** The staffed window (built as 08:00–22:00 GMT) depends on who is hired and where.
7. **Voice calls (W11).** Whether the Sendbird contract covers calls, and the moderation capacity the pilot shows.
8. **Parked accounts (I-11; Spec 1 O3).** Whether a live Dating restriction on a parked account follows the phone number to the fresh account while the old account is parked. Built default, as in Spec 1: no (the restrictions reach the number at the 180-day purge). A yes adds one write to W1d's parking trigger (§6.3).
9. **Opinions bans after re-registration (I-16; Spec 1 O4).** Whether an Opinions ban or strike count should survive delete + re-register through `enforcement_records`. Spec 1 recommends yes. This spec reserves `scope = 'opinions'` and writes only `dating`; a yes is built as Spec 1 W9d after this spec's W1a, a no drops the reserved value in the next Dating migration.
10. **Q17 exceptions (R-2).** Sign-off on the three survivors of "Exit hard-deletes everything" in §1.3: sealed messages for 30 days, the never-introduce list only if ticked (unticked by default), and consent events for the account's life + 1 year.

---

## 11. Changelog — cross-spec review fix pass (2026-10-24)

Applied against `2026-10-24-cross-spec-review.md` (its "Controller rulings for the fix pass" binding) and 11 §12 including Q19b, then aligned with Spec 1's finished fix pass (its §5.5, §5.8, §10 and §11). Only findings that touch Spec 2 are listed.

| Finding | What changed here |
|---|---|
| **R-2** | §1.3 Q17 row lists the three exceptions for owner sign-off (sealed messages 30 days, never-introduce list only if ticked, consent events); §3.8 "Keep my list" is **unticked by default** and the consent record is named; §4.8, §4.9 (`p_keep_never_introduce` defaults false), §7.1, mutant 30; §10 item 10. |
| **R-5** | §4.10: `chat_couples_locked_screen.dart` button removed by S1 W3b unconditionally; this spec doesn't edit the file. |
| **R-6** (ruling, Q19b) | Header repo rules, §1.1, §1.3 Q19b row: the current project `mrgjtyacrzfylawyzabm` is development; `app.settings.attune_environment` read only through Spec 1's `private.attune_environment()` / `get_attune_environment()`, `development` while unset; only the owner sets `production`; **nothing in this spec sets it**. §2.2: every seed `dating_enabled = false`, the dev script publishes GH/GB in development; "absent counts as production" removed. §4.9: the dev script starts with `private.assert_development_project()`. §8 W10: readiness red until the project reads `production`; the owner flips it. Tests §7.1, §7.3, mutant 25; R10. |
| **I-1, I-2** (ruling) | §4.9 rewritten: migrations by name, purpose and order within each batch only; timestamps assigned at build time after every applied migration; grants twins on the `…10` pattern; shared functions always re-created from their live body (repo rules). All `202612…` timestamps removed. |
| **I-3** | Header, §2.2, §4.9 W1b, §4.10, R18: W1b re-creates Spec 1's seam `private.dating_open_countries()` over `country_safety_config`, then deletes the row; `get_public_app_config()`, the Welcome preview, A6 and the Me slot unchanged; contract compares every other key. |
| **I-4** | §2.1, §4.4, §4.10, R21: `get_dating_eligibility()` kept in W2 as a same-shape shim over `dating_eligibility`, dropped in W3a after a `lib/` grep test (Spec 1's Me slot calls no Dating RPC). |
| **I-5** | §4.9 W2, §4.10, §8 W2, R13, §7.1, mutant 24: one writer per reason, as Spec 1 D18: Spec 1's `set_user_path_internal` pauses only on → `relationship`; W2's `users.path` trigger **skips the switch to `relationship`** and pauses every other change away from Dating with `path_change`. |
| **I-7** | §3.3.2, §6.3, §7.1: every `place_account_hold` call passes three arguments (Spec 1 also defaults `p_ref`). |
| **I-8** | Header: `set_user_path_internal` is Spec 1's (S1 W1b), not W3. |
| **I-9** | §2.7, §3.13, §3.14, §4.9, §4.10, §8 W3a/W6c, §7.4: `me_update` (type, copy, `notification_config.dart` case, tap to Me) lands in **W3a**, before the first possible sender (a notify request; the review table said W5b, moved earlier because notify pushes can fire from W3a); `me_checkin` gets a W6c case → `/dating/checkin` behind the lock. |
| **I-10** | Header, §3.2 D9, §4.7, §7.3: inline only; a match goes through Spec 1's `_shared/csam_match_path.ts` with `record_inline_csam_match`; `dating-profile-photos` is not in Spec 1's scan queue; `media_scan_status` (dropped by Spec 1) not used. |
| **I-11** | Header, §4.4, §4.9 W1a/W1d, §6.3, §7.1, mutant 27, R19: `dating_phone_hmac_for_user` prefers `users.parked_phone_hmac` (never the `+999` HMAC); a W1d trigger pauses a parked account; carry-over under the real number at the purge; live restrictions following the number is owner item O3 (built default no, matching Spec 1). |
| **I-12** | §3.9, §8 W9: the AU2 chip comes from a client override of `aboutUsDateSuggestionsProvider` fed by `get_dating_link_origin`; no `suggested_dates`. |
| **I-13** | §4.3, §4.7, §4.9 W9, §4.10, R9: W9 re-creates `export_relationship` from its live body and adds the `dating` part to `build-data-exports`. |
| **I-14** | §2.1, §4.9: `dating_eligibility(p_user, p_scope)` created in W1b (gates 1–4, 6), re-created in W2 (+5), W4b (+8), W8b (+7); setup writers use the `setup` scope. |
| **I-15** | Dev script renamed `supabase/sql/dev_enable_spec2_dating_flags.sql`. |
| **I-16** | §4.3, §10 item 9: `scope = 'opinions'` stays reserved and unwritten here; Spec 1 O4 decides (a yes is Spec 1's W9d, a no drops the value). |
| **I-17** | Header, §6.1, §7.3, §8 W6b: the Dating chat imports Spec 1 W9a's `_shared/unicode_normaliser.ts` and shared fold table, no fold table of its own; each lexicon family states its form (match form; `age_signal` base form only); terms stored in the match form. |
| **C-2, C-3** (ruling) | Header, §3.0, §3.4, §6.7, §4.10, §7.4, R3, §8 W8a: Dating registers one entry in Spec 1's device wipe registry with **one line in `lib/app/device_wipes.dart`**; `quick_exit_service.dart` and `auth_provider.dart` are never edited; quick exit never clears the Dating lock (`me_section_lock`), the Safety PIN or the plain icon. |
| **C-4** (ruling) | §3.9 step 6, §4.10, §7.4, R20, §8 W9: the 30-day card is one `HomeCard` appended to `ConversationsScreen`'s `ReorderableHomeCards` list (W9); Games entry points untouched. |
| **C-5 / S19** (ruling) | §3.0, §3.3.4, §6.7, §7.2 S19: no "dating" in any key, value or file name; the S19 test also allow-lists Spec 1's device keys (§5.5) plus `attune.install_id`, which is created at first launch for everyone; the Dating lock key is `me_section_lock`. |
| **C-6, S-7** | §3.3.4, §4.10, §7.4, R15: the `x-attune-device` header is sent only by a Dating-scoped `SupabaseClient` (`accessToken` from the main session); `lib/main.dart` not edited. |
| **C-9** | §1.5: Dating docs are this spec's; Spec 1 W10c doesn't touch them. |
| **A-1** (ruling) | Header, §4.5, §7.1, §7.5, §8: no instruction to run `local_pg_setup.sh` or `local_pg_grants.sql` on `attune_spec3a`; per-file `psql -f`; `mutant.sh` described as non-destructive. |
| **A-3** | §3.9 step 3, §7.1: first 50 messages copied masked unless both swapped. |
| **A-7** | R2, §4.10, §8 W10: W10 removes the old `dating_mutual_match` case. |
| **A-8** | Header: which "Spec 2" this is. |
| **A-9** | §2.1 gate 5, §7.1, mutant 29: the window predicate `ended_at > now() - 30 days`. |
| **A-10** | §3.1, §4.9 W1b, §4.10, §7.1: W1b re-creates Spec 1's seam `private.dating_home_summary` (`{enabled, enrolled}`) over Dating's eligibility and states; Settings reads `get_my_home_state().dating.enrolled`. |
| **A-11** | §3.2 D13, §8 W3c/W8b: the plain-icon offer is hidden until W8b. |
| **S-2** | §4.1, §6.9, §4.9 W1a: every Dating metric is server-side (`private.bump_metric_internal`, `bump_metric_server` for edge functions); W1a adds the `metric_key_prefixes` row `dating.` and no `metric_client_keys` row; `dating.quick_exit` dropped; funnel keys corrected. |
| **S-4** | §4.2, §4.3 (`dating_export_reads`), §4.4, §6.8, §7.1, mutant 23: `dating_export_for_user(uuid)` replaced by `dating_export_for_job(p_job_id)` (no user-id parameter; job must be `building`; at most 3 calls; logged); §4.2's service-role claim corrected; canary allows no other service-role decrypt path. |
| **S-5** | §4.1, §4.3, §4.5, §6.4, §6.8, §7.1, mutant 26, R22: no stored `sensitive_routing` bit (computed at read time by `dating_case_needs_sensitive_routing`); `service_role` revoked on introductions, interest actions, matches and link requests; derived special-category data named in the DPIA. |
| **S-6** | §4.4, §7.1, mutant 28: `get_dating_link_origin` members only, opaque `link_origin_unavailable`. |
| **F-1** | §4.5, §8 W3c: this spec adds no `storage.objects` trigger; inline scanning is unaffected by Spec 1's hosted spike; any future one is spiked on the hosted development project first. |
| **F-3** | Header repo rules: own `BEGIN; … COMMIT;`, no `CONCURRENTLY`, no reference to a later wave's table. |
| **F-4** | §6.7, §7.7: `sceneCaptureState` with `isCaptured` fallback; device checks in release builds. |
| **F-6** | §6.4: the console imports only `lib/console/**` and a web-safe client; CI builds it for web. |
| **W-2, W-3** (ruling) | Header and §8: 23 batches (W1a–W1d, W2, W3a–W3c, W4a–W4b, W5a–W5c, W6a–W6c, W7a–W7c, W8a–W8b, W9, W10) per the split table; gates stay per wave; bare wave numbers still cite the whole wave; tests and mutants assigned per batch. |
| **Spec 1 alignment** (coordinator, after Spec 1's pass) | Every Spec 1 dependency now cites its sub-wave (S1 W1a–c, W2a–b, W3a–c, W5, W6a–b, W7a–b, W9a–b, W10a–c); `account_holds` / `place_account_hold` from S1 W1b and the enforcing hook from S1 W6a; environment helpers, seams, registry, normaliser, metric tables, `me_section_lock` and the S19 allow-list use Spec 1's names. |
| **Found in this pass** | Ordering faults under the "no later-wave table" rule fixed: `publish_country_config` gains its kill switch in W1d and its notify queueing in W3a (re-created from its live body each time); `dating_require_trusted_device()` starts as a W1c pass-through so no RPC is re-created in W4b; `dating_notify_requests` moves to W1b. |

Not applicable to this spec (Spec 1 or Spec 3 only): R-1, R-3, R-4, R-7, I-6 (its rule is applied here too), C-1, C-7, C-8, N-1, N-2, A-2, A-4, A-5, A-6, S-1, S-3, S-8, S-9, F-2, F-5, W-1.

---

## Owner approval (2026-10-24)

The owner approved Specs 1, 2 and 3 as written, together with the recommendations for the remaining open items:
- **O2 (Healing AI):** yes. Healing's AI insight gets the same pause, with the `self_disclosure` crisis check running first. It is built in S1 W9 behind `healing_ai_insights`, under the same clinician gate.
- **O3 (parked account restrictions):** no. A parked account's live Dating restrictions do **not** follow a recycled number to the fresh account. The enforcement record stays attached to the old account and its HMAC.
- **O4 (Opinions enforcement records):** yes. Opinions-scope enforcement records survive account deletion like Dating's. This is built as **S1 W9d**, after S2 W1 creates `enforcement_records`.

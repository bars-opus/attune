# Spec 1 — App flow, identity and data model, About us, Opinions and Journal safety minimum — Design

**Date:** 2026-10-24 · **Status:** design for owner review (not a plan, no code), revised by the cross-spec review fix pass (§11) · **Repo state read:** `main` at `a7b07e79` plus working tree.

**Sources, in precedence order.**
1. `docs/superpowers/research/2026-10-24-flow-dating-research/11-synthesis-decisions.md` **§12 owner rulings** (override everything below them).
2. 11 §0–§3, §5, §7–§11; the research files it cites (05 onboarding, 06 audit, 09 everyday simulations, 10 risk simulations, 07 Opinions, 04 safety, 08 citation check).
3. The code read for every surface named here (cited as `file:line`, today's line numbers).
4. Sibling specs written in parallel: `2026-10-24-dating-mode-design.md` (Spec 2) and `2026-10-24-forum-removal-design.md` (Spec 3). Where they name a Spec 1 object, this spec uses that name.
5. House rules: `ATTUNE_SOUL.md` and `ATTUNE_THESIS.md` win and are never edited; the permanent constraints; the date standard (`MyDateFormat`, date and info joined by `MyDateFormat.join`); the couple-name rule (`coupleNameProvider`); "format new files only".

**Conventions.** `11 §2.3` = file 11, that section. `10 F-1` = code fact 1 in file 10. `S2 W4` = Spec 2, wave 4. `W5` alone = this spec's wave 5. Copy in quotation marks is the exact English string; `{name}` tokens are filled at runtime. Every new string goes into `lib/i10n/app_en.arb` under a `flow_`, `aboutUs_`, `support_` or `opinionSafety_` key prefix; other locales fall back to English until translated.

**Which "Spec 1".** This is Spec 1 of the 2026-10-24 flow and dating program (with Spec 2 = Dating Mode and Spec 3 = forum removal). It is not the earlier launch program's specs: there, "Spec 2" was the Safety PIN and quick exit, and "Spec 3a/3b/3c" were relationship lifecycle, deletion and export. Code comments such as "Spec 2 review C2" and the "Spec 3a actions" named below refer to that earlier program.

**Wave count: 9 groups.** The waves keep their 11 §11 numbers: **W1–W7, W9, W10**. **W8 (Opinions v2: anonymity and feedback) is removed** by ruling Q9 and its number is held empty, because Spec 2 and Spec 3 already cite "S1 W9" (content filter, review queue v0) and "S1 W10" (accessibility, doc amendments). If the owner reopens Q9, the redesign takes W8 back without renumbering anything. Large waves are split into lettered sub-waves of 3–4 tasks each (cross-spec review W-1): **W1a–c, W2a–c, W3a–c, W4a–b, W5, W6a–c, W7a–b, W9a–c, W10a–c** (§8). A citation without a letter ("S1 W9", "S1 W10", "S1 W1") means the whole group and stays valid.

---

## 1. Goal, non-goals, owner rulings

### 1.1 Goal

One app with three ways in, built on an identity that can't be rewritten from the phone:
- **Sign-up that a minor can't get through and an adult rarely fails:** name → date of birth (checked on the device) → phone → code (SMS, WhatsApp, voice) → consent, with a server-side under-18 refusal.
- **Three paths** stored on the account (In a relationship / Single and open to dating / Just for me), with Relationship and Dating never active together, a **two-tab home** (Opinions + Chat or Me), silent switching, and a clean hand-off to Spec 2 for Dating.
- **A couples flow that survives real life:** the code in every invite message, "My partner already invited me", a day-7 "Send a new invite", an age and phone check on accept, and a shared **About us** profile that is attributed, quiet and never a type or score.
- **Worldwide launch hygiene for the non-dating app:** platform age signals, Play Restrict Minor Access, a CSAE page, recycled-number protection, country-routed support resources, CSAM hash matching on uploads.
- **The Opinions and Journal safety minimum** ruled in Q10, without the deferred redesign.
- **Accessibility from the first new screen**, and a staged plan to stop clamping the phone's text size app-wide.

### 1.2 Non-goals

- **Dating Mode itself** (D1–D13, verification, matching, dating chat, enforcement records, the gentle-wait reflection). Spec 2 owns it. Spec 1 builds only the Dating section slot inside Me, the path, and the ending hand-off.
- **Forum removal.** Spec 3 owns it; it lands before Spec 1 (Spec 3 W1–W2). Shared files are listed in §5.7.
- **The Opinions redesign (old W8, Q9 "open for debate"):** per-post handles, author-page removal, dislike/repost/quote removal, author-only reactions, Discover re-rank, status-label stamping, coarse times, neutral comment pushes, the audience reminder, "Attune asks". Also not ruled in by Q10 and therefore not built: report thresholds 3/2, a removal notice that names the rule and offers an appeal (W9 only restores today's two notices, §4.3), the reconsider prompt, author comment controls, drafts / keep private / post later, tag mute and new tags, the country-aware compose note.
- **Apple / Google / passkey sign-in** (Q18). Only a seam (§6.8).
- **Solo "Working on us, on my own" content** (Q7: follow-up outside these specs).
- **A journal lock, a duress PIN, the About-us flip-flop hint** (11 §3.4 "optional, P2"), guest drafting in Opinions.
- **Games.** Nothing under `lib/features/games/**`, no `ChatScreen` game entry point, no `UniversalBubble` parameter, no change to the `auth_exports.dart` barrel.

### 1.3 Owner rulings this spec applies

| Ruling | What it means here |
|---|---|
| **Q1 Launch** | The app (couples, Just for me, Opinions) is **worldwide from day one**. So W6 (age signals, Restrict Minor Access, CSAE page) and W7 (resources, CSAM) are launch items everywhere, not country-gated. Dating opens only in Ghana and the UK (Spec 2); Spec 1's path card says "Not open in {country} yet" elsewhere. **Day one still waits on two country gates (§6.10, 11 §7.2):** the Ghana store listing goes live only after the Ghanaian legal opinion, and the UK listing only after its Online Safety Act assessments. "Worldwide" means every other country on day one, with Ghana and the UK joining when their gates clear (or the owner asks counsel for a faster non-dating Ghana opinion). |
| **Q4** (accepted) | DOB **before** the phone, held on the device, written after the code; server refuses under 18. |
| **Q5** (accepted) | `users.phone` not client-writable, mirrored from `auth.users`. Enforcement carry-over by phone HMAC is Spec 2's (`enforcement_records`). |
| **Q6 Navigation** | Two tabs. Tab 2 = **Chat** on the Relationship path, **Me** on Dating and Just for me. Dating is a section inside Me, with an optional **Dating lock**. |
| **Q7** (accepted) | "On my own for now" stays Relationship and never shows Dating; "Send a new invite" replaces "Invite someone else"; withdrawing an invite returns to the previous path; confirm before an invite pauses Dating. |
| **Q8** (accepted) | About us: the owner's four fields, customary-marriage helper text, up to 2 ceremony years, optional child age bands, one anniversary source, an attribution line, no push, no feed. |
| **Q9 Opinions redesign** | **Deferred, not decided.** Opinions stays as it is. Old W8 is out of scope. |
| **Q10 Safety minimum** | (1) Pre-post content filter (contact info, slurs, explicit content) with a Unicode normaliser, a "Need support now?" link, an "at risk" report reason. (2) The Journal's Gemini insight paused until the hard-coded `self_disclosure` check runs first. In W9. |
| **Q11** (accepted) | Raise the text-scale clamp in stages. |
| **Q18 Sign-in** | Phone only. The phone is the identity anchor; a seam for linking methods later. |
| **Q19 / Q19b Switch-on** | Everything behind feature flags; **all flags ON in development** for full testing; production switch-on waits for each wave's gate. The current Supabase project (`mrgjtyacrzfylawyzabm`) **is** the development project until launch (Q19b); production mode is the server setting in §2.5, set only by the owner. |
| **Q20** (accepted) | The doc amendments are applied in W10 (§8). |

### 1.4 Decisions this spec makes where the sources or the code disagree

| # | Decision | Why |
|---|---|---|
| D1 | Waves keep their numbers; W8 is held empty. | Spec 2 and Spec 3 already cite S1 W9 and S1 W10. |
| D2 | The attribution line renders as **"Changed by Yaw - Tue, 12 Nov"** (`MyDateFormat.join`), not with "·". **Owner confirms at sign-off** (Q8 was accepted as "Changed by Yaw · 12 Nov"). | The owner's date standard (2026-10-15) forbids "·" next to a date. Same words, house separator. |
| D3 | `users.mode` is **retired, and the column is kept** (controller ruling, 2026-10-24): every writer stops (client, both invite functions, the five dating functions), clients lose the column grant, a contract test proves nothing writes it. No SQL fixture is edited. | Eight SQL fixtures insert `mode`, one of them `supabase/tests/games_contracts.sql`; dropping the column would mean editing a Games test, which the Games rule forbids. |
| D17 | W9 **restores the two Opinions moderation notices** (`forum_content_removed`, `forum_posting_banned`) that `admin_confirm_content_removal` stopped queuing in `20260802120000` (Spec 3 V8 and §10 F-1). **Owner nods at sign-off** (it isn't in Q10's list). | A removal or ban the author is never told about is a silent punishment. Restoring today's notices is a bug fix, not the redesign (rule and appeal stay deferred). |
| D4 | Phone HMAC callers in Dating are re-pointed to `auth.users.phone` by **Spec 2 W1**, not here. F-1 is closed in W1 by the column grant alone. | Spec 2 §5 already owns `dating_phone_hmac_for_user(uuid)`; the dating fixtures (`dating_exclusion_wiring_test.sql`) put the phone only on `public.users` and change with that work. |
| D5 | **Found while writing this spec, widened by the cross-spec review (S-1, Critical):** `profiles.banned_until` **and `profiles.confirmed_violation_count`** are client-writable today (table-level `INSERT`, `UPDATE` and `DELETE` on own row, `20260713120000:80`; the count column from `20260722120000:23`; no guard trigger anywhere). A banned Opinions author can clear their own ban, reset their strike count to 0 so they never reach the 3-strike ban, or delete and re-insert their profile to reset both. W1a adds one guard trigger for both columns and for that delete (§4.4), with a contract test and a mutant. | Same class as 10 F-1. Both columns are written only by the service-role `admin_confirm_content_removal`. |
| D6 | **Found:** `AppConstants.supportEmail = 'support@yourapp.com'` (`lib/core/utils/constants.dart:50`) is a placeholder shipped in the EULA. W6 replaces it. | Apple 1.2 needs published contact information. |
| D7 | `accept-invite` moves its decision into **one SQL function** (`accept_relationship_invite_v2`), called by the edge function with the service role. | Today it is five separate client calls (`accept-invite/index.ts`), so "withdraw the acceptor's own invite in the same transaction" is impossible as written. |
| D8 | Sign-up writes the account in **one atomic RPC** (`complete_sign_up`): an under-18 DOB writes nothing at all, not even the `users` row. | Today `record_eula_acceptance` creates the row before anything else (`20260817120000:61-74`). |
| D9 | An invite is **accepted only after an explicit "Join {name}" tap**, not silently by the gate. | Today `OnboardingGate` accepts before the name step (`onboarding_gate.dart:41-44`); on a shared phone the next person to sign in inherits the code (10 S17). |
| D10 | The path-chosen moment uses the standard 300 ms step, not a 400 ms container transform. | Keeps the flow inside the app's 150–320 ms band; the one calm celebration per path is the only flourish. |
| D11 | Copy says **"Use the newest code."** after a resend. | Supabase Auth keeps one live phone code per user; "either of the last two works" is not something the client can promise. |
| D12 | The Journal pause (flag check, default off) lands in **W1**; the `self_disclosure`-first check lands in W9. | The risk is live today (10 F-7) and the pause is one guard. |
| D13 | An "at risk" report **never counts toward auto-hide**. | Hiding a help-seeking post cuts the person off from support; the reason exists to reach a human. |
| D14 | `profiles.relationship_status` is written **once, at the first path choice**, as today, and never re-synced on a switch. **Known limit (review S-9):** the column stays client-writable (the legacy onboarding upsert writes it, `onboarding_submission_service.dart:59`), so "written once" binds only the server. It is a self-declared label that no gate, filter or match reads; it is added to the `profiles` guard when the legacy onboarding path is deleted (not in this spec). | The column is readable by every signed-in user (`20260713120000:57-60`); re-syncing it would broadcast path switches. The stale-label problem stays with Q9 (§10 O1). |
| D15 | Every reader of the Dating open-country list goes through **one server seam**, `private.dating_open_countries() → text[]` (W1c), exposed to clients as `config.dating_open_countries` in `get_public_app_config()` (anon). The readers are: the **pre-auth Welcome Dating preview** (WL1), the A6 "Not open in {country} yet" line, and the Me Dating slot (until S2 W3 replaces it). In W1c the seam reads the interim `app_public_config` row. **Spec 2 W1 re-creates the seam** (or `get_public_app_config()` from its live body) to read `country_safety_config`, keeping the key's shape (an array of ISO 3166-1 alpha-2 codes), and only then deletes the row. No client is re-pointed for the Welcome sheet. "Tell me when it's here" is Spec 2's (`dating_notify_requests`). | Spec 2 §2.2 owns the country table; two tables would drift. One seam means a reader can't be missed (review I-3). |
| D16 | Questions addressed to one partner keep "you two" ("Where do you two live?"); titles and labels that name the pair use `coupleLabel(name)`. | The couple-name rule targets naming the pair as a unit; "couples" as a fallback inside a question changes its meaning, and a pending pair has no chat name yet. |
| D18 | **One owner for Dating pauses on a path change (review I-5).** Spec 1's `set_user_path_internal` calls `pause_dating_for_relationship_user` **only on a change to `relationship`** (the confirmed "Inviting a partner pauses Dating" case, with the relationship reason). Every other change away from Dating (Dating → Just for me) is paused by **Spec 2 W2's `AFTER UPDATE OF path` trigger** with `pause_reason = 'path_change'`; that trigger leaves a change to `relationship` to this call. | One writer per reason; no double pause, no wrong reason. Until S2 W2 lands, Dating → Just for me doesn't pause today's v1 enrollment, which is why `flow_paths_v2` gets the S2 W2 production gate (§8 W3c). |
| D19 | **Spec 1 owns the device wipes (controller ruling C-2/C-3).** Spec 1 owns `quick_exit_service.dart` and the sign-out path in `auth_provider.dart`, and adds one generic, ordered **device wipe registry** (§5.8) that both call. Spec 2 registers its Dating entries in the registry and never edits those two files. **Quick exit never clears a protective setting:** the Dating lock, the Safety PIN and the discreet icon survive it. | Quick exit doesn't sign out: it sets `safety_requires_unlock`, wipes caches and leaves. Clearing the lock there would remove the protection exactly when someone is looking over the person's shoulder. |
| D20 | **No Dating value on the device (controller ruling C-5).** The home-state cache stores the **tab layout** (`chat` or `me`), never the path; Dating state is always read from the server and held in memory only. Spec 1's device keys carry no "dating" in their names or values (§5.5). | Spec 2's S19 test ("no Dating data on disk") must pass on a searched phone. |

### 1.5 Never touch (binding)

- `lib/features/games/**`, `ChatScreen` game entry points (`chat_screen.dart:69-78, 2137, 5189`), `message_bubble.dart` game bubbles, `UniversalBubble` and `ChatTextField` forum-era parameters, `lib/features/auth/utility/auth_exports.dart`.
- `profiles.display_name` and its read-by-every-signed-in-user policy (8 game call sites).
- The `home_screen.dart` redirect latch and its `ModalRoute.isCurrent` guard (`home_screen.dart:340-365`).
- The `relationships` grants model (column-level SELECT, no client UPDATE; `20261018100100:34-41`).
- The existing Safety PIN and quick exit: extended, never rewritten (quick exit and sign-out each gain one call to the device wipe registry, §5.8; their existing wipes stay exactly as they are).
- `ATTUNE_SOUL.md`, `ATTUNE_THESIS.md`.

---

## 2. Rules for every screen

### 2.1 Copy

- Plain words, sentence case, short sentences. No "AI", "analysis", "insight", "intelligence" or "patterns" in anything a couple sees before linking (Master Spec decision 29), except the consent line (A5), which must disclose.
- The partner is always **named**: the partner's first name from the server once linked; before linking, the optional first name typed at R1 (device only); otherwise "your partner". Never "he", "she" or "they".
- The pair as a unit uses `coupleLabel(name)` / `coupleInSentence(name)` (§1.4 D16).
- Every sensitive question has one "why we ask" line and a "More about this" sheet. "Skip" sits in the same place (bottom-left text button) on every optional question.
- Dates use `MyDateFormat` only. W5 adds `MyDateFormat.toMonthYear` ("October 2024") and `MyDateFormat.toYear` to the shared class so no screen invents a pattern.

### 2.2 Motion tokens (added to `lib/core/ui/motion/motion_tokens.dart`, W2)

| Token | Value | Use |
|---|---|---|
| `kStepForwardDuration` | `Durations.medium2` (300 ms) | Shared-axis X step: 30 dp slide with `Curves.easeInOutCubicEmphasized`; outgoing fades 0–90 ms (`Easing.emphasizedAccelerate`), incoming 90–300 ms (`Easing.emphasizedDecelerate`) |
| `kStepBackDuration` | `Durations.medium1` (250 ms) | Same, reversed |
| `kReducedMotionFade` | `Durations.short3` (150 ms) | Opacity-only cross-fade replacing every step when `reduceMotionOf(context)` is true |
| `kSelectionDuration` | `Durations.short3` (150 ms) | Option selected: state layer + check; `HapticFeedback.selectionClick` |
| `kCodeAcceptedHold` | 400 ms | Code accepted: check fades in over 150 ms, holds, then auto-advances |
| `kCelebrationMaxDuration` | `Durations.long4` (600 ms) | Ceiling for the one calm celebration per path |
| `kSharedAxisOffset` | 30 dp | Slide distance; negated under `TextDirection.rtl` |

- **One calm celebration per path:** Relationship = "You're both here" (two avatars settle with the existing `SettleIn` spring, `kSettleDuration` 280 ms, then the line fades in; ≤ 600 ms; one light haptic; once per phone). Just for me = "Saved, just for you." (the check fades in over 150 ms; text only). Dating = the first mutual match screen in Spec 2, held to the same 600 ms ceiling.
- **Never animated:** the under-18 stop, consent, the dormancy screen, the hold screen, any safety or country note, the ending card and gentle-wait line, report and support sheets, "not open here", expired invites.
- No confetti, no fake "setting up" waits; any wait over 400 ms shows a linear indicator with words ("Sending your code…"), nothing under 400 ms.
- New shared widget `lib/core/ui/motion/shared_axis_step.dart` (`SlideTransition` + `FadeTransition`, no new package).
- **The 900 ms card advance** (`onboarding_deck_card.dart:88`, `_advanceDuration`) is cut to `kMakeRoomDuration` (320 ms) in W10.

### 2.3 Accessibility (from W2 onwards, not at the end)

- Every new screen is wrapped in `AllowLargeText` (`lib/core/ui/text/allow_large_text.dart`, W2). The root shell clamps to 1.0 (`app_shell.dart:34-35`) and a nested `withClampedTextScaling` can't rise above its parent, so the wrapper re-reads `MediaQueryData.fromView(View.of(context)).textScaler` and clamps it to 2.0 for its subtree.
- Golden tests for every new screen at 1.0, 1.3 and 2.0, and once under `Directionality.rtl`.
- Every control has a semantic label (`Semantics(container: true, label: …)` where a label would otherwise merge into its parent); touch targets ≥ 44 dp; contrast ≥ 4.5:1; widget tests run `labeledTapTargetGuideline`, `androidTapTargetGuideline` and `textContrastGuideline`.
- Errors are announced (`SemanticsService.announce`) and never shown by colour or motion alone.
- Undo affordances stay until the next action, or at least 20 s when a screen reader is on.

### 2.4 Permissions

- No contacts permission, ever. Photos through the system picker. Location only inside Map (unchanged).
- **Notifications are asked only in context** (W3c): one line of reason plus one "Turn on" button, inside the feature; dismissing is carrying on. The automatic ask after sign-in (`onesignal_service.dart:587-631`) stops under `flow_paths_v2`. Contexts: R2 heads-up, R4 messages, J3 reminder (Spec 2 adds its own).

### 2.5 Feature flags

All rows live in `public.feature_flags`, inserted **false** by W1c's flags migration (migrations never turn a flag on). `supabase/sql/dev_enable_spec1_flags.sql` (not a migration) turns every one on in development.

**Environments (Q19b; review R-6, controller ruling).**
- The current Supabase project (`mrgjtyacrzfylawyzabm`) is the **development and testing project until launch**. It has no real users, and everything in this spec is switched on there. Before launch the owner either flips it to production mode or creates a separate production project.
- Production mode is one server setting, **`app.settings.attune_environment`**. It reads `'development'` while unset. **Only the owner** sets it to `'production'` at launch (`ALTER DATABASE postgres SET app.settings.attune_environment = 'production'`, on whichever project becomes production, before its first real user). **No migration, script or edge function in this spec ever sets it.**
- `private.attune_environment() → text` (W1c, no grants; a service-role wrapper `get_attune_environment()` for edge functions) returns `'development'` when the setting is unset or empty, `'production'` when it reads `production`, and `'production'` for any other value, so a typo fails closed.
- **What production mode enforces here:** (1) the production flag gate below; (2) `dev_enable_spec1_flags.sql` refuses to run; (3) `scan-media` refuses the `stub` matcher (W7b). Spec 2 uses the same helper for its own guards.
- **The dev script** starts with `SELECT private.assert_development_project();` (W1c), which `RAISE`s `env:not_development` unless `private.attune_environment()` reads `development` **and**, when `app.settings.supabase_url` is set, it names the development project ref. It never writes the setting. Like `dev_enable_spec8_flags.sql`, it is safe to re-run. Spec 2's dev script can call the same guard.

**Production flag gate (review R-7).** `private.flag_production_gates(flag_key text PK, gate text NOT NULL, review_ref text NULL, recorded_by text NULL, recorded_at timestamptz NULL)` holds one row per gated flag below, seeded in W1c with the wave's gate text and a NULL `review_ref`. A `BEFORE INSERT OR UPDATE` trigger on `public.feature_flags` refuses `enabled = true` for a gated flag with `flag:gate_evidence_required` when the environment is production and the row's `review_ref` is NULL. It does nothing in development and nothing for ungated flags. The owner records evidence through the service role (`record_flag_gate_evidence(p_flag text, p_review_ref text)`). `production_flag_violations() → setof text` (service role) lists gated flags that are on without evidence: the launch checklist runs it **right after** flipping the setting and turns those flags off, because the trigger only sees later writes. Spec 2 may add its own rows.

**Flag dependencies (review A-6).** `flow_paths_v2` needs `flow_signin_v2`; `flow_couples_v2` needs `flow_paths_v2`; `couple_profile` needs `flow_couples_v2`. Readers use the **effective** value (the flag and everything it needs). On the client, each provider in §5.3 computes it. On the server, `private.spec1_flag_on(p_key text) → boolean` (W1b, because `set_my_path` reads it; W1c inserts the rows) does the same, and `get_public_app_config()` returns effective values.

| Flag | Wave | Read by | Off means | Production gate |
|---|---|---|---|---|
| `flow_signin_v2` | W2a–c | client (also anon via `get_public_app_config`), `accept_relationship_invite_v2`, `create-relationship-invite` | `IntroScreen`, `LoginScreen`, EULA v1 and today's onboarding; invite age check skipped | W2 group gate (W2c) |
| `flow_paths_v2` | W3a–c | client | today's `OnboardingMode` home and post-sign-in push prompt | Spec 2 W2 live (D18) |
| `flow_couples_v2` | W4b | client | today's invite copy, "Invite someone else", silent accept | none (Pidgin stays hidden until its own review) |
| `couple_profile` | W5 | client, Together | no About us; "Add your anniversary" opens the reminder sheet | W5 gate |
| `dormancy_rule` | W6a | `attune_access_token_hook` | no dormancy challenge (holds still apply) | W6a gate |
| `platform_age_signals` | W6b | client (anon) | no Declared Age Range / Play Age Signals read | W6b gate |
| `support_resources_v2` | W7a | client (anon) | today's static Safety resources screen | W7a gate |
| `csam_hash_matching` | W7b | `scan-media`, `media_scan` trigger (or sweep) | nothing is queued or scanned | W7b gate |
| `opinions_safety_v1` | W9a, W9b | `private.assert_opinion_content_ok`, client | no filter, no support link, no at-risk reason | W9a and W9b gates (reviewed lists, a named daily reviewer) |
| `journal_ai_insights` | W1c (created), W9c (may switch on) | `analyse-journal-entry` | no Gemini call; status `paused` | W9c gate (clinician) |
| `text_scale_v2` | W10a | client (anon) | root clamp stays 1.0 | W10 group gate (W10c) |

Security hardening is **never** behind a flag (W1a grants, the `profiles` moderation guard for `banned_until` and `confirmed_violation_count`, the atomic accept, the scoped invite key, the metric allow-list, the OTP intent rules, holds in the access-token hook).

---

## 3. Screen-by-screen flow

Format per screen: **Purpose · Copy · Fields · Validation · Storage · Motion · Accessibility · Errors.** Global rules in §2 are not repeated.

### 3.1 Store page and first open

**S0 · Store listing** (owner, App Store Connect and Play Console; W2 gate)
- Purpose: promise exactly what the app does.
- Copy: subtitle "Love, dating and you" (≤ 30 characters). Description first line: "Adults 18+. Sign in with your phone number. Dating is open in Ghana and the UK." First three screenshots, captured from the app: the Relationship space (couples of different ages, including a married couple over 50), an introduction card with "Open in Ghana and the UK", a journal page. Imagery localised per market; the Ghana listing goes live only after the Ghanaian legal opinion (11 §7.2).
- Ratings: App Store 18+; Play content rating answered for an 18+ social and dating app; Play **Restrict Minor Access** on (W6b).

Screen ids **WL0** and **WL1** are screens, not waves (review A-2).

**WL0 · Native splash** — unchanged asset; ≤ 1 s; the first frame never waits on the network (W10 measures and fixes, §3.14).

**WL1 · Welcome** (`/welcome`, replaces `IntroScreen` under `flow_signin_v2`)
- Purpose: show the three ways in and every gate before anyone types.
- Copy:
  - Title: "Love, dating and you, in one calm place."
  - Three equal cards, nothing preselected: "In a relationship" · "A private space for you and your partner." / "Single and open to dating" · "A few introductions a day. Only when it's mutual." / "Just for me" · "Your journal, quizzes and Healing."
  - Buttons: **"Get started"** (primary), **"I already have an account"**, **"I have an invite"**. Text link: **"Read Opinions first"**.
  - Footer: "Attune is for adults (18+) and uses your phone number to sign in." Links: "Terms", "Privacy".
- Card → **preview sheet** (static, bundled, no network):
  - Relationship: title "A space for the two of you"; lines "Chat, plans and memories only you two can see." / "Your journal stays yours. Your partner never sees it." / "Invite your partner with a link or a code."
  - Dating: title "Introductions, not swiping"; lines "Up to 3 introductions a day, chosen for what you both want." / "A match only when you both say yes." / "A live video selfie checks your age before your first introduction." / "Dating is open in {open countries}. More countries later." (built from `get_public_app_config().config.dating_open_countries` and its prefs cache, the D15 seam, e.g. "Ghana and the UK"; the line is left out when the list is empty or has never been read).
  - Just for me: title "A private space for you"; lines "A journal only you can read." / "Short quizzes about how you connect." / "Healing, after a breakup or a loss." / "Single, partnered or in between."
  - Each sheet: one bundled illustration (WebP ≤ 60 KB, with an `excludeFromSemantics` decorative flag and the lines as the readable content), buttons "Get started", "Close".
- Storage: any button tap writes the first-launch flag through `PreferencesService.setFirstLaunchCompleted()` and flips `RoutingNotifier.completeFirstLaunch()`, exactly as `IntroScreen` does.
- Motion: sheet in 300 ms, out 200 ms; reduce motion → 150 ms fade.
- Accessibility: cards are buttons labelled "{title}. {line}. Opens a preview."; reading order title → cards → buttons → link → footer.
- Errors: none (no network). If the device carries an active under-18 block (§3.6), "Get started", "I have an invite" and "Read Opinions first" open X1 instead.

### 3.2 Guest

**G1 · Birth-year gate** (`/guest-age`, once per install)
- Purpose: a neutral age gate before reading Opinions (09 Q12; FTC neutral gate).
- Copy: title "What year were you born?"; hint "We ask everyone. It stays on this phone."; field label "Year"; button "Continue".
- Fields: 4-digit year, numeric keyboard, **no default**, no list of qualifying years.
- Validation: 4 digits ("Enter the year with 4 digits, like 1994."); not after this year ("That year is in the future."); not before 1900 ("Check the year."). `currentYear − year < 18` → X1. Equal to 18 passes (the full DOB at A2 decides).
- Storage: the year in the backup-excluded secure store `attune_age_gate` (FlutterSecureStorage, Android file excluded from backup, iOS Keychain `first_unlock_this_device`); a plain prefs bool `attune.age_gate.guest_ok` for routing. The year pre-fills A2's year field and is deleted when sign-up completes.
- Motion: none. Accessibility: field labelled "Year you were born, 4 digits". Errors: inline under the field.

**G2 · Guest Opinions** — unchanged (Q9). Tab 1 = Opinions (Discover); Tab 2 label becomes **"Sign in"** and shows `LoginProfile` with new copy (W2): title "Join Attune"; body "A private space for couples, a few introductions a day for singles, and a journal just for you."; buttons "Get started", "I already have an account", "I have an invite". The topic carousel stays (Spec 3 removes its Forums card through the registry).

**G3 · Guest → sign-up** — any write or react action opens "Sign in to write" → SignUpFlow (A1). After A6 the person lands **once** on the Opinions tab where they started (`attune.flow.return_to = opinions`); no guest draft is kept (Opinions stays as is).

### 3.3 Sign-in: a new account (`/signup`, one route hosting steps A1–A5 with `SharedAxisStep`)

The order is **name → DOB → phone → code → consent** (Q4). A1–A3 are held on the device (`SignUpDraftStore`, anonymous scope) so closing the app resumes at A4.

**A1 · Your name**
- Copy: title "What should we call you?"; hint "This is the name your partner sees. Opinions never shows it."; field label "Your name"; button "Continue".
- Validation: trimmed, internal whitespace collapsed; 1–40 characters; at least one letter in any script (`RegExp(r'\p{L}', unicode: true)`). Errors: "Add a name with at least one letter." / "Use 40 characters or fewer." Today's ASCII rule (`profile_setup_step.dart:58-59`, `[a-zA-Z]` ×2) is not used.
- Storage: device draft until A5, then `users.display_name` and `profiles.display_name` (games read the latter). The draft also holds a random 16-byte `device_nonce`, made when the draft is created and deleted with it; it is sent only to `otp-delivery-intent` (stored there as a SHA-256 hash for 10 minutes) and never identifies the person.
- Accessibility: autofocus; `TextInputAction.next`.

**A2 · Date of birth**
- Purpose: stop a minor before they hand over a phone number.
- Copy: title "What's your date of birth?"; hint "We only ever show your age, never your birthday."; example under the fields in locale order ("For example, 27 3 1996" or "For example, 3 27 1996").
- Fields: three labelled numeric fields, **Day · Month · Year** or **Month · Day · Year** following the device locale's `DateFormat.yMd` pattern; no defaults (year pre-filled only from G1).
- Validation (inline, specific): "Day must be between 1 and 31." / "Month must be between 1 and 12." / "Year must have 4 digits." / "That date doesn't exist. Check the day and month." / "That date is in the future." / "Check the year." (more than 120 years ago).
- Confirmation once valid: "{MyDateFormat.toDate(dob)} - that makes you {age}." (e.g. "Friday, November 8, 1991 - that makes you 34."). Age is computed against today's UTC date (stricter at the day boundary).
- Platform signals (W6b, `platform_age_signals`): on open, read Apple Declared Age Range (when the App Store storefront is in `age_signal_storefronts`) or Play Age Signals. A minor or supervised result opens X1 without asking for the DOB. If the DOB says adult and the signal says minor, X1 (the stricter wins). Unknown or unavailable: the DOB decides. Nothing about the signal is stored or sent.
- Storage: device draft until A5.
- Under 18 → X1 and a 30-day device block (§3.6).
- Motion: none on the stop. Accessibility: each field labelled "Day of birth", "Month of birth", "Year of birth"; the confirmation line is a live region.

**A3 · Phone**
- Copy: title "What's your phone number?"; hint "We'll text you a code to sign in. We never show your number to anyone."; primary button "Text me a code"; secondary "Send by WhatsApp instead"; inline "By continuing you agree to the Terms and Privacy Policy."
- Fields: country (button with flag and calling code) + national number.
- Default country: Android SIM country (`TelephonyManager.getSimCountryIso`, new `lib/core/platform/sim_country.dart`), else the device region, else none (the picker opens). Never hard-coded Ghana (today `phone_country.dart` `defaultCountry => ghana`).
- Validation: `phone_numbers_parser` for the chosen country; a leading national 0 is accepted and dropped; stored E.164. Errors: "Check the number. It looks too short." / "Check the number. It looks too long." / "That doesn't look like a {country} number. Check the country."
- WhatsApp: a sheet "Is WhatsApp on {formatted number}?" body "We'll send the code to WhatsApp on this number. If WhatsApp is on a different number, we'll text you instead." buttons "Yes, send it to WhatsApp" / "No, text me".
- Storage: the number and chosen channel in the device draft; `auth.users.phone` after A4.
- Sending: the client first calls `otp-delivery-intent` (channel, platform, locale and the draft's random `device_nonce`), then `signInWithOtp(phone, channel: OtpChannel.sms)`; the Send SMS Hook delivers on the intended channel only when the intent rules hold, and otherwise by SMS (§4.5, review S-3). Wait > 400 ms → "Sending your code…". Until W2c lands, W2b sends by SMS through Supabase's built-in provider and shows no channel choice.
- Errors (no vendor names): "We couldn't send a code right now. Try WhatsApp or a call." / "Too many codes. Try again in {minutes} minutes." / "Phone sign-in is unavailable right now. Please try again later."

**A4 · Code**
- Copy: title "Enter the code"; subtitle "We sent a 6-digit code to {formatted number}."; link "Wrong number? Change it"; resend "Send a new code in 0:30" → "Send a new code"; after a resend, "Use the newest code."
- Field: **one** text field drawn as six boxes (`one_time_code_field.dart`), `AutofillHints.oneTimeCode`, digits only, max 6; semantics "Verification code, 6 digits". Android autofill through the SMS Retriever / User Consent APIs via the `smart_auth` package (no SMS permission); iOS through `oneTimeCode` and the origin-bound last line.
- Resend ladder: available at 30 s, then 60 s, then 120 s after each send (stored `last_sent_at` and `send_count` in the draft, so reopening keeps the ladder). After the **second** resend two more buttons appear: "Try WhatsApp" and "Call me with the code". The call copy: "We're calling {formatted number} now. The code is read out twice."
- Validity: 10 minutes (Auth setting, §4.5).
- Accepted: the check fades in, holds 400 ms, auto-advances. Wrong: "That code didn't work. Check it and try again." with a medium haptic; a two-cycle shake only when motion is allowed. Expired: "That code has expired. Send a new one."
- Hook outcomes on verify: `account_dormant:{nonce}` → DM1 (§3.5); `account_review` → H1 (§3.15).
- After verify, the client calls `get_my_home_state()`: no account → A5; an existing complete account → the typed name and DOB are **discarded**, "Welcome back, {stored name}." for 1 s, then home on the stored path; an existing account with `needs` → the matching interstitial (§3.15).

**A5 · Before you start** (EULA v2)
- Copy: title "Before you start"; three bullets:
  1. "Attune is for adults. Everyone here is 18 or older."
  2. "Some Attune features use AI to give you private suggestions. In a shared space they can read your chat with your partner, and only after you both agree. What it suggests to one of you is never shown to the other."
  3. "You can download everything you've added, and delete your account, any time."
  Links "Terms of use", "Privacy policy", "More about AI in Attune"; buttons "Agree and continue" / "Not now".
- Bullet 2 is checked sentence by sentence against the live AI features (Sessions consent, journal insight, Pulse) by the owner and privacy counsel before W2 switch-on (W2 gate).
- Storage: `complete_sign_up(p_display_name, p_birth_date, p_eula_version '2')` (§4.3) writes `users`, `profiles.display_name`, `account_birthdates` and the consent in one transaction, phone from `auth.users`. Offline: the call is queued (`PendingSignUp`) and replayed by `OnboardingSyncService`; the flow continues to A6 locally.
- "Not now" signs out; nothing was written (the empty auth user is purged within 24 h, §4.9).
- Errors: `signup:not_eligible` → X1 (server variant: "We couldn't create your account." + the X1 body); `signup:phone_required` → "Phone sign-in is unavailable right now."
- Motion: none.

### 3.4 Sign-in: a returning account ("I already have an account")

- A3 → A4 with the same copy. **A code is always sent** (`signInWithOtp` creates an auth user for an unknown number, which is purged after 24 h if nothing follows); nothing is answered before the code proves ownership (10 F-10).
- After A4: complete account → home on the last path; needs → interstitials; **no account** → N1.
- **N1 · No account:** title "We couldn't find an Attune account for this number"; body "You can create one now."; buttons "Create an account" (→ A1, A2 with the draft, A5, A6) / "Use a different number" (signs out → A3).

### 3.5 A recycled number (W6a, `dormancy_rule`)

The access-token hook refuses a fresh OTP sign-in to an account with no activity for 180 days and returns a single-use nonce (§4.4). No token is issued, so no data is readable.

**DM1 · Welcome**
- Copy: title "Welcome to Attune"; body "Let's get you set up."; button "I'm new to Attune"; small link "Used Attune before on this number? Contact support" (mailto the support address).
- Nothing about the old account is shown: no name, no path, no partner, no dates.
- "I'm new to Attune" → `start-fresh-account` (nonce) parks the old account (§4.5) → **DM2**: "One more code to finish" / "We'll send a new code to {formatted number}." / "Send code" → A4 → a new account (A1/A2 from the draft if present, A5, A6).
- Support policy: support never confirms or denies that an account exists, except under valid legal process; recovery is support-only and **a DOB alone never unlocks anything** (10 S7).
- Motion: none. DV specialist reviews DM1 and DM2 (W6a gate).

### 3.6 The under-18 stop

**X1 · Attune is for adults** (`/age-stop`)
- Copy: title "Attune is for adults"; body "You need to be 18 or older to use Attune. We haven't saved anything you entered."; link "Support for young people" (W7: the `youth` category for the device country; before W7, the international directory `https://findahelpline.com`); button "Close".
- Storage: `blocked_until = now + 30 days` in two places: a plain prefs file **included** in Android Auto Backup (`attune_age_block.xml`) and an iOS Keychain item. The block **usually** survives a reinstall: on iOS through the Keychain; on Android only when a backup has run before the uninstall (Auto Backup runs about daily, on Wi-Fi and while charging) (review F-5). The draft (name, DOB, phone) is deleted. Server variant: the client signs out.
- While blocked: Welcome's actions and G1 open X1. The block clears itself after 30 days. No retry loop, no hint of the cut-off.
- Motion: none.

### 3.7 Path choice

**A6 · What brings you to Attune?** (inside `/onboarding`, `PathStep`, under `flow_paths_v2`)
- Copy: title "What brings you to Attune?"; three equal cards, nothing preselected:
  - "In a relationship" · "A private space for you and your partner."
  - "Single and open to dating" · "A few introductions a day. Only when it's mutual." + "Not open in {country} yet" where `{country}` (ISO from the person's own E.164 number, parsed on the device) isn't in `config.dating_open_countries` (the D15 seam).
  - "Just for me" · "Your journal, quizzes and Healing. Single, partnered or in between."
  - Footer "You can change this any time. Your journal and quizzes are yours whichever you choose."; link "My partner already invited me" (→ RI-2); button "Continue" (enabled after a choice).
- Storage: `set_my_path(p_path)`; offline → Relationship and Just for me are queued (`PendingPath`) and replayed. **Dating is never queued** (no Dating value on the device, D20): offline, choosing it shows "Dating needs a connection. Try again when you're online." [Try again], and the person can pick another path. Server writes `onboarding_profiles.completed_at` and, first time only, `profiles.relationship_status` (`taken` / `single` / `figuring_it_out` for relationship / dating / just_me).
- Then: Relationship → R1; Dating → Me home (Dating slot); Just for me → Me home.
- Motion: selection 150 ms; Continue → 300 ms step. Accessibility: cards are a radio group ("Choose one of three").

### 3.8 Path R: In a relationship

**R1 · Invite your partner** (`InvitePartnerStep`, W4b copy under `flow_couples_v2`)
- Copy: title "Invite your partner"; body "Send a link. When {name} joins, your private space opens."; field "Their first name (optional)" with helper "Used in your message and on this phone only."; chip group "How should it sound?" — "Simple", "Casual", "Pidgin" (Pidgin only after cultural sign-off, W4 gate); toggle "Add: 'I found this myself. I just thought it'd be nice.'"; preview box titled "What {name} will see".
- Messages (no AI vocabulary; `{name}` omitted with its comma when blank):
  - Simple: "Hi {name}, I'd like us to try Attune together. It's a private space just for the two of us.\nGet the app: {link}\nOpen Attune → I have an invite → {CODE}"
  - Casual: "Hey {name}! I found an app for couples and thought of us. Private, just you and me.\nGet it here: {link}\nOpen Attune → I have an invite → {CODE}"
  - Pidgin (cultural reviewer confirms wording): "{name}, make we try Attune. Na private space for only you and me.\nDownload am: {link}\nOpen Attune → I have an invite → {CODE}"
  - The optional line goes before the link.
- Actions: "Send on WhatsApp" (when installed; opens WhatsApp share with the text, no recipient), "Share another way", "Show QR code", "Copy code"; links "Invite later", "My partner already invited me".
- Storage: `relationships` pending row (7-day TTL, `create-relationship-invite`); `users.path = 'relationship'` already set; the first name in user-scoped prefs `attune.flow.<uid>.partner_first_name`, deleted on linking and by the device wipe registry on sign-out (§5.8).
- Errors: the existing invite errors (cap, already active → resync).

**R2 · Heads-up** (inline row on the sent state): "Get a heads-up when {name} joins" + "Turn on" (the contextual push ask). Shown only while permission isn't granted.

**R3 · Your space while you wait** (`RelationshipSpaceScreen`, Tab 2 on the Relationship path when not linked)
- Pending:
  - The invite card (existing `InviteCard`) with "Send again".
  - `PendingInviteGuide` v2: before 48 h "We'll suggest a private reflection space if this takes a little while."; 48 h–7 d "A private space while you wait" / "Your reflections stay private to you." / "Open your journal"; from 7 d title "It's been a week", body "Your invite to {name} has run its week. What would you like to do?", buttons **"Keep waiting"**, **"Send a new invite"** (withdraws the old code, mints a new one, opens the share step; helper "Send it to the same number or a different one."), **"Use Attune on my own for now"**.
  - Day 30 (from `get_my_invite_age`), once: "Want to send {name} a new invite?" [Send a new invite] [×]. Never again unless asked. Codes are never renewed silently.
  - A first note card ("Write a first note"), "A quiz about you, for you", the About us card (W5), and the line "When {name} joins, read receipts start off. You can both turn them on."
  - A "Cancel this invite" item in the card menu: when the person came from another path (`path_previous` set), it returns them there (`withdraw_my_pending_invites(true)`); otherwise the state becomes *none*.
- None (never invited, "on my own", or cancelled with no previous path): the same space without the invite card; button "Invite {name}" / "Invite your partner". **No Dating entry, ever.** W3b also removes the "Meet someone in Dating mode" button from `chat_couples_locked_screen.dart` (`:379`) **unconditionally**, not behind the flag, so the legacy flag-off screen never shows Dating either (review R-5).
- Paused: `RelationshipLifecycleCard` (existing) + Your space; no invite, no Dating (06 §2.3: paused stays Relationship).
- Ended, within the 30-day window: `RelationshipLifecycleCard` + Your space; no invite, no Dating, no "More ways" row (09 P15).
- After the window: Your space + one "More ways to use Attune" row.

**R4 · Linked**
- Copy: title "You're both here"; body "Your private space with {name} is open."; inline "Get notified when {name} messages you" + "Turn on"; then Chat opens.
- Shown once on each phone (`attune.flow.<uid>.linked_moment.<relationshipId>`), on the next open if the phone wasn't open at link time.
- Storage: `relationships` active; drafts adopted into `couple_profiles` (W5).
- Motion: the Relationship celebration (§2.2); reduce motion → static avatars and text.

**R5 · Later — Ask 2 saves as it goes** (W4b): every answer and anchor is written to user-scoped prefs `attune.ask2.<uid>.<relationshipId>` as it's given; reopening resumes at the first unanswered item; cleared on completion, and by the device wipe registry on sign-out and on quick exit (§5.8). The server write stays at the end (`ask2_submission_service.dart`).

**RI · The invitee**
- **RI-1 · You've been invited** (`/invite`, pre-auth): from an invite link (code stored, scoped, §5.5) or Welcome's "I have an invite". Copy: title "You've been invited to Attune"; body "Someone invited you to a private space on Attune. Create your account to see who it is and to join."; buttons "Create an account" (A1–A5) / "I already have an account" (A3–A4). **No inviter name before the code is verified by sign-in** (10 F-10).
- **RI-2 · Enter your invite code** (when no code is stored): field "Invite code" (6 characters, A–Z and 2–9, case-insensitive, spaces ignored); button "Continue"; error "Codes have 6 letters and numbers. Check it with the person who sent it."
- Android: on first launch the Play Install Referrer (`play_install_referrer` package) is read once; a `invite_code=K7P2QM` referrer is stored like a link. The invite web page (`bars-opus/attune-invite-web`) appends that referrer to its Play link (owner change in that repo). iOS: the code is typed.
- **RI-3 · Join {name}?** (after A5, or after a returning sign-in with a stored code): from `preview_relationship_invite(code)`. Copy: title "Join {name}?"; body "{name} invited you to a private space for the two of you on Attune."; buttons "Join {name}" / "Not now"; link "Not what you expected? Choose another way to use Attune" (→ A6).
- States: expired → RI-4; invalid or used by someone else → "We couldn't find that invite. Check the code with the person who sent it." [Enter the code again]; own invite → "This is your own invite. Send it to your partner instead."; already in a relationship → today's text ("You're already in a relationship on Attune. End it first to join a new one."); age refusal → neutral "We couldn't link these accounts. If you think this is wrong, contact support."; missing DOB (legacy account) → the A2 interstitial, then back.
- **RI-4 · Expired:** "This invite has expired. Ask {name} to send a new one." [Ask {name} on WhatsApp] (opens WhatsApp share with "Hi {name}, my Attune invite expired. Could you send me a new one?", no recipient).
- On "Join": `accept-invite` → R4. The path becomes Relationship on the server; A6 is skipped.

**About us (AU, W5)** — one question per screen, every one skippable, step dots "2 of 5", easiest first; offered during the wait (R3 card) and after linking (Together "Start with" row and Settings → Your relationship → "About us"); never before an invite exists. Before linking, answers go to the inviter's **draft**; on linking they become the shared profile.

| # | Question | Options and fields | Helper / why line | Storage |
|---|---|---|---|---|
| AU1 | "How would you describe where you two are?" | "Dating" · "Engaged" · "Married" · "Something else" (40 characters, "In your own words") · "Skip" | Engaged: "Planning to marry, including after the knocking and before the wedding." Married: "Any kind of marriage: customary, religious or civil." Why: "So what Attune suggests fits you two. Either of you can change this. It's never used to score or type you." **Wording confirmed by the cultural reviewer (W5 gate).** | `stage`, `stage_words` |
| AU2 | "When did you two get together?" | Month + year; "Add the day" (optional); "Not sure of the month" (year only); a chip slot for suggested dates, fed only by the client provider `aboutUsDateSuggestionsProvider(relationshipId)` (returns `[]` here; Spec 2 W9 overrides it from `get_dating_link_origin` with "The day you matched: {date}"; never pre-filled). The server profile carries no suggestions (review I-12). | "Use whichever date feels right to you both." Why: "So we can remember your anniversary with you, if you'd like." | `together_since`, `together_since_precision` |
| AU3 | "What year did you marry?" (only when Married) | Year; optional month and day; optional label chips "Customary", "Church", "Mosque", "Civil", "Other"; "Had more than one ceremony? Add another" (at most 2) | — | `ceremonies` |
| AU4 | "Where do you two live?" | "Together" · "Apart, nearby" · "Long distance" | Why: "So plans, maps and reminders fit how you live." No option ranks above another. | `living` |
| AU5 | "Are there children in your life together?" | "No" · "Yes" · "We're expecting" · "Prefer not to say"; if Yes, "Their ages (optional)": "Under 2", "2–5", "6–12", "13–17", "18+" | Why: "So ideas and reminders suit your family." No names, counts, "yet" or follow-ups by date. | `children`, `child_age_bands` |
| AU6 | "Remember your anniversary?" | "No, thanks" · "The day you got together" · "{Label} ceremony, {year}" for each ceremony | When the chosen date has no day: "What day was it?" (day + month). **The single source** for Together's anniversary reminder. | `anniversary_source`, linked `reminders` row |

- **About us screen** (`/about-us/:relationshipId`): title `coupleLabel(name)`, falling back to "About us"; one row per answer ("Together since" → "October 2024"; "Where you are" → "Married"; "Ceremonies" → one line each, "Customary, 1999"; "Where you live" → "Apart, nearby"; "Children" → "Yes (13–17, 18+)"; "Anniversary" → "The day you got together" or "Off"); under each answered row **"Changed by {first name or 'you'} - {date}"** (`MyDateFormat.toDateShort` this year, `toDate` otherwise). Footer: "Either of you can change these. It's never used to score or type you." No push, no feed, no history list.
- "Together since" is **never rendered as an elapsed counter** anywhere.
- Validation: no future dates ("That date is in the future."); ceremonies only when Married (switching away clears them, attributed); at most 2; bands only with "Yes".
- Read-only while paused or in the ending window ("You can read this until {window end}."); gone after archive.
- Errors: offline edits queue and replay (last write wins, attributed at replay); a refused write → "We couldn't save that. Try again."

### 3.9 Path D: Single and open to dating (entry only)

Spec 2 builds D0–D13. Spec 1 W3b provides the **Dating slot** at the top of Me (Dating path only), replaced in S2 W3 by Spec 2's `DatingSection` (`get_dating_home()`). **The slot calls no Dating RPC** (review I-4): it reads only `get_my_home_state()` (its `path`, `link` and `dating {enabled, enrolled}` summary, §4.3) and the D15 open-country list, so it keeps working when Spec 2 W2 drops `get_dating_eligibility()` before S2 W3 replaces the slot.
- Dating open in the person's country (`config.dating_open_countries` contains it and `dating.enabled` is true): title "Dating"; body "Up to 3 introductions a day. A match only when you both say yes."; buttons "Set up Dating" (today's `/dating-mode` route until S2 W3 replaces it) and "Not ready? Use Attune just for me" (one-tap switch).
- Not open: title "Dating isn't open in {country} yet"; body "Dating is open in {open countries}. We're adding countries one at a time."; link "Not in {country}? Change" (country picker, device-only, stored under the neutral key `attune.flow.<uid>.country_override`). No "Tell me when it's here" here: Spec 2 W3 adds it with its server row.
- Gentle wait (relationship ended inside Attune, window open): "Dating opens for you on {MyDateFormat.toDate(window end)}." + "This pause is because your relationship ended here. It isn't a judgement about you." + "Healing is here if you want it". Spec 2 W2 adds the reflection.
- **Dating lock** (Q6; owned here, enforced on Dating routes by S2 W3): Settings → Safety → "Dating lock" (shown when the path is Dating or `get_my_home_state().dating.enrolled` is true; the client never reads `dating_enrollments` itself, review A-10): "Ask for your Safety PIN before showing Dating." Turning it on with no Safety PIN opens the existing PIN setup first. Storage: the neutral key `me_section_lock` in the safety secure store (device only, backup-excluded; no "dating" in the key or value, D20); the code file stays `lib/features/safety/data/dating_lock_store.dart`. While on, the slot shows one row "Dating is locked" → PIN sheet → slot. **It is a protective setting:** quick exit never clears it; only sign-out does (D19, §5.8).

### 3.10 Path J: Just for me — the Me home (`MeHomeScreen`, Tab 2 on Dating and Just for me)

- Header "Your space".
- **J1 first-action card** (until the first note or first quiz): "Start here" · "Write your first note" / "Take a 3-minute look at how you connect" (the optional Track A quiz, with the existing self-facing caveat). After the first note: "Saved, just for you." (the Just-for-me celebration).
- Rows: "Journal" · "Notes only you can read"; "Quizzes" · "Short, private, about you"; "Healing" · **"After a breakup or a loss"** (W3 copy; W7 adds the choice "A breakup" → Healing / "Someone I love died" → grief support + "Write about it in your journal"); **J3** "Remind me to write" · "Off" or "{weekday}s at {MyDateFormat.toTime}".
- **J3 sheet:** "When should we remind you?" weekday chips Mon–Sun, a time picker, "Turn on"; if notifications are off: "Reminders need notifications." + "Turn on notifications" (the contextual ask). Push text, neutral for checked phones: title "Attune", body "A few quiet minutes for you, if you'd like." Storage: `journal_reminder_settings` (§4.2). The journal manual line "no reminders nagging you" becomes "No reminders unless you set one."
- **J4 "More ways to use Attune"** (one neutral row, 09 P19): a sheet with "Invite a partner" · "A private space for you and your partner." and "Single and open to dating" · "A few introductions a day. Only when it's mutual." (on the Dating path: "Invite a partner" and "Just for me"). Replaces the two rows "Invite a partner" / "Turn on Dating".
- J5 "Attune asks" is deferred with Q9.

### 3.11 Each path's home

| Who | Tab 1 | Tab 2 (default after sign-in) | Built from |
|---|---|---|---|
| Guest | **Opinions** (default) | "Sign in" → `LoginProfile` (new copy) | unchanged shell; G1 first |
| Relationship, linked | Opinions | **Chat** → `ChatHomeScreen` (Plans card first) | `AuthenticatedChatWorkspace(isCouples: true)` (unchanged) |
| Relationship, pending / none / paused / ended window / after | Opinions | **Chat** → `RelationshipSpaceScreen` (R3 states) | new screen; never Dating |
| Dating | Opinions | **Me** → Dating slot, then Your space | new `MeHomeScreen` |
| Just for me | Opinions | **Me** → Your space | new `MeHomeScreen` |

- Tab 2 label "Chat" or "Me" (icons `chat_bubble_outline` / `person_outline`). "Dating" never appears on the tab bar.
- `HomeScreen` takes the **tab layout** (`chat` or `me`) from `HomeState`; `HomeWidget` applies `initialTabIndex` only in `initState` (`home_widget.dart:56-59`), so the shell is wrapped in `KeyedSubtree(key: ValueKey('home-$tab'))`: a switch between the Relationship path and the other two rebuilds the shell; Dating ↔ Just for me (both Me) and a link change (pending → linked) only swap Tab 2's child. The first frame may use the cached layout; whether Me shows the Dating slot comes only from the server answer (D20).
- `/home?tab=me` and `/home?tab=chat` open Tab 2 (used by Spec 2's `me_update` push and by the journal reminder tap).

### 3.12 Switching paths — Settings → "How you use Attune" (W3c)

Screen: three radio rows with the A6 lines; footer "Your journal, quizzes and Healing stay yours whichever you choose. Nobody is told when you change this." **Every switch is silent to everyone else.**

| From → to | What the person sees | Server |
|---|---|---|
| Just for me → Relationship | R1 (path set when the invite is sent) | `set_my_path('relationship')`, `path_previous = 'just_me'` |
| Dating → Relationship | Sheet "Inviting a partner pauses Dating" / "Your introductions stop and your Dating profile is hidden. Nobody is told." [Continue] [Cancel] → R1 | `set_my_path('relationship', p_confirmed => true)` pauses Dating through `pause_dating_for_relationship_user` (the only pause Spec 1 makes, D18) |
| Dating → Just for me | Sheet "Use Attune just for you?" / "Dating will be paused and hidden. Nobody is told. You can delete your Dating profile from Dating settings." [Switch] [Cancel] | `set_my_path('just_me')`; Spec 2 W2's path trigger pauses Dating with `pause_reason = 'path_change'` (D18); Exit stays separate (Spec 2 makes it a hard delete) |
| Just for me → Dating | Me with the Dating slot | `set_my_path('dating')` |
| Relationship (pending) → other | Sheet "Cancel your invite?" / "Your invite code will stop working. {name} won't be told." [Cancel invite and switch] [Keep invite] | withdraws pending invites in the same call |
| Relationship (linked or paused) → other | Screen "You're in a shared space with {name}. To use Attune another way, end it first. Pausing keeps it, read-only, for up to 30 days." [Pause our shared space] [End relationship] [Not now] (the existing Spec 3a actions) | refused with `path:relationship_open` |
| Relationship (ended, window open) → Dating | the gentle-wait line (§3.9) | allowed; Spec 2 enforces the wait |
| Relationship (ended, window open) → Just for me | Me, with the lifecycle card on top until the window closes | allowed |
| A wrong first choice | Dating slot "Not ready? Use Attune just for me" | one-tap `set_my_path('just_me')` |

### 3.13 Ending → gentle wait → Spec 2

1. End (Spec 3a, unchanged): no push to the other partner; both see the ending card, a 30-day read-only window and an export; the former-partner exclusion is written both ways.
2. During the window the Relationship home shows only the lifecycle card and Your space: **no Dating prompt, no invite, no "More ways" row**. Dating stays reachable only through Settings → How you use Attune.
3. Choosing Dating early shows "Dating opens for you on {window end}." (§3.9); Spec 2 W2 adds the reflection and Healing offer and enforces `dating_gentle_wait_opens_at`.
4. No wait for endings outside Attune.

### 3.14 Offline and low data

| Need | Decision |
|---|---|
| A bad network never traps anyone | A1–A3 kept on the device; `complete_sign_up`, `set_my_path` and About-us edits queue and replay through `OnboardingSyncService` (idempotent RPCs). `accept-invite` and Dating wait for the DOB to be on the server. |
| The first frame never waits on the network | W10 measures an airplane-mode cold start with an expired session. If the first frame comes more than 1 s after the splash, `main.dart` bounds `Supabase.initialize` at 2 s before `runApp`, continues, and the auth listener reconciles; every direct `Supabase.instance.client` read on the first-frame path is audited first. |
| App size | W10 measures the release AAB/IPA; Spec 1 may add at most 1.5 MB download size (native age-signal and SIM channels, `smart_auth`, `play_install_referrer`, three WebP previews). Play ships the AAB (per-ABI splits); direct APKs use `--split-per-abi`. Mapbox can't be deferred (Flutter deferred components don't cover native plugin code), so it isn't attempted. |
| Onboarding network budget | OTP plus three small writes; no remote media; previews bundled. |
| Journal | Verified to save offline and sync later (journal notes' outbox); a test proves it. |
| Pushes that never arrive | Nothing in Spec 1 depends on a push: link state, home state and reminders self-heal on open. |

### 3.15 Legacy accounts, holds and interstitials

`get_my_home_state().needs` lists what an account lacks, in order: `consent` (EULA < 2), `birth_date`, `name` (display name empty), `path`. The existing redirect latch sends the person to `/onboarding`, and `OnboardingGate` shows only the missing steps:
- **A5c** "We've updated our terms" + the three A5 bullets → `record_eula_acceptance('2')`.
- **A2** "Add your date of birth" (same screen) → `set_my_birth_date`; under 18 → H1.
- **A1**, **A6** as above.

**H1 · Account check** (any hold, or `account_review` from the hook): title "We need to check your account"; body "You can't use Attune while we do this. If you think this is a mistake, contact support."; buttons "Contact support" / "Sign out". No reason is shown. No motion. **When it appears (review F-2):** when the hook refuses a background token refresh, `supabase_flutter` signs the device out without showing the hook's message, so the person lands on sign-in; H1 appears when they next sign in by code and the verify returns `account_review`. A hold read from `get_my_home_state().hold` while a session is still valid also opens H1.

**Settings → Date of birth** (W6b): "Your age: {age}" (never the date); "Fix a mistake" once, within 7 days of sign-up and only while Dating isn't active → the A2 screen → `correct_my_birth_date`. Otherwise: "To change this, contact support."

**Settings → Safety → "Report a concern about a child"** (W6c; also linked from the Support screen): title "Report a concern about a child"; body "Tell us what you saw and where. A person on our team reads every report. If a child is in danger right now, call {emergency number}."; chips "Where did you see it?" (Chat, Stories, Opinions, Dating, Somewhere else); text field (up to 2,000 characters); button "Send report"; confirmation "Thank you. We've received your report." The reported person is never told.

---

## 4. Data model

### 4.1 Principles (11 §3.1, applied)

1. New per-user tables: RLS on, `REVOKE ALL … FROM PUBLIC, anon, authenticated`, then the narrowest grant; writes only through `SECURITY DEFINER SET search_path = ''` functions that take the actor from `auth.uid()` and qualify every name.
2. Every migration that creates objects has a paired `…10_grants.sql` migration (repo pattern); every table-level `REVOKE` is also replayed by `scripts/local_pg_table_privileges.py`, and a column-level grant gets an explicit line in `scripts/local_pg_grants.sql` so the harness can't silently re-grant it.
3. Nothing new on `profiles` (public) or `relationships` (column-locked).
4. No analytics SDK; aggregates only (`metric_counters`), shown at n ≥ 50, never with answers, gender, preference, faith or age signals.
5. Edge functions log categories and HMACs only, never phone numbers, codes, names or content.

### 4.2 Tables

**`public.users` (changed, W1)**
- Add `path text NULL CHECK (path IN ('relationship','dating','just_me'))`, `path_previous text NULL CHECK (same)`, `path_chosen_at timestamptz NULL`, `phone_released_at timestamptz NULL` (set when the account is parked for a fresh start). All four are added by W1a's lockdown migration; their writers arrive in W1b and W6a.
- Add `parked_phone_hmac text NULL` (W6a, review I-11): the HMAC of the account's **real** number, written by `consume_fresh_start` just before the number is replaced by a `+999…` placeholder. It uses the existing `public.dating_phone_hmac(text)` (key `app.settings.dating_exclusion_key`) over the canonical form `'+' || digits`, so it equals what Spec 2's `dating_phone_hmac_for_user` would have computed from `auth.users.phone`. Spec 2's helper **prefers this column for a parked account**, so enforcement records and block pairs written at the 180-day purge carry the real number's HMAC. NULL when the key isn't configured (the identity health counts it). Not granted to clients; deleted with the row.
- `CHECK (char_length(display_name) <= 40) NOT VALID` (new writes only).
- `mode`: `COMMENT 'Retired (Spec 1 W1). Not written by the app, edge functions or SQL functions; not granted to clients. Kept so SQL fixtures still insert it.'` Default and CHECK kept. The column is not dropped by any wave of this spec (controller ruling).
- Grants (`…_grants.sql`): `REVOKE INSERT, UPDATE ON public.users FROM authenticated; GRANT UPDATE (display_name, avatar_url, timezone) ON public.users TO authenticated;` SELECT unchanged (own-row RLS). The policy "users insert own profile" stays; it is inert without an INSERT grant. `timezone` stays granted: `set_my_timezone` is the app's path and `user_timezone_contracts.sql:133` tests a direct client write that readers must reject.
- `phone` is written only by `complete_sign_up` / `record_eula_acceptance` (from `auth.users`), the invite functions' `ensureUserRow` (from the verified JWT), and the sync trigger (§4.4).

**`public.profiles` (changed, W1a)** — no column change. Trigger `profiles_guard_moderation_columns` (§4.4) stops clients setting or changing `banned_until` **or `confirmed_violation_count`** (review S-1), forces both to their defaults on a client INSERT, and refuses a client DELETE of a profile that has strikes or a future ban.

**`public.onboarding_profiles` (changed, W1b)** — `DROP COLUMN mode` (no SQL reader; no fixture uses it). The legacy client upsert writes it today (`onboarding_submission_service.dart:68`), so the same W1b release removes `mode` from that upsert, and the drop runs only once that client is the one in use (no real users on the development project, Q19b). `completed_at` is written by `set_my_path` (first path); `attachment_answers`, `anchors` keep defaults `'[]'`. Direct own-row grants unchanged (the optional quiz and Ask 2 still write).

**`public.account_birthdates` (new, W1b)**

| Column | Type | Notes |
|---|---|---|
| `user_id` | uuid PK → `public.users(id) ON DELETE CASCADE` | |
| `birth_date` | date NOT NULL CHECK (`birth_date >= '1900-01-01'`) | never displayed; only an age is shown |
| `source` | text NOT NULL DEFAULT `'self_declared'` CHECK IN (`self_declared`, `support_corrected`) | a declaration, never assurance (Spec 2 keeps assurance elsewhere) |
| `declared_at` | timestamptz NOT NULL DEFAULT now() | |
| `corrected_at` | timestamptz NULL | |
| `self_corrections` | smallint NOT NULL DEFAULT 0 CHECK (`self_corrections <= 1`) | |

RLS on; no policies; no grants to `anon`/`authenticated`.

**`public.account_holds` (new, W1b; enforced by the W6a hook)** — `user_id uuid → public.users ON DELETE CASCADE`, `kind text CHECK IN ('age_review','recovery_hold','safety_review')`, `reason_ref text NULL`, `created_at`, `expires_at timestamptz NULL` (recovery: +180 days), `resolved_at`, `resolved_by text`; PK (`user_id`, `kind`). No grants. Created in W1b because `set_my_birth_date` and `get_my_home_state` (W1b) use it; the access-token hook that closes the whole app for a held account lands in W6a. Spec 2 opens holds through `place_account_hold` (e.g. a confirmed minor, a CSAM hit on a dating photo); Spec 2 cites this under "S1 W6", which still holds because W6a is where holds start to bite.

**`public.metric_counters` (new, W1b)** — `day date`, `key text CHECK (key ~ '^[a-z0-9_:>.-]{1,80}$')`, `count bigint NOT NULL DEFAULT 0`, PK (`day`, `key`). **`public.metric_key_prefixes`** — `prefix text PK`, `owner_spec text`: prefixes that **server-side** callers may bump (definer functions and service-role edge functions). **`public.metric_client_keys`** (review S-2) — `key text PK` (same pattern), `anon_ok boolean NOT NULL DEFAULT false`, `owner_spec text`: the **exact** keys a client may bump, seeded with Spec 1's list (§4.3 `bump_metric`); Spec 2 inserts its own prefix and its own exact client keys. All three: RLS on, no client grants. View `public.metric_counters_report` (service role only) blanks any cell under 50. **Daily row cap:** at most 5,000 distinct keys per UTC day; past the cap a new key isn't created and the exempt row `metric_cap_reached` is incremented instead (existing keys keep counting).

**`public.app_public_config` (new, W1c)** — `key text PK CHECK (key IN ('age_signal_storefronts','dating_open_countries'))`, `value jsonb NOT NULL`, `updated_at`. Seeds: `age_signal_storefronts = ["USA","BRA"]`, `dating_open_countries = ["GH","GB"]`. Service-role writes only; read through `get_public_app_config()`; the `dating_open_countries` row is read only through the seam `private.dating_open_countries()` (D15). Spec 2 W1 re-creates the seam over `country_safety_config`, then deletes the row.

**`private.flag_production_gates` (new, W1c)** — §2.5. No grants.

**`private.otp_delivery_intents` (new, W2c)** — `phone_hmac text`, `channel text CHECK IN ('sms','whatsapp','voice')`, `platform text CHECK IN ('ios','android','other')`, `locale text`, `device_hash text NOT NULL` (SHA-256 of the client's `device_nonce`, review S-3), `created_at timestamptz`, PK (`phone_hmac`, `created_at`). TTL 10 minutes. An intent is **usable** by the hook for 60 seconds only.
**`private.otp_send_events` (new, W2c)** — `id bigserial`, `phone_hmac`, `channel`, `route text`, `country_code char(2)`, `created_at`. Used for rate limits; TTL 24 hours.
**`private.otp_routes` (new, W2c)** — `country_code char(2)` (`'*'` = default), `channel`, `provider text`, `priority smallint`, `enabled bool`; PK (`country_code`, `channel`, `provider`).
**`private.otp_destination_rules` (new, W2c)** — `calling_code_prefix text PK`, `rule text CHECK IN ('allow','block')`, `max_sends_per_hour int`. Seeds block `+999` (parked numbers, §4.5) and known premium-rate prefixes from the provider's fraud list; launch countries GH, GB, US, CA, NG, KE get explicit allow rows with hourly caps; every other prefix uses the default cap.
All four: no grants; reached only through service-role functions.

**`public.journal_reminder_settings` (new, W3c)** — `user_id uuid PK → public.users ON DELETE CASCADE`, `enabled bool NOT NULL`, `iso_weekday smallint CHECK (1..7)`, `local_time time`, `last_enqueued_for date`, `updated_at`. RLS: SELECT own (`user_id = auth.uid()`); writes through `set_my_journal_reminder`. Grants: SELECT to `authenticated`.

**`private.invite_preview_attempts` (new, W4a)** — `user_id`, `attempted_at`; index (`user_id`, `attempted_at`). TTL 1 day, through its own retention cron (§4.6).

**`public.couple_profiles` (new, W5)**

| Column | Type / values | Notes |
|---|---|---|
| `relationship_id` | uuid PK → `relationships(id) ON DELETE CASCADE` | lives and dies with the relationship (purge per Spec 3b) |
| `together_since` | date NULL | stored normalised (month → day 1, year → 1 Jan); never an elapsed counter |
| `together_since_precision` | text NULL CHECK IN (`day`,`month`,`year`); NOT NULL when `together_since` is set | |
| `stage` | text NULL CHECK IN (`dating`,`engaged`,`married`,`other`) | |
| `stage_words` | text NULL CHECK (`char_length <= 40`), only when `stage = 'other'` | the couple's own words |
| `ceremonies` | jsonb NOT NULL DEFAULT `'[]'` CHECK (array, length ≤ 2) | `[{year int, month int?, day int?, label?}]`, label IN (`customary`,`church`,`mosque`,`civil`,`other`); non-empty only when `stage = 'married'` |
| `living` | text NULL CHECK IN (`together`,`apart_nearby`,`long_distance`) | `distance_ends_on` stays in Plans/Map |
| `children` | text NULL CHECK IN (`none`,`yes`,`expecting`,`prefer_not_to_say`) | |
| `child_age_bands` | text[] NOT NULL DEFAULT `'{}'` CHECK (`<@ ARRAY['under2','2to5','6to12','13to17','18plus']`) and empty unless `children = 'yes'` | no names, counts or whose child |
| `anniversary_source` | text NOT NULL DEFAULT `'off'` CHECK IN (`off`,`together_since`,`ceremony_1`,`ceremony_2`) | |
| `anniversary_reminder_id` | uuid NULL → `reminders(id) ON DELETE SET NULL` | the one materialised reminder |
| `{together_since, stage, ceremonies, living, children, anniversary}_changed_by` | uuid NULL → `auth.users(id) ON DELETE SET NULL` | six attribution pairs |
| `{…}_changed_at` | timestamptz NULL | |
| `updated_at` | timestamptz NOT NULL DEFAULT now() | |

RLS: SELECT `USING (public.relationship_chat_open(relationship_id))` (active, paused, or ended inside the window; not sealed; not archived). No write policies. Grants: SELECT to `authenticated`. Not in the Realtime publication (the change signal is).

**`public.couple_profile_drafts` (new, W5)** — `user_id uuid PK → public.users ON DELETE CASCADE`; the same answer columns (no attribution); `{field}_set_at timestamptz` per field (for merging); `updated_at`. RLS: SELECT own. Grants: SELECT to `authenticated`. Deleted when moved into `couple_profiles`, when the owner's path becomes Dating (by `set_user_path_internal` as re-created in W5, review I-6), and with the account.

**`public.account_activity` (new, W6a)** — `user_id uuid PK → public.users ON DELETE CASCADE`, `last_active_at timestamptz NOT NULL`. No grants.
**`public.fresh_start_challenges` (new, W6a)** — `nonce_hash text PK` (SHA-256 of a 32-byte random nonce), `user_id uuid → public.users ON DELETE CASCADE`, `created_at`, `used_at`. Usable for 15 minutes; rows deleted after 1 hour by their own retention cron (§4.6); no grants.
**`private.auth_hook_failures` (new, W6a, review S-8)** — `id bigserial`, `at timestamptz`, `sqlstate text`, `alerted_at timestamptz NULL`. One row per fail-open in the access-token hook (no user id, no claims). No grants; kept 30 days.
**`public.child_safety_reports` (new, W6c)** — `id uuid PK`, `reporter_user_id uuid NULL → auth.users ON DELETE SET NULL`, `where_seen text NULL CHECK IN ('chat','stories','opinions','dating','other')`, `details text NOT NULL CHECK (char_length BETWEEN 1 AND 2000)`, `status text NOT NULL DEFAULT 'new' CHECK IN ('new','reviewing','actioned','closed')`, `created_at`, `reviewed_at`. No client grants.

**`public.support_resources` (new, W7a)** — `id uuid PK`, `country_code text NOT NULL CHECK (country_code ~ '^([A-Z]{2}|XX)$')` (`XX` = international), `category text NOT NULL CHECK IN ('emergency','dv','crisis','sexual_assault','sextortion','child_safety','youth','lgbtq_legal','grief','perinatal','addiction','financial_control')`, `name`, `description`, `phone`, `sms`, `whatsapp`, `url`, `hours`, `languages text[]`, `is_police bool NOT NULL DEFAULT false`, `sort_order int`, `verified_at date NOT NULL`, `verified_by text NOT NULL`, `catalogue_version text NOT NULL`, `active bool NOT NULL DEFAULT true`. RLS on; read only through `get_support_resources`. Loaded by `scripts/load_support_resources.sh` (service role) from `assets/support_resources/catalogue.json`, the same file the app bundles for offline.

**`private.media_scan_queue` (new, W7b)** — `id bigserial PK`, `bucket text`, `object_name text`, `owner_user_id uuid NULL`, `mime text`, `source text NOT NULL DEFAULT 'queue' CHECK IN ('queue','inline')` (`inline` = a match recorded by a synchronous pipeline, review I-10), `status text CHECK IN ('pending','scanning','clear','match','failed')`, `attempts int`, `next_attempt_at`, `enqueued_at`, `scanned_at`, `vendor text`, `vendor_ref text`; UNIQUE (`bucket`, `object_name`).
**`public.safety_escalations` (new, W7b)** — `id`, `kind CHECK IN ('csam_match','scan_failed')`, `user_id uuid NULL`, `bucket`, `object_name`, `status CHECK IN ('open','reported','closed')`, `created_at`, `notes`. Service role only.
**Storage bucket `safety-quarantine` (new, W7b)** — private, no `storage.objects` policies (service role only).

**`private.content_filter_terms` (new, W9a)** — `id`, `family CHECK IN ('slur','explicit')`, `term text` (stored in the **match form** of the shared normaliser, §4.3 W9a, so one spelling per term covers Twi written with or without ɛ/ɔ), `match_mode CHECK IN ('token','squashed')`, `locale text`, `source CHECK IN ('draft','reviewed')`, `review_ref text NULL`, `active bool`, `created_at`. No grants. Loaded by the operator script `supabase/sql/load_content_filter_terms.sql` (development: a small `[DRAFT]` English list; production: the reviewed lists, W9 gate).

**`public.forum_reports` (unchanged table, W9b behaviour)** — the new reason `'Someone may be at risk'` is valid and priority; status values unchanged.

### 4.3 Functions (all `SECURITY DEFINER SET search_path = ''`; grants listed; errors are `RAISE EXCEPTION '<domain>:<code>'`)

**Rule for every wave (reviews I-1, I-6):** a function never names a table, column or function that a later wave creates. When a later wave needs a function to do more, that wave re-creates it **from its live body** (found at build time with `grep -l` over `supabase/migrations`, or `pg_get_functiondef` on the scratch database), adding only its own lines.

**W1a — users and profiles lockdown**

| Function | Grants | Behaviour |
|---|---|---|
| `verified_phone(p_user uuid) → text` | none | `auth.users.phone` (Spec 2 builds its HMAC helper on the same source). |
| `private.guard_profile_moderation_columns()` (trigger function) | none | §4.4 `profiles_guard_moderation_columns`. |
| `pause_dating_for_relationship_user`, `activate_dating_profile`, `pause_dating_mode`, `exit_dating_mode`, `delete_dating_profile` | unchanged | Each re-created verbatim from its latest body minus its `UPDATE public.users SET mode` statement (D3). |

**W1b — metric storage, birthdates, holds, paths, home state**

| Function | Grants | Behaviour |
|---|---|---|
| `private.bump_metric_internal(p_key text) → void` | none | For definer callers. The key must match the `metric_counters` pattern and start with a `metric_key_prefixes` prefix; otherwise nothing happens. Increments today's (UTC) row, applying the daily row cap (§4.2). Runs in its own exception block, so a metric never fails its caller. |
| `bump_metric_server(p_key text) → void` | service_role | The same, for edge functions (`send-sms-hook`, `analyse-journal-entry`, `scan-media`, the hook alert). |
| `bump_metric(p_key text) → void` | anon, authenticated | **Exact keys only (review S-2):** the key must have a `metric_client_keys` row, and an anonymous caller (`auth.uid()` NULL) may bump only rows with `anon_ok`. Anything else is ignored silently (no error, no row). Then the internal bump, cap included. Client-reported counts are advisory: no gate, threshold or decision reads them. Server events are never in `metric_client_keys`, so no client can inflate them. |
| `complete_sign_up(p_display_name text, p_birth_date date, p_eula_version text) → jsonb` | authenticated | Requires `auth.users.phone` and `phone_confirmed_at` (`signup:phone_required`). Validates the name (1–40 after trim; at least one character outside space, punctuation and digits) and the date (≥ 1900, not future). Age < 18 → `signup:not_eligible` and **nothing is written**. Inserts `users` (phone from `auth.users`, EULA version and time), `profiles(id, display_name)` (`ON CONFLICT` only fills an empty name), `account_birthdates` (`ON CONFLICT DO NOTHING`, never overwrites). Idempotent: a replay returns `{age, created:false}`. Bumps `signup_completed` (internal). |
| `set_my_birth_date(p_birth_date date) → jsonb` | authenticated | Legacy accounts only. Second set → `birth_date:already_set`. Under 18 → places an `age_review` hold and returns `{status:'not_eligible'}` (no exception, so the hold commits). Otherwise `{status:'ok', age}`. |
| `get_my_age() → int` | authenticated | NULL when unset. |
| `account_age(p_user uuid) → int` | none (revoked from PUBLIC, anon, authenticated) | For definer callers (accept, Spec 2). |
| `place_account_hold(p_user uuid, p_kind text, p_ref text DEFAULT NULL) → void` | none (definer callers; Spec 2) | Upsert an active hold. `p_ref` defaults to NULL so Spec 2's two-argument call `place_account_hold(user, 'age_review')` works (review I-7). |
| `private.spec1_flag_on(p_key text) → boolean` | none | The **effective** flag (§2.5 dependencies); a missing row is off. Created here because `set_my_path` reads it; W1c inserts the rows. |
| `private.dating_home_summary(p_user uuid) → jsonb` | none | `{enabled, enrolled}`: `enabled` = today's `public.dating_flag_enabled('dating_mode_enabled')`; `enrolled` = a `dating_enrollments` row in `profile_draft`, `active`, `paused` or `suspended`. **A seam Spec 2 re-creates** when it changes its flags or tables; no client reads Dating tables for this (reviews I-4, A-10). |
| `set_user_path_internal(p_user uuid, p_path text) → void` | none | The single path writer: validates the value, sets `path_previous` (when the path changes), `path`, `path_chosen_at`; first time also upserts `onboarding_profiles.completed_at` and `profiles.relationship_status`; **when the new path is `relationship` and the person has an active Dating enrollment, calls `pause_dating_for_relationship_user(p_user)`** (the only pause Spec 1 makes; any other change away from Dating is paused by Spec 2 W2's path trigger, D18); bumps `path_chosen:{path}` or `path_switch_7d:{from}>{to}` / `path_switch_30d:{from}>{to}` by elapsed time (internal). **Names no W5 table** (review I-6): W5 re-creates it from its live body to also delete the person's `couple_profile_drafts` row on a switch to Dating. Spec 2 W9 calls it for a Dating → couple link. |
| `set_my_path(p_path text, p_confirmed boolean DEFAULT false) → jsonb` | authenticated | Needs a `users` row, a DOB with age ≥ 18 and, when `flow_signin_v2` is effectively on, EULA `'2'` (`path:needs_signup`). Active or paused relationship and `p_path <> 'relationship'` → `path:relationship_open`. Own pending invites and `p_path <> 'relationship'`: unconfirmed → `path:confirm_withdraw`; confirmed → withdraws them. Dating active and `p_path = 'relationship'`: unconfirmed → `path:confirm_pause_dating`. Then `set_user_path_internal`; returns `get_my_home_state()`. |
| `get_my_home_state() → jsonb` | authenticated | `{path, tab, path_previous, needs:[…], hold, eula_version, dating:{enabled, enrolled}, link:{state, relationship_id, partner_first_name, invite_expires_at, window_ends_at}}`. `tab` = `chat` on the Relationship path, otherwise `me` (the only path-derived value a client caches, D20). `hold` = any unresolved `account_holds` row. `dating` from `private.dating_home_summary`. `link.state` from the latest relationship: own pending invite → `pending`; `active` → `linked`; `paused` → `paused`; `ended` with `relationship_chat_open` → `ended_window`; ended later or archived → `after_ending`; none → `none`. `partner_first_name` uses the lifecycle RPC's guard against a phone stored as a name. |
| `withdraw_my_pending_invites(p_return_to_previous_path boolean DEFAULT false) → int` | authenticated | Replaces the no-argument version (`DROP FUNCTION` then `CREATE`; the client's no-argument call resolves to the default). Deletes the caller's pending, unaccepted invites; with `true` and `path_previous` set, restores it. |

Seeds (W1b). **Server prefixes** (`metric_key_prefixes`, owner Spec 1): `signup_completed`, `path_chosen:`, `path_switch_7d:`, `path_switch_30d:`, `invite_accepted`, `otp_sent:`, `otp_refused:`, `dormancy_`, `support_card_shown:journal`, `auth_hook_fail_open`. **Client keys** (`metric_client_keys`, exact; `anon_ok` = true only for the pre-auth funnel): pre-auth `welcome_preview:relationship`, `welcome_preview:dating`, `welcome_preview:just_me`, `guest_age_ok`, `signup_started`, `signup_step:name`, `signup_step:dob`, `signup_step:phone`, `signup_age_stop`; signed-in only `push_ask_shown:{r2|r4|j3}`, `push_ask_granted:{r2|r4|j3}` (six rows), `invite_shared:{whatsapp|share|qr|copy}` (four rows), `invite_new_day7`, `invite_day30_shown`, `opinion_blocked:{contact_info|slur|explicit}` (three rows; the writer's error rolls back any server bump, so the client counts it), `support_link_opened:{opinions|journal}` (two rows). Platform age signals are never counted (Play Age Signals' terms forbid analytics use). Spec 2 registers the prefix `dating.` for its server events and lists its own exact client keys.

**W1c — environment, flags, public config, identity health**

| Function | Grants | Behaviour |
|---|---|---|
| `private.attune_environment() → text` | none | §2.5: `'development'` when `app.settings.attune_environment` is unset or empty; `'production'` for `production` and for any unrecognised value. |
| `get_attune_environment() → text` | service_role | The same, for edge functions. |
| `private.assert_development_project() → void` | none (the dev scripts run as `postgres`) | The dev-script guard (§2.5): `env:not_development` unless the environment reads `development` and, when `app.settings.supabase_url` is set, it contains the development project ref `mrgjtyacrzfylawyzabm`. |
| `private.guard_flag_production_gate()` (trigger function on `public.feature_flags`) | none | §2.5 production flag gate; `flag:gate_evidence_required`. |
| `record_flag_gate_evidence(p_flag text, p_review_ref text) → void` | service_role | Owner-only in practice (SQL editor); sets `review_ref`, `recorded_by = current_user`, `recorded_at`. |
| `production_flag_violations() → setof text` | service_role | Gated flags that are on without evidence (run right after the environment flip). |
| `private.dating_open_countries() → text[]` | none | The D15 seam. W1c reads `app_public_config.dating_open_countries`; **Spec 2 W1 re-creates it** over `country_safety_config` (same shape: ISO alpha-2 codes, sorted). |
| `get_public_app_config() → jsonb` | anon, authenticated | `{flags:{flow_signin_v2, platform_age_signals, support_resources_v2, text_scale_v2}, config:{age_signal_storefronts, dating_open_countries}}`, flags as effective values, `dating_open_countries` from the seam. Nothing else. |
| `get_identity_health() → jsonb` | service_role | Counts: accounts without DOB, without path, with each hold kind; unfinished sign-ups awaiting purge. W6a re-creates it from its live body to add dormancy challenges in 7 days, parked accounts (and those without a `parked_phone_hmac`), and hook fail-opens. |
| `unfinished_signup_candidates() → setof uuid` | service_role | `auth.users` without a `public.users` row, created more than 24 h ago. |

**W2c — phone codes**

The intent is a **request to change the channel away from SMS, never a requirement** (review S-3). The Send SMS Hook only sees the phone, not the device that asked, so an intent can't be matched to the requester directly. Instead, an intent is honoured only when it is fresh, within the per-number cap, and unopposed; anything doubtful is sent by SMS, the one channel a person with the SIM can always receive. Someone who knows a number can therefore at most force an SMS, never move another person's code to WhatsApp or voice.

| Function | Grants | Behaviour |
|---|---|---|
| `otp_record_intent(p_phone_hmac text, p_channel text, p_platform text, p_locale text, p_device_hash text) → jsonb` | service_role | Called by `otp-delivery-intent` (per-IP limit there). At most **6 intents per number per hour** across all devices; past the cap the intent isn't stored (`{stored:false}`, and the send falls back to SMS). Stores `device_hash`. |
| `otp_take_send_decision(p_phone_hmac text, p_country char(2), p_calling_prefix text) → jsonb` | service_role | `{allowed, reason, channel, routes:[…], retry_after_s}`: applies the destination rule, per-number limits (6 per hour, 15 per day), the per-prefix hourly cap, then chooses the channel: the newest intent is used **only if** it is under 60 seconds old **and** every intent for that number in the last 10 minutes carries the same `device_hash`; otherwise (none, stale, or two devices) the channel is `sms`. Returns the ordered routes for that channel and SMS routes as fallback. Records the send event; bumps `otp_refused:{reason}` on a refusal (internal). |
| `otp_purge() → void` | cron | Deletes intents older than 10 min and send events older than 24 h. It names only W2c tables; later waves' retention jobs are their own crons (§4.6, review I-1). |

**W3c — Me and reminders**

| Function | Grants | Behaviour |
|---|---|---|
| `set_my_journal_reminder(p_enabled bool, p_iso_weekday smallint, p_local_time time) → void` | authenticated | Upsert own row. |
| `get_my_journal_reminder() → jsonb` | authenticated | Own row. |
| `enqueue_journal_reminders() → int` | cron | For enabled rows whose local weekday and time (zone from `notification_recipient_tz`) fell in the last 15 minutes and `last_enqueued_for` < today: inserts one `scheduled_notifications` row (type `journal_reminder`, neutral title and body, `source_key journal_reminder:{user}:{date}`); quiet hours apply in the worker. |

**W4a — invites**

| Function | Grants | Behaviour |
|---|---|---|
| `accept_relationship_invite_v2(p_acceptor uuid, p_invite_code text) → jsonb` | service_role | One transaction: normalise the code; idempotency through `relationship_invite_acceptances` (SHA-256 via `extensions.digest`); lock the pending row `FOR UPDATE`; refuse own (`invite:own`), expired (`invite:expired`), invalid or taken (`invite:invalid`, `invite:already_accepted`); acceptor in an active or paused relationship (`invite:already_in_relationship`); acceptor without `users` row or verified phone (`invite:phone_required`); when `flow_signin_v2` is effectively on, acceptor without DOB (`invite:age_required`), either side under 18 or inviter without DOB (`invite:not_possible`, neutral). Then **deletes the acceptor's own pending invites**, sets the row `active`, inserts the acceptance, sets the acceptor's path through `set_user_path_internal(…,'relationship')`, bumps `invite_accepted` (and `_24h` / `_7d`; internal). The `relationship:already_open` guard maps to `invite:already_in_relationship`. Returns `{relationship_id, status, idempotent, inviter_id}`. |
| `preview_relationship_invite(p_code text) → jsonb` | authenticated | 10 per user per hour, 30 per day (`invite:try_later`). `{state, inviter_first_name}` with `state` one of `ok`, `expired`, `invalid`, `own`, `linked`; a name only for `ok` and `expired`. |

**W5 — About us**

| Function | Grants | Behaviour |
|---|---|---|
| `get_couple_profile(p_relationship_id uuid) → jsonb` | authenticated | Member and `relationship_chat_open` (`couple_profile:not_found` otherwise). Values, per-field `changed_by_me` / `changed_by_first_name` / `changed_at` (never a raw id), `read_only` (true unless active). No suggested dates: the AU2 chip comes only from the client provider (§3.8, review I-12), so `couple_profiles` functions stay Spec 1's alone. |
| `update_couple_profile(p_relationship_id uuid, p_patch jsonb) → jsonb` | authenticated | Active, non-archived member only (`couple_profile:read_only`). Allowed keys only (`couple_profile:unknown_key`); validates each value (future date, ceremonies only when married, ≤ 2, bands only with yes, anniversary needs a day: `couple_profile:anniversary_needs_day`); locks the row; writes changed values with `{field}_changed_by = auth.uid()`, `{field}_changed_at = now()`; leaving Married clears ceremonies (attributed); calls `sync_anniversary_reminder`. The together signal trigger bumps both phones. |
| `get_my_couple_profile_draft() → jsonb` / `update_my_couple_profile_draft(p_patch jsonb) → jsonb` | authenticated | Own draft, same validation, path must be Relationship. |
| `adopt_couple_profile_drafts(p_relationship_id uuid, p_inviter uuid, p_acceptor uuid) → void` | none | Called by `accept_relationship_invite_v2` (re-created in W5): inviter's draft first, the acceptor's fills empty fields; attribution = draft owner and its `set_at`; both drafts deleted. |
| `sync_anniversary_reminder(p_relationship_id uuid) → void` | none | `off` → deletes the linked reminder; otherwise upserts one `reminders` row (`reminder_type 'anniversary'`, title "Anniversary", `recurrence 'yearly'`, next occurrence at 09:00 in the editor's zone, `created_by` = editor). |
| `export_relationship(…)` (re-created from its latest body, today `20261024100700_story_export_order.sql`) | unchanged | Adds `about_us`: values plus `changes:[{field, by: export_who(me, id), at}]`, no ids. |
| `export_bundle(…)` (re-created from its latest body) | unchanged | Adds `personal.settings.birth_date`, `personal.settings.path`, `personal.settings.journal_reminder`. |
| `set_user_path_internal(…)` (re-created from its live body) | none | Adds one statement: a change to `dating` deletes the person's `couple_profile_drafts` row (review I-6). Nothing else changes. |

**W6a — holds enforced, recycled numbers**

| Function | Grants | Behaviour |
|---|---|---|
| `attune_access_token_hook(event jsonb) → jsonb` | supabase_auth_admin only (revoked from PUBLIC, anon, authenticated) | §4.4. |
| `consume_fresh_start(p_nonce text) → uuid` | service_role | Unused, ≤ 15 min challenge → marks used, places `recovery_hold` (expires +180 d), **writes `users.parked_phone_hmac` from the real `auth.users.phone`** (review I-11; before the edge function replaces the number), returns the old user id; else `fresh_start:invalid`. |
| `recovery_hold_candidates() → setof uuid` | service_role | Holds of kind `recovery_hold` past `expires_at` and unresolved. |
| `identity_alerts_due() → jsonb` / `mark_identity_alerts_sent(p_ids bigint[]) → void` | service_role | Hook fail-opens not yet alerted (`auth_hook_failures.alerted_at IS NULL`), for the `identity-health-alert` job (review S-8). |
| `get_identity_health()` (re-created from its live body) | service_role | Adds dormancy challenges in 7 days, parked accounts, parked accounts without `parked_phone_hmac`, hook fail-opens in the last 24 h. |

`place_account_hold` is created in W1b (with `p_ref DEFAULT NULL`), not here.

**W6b — date-of-birth correction**

| Function | Grants | Behaviour |
|---|---|---|
| `correct_my_birth_date(p_birth_date date) → jsonb` | authenticated | Once, within 7 days of `declared_at`, and only with no Dating enrollment in `active` (`birth_date:correction_closed`). Under 18 → `age_review` hold, `{status:'not_eligible'}`. |

**W6c — child safety**

| Function | Grants | Behaviour |
|---|---|---|
| `report_child_safety_concern(p_where text, p_details text) → void` | authenticated | 5 per user per day (`child_report:limit`); inserts one `child_safety_reports` row; the named child-safety contact reads that table (service role) and nothing tells the reported person. |

**W7a — resources**

| Function | Grants | Behaviour |
|---|---|---|
| `get_support_resources(p_country text) → jsonb` | anon, authenticated | Active rows for the country plus `XX`, emergency first, then `sort_order`; `{country_supported, catalogue_version, resources:[…]}`. |

**W7b — image safety**

Dating profile photos are **not** queued: Spec 2's `process-dating-photo` matches them inline before approval, and records a hit through `record_inline_csam_match`, so every photo is scanned once and a hit opens one hold and one escalation (review I-10).

| Function | Grants | Behaviour |
|---|---|---|
| `enqueue_media_scan()` (trigger function on `storage.objects`, or the fallback in §4.4) | none | §4.4. |
| `claim_media_scan_jobs(p_limit int) → setof private.media_scan_queue` | service_role | `FOR UPDATE SKIP LOCKED`, `pending` and due → `scanning`. |
| `private.handle_csam_match(p_bucket text, p_object_name text, p_owner uuid, p_vendor text, p_vendor_ref text) → bigint` | none | The one match path, shared by both entry points: records the match, places a `safety_review` hold on the owner (`place_account_hold`), opens a `csam_match` escalation, queues deletion of the original object through `queue_media_deletion`; returns the escalation id. It copies nothing itself: the caller has already copied the object to `safety-quarantine`. |
| `complete_media_scan(p_job_id bigint, p_result text, p_vendor text, p_vendor_ref text) → void` | service_role | `clear` → done. `unavailable` → back-off (1, 5, 15, 60 min, then hourly) up to 24 h, then `failed` + a `scan_failed` escalation. `match` → `private.handle_csam_match`. |
| `record_inline_csam_match(p_bucket text, p_object_name text, p_owner uuid, p_vendor text, p_vendor_ref text) → bigint` | service_role | For synchronous pipelines (Spec 2's `process-dating-photo`): inserts a `media_scan_queue` row with `source = 'inline'`, `status = 'match'` (idempotent on `bucket`, `object_name`), then `private.handle_csam_match`. Returns the escalation id, which Spec 2 links to its own `csam` moderation hold. |

`media_scan_status` is **not** built: no caller needs the queue's state once dating photos match inline.

**W9a — the shared normaliser and the pre-post filter**

One normaliser, one fold table and one goldens file serve Spec 1's filter and Spec 2's dating chat (review I-17). Spec 1 W9a owns them; Spec 2 W6 imports them and adds no second fold table.
- **Fold table:** `supabase/functions/_shared/unicode_fold_table.json` (invisible characters to remove, confusables → Latin, the West African letter fold, the leetspeak fold, separators). The SQL `translate()` strings in the migration are written from it, and a test checks they match.
- **TypeScript port:** `supabase/functions/_shared/unicode_normaliser.ts` (`baseForm`, `matchForm`), for Spec 2's `_shared/dating_chat_safety.ts`. The couples `chat_safety.ts` is not touched.
- **Goldens:** `supabase/tests/fixtures/unicode_normaliser_goldens.json`, run through both the SQL functions (`opinion_filter_contracts.sql`) and the TS port (`unicode_normaliser.test.ts`); both must give the same output for every line.
- **Two forms.** The **base form** keeps letters as typed (ɛ, ɔ, ŋ stay) and keeps `$`, so Spec 2's money-script patterns can match amounts. The **match form** adds the West African fold (`ɛ→e, ɔ→o, ŋ→ng, ƒ→f, ʋ→v, ɓ→b, ɗ→d, ƙ→k`) and leetspeak (`0→o, 1→i, 3→e, 4→a, 5→s, 7→t, @→a, $→s`). Term lists are stored and matched in the match form, so a Twi term typed on a phone without a Twi keyboard still matches. Each Spec 2 lexicon family states which form it matches.

| Function | Grants | Behaviour |
|---|---|---|
| `private.normalize_for_filter(p_text text) → text` (IMMUTABLE) | none | The **base form**: `normalize(p_text, NFKC)` → `lower` → remove zero-width, soft hyphen and bidi controls (`[​-‏‪-‮⁠-⁤﻿­]`) → fold the confusables map (Cyrillic and Greek look-alikes → Latin) with `translate` → separators (whitespace, ASCII punctuation, common Unicode punctuation) → single spaces. No letter is dropped. |
| `private.match_form(p_text text) → text` (IMMUTABLE) | none | `normalize_for_filter`, then the West African fold and the leetspeak fold from the shared table. |
| `private.digits_from_words(p_text text) → text` | none | English digit words (zero…nine; "oh" only inside a run of digit words) → digits; local-language number words come from the reviewed list. |
| `private.content_filter_verdict(p_text text, p_families text[]) → text` | none | NULL or `contact_info` / `slur` / `explicit` (first hit). **Contact:** after digit words, a run of 9–15 digits joined by at most single separators (space . - ( ) /) that starts with `+`, `00` or `0`, or matches the NANP shape, or starts with a calling code from the list — except when every group is a 4-digit year 1900–2099; e-mail addresses including "at … dot …" forms for common providers; URLs (`http`, `www.`, `wa.me`, `t.me`, short-link hosts, bare domains on a fixed TLD list); `@handles` of 3+ characters; a platform name (Instagram, Snapchat, TikTok, Telegram, WhatsApp, Signal and short forms) followed by ":" or "@" and a handle. **Slur / explicit:** `token` terms match as whole tokens in the match form; `squashed` terms (long, distinctive ones only) also match in the separator-free match form. Contact detection runs on the base form after digit words (so `$` and digits keep their meaning). Spec 2 calls this for prompts. |
| `private.assert_opinion_content_ok(p_text text) → void` | none | When `opinions_safety_v1` is on: verdict non-null → `content:{verdict}`. |
| `create_opinion`, `create_opinion_with_poll` (content and every option), `create_opinion_with_quote`, `edit_opinion`, `create_opinion_comment`, `edit_opinion_comment` | unchanged grants | Re-created from their latest bodies (today: `20260807120000` for `create_opinion`, `edit_opinion`, `create_opinion_comment`; `20260726120000` for the poll; `20260729120000` for the quote; `20260730120000` for `edit_opinion_comment`) **plus one call** to `assert_opinion_content_ok` before the insert or update. Nothing else changes. |

**W9b — at-risk reason, review queue v0, restored notices**

| Function | Grants | Behaviour |
|---|---|---|
| `private.assert_valid_report_reason`, `private.is_priority_reason` | unchanged | Add `'Someone may be at risk'` (valid, priority). |
| `report_opinion`, `report_opinion_comment` | unchanged | Re-created from `20260802120000`: an at-risk report is recorded with `priority = true` and **does not increment `report_count`**. |
| `admin_confirm_content_removal(p_content_type text, p_content_id uuid)` | unchanged (service_role only; revoked from PUBLIC, anon, authenticated) | Re-created from its **live** body (`20260802120000:205-267`, including the never-shorten ban extension and the `forum_post` branch, which Spec 3 W3 removes later from this body), with `search_path = ''` and every name qualified, **plus the two notices the `20260802` rewrite dropped** (Spec 3 V8): after a removal that found an author, `private.enqueue_forum_notification(p_user_id => author, p_title => 'Post removed', p_body => 'One of your posts was removed for breaking the Opinions guidelines.', p_type => 'forum_content_removed', p_opinion_id / p_comment_id => the removed item)`; when the ban starts or moves, `p_type => 'forum_posting_banned'`, title "Posting paused", body "You can't post in Opinions for 7 days." for a new ban or "Your pause on posting in Opinions has been extended." when an existing future ban was extended. Nothing is queued when the content was already removed. Taps route as Spec 3's keep list says (`notification_config.dart:185-192`, unchanged: home). **Also fixes OPN-BAN-42702 (§8 W9b):** in the ban-extension `SELECT`, the column is qualified (`FROM public.profiles AS p` … `p.banned_until`), because the function's `RETURNS TABLE (violation_count int, banned_until timestamptz)` declares an OUT variable named `banned_until`, so a bare `banned_until` raises 42702. `search_path = ''` does not cover this: a bare column is not a schema-qualified name. The return shape does not change. |
| `admin_list_priority_reports(p_limit int DEFAULT 50) → jsonb` | service_role | **Review queue v0:** pending priority reports, oldest first, with the reason and a 280-character excerpt; the reviewer works from the SQL editor or Spec 2's console. |
| `remove_my_opinion(p_opinion_id uuid) → void` | authenticated (revoked from PUBLIC, anon) | **New, OPN-DELETE-RLS (§8 W9b).** `SECURITY DEFINER`, `search_path = ''`, every name qualified. Sets `removed_at = now()` on the caller's own opinion: `WHERE id = p_opinion_id AND user_id = auth.uid() AND removed_at IS NULL`. Someone else's, a missing or an already-removed opinion changes nothing and raises nothing (today's client contract: a non-owner delete is a no-op). Not gated by the posting ban or `opinions_safety_v1`: removing your own words is never a posting act. |
| `remove_my_comment(p_comment_id uuid) → void` | authenticated (revoked from PUBLIC, anon) | **New, OPN-DELETE-RLS.** Same shape for `opinion_comments`. In the same function it lowers the parent opinion's `comment_count` by one (floor 0), **only when this call removed a live comment**, so a repeat call never decrements twice. The client therefore stops calling `decrement_opinion_comment_count` from `deleteComment`. |

### 4.4 Triggers and auth hooks

| Object | Wave | Definition |
|---|---|---|
| `auth_users_phone_sync` AFTER UPDATE OF `phone` ON `auth.users` | W1a | `UPDATE public.users SET phone = NEW.phone WHERE id = NEW.id AND phone IS DISTINCT FROM NEW.phone` (skips NULL). No INSERT trigger, so the 131 fixtures that insert `public.users` directly keep working. |
| `profiles_guard_moderation_columns` BEFORE INSERT OR UPDATE OR DELETE ON `public.profiles` | W1a | **Client writes only:** the guard acts when `current_user IN ('authenticated', 'anon')`, the repo's server-only precedent (`20261019110300_system_notice_server_only.sql:27`), so definer functions (which run as their owner) and the service-role `admin_confirm_content_removal` pass. INSERT forces `banned_until := NULL` and `confirmed_violation_count := 0`. UPDATE that changes `banned_until` **or `confirmed_violation_count`** → `profile:moderation_column`. DELETE of a profile with `confirmed_violation_count > 0` or `banned_until > now()` → `profile:moderation_locked` (review S-1: a delete and re-insert can no longer reset strikes or a ban). No other column is affected (location, quiz and profile writers unchanged; an upsert that doesn't name the two columns leaves them alone). |
| `couple_profiles_together_signal` AFTER INSERT OR UPDATE OR DELETE ON `couple_profiles` | W5 | `EXECUTE FUNCTION public.bump_together_signal()` (existing). |
| `feature_flags_production_gate` BEFORE INSERT OR UPDATE ON `public.feature_flags` | W1c | §2.5: refuses enabling a gated flag without evidence, in production only. Every other write passes unchanged (dev scripts, the `20260705210000` replay that forces Dating flags off). |
| `attune_access_token_hook` (Supabase Custom Access Token Hook, Postgres function) | W6a | Every token issue, sign-in or refresh. (1) Any unresolved hold (`age_review`, `safety_review`, `recovery_hold`) → `{"error":{"http_code":403,"message":"account_review"}}`, so a parked account's old sessions stop at their next refresh (within an hour) without touching `auth.sessions`; the client is signed out then, and H1 shows at the next code sign-in (§3.15). (2) `dormancy_rule` on, `authentication_method = 'otp'`, a `users` row exists, no unresolved `recovery_hold`, and `coalesce(account_activity.last_active_at, users.created_at) < now() - interval '180 days'` → inserts a challenge and returns `{"error":{"http_code":403,"message":"account_dormant:<nonce>"}}`; bumps `dormancy_challenge`. (3) Otherwise upserts `account_activity.last_active_at = now()` when older than 12 h and returns the event unchanged. Any unexpected internal error is caught and the event returned unchanged, so a bug can never lock everyone out (deliberate refusals are the only errors). **Each fail-open is counted and alerted (review S-8):** the handler inserts one `private.auth_hook_failures` row (in its own nested exception block, so recording can't fail the hook) and bumps `auth_hook_fail_open`; the `identity-health-alert` job posts any new row to `SAFETY_ALERT_WEBHOOK` within 15 minutes. The trade-off stays: a held account (`age_review`, CSAM `safety_review`) may get a token while the hook is failing, so any fail-open is treated as an incident. |
| `enqueue_media_scan` AFTER INSERT ON `storage.objects` | W7b | Only when `csam_hash_matching` is on and `bucket_id IN ('message-media','story-media','relationship-avatars','journal-media','planning-media')` (**not** `dating-profile-photos`, which Spec 2 matches inline, review I-10) and the mime is an image or video: `INSERT … ON CONFLICT DO NOTHING` inside an exception block, so a failure never blocks an upload. **Spike first (review F-1):** no trigger on `storage.objects` exists in the repo, and hosted Supabase may not grant `postgres` the TRIGGER privilege there. Before W7b, create and drop a no-op trigger on the development project. If that fails, the fallback is a 1-minute sweep, `enqueue_new_storage_objects()` (cron), that inserts queue rows for objects in the listed buckets created since the last sweep (by `created_at`, with a 2-minute overlap and `ON CONFLICT DO NOTHING`); the local bootstrap gains a `storage.objects` stub for either path. |

The Send SMS Hook (W2c) is an HTTP hook to the `send-sms-hook` edge function (§4.5).

### 4.5 Edge functions

| Function | Wave | New / changed | Behaviour |
|---|---|---|---|
| `create-relationship-invite` | W1a, W4a | changed | W1a: `ensureUserRow` stops writing `mode` and never uses the phone as a display name (`''` instead). W4a: with `flow_signin_v2` effectively on, an inviter without a DOB or under 18 gets 428 `invite:age_required` / 403 neutral. |
| `accept-invite` | W1a, W4a | changed | W1a: the same `ensureUserRow` fix. W4a: calls `accept_relationship_invite_v2(user.id, code)`, maps codes to today's statuses and messages (the "You're already in a relationship" prefix is kept for `kAlreadyInRelationshipPrefix`), then enqueues the existing best-effort `invite_accepted` push. |
| `analyse-journal-entry` | W1c, W9c | changed | W1c: before any provider call, `journal_ai_insights` off → `{status:'paused'}` for both actions. W9c: **first statement after loading the entry** runs `detectSelfDisclosure(title + content, {victimisation: privateSafetyCheckOn})`, where `privateSafetyCheckOn` is the existing Spec 8 flag `private_safety_check` read the way `ai-assist` reads it (default off; review A-4). Self-harm, the reviewed corpus, always runs; the `[DRAFT]` victimisation list runs only with that flag; a match returns `{status:'support_offered'}`, calls no provider, persists nothing and checks no cache; `get_patterns` excludes matched entries and returns `support_offered` without a provider call when the newest entry matches. Bumps `support_card_shown:journal` through `bump_metric_server`. |
| `purge-unfinished-signups` | W1c | new (cron, service role) | Deletes `unfinished_signup_candidates()` through `auth.admin.deleteUser`. |
| `otp-delivery-intent` | W2c | new (`verify_jwt = false`) | Body `{phone, channel, platform, locale, device_nonce}` (16 random bytes, base64url, required); per-IP 10 per hour; HMACs the E.164 number with `OTP_HMAC_KEY` and hashes the nonce (SHA-256); `otp_record_intent`. Returns 204 always (never says whether the number is known, or whether the intent was stored). |
| `send-sms-hook` | W2c | new (Auth Send SMS Hook, standard-webhooks signature `SEND_SMS_HOOK_SECRET`) | `otp_take_send_decision`; then by channel: **SMS** via the country's first route, failing over to the next (Ghana-direct first for GH; a global provider elsewhere). The message shape follows the intent's platform (`other` gets the iOS shape). iOS message: "Your Attune code is {otp}. It expires in 10 minutes. Don't share it.\n\n@invite.attune.barsopus.com #{otp}". Android message: "<#> Your Attune code is {otp}. It expires in 10 minutes. Don't share it.\n{app hash}" (hashes from `ANDROID_SMS_APP_HASHES` per signing key). **WhatsApp** via the Cloud API authentication template (copy-code and Android one-tap buttons); a synchronous failure falls back to SMS. **Voice** via the voice route: "Your Attune code is {d, d, d, d, d, d}. Again: {d, d, d, d, d, d}."; a synchronous failure also falls back to SMS. A non-SMS channel is used only when `otp_take_send_decision` chose it (fresh, capped, single-device intent); otherwise SMS (review S-3). Refuses `+999`. Bumps `otp_sent:{CC}:{channel}:{route}` (`bump_metric_server`); a refusal returns the hook error `otp:rate_limited:{seconds}` or `otp:unavailable`. |
| `start-fresh-account` | W6a | new (`verify_jwt = false`, per-IP 5 per hour) | `consume_fresh_start(nonce)` (which records the real number's HMAC in `users.parked_phone_hmac` first, review I-11) → parks the old account: Auth admin `updateUserById(old, {phone: '+999' + 12 digits from the user id, retried on collision})` (`+999` is an unassigned ITU code and the Send SMS Hook refuses it); sets `phone_released_at`. Its sessions need no revocation: the hook refuses every token for a held account. The sync trigger mirrors the parked number to `public.users`. The client then signs in again by OTP, which creates a new user. |
| `purge-recovery-holds` | W6a | new (cron) | For `recovery_hold_candidates()`: `prepare_account_deletion(id)` then `auth.admin.deleteUser(id)` (the existing deletion path). Spec 2's deletion steps read `parked_phone_hmac` through `dating_phone_hmac_for_user`, so carry-over follows the real number, not `+999…`. |
| `identity-health-alert` | W6a | new (cron, service role) | `identity_alerts_due()`; posts each new hook fail-open (count and time only) to `SAFETY_ALERT_WEBHOOK`; `mark_identity_alerts_sent`. |
| `scan-media` | W7b | new (cron, service role) | Claims jobs; downloads; calls `_shared/csam_matcher.ts` (`CSAM_MATCHER` set to `photodna`, `safer` or `stub`; the stub matches a test hash list; **in production, `get_attune_environment()`, the stub is refused** and every job is completed as `unavailable`, so nothing is ever marked clear by a stub); on `match` calls `_shared/csam_match_path.ts` `quarantineAndRecord()` (copies the object to `safety-quarantine` first, then `complete_media_scan`); posts the escalation to `SAFETY_ALERT_WEBHOOK` (a destination the owner configures). Video: the vendor's video hashing where the contract includes it; until then the poster/thumbnail object is scanned and the gap is listed in the runbook. Pipelines that process synchronously (Spec 2's `process-dating-photo`) call `csam_matcher.ts` inline and, on a match, the same `_shared/csam_match_path.ts` helper with `record_inline_csam_match` in place of `complete_media_scan`, so the quarantine, hold, escalation and deletion are identical. |

**Auth settings (ops, W2c and W6a, per environment; first on the development project):** phone OTP length 6, expiry 600 s, per-number frequency 30 s; the project-wide SMS hourly limit raised for worldwide sign-up; Send SMS Hook enabled with the function URL and secret; Custom Access Token Hook enabled with `public.attune_access_token_hook`. The owner confirms in the dashboard that the project's plan offers both hooks (Supabase documents Send SMS and Custom Access Token as available on Free and Pro; it can't be confirmed from the repo, and `config.toml` has no `[auth]` section yet) (review F-2). Local: `supabase/config.toml` gains `[functions.*] verify_jwt` entries and `[auth.hook.*]` sections; `scripts/local_pg_bootstrap.sql` gains a `supabase_auth_admin` role stub.

### 4.6 Crons (registered by name, idempotently, the way `20260907120000_register_scheduled_jobs.sql` registers workers)

Each table's retention job is registered by the migration that creates the table, so no wave re-creates another wave's purge function and waves can land in any dependency-valid order (review I-1).

| Job | Schedule (UTC) | Wave | Runs |
|---|---|---|---|
| `metric-counters-retention` | `12 4 * * *` | W1b | `DELETE FROM metric_counters WHERE day < current_date - 400` |
| `purge-unfinished-signups` | `41 3 * * *` | W1c | edge function |
| `otp-purge` | `37 * * * *` | W2c | `otp_purge()` (W2c tables only) |
| `enqueue-journal-reminders` | `*/15 * * * *` | W3c | `enqueue_journal_reminders()` |
| `invite-preview-retention` | `39 * * * *` | W4a | deletes `invite_preview_attempts` older than 1 day |
| `fresh-start-retention` | `43 * * * *` | W6a | deletes `fresh_start_challenges` older than 1 hour and `auth_hook_failures` older than 30 days |
| `purge-recovery-holds` | `55 3 * * *` | W6a | edge function |
| `identity-health-alert` | `*/15 * * * *` | W6a | edge function |
| `scan-media` | `* * * * *` | W7b | edge function |
| `media-scan-retention` | `27 4 * * *` | W7b | removes `clear` queue rows older than 7 days |
| `enqueue-new-storage-objects` | `* * * * *` | W7b, fallback only | the §4.4 sweep, registered only if the F-1 spike fails |

### 4.7 Migrations, by name and order (no timestamps)

**Timestamps are assigned at build time (reviews I-1, I-2; controller ruling).** This spec lists each migration by **name, purpose and order within its wave** only. When a wave is built, the implementer gives each file a timestamp later than every migration already applied, in the actual build order (`supabase migration new <name>` does this). Waves may then run in any dependency-valid order (§8), and a hotfix written during the program never sorts before an applied file. The same rule applies to any migration written while the program runs, in any spec: it always takes a timestamp after the newest applied migration.

**Every file:**
- is one atomic `BEGIN; … COMMIT;` (Spec 3's rule; 8 recent repo files already do this), so a local `psql -f` can't half-apply it (review F-3);
- uses no `CREATE INDEX CONCURRENTLY` (it can't run inside a transaction);
- has its `<name>_grants.sql` twin, written right after it (repo pattern);
- re-creates any existing function **from its live body**, found at build time, never from a body copied into this spec.

| # | Name (+ `_grants` twin) | Wave | Purpose |
|---|---|---|---|
| 1 | `identity_users_lockdown` | W1a | `users` columns (`path`, `path_previous`, `path_chosen_at`, `phone_released_at`), `mode` comment, phone sync trigger, the `profiles` moderation guard (`banned_until` **and** `confirmed_violation_count`, S-1), `verified_phone`; the five dating functions re-created from their live bodies minus their `UPDATE public.users SET mode` statement (`pause_dating_for_relationship_user`, `activate_dating_profile`, `pause_dating_mode`, `exit_dating_mode`, `delete_dating_profile`); column grants. The same release changes the client upsert and both invite functions (§4.5). |
| 2 | `metric_counters` | W1b | `metric_counters`, `metric_key_prefixes`, `metric_client_keys` and their seeds; `private.bump_metric_internal`, `bump_metric_server`, `bump_metric` (exact keys, S-2); report view; retention cron. First in W1b because the next two bump metrics. |
| 3 | `account_birthdates_and_holds` | W1b | `account_birthdates`, `account_holds`; `complete_sign_up`, `set_my_birth_date`, `get_my_age`, `account_age`, `place_account_hold` (`p_ref DEFAULT NULL`) |
| 4 | `paths_and_home_state` | W1b | `private.spec1_flag_on`, `private.dating_home_summary`, `set_user_path_internal` (no W5 table, I-6), `set_my_path`, `get_my_home_state`, `withdraw_my_pending_invites` v2, drop `onboarding_profiles.mode` |
| 5 | `spec1_flags_and_public_config` | W1c | `private.attune_environment`, `get_attune_environment`, `private.assert_development_project`; eleven flag rows (false); `private.flag_production_gates` with its seeds, trigger, `record_flag_gate_evidence`, `production_flag_violations`; `app_public_config`, `private.dating_open_countries`, `get_public_app_config` |
| 6 | `identity_health` | W1c | `get_identity_health` (W1 counts only), `unfinished_signup_candidates`, purge cron |
| 7 | `otp_delivery` | W2c | OTP tables (intents with `device_hash`), seeds, functions, purge cron |
| 8 | `journal_reminders` | W3c | table, RPCs, enqueue function, cron |
| 9 | `accept_invite_v2` | W4a | `accept_relationship_invite_v2`, `preview_relationship_invite`, attempts table and its retention cron |
| 10 | `couple_profiles` | W5 | tables, RPCs, signal trigger, anniversary sync, `accept_relationship_invite_v2` re-created with draft adoption, `set_user_path_internal` re-created with the draft delete (I-6), `export_relationship` and `export_bundle` re-created |
| 11 | `account_dormancy_and_fresh_start` | W6a | `account_activity`, `fresh_start_challenges`, `auth_hook_failures`, `users.parked_phone_hmac`; the hook; `consume_fresh_start`, `recovery_hold_candidates`, `identity_alerts_due`, `mark_identity_alerts_sent`; `get_identity_health` re-created; crons |
| 12 | `birth_date_correction` | W6b | `correct_my_birth_date` |
| 13 | `child_safety_reports` | W6c | table, `report_child_safety_concern` |
| 14 | `support_resources_v2` | W7a | table, `get_support_resources` |
| 15 | `media_scan` | W7b | queue (with `source`), escalations, quarantine bucket, the storage trigger (or the sweep fallback), `private.handle_csam_match`, `complete_media_scan`, `record_inline_csam_match`, crons |
| 16 | `opinion_content_filter` | W9a | base and match forms, digits, terms table, verdict, assert, the six writer RPCs |
| 17 | `opinion_at_risk_and_review_queue` | W9b | report reasons, the two report RPCs, review queue v0 |
| 18 | `opinion_moderation_notices` | W9b | `admin_confirm_content_removal` re-created from its live body with the two notices restored **and the strike-3 `banned_until` qualification (OPN-BAN-42702)** |
| 19 | `opinion_remove_own` | W9b | `remove_my_opinion`, `remove_my_comment` (OPN-DELETE-RLS) |

W10 has no migration.

### 4.8 Data retention

| Data | Where | Kept until |
|---|---|---|
| Sign-up draft (name, DOB, phone, channel, ladder) | device, anonymous scope | sign-up completes, or 7 days, or the under-18 stop (deleted at once) |
| Guest birth year | device secure store | sign-up completes, or uninstall |
| Under-18 block | device (backed-up prefs file + iOS Keychain) | 30 days |
| Partner first name (R1) | device, user scope | linking, sign-out (wipe registry) |
| Ask 2 progress | device, user scope | completion, sign-out, quick exit (wipe registry) |
| Dating lock setting (`me_section_lock`) | device secure store | sign-out only; **kept on quick exit** (a protective setting, D19) |
| Home-state cache (tab layout, link state, needs, hold) | device, user scope | replaced on each server answer; sign-out (wipe registry) |
| `account_birthdates` | server | account deletion (cascade); in the person's own export only |
| Unfinished sign-up (auth user without `users` row) | Auth | 24 hours |
| OTP intents / send events / invite previews / fresh-start challenges | server | 10 minutes / 24 hours / 1 day / 1 hour |
| `metric_counters` | server, aggregates | 400 days |
| `couple_profiles` | server | the relationship's purge (Spec 3b: 12 months after archive); read-only in the window |
| `couple_profile_drafts` | server | moved on linking, switching to Dating, or account deletion |
| `journal_reminder_settings`, `account_activity` | server | account deletion |
| Recovery hold (parked old account), with its `parked_phone_hmac` | server | 180 days, then the account-deletion path |
| Hook fail-open records (`auth_hook_failures`, no user data) | server | 30 days |
| `child_safety_reports` | server | 2 years after closing, unless counsel places a legal hold |
| CSAM match evidence (quarantine object, escalation) | server | counsel's instruction per country (the US currently expects one year after a CyberTipline report); default one year |
| `media_scan_queue` | server | 7 days after a `clear` result; matches kept with the escalation |
| Content-filter blocks | not stored | only `opinion_blocked:{reason}` counts |
| Journal crisis-check matches | not stored | only `support_card_shown:journal` counts |

---

## 5. Client architecture

### 5.1 Files to create

| File | Wave | Purpose |
|---|---|---|
| `lib/core/ui/motion/shared_axis_step.dart` | W2a | step transition (§2.2) |
| `lib/core/ui/text/allow_large_text.dart` | W2a | the opt-in large-text wrapper |
| `lib/core/flags/public_app_config.dart` | W1c | `get_public_app_config` + prefs cache for the first frame (the open-country list included) |
| `lib/core/metrics/metric_counter.dart` | W1c | fire-and-forget `bump_metric`, typed so only the seeded exact keys can be passed |
| `lib/core/device/device_wipe_registry.dart` | W3a | the device wipe registry (§5.8) |
| `lib/app/device_wipes.dart` | W3a | `registerDeviceWipes()`, called once at boot: Spec 1's entries, plus one line per other feature's own register function (Spec 2 adds `registerDatingDeviceWipes()` here) |
| `lib/core/platform/sim_country.dart` (+ Kotlin channel) | W2b | Android SIM country; iOS returns null |
| `lib/core/platform/age_signals.dart` (+ Swift `DeclaredAgeRange`, Kotlin Play Age Signals) | W6b | `AgeSignal {source, status: adult/minor/supervised/unknown/unavailable}`, never stored. **iOS:** Declared Age Range needs the iOS 26 SDK (Xcode 26); the framework is weak-linked and called only under `if #available(iOS 26, *)`, returning `unavailable` below it. Device checks run in **release** mode, because debugging on iOS 26 needs a newer Flutter than 3.29 (review F-4). |
| `lib/core/platform/install_referrer.dart` | W4b | one read on first launch |
| `lib/features/auth/sign_up/presentation/screens/welcome_screen.dart`, `widgets/path_preview_sheet.dart` | W2a | WL1 screen |
| `lib/features/auth/sign_up/presentation/screens/sign_up_flow.dart` and `steps/{name,birth_date,phone,code,consent,no_account,dormant,fresh_start}_step.dart` | W2b, W6a | A1–A5, N1, DM1–DM2 |
| `lib/features/auth/sign_up/presentation/screens/{guest_age_gate,under_age_stop,account_hold}_screen.dart` | W2a, W6a | G1, X1, H1 |
| `lib/features/auth/sign_up/presentation/widgets/one_time_code_field.dart` | W2c | one field, six drawn boxes, autofill |
| `lib/features/auth/sign_up/data/{sign_up_draft_store,age_gate_store,account_service}.dart` | W2b | device draft (with `device_nonce`), age gate, sign-up RPCs |
| `lib/features/auth/sign_up/data/otp_delivery_service.dart` | W2c | intent + OTP |
| `lib/features/auth/sign_up/domain/{birth_date_validator,display_name_validator,default_phone_country,resend_ladder}.dart` | W2b | pure, unit-tested |
| `lib/features/onboarding/domain/home_state.dart` | W1b | `AppPath`, `AppTab`, `LinkState`, `HomeState`, `needs` |
| `lib/features/onboarding/data/home_state_store.dart` | W1b | user-scoped cache of the last server home state: **tab layout, link, needs, hold only** (D20) |
| `lib/features/onboarding/presentation/providers/home_state_providers.dart` | W3a | §5.3 |
| `lib/features/onboarding/presentation/widgets/path_step.dart` | W3a | A6 |
| `lib/features/onboarding/presentation/widgets/invite_partner_step.dart` | W4b | R1+R2 |
| `lib/features/relationships/presentation/screens/relationship_space_screen.dart` | W3b | R3 |
| `lib/features/relationships/presentation/screens/{invite_landing_screen,join_invite_screen}.dart` | W4b | RI-1/RI-2, RI-3/RI-4 |
| `lib/features/relationships/presentation/widgets/linked_moment.dart` | W4b | R4 |
| `lib/features/relationships/data/invite_messages.dart` | W4b | the registers |
| `lib/features/me/presentation/screens/me_home_screen.dart`, `widgets/{dating_slot,your_space_section,more_ways_sheet,first_action_card}.dart` | W3b | Me home |
| `lib/features/me/presentation/widgets/journal_reminder_row.dart`, `lib/features/me/data/journal_reminder_service.dart` | W3c | J3 |
| `lib/features/safety/data/dating_lock_store.dart` | W3b | device setting, stored under the neutral key `me_section_lock` |
| `lib/features/settings/presentation/screens/how_you_use_attune_screen.dart` | W3c | §3.12 |
| `lib/features/couple_profile/{data/couple_profile_service.dart, domain/couple_profile.dart, presentation/screens/about_us_screen.dart, presentation/screens/about_us_question_flow.dart, presentation/widgets/{about_us_card,changed_by_line}.dart}` | W5 | About us |
| `lib/features/safety/presentation/screens/report_child_concern_screen.dart` | W6c | child report |
| `lib/features/safety/presentation/screens/support_resources_v2_screen.dart`, `data/support_resources_repository.dart`, `assets/support_resources/catalogue.json` | W7a | resources |
| `supabase/functions/_shared/csam_match_path.ts` | W7b | the one quarantine-and-record path, used by `scan-media` and Spec 2's `process-dating-photo` |
| `supabase/functions/_shared/unicode_fold_table.json`, `_shared/unicode_normaliser.ts` (+ test), `supabase/tests/fixtures/unicode_normaliser_goldens.json` | W9a | the shared normaliser (§4.3 W9a) |
| `lib/app/text_scale_policy.dart` | W10a | root cap from `text_scale_v2`; route prefixes that keep 1.0 |
| `lib/features/opinions/presentation/widgets/need_support_link.dart` | W9b | the link |
| `lib/features/opinions/domain/content_filter_error.dart` | W9a | error mapping |
| `lib/features/reflection_journal/presentation/widgets/journal_support_card.dart` | W9c | the writer card |

### 5.2 Files to change

| File | Wave | Change |
|---|---|---|
| `lib/features/onboarding/data/onboarding_submission_service.dart` | W1a, W1b | W1a: stop writing `users.phone` and `users.mode` (the `users` upsert becomes an update of `display_name` only). W1b: stop writing `onboarding_profiles.mode` (the column is dropped in W1b) |
| `lib/features/onboarding/data/onboarding_store.dart` | W1c | scoped invite code (§5.5); add keys, rename none |
| `lib/main.dart` | W2a, W3a, W4b, W10b | invite links under `flow_signin_v2` → `/invite` (still clearing first launch); `registerDeviceWipes()` once at boot (W3a); Install Referrer read; W10b boot bound if measured |
| `lib/app/routing/app_router.dart`, `routing_notifier.dart` | W2a–W7a | §5.4; only the auth, onboarding, settings and safety blocks |
| `lib/home/home_screen.dart` | W3a | `_HomeGateData` gains `homeState`; v2 sync; Tab 2 by tab layout; keyed shell (§5.6 R1) |
| `lib/features/onboarding/presentation/screens/onboarding_gate.dart`, `onboarding_flow.dart` | W3a, W4b | v2 runs `needs` steps then A6 and R1; no acceptance before the name (RI-3 instead) |
| `lib/features/chat/presentation/screens/chat_couples_locked_screen.dart` | W3b | **remove the "Meet someone in Dating mode" button (`:370-383`) unconditionally**, and its `RouteNames.datingMode` use; nothing else on the screen changes (review R-5; §5.6 R17) |
| `lib/features/onboarding/presentation/widgets/pending_invite_guide.dart` | W4b | `v2` parameter: "Send a new invite" and the name |
| `lib/features/onboarding/presentation/screens/ask2_flow.dart` | W4b | save-as-you-go; registers its wipe entry |
| `lib/features/onboarding/presentation/widgets/onboarding_deck_card.dart` | W10b | 900 → 320 ms |
| `lib/features/onboarding/data/onboarding_sync_service.dart` | W2b–W5 | replays `PendingSignUp`, `PendingPath` (never a Dating choice), About-us patches |
| `lib/features/auth/log_in/presentation/screens/login_profile.dart` | W2b | v2 copy and three buttons |
| `lib/features/auth/data/eula_acceptance_service.dart` | W2b | version `'2'` under `flow_signin_v2` |
| `lib/features/auth/data/passwordless_auth_service.dart` | W2c, W6a | classify `account_dormant:*`, `account_review`, `otp:rate_limited:*`; remove the debug phone log |
| `lib/features/safety/domain/services/quick_exit_service.dart` | W3a | **Spec 1 owns it (D19).** One added line in `_run`, after the existing Together, map and Stories calls: `unawaited(DeviceWipeRegistry.instance.run(WipeMoment.quickExit))`. The cover, `safety_requires_unlock`, the 300 ms wait, the second Stories wipe and the exit are unchanged (§5.6 R18) |
| `lib/features/auth/providers/auth_provider.dart` | W3a | **Spec 1 owns the sign-out path (D19).** One added entry in `AuthOperations.signOut`'s side-by-side `wipe()`: `DeviceWipeRegistry.instance.run(WipeMoment.signOut)`, beside the four existing wipes, so its bound doesn't add to theirs. `SignOutHooks`, the push release and the `auth_exports.dart` barrel are unchanged (§5.6 R19) |
| `lib/features/safety/data/safety_sign_out.dart` | W3a | the same registry call in the fallback path, next to its story-outbox wipe (a repeat is a no-op) |
| `lib/core/notifications/services/onesignal_service.dart`, `push_permission_policy.dart` | W3c | `askInContext(PushAskContext)`; no automatic ask under `flow_paths_v2` |
| `lib/core/notifications/config/notification_config.dart` | W3c | `journal_reminder` tap → `/home?tab=me` → journal |
| `lib/features/settings/data/settings_data.dart` | W3b, W3c, W5, W6b, W6c, W7a | rows: Dating lock (W3b); How you use Attune (W3c); About us; Date of birth; Report a concern about a child; Support |
| `lib/features/together/presentation/screens/together_screen.dart` | W5 | "Add your anniversary" → AU6 (flag on); "About us" row; the linked reminder's sheet says "This reminder follows About us" + "Change in About us" |
| `lib/features/safety/presentation/screens/safety_resources_screen.dart` | W7a | v2 body under `support_resources_v2` (same route name, so every existing link keeps working) |
| `lib/features/opinions/presentation/screen/{opinion_compose_screen,edit_opinion_screen,quote_compose_screen,comment_thread_screen}.dart`, `lib/features/opinions/data/opinion_more_data.dart` | W9a, W9b | W9a: filter errors inline (draft kept). W9b: "Need support now?" in compose and in every post and comment menu, the at-risk reason in both report lists |
| `lib/features/opinions/data/repositories/opinion_repository.dart` | W9b | `deleteOpinion` and `deleteComment` call `remove_my_opinion` / `remove_my_comment` instead of a direct `UPDATE` (OPN-DELETE-RLS); `deleteComment` drops its `opinion_id` pre-select and its `decrement_opinion_comment_count` call (the RPC decrements once). Nothing else in the file changes |
| `lib/features/reflection_journal/presentation/screens/journal_entry_screen.dart`, `data/models/journal_analysis.dart` | W1c, W9c | W1c: `paused` shows nothing. W9c: support card on `support_offered`; "Need support now?" in the entry menu |
| `lib/core/utils/constants.dart` | W6c | real `supportEmail`, new `childSafetyEmail` (owner provides; proposed `support@barsopus.com`, `childsafety@barsopus.com`) |
| `lib/core/utils/date_formatter.dart` | W5 | `toMonthYear`, `toYear` |
| `lib/core/ui/motion/motion_tokens.dart` | W2a | tokens (§2.2) |
| `lib/app/feature_flag_refresher.dart` | W1c+ | each new flag provider added to `refreshedFlagProviders` |
| `lib/app/app.dart`, `lib/app/app_shell.dart` | W10a | `appShell(maxTextScale:)` from `textScaleCapProvider` |
| `lib/app/documentations/user_manual/**` | W3c, W5, W7a, W9b | topics: "How you use Attune" (`flow_paths_v2`), "About us" (`couple_profile`), Support (v2), Opinions safety and Journal lines; flags declared in `DocumentationRegistry`. Topics are added through the registry only; nothing pins a module count (Spec 3's test asserts the forum topics are absent, not a total; review C-1) |
| `lib/i10n/app_en.arb` (+ generated) | W2a+ | new keys |
| `pubspec.yaml` | W2c, W4b | `smart_auth`, `play_install_referrer` |
| `android/app/src/main/res/xml/{backup_rules,data_extraction_rules}.xml` | W2a | exclude `attune_age_gate`; the age-block file stays included |
| `ios/Runner/Runner.entitlements` | W2c, W6b | `webcredentials:invite.attune.barsopus.com`; Declared Age Range entitlement |
| `supabase/config.toml`, `scripts/local_pg_bootstrap.sql`, `scripts/local_pg_grants.sql` | W1a, W2c, W6a, W7b | §4.5, §4.1 (`storage.objects` stub in W7b). Edited for CI's from-scratch build; never **run** against `attune_spec3a` (§7.1) |

### 5.3 Providers (Riverpod)

- `publicAppConfigProvider` (FutureProvider, seeded from prefs) and one bool provider per flag (`flowSignInV2Provider`, `flowPathsV2Provider`, `flowCouplesV2Provider`, `coupleProfileEnabledProvider`, `platformAgeSignalsProvider`, `supportResourcesV2Provider`, `opinionsSafetyProvider`, `textScaleCapProvider`). An unreadable flag is off, except the first-frame default for `flow_signin_v2`, which comes from `Environment.flowV2Default` (`.env.json` key `FLOW_V2_DEFAULT`: true in development builds, false in production) until the first fetch. Each provider returns the **effective** value (§2.5): `flowPathsV2Provider` is `flow_paths_v2 && flowSignInV2`, `flowCouplesV2Provider` is `flow_couples_v2 && flowPathsV2`, `coupleProfileEnabledProvider` is `couple_profile && flowCouplesV2` (review A-6). `datingOpenCountriesProvider` reads `config.dating_open_countries` from the same cached config (D15).
- `homeStateProvider` (AsyncNotifier, family by user id): seeds from `HomeStateStore` (tab layout, link, needs, hold), refreshes from `get_my_home_state()` on launch, resume, sign-in and `relationshipModeResyncSignal`; writes the store **without the path or the `dating` summary**; exposes `tab`, `linkState`, `needs`, `hold` (from cache or server) and `path` and `dating` (server answer only, in memory, `null` until it arrives; D20).
- `signUpDraftProvider` (Notifier over `SignUpDraftStore`), `ageGateProvider`, `pendingInviteProvider` (user-scoped), `deviceCountryProvider`.
- `coupleProfileProvider(relationshipId)` (fetch + `together_change_signals` realtime refetch), `coupleProfileDraftProvider`, `aboutUsDateSuggestionsProvider(relationshipId)` (returns `[]`; Spec 2 W9 overrides it).
- `journalReminderProvider`, `datingLockProvider`, `supportResourcesProvider(country)`.
- `deviceWipeRegistryProvider` exposes `DeviceWipeRegistry.instance` for tests (§5.8).

### 5.4 Router changes (`app_router.dart`, `routing_notifier.dart`)

- **New routes:** `/welcome`, `/signup` (extra: `new` / `returning` / `invite`), `/guest-age`, `/invite`, `/age-stop`, `/account-check`, `/settings/how-you-use-attune`, `/about-us/:relationshipId`, `/settings/report-child-concern`. The support screen keeps `RouteNames.safetyResources`.
- **First launch:** with `flow_signin_v2`, `/_invisible` → `/welcome` instead of `/intro`. While `isFirstLaunch` is true the redirect allows `{/welcome, /signup, /guest-age, /invite, /age-stop, /intro, safetyResources}` and sends everything else to the first-launch screen (today it allows only `/intro`, `app_router.dart:422-425`).
- **Guest gate:** signed out, `/home`, no `guest_ok` → `/guest-age`.
- **Under-18 block:** an active device block sends `/signup`, `/invite` and `/guest-age` to `/age-stop`.
- `RoutingNotifier` gains `flowV2`, `guestAgeOk` and `underAgeBlocked` (read synchronously from prefs at boot, refreshed by their stores).
- Holds don't need a guard: the hook refuses tokens and the client lands on H1.
- Untouched, cited by name because line numbers move about 55 lines after Spec 3 W1 (review C-8): every `lib/features/games/**` import; every `GoRoute` whose builder builds a Games screen (the block from `thirtySixChapterInvitation` through `thisOrThatCustomCreate`, and the `/games/*` routes such as `paintBallLobby`); the dating block (Spec 2); the forum block (removed by Spec 3 first). R2's architecture test lists these route names and fails if any changes.

### 5.5 The onboarding store replacement

- **`HomeStateStore`** replaces `OnboardingMode` as the home's source under `flow_paths_v2`: key `attune.home.<scope>.state` (JSON `{tab, link, needs, hold, at}`, with `tab` one of `chat` / `me`), written only from a server answer, so a local value is never invented (the lesson in `onboarding_store.dart:105-121`). **It never stores the path or anything about Dating** (D20, controller ruling C-5): Dating and Just for me both cache `me`, and the Dating slot is drawn only from the live server answer. `HomeScreen`'s `isComplete` under v2 is `needs.isEmpty` from this cache.
- **No Dating on the device (D20).** Spec 1's device keys and values never contain "dating": the Dating lock is `me_section_lock` in the safety store; the Dating slot's country picker is `attune.flow.<uid>.country_override`; a Dating path choice is never queued offline (§3.7). **Allow-list for Spec 2's S19 test** ("no Dating data on disk"): `attune.home.<scope>.state`, `attune.flow.<uid>.country_override`, the safety store's `me_section_lock`, plus every Spec 1 key that exists for a person who never used Dating (sign-up draft, invite code, partner name, Ask 2 progress, linked moment, guest age gate, under-18 block).
- **Legacy stays readable:** `OnboardingStore`, `OnboardingMode` and `resolveModeFromRelationshipStatus` remain for the flag-off path and are not renamed (06 R4). When v2 writes its first state for a scope, it removes that scope's `attune.onboarding.<scope>.mode` once; if the flag is later switched off, the legacy sync rebuilds `mode` from the server.
- **Scoped invite code (W1c, unconditional):** a link opened while signed out goes to `attune.onboarding.anonymous.pending_invite` = `{code, stored_at}`; on sign-in it is claimed into `attune.onboarding.user.<uid>.pending_invite` only if under 24 h old, then the anonymous slot is cleared. A link opened while signed in goes straight to the user slot. The legacy unscoped key (`onboarding_store.dart:70`) is read once, moved to the anonymous slot with `stored_at = now`, and deleted. Under `flow_couples_v2` acceptance happens only from RI-3.
- **Sign-up draft:** `attune.flow.anonymous.signup_draft` (name, DOB, E.164, country, channel, `device_nonce`, `last_sent_at`, `send_count`, `return_to`); the DOB never leaves the device until `complete_sign_up`.

### 5.6 Regression notes for shared files

| # | File | Risk | Mitigation |
|---|---|---|---|
| R1 | `lib/home/home_screen.dart` | Re-opening the sign-in redirect storm; stranding a couple behind the wrong screen | The latch block (`:340-365`) is not edited: v2 only changes what `_gateData.isComplete` means (`needs.isEmpty`), which changes the latch's input. The tab layout is one more field on `_HomeGateData`. Tests in `test/home/*` are extended **first**: latch fires once; **latch fires exactly once for a legacy account whose `needs = [birth_date]`, and not again after the DOB is added** (review N-2); signed-out guest shell; v2 tab mapping; keyed rebuild on a tab-layout change; no rebuild on a link change or on Dating ↔ Just for me. |
| R2 | `lib/app/routing/app_router.dart` | First-launch redirect swallowing new routes or invite links | Allow-list test for every pre-auth route with `isFirstLaunch` true; invite deep-link test (cold start). Only the named blocks change. |
| R3 | `lib/main.dart` | Invite link racing the router; acceptance before DOB | Keep `waitForRouterSettled` and the first-launch clear; acceptance moves to RI-3; the server age check is the backstop. |
| R4 | `OnboardingStore` | Renamed enums breaking decoding on test devices | Add keys, rename none; migrate the legacy invite key once. |
| R5 | `users` grants | The onboarding upsert failing after the grant change | Client change and grant migration ship in the same release (W1a); the `onboarding_profiles.mode` drop ships with the client that stops writing it (W1b); contract proves `UPDATE (display_name)` still works. |
| R6 | `profiles` guard | Breaking location, quiz or profile writers, or definer functions that write `profiles` | Guard touches only `banned_until`, `confirmed_violation_count` and deletes of a profile with strikes or a ban; it acts only for `current_user IN ('authenticated','anon')`, so definer functions (`complete_sign_up`, `set_user_path_internal`) and the service-role moderation function pass; tests for a location write, a profile upsert that doesn't name the two columns, and a delete of a clean profile, all as `authenticated`. |
| R7 | `onesignal_service.dart` | Couples never asked for push | R4 inline ask; legacy keeps the old ask; re-test chat push, Safety-lock suppression and sign-out release (`test/features/auth/auth_sign_out_push_test.dart`). |
| R8 | `accept-invite` | Behaviour drift in error texts the app parses | `index.test.ts` cases kept; new cases for each code; the "You're already in a relationship" prefix pinned. |
| R9 | `export_relationship` / `export_bundle` | Re-creating from a stale body would drop the stories export order | Re-create from the latest body found by `grep -l` at build time (today `20261024100700`); `data_export_contracts.sql` and `story_export_contracts.sql` must stay green. |
| R10 | Opinions writer RPCs | A stale body re-created | Same rule; the diff against the previous body must be exactly one added line per function. |
| R11 | `app_shell.dart` root clamp | Every screen reflows | Last step of W10, behind `text_scale_v2`, after the audit. |
| R12 | Access-token hook | A bug locks everyone out | Unexpected errors return the event unchanged and are counted and alerted (S-8); a contract test feeds malformed events; production enable waits for the W6 gate. |
| R13 | `storage.objects` trigger | Uploads blocked; the trigger can't be created on hosted Supabase | F-1 spike on the development project before W7b, with the sweep fallback; exception-guarded insert; a contract test makes the queue insert fail and proves the upload row still lands. |
| R14 | Send SMS Hook | One provider outage stops all sign-ins | Ordered routes with failover, voice and WhatsApp alternatives, `otp:unavailable` copy; real-carrier tests gate switch-on. |
| R15 | Games | Accidental edits | §1.5; a CI check that the diff touches no file under `lib/features/games/` and leaves `auth_exports.dart` byte-identical. |
| R16 | Formatting | Noisy diffs | `dart format` on new files only. |
| R17 | `chat_couples_locked_screen.dart` | Removing the Dating button breaks the invite buttons around it | Only the `if (_invite == null) ...[Gap, AppButton]` block for the Dating button goes; a widget test finds no "Meet someone in Dating mode" with the flag off and on, and the invite buttons still work. |
| R18 | `quick_exit_service.dart` | A new wipe stalls quick exit (the 2026-10-14 lesson: an unmocked `SharedPreferences` call never completes in tests), or clears a protective setting | One fire-and-forget registry call after the cover is up; every entry has its own `try` and a bound; quick-exit tests mock every channel and prefs; a test proves the Dating lock, the Safety PIN and the discreet-icon choice survive quick exit; the existing Together, map and Stories calls are untouched. |
| R19 | `auth_provider.dart` sign-out path | A wipe delays or breaks sign-out; Games reach this file's providers through the `auth_exports.dart` barrel | The registry runs inside the existing side-by-side `wipe()`, bounded (3 s total) and never throws; `SignOutHooks`, the push release and `auth_exports.dart` don't change; `test/features/auth/auth_sign_out_push_test.dart` and a new sign-out wipe test stay green, and so do the Games tests. |

### 5.7 Files shared with Spec 3 (forum removal lands first)

| File | Spec 3 | Spec 1 |
|---|---|---|
| `lib/app/routing/app_router.dart` | removes forum imports and routes | adds §5.4 routes and the redirect allow-list |
| `lib/core/notifications/config/notification_config.dart` | forum taps → home | adds `journal_reminder` |
| `lib/features/onboarding/presentation/widgets/profile_setup_step.dart` | subtitle line 22 | legacy only; v2 uses A1 |
| `lib/features/auth/intro/intro_screen.dart`, `login_profile.dart` | none (carousel via registry) | LoginProfile copy; Welcome replaces Intro under the flag |
| `lib/features/opinions/presentation/screen/opinions_tab.dart`, `create_content_chooser.dart`, `create_content_fab.dart` | removes the Forums layer | nothing (W9a/W9b edit the compose and thread screens) |
| `lib/app/documentations/user_manual/data/manual_documentation_registry.dart`, `chat_docs.dart` | unregisters `ForumDocs`; one string | registers new topics; "copy without forums" becomes Spec 3's architecture test passing |
| `lib/i10n/app_*.arb` | `mutedItemSubtitle` | new keys |
| `test/widget_test.dart`, `test/core/notifications/notification_tap_routing_test.dart` | forum imports and cases | home-shell expectations; reminder tap |
| `forum_reports`, `private.assert_can_post`, `admin_confirm_content_removal` | W3 removes forum branches (from the live body) | W9b changes the report reasons, the two report RPCs, and `admin_confirm_content_removal` (re-created from its live body with the two notices restored and nothing else changed); no rename, no forum-branch removal. Spec 3 W3 then rewrites that function from the new live body, so it keeps the notices. |
| `supabase/functions/process-scheduled-notifications` | allow-list until forum rows are gone | no new payload keys |
| `ATTUNE_MASTER_SPEC.md` | hands over "Forums retired 2026-10, Spec 3" | W10c applies it with the Q20 amendments |
| `lib/architecture/FORUM.md` | banners (§5 included) | **nothing**: FORUM.md belongs to Spec 3 (review C-9) |

### 5.8 The device wipe registry (W3a; controller ruling C-2/C-3, D19)

One generic, ordered list of "things to remove from this phone", run on two moments. Spec 1 owns it and the two call sites; other features only register entries.

- **File:** `lib/core/device/device_wipe_registry.dart`. `enum WipeMoment { signOut, quickExit }`. `DeviceWipeRegistry.instance.register(DeviceWipeEntry(id, order, moments, run, bound))`: `id` unique (a duplicate is refused in debug and ignored in release), `order` an int (lower runs first), `moments` a non-empty set, `run` a `Future<void> Function()`, `bound` at most 2 s (default 1 s).
- **Running:** `run(moment)` takes the entries for that moment, groups them by `order`, and runs each group side by side; every entry runs inside **its own `try`** with `.timeout(bound)`, the way the stories Wave 2/4 wipes do, so one failing or hanging entry never skips another. The whole run is bounded at 3 s and never throws.
- **Call sites (the only edits to the shared files):** quick exit calls it fire-and-forget after the cover is up and after the existing Together, map and Stories calls (§5.2). Sign-out calls it inside `AuthOperations.signOut`'s side-by-side `wipe()` and in `safetySignOut`'s fallback. Nothing else in those files changes.
- **Registration:** `registerDeviceWipes()` in `lib/app/device_wipes.dart`, called once from `main.dart` at boot. Each feature keeps its own register function in its own folder; the bootstrap file has one line per feature. **Spec 2 adds exactly one line there (`registerDatingDeviceWipes()`) and never edits `quick_exit_service.dart` or `auth_provider.dart`.**
- **Protective settings never wipe on quick exit:** the Dating lock (`me_section_lock`), the Safety PIN and the discreet-icon choice. `register()` refuses (debug assert, release ignore) an entry tagged `protective: true` whose moments include `quickExit`, and a test lists every quick-exit entry and checks none of them touches those keys.
- **Spec 1's entries:**

| Id | Wave | Moments | Removes |
|---|---|---|---|
| `spec1.home_state_cache` | W3a | sign-out | `attune.home.<uid>.state` |
| `spec1.dating_lock` | W3b | sign-out only (`protective: true`) | `me_section_lock` |
| `spec1.partner_first_name` | W4b | sign-out | `attune.flow.<uid>.partner_first_name` |
| `spec1.ask2_progress` | W4b | sign-out, quick exit | every `attune.ask2.<uid>.*` key |

- **Tests (W3a):** `test/core/device/device_wipe_registry_test.dart` (order, own try per entry, bound, duplicate ids, the protective rule); a sign-out test that a registered entry ran and that the four existing wipes and the push release still ran; a quick-exit test with mocked prefs and channels that the registry ran, quick exit still exited, and the lock survived.

---

## 6. Safety and privacy

1. **Age, in layers.** A neutral DOB for everyone before the phone; platform age signals where they exist (stricter wins); a server refusal that writes nothing; an age and phone check on both sides of an invite; a whole-account hold for a self-confessed minor. A typed DOB never unlocks Dating (Spec 2 verifies). Residual: an adult-typing minor can still link with a partner who lies too (09 P17); CSAM matching and "Report a concern about a child" are the backstops.
2. **Identity can't be rewritten from the phone.** `users.phone` is mirrored from Auth; `banned_until` and the strike count `confirmed_violation_count` can't be changed by their owner, and a profile with strikes or a ban can't be deleted and re-created (S-1); the path is server-written; the DOB is write-once with one supervised correction; a client can bump only exact, listed metric keys (S-2); a stranger who knows a number can't move its sign-in code off SMS (S-3).
3. **Recycled numbers.** No token for a dormant account; a fresh start parks the old account (no sessions, no number) for 180 days of support-only recovery. Residual: a SIM swap on an active number isn't caught here; the new-device notice and "Sign out all other devices" (existing) and Spec 2's new-device Dating re-verification cover it. A stranger on a recycled number inherits the old owner's former-partner exclusion (never introduced to that one person), accepted as harmless. The parked account keeps the real number's HMAC (`parked_phone_hmac`), so the old owner's Dating restrictions and blocks are carried over at the purge under the real number, not lost to the `+999…` placeholder (I-11). Whether **live** Dating restrictions also follow the number to the fresh account is open (§10 O3).
4. **No enumeration.** A code is always sent first; the inviter's name only after sign-in, rate-limited; support never confirms an account.
5. **Silence.** No push, feed or signal tells anyone about a path switch, a profile edit, an invite cancellation, a report or a hold. `profiles.relationship_status` is not re-synced (§1.4 D14). The journal reminder push is neutral.
6. **Crisis routing never depends on an LLM.** The journal check is the hard-coded `self_disclosure` corpus, runs before any provider, never blocks writing, persists nothing and shows the card only to the writer. The Opinions "Need support now?" link is always there, whatever anyone types. An at-risk report goes to a person, never to the author automatically.
7. **CSAM.** Hash matching on every image upload bucket (dating photos inline in Spec 2's pipeline, every other bucket through the scan queue, one shared match path); a match quarantines, removes, holds the account and escalates to a named person; no automatic report without that person; the partner is never told. Escalation runbook (NCMEC / IWF / Ghana CSA / local police per counsel) is a W7 gate.
8. **Sign-in seam (Q18).** The phone stays the anchor. Any later method is linked from a signed-in account only (Supabase `linkIdentity`), never used to create an account; a phone stays required for couples invites and Dating. `AuthService`'s Apple and Google methods stay as they are, unused; no screen offers them.
9. **What Spec 1 doesn't collect:** gender or pronouns at sign-up, contacts, GPS, a couple "issues" question, children's names or counts, reasons for an ending, the SIM serial, the IP history, any platform age signal.
10. **Country gates outside the code** (they block a country's listing, not a wave): UK Online Safety Act illegal-harms and children's-access assessments (UK counsel); Ghana Data Protection Commission registration (owner); the DPIA (privacy counsel; Spec 1's parts: DOB, journal, CSAM scanning of private uploads, which the privacy policy discloses); the US app-store age laws (Texas in force; covered by W6).

---

## 7. Testing strategy

### 7.1 SQL contracts (local `attune_spec3a`, never `attune_test`)

**Non-destructive steps only (review A-1, controller ruling).** `scripts/local_pg_setup.sh` runs `dropdb`/`createdb`, so this spec **never** runs it, and never runs `scripts/local_pg_grants.sql` against `attune_spec3a` either (it blanket-grants tables and would undo a deliberate `REVOKE`). On `attune_spec3a`, apply each new migration and then its grants twin, one file at a time, and run contract files the same way: `psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f <file>` (Spec 3's procedure). The from-scratch build is CI's `sql-contracts` job; `local_pg_grants.sql` and `local_pg_table_privileges.py` are still **edited** (§4.1) so that build matches production. Record the pass/fail baseline of every contract file on `attune_spec3a` before W1a; no wave may add a failure. Every assertion checks the **specific** error text (never `WHEN OTHERS`); fixtures use a dedicated phone range per file (`+1555 81xx…` for W1, `82xx` W4, `83xx` W5, `84xx` W6, `85xx` W7, `86xx` W9, `87xx` W2) and set `auth.users.phone` as well as `public.users.phone`; ordering inside one `DO` block uses `clock_timestamp()`.

| File | Wave | Proves |
|---|---|---|
| `identity_foundation_contracts.sql` | W1a–W1c | as `authenticated`: `UPDATE users SET phone/mode/path/eula_version` → 42501; `UPDATE display_name` works; `complete_sign_up` under 18 → `signup:not_eligible` with **zero** rows in `users`, `profiles`, `account_birthdates`; replay idempotent; phone taken from `auth.users`, not input; second `set_my_birth_date` → `birth_date:already_set`; `account_age` not executable by `authenticated`; `place_account_hold(user, 'age_review')` with two arguments works; `set_my_path` errors (`path:relationship_open`, `path:confirm_withdraw`, `path:confirm_pause_dating`, `path:needs_signup`); `path_previous` and withdraw-with-return; Dating → Just for me makes **no** `pause_dating_for_relationship_user` call, Dating → Relationship makes exactly one (D18); `get_my_home_state` link states (six fixtures), `tab` mapping and the `dating` summary; **`profiles` guard (S-1):** as `authenticated`, UPDATE of `banned_until` → `profile:moderation_column`, UPDATE of `confirmed_violation_count` (to 0, and to any other value) → `profile:moderation_column`, INSERT with a ban or a count → both stored as NULL / 0, DELETE of a profile with a count above 0 → `profile:moderation_locked`, DELETE of a profile with a future ban → `profile:moderation_locked`, DELETE of a clean profile allowed; a definer function and the service role may write both columns; a location update and a profile upsert that doesn't name the two columns are allowed; **metrics (S-2):** `bump_metric` as `anon` with a signed-in-only key → no row; with an unlisted key (`signup_completed`, `invite_accepted`, `x_y`) → no row, as `anon` and as `authenticated`; with a listed key → one increment; `bump_metric_server` and `private.bump_metric_internal` not executable by `anon` or `authenticated`; past the daily cap a new key isn't created and `metric_cap_reached` moves; **flags and environment (R-6, R-7):** `private.attune_environment()` reads `development` unset, `production` set, `production` for a typo (each with `set_config` inside the test transaction); with the environment `production` and no evidence, enabling `journal_ai_insights` → `flag:gate_evidence_required`, while an ungated flag and any write in development pass; `production_flag_violations()` lists a gated flag that is on; `private.assert_development_project()` raises `env:not_development` in production and for a non-development `supabase_url`; effective flags follow the dependencies; `get_public_app_config` returns only the listed keys to `anon`, and `dating_open_countries` comes through the seam; **no function body writes `users.mode`** and **no W1 function body names a W5 or W6 table** (`pg_proc.prosrc` scans) |
| `otp_delivery_contracts.sql` | W2c | per-number and per-prefix limits, `+999` blocked; **intents (S-3):** a fresh single-device intent sets the channel; an intent older than 60 s → `sms`; two device hashes for one number in 10 minutes → `sms`; the 7th intent in an hour isn't stored and the send is `sms`; no intent → `sms`; purge; no client grants |
| `journal_reminder_contracts.sql` | W3c | own-row only; enqueue once per local day; neutral payload |
| `invite_v2_contracts.sql` | W4a | each refusal code; **the acceptor's own pending invites are gone in the same transaction**; a forced failure after the update rolls everything back; idempotent re-accept; path set; preview rate limit; the inviter-age check; the retention cron deletes only old attempts |
| `couple_profile_contracts.sql` | W5 | member read; outsider, sealed and archived denied; paused and window read-only; every validation; attribution per field; signal bump; draft survives a withdrawal; draft adoption order; **a switch to Dating deletes the draft** (re-created `set_user_path_internal`, I-6); anniversary reminder created, moved, deleted; export section present and uuid-free; `get_couple_profile` has no `suggested_dates` key; **never a type or score** (below) |
| `dormancy_contracts.sql` | W6a, W6b | hook: dormant OTP → `account_dormant:` + challenge; a dormant account's refresh passes (same device); recent account passes; each hold kind, including `recovery_hold` on a refresh → `account_review`; malformed event returns unchanged **and writes one `auth_hook_failures` row**; executable only by `supabase_auth_admin`; nonce single-use and 15-minute expiry; **`consume_fresh_start` writes `parked_phone_hmac` equal to `dating_phone_hmac('+' || digits)` of the real number before any phone change** (I-11); correction rules (W6b) |
| `child_safety_contracts.sql` | W6c | insert through RPC only; 5-per-day limit; no client read |
| `support_resources_contracts.sql` | W7a | anon read; emergency first; no write grants |
| `media_scan_contracts.sql` | W7b | trigger (or sweep) enqueues only listed buckets, **never `dating-profile-photos`**, and only with the flag; a failing queue insert doesn't block the upload row; a queued match and an inline match (`record_inline_csam_match`) each give exactly one hold and one escalation through the same path; an inline match twice for one object is idempotent; no client access to queue, escalations or quarantine |
| `opinion_filter_contracts.sql` | W9a, W9b | the shared goldens (`supabase/tests/fixtures/unicode_normaliser_goldens.json`, loaded with `\set`) through both the base and the match form; the migration's `translate()` strings equal the fold table; each of the six writers refuses with `content:contact_info` / `content:slur` / `content:explicit`; years like "1999 2004 2010" pass; a Twi term matches typed with ɛ/ɔ and with e/o; flag off → all allowed; the at-risk reason is valid, priority and doesn't move `report_count` (W9b); review queue is service-role only (W9b) |
| `opinion_moderation_notice_contracts.sql` | W9b | as service role: removing an opinion queues exactly one `forum_content_removed` row for its author with `opinion_id`; a comment, one with `comment_id`; removing already-removed content queues nothing; the third confirmed removal queues one `forum_posting_banned` row with the new-ban body; a further removal during the ban queues the extended body and moves `banned_until` forward, never back; `authenticated` calling the function → 42501; the counts and ban dates match the live behaviour exactly, **with the W1a guard in place** (the service-role writer still moves both columns). **Reaches strike 3 (OPN-BAN-42702):** a fixture author with two confirmed removals gets a third removal as service role; it must not raise 42702, must return `(3, banned_until)`, must leave `profiles.confirmed_violation_count = 3` and `banned_until` about 7 days ahead, and must queue the `forum_posting_banned` new-ban notice; a fourth removal during the ban moves `banned_until` forward by 7 days from the existing ban, never back. The "exactly the live behaviour" clause covers strikes 1 and 2 only; strike 3 raises today, which is the bug |
| `opinion_remove_own_contracts.sql` | W9b | (OPN-DELETE-RLS) as `authenticated`: the author's `remove_my_opinion` sets `removed_at`, and the opinion drops out of `get_discover_opinions` and the tag and following reads; the author's `remove_my_comment` sets `removed_at` and lowers the parent's `comment_count` by exactly 1; a second call changes nothing and does not decrement again; another user's call changes nothing for either (row and count unchanged); a call as a banned author still works; as `anon` → 42501; `comment_count` never goes below 0; a direct client `UPDATE … SET removed_at` by the author is still refused (the fix is the RPC, not a looser policy); the fixture phones use the `86xx` range |


**"Never a type or score" contract** (W5): `couple_profiles` has exactly the listed columns (`information_schema`); the only functions whose bodies mention `couple_profiles` are the allow-listed ones (`get_couple_profile`, `update_couple_profile`, `adopt_couple_profile_drafts`, `sync_anniversary_reminder`, `export_relationship`, and the purge path); no view selects from it; plus `test/architecture/couple_profile_never_typed_test.dart` scanning the repo so that `couple_profiles` and the Dart model appear only in allow-listed files, and never in `supabase/functions/**` AI loaders or prompt builders.

### 7.2 Deno tests

- `send-sms-hook`: signature check, channel routing, failover, WhatsApp and voice failure → SMS, a decision of `sms` never uses another channel, the two message shapes, `+999` refusal, no phone in logs.
- `otp-delivery-intent`: always 204 (stored or capped alike), IP limit, missing or malformed `device_nonce` refused with 204 and nothing stored, the nonce never logged.
- `accept-invite/index.test.ts`: every code mapped; prefix kept.
- `analyse-journal-entry`: with a spy on `callGeminiJson`, a matching entry never reaches it (flag on or off); flag off → `paused` and no call; `get_patterns` exclusion; the check runs before the cache read; the victimisation list runs only with `private_safety_check` on.
- `scan-media`: stub matcher match / clear / unavailable paths; quarantine copy before removal; with `get_attune_environment()` = `production` the stub clears nothing.
- `_shared/unicode_normaliser.test.ts`: the shared goldens give the same base and match forms as the SQL functions.
- `_shared/csam_match_path.test.ts`: quarantine copy happens before the record call, for both the queued and the inline entry point.

### 7.3 Flutter unit and widget tests

- Validators: DOB (each error, leap years, locale order), name (scripts, length), phone default country (SIM, region, none), resend ladder, content-filter error mapping, `LinkState` mapping, path → tab mapping.
- Screens: every new screen at 1.0, 1.3 and 2.0 (goldens) and under RTL; semantics labels found with exact finders; tap targets and contrast guidelines; reduce motion replaces steps with the 150 ms fade; X1, DM1, H1 and consent have no animation.
- Device wipes (§5.8): the registry test; sign-out runs every sign-out entry and the existing wipes; quick exit runs the quick-exit entries, still exits, and the Dating lock, Safety PIN and icon choice survive; no Spec 1 prefs key or value contains "dating" after a Dating-path session (the S19 allow-list, §5.5); a Dating path choice offline isn't queued.
- Flows: first launch → Welcome allow-list; G1 → guest Opinions; A1–A5 resume at A4 after a restart; under-18 at A2 writes nothing and sets the block; existing account discards the draft; N1; RI-1 → RI-3 → R4; scoped invite claim (24 h window, two accounts on one phone); day-7 "Send a new invite"; Dating never rendered on the Relationship path (all five link states), and no "Meet someone in Dating mode" on `ChatCouplesLockedScreen` with `flow_paths_v2` off or on; "More ways" hidden in the window; How you use Attune confirmations; About us edit and attribution line; journal support card; "Need support now?" in compose and menus.
- Existing tests that must stay green unchanged: `test/home/*` (extended, not rewritten), `onboarding_pending_sync_test.dart`, `relationship_mode_sync_test.dart`, `couples_waiting_step_test.dart`, `login_profile_test.dart`, `phone_number_field_test.dart`, `test/accessibility/large_text_test.dart`, `universal_bubble_test.dart`, every games test.
- Commands: `flutter test`; analyzer on touched files only, filtered with `grep -E "^\s*(error|warning) "`.

### 7.4 Mutation checks (each must turn a test red with the expected message)

| Mutant | Caught by |
|---|---|
| `GRANT UPDATE (phone)` on `users` | identity contract |
| Drop `confirmed_violation_count` from the `profiles` guard (or let a client DELETE a profile with strikes) | identity contract (S-1) |
| `GRANT EXECUTE ON bump_metric_server TO anon`, or let `bump_metric` accept any key under a prefix | identity contract (S-2) |
| `otp_take_send_decision` uses the newest intent regardless of device or age | OTP contract (S-3) |
| Re-add the `couple_profile_drafts` delete to the W1 body of `set_user_path_internal` | identity contract (W1 prosrc scan, I-6) |
| Re-add `dating-profile-photos` to the scan trigger's buckets | media contract (I-10) |
| Let `private.assert_development_project()` pass when the environment reads `production` | identity contract (R-6) |
| Register a quick-exit wipe of `me_section_lock` | registry test (D19) |
| Remove the age check in `complete_sign_up` | identity contract (zero-rows assertion) |
| Remove the withdrawal statement in `accept_relationship_invite_v2` | invite contract |
| Accept before RI-3 in `OnboardingGate` | flow widget test |
| Remove the `self_disclosure` call or move it after the cache read | Deno spy test |
| Comment out `assert_opinion_content_ok` in one writer | filter contract (per writer) |
| Count at-risk reports toward `report_count` | filter contract |
| Remove either restored `enqueue_forum_notification` call | moderation-notice contract |
| Add a function that reads `couple_profiles` into a label | never-typed contract |
| Hook returns the event for a dormant OTP | dormancy contract |
| Drop the exception guard in `enqueue_media_scan` | media contract |
| Show the Dating slot on `RelationshipSpaceScreen` | widget test |
| Animate X1 | reduce-motion / no-animation test |

### 7.5 Device checklist

- Real-carrier codes by SMS, WhatsApp and voice: MTN, Telecel, AirtelTigo (Ghana); EE, Vodafone, O2 (UK); a US and a Canadian carrier; a dual-SIM Android with WhatsApp on the other SIM.
- Android SMS Retriever autofill with the release signing key's hash; iOS code autofill from SMS and from the WhatsApp notification.
- TalkBack and VoiceOver through A1–A6, R1, RI-3, About us, X1; 200% system text; an Android Go phone (2 GB); three OEMs (Samsung, Tecno/Infinix, Pixel).
- Airplane-mode cold start with an expired session (first-frame time).
- Install Referrer on a clean Android install from the invite page.
- Under-18 block across reinstall (iOS Keychain; Android only after a backup has run).
- Declared Age Range and Play Age Signals in **release** builds (iOS 26 device for Declared Age Range; an iOS 18 device to prove the weak-linked path returns `unavailable`).
- On the development project (W6a): the hook's refusal text reaches the client at code sign-in (`account_review`, `account_dormant:<nonce>`), and a phone verify reports `authentication_method = 'otp'` to the hook (review F-2).
- Recycled number on the development project: age an account's activity past 180 days, sign in on another phone, DM1 → fresh start → new account; the old account unreadable and parked.
- Journal: a crisis phrase shows the card and no AI note; Opinions: a phone number, an email and a `[DRAFT]` slur are refused with their reasons.

---

## 8. Waves (9 groups: W1–W7, W9, W10; W8 held for the deferred Opinions redesign)

Each group is split into lettered sub-waves of about 3–4 tasks (review W-1, W-3). "S1 W9" or "S1 W10" without a letter means the whole group, so every existing citation in Spec 2 and Spec 3 stays valid.

**Default order:** Spec 3 W1–W2 → **W1a → W1b → W1c → W2a → W2b → W2c → W3a → W3b → W3c → W4a → W4b → W5 → W6a → W6b → W6c → W7a → W7b → W9a → W9b → W9c → W10a → W10b → W10c** → Spec 2. Because migration timestamps are assigned when a wave is built (§4.7), any order that respects each sub-wave's "Depends on" line is valid. For example, W6a can run straight after W2c, and W7b straight after W1c. Development (the current project, Q19b) turns every flag on as each wave lands. **No wave turns anything on in production;** each gate line is what must be true first, and the production flag gate (§2.5) enforces it for the flagged waves.

**W1a · Users and profiles lockdown**
- Contents: migration 1 (`identity_users_lockdown`), including the `profiles` guard for `banned_until` **and** `confirmed_violation_count` (S-1); the five dating functions re-created without `users.mode`; the client stops writing `users.phone` and `mode`; both invite functions' `ensureUserRow` fix. Grants, client and edge changes ship in one release.
- Depends on: Spec 3 W2 (order, not need).
- Tests: the W1a part of `identity_foundation_contracts.sql` (grants, guard, no `mode` writer); the S-1 mutant; full SQL and Flutter suites at baseline.
- Gate: **none** (security fixes ship unflagged).

**W1b · Metric storage, birthdates, holds, paths, home state**
- Contents: migrations 2–4 (`metric_counters` with the exact-key client surface, S-2; `account_birthdates_and_holds`; `paths_and_home_state`); the client stops writing `onboarding_profiles.mode`; `HomeState` model and `HomeStateStore` (tab layout only, D20).
- Depends on: W1a.
- Tests: the W1b part of the identity contract (sign-up, DOB, holds, paths, home state, metrics, D18 pause rule, W1 prosrc scan); the S-2 and I-6 mutants; `HomeState` unit tests.
- Gate: **none.**

**W1c · Environment, flags, public config, health, Journal pause**
- Contents: migrations 5–6 (`spec1_flags_and_public_config` with the environment helper, the dev-project guard, the production flag gate and the D15 seam; `identity_health`); `purge-unfinished-signups`; the Journal pause in `analyse-journal-entry`; the scoped invite key; `public_app_config` and `metric_counter` clients (effective flags); `supabase/sql/dev_enable_spec1_flags.sql` (guarded, never sets the environment).
- Depends on: W1b.
- Tests: the W1c part of the identity contract (environment, gate, seam, guard); Deno pause test; scoped-key unit tests.
- Gate: **none.** It is not "no visible change" (review A-5): with `journal_ai_insights` off, `analyse-journal-entry` returns `paused` and **Journal Gemini insights stop wherever the flag is off**. On the development project the dev script turns the flag on, so nothing changes there. On a production project they stay off until the W9c gate. The release note says so.

**W2a · Foundations and the first screens**
- Contents: motion tokens; `SharedAxisStep`; `AllowLargeText`; router first-launch allow-list; WL1 Welcome and previews (the open-country line from the D15 seam); G1; X1 (backed-up file + Keychain).
- Depends on: W1c.
- Tests: allow-list and cold-start invite tests; goldens at three scales and RTL; X1 no-animation test.
- Gate: the W2 group gate (under W2c).

**W2b · Sign-up steps**
- Contents: A1–A5 and N1 over Supabase's built-in SMS; the sign-up draft store (with `device_nonce`); validators; EULA v2; `PendingSignUp` replay; LoginProfile copy; SIM country.
- Depends on: W2a.
- Tests: validator and flow tests (resume at A4, under-18 writes nothing, existing account discards the draft); goldens.
- Gate: the W2 group gate.

**W2c · Phone codes**
- Contents: migration 7 (`otp_delivery`, with the S-3 intent rules); `otp-delivery-intent`; `send-sms-hook` with failover and SMS fallback; the one labelled code field with autofill (`smart_auth`, `webcredentials`); WhatsApp and call options in A3/A4.
- Depends on: W2b.
- Tests: `otp_delivery_contracts.sql`; Deno hook and intent tests; autofill widget tests.
- **W2 group gate (before `flow_signin_v2` in production):** **SMS, voice and WhatsApp providers contracted (owner); MTN alphanumeric sender ID registered; Meta authentication template approved; real-carrier tests pass in Ghana, the UK, the US and Canada; the A5 AI line checked by the owner and privacy counsel; EULA v2 text approved by counsel; `webcredentials` added to the invite domain's association file (owner, `attune-invite-web`); store listing (S0) updated.**

**W3a · Home state and the keyed shell**
- Contents: `homeStateProvider`; path-aware `HomeScreen` (latch untouched, keyed by tab layout; `test/home/*` extended **first**, N-2 included); A6; the device wipe registry with its call sites in `quick_exit_service.dart`, `auth_provider.dart` and `safety_sign_out.dart`, and the home-state cache entry (§5.8, C-2/C-3).
- Depends on: W2b.
- Tests: home tests (latch once, legacy `needs = [birth_date]` once, tab mapping, keyed rebuild); registry, sign-out and quick-exit tests.
- Gate: the W3 group gate (under W3c).

**W3b · Relationship space, Me and the Dating slot**
- Contents: `RelationshipSpaceScreen` states; `MeHomeScreen` (J1, J4, Healing copy); the Dating slot (no Dating RPC, I-4) and the Dating lock (`me_section_lock`, sign-out-only wipe entry); the "Meet someone in Dating mode" button removed from `chat_couples_locked_screen.dart` unconditionally (R-5). No Relationship-home card slot: the 30-day Dating card is Spec 2 W9's, on `ChatHomeScreen`'s conversations home cards list (controller ruling C-4).
- Depends on: W3a.
- Tests: "never Dating on the Relationship path" (all link states, flag on and off); slot and lock widget tests; the lock survives quick exit.
- Gate: the W3 group gate.

**W3c · Switching, push asks, reminders**
- Contents: Settings → How you use Attune with every confirmation; contextual push asks (`onesignal_service.dart` regression pass); J3 and journal reminders (migration 8); the `journal_reminder` tap; manual topic.
- Depends on: W3a.
- Tests: `journal_reminder_contracts.sql`; push-policy tests; switching widget tests.
- **W3 group gate (before `flow_paths_v2` in production):** **Spec 2 W2's path trigger is live, so Dating → Just for me pauses Dating (D18).** Nothing else.

**W4a · Invite server**
- Contents: migration 9 (`accept_invite_v2`, with its retention cron); `accept-invite` rewrite; inviter age check in `create-relationship-invite`.
- Depends on: W1b.
- Tests: `invite_v2_contracts.sql`; `accept-invite` Deno tests.
- Gate: the W4 group gate (under W4b).

**W4b · Couples flow on the phone**
- Contents: R1 registers with the code in every message; "My partner already invited me"; RI-1 to RI-4; R2, R4; day-7 "Send a new invite", day-30 line, "on my own"; Install Referrer; Ask 2 saves as it goes; the partner-name and Ask 2 wipe entries.
- Depends on: W4a, W3b.
- Tests: invitee flow tests; cold-start deep-link test; Ask 2 resume and wipe tests.
- **W4 group gate:** **the cultural reviewer confirms the Pidgin register** (until then only Simple and Casual are offered). Regression: `main.dart` invite deep link.

**W5 · About us** (one wave: about 4 tasks)
- Contents: migration 10 (profiles, drafts, RPCs, signal, anniversary sync, draft adoption, export, the `set_user_path_internal` draft delete, I-6); AU1–AU6 flow; About us screen and card; "Changed by" line; Together's anniversary single source; `MyDateFormat.toMonthYear` / `toYear`; manual topic.
- Depends on: W4a, W3b.
- Tests: `couple_profile_contracts.sql` including never-a-type-or-score; `data_export_contracts.sql` updated for `about_us`; widget tests.
- Gate: **the Ghanaian cultural reviewer confirms the stage options and helper text (engaged, married, ceremonies, labels).**

**W6a · Holds enforced, recycled numbers**
- Contents: migration 11 (`account_dormancy_and_fresh_start`: the access-token hook with fail-open counting, `parked_phone_hmac`, `get_identity_health` re-created); DM1–DM2 and `start-fresh-account`; `purge-recovery-holds`; `identity-health-alert`; H1.
- Depends on: W2c, W1b.
- Tests: `dormancy_contracts.sql`; the F-2 checks and the recycled-number path on the development project.
- Gate: **DV specialist reviewed DM1, DM2 and H1; the owner confirms the plan offers both hooks; both auth hooks enabled in production only after the same run passes on the development project.**

**W6b · Age signals and DOB correction**
- Contents: migration 12 (`birth_date_correction`); platform age signals at A2 (Declared Age Range weak-linked, iOS 26 SDK; Play Age Signals); under-18 block hardened; DOB correction in Settings.
- Depends on: W2b.
- Tests: age-signal channel unit tests with fakes; correction rules in `dormancy_contracts.sql`; release-mode device checks.
- Gate: **Play Restrict Minor Access on and 18+ ratings set in both stores (owner); Apple Declared Age Range entitlement granted (owner).**

**W6c · Child safety**
- Contents: migration 13 (`child_safety_reports`); "Report a concern about a child"; real support and child-safety addresses; CSAE page content (§8.1).
- Depends on: W1c.
- Tests: `child_safety_contracts.sql`; widget tests.
- Gate: **CSAE standards page published and linked in Play Console, with a named child-safety contact (owner).**

**W7a · Support resources v2**
- Contents: migration 14; `support_resources_v2_screen` (country line and picker, emergency first, tap-to-call confirmation "Call {number}? Calls may show in your phone's call history.", categories, "Not the police" tag, unsupported-country fallback "We don't have a checked list for {country} yet." + "Find a helpline" + "In an emergency, call your local emergency number.", offline catalogue); the Healing grief branch; youth link on X1; release check `test/launch/support_resources_release_test.dart` (fails when a Tier A country's entry in the bundled catalogue is older than 90 days, or 7 days on a release tag).
- Depends on: W3b, W2a.
- Tests: `support_resources_contracts.sql`; release check; widget tests.
- Gate: **resource entries verified per country — Ghana, UK, US, Canada with every category (emergency, dv, crisis, sexual_assault, sextortion including CSA 292 and StopNCII, child_safety, youth, lgbtq_legal, grief, perinatal) within 7 days of release; every other country's emergency number and the international directory — by the DV professional and the cultural reviewer; clinician reviews the grief branch copy.**

**W7b · Image safety**
- Contents: **first, the F-1 spike** on the development project (create and drop a no-op trigger on `storage.objects`; record the result); migration 15 (`media_scan`, with the trigger or the sweep fallback, `dating-profile-photos` excluded, `record_inline_csam_match`); `scan-media` (stub refused in production), `csam_matcher.ts`, `csam_match_path.ts`, quarantine, escalations.
- Depends on: W1c.
- Tests: `media_scan_contracts.sql`; Deno scanner and match-path tests.
- Gate: **CSAM hash-vendor eligibility and contract (PhotoDNA, Google Content Safety API or Thorn Safer; owner); escalation runbook approved by counsel; the named child-safety contact receives escalations.**

**W8 · held empty** — the Opinions redesign (Q9, deferred).

**W9a · Shared normaliser and the pre-post filter**
- Contents: migration 16 (`opinion_content_filter`: base and match forms, digits, terms table, verdict, assert, six writers); the shared fold table, TS port and goldens (I-17), which Spec 2 W6 imports; inline filter errors with the draft kept: "Phone numbers, emails, links and usernames can't go in Opinions. They can identify you or someone else. Take it out and post again." / "This includes a word that attacks people for who they are. Opinions doesn't allow it." / "Opinions doesn't allow sexual content. You can describe what happened without explicit words."; the `opinion_blocked:{reason}` client count.
- Depends on: W1c; Spec 3 W1 (the Opinions shell).
- Tests: `opinion_filter_contracts.sql`; `unicode_normaliser.test.ts`; widget tests.
- Gate: **the cultural reviewer supplies and signs the slur and explicit lists (including Twi, Ga, Ewe, Hausa and Pidgin) and local number words.** `opinions_safety_v1` may be switched on in production only after this gate and W9b's (its gate row, §2.5).

**W9b · At-risk reason, review queue, restored notices**
- Contents: migration 17 (`opinion_at_risk_and_review_queue`); "Need support now?" in compose and every post and comment menu (→ Support); the reason "Someone may be at risk" with the confirmation "Thank you. A person on our team will look at this soon. If someone is in danger right now, call your local emergency number." [See emergency numbers]; **the restored "Post removed" and "Posting paused" notices** (migration 18; not flagged, because it restores live behaviour lost in `20260802`); **two pre-existing Opinions bug fixes (below):** OPN-BAN-42702 inside migration 18 and OPN-DELETE-RLS as migration 19.
- **Pre-existing Opinions bugs fixed here.** Spec 3's W1–W2 final review found both on the live code. Neither was caused by Spec 3 and Spec 3 did not touch them, so they are Spec 1 W9 work under these ids (not "F-2" or "O-1", which collide with other review numbering):
  - **OPN-BAN-42702.** `admin_confirm_content_removal` raises 42702 (`column reference "banned_until" is ambiguous`) at the **third** confirmed removal, so the 7-day ban never applies and `banned_until` is never set. Cause: `RETURNS TABLE (violation_count int, banned_until timestamptz)` declares an OUT variable with the same name as the `profiles.banned_until` column, and the ban-extension `SELECT GREATEST(COALESCE(banned_until, now()), now()) + interval '7 days' …` (`20260802120000:254`) names the column bare. Strikes 1 and 2 never reach it. **Fix (migration 18):** W9b re-creates the function anyway; qualify the column (`p.banned_until` with a table alias) and keep the return shape. **Contract:** `opinion_moderation_notice_contracts.sql` must reach strike 3 (see Tests); today it would fail there. Spec 3's `forum_retirement_contracts.sql` section E deliberately stops at strike 2 for this reason, and is not edited.
  - **OPN-DELETE-RLS.** Deleting your own opinion or comment fails with `new row violates row-level security policy`. Cause: `deleteOpinion` and `deleteComment` (`opinion_repository.dart:113-118, 468-479`) do a direct client `UPDATE … SET removed_at = now() WHERE id = …`. That statement needs SELECT rights on the rows, so Postgres also checks the new row against the SELECT policies `opinions_public_read` and `opinion_comments_public_read` (`20260716120000:279-282, 311-314`, `USING (removed_at IS NULL AND hidden_pending_review = false)`). Setting `removed_at` makes the new row fail that check, even though `opinions_owner_update` / `opinion_comments_owner_update` allow the owner. It reproduces with every pre-W2 grant restored, so it is not W2. Live callers: `opinion_providers.dart:492` and `:1336`. **Fix (migration 19):** two owner-checked `SECURITY DEFINER` RPCs, `remove_my_opinion` and `remove_my_comment` (§4.3 W9b), and the repository calls them instead of the direct UPDATE; `deleteComment` also drops its separate `decrement_opinion_comment_count` call and its `opinion_id` pre-select. **No policy is loosened:** the SELECT policies are not edited, so removed content stays invisible and a direct client UPDATE of `removed_at` stays refused. **Contract:** `opinion_remove_own_contracts.sql` (§7.1).
- Depends on: W9a; W7a (the support target; without it the link opens today's screen).
- Tests: the W9b rows of `opinion_filter_contracts.sql`; `opinion_moderation_notice_contracts.sql` (now including strike 3); `opinion_remove_own_contracts.sql`; Spec 3's `retired_forum_push_routing_test.dart` stays green (both kept types land on home); widget tests.
- Gate: **a named daily reviewer works review queue v0.** With W9a's gate, this is what `opinions_safety_v1`'s production gate row records.

**W9c · Journal crisis check**
- Contents: the Journal `self_disclosure`-first check (victimisation list behind `private_safety_check`, A-4) and the writer card ("If things feel heavy right now, you don't have to carry it alone. Support is here if you want it." [See support] [Not now]); "Need support now?" in the journal entry menu.
- Depends on: W1c (the pause flag); W9b (the shared link widget).
- Tests: Deno journal tests (spy, order, flag); widget tests.
- Gate: **the clinician and the suicide-prevention reviewer sign the journal card and confirm the self-harm corpus. Only then may `journal_ai_insights` be switched on in production** (its gate row, §2.5).

**W10a · Large text**
- Contents: large-text audit with goldens at 1.0 / 1.3 / 2.0 in the order chat → Opinions → Together/Planning → Settings → Healing → journal, fixing truncation and overflow, checking `ScreenUtil` (`minTextAdapt`, the identity `fontSizeResolver`) and the iPad 1.25× cap; then the root clamp raised behind `text_scale_v2` to the **highest of 2.0, 1.6 or 1.3 at which every audited surface, including the in-chat game sheets, passes** (game routes keep 1.0 through `TextScalePolicy` route prefixes, checked by an architecture test against `app_router.dart`; no Games file is edited).
- Depends on: W1–W7, W9.
- Tests: golden suites; `large_text_test.dart` extended; architecture test for game route prefixes.
- Gate: the W10 group gate (under W10c).

**W10b · Motion, RTL, first frame, size**
- Contents: reduce-motion pass and the 900 → 320 ms deck advance; RTL pass on every Spec 1 screen; first-frame measurement and, if needed, the bounded boot; app-size measurement and budget.
- Depends on: W1–W7, W9.
- Tests: RTL tests; reduce-motion tests; size report.
- Gate: the W10 group gate.

**W10c · Dead code and doc amendments**
- Contents: dead auth code removed in a separate commit (`UsernameCreationScreen`, `VerifyEmailScreen`, `ForgotPasswordScreen`, `UpdatePasswordScreen`, `PasswordResetEmailSentScreen`, `LoginScreenOptions`, `EmailSignupAttempt` models, `SplashScreen`, `AttuneShell`; never `auth_exports.dart`, `AuthService` or `AuthUiService`). **Files this touches (review N-1):** `lib/core/utils/exports/export_screens.dart` (the `login_screen_options.dart` export at `:43`; `auth_exports.dart` re-exports this barrel to Games, so its bytes stay the same but its export surface shrinks) and `lib/features/profile/repositories/supabase_profile_repository.dart` (its `UsernameCreationScreen` reference). Before deleting, a grep proves no file under `lib/features/games/**` uses any removed symbol, and every Games test runs after. **Approved doc amendments (Q20), only these (review C-9):** `ATTUNE_MASTER_SPEC.md` (decisions 11, 18, 20, 21, 22, 23 and 25, §2 modes → paths, §8.8 Track A, §9, plus Spec 3's line "Forums retired 2026-10, Spec 3"); `lib/architecture/AUTH_ONBOARDING_ENGINE.md` (order, voice OTP, no Ask 2 preview); CR-06 §5.3 rule 6; and the `ATTUNE_SOUL.md:73` wording, which goes to the owner as a proposal and is never edited here. The Dating docs (`DATING_MODE_SPEC.md`, `DATING_CHAT_SAFETY_SPEC.md`) belong to Spec 2; `FORUM.md` §5 belongs to Spec 3.
- Depends on: W10a, W10b.
- Tests: Games tests; analyzer on touched files.
- **W10 group gate (before `text_scale_v2` in production):** **the device matrix (TalkBack, VoiceOver, 200% text, Android Go, three OEMs) passes on the chosen cap.**

### 8.1 CSAE standards page (content, published by the owner on barsopus.com, linked in Play Console)

Zero tolerance for child sexual abuse and exploitation; what is prohibited (CSAM, grooming, sextortion of minors, sexualised content involving minors); how Attune prevents it (18+ only, DOB gate, platform age signals, hash matching on uploads, human review); how to report (in the app: Settings → Safety → "Report a concern about a child"; by email to the child-safety address); what happens (review by a person within 24 hours, removal, account action, reports to the authorities with a duty or a route for them, evidence preserved as the law requires); the named child-safety contact (role and address); compliance with child-safety laws where Attune operates.

---

## 9. Regression risks

| Risk | Where | Mitigation |
|---|---|---|
| Sign-in redirect storm returns | `home_screen.dart` | Latch untouched; tests first (§5.6 R1) |
| A couple stranded on the waiting screen after their partner accepts | home state sync | `get_my_home_state` on launch, resume, sign-in and the resync signal; the stale-invite 409 path kept |
| Pre-auth routes bounce to `/intro` | router | Allow-list + tests |
| Onboarding writes fail after the `users` grant change or the `onboarding_profiles.mode` drop | W1a, W1b | Same-release client changes; contract on `display_name` |
| Banned user can no longer save profile basics, or a definer writer trips the guard | `profiles` guard | Only `banned_until`, `confirmed_violation_count` and deletes of a profile with strikes or a ban are refused, and only for direct client writes (`current_user` check); tests for other writers |
| Quick exit or sign-out stalls, or quick exit clears the Dating lock | W3a registry | One bounded, never-throwing call per site; each entry in its own `try`; protective entries can't register for quick exit; tests (§5.6 R18, R19) |
| Dating appears on a phone after use | W3a/W3b | Tab layout only in the cache; neutral key names; Dating never queued offline; Spec 2's S19 test with Spec 1's allow-list |
| Metrics inflated or unbounded rows | W1b | Exact client keys, anon only for the pre-auth funnel, server events without a client grant, a daily row cap |
| Someone moves another person's sign-in code to WhatsApp or voice | W2c | Fresh, capped, single-device intents only; everything else by SMS |
| A dev script runs against production | W1c | `private.assert_development_project()`; nothing sets the environment but the owner |
| A gated flag left on when the project becomes production | W1c | `production_flag_violations()` in the launch checklist right after the flip; the trigger refuses later enables |
| Couples never get push permission | W3c | R4 inline ask; legacy unchanged; push tests |
| Invite errors change wording the app parses | `accept-invite` | Messages kept; tests |
| Export loses the stories order or gains an id | W5 | Re-create from the latest body; both export contracts |
| A dating function loses behaviour when its `mode` line is removed | W1a | Body copied verbatim from the latest definition; `dating_mode_contracts.sql` and `dating_exclusion_wiring_test.sql` green; diff is one removed statement |
| Every screen reflows | W10a | Last step, behind a flag, after the audit and device matrix |
| The hook locks everyone out | W6a | Unexpected errors pass through and are counted and alerted; a run on the development project before production |
| An upload fails because of the scan trigger, or the trigger can't be created | W7b | F-1 spike first, sweep fallback; exception-guarded insert; contract |
| A dating photo scanned twice, two holds | W7b | `dating-profile-photos` out of the trigger; one shared match path for queue and inline |
| A false CSAM match | W7b | Human review before any report; the hold is reversible; the escalation records the vendor reference |
| The filter blocks ordinary posts (years, money, place names) | W9a | Year exemption; 9-digit floor; goldens include ordinary Ghanaian, Nigerian and UK text; `squashed` matching only for distinctive terms |
| A shared phone's next user inherits an invite | invite key | Scoped claim with a 24 h window and an explicit "Join {name}" |
| Test devices with old prefs | stores | New keys only; one-time migration of the legacy invite key |
| The local harness re-grants a revoked column | SQL tests | Explicit line in `local_pg_grants.sql` for CI's from-scratch build; `local_pg_grants.sql` is never run against `attune_spec3a`; the identity contract fails if a grant comes back |
| The scratch database is wiped | SQL tests | `local_pg_setup.sh` is never run; per-file `psql -f` only (§7.1) |
| A migration sorts before an applied one, or a later wave drops an earlier wave's change | migrations | Timestamps assigned at build time, after the newest applied file; functions re-created from their live bodies; each table's retention is its own cron (§4.6, §4.7) |
| The strike-3 fix bans someone for the first time, unexpectedly | W9b (OPN-BAN-42702) | Today the third confirmed removal errors and no ban is ever set, so the first real 7-day ban follows the fix. Say so in the W9b release note; the ban notice (D17) tells the author; the contract reaches strike 3 and a fourth removal |
| Owner delete removes the wrong row, or double-decrements the comment count | W9b (OPN-DELETE-RLS) | Owner-checked definer RPCs; the decrement runs only when a live comment was removed; the client drops its own decrement; contract covers a second call and a non-owner |
| Games touched | everywhere | §1.5; CI path check; Games tests after the W10c dead-code commit |

---

## 10. Open items (genuinely open)

| # | Item | Who decides | What's needed |
|---|---|---|---|
| O1 | **Q9 — the Opinions redesign**, open for debate. While it stays open, these known risks remain: guests and partners can read an author's whole history from one recognised post (10 S12); comment text in push previews; `profiles.relationship_status` public and written once (stale after a switch); auto-hide at 10 reports; removal notices that don't name the rule or offer an appeal (W9 restores today's notices only); "We will review this within 24 hours" promised without a staffed SLA. | Owner | A ruling on Q9 and on whether neutral push previews and a rule-and-appeal notice can come forward without the rest. If they can, they go into the held W8. |
| O2 | **Should Healing's AI get the same `self_disclosure`-first pause as the Journal?** `generate-healing-portrait` and `generate-healing-post-mortem` send the person's breakup reflections to a provider with no writer-facing crisis check, as the Journal did (10 F-7). The Q10 ruling names only the Journal. | Owner | **Recommendation: yes.** Same pattern as the Journal, in W9c: a `healing_ai_insights` flag (off in production, with a production gate row, §2.5) checked before any provider call; then `detectSelfDisclosure` on the reflection text first, with no provider call, nothing persisted and the same writer card on a match. Healing is where people write about the worst week of a breakup, so the risk is higher than in the Journal. Same clinician gate. |
| O3 | **Do a parked account's live Dating restrictions follow the number to the fresh account?** (review I-11) The fresh account is assumed to be a new person, so today they don't; the old account's records are carried over under the real number's HMAC only at the 180-day purge. | Owner (with the safety owner) | A yes means Spec 2's restriction checks also read `parked_phone_hmac` of any parked account with the same real-number HMAC while it is parked. Spec 1 needs no change either way. |
| O4 | **Should an Opinions ban or strike count survive account deletion and re-registration?** (review I-16) Spec 2 reserves `enforcement_records.scope = 'opinions'` for this. Today deletion through the service path resets both. | Owner | **Recommendation: yes, for a live ban or a count above 0.** It can't land in Spec 1's W9 as built, because `enforcement_records` only exists from Spec 2 W1. If ruled yes, it becomes **S1 W9d**, built after S2 W1: `prepare_account_deletion` writes an `opinions` record (count and ban end), and `complete_sign_up` is re-created from its live body to restore them for the same phone HMAC. If ruled no, Spec 2 drops the `'opinions'` value. |

Outside parties this spec depends on (not open questions, named with what they owe): **SMS, voice and WhatsApp providers** and Meta (routes, sender ID, template) — W2; **privacy counsel** (A5 line, EULA v2, DPIA, retention of child-safety reports and CSAM evidence) — W2, W6, W7; **Ghanaian cultural reviewer** (Pidgin register, stage wording, slur and explicit lists, local number words, resources) — W4b, W5, W7a, W9a; **DV specialist** (DM1, DM2, H1, resources) — W6, W7; **couples clinician and suicide-prevention reviewer** (journal card, self-harm corpus, grief copy) — W7, W9; **CSAM hash vendor** — W7; **Apple and Google consoles** (ratings, Restrict Minor Access, Declared Age Range entitlement, CSAE link) — W6; **`attune-invite-web` repo** (Play referrer, `webcredentials`) — W2, W4; **barsopus.com** (CSAE page) — W6; **a named daily Opinions reviewer and a named child-safety contact** (owner) — W7, W9.

---

## 11. Changelog — cross-spec review fix pass (2026-10-24)

Applied against `2026-10-24-cross-spec-review.md`, with its "Controller rulings for the fix pass" and 11 §12 (Q19b) as binding. Only findings that touch Spec 1 are listed; the rest belong to Spec 2 or Spec 3.

| Finding | What changed here |
|---|---|
| **S-1** (Critical) | D5, §4.2, §4.4: the W1a `profiles` guard now also locks `confirmed_violation_count` (client UPDATE refused, INSERT forces 0) and refuses a client DELETE of a profile with strikes or a future ban; it acts only for `current_user IN ('authenticated','anon')` (repo precedent). Identity contract cases and a mutant (§7.1, §7.4); R6, §6.2. |
| **S-2** | §4.2, §4.3 W1b: server prefixes (`metric_key_prefixes`) bumped only by definer callers or `bump_metric_server` (service role); client `bump_metric` takes **exact keys** from `metric_client_keys`, anon only for `anon_ok` pre-auth keys; daily cap of 5,000 distinct keys with `metric_cap_reached`. Seeds listed; contract and mutant. |
| **S-3** | §3.3 A1/A3, §4.2, §4.3 W2c, §4.5: intents carry a hashed `device_nonce`; honoured only if under 60 s old, within 6 per number per hour, and from a single device in 10 minutes; otherwise SMS. WhatsApp and voice failures fall back to SMS. Contract and Deno cases. |
| **S-8** | §4.4 hook: each fail-open writes `auth_hook_failures` and bumps a metric; new `identity-health-alert` job posts to `SAFETY_ALERT_WEBHOOK`. |
| **S-9** | D14: the client-writable `relationship_status` is stated as a known limit (self-declared, read by no gate). |
| **R-1, R-3** | D2 and D17 marked for owner confirmation at sign-off; no other change. |
| **R-4** | §1.3 Q1: day-one worldwide listing waits on the Ghana and UK country gates. |
| **R-5** | §3.8 R3, §5.2, §5.6 R17: W3b removes "Meet someone in Dating mode" from `chat_couples_locked_screen.dart` unconditionally. |
| **R-6** (ruling) | §1.3, §2.5: the current project (`mrgjtyacrzfylawyzabm`) is development until launch; `app.settings.attune_environment` reads `development` while unset and only the owner sets `production`; `private.attune_environment()` and `get_attune_environment()`; the dev script calls `private.assert_development_project()` and never sets the setting. |
| **R-7** | §2.5: `private.flag_production_gates`, a `feature_flags` trigger refusing gated flags in production without evidence, `record_flag_gate_evidence`, `production_flag_violations()` for the launch flip. |
| **I-1, I-2** (ruling) | §4.7 lists migrations by name, purpose and order only; timestamps are assigned at build time after the newest applied file (the same rule for any program-time migration); §4.6 gives each table its own retention cron, so no wave re-creates `otp_purge`; §8 order is any dependency-valid order. |
| **I-3** | D15, §3.1, §4.3 W1c: one seam `private.dating_open_countries()` behind `get_public_app_config().config.dating_open_countries`, used by the Welcome preview, A6 and the Me slot; Spec 2 W1 re-creates the seam before deleting the row. |
| **I-4, A-10** | §3.9, §4.3 W1b: the Me Dating slot calls no Dating RPC; `get_my_home_state()` carries `dating {enabled, enrolled}` from the seam `private.dating_home_summary`, which also decides when the Dating lock setting shows. |
| **I-5** | D18, §3.12, §4.3 W1b: Spec 1 pauses Dating only on a change to `relationship`; Dating → Just for me is Spec 2 W2's path trigger; `flow_paths_v2` gets that as its production gate. |
| **I-6** (ruling) | §4.3 W1b/W5, §4.7: `set_user_path_internal` (W1b) names no W5 table; W5 re-creates it from the live body with the draft delete. Also found and fixed under the same rule: `account_holds` and `place_account_hold` move to W1b (W1 functions used them); `get_identity_health` keeps W1 counts and is re-created in W6a. |
| **I-7** | `place_account_hold(..., p_ref text DEFAULT NULL)`. |
| **I-10** | §4.3 W7b, §4.4, §4.5: `dating-profile-photos` leaves the scan trigger; `private.handle_csam_match` shared by `complete_media_scan` and the new service function `record_inline_csam_match`; `_shared/csam_match_path.ts`; `media_scan_status` dropped. |
| **I-11** | §4.2, §4.3 W6a, §4.5, §6.3: `users.parked_phone_hmac` written by `consume_fresh_start` from the real number before parking; Spec 2's HMAC helper prefers it. Owner question O3. |
| **I-12** | §3.8 AU2, §4.3 W5: `suggested_dates` removed from `get_couple_profile`; the chip comes only from the client provider that Spec 2 W9 overrides. |
| **I-16** | §10 O4: owner question with a recommendation; if yes, a later S1 W9d after S2 W1. Not built now. |
| **I-17** | §4.3 W9a, §5.1: one fold table, one TS port and one goldens file owned by S1 W9a, imported by Spec 2 W6; base form (letters and `$` kept) and match form (West African fold, leetspeak); term lists stored in the match form. |
| **C-2, C-3** (ruling) | D19, §5.2, §5.6 R18–R19, new §5.8: Spec 1 owns `quick_exit_service.dart` and the `auth_provider.dart` sign-out path and adds the device wipe registry (ordered, bounded, own `try` per entry); Spec 2 registers through `lib/app/device_wipes.dart`; quick exit never clears the Dating lock, the Safety PIN or the discreet icon; the lock clears on sign-out only (§3.9, §4.8). |
| **C-4** (ruling) | No Spec 1 card slot: the 30-day Dating card is Spec 2 W9's, on `ChatHomeScreen`'s conversations home cards list (W3b note). The split table's "Relationship-home card slot" in W3b is therefore not applied. |
| **C-5** (ruling) | D20, §3.7, §3.11, §5.5: the home-state cache stores the tab layout (`chat`/`me`), never the path; the shell is keyed by tab layout; the lock key is `me_section_lock`; a Dating choice is never queued offline; an allow-list for Spec 2's S19 test. |
| **C-8** | §5.4: game routes cited by route name, not line ranges. |
| **C-9** | §8 W10c: Spec 1 amends only the Master Spec, `AUTH_ONBOARDING_ENGINE.md`, CR-06 and the SOUL proposal, plus the "Forums retired" line; Dating docs are Spec 2's, `FORUM.md` Spec 3's (§5.7). |
| **C-1** (Spec 3's, noted) | §5.2 manual row: topics are added through the registry and nothing here pins a module count. |
| **N-1** | §8 W10c lists `export_screens.dart:43` and `supabase_profile_repository.dart`, a Games-symbol grep before deleting, and the Games tests after. |
| **N-2** | §5.6 R1: a latch test for a legacy account with `needs = [birth_date]`. |
| **A-1** (ruling) | §7.1: no instruction to run `local_pg_setup.sh`; per-file `psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f` only; `local_pg_grants.sql` never run against the scratch database. |
| **A-2** | §3.1: screens renamed WL0 and WL1. |
| **A-4** | §4.5: `detectSelfDisclosure(..., {victimisation: <private_safety_check flag>})`, default off. |
| **A-5** | §8 W1c gate: says the Journal pause stops Gemini insights wherever the flag is off. |
| **A-6** | §2.5, §5.3: flag dependencies and effective flags on the client and the server (`private.spec1_flag_on`). |
| **A-8** | Header: which "Spec 1/2/3" this is. |
| **F-1** | §4.4, §8 W7b: spike on the development project before W7b, with a 1-minute sweep fallback. |
| **F-2** | §3.15 H1, §4.5, §7.5, W6a gate: H1's trigger reworded; the plan check; two checks on the development project. |
| **F-3** | §4.7: each migration one `BEGIN; … COMMIT;`, no `CONCURRENTLY`. |
| **F-4** | §5.1, §7.5, W6b: Declared Age Range weak-linked behind `#available(iOS 26, *)`, iOS 26 SDK, release-mode device checks. |
| **F-5** | §3.6 X1: "usually survives" a reinstall. |
| **W-1, W-3** (ruling) | §8: W1a–c, W2a–c, W3a–c, W4a–b, W5, W6a–c, W7a–b, W9a–c, W10a–c, per the review's split table. One deviation: the metric storage and client surface land together in W1b (not W1c), because W1b's functions bump metrics. Citations without a letter mean the whole group. |
| **OPN-BAN-42702** (added 2026-10-25, Spec 3 W1–W2 final review F6) | §4.3 and §4.7 (migration 18), §7.1 (`opinion_moderation_notice_contracts.sql` now reaches strike 3), §8 W9b, §9: `admin_confirm_content_removal` raises 42702 at the third confirmed removal, so the 7-day ban never applies; W9b qualifies the column when it re-creates the function. Replaces the id "F-2", which collides with this spec's own review F-2. |
| **OPN-DELETE-RLS** (added 2026-10-25, same review, ledger item O-1) | §4.3 and §4.7 (new migration 19 `opinion_remove_own`), §5 file table (`opinion_repository.dart`), §7.1 (`opinion_remove_own_contracts.sql`), §8 W9b, §9: deleting your own opinion or comment fails RLS because the direct `UPDATE … SET removed_at` makes the new row fail the SELECT policy; fixed by `remove_my_opinion` / `remove_my_comment` definer RPCs, with no policy change. |

Also corrected in passing: the legacy `onboarding_profiles` upsert writes `mode`, so W1b removes it from the client in the same release as the column drop (§4.2, §5.2, R5).


---

## Owner approval (2026-10-24)

The owner approved Specs 1, 2 and 3 as written, together with the recommendations for the remaining open items:
- **O2 (Healing AI):** yes. Healing's AI insight gets the same pause, with the `self_disclosure` crisis check running first. It is built in S1 W9 behind `healing_ai_insights`, under the same clinician gate.
- **O3 (parked account restrictions):** no. A parked account's live Dating restrictions do **not** follow a recycled number to the fresh account. The enforcement record stays attached to the old account and its HMAC.
- **O4 (Opinions enforcement records):** yes. Opinions-scope enforcement records survive account deletion like Dating's. This is built as **S1 W9d**, after S2 W1 creates `enforcement_records`.

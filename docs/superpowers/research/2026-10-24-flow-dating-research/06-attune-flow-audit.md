# 06 — Attune flow audit: what exists, what must change, what can be reused

Researcher 06 · 2026-10-24 · scope: code and docs only (no web research) · repo read-only at `main` a7b07e79 plus working tree.

---

## 1. How this was researched

**Sources.** The Flutter client (`lib/**`), 434 Supabase migrations (`supabase/migrations/*`), edge functions (`supabase/functions/*`), operator SQL scripts (`supabase/sql/*`), SQL contract tests (`supabase/tests/*`), Flutter tests (`test/**`), and the architecture docs named in the brief (`AUTH_ONBOARDING_ENGINE.md`, `ATTUNE_MASTER_SPEC.md` §2, §9, §15, `DATING_MODE_SPEC.md`, `DATING_CHAT_SAFETY_SPEC.md`, `DATING_MODE_REVIEW_AND_GATES.md`, `docs/reviews/DATING_REVIEW_FABLE.md`, `FORUM.md`) and the couples research of 2026-10-16 (`06-synthesis-roadmap.md` §3, §5, §9).

**Method.** Each route, screen and writer was read at source and traced with grep to every caller. Each table was traced to its creating migration and every later `ALTER`, grant and `CREATE OR REPLACE` of the functions that use it. Nothing was executed: no app run, no test run, no database query.

**Evidence grades, adapted for a code audit.** The brief's scale is for research evidence. Here:
- **[C] code-verified**: read today at the cited `file:line`. Treat as **Strong**.
- **[D] doc-stated**: a spec, comment or review says it, and I did not verify it against running code or the live database. Treat as **Moderate**.
- **[I] inferred**: follows from code paths I read but did not execute. Treat as **Weak**.

**Limits.**
- Migrations are not the live database. At least one cron job exists only in the database (§2.5.4), and flag values in production are unknown.
- Line numbers are as of today's working tree.
- Cultural and legal points are flagged for the owner, not researched. Other researchers in this programme cover the external evidence.

---

## 2. Findings

### 2.1 Current first-run journey, screen by screen

#### 2.1.1 Cold start and routing

| Step | What happens | Writes | Source |
|---|---|---|---|
| `main()` | Mapbox token, Supabase init (30 s timeout), deep-link listener, chat cache (8 s bound), `SharedPreferences`, `RoutingNotifier(isFirstLaunch)`, safety-lock seed (3 s bound). Overrides the router, prefs and sign-out hooks. | none | `lib/main.dart:37-92` [C] |
| Root shell | `ShareIntakeListener` → `SafetyLockGate` → `AppPrivacyCover` → `QuickExitZone` → `NewDeviceNotice` → `RelationshipLifecycleWatcher` → text-scale clamp 1.0. Wraps every route. | none | `lib/app/app_shell.dart:23-44` [C] |
| Router boot | `initialLocation: '/_invisible'`. The redirect sends `/_invisible` to `/intro` on first launch, otherwise to `/home`. **Every route except `/intro` is forced to `/intro` while `isFirstLaunch` is true.** | none | `lib/app/routing/app_router.dart:408-428` [C] |
| First-launch flag | `is_first_launch_Attune` (bool). It survives `clearAll` on purpose. | prefs | `lib/core/services/shared_preferences_service.dart:11-20,35-36`; `lib/core/utils/constants.dart:28` [C] |

#### 2.1.2 Screens a new user meets (no invite link)

| # | Screen / route | What it shows | What it collects | Where it writes | Flags / gates | Source |
|---|---|---|---|---|---|---|
| 1 | **IntroScreen** `/intro` | Green full-screen page with an animated circle, a **Get Started** button, "Welcome to Attune", the logo, a horizontal carousel of every *ungated* manual topic (26 of 35, including **Forums**, **Dating Mode**, **Healing**, **Verdict**) and a legal link. | nothing | `is_first_launch_Attune=false`, then `completeFirstLaunch()` and `go('/home')` | Carousel uses `DocumentationRegistry.visibleModules(const {})` | `lib/features/auth/intro/intro_screen.dart:38-40,127-152`; registry `lib/app/documentations/user_manual/data/manual_documentation_registry.dart:48-62,116-152` [C] |
| 2 | **HomeScreen (guest)** `/home` | Two tabs: **Opinions** (default for guests) and **Chat**. | nothing | none | `isAuthenticated=false` → tab 0 | `lib/home/home_screen.dart:367-406` [C] |
| 2a | Opinions tab (guest) | `OpinionsTab`: an outer **Opinions / Forums** tab bar. Under Opinions, Following and Discover (guests land on Discover). Forums is also readable by guests. | nothing | none | anon RPC grants (§2.6) | `lib/features/opinions/presentation/screen/opinions_tab.dart:65-80,115-119,337-352` [C] |
| 2b | Chat tab (guest) = **LoginProfile** | Menu → Settings, "Hello!", guest overview ("…start your shared space with your partner"), **Continue with phone number**, **Invite a friend** (`Share.share` app link; in debug it opens an onboarding preview), the same topic carousel, legal link. | nothing | none | — | `lib/features/auth/log_in/presentation/screens/login_profile.dart:24-26,141-193`; copy `lib/i10n/app_en.arb:170-171` [C] |
| 3 | **LoginScreen** (bottom sheet from LoginProfile, or the `/login` route) | Two tabs. **Phone**: country picker (every country, **default Ghana**), number field, a WhatsApp toggle whose copy says "Attune uses phone OTP at launch…". **Code**: code field, 60 s resend. | E.164 phone number; OTP channel (SMS or WhatsApp) | Supabase Auth (`signInWithOtp`, then `verifyOTP` with `OtpType.sms` for both channels). Selected country is held in memory only. | Debug build logs the phone (`kDebugMode`) | `login_screen.dart:132-278`; `login_phone_step.dart:50-72`; `phone_country.dart:41-46`; `passwordless_auth_service.dart:33-81` [C] |
| 4 | **EULA gate** (sheet that cannot be swiped away) | EULA v`'1'`. **Accept** or **Reject**. Reject signs the user out. A sheet torn down mid-answer is treated as "unavailable", not as a decline. | consent | RPC `record_eula_acceptance` **inserts the `public.users` row** (phone from the JWT, `display_name=''`, `eula_accepted_at`, `eula_version`). It raises `phone_required` if the account has no phone. | Version constant `currentVersion='1'` | `eula_gate.dart:35-77`; `eula_acceptance_service.dart:21,38-65`; `supabase/migrations/20260817120000_eula_acceptance.sql:14-16,34-75` [C] |
| 5 | Post-verify hop | Latched `_goToOnboarding`: pops the sheet if it is a `PopupRoute`, then `go('/onboarding')`. | — | — | — | `login_screen.dart:319-370` [C] |
| 6 | **OnboardingGate** `/onboarding` | Spinner. (a) Accepts a pending invite code if one is stored. (b) Checks completion server-first (`onboarding_profiles.completed_at`). (c) Not signed in → `/login`; complete → `/home`; otherwise mounts the flow. | — | Invite acceptance (§2.1.5); `attune.onboarding.<scope>.completed` backfill | `kDebugMode && extra==true` gives the preview scope | `onboarding_gate.dart:26-56,101-163`; `onboarding_store.dart:93-129` [C] |
| 7 | **OnboardingFlow, step 0: ProfileSetupStep** | "What should Attune call you?" Copy: **"Opinions and forums stay anonymous."** | display name (needs at least 2 letters; autofocus) | held in memory until `_finish` | — | `profile_setup_step.dart:19-59`; `onboarding_flow.dart:48-51,292-298` [C] |
| 8 | **Step 1: OnboardingModeStep** | "Are you single or in a relationship?" **Single** ("Build self-understanding…") or **In a relationship** ("Invite your partner into a private space…"). | `OnboardingMode.personal` or `couples` | memory | Decision 18 / 29 copy rules | `onboarding_mode_step.dart:19-41`; `onboarding_flow.dart:299-309` [C] |
| 9 | Single only: confirm sheet + `AttachmentQuizDocs` sheet → **AttachmentQuizStep** ×26 | 26 situational questions on a 5-point scale, nullable (no pre-filled midpoint). Fanned card deck. | 26 integers | memory | Not the clinical 7-point quiz; never scored | `onboarding_flow.dart:133-179,310-325`; `onboarding_models.dart:43-189` [C] |
| 10 | Single only: confirm + `AnchorsDocs` → **AnchorsStep** | 3 personal anchors with example hints. | 3 strings | memory | — | `onboarding_flow.dart:184-226,326-330`; `onboarding_models.dart:191-216` [C] |
| 11a | Single: **PersonalReadyStep** | "Personal mode is ready." **Enter Attune.** | — | `_finish` (below) | — | `personal_ready_step.dart:13-41` [C] |
| 11b | Couples (inviter): **CouplesWaitingStep** | "Invite your partner". Creates or fetches the invite (QR code, code, share link). `PendingInviteGuide` by wait time: under 48 h a line and Continue; 48 h to 7 days "Open reflection mode"; from day 7 keep waiting / on my own / invite someone else. | — | `relationships` pending row (edge function); withdraw RPC | Spec 5 R5-9/10 | `couples_waiting_step.dart:36-166`; `pending_invite_guide.dart:27-136` [C] |
| 12 | **`_finish`** | EULA re-checked. Remote submit, then local completion, then `/home`. | — | `public.users` upsert `{id, phone, display_name, mode}`; `public.profiles` upsert `{id, display_name, relationship_status: single|taken}`; `public.onboarding_profiles` upsert `{user_id, mode, attachment_answers, anchors, completed_at}`. On failure, prefs `pending_submission` (replayed by `OnboardingSyncService`). Then prefs `mode`, `display_name`, `completed`. | **Returns silently if `user.phone == null`** | `onboarding_flow.dart:228-281`; `onboarding_submission_service.dart:23-82`; `onboarding_store.dart:145-184`; `onboarding_sync_service.dart:24-41` [C] |
| 13 | **HomeScreen (signed in)** | If not complete: latched redirect to `/onboarding`. Otherwise tabs Opinions + Chat. Default tab is **Chat for `couples`**, Opinions otherwise. | — | relationship-mode sync on launch, resume and sign-in; timezone report | — | `home_screen.dart:77-113,150-228,340-411` [C] |
| 14 | Chat tab, not linked = **ChatCouplesLockedScreen** | Settings menu; `RelationshipLifecycleCard` (paused or ended); welcome card. **Pending**: invite card plus `PendingInviteGuide`. **Personal** (not paused): **Invite your partner** and **Meet someone in Dating mode** (shown only when no invite exists). Then a locked chat preview, **Personal reflections** (journal) and **Healing from a breakup?** (self-report sheet). | — | `createInvite`, then `store.startCouplesInvite()` (prefs `mode=couplesPending`) | `pausedSpace` hides invite and Dating | `chat_couples_locked_screen.dart:39-61,251-421` (Dating button `371-384`, Healing `407-412`) [C] |
| 14b | Chat tab, linked = `ChatHomeScreen` | Conversations workspace. | — | — | — | `authenticated_chat_workspace.dart:24-40` [C] |
| 15 | **Ask 2** `/ask2/:relationshipId` (couples only, days later, from the `ask2_invite` push) | Intro "A closer look" → the same 26 questions → relationship anchors → reveal (anchors reflected back, private safety self-check, Love map and This-or-That links). | answers, anchors | `onboarding_profiles` **UPDATE** (answers, anchors, `ask2_completed_at`) plus RPC `complete_ask2`. **No retry layer.** | `evaluate-ask2-eligibility` cron (hourly :17) | `ask2_flow.dart:13-139`; `ask2_submission_service.dart:26-50`; `notification_config.dart:116-125`; `supabase/migrations/20260907120000_register_scheduled_jobs.sql:179-183` [C] |

#### 2.1.3 SharedPreferences keys in the first run

| Key | Meaning | Source |
|---|---|---|
| `is_first_launch_Attune` | Intro shown or not | `shared_preferences_service.dart:11-20` [C] |
| `attune.onboarding.<scope>.completed / .mode / .display_name / .pending_submission` | scope is `user.<uid>`, `anonymous` or `preview` | `onboarding_store.dart:62-69,214` [C] |
| `attune.onboarding.pending_invite_code` | **Not user-scoped.** It survives sign-out and account switches. | `onboarding_store.dart:70,167-175` [C] |
| `seen_feature_intro_<featureId>` | Healing and Dating intro gates are shown once per device | `lib/core/intro/data/seen_feature_intro_store.dart:13-20` [C] |
| `auth.isRecoveryMode` | Password-reset leftover (dead path) | `routing_notifier.dart:14,44-51` [C] |

#### 2.1.4 Feature flags on the first-run path

- **None gate onboarding itself.** [C]
- The flags on the path are the Dating flags (behind `get_dating_eligibility`, §2.4), the Healing and Dating intro gates (`FeatureIntroFlowGate`, `app_router.dart:600-613,1664-1677`), and the manual-topic flags (`manual_documentation_registry.dart:48-62`). [C]

#### 2.1.5 Invite create and accept, and deep links

- **create-relationship-invite**:
  - 7-day TTL, 6-character code (`index.ts:8-9`).
  - Returns the live invite unless `force_new` is set (`:58-88`).
  - Refuses while an active or paused relationship exists (`:45-49`).
  - Caps concurrent pending invites (`:90-104`).
  - Inserts a `pending` relationship (`:113-121`).
  - `ensureUserRow` upserts `users{mode:'couples', display_name: phone}` with `ignoreDuplicates` (`:140-162`). Because the EULA RPC already created the row, the phone-as-name fallback never lands in practice [I]. [C]
- **accept-invite**:
  - Idempotent via `relationship_invite_acceptances` hashes (`:29-40,103-108`).
  - Refuses if the invitee already has an active or paused relationship (`:69-71`).
  - Sets the row `active` (`:80-91`) and queues an `invite_accepted` push to the inviter (`:117-125`).
  - **No age check and no onboarding check.** [C]
- **Deep links**, all handled in `main.dart:159-291`:
  - `attune://auth/callback` (Supabase session).
  - Planning or widget links.
  - Invites in two forms: `https://invite.attune.barsopus.com/i/<code>` (App Links / associated domains in `AndroidManifest.xml:111-122` and `Runner.entitlements:11`) and the legacy `attune://invite?code=`.
- **What an invite link does**:
  - It stores the code (anonymous scope).
  - It **clears the first-launch flag** so the `/intro` redirect cannot swallow it (`main.dart:223-226`).
  - It goes to `/onboarding`, which sends a signed-out user to `/login` (`onboarding_gate.dart:137-142`).
  - After OTP and EULA, the gate accepts the invite **before** the name step (`onboarding_gate.dart:41-44`).
  - The flow skips the mode fork (`onboarding_flow.dart:73-75,297`), shows **CouplesJoinedStep**, then `_finish(mode: couples)`. [C]
- The **Ask 2** push is a deep-link-like route (`/ask2/<id>`). There are **no forum deep links** other than notification taps (§2.5). [C]

#### 2.1.6 Dead and unrouted code on the auth and first-run surface

| Item | State | Source |
|---|---|---|
| `SplashScreen` | Not in the route table. It references `/createUsername` and `hasUsername`. | `lib/app/splash_screen.dart:30-51` [C] |
| `RouteNames.splash`, `loginOptions`, `createUsername`, `verifyEmail`, `forgotPassword`, `updatePasswordScreen`, `passwordResetSentScreen`, plus about 45 shop, booking and marketplace constants | Declared, never routed | `app_router.dart:161-235` vs the route list `:429-1767` [C] |
| `UsernameCreationScreen`, `VerifyEmailScreen`, `ForgotPasswordScreen`, `UpdatePasswordScreen`, `PasswordResetEmailSentScreen`, `LoginScreenOptions`, `EmailSignupAttempt` models | No importers (except the `export_screens.dart` barrel for `LoginScreenOptions`) | grep, `lib/core/utils/exports/export_screens.dart:43` [C] |
| Email, Google and Apple sign-in | `AuthService.signUpWithEmail / signInWithPassword / signInWithGoogle / signInWithApple`, with a Google channel named `com.barsOpus.florence/google_sign_in` (cloned-app residue). `AuthUiService` wraps them. **AuthService stays live** for sign-out through `auth_provider.dart:21-22`. `google_sign_in` and `sign_in_with_apple` are in `pubspec.yaml:67-68`. | `lib/features/auth/services/auth_service.dart:9,24-26,51-89`; `auth_ui_service.dart:108-251` [C] |
| `AttuneShell` | A 5-tab placeholder shell (Pulse, Chat, Games, Insights, Profile). Unused. | `lib/features/shell/presentation/attune_shell.dart:3-60` [C] |
| `ForumHome` | Unused wrapper around `OpinionsTab` | `lib/home/widgets/forum_home.dart` [C] |
| Notification cases `booking_*`, `shop_*`, `review_request`, `new_shop_nearby` | Cloned-app residue | `notification_config.dart:76-97` [C] |
| `RoutingNotifier` pending-deep-link slug ("aurain.barsopus.com") | Self-described as vestigial | `routing_notifier.dart:94-125` [C] |
| Settings rows `/notifications`, `/editLocation`, `/guide` | Point at routes that do not exist | `settings_data.dart:77,87,263` vs the route table [C] |

#### 2.1.7 Doc drift

`AUTH_ONBOARDING_ENGINE.md` is out of step with the code in four places. [C]
- It still says the legal sheet comes *before* the phone step (`:105-112`). It now comes after OTP (`login_profile.dart:146-151`).
- It still shows a "Compatibility preview" reward in Ask 2 (`:142-147`). Decision 30 removed it (`ATTUNE_MASTER_SPEC.md:3081`).
- It requires **voice OTP fallback** and a Ghana-direct SMS provider (`:53-79`). Neither is in the client: only `sms` and `whatsapp` channels exist (`login_phone_step.dart:64-71`). [C for the client; provider configuration unknown]
- It says "do not collect gender" at basic profile setup (`:81-91`). This agrees with research 06 §9 ("no gender fields at signup").

### 2.2 Data model inventory: identity and couples

#### 2.2.1 What exists

| Table | Columns (current) | RLS and grants | Writers | Readers | Source |
|---|---|---|---|---|---|
| `public.users` | `id` (FK `auth.users`), `phone` **NOT NULL UNIQUE**, `display_name` NOT NULL, `avatar_url`, `mode` CHECK (`couples`, `personal`, `healing`, `dating`) default `personal`, `eula_accepted_at`, `eula_version`, `timezone`, `created_at`, `updated_at`. `email` dropped. | Own-row SELECT, INSERT and UPDATE. **Table-level `UPDATE` granted to authenticated**, so every column is client-writable. | Onboarding upsert (client); `record_eula_acceptance`; invite functions (`ensureUserRow`); dating RPCs (`mode`) | Chat repository (`id, display_name, avatar_url`), but RLS is own-row only; see note. **`mode` is read by nothing.** | `supabase/migrations/20260606120000_attune_core_schema.sql:6-17,98-112`; `20260606133000_phone_only_auth.sql:4-13`; `20260724120000_grant_missing_core_table_privileges.sql:12-13`; `20260817120000_eula_acceptance.sql:14-16`; `20261017160000_user_timezone.sql:10`; `supabase_chat_repository.dart:1224-1236` [C] |
| `public.profiles` | `id`, `username` UNIQUE, `display_name`, `avatar_url`, `bio`, `relationship_status` CHECK (`single`, `taken`, `figuring_it_out`, `open`), `preferred_location`, `last_location_update`, `onesignal_player_id`, `banned_until`, timestamps | **Readable by every authenticated user**; owner-only writes | Onboarding writes `single` or `taken` **once**. Never updated when a user pairs or unpairs. | Opinions labels, games partner names (8 call sites), moderation, block lists | `20260713120000_profiles_public_identity.sql:26-80`; `20260716120000_forums_opinions_launch.sql:29-37`; `onboarding_submission_service.dart:54-62,80-82` [C] |
| `public.onboarding_profiles` | `user_id`, `mode` CHECK (`couples`, `personal`), `attachment_answers` jsonb, `anchors` jsonb, `completed_at`, `ask2_completed_at`, `updated_at` | Own-row | Onboarding (Ask 1), Ask 2 update | Completion check (`resolveIsComplete`) | `20260606120000:53-60`; `20260721123000_onboarding_profiles_ask2.sql:6-7`; `onboarding_store.dart:93-129` [C] |
| `public.relationships` | `user_a`, `user_b`, `invite_code`, `invite_expires_at`, `invite_accepted_at`, `status` (`pending`, `active`, `paused`, `ended`, later `archived`), **`started_at date` (never written)**, `ended_at`, `ended_by`, `paused_at`, `chat_archived_at`, `chat_archived_reason`, `chat_name`, `chat_avatar_url`, `chat_avatar_thumbnail_url`, counters | Member SELECT through a **column-level grant list**. **No client UPDATE at all**; every write goes through a SECURITY DEFINER RPC or a service-role function. | Edge functions, lifecycle RPCs, `set_relationship_chat_name` | Everywhere | `20260606120000:19-43`; `20260826130000_relationship_chat_identity.sql:19-29`; `20261017110000_relationships_write_lockdown_grants.sql:22-23`; `20261018100100_relationship_lifecycle_grants.sql:34-41` [C] |

**`started_at`.** No client or function writes it. The only reader is `ORDER BY r.started_at DESC NULLS LAST` in `together_active_relationship` (`20261014160000_together_calendar_feed.sql:18-25`), which is harmless because only one active relationship can exist. [C]

**Note on `users` reads.** The chat repository selects partner rows from `users`, but the only SELECT policy is `id = auth.uid()`. The partner's row will not come back [I]. This is outside this brief, recorded so the couple profile does not copy the pattern.

#### 2.2.2 Couple-profile-like data that already exists

| Data | Where | Shape | Source |
|---|---|---|---|
| Couple name | `relationships.chat_name` (1–30 characters), set by either partner through an RPC; read by `coupleNameProvider` (placeholder "Couples") | Shared, either partner edits | `20260826130000:19-29`; `lib/core/providers/couple_name_provider.dart:6-31` [C] |
| Shared avatar | `relationships.chat_avatar_url`, `chat_avatar_thumbnail_url` (upload-intent pipeline) | Shared | `20260826130000:19-23,40-240` [C] |
| Anniversary reminder | `reminders` (`reminder_type IN ('anniversary', 'birthday', 'checkin', 'ai_generated')`, `remind_at`, `recurrence`); Together's empty state shows **"Add your anniversary"**, which opens the reminder sheet | Relationship-scoped, both members via RLS | `20260814120000_couples_calendar_reminders.sql:19-37`; `together_screen.dart:1290-1298` [C] |
| Anniversary moments | `timeline_events.event_type='anniversary'` (moment types: milestone, highlight, conflict, first, anniversary); `timelineAnniversariesThisMonthProvider` | Relationship-scoped | `log_moment_type_screen.dart:52-82`; `reminders_providers.dart:205-219` [C] |
| Family and children-adjacent | `couple_family_members(name ≤80, birthday)`, **no relation type**, members-only RLS; linked from reminders | Relationship-scoped | `20260814120000:9-17,104-140` [C] |
| Change signal pattern | `together_change_signals`: a per-couple "something changed" realtime bump. Both partners refetch; the signal is never a second source of truth. | Pattern to copy | `20261014100000_together_change_signals.sql:1-20` [C] |
| Export | The per-relationship export bundle already carries `reminders` and `family` | Pattern to extend | `20261018120000_data_export.sql:128-137` [C] |

#### 2.2.3 What is missing for the new decisions

| Needed | Exists? | Gap |
|---|---|---|
| DOB for everyone at sign-up | **No.** The only `birth_date` in the schema is `dating_age_verifications.birth_date`, written only by service-role `verify_dating_age`. | Nothing collects a DOB. Nothing stops an under-18 from creating an account or accepting an invite. [C] `20260705210000_dating_mode_v1_2_hardening.sql:17-29`; `20260712140000_dating_age_verification_writer.sql:12-45` |
| "Only age is ever shown" | Partly in the dating spec (§4.1: DOB never displayed, age derived server-side) | The introductions RPC returns **no age at all** (`20260712160000_dating_former_partner_exclusion.sql:251-256`). [C] |
| Path choice on the account | **No.** `OnboardingMode` has 3 client values; `users.mode` is write-only. | "Single and open to dating" and "Just for me" cannot be told apart. Both resolve to `personal` (`relationship_mode_sync.dart:14-23`). [C] |
| Shared couple profile (together since; stage dating / engaged / married + year / other; living together / apart / long distance; children) | **No.** Only the name, avatar and anniversary-as-reminder. | Whole feature missing. [C] |

#### 2.2.4 Where each should live (proposal, following existing patterns)

1. **DOB: a new private table, not `users` and not `profiles`.**
   - Why not those two: `profiles` is readable by every signed-in user (`20260713120000:57-60`), and `users` carries a table-level client UPDATE grant (`20260724120000:13`).
   - Shape: `public.account_birthdates(user_id PK → public.users ON DELETE CASCADE, birth_date date NOT NULL, source text CHECK IN ('self_declared','verified'), declared_at, corrected_at)`.
   - Access: RLS on, `REVOKE ALL FROM PUBLIC, anon, authenticated`.
   - Writes: one SECURITY DEFINER `SET search_path = ''` RPC, `set_my_birth_date(p_birth_date date) RETURNS int` (the age). It refuses under-18 with an opaque error and refuses a second set. Corrections go through a support path. Reads: `get_my_age()`.
   - An internal, ungranted `account_age(uuid)` serves Dating and `accept-invite`.
   - This mirrors `dating_age_verifications`, which is service-role only and never client-writable (`20260705210000:17-29,105`).
2. **Path choice: `public.users.path text CHECK (path IN ('relationship','dating','just_me'))` plus `path_chosen_at`**, written only by `set_my_path(p_path)`.
   - In the same migration, replace the table-level UPDATE grant on `users` with column grants (display name, avatar, timezone).
   - Retire `users.mode`: drop the CHECK value `healing` and stop the client, invite and dating writers (list in §2.3).
   - The path is the **home the person chose**, not authority. Couple link state stays `relationships.status`; dating state stays `dating_enrollments.state`.
3. **Couple profile: a new `public.couple_profiles(relationship_id PK → relationships ON DELETE CASCADE, …)`**, not new columns on `relationships`.
   - Why: `relationships` has no client UPDATE and a column-level SELECT list (`20261018100100:34-41`). Every new column there is invisible until it is re-granted.
   - Fields:
     - `together_since date` with `together_since_precision text CHECK IN ('day','month','year')`;
     - `stage text CHECK IN ('dating','engaged','married','other')`;
     - `married_year smallint` (only when `stage='married'`);
     - `stage_words text` (≤40, the couple's own description for `other`);
     - `living text CHECK IN ('together','apart','long_distance')`;
     - `children text CHECK IN ('none','expecting','yes','prefer_not_to_say')`;
     - `updated_by uuid → auth.users ON DELETE SET NULL` (NO ACTION foreign keys blocked `deleteUser` before, `20261018110000_chapters_deletion.sql:1-25`);
     - `updated_at`.
   - Access: members-only SELECT. Writes only through `update_couple_profile(p_relationship_id, p_patch jsonb)`, SECURITY DEFINER `SET search_path = ''`, which checks active, non-archived membership (the `planning_is_active_member` pattern, `20260941040000_planning_item_rpcs.sql`), validates each key, locks the row and bumps a Together change signal so **both phones refetch at once**.
   - Export: add to the per-relationship export bundle (`20261018120000:128-137`).
   - Lifecycle: it lives and dies with the relationship row (archive window, 12-month purge, 90-day reopen) [I].
   - **Never a type or a score**: no derived column. Add a contract test that no function maps profile fields to a label, like the `love_language` absence test (`20260933150000_dating_alignment_v1.sql:1-12`).
   - **"Together since" must never render as an elapsed counter.** Research 06 §5.4: "Countdown to togetherness allowed; elapsed time never."
4. **Interested-in and gender identity: keep them where they already are**, on Dating tables only (`dating_profiles.gender_identity`, `gender_visible` default false; `dating_preferences.gender_preferences`; `20260705210000:106-131`). Never on `users` or `profiles`. Never at sign-up (research 06 §9: "no gender fields" at signup).

### 2.3 Modes today and how they map to the three paths

**Today's mode signals:**

| Signal | Values | Who writes | Who reads | Source |
|---|---|---|---|---|
| `OnboardingMode` (client enum, cached in prefs) | `personal` ("Single"), `couplesPending`, `couples` | Onboarding `_finish`; `startCouplesInvite`; `syncModeFromServer` | HomeScreen (tab choice, Chat content) | `onboarding_models.dart:1-23`; `onboarding_store.dart:156-204`; `home_screen.dart:368-397` [C] |
| `resolveModeFromRelationshipStatus` | `active` → couples; `pending` → couplesPending; **`paused`, `ended` and anything unknown → personal** | — | `_syncRelationshipMode` on launch, resume and sign-in, plus `relationshipModeResyncSignal` | `relationship_mode_sync.dart:14-23`; `home_screen.dart:34,150-228` [C] |
| `users.mode` | `couples` / `personal` / `healing` / `dating` | Client onboarding upsert (`onboarding_submission_service.dart:47`); invite functions on insert (`create-relationship-invite:159`, `accept-invite:163`); `activate_dating_profile` sets `dating` (`20260705210000:541`); `pause_dating_for_relationship_user`, `pause_dating_mode`, `exit_dating_mode` and `delete_dating_profile` reset to `personal` (`20260703203000_dating_mode_contract_hardening.sql:369,626,670,1058`; its older `activate` at `:582` is superseded) | **Nothing.** No client select, no SQL predicate, no edge function. `healing` is never written. | grep; `20260606120000:12-13` [C] |
| `onboarding_profiles.mode` | `couples` / `personal` | Onboarding | Nothing beyond the existence check | `20260606120000:55` [C] |
| `profiles.relationship_status` | `single` / `taken` (two more allowed, never written) | Onboarding, once | Opinions labels (public) | §2.2 [C] |

**How the home changes per mode today** (`home_screen.dart:367-397`, `authenticated_chat_workspace.dart:24-40`): [C]
- Guest: Opinions + LoginProfile.
- Not complete: redirect to onboarding.
- `couples`: default tab Chat, showing `ChatHomeScreen`.
- `couplesPending`: default Opinions; Chat shows the locked screen in its pending variant.
- `personal` or null: default Opinions; Chat shows the locked screen in its personal variant, with invite, Dating, journal and Healing.

**Mapping to the new paths:**

| Today | New | Action |
|---|---|---|
| `personal` | **Just for me** *or* **Single and open to dating** | **Split.** The split needs the stored path (§2.2.4 #2). Dating state comes from `dating_enrollments`, not from a mode. |
| `couplesPending` | **In a relationship**, waiting for partner | Keep as a sub-state of the Relationship path. Rename the enum to a link state (`none` / `pending` / `linked`). |
| `couples` | **In a relationship**, linked | Keep. |
| `paused` → `personal` | Should stay **In a relationship** (paused) | **Change.** Today a pause flips the user's home to the personal variant, and only `pausedSpace` patches it (`chat_couples_locked_screen.dart:257-260`). |
| `users.mode` (all four) | `users.path` | Replace. Remove `healing` (Healing is a feature inside Just for me). Stop the dating RPCs writing `dating`. |
| `onboarding_profiles.mode` | the path at onboarding time, or drop | Widen the CHECK or drop the column (fresh start). |
| `profiles.relationship_status` | Opinions label | Re-derive from the path and keep it in sync on path change (owner question 7). |

### 2.4 Dating Mode as built, and what to do with each piece

**Status in one line.**
- Built: schema, RPCs, client screens, the photo pipeline, scoring, snapshots and weekly generation.
- **Not reachable for anyone today**: all flags are off; the only eligibility path needs a Healing journey with a readiness score above 70; activation needs preference arrays that nothing writes.
- Code for reference. Client: `lib/features/dating/**` (16 files, 3,727 lines). Server: 20 `*dating*` migrations. Edge functions: `upload-dating-photo`, `process-dating-photo`, `verify-dating-profile`.

**The blockers in the review documents need updating.** `DATING_MODE_REVIEW_AND_GATES.md:42-56` and `DATING_REVIEW_FABLE.md:511-515` list four. [C]
- **Candidate generation is now built.** Scoring core `20260933150000_dating_alignment_v1.sql`, snapshots `20260933160000`, symmetric hard filters and generation `20260933170000`, weekly cron and a *draft* config `20260933180000`. The config's CHECK refuses `active` without four review refs (`20260705210000:47-64`). [C]
- **The exclusion key moved to Vault.** It is wired into `end_relationship` (`20260931130000_wire_dating_exclusion.sql`) and health-checked (`20260933140000_dating_health_exclusion_key.sql`). It still has to be **provisioned**. [C]
- **The KYC or DOB backend still does not exist.** `verify_dating_age` is service-role only, and nothing calls it. [C]
- **Dating chat safety** now has a full draft spec (`DATING_CHAT_SAFETY_SPEC.md`, "Nothing in this document is approved", `:3-4`). Its release blockers are unchecked (`:418-437`). [C]

**Keep / change / replace / remove under the new decisions**: worldwide, no Healing gate for new singles, private interested-in, separate dating chat, a few curated per day.

| Piece | As built | Verdict | Why / what changes | Source |
|---|---|---|---|---|
| Flags `dating_mode_enabled`, `dating_alignment_algorithm_v1`, `dating_candidate_generation`, `dating_match_messaging`, `dating_profile_photos` | All forced false on migration replay. RLS hides `dating_%` from clients; the client learns availability through `get_dating_eligibility`. | **Keep** | Good kill switches. Note `ON CONFLICT DO UPDATE SET enabled=false`: replaying that migration turns them off again. | `20260705210000:3-15`; `dating_feature_flags.dart:21-32` [C] |
| Healing gate `dating_healing_gates_hold` | `eligible_for_dating_opt_in`, every Healing stage done, **latest readiness > 70**, **8 weeks from the breakup** (4-week journey floor for self-reported). Used by eligibility, activation and `dating_candidate_is_current`. | **Replace** | New rule: no gate for new singles. A **gentle time wait only when the person's relationship ended inside Attune** (derive from `relationships.ended_at`; Healing offered, not required). The spec's "readiness journey" for never-partnered users was **never built** (`breakup_at_source` CHECK allows only `relationship` and `user_reported`). | `20260705210000:184-215,287-336,505-543`; `20260703193000_healing_mode_v1_1.sql:10`; `DATING_MODE_SPEC.md:88-102` [C] |
| Age gate `dating_age_gate_holds` and `dating_age_verifications` | Needs an unrevoked verified `birth_date` at least 18 years ago. Age in generation comes from this table. | **Change** | Feed it from the new sign-up DOB; whether self-declared is enough is owner question 2. Keep "age derived server-side, never client". | `20260705210000:17-29,217-230`; `20260933170000:97-108` [C] |
| Relationship guard `dating_has_relationship` | `pending`, `active` or `paused` blocks Dating. A trigger pauses Dating for both people when a relationship row appears. | **Keep** | It is exactly what a match → couple link needs. Watch out: a Just-for-me user who taps "Invite your partner" gets Dating paused [I]. | `20261018100300_lifecycle_hardening.sql:290-318` [C] |
| Enrollment state machine | `ineligible` → `eligible_to_opt_in` → `profile_draft` → `active`, `paused`, `exited`, `suspended`. `state_version`. Append-only consent events. | **Keep** | Matches "switch Dating on later". | `20260703194500_dating_mode_v1_1.sql:1-24`; `20260703203000:1-3` [C] |
| Consent screen | Terms v`1.2.0`, an optional historical-data checkbox, an **"I confirm I am 18 or older" checkbox** | **Change** | The age checkbox is redundant once DOB exists. Keep the terms and the separate historical consent. | `dating_consent_screen.dart:14,58-88` [C] |
| Profile: city | **Hard-coded six Ghana cities**: Accra, Kumasi, Tema, Takoradi, Cape Coast, Tamale → `city_region_code` | **Replace** | Worldwide needs `country_code` (ISO) plus a coarse city or region. The server accepts any 1–80 character string. | `dating_profile_screen.dart:25-32`; `20260705210000:460` [C] |
| Profile: intention | Long-term relationship / Intentional dating / Still figuring it out | **Change (review)** | Pending the cultural review the spec already requires (`DATING_MODE_SPEC.md:316-323`). It also feeds `intention_priorities` in the snapshot. | `dating_profile_screen.dart:34-38`; `20260933160000` [C] |
| Profile: age range | 18–70 (DB CHECK and RPC), default 25–40 | **Change** | Worldwide adults over 70 are excluded by schema; owner question. | `20260703194500:40-47`; `20260705210000:463-464`; `dating_profile_screen.dart:20-21` [C] |
| `gender_identity`, `gender_visible`, `gender_preferences`, `region_preferences`, `intention_preferences` | Columns exist. **No RPC writes any of them** (only the SQL contract test does). The client never asks. | **Change: build the writer and UI** | Interested-in (men / women / everyone) goes here, private. **Blocking bug:** `activate_dating_profile` and `dating_profile_ready` require **all three arrays non-empty**, so **no real user can ever activate**. The generation filter treats an empty array as "everyone", which **contradicts** the activation rule. Store "everyone" explicitly, or relax the predicate. | `20260703203000:8-11`; `20260705210000:106-131,268-285,525-535`; `20260813140000_dating_photo_storage_bucket.sql:59-77`; `20260933170000:117-145`; `supabase/tests/dating_mode_contracts.sql:99-105` [C] |
| Symmetric hard filters | Age range both ways, gender both ways, region and intention lists both ways, blocks, former partner, no repeat pair, prior match cooldown | **Keep** | This *is* "only mutual matches are introduced". | `20260933170000:15-160` [C] |
| Former-partner exclusion (phone HMAC) | HMAC of the verified phone with a Vault key, written by `end_relationship`, survives deletion, checked in generation, acting and listing. Fails silently if the key is unset (now monitored). | **Keep; provision the key** | Apple or Google sign-in without a phone would break it. Require a verified phone for Dating (owner question 17). | `20260712160000`; `20260931130000`; `20260933140000:1-20` [C] |
| Scoring and snapshots | Equal-weighted draft config; `love_language` absent by construction; quiz features read only **with historical consent** | **Keep; review** | The spec says that without historical consent "current self-reported quiz dimensions" are still used (`DATING_MODE_SPEC.md:110-113`). The code gates quizzes behind historical consent. Reconcile one or the other. | `20260933160000:115-170`; `20260933180000:29-67` [C] |
| Generation cadence | **Weekly** (Sunday 03:17 UTC), ISO-week cohort window, cap **5** open introductions, TTL 7 days, scan limit 200, single partition `all` | **Change** | "A few curated per day" needs a daily cohort window (the idempotency key is per week), a daily per-user drop size, a shorter TTL, and partitioning by country or region at worldwide scale. Spec §6.4 says weekly, so the spec needs amending. | `20260933170000:~299`; `20260933180000:23-27,67`; `DATING_MODE_SPEC.md:304-312` [C] |
| Introductions and double opt-in | Bands only (`limited_signal` / `some` / `promising`); double-blind viewer-scoped state (C3 fix); `act_on_dating_introduction`; atomic match | **Keep** | — | `20260712120000_dating_double_blind_fix.sql:24-40`; `20260712130000` [C] |
| Introduction payload | name, city, intention, summary, band, reasons. **No age, no photos.** `list_dating_profile_photos` returns only your own photos. | **Change** | The spec's card (§4.2) shows age, photo and city. The counterpart-photo read path is unbuilt. | `20260712160000:251-286`; photo functions list [C] |
| Matches screen | Shows the match, then First date guide, Safety resources, Unmatch, Block, Report. Copy: chat safety review "is still a production gate" | **Change** | Add the separate dating chat entry point. | `dating_matches_screen.dart:62,156-215` [C] |
| Dating chat | **Not built** (no `dating_messages` table). Spec drafted: separate table, RLS, outbox and worker; never fed to the couples AI; the shared Flutter chat surface is abstracted over a message source. | **Build new, per spec** | Must not reuse `ChatScreen` itself (games are embedded in it, §2.8). | `DATING_CHAT_SAFETY_SPEC.md:333-370`; grep [C] |
| Guided first date and private reflection | Static prompts, safety and mobile-money scam lines, quick exit, private reflection (flag-gated writes) | **Keep** | — | `dating_guided_date_screen.dart:23-26,151-264` [C] |
| Photos | Upload intent, private bucket, EXIF strip, **Google Vision** face check (confidence 0.7, area 0.06), moderation outbox | **Keep** | — | `process-dating-photo/index.ts:36-136,191-201`; `20260813130000`; `20260813140000` [C] |
| Selfie verification | **AWS Rekognition** compare of the selfie with the approved photos, setting `verification_state`; required by `dating_profile_ready` | **Keep** | It verifies photo consistency, **not age**. | `verify-dating-profile/index.ts:9-35`; `20260813140000:59-77` [C] |
| Match → couple link | Spec: "a separate mutual, verified relationship-link flow". **Not built.** | **Build new** | Reuse `create-relationship-invite` and `accept-invite` (the code exchange). The relationship guard then auto-pauses Dating for both. | `DATING_MODE_SPEC.md:347-350` [C] |
| Dashboard and intro gate copy | Brief copy: "separate from Healing… explicit consent step". Manual: Dating "only becomes available once you're eligible through Healing Mode". | **Change** | Copy contradicts the new rule. The Dating topic also shows in the pre-sign-in carousel. | `app_router.dart:1664-1677`; `dating_mode_docs.dart:58,196` [C] |
| `users.mode='dating'` writes | activate, pause, exit | **Remove** | Nothing reads them (§2.3). | §2.3 [C] |
| Notification `dating_mutual_match` | Routes to `/datingMatches` | **Keep** | — | `notification_config.dart:210-211` [C] |
| Export | "Download my data" **asserts there is no `dating` section** | **Owner and legal question** | Worldwide privacy law may require exporting your own dating data. | `supabase/tests/data_export_contracts.sql:229-233` [C] |
| Country-aware safety notes | **None.** Safety resources are hard-coded for Ghana, the US and the UK. Research 06 F10 (country-routed resources with `country_code` and an LGBTQ+ category) is unbuilt. | **Build new** | Needs the dating `country_code` and reviewed per-country content. | `safety_resources_screen.dart:121-141`; research 06 §3 F10 [C] |

### 2.5 Forum removal blast radius (exhaustive)

**Size.** Client: about 22 files deleted (about 6,000 lines) and 14 files edited. Server: 2 edge functions, **3 cron jobs (one exists only in the database)**, 3 operator SQL scripts, about 30 forum-only SQL functions, 8 forum-only tables and 2 views to drop later. **Some objects carry a "forum" name but serve Opinions and must stay** (§2.5.6).

#### 2.5.1 Client files to delete

| File(s) | Notes |
|---|---|
| `lib/features/forums/**`, 18 files, 5,776 lines: `forum_feed_cache.dart`, `forum_post_model.dart`, `topic_model.dart`, `forum_repository.dart`, `forum_providers.dart`, `contributing_forums_screen.dart`, `debate_room_screen.dart`, `forum_insight_screen.dart`, `forums_explore_screen.dart`, `forums_section.dart`, `side_selection_screen.dart`, `submit_topic_screen.dart`, `forum_card.dart`, `forum_card_subdetails.dart`, `forum_post_bubble.dart`, `mini_container_indicator.dart`, `topic_impression_tracker.dart`, `topic_voting_card.dart` | [C] |
| `lib/home/widgets/forum_home.dart` | Already dead [C] |
| `lib/app/documentations/user_manual/data/forum_docs.dart` (topic id `forums`) | The manual guard needs at least 33 topics; 34 remain (`test/app/documentations/manual_content_guard_test.dart:24`) [C] |
| `test/features/forums/forum_feed_cache_test.dart` | [C] |

#### 2.5.2 Client files to edit

| File | What to change | Source |
|---|---|---|
| `lib/app/routing/app_router.dart` | Remove forum imports `35-38`, `RouteNames.debateRoom/sideSelection/forumInsight` `245-247`, and routes `549-599` | [C] |
| `lib/core/notifications/config/notification_config.dart` | Cases `forum_topic_activated`, `forum_activity`, `forum_quiet` push `forumInsight` (`163-172`). Change to `home` **before** the route goes, or a stale push throws. **Keep** `forum_content_removed` and `forum_posting_banned` (`185-192`); they are Opinions moderation (§2.5.6). | [C] |
| `lib/features/opinions/presentation/screen/opinions_tab.dart` | Imports `9-11`; the outer `TabController(length: 2)` and `IndexedStack` with `ForumsSection` `35,65-80`; the FAB `onTopicSubmitted` `188-202`; the chooser `235`; outer tab items "Opinions / Forums" `337-342` | [C] |
| `lib/features/opinions/presentation/screen/tag_browse_screen.dart` | Forum imports `5-7`, `forumTopicsByTagProvider` `97,108,241,319`, the "Forums" tab `188`, the empty state `313`, `ForumCard` `339` | [C] |
| `lib/core/widgets/create_content_chooser.dart` | Imports `SubmitTopicScreen` `4`; the topic branch `44-49`; the "Start a forum topic" row `100-115`. The chooser collapses to a direct compose. | [C] |
| `lib/core/widgets/create_content_fab.dart`, `lib/features/opinions/presentation/screen/discover_feed_screen.dart:164` | Drop `onTopicSubmitted` | [C] |
| `lib/features/opinions/presentation/screen/tag_search_screen.dart:57` | Hint "Find opinions and forums…" | [C] |
| `lib/features/onboarding/presentation/widgets/profile_setup_step.dart:22` | "Opinions and forums stay anonymous." | [C] |
| `lib/app/documentations/user_manual/data/manual_documentation_registry.dart:22,133` | Unregister `ForumDocs()`. The intro and LoginProfile carousels change with it. | [C] |
| `lib/i10n/app_*.arb` (`app_en.arb:321`, `app_fr.arb:326`, `app_it.arb:326`, plus de, es and pt) and generated files | `mutedItemSubtitle` "Anonymous forum accounts you've muted" | [C] |
| `lib/app/documentations/user_manual/data/opinions_docs.dart:3` | Comment says it is "sourced from FORUM.md". FORUM.md §4 still documents Opinions, so **keep FORUM.md** and mark §5 retired. | [C] |
| Comment-only mentions (no behaviour): `nav_visibility_provider.dart:7-8`, `home_widget.dart:167`, `feed_cache_store.dart:10`, `poll_*`, `relationship_status_display.dart:5`, `relative_time.dart:4-6`, `format_compact_count.dart:4`, `count_broadcast_channel.dart:12`, `reply_avatar_stack.dart`, `universal_bubble.dart`, `tag_chip_row.dart`, `tag_picker.dart`, `chat_text_field.dart:195-201`, `chat_state.dart:366`, `reflection_journal_*`, `reminders_providers.dart:50`, `settings_data.dart:131`, `app_theme.dart:385-389`, `app_colors.dart:36` | Optional tidy-up. **Do not change behaviour** (§2.5.6). | [C] |
| Tests: `test/widget_test.dart:11,26` (imports `forum_providers` for the two-tab shell test); `test/core/notifications/notification_tap_routing_test.dart:24-32` (forum payload group) | Edit | [C] |
| Tests to **keep**: `test/core/widgets/universal_bubble_test.dart:329,500-608` (the "forums-shaped bubble" guards protect `UniversalBubble`, which chat and games use); `test/app/theme/design_tokens_test.dart:11` | — | [C] |

#### 2.5.3 Edge functions, jobs and scripts

| Object | Schedule / role | Source |
|---|---|---|
| `supabase/functions/activate-topics` | Cron `activate-topics-sweep` `'23 * * * *'`; inserts `forum_topic_activated` | `20260907120000_register_scheduled_jobs.sql:44,173-177`; `activate-topics/index.ts:34-107` [C] |
| `supabase/functions/forum-quiet-check` | Cron `forum-quiet-check` `'7 */2 * * *'`; queues `forum_quiet` | `20260907120000:46,185-189` [C] |
| **`mark-quiet-forums`** | **Untracked.** Registered by hand (jobid 3, `'0 1 * * *'`); no migration creates it; patched by an operator script. Must be unscheduled *by name* before `forum_topics` is dropped, or it fails nightly and unread. | `20260727130000_forum_activity_notifications.sql:360-381`; `supabase/sql/patch_mark_quiet_forums_null_last_post.sql:1-30`; cron failures go unread, `20260931120000_vault_backed_settings.sql:1-20` [C][D: live jobid] |
| Operator scripts `supabase/sql/schedule_activate_topics.sql`, `schedule_forum_quiet_check.sql`, `patch_mark_quiet_forums_null_last_post.sql` | Delete with the jobs | [C] |
| `process-scheduled-notifications` | Payload allowlist keeps `forum_post_id` and `topic_id` (`index.ts:102-108`). Leave until the forum notification rows are gone. | [C] |

#### 2.5.4 Notification types

| Type | Producer | Verdict |
|---|---|---|
| `forum_topic_activated` | `activate-topics` | Remove |
| `forum_activity` | `private.queue_forum_activity_notifications` (inside `create_forum_post`) | Remove |
| `forum_quiet` | `notify_quiet_topic` / `forum-quiet-check` | Remove |
| `forum_content_removed` | `admin_confirm_content_removal` for **opinion, comment** and forum post | **Keep** (rename later if wanted) |
| `forum_posting_banned` | Same function; posting ban for **Opinions** | **Keep** |

Sources: `20260727130000:157-276,382-430`; `20260727120000_opinion_engagement_and_moderation_notifications.sql:381-454`. [C]

#### 2.5.5 SQL objects, in drop order (later)

- **Forum-only tables (8):**
  - `forum_topics`, `topic_votes`, `topic_impressions`, `forum_posts`, `forum_post_likes`, `user_forum_sides` (`20260716120000_forums_opinions_launch.sql:107-180`);
  - `forum_topic_tags` (`20260731120000_opinion_and_forum_topic_tags.sql:79`);
  - `forum_topic_visits` (`20260727130000:71`).
- **Views (2):** `public_forum_topics`, `public_forum_posts` (`20260716120000`, `20260730140000`, `20260809120000`).
- **Forum-only functions (about 30):**
  - `activate_pending_topics`, `expire_old_topics`, `mark_quiet_topics`, `notify_quiet_topic`, `record_forum_topic_visit`, `private.queue_forum_activity_notifications`;
  - `create_forum_post`, `create_forum_topic`, `create_forum_topic_with_poll`, `edit_forum_post`;
  - `attach_forum_topic_tags`, `get_forum_topic_tags`, `get_forum_topics_by_tag`, `get_tags_for_forum_topics`, `get_polls_for_topics`;
  - `get_active_forums_filtered`, `get_quiet_forums_filtered`, `get_voting_topics_filtered`;
  - `increment/decrement_topic_upvote_count`, `increment/decrement_topic_downvote_count`, `increment/decrement_topic_post_count`, `increment_topic_seen_count`, `increment/decrement_forum_post_like_count`;
  - `report_forum_post`, `report_forum_topic`.
  - Grep of `FUNCTION … (forum|topic)` across migrations. [C]
- **Contract tests** that name forum objects: `supabase/tests/security_lockdown_contracts.sql:17` (`public.forum_topic_tags`). [C]
- **Account deletion**: forum rows cascade from `auth.users` (`submitted_by` and `user_id` FKs `ON DELETE CASCADE`, `20260716120000:107-190`). **Data export**: nothing to change; its contract already forbids a `forum` section (`data_export_contracts.sql:229-233`). [C]

#### 2.5.6 What Opinions shares with Forums and must stay

| Shared object | Why it stays | Source |
|---|---|---|
| **`forum_reports` table** | `report_opinion` and `report_opinion_comment` insert into it (`opinion_id`, `comment_id` columns, dedup indexes) | `20260716120000:182-190`; `20260802120000_report_dedup_and_ban_extension_fix.sql:25-32,65-135` [C] |
| `admin_confirm_content_removal` and `profiles.banned_until` | Three confirmed removals give a 7-day ban for opinions and comments too; only its `forum_post` branch goes | `20260722120000_forum_ban_enforcement.sql:1-20`; `20260802120000:206-231` [C] |
| `private.assert_can_post` | Opinion 5 per day plus 60 s cooldown, comment 20 per day; only the `topic` branch goes | `20260716140000_forums_opinions_anonymity_hardening.sql:73-118` [C] |
| `private.enqueue_forum_notification` | The helper behind every Opinions notification (like, comment, reply, repost, quote, moderation) | `20260727120000:50-107,214,316,332`; `20260728120000:128`; `20260729120000:90` [C] |
| `post_polls` (+ `poll_options`, `poll_votes`), `PollCard`, `poll_repository`, `poll_providers` | Polls on opinions. `topic_id` FK plus `CHECK num_nonnulls(opinion_id, topic_id) = 1`; drop the column and constraint *after* `forum_topics` | `20260726120000_polls_on_opinions_and_topics.sql:32-42` [C] |
| `tags`, `opinion_tags`, `tag_follows`, `TagChipRow`, `TagPicker` | Opinion tags | `20260731120000:31,68`; `20260825120000_tag_follows.sql:20` [C] |
| `FeedCacheStore` (keep) vs `forum_feed_cache.dart` (delete) | Opinions cache | `lib/core/cache/feed_cache_store.dart` [C] |
| `ListviewLoadingShimmer` / `ForumSchimmer` | Used by 8 Opinions screens | `lib/core/widgets/shop_listview_loading_shimmer.dart`, `forum_shimmer.dart` [C] |
| `relationship_status_display.dart` | Opinions cards and threads, the locked chat screen | [C] |
| `count_broadcast_channel.dart`, realtime count triggers | Opinion like and dislike counts | `20260826120000_realtime_count_broadcasts.sql:21-130` [C] |
| `ThemeColors.against` | Also used by `couple_map/widget/presentation/region_map_painter.dart` | `app_theme.dart:385-391` [C] |
| `UniversalBubble`, `ChatTextField` (forum-only optional parameters) | Shared with chat, comments and **games** (`game_message_bubble.dart`). Leave the parameters. | grep [C] |

#### 2.5.7 Safe removal order

1. **Client release (no data loss).**
   - Route forum notification taps to home.
   - Remove the Forums tab, the chooser's topic option, the tag-browse Forums tab, the debate, side-selection and insight routes, `ForumDocs`, and the copy (onboarding line, l10n string, tag search hint).
   - Delete `lib/features/forums/**`, `forum_home.dart` and the forum cache test. Edit `widget_test.dart` and the routing test.
   - Keep every shared object in §2.5.6.
2. **Server: stop producers** (same week).
   - Unschedule `activate-topics-sweep`, `forum-quiet-check` and **`mark-quiet-forums`** by name.
   - Delete or undeploy both edge functions and the 3 scripts.
   - Revoke EXECUTE on the forum RPCs (including the anon grants from `20260821120000_public_forum_reads.sql`) so old builds fail closed.
   - Mark the 3 forum-only notification types `cancelled` in the outbox.
3. **Later migration (after one release in the field).**
   - Drop the views, then the forum-only functions, then the 8 tables.
   - Then remove `post_polls.topic_id` and its CHECK.
   - Then the `forum_post` branches of `assert_can_post` and `admin_confirm_content_removal`.
   - Optionally rename `forum_reports` → `content_reports` and `enqueue_forum_notification` → `enqueue_community_notification`, updating every caller in the same migration.
   - Update `security_lockdown_contracts.sql:17`.

### 2.6 Opinions today

| Capability | How it works | Source |
|---|---|---|
| Anonymity | `opinion_author_handle(uid)` = HMAC(user_id, private secret). **Stable per author, not daily-rotating.** Decision 21 said daily rotation for forums; follows depend on a stable handle. The real `user_id` never reaches the client. | `20260716140000:13-64`; `ATTUNE_MASTER_SPEC.md:3071`; `opinion_model.dart:17-20` [C] |
| Status label | `relationship_status_at_post` (single / taken / figuring_it_out / open) captured from `profiles.relationship_status`, shown as an S/T/F/O glyph | `20260716120000:43-57`; `relationship_status_display.dart:23-58` [C] |
| Feeds | Following and Discover RPCs; tag-filtered feeds | `20260716140000:127-236`; `20260806120000_tag_filtered_discover_feeds.sql` [C] |
| Compose | `create_opinion`, `create_opinion_with_poll`, `create_opinion_with_quote`; content up to 5,000 characters; tags capped | `opinion_repository.dart`; `20260807120000_raise_content_length_to_5000.sql`; `20260801120000` [C] |
| Reactions | like and dislike; own-post reactions blocked by RLS; live counts | `opinion_card.dart:647`; `20260826120000` [C] |
| Comments | threaded replies, comment likes | `20260716140000:242-282,479-519` [C] |
| Saves, reposts, quotes | `opinion_saves`, `opinion_reposts`, quote lookups and counts | `20260727140000`, `20260728120000`, `20260729120000`, `20260820120000` [C] |
| Follow | authors by handle, tags | `20260716140000:362-441`; `20260825120000` [C] |
| Mutes and hides | `opinion_mutes`, `opinion_hides`, Muted authors screen | `20260730130000_opinion_mute_and_hide.sql:24,46`; `muted_authors_screen.dart` [C] |
| Edit window | 15 minutes, enforced server-side | `opinion_model.dart:3-13`; `20260730120000` [C] |
| Limits | 5 opinions per 24 h, 60 s cooldown, 20 comments per 24 h; ban gate | `20260716140000:73-118` [C] |
| Moderation | Reports go to `forum_reports`; auto-hide at a threshold; `admin_confirm_content_removal` (service role only, **no admin UI**) leads to a ban and notices | `20260722120000:1-20`; `20260802120000` [C] |
| Guest read-only | Anon reads of opinions, tags, quotes and status | `20260818120000_public_opinion_reads.sql`; `20260822*`, `20260823*` [C] |
| Notifications | `opinion_liked`, `opinion_commented`, `opinion_comment_reply` route to the thread loader | `notification_config.dart:174-183` [C] |

**If Opinions becomes *the* community surface:**
- **Simplify `OpinionsTab`.** Drop the outer tab bar and `IndexedStack`; keep Following and Discover and the guest-lands-on-Discover rule (`opinions_tab.dart:115-139`). The FAB composes directly.
- **Re-state the anonymity contract.** It is a *stable pseudonym* (handle-level follows and profiles exist, `anonymous_profile_screen.dart`), not daily rotation. Decision 21 needs amending to match the code, or the code changed.
- **The status label becomes the only public relationship signal.** It is written once at onboarding and never updated (§2.2), so it goes stale on pairing or ending. It needs path-aware values and resync (owner question 7).
- **Moderation load concentrates on one surface with no admin UI.** Fine for a fresh start; worth a named owner.
- Keep the Opinions ↔ Dating separation. No link from a handle to a dating profile; the handle derives from `user_id` only.

### 2.7 Navigation

**Today.**
- Two tabs, Opinions and Chat (`home_screen.dart:375-397`).
- **Decision 11** (`ATTUNE_MASTER_SPEC.md:3061`): "2 tabs: Opinions and Chat; Opinions default for anonymous/single users, Chat default for couples; dot not badge".
- §9 says Opinions holds a "Nested Forums area" (`:2729-2731`).
- Decision 33 and research 06 §5.4 later added: a "Plans" card first under Chat, "no new tab" (`ATTUNE_MASTER_SPEC.md:3084`; synthesis §5.4 last row).
- `HomeWidget` supports 2–5 tabs, but **applies `initialTabIndex` only in `initState`** (`home_widget.dart:39-43,58-59`). A path switch needs a keyed rebuild.

**What each path's home should become** (recommendation, keeping decision 11's two-tab shell):

| Path | Tab 1 | Tab 2 (default after onboarding) | Built today? |
|---|---|---|---|
| In a relationship | Opinions | **Chat**: linked → `ChatHomeScreen` (Plans first); pending → the waiting part of `ChatCouplesLockedScreen`, plus the couple profile | Mostly |
| Single and open to dating | Opinions | **Dating**: today's introductions, matches, the separate dating chats, plus journal and quiz entries | Dashboard exists (`dating_dashboard_screen.dart:60-97`); chat and photos-in-cards missing |
| Just for me | Opinions | **Me**: journal, quizzes (today on Profile and Pulse), Healing, quiet "Invite a partner" and "Turn on Dating" rows | The `ChatCouplesLockedScreen` personal variant is the nearest; quizzes live at `know_yourself_section.dart:282,315` |

### 2.8 Everything NOT to touch: in-chat Games

- **Folders.** `lib/features/games/**`: constellation, data, dots_and_boxes, invites, love_map, mirror, paint_ball, presentation, scenario, session_games, sliding_scale, snakes_and_ladders, thirty_six_questions, this_or_that, truth_or_dare, word_hunt. Plus `lib/features/community/**` (games' community questions, `/communityFeed`, `app_router.dart:1294-1302`). [C]
- **Chat entry points.**
  - `chat_screen.dart:69-78` (game imports), `:2137` (`showGames: true`), `:5189` (`ChatGamesSheet`);
  - `message_bubble.dart:41-43` (game bubbles);
  - `reply_composer_preview.dart:3-4`;
  - `seen_receipts_repository.dart:2` (`games_hub_providers`).
  - **Dating chat must be a separate screen**, not a mode of `ChatScreen`. [C]
- **Routes.** Game imports `app_router.dart:18-25,69-97`; game routes `:1003-1392,1679-1760`. Leave untouched when forum and dating routes change in the same file. [C]
- **Couplings the flow change must avoid.** [C]
  - `profiles.display_name`: 8 game call sites read the partner's name (`game_partner_name_provider.dart:38` and others). Keep the column and its public read.
  - The `auth_exports.dart` barrel is imported by `custom_truth_or_dare_list_screen.dart:3`. Do not delete or narrow the barrel while removing dead auth screens.
  - `UniversalBubble` is used by `game_message_bubble.dart`. Do not "clean" its forum-only parameters.
  - `Ask2RevealStep` links to `loveMap` and `thisOrThatGamesHub` (`ask2_flow.dart:121-122`).
  - `relationships.games_completed`; the game-invite notify migrations `20260930150000`–`20260937140000`.
  - `DocumentationRegistry` related topics for `games` (`manual_documentation_registry.dart:77-78`).
  - Games report through `report_custom_question`, not `forum_reports` (`this_or_that_repository.dart:357-365`), so forum removal does not affect games.

---

## 3. Implications for Attune

### 3.1 What to build, change, avoid or measure

1. **Collect DOB before anything that creates relationship data.** The new order should be OTP → EULA (bumped to v2 with 18+ and UGC terms) → DOB → name → path.
   - Store the DOB in a private table with an RPC writer (§2.2.4 #1).
   - Add an age check inside `accept-invite`.
   - Why: today an invitee is linked *before* the name step (`onboarding_gate.dart:41-44`), and nothing checks age (§2.1.5). The EULA text has no age clause (`app_en.arb:473`), and `currentVersion='1'` (`eula_acceptance_service.dart:21`).
2. **Store the path on the account (`users.path`) and treat relationship and dating state as derived.** Why: the two relationship-less paths are indistinguishable today (`relationship_mode_sync.dart:14-23`), and `users.mode` is write-only (§2.3). In the same migration, lock `users` column grants (`20260724120000:13`), or the new column is client-writable.
3. **Retire `users.mode` and the `healing` mode value; stop the eight writers listed in §2.3.** Why: a second "mode" that nobody reads invites future bugs. This is a fresh start, so no backfill is needed.
4. **Build the couple profile as `couple_profiles` plus an RPC plus a Together change signal**, never as `relationships` columns (§2.2.4 #3).
   - Add a contract test that it produces no type or score.
   - Ban elapsed-time rendering of "together since".
   - Why: the relationships grants model (`20261018100100:34-41`), research 06 §5.3–5.4, and the owner's "never a type or a score".
5. **Wire "Add your anniversary" to the couple profile instead of a parallel date.** Why: two sources of "when we got together" (`reminders` vs the profile) will drift. `together_screen.dart:1293`.
6. **Fix Dating activation before any flag flip.** Build the writer for `gender_identity`, `gender_preferences`, `region_preferences` and `intention_preferences`, and resolve the empty-array contradiction. Why: activation is impossible today (§2.4, `20260705210000:525-535` vs `20260933170000:117-145`).
7. **Replace the Healing gate with "ended in Attune → gentle time wait"** in the three places it is checked: `get_dating_eligibility`, `activate_dating_profile`, `dating_candidate_is_current`. Remove the readiness-score requirement. Why: owner decision. The never-partnered path was never built (`healing_mode_v1_1.sql:10`).
8. **Change generation from weekly to a daily cohort with a small per-user drop and a shorter TTL, partitioned by country.** Amend `DATING_MODE_SPEC.md` §6.4. Why: the idempotency key is weekly (`20260933170000:~299`); worldwide needs partitioning.
9. **Go worldwide in Dating data.**
   - Add `country_code` and a coarse region.
   - Drop the Ghana city list.
   - Widen the 18–70 age bounds (owner question).
   - Add age and approved photos to the introduction payload.
   - Build a country-routed safety notes and resources model (research 06 F10).
   - Why: §2.4 rows for city, age range, payload and safety notes.
10. **Build the dating chat from `DATING_CHAT_SAFETY_SPEC.md` after its §12 sign-off**, as its own table, outbox and screen. Why: the spec requires structural isolation (`:337-350`), and `ChatScreen` embeds games (§2.8).
11. **Build the match → couple link on the existing invite exchange.** Why: the relationship guard already pauses Dating on a pending link (`20261018100300:290-318`).
12. **Keep the phone as the identity anchor even when Apple or Google arrive.** At least require a verified phone for Dating and for couples invites. Why: `users.phone NOT NULL` (`20260606133000:7-8`), `record_eula_acceptance` raises `phone_required` (`20260817120000:55-60`), onboarding submit silently skips (`onboarding_submission_service.dart:33-34`), and the former-partner exclusion is a phone HMAC.
13. **Remove Forums in the three-stage order of §2.5.7.** Keep every shared object in §2.5.6. Why: the moderation types, reports table, posting limits, polls and notification helper serve Opinions.
14. **Simplify Opinions to one section; make the status label path-aware and kept in sync; amend decision 21 to "stable pseudonym".** Why: §2.6.
15. **Delete the dead auth and shell code (§2.1.6) in a separate change, not mixed with the flow change.** Why: it shares barrels with games (`auth_exports.dart`), and a combined diff hides regressions.
16. **Owner amendments needed** (the researcher cannot edit these):
    - `ATTUNE_SOUL.md:73` ("a forum");
    - Master Spec decisions 11, 18, 20, 21, 22, 23, 25, §2 modes and §9 tab contents;
    - `AUTH_ONBOARDING_ENGINE.md` (§2.1.7);
    - `DATING_MODE_SPEC.md` §2, §3.1, §4.1, §6.4.
17. **Measure.** Add a health check (like `get_dating_operational_health`) for:
    - accounts without a DOB;
    - accounts without a path;
    - relationships ended without an exclusion row (already exists, `20260933140000`);
    - forum crons still scheduled.

### 3.2 Reuse / change / build-new

| Area | Reuse as is | Change | Build new |
|---|---|---|---|
| Boot, router, root shell | `main.dart` init; `appShell` safety layers; `waitForRouterSettled` | Router redirect (pre-auth DOB and path screens); drop forum routes; path-aware `/home` | — |
| Intro and guest | Intro carousel widget; `LoginProfile` shell | Carousel content (no Forums; Dating copy); guest overview copy (not couples-only) | — |
| Sign-in | `PasswordlessAuthService`, `LoginScreen` (phone and WhatsApp), country picker, `EulaGate` | EULA v2 (18+, UGC); voice OTP fallback per `AUTH_ONBOARDING_ENGINE.md:69-71` | Apple and Google (later) on the existing `AuthService` methods, with phone linking |
| Onboarding | `OnboardingStore` scoping and pending-submission replay; `OnboardingDeckScope`, `OnboardingStepFrame`, quiz and anchor steps; `CouplesWaitingStep`, `PendingInviteGuide`; Ask 2 | Mode step → 3-path step; profile copy; `_finish` writers (path, no `users.mode`); invitee order (DOB before accept); scope the invite key | DOB step; couple-profile step (Relationship path); dating setup hand-off (Dating path) |
| Identity data | `users`, `profiles` (display name for games), `onboarding_profiles` | `users` column grants; retire `mode`; `onboarding_profiles.mode` | `account_birthdates`; `users.path` |
| Couples | Invite functions, lifecycle RPCs, `chat_name` and avatar, reminders, family members, change signals, export bundle | `accept-invite` age check; paused stays on the Relationship home | `couple_profiles` plus RPC, UI, export entry and contract test |
| Home and navigation | `HomeWidget` (2–5 tabs), `HomeTab`, `AuthenticatedChatWorkspace` | `HomeScreen` tab-2 choice by path; keyed rebuild on path change | Me home; Dating home tab container |
| Dating | Enrollment machine, consent events, flags, hard filters, double opt-in, exclusion HMAC, photos and Vision, Rekognition verification, guided date, reflections, block, unmatch, report | Eligibility (Healing out, wait in); age gate source; consent age checkbox; city → country; age bounds; preference writers; activation predicate; daily cadence; intro payload (age, photos); copy and docs | Dating chat (table, outbox, worker, screen); country safety notes; match → couple link; counterpart photo read |
| Opinions | Everything in §2.6 | Single-section tab; chooser removal; status label sync; decision 21 wording | — |
| Forums | — | — | Removal migrations (§2.5.7) |
| Games | Everything | Nothing | Nothing |

### 3.3 Risk list (regressions in shared files)

| # | File / object | Risk | Mitigation |
|---|---|---|---|
| R1 | `lib/home/home_screen.dart` | It owns onboarding redirect latching (`340-364`, the "storm of repeated redirects" comment), relationship-mode sync (`150-228`) and pending-invite retry (`278-319`). Adding path logic here can re-open the sign-in redirect storm or strand a couple behind the locked screen. | Add the path as one more field on `_HomeGateData`. Keep the latch and the `ModalRoute.isCurrent` guard unchanged. Extend `test/home/*` (3 test files) first. |
| R2 | `lib/app/routing/app_router.dart` | First-launch redirect forces `/intro` for **every** route (`422-425`). New pre-auth screens or deep links will bounce. The file also hosts all game routes. Removing the forum routes before the notification cases change makes stale pushes throw. | Change `notification_config.dart:163-172` first. Touch only the forum and dating blocks. |
| R3 | `lib/main.dart` | Invite deep links clear first launch and go to `/onboarding` (`210-228`). A new DOB or path step must not let the gate accept the invite earlier. | Move acceptance after the DOB step, and enforce the age check server-side too. |
| R4 | `OnboardingStore` | Renaming enum values breaks the `mode` getter (unknown → null, `156-163`) and pending-submission decoding (`34-53`). Test devices keep old prefs. The invite-code key is unscoped (`70`). | Add new keys rather than renaming. Clear old keys once. Scope the invite key per user. |
| R5 | `OnboardingSubmissionService` | Silent early return without a phone (`33-34`). With Apple or Google, users look onboarded locally but have no server rows. | Make it throw or route to "add phone", with a test. |
| R6 | `users` grants | Any new column is client-writable via `20260724120000:13`. Tightening breaks the onboarding upsert that writes `mode`. | Change the grants and the client writer in one release. |
| R7 | `relationships` grants | New columns are invisible through the column-level SELECT (`20261018100100:34-41`). | Use `couple_profiles`. |
| R8 | `opinions_tab.dart` / `tag_browse_screen.dart` | Removing the outer `TabController` and `IndexedStack` changes the header, the nav-visibility reset listeners (`39-46`) and guest landing (`115-139`). Visual regression risk in the Opinions header. | Widget test for guest and signed-in landing; screenshot check. |
| R9 | Moderation objects named "forum" | Removing `forum_content_removed`, `forum_posting_banned`, `forum_reports` or `enqueue_forum_notification` with Forums **breaks Opinions moderation and notifications**. | §2.5.6 keep list. |
| R10 | Untracked `mark-quiet-forums` cron | Fails silently every night after the table drop. | Unschedule by name in stage 2. |
| R11 | Dating predicates | `dating_candidate_is_current` also filters matches (Fable H4a). Changing eligibility shifts match visibility. | Re-run `supabase/tests/dating_mode_contracts.sql`. It still needs CI per memory. |
| R12 | Generation cohort | The weekly idempotency key silently caps any daily schedule at one run per week. | Change the cohort format together with the cron. |
| R13 | `DocumentationRegistry` | Removing `ForumDocs` changes both carousels. Dating docs still promise a Healing gate. | Update the Dating docs in the same change. The guard test at ≥33 still passes with 34. |
| R14 | Games coupling | `auth_exports.dart` barrel, `UniversalBubble`, `profiles.display_name`, `ChatScreen`. | §2.8. |
| R15 | Formatting | Repo rule: never `dart format` existing files (project memory), or edited files reflow and diffs explode. | Format new files only. |

---

## 4. Open questions for the owner

| # | Question | Recommendation |
|---|---|---|
| 1 | Where do DOB and the path question sit in the first run? | **After OTP and EULA, DOB first, then name, then path.** An under-18 then never creates relationship or Dating data, and an invitee's age is known before linking (R3). |
| 2 | Is a self-declared sign-up DOB enough for Dating, or does Dating keep a verified age (`verify_dating_age`)? | Self-declared for the app. **Dating keeps a verified tier** (provider or ID step) where law or risk requires it. Rekognition verifies photo consistency, not age (§2.4). Needs legal input per market. |
| 3 | What happens to someone who enters an age under 18? | Store nothing, show a neutral message, sign out. No retry loop that teaches the cut-off. Confirm with legal. |
| 4 | "Every change visible to both": live values only, or a change notice? | **Both see the current values live, plus a quiet "Last edited by Ama · 12 Oct" line.** No push, no activity feed (research 06 §5.3 #6). |
| 5 | Stage values: yours (dating / engaged / married + year / other) or research 06's (new / established / engaged / married / parents / later-life)? | **Yours**, with children as a separate field and no "parents" stage. The couple's own words for "other". |
| 6 | Children: a simple answer, or names and birthdays? | Simple enum on the profile. Optional **link to the existing family members** (add a `relation` column) rather than a new child table. |
| 7 | Opinions status label for Dating and Just-for-me users? | Relationship → "Taken", Dating → "Single", Just for me → the user chooses (including none). **Re-sync on every path or link change**; today it never changes after onboarding. |
| 8 | Retire `users.mode` now? | **Yes.** Replace it with `users.path` in one migration with all eight writers updated (fresh start, nothing reads it). |
| 9 | Dating geography: how should region preference work? | Country (ISO) required, coarse city from a per-country list, preference "my city / my country / anywhere". Never GPS (`DATING_MODE_SPEC.md:152`). |
| 10 | Gender identity options, and how "everyone" is stored | Ask only inside Dating, never at sign-up. Store "everyone" as an explicit full set so the activation predicate stays simple. Keep `gender_visible` default false. |
| 11 | Daily curated count and lifetime | Config-driven: 1–3 per day, open cap 3–5, TTL 2–3 days, **no countdown copy** (Fable M8). Validate in pilot. |
| 12 | How long is the gentle wait after an Attune relationship ends? | Keep a time wait from `relationships.ended_at` (today 8 weeks); drop the readiness score; Healing offered, never required. Needs clinical review. |
| 13 | Should "Download my data" include your own Dating data? | **Yes**: your own profile, preferences and consents, never another person's. Needs legal confirmation; the contract test changes with it. |
| 14 | When are forum tables dropped, and is `forum_reports` renamed? | Drop after one release in the field. Rename to `content_reports` in the same later migration, or keep the name with a comment. |
| 15 | Second-tab label per path | Keep the two-tab shell (decision 11). Label it **Chat / Dating / Me** by path. |
| 16 | Should Just-for-me users see "Invite a partner" and "Turn on Dating"? | Yes, one quiet row each on the Me home ("Dating can be switched on later"). |
| 17 | When Apple or Google sign-in arrives, is a phone still required? | **Yes for Dating and couples invites** (the exclusion HMAC and abuse response depend on it). Optional for Just for me. |
| 18 | Who signs off `DATING_CHAT_SAFETY_SPEC.md` §12, and who owns Opinions moderation (no admin UI)? | Name both owners before the build starts. The dating chat spec is the right basis; approve it before code. |
| 19 | Spec amendments (SOUL line 73, Master Spec decisions 11/18/20/21/22/23/25, `AUTH_ONBOARDING_ENGINE.md`, `DATING_MODE_SPEC.md` §2/§3.1/§4.1/§6.4) | Approve the wording in the decision document so specs and code stop drifting. |

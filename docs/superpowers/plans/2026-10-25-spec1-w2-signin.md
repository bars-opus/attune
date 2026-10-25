# Spec 1 W2 (Sign-in v2: W2a, W2b, W2c) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Behind `flow_signin_v2`, replace IntroScreen, LoginScreen and EULA v1 with Spec 1's sign-in: Welcome and its three previews, the guest birth-year gate (G1), the under-18 stop (X1) with its 30-day device block, the pre-auth invite landing (RI-1/RI-2), one `/signup` route hosting name → date of birth → phone → code → consent (A1–A5), "No account" (N1) and "Welcome back", EULA v2, a queued `complete_sign_up`, and, on the server, phone codes that can go by SMS, WhatsApp or a call through a Send SMS Hook that honours a channel request only when it is fresh, capped and from one device. With the flag off, today's flow is unchanged and tests prove it.

**Architecture:** Three sub-waves. **W2a** adds the motion tokens, `SharedAxisStep`, `AllowLargeText`, a small set of accessible flow widgets, the first screens (WL1, previews, G1, X1, RI-1/RI-2) and one router seam, `lib/app/routing/sign_in_redirect.dart`, which holds today's first-launch rule unchanged plus the v2 rules (pre-auth allow-list, guest gate, under-18 block). **W2b** adds pure validators, the device draft, `AccountService` over W1's `complete_sign_up` / `get_my_home_state`, a widget-free `SignUpCoordinator`, the step widgets and `SignUpFlow`, the queued A5 replay, EULA v2, LoginProfile's "Join Attune", and the resume rule that brings an unfinished sign-up back to `/signup`; W2b sends codes through Supabase's built-in SMS. **W2c** adds migration 7 (`otp_delivery`), two edge functions (`otp-delivery-intent`, `send-sms-hook`) with Twilio, Meta WhatsApp and Arkesel adapters, the client's delivery intent, WhatsApp and call options, and Android SMS autofill (`smart_auth`) plus iOS `webcredentials`. Every Dart, Deno and SQL block below was run while writing this plan: the Dart and Deno in a scratch copy of the tree (each sub-wave's end state built and tested on its own: 293, 310 and 342+ passing tests), the SQL on a scratch Postgres 17 restored from `attune_spec3a`'s schema (`pg_dump --schema-only`, read-only on `attune_spec3a`), the migration applied twice, the contract green, and its mutant red with the message quoted.

**Tech Stack:** Flutter 3.29.1 (Dart 3.7), Riverpod 2.6, GoRouter 10.2, Supabase Postgres 17 (pg_cron, Vault-backed `public.app_setting`), Supabase CLI 2.75, Deno 2 for edge-function tests, `smart_auth` 3.2.0 (new), psql.

**Spec:** `docs/superpowers/specs/2026-10-24-app-flow-identity-design.md` — §1.3–1.5, §2 (copy, motion tokens, accessibility, permissions, flags), §3.1–3.4, §3.6, §3.14–3.15 (W2 parts), §4 rows tagged W2a–W2c (migration 7, `private.otp_*`, `otp_record_intent`, `otp_take_send_decision`, `otp_purge`, `otp-delivery-intent`, `send-sms-hook`, the auth settings note, cron `otp-purge`), §5.1–5.6 rows tagged W2*, §7 (W2 contracts, Deno and Flutter tests, mutants), §8 W2a–W2c and the W2 group gate, §9, §11. Format reference: `docs/superpowers/plans/2026-10-25-spec1-w1-identity.md`.

## Global Constraints

- Work in the main working tree on `main` (`/Users/user/attune`). The owner and W1's final review may have uncommitted edits: never revert, stash, stage, checkout or reformat them. Every edit below is an exact-string replacement; if the text to replace has moved because W1 changed it, apply the same change to W1's current text and say so in the task report.
- **NO commits.** No `git add`, `git commit`, `git stash`, `git checkout`, `git reset`, `git rm`. Tasks end with "Run tests", not "Commit".
- Never `dart format` a pre-existing file (the repo predates the 3.7 formatter). Format only the files this plan creates; the code below is already formatter output, so formatting them changes nothing. Never `deno fmt` anything (the repo's TypeScript isn't deno-fmt'ed).
- **SQL:** contracts run only on the local scratch database `attune_spec3a`, only as `psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f <file>`, inside the file's own `BEGIN … ROLLBACK`. Confirm the target first (`psql -X -d attune_spec3a -Atc 'select current_database()'` prints `attune_spec3a`). NEVER `attune_test`. NEVER run `scripts/local_pg_setup.sh` or `scripts/local_pg_grants.sql`; Task 10 **edits** `scripts/local_pg_grants.sql` and never runs it.
- **Migrations** (W2c only): `20261025110000_otp_delivery.sql` + `20261025110010_otp_delivery_grants.sql`. If `ls supabase/migrations | sort | tail -1` shows anything at or after `20261025110000` when Task 10 starts, shift both to the next free hour, keeping the order. Each file is one `BEGIN; … COMMIT;`, idempotent (applied twice, `exit=0` both times), `SET LOCAL lock_timeout = '5s'` where it creates or alters tables, every `SECURITY DEFINER` function has `SET search_path = ''` and schema-qualifies every name, server-only tables and functions are revoked inside the migration itself and again in the twin, grants are explicit, nothing reaches `anon` or `authenticated`. No `CREATE INDEX CONCURRENTLY`. No new public table (so no service_role DML is owed).
- **Flags:** W2 adds no flag. Everything here is behind `flow_signin_v2` (inserted false by W1c's `20261025100400`; `supabase/sql/dev_enable_spec1_flags.sql` already turns it on in development, so that script doesn't change). With the flag off, every existing route, screen and the EULA prompt behave exactly as today (Task 4's flag-off redirect table, Task 6's EULA check, Task 9's LoginProfile check, and the untouched `login_profile_test.dart`, `widget_test.dart`, `onboarding_flow_test.dart` prove it).
- **Never touch:** `lib/features/games/**`, `ChatScreen` game entry points, `UniversalBubble` / `ChatTextField` parameters, `lib/features/auth/utility/auth_exports.dart`, `lib/home/home_screen.dart` (its latch is W3a's), `lib/features/opinions/**` (Opinions stays exactly as is), `ATTUNE_SOUL.md`, `ATTUNE_THESIS.md`, every applied migration, every existing SQL contract.
- **Dates** shown to people use `MyDateFormat` only; a date and its detail are joined with `MyDateFormat.join` (`' - '`), e.g. A2's "Friday, November 8, 1991 - that makes you 34."
- **Copy:** every new string is an English `flow_*` key in `lib/i10n/app_en.arb`, generated with `flutter gen-l10n` (exact command in Task 2); the other locales fall back to English. No vendor name appears in anything a person sees.
- **UI:** Material 3 from the app theme (`AppTheme`, `Spacing`, `BorderRadiusTokens`, `ContentWidth`, `.w`/`.h`), every new screen wrapped in `AllowLargeText`, every control labelled, targets ≥ 48 dp, text contrast ≥ 4.5:1, errors announced and shown with an icon (never colour alone), goldens at 1.0, 1.3, 2.0 and right to left, `androidTapTargetGuideline`, `labeledTapTargetGuideline` and `textContrastGuideline` on every new screen. Never animated: X1, consent (A5/A5c).
- **No real provider calls in tests.** Provider secrets (Twilio, Meta, Arkesel), `OTP_HMAC_KEY`, `SEND_SMS_HOOK_SECRET` and `ANDROID_SMS_APP_HASHES` are the owner's environment variables. With the hook off, Supabase's built-in SMS sends every code; with it on and a secret missing, the hook fails closed (`otp:unavailable`) and the intent endpoint stores nothing.
- **Phone-only sign-in.** No Apple or Google sign-in; `AuthService`'s methods stay as they are, unused.
- **No deploys.** `supabase db push`, `supabase functions deploy`, `supabase secrets set`, dashboard settings and store work are the owner's ("Owner deploy checklist"). Don't read `.env*`, credentials or the keychain. The one new package is `smart_auth` (Task 13, `flutter pub add`).
- **Regression gate at the end of each sub-wave** (Tasks 4, 9, 13): the full `flutter test` passes; `flutter analyze --no-pub lib test` shows no `error` line that the Task 1 baseline didn't; no Games file, `auth_exports.dart`, `home_screen.dart`, Opinions file or Games contract changed since Task 1; W2c also: every SQL contract on `attune_spec3a` shows no new FAIL against the Task 1 baseline, `otp_delivery_contracts.sql` is PASS, and the Deno tests pass.

## Review Focus

1. **A person in Ghana typing their date of birth** (device locale `en_GH`): they expect Day · Month · Year. intl 0.19 has no `en_GH` pattern and plain `en` is the US order, so a naive lookup puts the month first. Test: Task 5, Step 1, `field order follows the locale; Ghana reads day first`.
2. **Closing the app after the code was accepted but before "Agree and continue"**: they expect to come back to A5, not to land in today's onboarding, which would create the account through `record_eula_acceptance` without a date of birth. Test: Task 8, Step 1, router group `verified and signed in as that account: back to A5…`, and Task 8's coordinator test `verified but closed before A5 resumes at A5 for that account only`.
3. **Someone who knows your number asks for your code by WhatsApp** while you are signing in: your code must still come by SMS. Test: Task 10, Step 1, contract B4 (`an opposed intent moved the code`).
4. **A returning account that accepted EULA v1 signs in through v2**: they expect "We've updated our terms" once, then home; never a second, v1 prompt in today's onboarding. Test: Task 8's `an existing account discards the typed name and date` (needsConsent) and Task 6's `asks only for a missing or older version, compared as numbers`.
5. **A name in a non-Latin script entered at A1, with `flow_paths_v2` still off**: today's onboarding follows A5, and its name step accepts ASCII letters only; the person expects not to be asked their name again, let alone refused. Test: Task 6, `skips the name step when A1 already took the name`.

## Decisions found while verifying the code (read before Task 1)

Each is a verified fact about today's code or the database, with the smallest change that keeps the spec's intent.

- **P-1 (G3 not built).** Every guest write action in Opinions shows a snackbar "Sign in to perform this action" (`opinion_card.dart:310`, `comment_thread_screen.dart:174`, `tag_browse_screen.dart:43`, `anonymous_profile_screen.dart:174`). Spec §3.2 G3 ("Sign in to write" → A1, return to Opinions once) needs edits to those four Opinions files, and the binding rule is that Opinions stays exactly as is. G3 and `attune.flow.return_to` are not built; a guest signs up from Tab 2 (G2, "Join Attune", Task 9) or Welcome. *Changes spec intent.*
- **P-2 (guest tab label).** The guest Tab 2 label ("Chat" → "Sign in", §3.2 G2) lives in `lib/home/home_screen.dart`, which nothing before W3a edits (§5.6 R1). W2 changes only what that tab shows (LoginProfile); the label waits for W3a.
- **P-3 (RI-1/RI-2 move to W2a).** §5.2 routes v2 invite links to `/invite` in W2a and Welcome has "I have an invite", but §5.1 lists `invite_landing_screen` (RI-1/RI-2) under W4b. W2a builds the pre-auth landing (code entry, "You've been invited", the two ways in) as `lib/features/auth/sign_up/presentation/screens/invite_landing_screen.dart`; RI-3/RI-4 (`join_invite_screen`, after sign-in) stay W4b. With `flow_couples_v2` off, the signed-in gate still accepts the stored code as today (spec §2.5).
- **P-4 (`/signup` during W2a).** W2a registers `/signup` with today's `LoginScreen` as its builder, so the development app (where `flow_signin_v2` is already on) keeps signing in between sub-waves; Task 8 swaps the builder for `SignUpFlow`.
- **P-5 (router state).** `RoutingNotifier.user` is never set on sign-in (only `setUser`/`clearUser` callers on sign-out), so the redirect reads the signed-in account live through an injectable `currentUserId` (default `Supabase.instance.client.auth.currentUser?.id`, `null` when Supabase isn't initialised). The redirect moves into `appRedirect()` in `lib/app/routing/sign_in_redirect.dart`; its flag-off branch is today's two rules verbatim plus one line (a v2-only route reached after the flag went off mid-session goes where today goes), and a table test compares it with today's rule for every existing route.
- **P-6 (legacy entries).** Sign-out (`logout_action.dart:61`), account deletion (`delete_account_action.dart:66`) and the safety sign-out (`safety_sign_out.dart:63`) go to `/intro`; OnboardingGate's signed-out branch goes to `/login` (`onboarding_gate.dart:138`). Under v2 the redirect maps `/intro` → `/welcome` (W2a) and `/login` → `/welcome` (W2b) instead of editing those files (two are W3a's).
- **P-7 (contrast).** The light theme's primary `#4F9F3A` with white text measures 3.31:1 and the theme's error `#F44336` on white 3.7:1; `textContrastGuideline` fails both (§2.3 needs 4.5:1). W2's flow widgets use the palette's own `appColors.primaryDark` (`#2F6F22`, 6.1:1) as the accent in light mode (`flowAccent()`), keep `colorScheme.primary` in dark mode, and show errors as on-surface text with an `error_outline` icon. The theme itself is not changed (it would restyle every screen).
- **P-8 (flow widgets).** `AppButton` pins its label to `TextScaler.noScaling`, one line, and plays a 500 ms scale-fade on mount (`app_button.dart:67, 174-176`); `AppTextFormField` has a fixed height and its visible label is a separate `Text` the screen reader doesn't attach to the field (`app_text_form_field.dart:482, 596-599`). Both break §2.2/§2.3 on these screens, so W2 adds `FlowFrame`, `FlowPrimaryButton`/`FlowSecondaryButton`/`FlowTextLink` and `FlowTextField` (Material 3 widgets from the theme). `BottomSheetUtils`, `PhoneCountryPickerSheet`, `MyDateFormat`, `UrlLauncherUtils` and the legal documents are reused.
- **P-9 (l10n).** `pubspec.yaml` has no `generate: true` and no `l10n.yaml`; the generated files are committed. `flutter gen-l10n --arb-dir=lib/i10n --template-arb-file=app_en.arb --output-dir=lib/i10n/generated --output-localization-file=app_localizations.dart --no-synthetic-package` reproduces all seven generated files byte for byte except one hand-edited doc comment (`You\'re browsing` → `You're browsing`), which a `perl` one-liner restores. Keys are `flow_<camelCase>`.
- **P-10 (where the age gate and block live).** The guest year goes in its own keystore file, `attune_age_gate` (FlutterSecureStorage, `encryptedSharedPreferences`, iOS `first_unlock_this_device`), added to both backup-exclusion files. The under-18 block goes in the **default** SharedPreferences file (`FlutterSharedPreferences.xml`, which Android Auto Backup already includes) under `attune.age_block.until`, plus an iOS Keychain copy restored at boot (bounded to 1 s), rather than a separate `attune_age_block.xml`: the router must read it synchronously at boot, which only the default prefs file allows without a new plugin call, and the backup behaviour is the same.
- **P-11 (date-of-birth order).** `dateTimePatternMap()` (intl 0.19) has no `en_GH`, `en_NG` or `en_KE`, and `en` is `M/d/y`. The order comes from the exact `language_REGION` pattern when one exists; otherwise month-first only for the US, its territories and the Philippines; day-first everywhere else. A year-first pattern (`y-MM-dd`, `en_CA`) reads day-first.
- **P-12 (name rule).** W1's server now normalises names with `private.normalize_display_name` (zero-width and direction characters dropped, whitespace collapsed); A1 does the same on the phone and requires one letter in any script (`\p{L}`), 1–40 code points.
- **P-13 (wrong vs expired code).** Auth answers `otp_expired` ("Token has expired or is invalid") for a wrong code and an old one alike, so A4 decides by the newest send's age (over 10 minutes: "That code has expired. Send a new one.").
- **P-14 ("Welcome back, {name}").** `get_my_home_state()` carries no name, so the flow reads the account's own `users.display_name` (own-row SELECT, unchanged); a phone number stored as a name is never shown ("Welcome back.").
- **P-15 (returning accounts with `needs`).** Today's LoginScreen asks for the EULA after every sign-in; without that, a v1 account signing in through v2 would never see the new terms until W3a. So `/signup` shows A5c ("We've updated our terms", `record_eula_acceptance('2')`) for `needs` ∋ `consent`, then "Welcome back". The `birth_date`, `name` and `path` interstitials stay W3a's (`OnboardingGate` v2, §5.2).
- **P-16 (sign-in v2 with paths still off).** `flow_paths_v2` needs `flow_signin_v2`, not the reverse, so "v2 sign-in, today's onboarding" is a valid production setting. After A5 the person goes to `/home`, whose latch opens today's `OnboardingFlow`. Three small changes keep that clean: `OnboardingFlow` skips its ASCII-only name step when the account's onboarding store already has the name (written only by A5 / "Welcome back"; the flag-off path never writes it before onboarding completes); `EulaGate` asks for EULA v2 under the flag; `EulaAcceptanceService` compares versions as numbers (an account on v2 is never asked to step down to v1) and treats a queued A5 as consent already given.
- **P-17 (resume).** The router sends `/_invisible`, `/home` and `/onboarding` to `/signup` when the draft has a code on its way (signed out) or names the signed-in account as verified but not through A5. Without it, reopening after A4 would let today's onboarding create the account with no date of birth.
- **P-18 ("Not now").** "Not now" signs out (the app's full sign-out) and keeps A1–A3 on the phone for their 7 days, but clears the code and the verified account so nothing resumes by itself. A5, N1 and "Welcome back" have no back button (signed in by then; only their own buttons leave).
- **P-19 (`OneTimeCodeField` in W2b).** A4 needs the one-field code input in W2b, so it lands there; W2c adds only the Android SMS listener and iOS `webcredentials`.
- **P-20 (`smart_auth`).** `flutter pub add smart_auth:^3.2.0` resolves against today's `pubspec.lock` adding only `smart_auth 3.2.0` (8 lock lines; sdk `>=2.16.1 <4.0.0`, flutter `>=2.5.0`, depends on `flutter` only). Its Android library: compileSdk 35, minSdk 16, `play-services-auth:21.3.0`; the app's AGP 8.7.0, Kotlin 2.1.20, Gradle 8.10.2, Java 11 and compileSdk 36 meet its stated floor. A4 uses the SMS Retriever API in release builds (silent, needs the app hash) and the User Consent API otherwise (one tap, no hash). iOS doesn't use it.
- **P-21 (SIM country).** A new `attune/device` MethodChannel in `MainActivity.configureFlutterEngine`, next to `attune/safety` (same pattern), answers `simCountryIso` from `TelephonyManager` (no permission). `deviceCountryProvider` gives `(sim, region)`; A3 waits for it (≤ 1 s) before opening the picker.
- **P-22 (OTP schema, smallest changes).** (a) `country_code` is `text` with a CHECK, not `char(2)`, so `'*'` stays `'*'`. (b) `otp_send_events.rule_prefix` is added: the per-prefix hourly cap counts by it. (c) `private.otp_intent_attempts (kind, key_hash, created_at)` is added: edge functions are stateless, so the per-IP limit (10 an hour) and the per-number intent cap (6 an hour) need counters that outlive the 10-minute intent TTL; `otp_record_intent` gains `p_ip_hash text DEFAULT NULL` (the IP is HMACed in the function, never stored). (d) `otp_purge` lives in `private` (cron only) and also purges the counters (1 hour). (e) `otp_take_send_decision` also returns `platform` (the newest intent's, within 10 minutes), which the hook needs for the message shape. (f) `otp_routes.provider` is CHECKed to the three adapters that exist. *Changes the spec's function signature and table list.*
- **P-23 (metric keys).** W1's metric key pattern is lower-case only (`^[a-z0-9_:>.-]{1,80}$`), so sends are counted as `otp_sent:gh:sms:arkesel`.
- **P-24 (country in the hook).** The hook needs a country for routing and counting, not a full parser: `+233` GH, `+234` NG, `+254` KE, `+44` GB, `+1` CA for Canadian area codes else US, anything else `XX` (default routes). Destination rules match on the number's first seven characters (`+` and six digits).
- **P-25 (no new Deno dependency).** Standard Webhooks verification (`webhook-id`, `-timestamp`, `-signature`, `v1,whsec_…` secret, 5-minute tolerance) is 30 lines of WebCrypto in `_shared/standard_webhooks.ts`, tested with the standard's published vector, reusing `constantTimeEqual` from `_shared/attune_auth.ts`.
- **P-26 (providers).** Twilio (SMS and voice), Meta Cloud API (WhatsApp authentication template) and Arkesel (Ghana direct, the registered sender) — owner question 1. A provider whose secrets are unset answers "unconfigured" and the next route is tried; if none sends, `otp:unavailable`. Each call is bounded at 2.5 s and the whole hook at 4.5 s, inside Auth's hook timeout.
- **P-27 (Android hash).** An SMS can end with one app hash: the hook uses the first of `ANDROID_SMS_APP_HASHES` (the release key's); debug builds read the code through the User Consent API, which needs none.
- **P-28 (`config.toml`).** It gains `[functions.otp-delivery-intent]` and `[functions.send-sms-hook]` with `verify_jwt = false`. The `[auth.hook.send_sms]` block is written commented out: enabled in the file, every `supabase start` (CI's `sql-contracts` job included) would need `SEND_SMS_HOOK_SECRET`, and a `supabase config push` would carry it to the project. The owner switches the hook on in the dashboard.
- **P-29 (`passwordless_auth_service.dart`).** W2c removes only the debug phone log (§5.2). The hook's `otp:*` codes and Auth's limits are classified in the new `lib/features/auth/sign_up/domain/otp_failure.dart`, so LoginScreen's copy (flag off) stays byte-identical; `account_dormant:*` / `account_review` are W6a's.
- **P-30 (no bootstrap stub).** `scripts/local_pg_bootstrap.sql` gets no `supabase_auth_admin` stub in W2: the Send SMS Hook is an HTTP hook; only W6a's Postgres access-token hook needs the role.
- **P-31 (previews).** The three bundled WebP illustrations aren't in the repo; each preview shows a decorative Material icon in a tinted circle (excluded from semantics) until the owner supplies them (checklist).
- **P-32 ("More about AI in Attune").** No AI-specific manual page exists; the link opens the existing About Attune topic (`AboutAttuneDocs`, whose FAQ covers AI and data). Counsel may ask for a dedicated page (W2 gate).
- **P-33 (`/signup` parameters).** `entry` (`new`, `returning`, `invite`) and `back` travel as query parameters, not `extra`, so the redirect and a cold-start resume can read them. In W2 `invite` behaves as `new` (W4b changes what follows A5).
- **P-34 (preview sheet timing).** `showModalBottomSheet` has one duration for both directions; the previews use a small `PopupRoute` (300 ms in, 200 ms out, 150 ms fade with reduce motion).
- **P-35 (legacy LoginProfile pieces).** LoginProfile's existing legal link is 18 dp tall at 3.0:1 contrast; it stays as it is (flag-off unchanged) and is a W10 audit item. Only the new "Join Attune" panel is held to §2.3.
- **P-36 (draft storage).** The sign-up draft (name, date of birth, number, ladder, nonce) is in the default prefs file because the router reads it synchronously; Android Auto Backup includes that file. It is deleted when sign-up completes, after 7 days, or at the under-18 stop (§4.8) — owner question 3.
- **P-37 (provider names).** §5.3's `signUpDraftProvider` and `ageGateProvider` are `signUpDraftStoreProvider` and `ageGateStoreProvider` here: plain stores, because `SignUpCoordinator` owns the draft's state for the life of `/signup`. `pendingInviteProvider` is W4b's.

## Owner questions (open; the plan builds the recommendation)

1. **Ghana-direct SMS provider.** The plan builds Arkesel as the first Ghana route, Twilio after it and everywhere else. *Recommendation:* use whichever Ghana provider already holds (or will register fastest) the MTN alphanumeric sender ID; if it isn't Arkesel, only `send-sms-hook/providers.ts`'s adapter and the `otp_routes_provider_check` constraint change.
2. **G3 "Sign in to write" (P-1).** It needs edits to four Opinions files, and Opinions is frozen. *Recommendation:* keep Opinions untouched now (guests sign up from Welcome or Tab 2's "Join Attune") and fold G3 into the Opinions redesign (Q9) or W3a's home work.
3. **The sign-up draft in Auto Backup (P-36).** Name, date of birth and number sit in the backed-up prefs file for at most 7 days. *Recommendation:* accept it (the same file already holds today's onboarding answers, and the draft is deleted at completion); the alternative is a separate, excluded prefs file read with an extra plugin call before the first frame.

## W1 interfaces this plan consumes (adjust here if W1's final review renames one)

- SQL: `public.get_my_home_state() → jsonb` (`has_account`, `needs` with `consent`); `public.complete_sign_up(p_display_name text, p_birth_date date, p_eula_version text)` refusing `signup:not_eligible`, `signup:phone_required`, `signup:invalid_name`, `signup:invalid_birth_date`, `signup:eula_required`, `signup:not_signed_in`; `public.record_eula_acceptance(p_version text)` (pre-W1); `private.bump_metric_internal(text)`, `public.bump_metric_server(text)`; metric prefixes `otp_sent:` and `otp_refused:` (seeded by `20261025100100`); the `flow_signin_v2` row (`20261025100400`). Not used by W2: `set_my_birth_date`, `set_my_path` (W3a).
- Dart: `HomeState.fromJson`, `HomeState.hasAccount`, `HomeState.needs`, `HomeNeed.consent` (`lib/features/onboarding/domain/home_state.dart`); `PublicAppConfigCache(prefs).read()?.flowSignInV2`, `flowSignInV2Provider`, `datingOpenCountriesProvider`, `publicAppConfigGatewayProvider`, `PublicAppConfigGateway.fetch()` (`lib/core/flags/public_app_config.dart`); `Environment.flowV2Default`; `metricCounterProvider`, `MetricCounter(MetricSender)`, `ClientMetricKey.welcomePreviewRelationship|welcomePreviewDating|welcomePreviewJustMe|guestAgeOk|signupStarted|signupStepName|signupStepDob|signupStepPhone|signupAgeStop` (`lib/core/metrics/metric_counter.dart`); `OnboardingStore.storeInviteFromLink(prefs, code, {userId})`, `OnboardingStore(prefs, scope: OnboardingStore.anonymousScope).pendingInviteCode`, `OnboardingStore.userScopePrefix`, `OnboardingStore.displayName` (`lib/features/onboarding/data/onboarding_store.dart`). `HomeStateStore` is W3a's.
- W2 needs W1 deployed first (the owner checklist says so), and Task 1 needs W1's suite green.

## File map

**W2a (Tasks 1–4): foundations and the first screens**
- Modify `lib/core/ui/motion/motion_tokens.dart`; create `lib/core/ui/motion/shared_axis_step.dart`, `lib/core/ui/text/allow_large_text.dart` (Task 1).
- Modify `lib/app/routing/routing_notifier.dart` (sign-in state) and `lib/app/routing/app_router.dart` (`RouteNames`) (Task 1).
- Modify `lib/i10n/app_en.arb` (+ regenerate `lib/i10n/generated/*`); create `lib/features/auth/sign_up/presentation/widgets/{flow_colors,flow_buttons,flow_frame,flow_text_field}.dart`, `lib/features/auth/sign_up/data/age_gate_store.dart`, `lib/features/auth/sign_up/domain/guest_year.dart`, `lib/features/auth/sign_up/presentation/screens/{guest_age_gate_screen,under_age_stop_screen}.dart`; modify `android/app/src/main/res/xml/{backup_rules,data_extraction_rules}.xml`; create `test/helpers/flow_harness.dart` (Task 2).
- Create `lib/features/auth/sign_up/domain/{invite_code,country_names}.dart`, `lib/features/auth/sign_up/presentation/widgets/path_preview_sheet.dart`, `lib/features/auth/sign_up/presentation/screens/{welcome_screen,invite_landing_screen}.dart` (Task 3).
- Create `lib/app/routing/sign_in_redirect.dart`, `lib/features/auth/sign_up/presentation/sign_up_flags.dart`; modify `lib/app/routing/app_router.dart` (redirect, routes), `lib/app/app.dart`, `lib/main.dart` (Task 4).

**W2b (Tasks 5–9): the sign-up steps over built-in SMS**
- Create `lib/features/auth/sign_up/domain/{display_name_validator,birth_date_validator,phone_entry,default_phone_country,resend_ladder,otp_failure,sign_up_draft}.dart`, `lib/features/auth/sign_up/data/sign_up_draft_store.dart` (Task 5).
- Create `lib/features/auth/sign_up/data/account_service.dart`; modify `lib/features/onboarding/data/{onboarding_store,onboarding_sync_service}.dart`, `lib/features/auth/data/eula_acceptance_service.dart`, `lib/features/auth/presentation/eula_gate.dart`, `lib/features/onboarding/presentation/screens/onboarding_flow.dart` (Task 6).
- Create `lib/core/platform/sim_country.dart`; modify `android/app/src/main/kotlin/com/barsopus/attune/MainActivity.kt`; create `lib/features/auth/sign_up/presentation/widgets/one_time_code_field.dart`, `lib/features/auth/sign_up/presentation/steps/{name_step,birth_date_step,phone_step,code_step,consent_step,no_account_step}.dart` (Task 7).
- Create `lib/features/auth/sign_up/data/{sign_up_gateways,sign_up_coordinator}.dart`, `lib/features/auth/sign_up/presentation/screens/sign_up_flow.dart`; modify `lib/app/routing/{routing_notifier,sign_in_redirect,app_router}.dart` (Task 8).
- Create `lib/features/auth/sign_up/presentation/widgets/join_attune_panel.dart`; modify `lib/features/auth/log_in/presentation/screens/login_profile.dart` (Task 9).

**W2c (Tasks 10–13): phone codes**
- Create `supabase/migrations/20261025110000_otp_delivery.sql`, `…110010_otp_delivery_grants.sql`, `supabase/tests/otp_delivery_contracts.sql`; modify `scripts/local_pg_grants.sql` (Task 10).
- Create `supabase/functions/_shared/{otp_phone,standard_webhooks}.ts` (+ tests), `supabase/functions/otp-delivery-intent/{handler,index,handler.test}.ts`; modify `supabase/config.toml` (Task 11).
- Create `supabase/functions/send-sms-hook/{messages,providers,handler,index,handler.test}.ts` (Task 12).
- Modify `pubspec.yaml`/`pubspec.lock` (`smart_auth`), `lib/i10n/app_en.arb`; create `lib/features/auth/sign_up/data/{otp_delivery_service,sms_code_listener}.dart`; modify `sign_up_gateways.dart`, `phone_step.dart`, `code_step.dart`, `sign_up_flow.dart`, `lib/features/auth/data/passwordless_auth_service.dart`, `ios/Runner/Runner.entitlements` (Task 13).

Tests live under `test/features/auth/sign_up/`, `test/core/ui/`, `test/core/platform/`, `test/app/routing/`, `test/helpers/` and next to each edge function.

**Not edited:** `lib/home/home_screen.dart`, `lib/features/onboarding/presentation/screens/onboarding_gate.dart`, `lib/features/auth/log_in/presentation/screens/login_screen.dart` and its widgets, `lib/features/opinions/**`, `lib/features/games/**`, `auth_exports.dart`, `supabase/sql/dev_enable_spec1_flags.sql`, `scripts/local_pg_bootstrap.sql`, every applied migration and existing contract.

---

### Task 1: Baselines, motion tokens, `SharedAxisStep`, `AllowLargeText`, the router's sign-in state (W2a; §2.2, §2.3, §5.4)

**Files:**
- Modify: `lib/core/ui/motion/motion_tokens.dart` (import line; append at the end)
- Create: `lib/core/ui/motion/shared_axis_step.dart`
- Create: `lib/core/ui/text/allow_large_text.dart`
- Modify: `lib/app/routing/routing_notifier.dart` (constructor; new sign-in block after it)
- Modify: `lib/app/routing/app_router.dart` (`RouteNames`: five constants)
- Create: `test/core/ui/motion/shared_axis_step_test.dart`, `test/core/ui/text/allow_large_text_test.dart`

**Interfaces:**
- Consumes: `reduceMotionOf(BuildContext)` (`lib/core/ui/motion/reduce_motion.dart`), Material `Durations`/`Easing`.
- Produces: tokens `kStepForwardDuration` (300 ms), `kStepBackDuration` (250 ms), `kStepFadeOutDuration` (90 ms), `kReducedMotionFade` (150 ms), `kSelectionDuration` (150 ms), `kCodeAcceptedHold` (400 ms), `kCelebrationMaxDuration` (600 ms), `kSharedAxisOffset` (30.0); `SharedAxisStep({required Object stepKey, required Widget child, bool forward = true})`; `AllowLargeText({required Widget child, double maxScaleFactor = 2.0})`; `RoutingNotifier({SharedPreferences? prefs, bool isFirstLaunch = false, bool flowV2 = false, bool guestAgeOk = false, bool underAgeBlocked = false, String? Function()? currentUserId})` with getters `flowV2`, `guestAgeOk`, `underAgeBlocked`, `currentUserId`, `isSignedIn` and setters `setFlowV2(bool)`, `setGuestAgeOk(bool)`, `setUnderAgeBlocked(bool)` (each notifies only on a change); `RouteNames.welcome = '/welcome'`, `signUp = '/signup'`, `guestAge = '/guest-age'`, `invite = '/invite'`, `ageStop = '/age-stop'`.

- [ ] **Step 1: Confirm the target, W1 green, and record the baselines**

```bash
cd /Users/user/attune
psql -X -d attune_spec3a -Atc 'select current_database()'
ls supabase/migrations | sort | tail -1
mkdir -p .superpowers/sdd/2026-10-25-spec1-w2
git status --short > .superpowers/sdd/2026-10-25-spec1-w2/git-status-before.txt
for f in supabase/tests/*.sql; do
  if psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f "$f" >/dev/null 2>&1; then echo "PASS $(basename "$f")"; else echo "FAIL $(basename "$f")"; fi
done > .superpowers/sdd/2026-10-25-spec1-w2/sql-baseline.txt
grep -c '^FAIL' .superpowers/sdd/2026-10-25-spec1-w2/sql-baseline.txt
grep identity_foundation .superpowers/sdd/2026-10-25-spec1-w2/sql-baseline.txt
flutter test --no-pub 2>&1 | tr '\r' '\n' | grep -E 'All tests passed!|Some tests failed' | tail -1
flutter analyze --no-pub lib test > .superpowers/sdd/2026-10-25-spec1-w2/analyze-baseline.txt 2>&1
grep -E '^\s*error ' .superpowers/sdd/2026-10-25-spec1-w2/analyze-baseline.txt | sed -E 's/:[0-9]+:[0-9]+//' | sort -u > .superpowers/sdd/2026-10-25-spec1-w2/analyze-errors-baseline.txt
wc -l < .superpowers/sdd/2026-10-25-spec1-w2/analyze-errors-baseline.txt
```
Expected: `attune_spec3a`; `20261025100510_identity_health_grants.sql` (or a later W1 fix-up — anything below `20261025110000` is fine); a FAIL count (16 when W1 was planned; keep whatever you get, every gate compares with it); `PASS identity_foundation_contracts.sql`; `All tests passed!`; `0`. If the Flutter suite is not green or the identity contract fails, stop and report: W1's final review must have landed first (this plan builds on its interfaces).

- [ ] **Step 2: Write the failing tests**

Create `test/core/ui/motion/shared_axis_step_test.dart` with exactly:

```dart
// Spec 1 §2.2 (W2a): the step transition. Forward 300 ms, back 250 ms, a
// 30 dp shared-axis slide that flips right to left, and a 150 ms cross-fade
// with nothing moving when reduce motion is on.
import 'package:attune/core/ui/motion/motion_tokens.dart';
import 'package:attune/core/ui/motion/shared_axis_step.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(
  String step, {
  bool forward = true,
  bool reduceMotion = false,
  TextDirection direction = TextDirection.ltr,
}) => MediaQuery(
  data: MediaQueryData(disableAnimations: reduceMotion),
  child: Directionality(
    textDirection: direction,
    child: SharedAxisStep(
      stepKey: step,
      forward: forward,
      child: Center(
        child: TextButton(onPressed: () {}, child: Text('step $step')),
      ),
    ),
  ),
);

double _dx(WidgetTester tester, String label) {
  final transform = tester.widget<Transform>(
    find.ancestor(of: find.text(label), matching: find.byType(Transform)).first,
  );
  return transform.transform.getTranslation().x;
}

void main() {
  testWidgets(
    'forward: the new step slides in from 30 dp and owns the screen at 300 ms',
    (tester) async {
      await tester.pumpWidget(_host('a'));
      await tester.pumpWidget(_host('b'));
      await tester.pump(const Duration(milliseconds: 1));

      expect(find.text('step a'), findsOneWidget);
      expect(find.text('step b'), findsOneWidget);
      expect(_dx(tester, 'step b'), closeTo(kSharedAxisOffset, 0.5));
      expect(_dx(tester, 'step a'), closeTo(0, 0.5));

      await tester.pump(kStepForwardDuration - const Duration(milliseconds: 2));
      expect(find.text('step a'), findsOneWidget, reason: 'still leaving');
      await tester.pump(const Duration(milliseconds: 2));
      expect(find.text('step a'), findsNothing);
      expect(_dx(tester, 'step b'), 0);
    },
  );

  testWidgets('back: 250 ms, and the slide comes from the other side', (
    tester,
  ) async {
    await tester.pumpWidget(_host('b'));
    await tester.pumpWidget(_host('a', forward: false));
    await tester.pump(const Duration(milliseconds: 1));
    expect(_dx(tester, 'step a'), closeTo(-kSharedAxisOffset, 0.5));

    await tester.pump(kStepBackDuration);
    expect(find.text('step b'), findsNothing);
  });

  testWidgets('right to left reverses the forward slide', (tester) async {
    await tester.pumpWidget(_host('a', direction: TextDirection.rtl));
    await tester.pumpWidget(_host('b', direction: TextDirection.rtl));
    await tester.pump(const Duration(milliseconds: 1));
    expect(_dx(tester, 'step b'), closeTo(-kSharedAxisOffset, 0.5));
    await tester.pumpAndSettle();
  });

  testWidgets('reduce motion: a 150 ms cross-fade, nothing moves', (
    tester,
  ) async {
    await tester.pumpWidget(_host('a', reduceMotion: true));
    await tester.pumpWidget(_host('b', reduceMotion: true));
    await tester.pump(const Duration(milliseconds: 1));
    expect(_dx(tester, 'step b'), 0);
    expect(_dx(tester, 'step a'), 0);

    await tester.pump(kReducedMotionFade);
    expect(find.text('step a'), findsNothing);
  });

  testWidgets('the leaving step takes no taps and is not read out', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_host('a'));
    await tester.pumpWidget(_host('b'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.bySemanticsLabel('step a'), findsNothing);
    expect(find.bySemanticsLabel('step b'), findsOneWidget);
    expect(
      find.ancestor(
        of: find.text('step a'),
        matching: find.byType(IgnorePointer),
      ),
      findsWidgets,
    );
    await tester.pumpAndSettle();
    semantics.dispose();
  });

  testWidgets('the same step with new content rebuilds in place', (
    tester,
  ) async {
    await tester.pumpWidget(_host('a'));
    await tester.pumpWidget(_host('a'));
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.text('step a'), findsOneWidget);
    expect(_dx(tester, 'step a'), 0);
  });
}
```

Create `test/core/ui/text/allow_large_text_test.dart` with exactly:

```dart
// Spec 1 §2.3 (W2a): the phone's text size reaches a Spec 1 screen through
// the root shell's 1.0 clamp, capped at 2.0 and never below 1.0.
import 'package:attune/core/ui/text/allow_large_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<double> _scaleOf10(WidgetTester tester, {required bool wrapped}) async {
  late double scaled;
  final probe = Builder(
    builder: (context) {
      scaled = MediaQuery.textScalerOf(context).scale(10);
      return const SizedBox();
    },
  );
  await tester.pumpWidget(
    MaterialApp(
      // What app_shell.dart does for every route.
      builder:
          (context, child) => MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.0,
            child: child!,
          ),
      home: wrapped ? AllowLargeText(child: probe) : probe,
    ),
  );
  return scaled;
}

void main() {
  testWidgets('the shell clamp alone keeps 1.0', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    expect(await _scaleOf10(tester, wrapped: false), 10);
  });

  testWidgets('wrapped, the phone text size comes through', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    expect(await _scaleOf10(tester, wrapped: true), closeTo(13, 0.001));
  });

  testWidgets('capped at 2.0', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 3.1;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    expect(await _scaleOf10(tester, wrapped: true), 20);
  });

  testWidgets('never below 1.0', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 0.8;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    expect(await _scaleOf10(tester, wrapped: true), 10);
  });
}
```

- [ ] **Step 3: Run them to verify they fail**

```bash
cd /Users/user/attune
flutter test --no-pub test/core/ui/motion/shared_axis_step_test.dart test/core/ui/text/allow_large_text_test.dart 2>&1 | tr '\r' '\n' | grep -E "Error when reading" | head -2
```
Expected: `Error: Error when reading 'lib/core/ui/motion/shared_axis_step.dart': No such file or directory` and the same for `allow_large_text.dart`.

- [ ] **Step 4: Add the motion tokens (§2.2)**

In `lib/core/ui/motion/motion_tokens.dart`:

Edit 1 of 2. Replace exactly:

```dart
import 'package:flutter/widgets.dart';

```

with:

```dart
import 'package:flutter/material.dart' show Durations;
import 'package:flutter/widgets.dart';

```

Edit 2 of 2. Replace exactly:

```dart
/// minutes late under your finger.
const Duration kArrivalAnimationWindow = Duration(milliseconds: 1500);
```

with:

```dart
/// minutes late under your finger.
const Duration kArrivalAnimationWindow = Duration(milliseconds: 1500);

/// Spec 1 §2.2 (W2): the sign-in and onboarding steps. Material 3 durations;
/// every step stays inside the 150–320 ms band.
const Duration kStepForwardDuration = Durations.medium2; // 300 ms
const Duration kStepBackDuration = Durations.medium1; // 250 ms

/// The outgoing step has faded out by this point of either step.
const Duration kStepFadeOutDuration = Duration(milliseconds: 90);

/// Replaces every step (and the preview sheet) when reduce motion is on.
const Duration kReducedMotionFade = Durations.short3; // 150 ms

/// An option being selected: state layer and check.
const Duration kSelectionDuration = Durations.short3; // 150 ms

/// A correct code: the check fades in, holds, then the flow moves on.
const Duration kCodeAcceptedHold = Duration(milliseconds: 400);

/// The ceiling for the one calm celebration per path.
const Duration kCelebrationMaxDuration = Durations.long4; // 600 ms

/// The shared-axis slide distance in logical pixels, negated right to left.
const double kSharedAxisOffset = 30;
```

- [ ] **Step 5: Write `SharedAxisStep` and `AllowLargeText`**

Create `lib/core/ui/motion/shared_axis_step.dart` with exactly:

```dart
import 'package:attune/core/ui/motion/motion_tokens.dart';
import 'package:attune/core/ui/motion/reduce_motion.dart';
import 'package:flutter/material.dart';

/// One step of a multi-step flow, entering with Material's shared-axis X
/// transition (Spec 1 §2.2): the outgoing step slides 30 dp away and fades
/// out over its first 90 ms; the incoming one slides in from 30 dp and fades
/// in from 90 ms to the end. Forward takes [kStepForwardDuration], back
/// [kStepBackDuration], and the direction flips under right-to-left text.
/// With reduce motion on, both cross-fade in [kReducedMotionFade] and
/// nothing moves.
///
/// A new [stepKey] starts a transition; the same key with a new [child]
/// just rebuilds in place. Only the incoming step takes taps and is read
/// by a screen reader.
class SharedAxisStep extends StatefulWidget {
  const SharedAxisStep({
    super.key,
    required this.stepKey,
    required this.child,
    this.forward = true,
  });

  final Object stepKey;
  final Widget child;

  /// False when going back a step: the slide reverses.
  final bool forward;

  @override
  State<SharedAxisStep> createState() => _SharedAxisStepState();
}

class _SharedAxisStepState extends State<SharedAxisStep>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    value: 1,
  );
  Widget? _outgoing;
  Object? _outgoingKey;
  bool _outgoingForward = true;

  @override
  void didUpdateWidget(covariant SharedAxisStep oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.stepKey == widget.stepKey) return;
    _outgoing = oldWidget.child;
    _outgoingKey = oldWidget.stepKey;
    _outgoingForward = widget.forward;
    _controller.duration =
        reduceMotionOf(context)
            ? kReducedMotionFade
            : widget.forward
            ? kStepForwardDuration
            : kStepBackDuration;
    _controller.forward(from: 0).whenCompleteOrCancel(() {
      if (!mounted) return;
      setState(() {
        _outgoing = null;
        _outgoingKey = null;
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = reduceMotionOf(context);
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final sign = (_outgoingForward ? 1.0 : -1.0) * (rtl ? -1.0 : 1.0);
    final total = _controller.duration?.inMilliseconds ?? 1;
    final fadeOutEnd = (kStepFadeOutDuration.inMilliseconds / total).clamp(
      0.0,
      1.0,
    );

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        final moving = _outgoing != null;
        final double incomingOpacity;
        final double outgoingOpacity;
        double incomingDx = 0;
        double outgoingDx = 0;
        if (!moving) {
          incomingOpacity = 1;
          outgoingOpacity = 0;
        } else if (reduce) {
          incomingOpacity = t;
          outgoingOpacity = 1 - t;
        } else {
          final slide = Curves.easeInOutCubicEmphasized.transform(t);
          incomingOpacity = Interval(
            fadeOutEnd,
            1,
            curve: Easing.emphasizedDecelerate,
          ).transform(t);
          outgoingOpacity =
              1 -
              Interval(
                0,
                fadeOutEnd,
                curve: Easing.emphasizedAccelerate,
              ).transform(t);
          incomingDx = sign * kSharedAxisOffset * (1 - slide);
          outgoingDx = -sign * kSharedAxisOffset * slide;
        }
        return Stack(
          fit: StackFit.passthrough,
          children: [
            if (moving)
              KeyedSubtree(
                key: ValueKey(('out', _outgoingKey)),
                child: IgnorePointer(
                  child: ExcludeSemantics(
                    child: Opacity(
                      opacity: outgoingOpacity,
                      child: Transform.translate(
                        offset: Offset(outgoingDx, 0),
                        child: _outgoing,
                      ),
                    ),
                  ),
                ),
              ),
            KeyedSubtree(
              key: ValueKey(('in', widget.stepKey)),
              child: Opacity(
                opacity: incomingOpacity,
                child: Transform.translate(
                  offset: Offset(incomingDx, 0),
                  child: widget.child,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
```

Create `lib/core/ui/text/allow_large_text.dart` with exactly:

```dart
import 'package:flutter/widgets.dart';

/// Lets the phone's own text size through to [child] (Spec 1 §2.3), up to
/// [maxScaleFactor] (2.0 by default) and never below 1.0.
///
/// The root shell clamps every route to 1.0 (`app_shell.dart`), and a nested
/// `MediaQuery.withClampedTextScaling` can't rise above its parent, so this
/// reads the scale straight from the view instead. Every Spec 1 screen is
/// wrapped in it from W2 onwards.
class AllowLargeText extends StatelessWidget {
  const AllowLargeText({
    super.key,
    required this.child,
    this.maxScaleFactor = 2.0,
  });

  final Widget child;
  final double maxScaleFactor;

  @override
  Widget build(BuildContext context) {
    final system = MediaQueryData.fromView(View.of(context)).textScaler;
    final data = MediaQuery.of(context);
    return MediaQuery(
      data: data.copyWith(
        textScaler: system.clamp(
          minScaleFactor: 1.0,
          maxScaleFactor: maxScaleFactor,
        ),
      ),
      child: child,
    );
  }
}
```

- [ ] **Step 6: Give the router its sign-in state and route names**

In `lib/app/routing/routing_notifier.dart` (all defaults off, so `RoutingNotifier()` in existing tests and today's `main.dart` call route exactly as before):

The edit. Replace exactly:

```dart
  final SharedPreferences? _prefs;

  RoutingNotifier({SharedPreferences? prefs, bool isFirstLaunch = false})
    : _prefs = prefs,
      _isFirstLaunch = isFirstLaunch {
    _isRecoveryMode = prefs?.getBool(_kRecoveryModeKey) ?? false;
  }

```

with:

```dart
  final SharedPreferences? _prefs;

  RoutingNotifier({
    SharedPreferences? prefs,
    bool isFirstLaunch = false,
    bool flowV2 = false,
    bool guestAgeOk = false,
    bool underAgeBlocked = false,
    String? Function()? currentUserId,
  }) : _prefs = prefs,
       _isFirstLaunch = isFirstLaunch,
       _flowV2 = flowV2,
       _guestAgeOk = guestAgeOk,
       _underAgeBlocked = underAgeBlocked,
       _currentUserId = currentUserId ?? _supabaseUserId {
    _isRecoveryMode = prefs?.getBool(_kRecoveryModeKey) ?? false;
  }

  // ==================== SPEC 1 SIGN-IN (W2) ====================
  //
  // Read synchronously at boot (main.dart) and kept current by their
  // owners: flowV2 by App's listener on the public config, guestAgeOk by
  // G1, underAgeBlocked by X1. All false by default, so a notifier built
  // without them routes exactly as before.

  bool _flowV2;
  bool _guestAgeOk;
  bool _underAgeBlocked;
  final String? Function() _currentUserId;

  /// flow_signin_v2, effective: Welcome and the v2 sign-up instead of
  /// IntroScreen and LoginScreen.
  bool get flowV2 => _flowV2;

  /// G1 was passed on this install.
  bool get guestAgeOk => _guestAgeOk;

  /// X1's 30-day device block is in force.
  bool get underAgeBlocked => _underAgeBlocked;

  /// The signed-in account, read live (the router's own user field is not
  /// kept in step with Auth).
  String? get currentUserId => _currentUserId();

  bool get isSignedIn => currentUserId != null;


  void setFlowV2(bool value) {
    if (_flowV2 == value) return;
    _flowV2 = value;
    notifyListeners();
  }

  void setGuestAgeOk(bool value) {
    if (_guestAgeOk == value) return;
    _guestAgeOk = value;
    notifyListeners();
  }

  void setUnderAgeBlocked(bool value) {
    if (_underAgeBlocked == value) return;
    _underAgeBlocked = value;
    notifyListeners();
  }

  static String? _supabaseUserId() {
    try {
      return Supabase.instance.client.auth.currentUser?.id;
    } catch (_) {
      return null;
    }
  }

```

In `lib/app/routing/app_router.dart`, the route names only (the routes and the redirect come in Task 4):

The edit. Replace exactly:

```dart
class RouteNames {
  static const String intro = '/intro';
  static const String home = '/home';
  static const String settings = '/settings';
```

with:

```dart
class RouteNames {
  static const String intro = '/intro';
  // Spec 1 W2 (§5.4): the v2 sign-in, all behind flow_signin_v2.
  static const String welcome = '/welcome';
  static const String signUp = '/signup';
  static const String guestAge = '/guest-age';
  static const String invite = '/invite';
  static const String ageStop = '/age-stop';
  static const String home = '/home';
  static const String settings = '/settings';
```

- [ ] **Step 7: Run the tests, format the new files, analyze**

```bash
cd /Users/user/attune
flutter test --no-pub test/core/ui/motion/shared_axis_step_test.dart test/core/ui/text/allow_large_text_test.dart test/features/chat/chat_screen_view_active_test.dart 2>&1 | tr '\r' '\n' | grep -E "All tests passed|Some tests failed" | tail -1
dart format lib/core/ui/motion/shared_axis_step.dart lib/core/ui/text/allow_large_text.dart test/core/ui/motion/shared_axis_step_test.dart test/core/ui/text/allow_large_text_test.dart
flutter analyze --no-pub lib/core/ui lib/app/routing test/core/ui 2>&1 | grep -E "^\s*(error|warning) " | head
```
Expected: `All tests passed!` (the chat test builds `createAppRouter(RoutingNotifier())`, so the new defaults are exercised); `Formatted 4 files (0 changed)`; no `error`/`warning` line.

---

### Task 2: W2a copy, the flow widgets, the age gate store, G1 and X1 (W2a; §3.2 G1, §3.6 X1, §2.3)

**Files:**
- Modify: `lib/i10n/app_en.arb` (+ regenerate `lib/i10n/generated/*.dart`)
- Create: `lib/features/auth/sign_up/presentation/widgets/flow_colors.dart`, `flow_buttons.dart`, `flow_frame.dart`, `flow_text_field.dart`
- Create: `lib/features/auth/sign_up/domain/guest_year.dart`, `lib/features/auth/sign_up/data/age_gate_store.dart`
- Create: `lib/features/auth/sign_up/presentation/screens/guest_age_gate_screen.dart`, `under_age_stop_screen.dart`
- Modify: `android/app/src/main/res/xml/backup_rules.xml`, `android/app/src/main/res/xml/data_extraction_rules.xml`
- Create: `test/helpers/flow_harness.dart`, `test/features/auth/sign_up/guest_age_gate_screen_test.dart`, `test/features/auth/sign_up/age_gate_backup_test.dart`

**Interfaces:**
- Consumes: Task 1's `AllowLargeText`, `RouteNames.welcome|ageStop|home`, `RoutingNotifier.setGuestAgeOk|setUnderAgeBlocked`; W1's `metricCounterProvider`, `ClientMetricKey.guestAgeOk`; `sharedPreferencesProvider`, `routingNotifierProvider`; `UrlLauncherUtils.launchUrlWithFeedback`; `AppContentWidth`, `ContentWidth.form`; `Theme.of(context).appColors.primaryDark`.
- Produces: `flowAccent(BuildContext) → Color`; `FlowPrimaryButton({required String label, required VoidCallback? onPressed, bool busy})`, `FlowSecondaryButton({label, onPressed})`, `FlowTextLink({label, onPressed, AlignmentGeometry alignment})`; `FlowFrame({required String title, required Widget body, String? hint, List<Widget> actions, VoidCallback? onBack})`; `FlowTextField({required controller, required label, String? semanticsLabel, String? errorText, …})`; `enum GuestYearError {fourDigits, future, check}`, `validateGuestYear(String, {required int currentYear})`, `isUnder18ByYear(int, {required int currentYear})`; `AgeGateStore(SharedPreferences, {FlutterSecureStorage? secure, DateTime Function()? now})` with `keystoreFile = 'attune_age_gate'`, `guestOkKey = 'attune.age_gate.guest_ok'`, `blockUntilKey = 'attune.age_block.until'`, `static readGuestOk(prefs)`, `static readBlocked(prefs, now)`, `passGuestGate(int)`, `guestBirthYear()`, `clearGuestBirthYear()`, `block()`, `static restoreBlock(prefs, {secure, now})`; `ageGateStoreProvider`; `GuestAgeGateScreen({DateTime Function()? now})`; `UnderAgeStopScreen({bool serverRefused = false})`, `UnderAgeStopScreen.youthSupportUrl`. Test harness: `pumpFlowScreen(tester, screen, {textScale, direction, reduceMotion, prefsValues, overrides, routing, openCountries, size}) → FlowHarness(router, routing, prefs, metrics)` with `.location`; `expectFlowGoldens(tester, name, screen, {prefsValues, overrides, openCountries, before})`; `expectFlowGuidelines(tester)`; `FakePublicConfigGateway`.

- [ ] **Step 1: Add the W2a copy and regenerate**

In `lib/i10n/app_en.arb`, at the very end of the file (it has no trailing newline):

The edit. Replace exactly:

```json
  "luxuryLevelModerate": "Moderate",
  "luxuryLevelLuxury": "Luxury",
  "luxuryLevelUltraLuxury": "Ultra Luxury"
}
```

with:

```json
  "luxuryLevelModerate": "Moderate",
  "luxuryLevelLuxury": "Luxury",
  "luxuryLevelUltraLuxury": "Ultra Luxury",

  "flow_continue": "Continue",
  "flow_close": "Close",
  "flow_back": "Back",
  "flow_listTwo": "{first} and {second}",
  "@flow_listTwo": {
    "placeholders": {
      "first": {"type": "String"},
      "second": {"type": "String"}
    }
  },
  "flow_countryUk": "the UK",
  "flow_countryUs": "the US",
  "flow_welcomeTitle": "Love, dating and you, in one calm place.",
  "flow_pathRelationshipTitle": "In a relationship",
  "flow_pathRelationshipLine": "A private space for you and your partner.",
  "flow_pathDatingTitle": "Single and open to dating",
  "flow_pathDatingLine": "A few introductions a day. Only when it's mutual.",
  "flow_pathJustMeTitle": "Just for me",
  "flow_pathJustMeLine": "Your journal, quizzes and Healing.",
  "flow_welcomeCardSemantics": "{title}. {line} Opens a preview.",
  "@flow_welcomeCardSemantics": {
    "placeholders": {
      "title": {"type": "String"},
      "line": {"type": "String"}
    }
  },
  "flow_welcomeGetStarted": "Get started",
  "flow_welcomeHaveAccount": "I already have an account",
  "flow_welcomeHaveInvite": "I have an invite",
  "flow_welcomeReadOpinions": "Read Opinions first",
  "flow_welcomeFooter": "Attune is for adults (18+) and uses your phone number to sign in.",
  "flow_linkTerms": "Terms",
  "flow_linkPrivacy": "Privacy",
  "flow_previewRelationshipTitle": "A space for the two of you",
  "flow_previewRelationshipLine1": "Chat, plans and memories only you two can see.",
  "flow_previewRelationshipLine2": "Your journal stays yours. Your partner never sees it.",
  "flow_previewRelationshipLine3": "Invite your partner with a link or a code.",
  "flow_previewDatingTitle": "Introductions, not swiping",
  "flow_previewDatingLine1": "Up to 3 introductions a day, chosen for what you both want.",
  "flow_previewDatingLine2": "A match only when you both say yes.",
  "flow_previewDatingLine3": "A live video selfie checks your age before your first introduction.",
  "flow_previewDatingCountries": "Dating is open in {countries}. More countries later.",
  "@flow_previewDatingCountries": {
    "placeholders": {
      "countries": {"type": "String"}
    }
  },
  "flow_previewJustMeTitle": "A private space for you",
  "flow_previewJustMeLine1": "A journal only you can read.",
  "flow_previewJustMeLine2": "Short quizzes about how you connect.",
  "flow_previewJustMeLine3": "Healing, after a breakup or a loss.",
  "flow_previewJustMeLine4": "Single, partnered or in between.",
  "flow_guestAgeTitle": "What year were you born?",
  "flow_guestAgeHint": "We ask everyone. It stays on this phone.",
  "flow_guestAgeLabel": "Year",
  "flow_guestAgeSemantics": "Year you were born, 4 digits",
  "flow_yearFourDigits": "Enter the year with 4 digits, like 1994.",
  "flow_yearFuture": "That year is in the future.",
  "flow_yearCheck": "Check the year.",
  "flow_ageStopTitle": "Attune is for adults",
  "flow_ageStopBody": "You need to be 18 or older to use Attune. We haven't saved anything you entered.",
  "flow_ageStopServerLead": "We couldn't create your account.",
  "flow_ageStopYouthLink": "Support for young people",
  "flow_inviteTitle": "You've been invited to Attune",
  "flow_inviteBody": "Someone invited you to a private space on Attune. Create your account to see who it is and to join.",
  "flow_inviteCreate": "Create an account",
  "flow_inviteCodeTitle": "Enter your invite code",
  "flow_inviteCodeLabel": "Invite code",
  "flow_inviteCodeError": "Codes have 6 letters and numbers. Check it with the person who sent it."
}
```

Then regenerate and restore the one doc comment the generator rewrites:

```bash
cd /Users/user/attune
flutter gen-l10n --arb-dir=lib/i10n --template-arb-file=app_en.arb --output-dir=lib/i10n/generated --output-localization-file=app_localizations.dart --no-synthetic-package > /dev/null
perl -0pi -e "s/\*\*'You\\\\'re browsing/**'You're browsing/" lib/i10n/generated/app_localizations.dart
git diff --numstat lib/i10n/generated
grep -c "flow_" lib/i10n/generated/app_localizations_en.dart
```
Expected: seven lines, each `<added>\t0\t…` (nothing deleted in any generated file); then `52` (one line per W2a getter or method).

- [ ] **Step 2: Write the failing tests and the harness**

Create `test/helpers/flow_harness.dart` with exactly:

```dart
// Spec 1 W2: pumps a sign-in screen the way the app shows it — the app
// theme, the root shell's 1.0 text clamp, ScreenUtil, the real
// localisations — inside a router whose every other location just says
// where the screen sent the person ("at /signup?entry=new").
import 'package:attune/app/routing/routing_notifier.dart';
import 'package:attune/app/theme/app_theme.dart';
import 'package:attune/core/flags/public_app_config.dart';
import 'package:attune/core/metrics/metric_counter.dart';
import 'package:attune/core/providers/routing_providers.dart';
import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/core/utils/screen_util_config.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakePublicConfigGateway implements PublicAppConfigGateway {
  FakePublicConfigGateway({this.openCountries = const []});

  final List<String> openCountries;

  @override
  Future<Map<String, dynamic>> fetch() async => {
    'flags': {'flow_signin_v2': true},
    'config': {
      'age_signal_storefronts': <String>[],
      'dating_open_countries': openCountries,
    },
  };
}

class FlowHarness {
  FlowHarness(this.router, this.routing, this.prefs, this.metrics);

  final GoRouter router;
  final RoutingNotifier routing;
  final SharedPreferences prefs;

  /// Every metric key the screen bumped, in order.
  final List<String> metrics;

  String get location =>
      router.routerDelegate.currentConfiguration.uri.toString();
}

/// Text sizes and directions every new screen's goldens cover (§2.3).
const flowGoldenVariants = <(String, double, TextDirection)>[
  ('scale1.0', 1.0, TextDirection.ltr),
  ('scale1.3', 1.3, TextDirection.ltr),
  ('scale2.0', 2.0, TextDirection.ltr),
  ('rtl', 1.0, TextDirection.rtl),
];

Future<FlowHarness> pumpFlowScreen(
  WidgetTester tester,
  Widget Function() screen, {
  double textScale = 1.0,
  TextDirection direction = TextDirection.ltr,
  bool reduceMotion = false,
  Map<String, Object> prefsValues = const {},
  List<Override> overrides = const [],
  RoutingNotifier? routing,
  List<String> openCountries = const [],
  Size size = const Size(390, 844),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  if (reduceMotion) {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
  }
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearAllTestValues);

  SharedPreferences.setMockInitialValues(prefsValues);
  FlutterSecureStorage.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final notifier = routing ?? RoutingNotifier(prefs: prefs, flowV2: true);
  final metrics = <String>[];
  final router = GoRouter(
    initialLocation: '/test',
    routes: [GoRoute(path: '/test', builder: (_, __) => screen())],
    errorBuilder: (_, state) => Scaffold(body: Text('at ${state.uri}')),
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        routingNotifierProvider.overrideWith((ref) => notifier),
        metricCounterProvider.overrideWithValue(
          MetricCounter((key) async => metrics.add(key)),
        ),
        publicAppConfigGatewayProvider.overrideWithValue(
          FakePublicConfigGateway(openCountries: openCountries),
        ),
        ...overrides,
      ],
      child: ScreenUtilConfig.builder(
        builder:
            (_) => MaterialApp.router(
              theme: AppTheme.lightTheme,
              debugShowCheckedModeBanner: false,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              routerConfig: router,
              builder:
                  (context, child) => Directionality(
                    textDirection: direction,
                    // What app_shell.dart does for every route.
                    child: MediaQuery.withClampedTextScaling(
                      maxScaleFactor: 1.0,
                      child: child!,
                    ),
                  ),
            ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return FlowHarness(router, notifier, prefs, metrics);
}

/// Pumps [screen] at every golden variant and compares
/// `goldens/<name>.<variant>.png`. Run with --update-goldens to create them.
Future<void> expectFlowGoldens(
  WidgetTester tester,
  String name,
  Widget Function() screen, {
  Map<String, Object> prefsValues = const {},
  List<Override> overrides = const [],
  List<String> openCountries = const [],
  Future<void> Function(WidgetTester tester)? before,
}) async {
  for (final (variant, scale, direction) in flowGoldenVariants) {
    await pumpFlowScreen(
      tester,
      screen,
      textScale: scale,
      direction: direction,
      prefsValues: prefsValues,
      overrides: overrides,
      openCountries: openCountries,
    );
    if (before != null) await before(tester);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/$name.$variant.png'),
    );
    expect(tester.takeException(), isNull, reason: '$name at $variant');
  }
}

/// The three accessibility guidelines every new screen meets (§2.3).
Future<void> expectFlowGuidelines(WidgetTester tester) async {
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  await expectLater(tester, meetsGuideline(textContrastGuideline));
}
```

Create `test/features/auth/sign_up/guest_age_gate_screen_test.dart` with exactly:

```dart
// Spec 1 W2a: G1 (the guest birth-year gate) and X1 (the under-18 stop).
import 'package:attune/features/auth/sign_up/data/age_gate_store.dart';
import 'package:attune/features/auth/sign_up/domain/guest_year.dart';
import 'package:attune/features/auth/sign_up/presentation/screens/guest_age_gate_screen.dart';
import 'package:attune/features/auth/sign_up/presentation/screens/under_age_stop_screen.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../helpers/flow_harness.dart';

DateTime _now() => DateTime.utc(2026, 10, 25, 12);

void main() {
  group('validateGuestYear', () {
    test('four digits, not after this year, not before 1900', () {
      expect(
        validateGuestYear('', currentYear: 2026),
        GuestYearError.fourDigits,
      );
      expect(
        validateGuestYear('94', currentYear: 2026),
        GuestYearError.fourDigits,
      );
      expect(
        validateGuestYear('2027', currentYear: 2026),
        GuestYearError.future,
      );
      expect(
        validateGuestYear('1899', currentYear: 2026),
        GuestYearError.check,
      );
      expect(validateGuestYear(' 1994 ', currentYear: 2026), isNull);
    });

    test('exactly 18 by year passes; 17 does not', () {
      expect(isUnder18ByYear(2008, currentYear: 2026), isFalse);
      expect(isUnder18ByYear(2009, currentYear: 2026), isTrue);
    });
  });

  testWidgets('G1: an adult year opens the guest home and is kept for A2', (
    tester,
  ) async {
    final h = await pumpFlowScreen(tester, () => GuestAgeGateScreen(now: _now));
    expect(find.text('What year were you born?'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Year you were born, 4 digits'),
      findsOneWidget,
    );

    await tester.enterText(find.byType(TextField), '1994');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(h.location, '/home');
    expect(h.routing.guestAgeOk, isTrue);
    expect(AgeGateStore.readGuestOk(h.prefs), isTrue);
    expect(await AgeGateStore(h.prefs).guestBirthYear(), 1994);
    expect(h.metrics, ['guest_age_ok']);
  });

  testWidgets(
    'G1: a year under 18 opens X1 and blocks the device for 30 days',
    (tester) async {
      final h = await pumpFlowScreen(
        tester,
        () => GuestAgeGateScreen(now: _now),
      );
      await tester.enterText(find.byType(TextField), '2012');
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(h.location, '/age-stop');
      expect(h.routing.underAgeBlocked, isTrue);
      expect(AgeGateStore.readBlocked(h.prefs, DateTime.now()), isTrue);
      expect(
        AgeGateStore.readBlocked(
          h.prefs,
          DateTime.now().add(const Duration(days: 31)),
        ),
        isFalse,
        reason: 'the block clears itself after 30 days',
      );
      expect(AgeGateStore.readGuestOk(h.prefs), isFalse);
      expect(h.metrics, isEmpty);
    },
  );

  testWidgets('G1: each mistake says what to fix, inline', (tester) async {
    await pumpFlowScreen(tester, () => GuestAgeGateScreen(now: _now));
    for (final (typed, message) in [
      ('94', 'Enter the year with 4 digits, like 1994.'),
      ('2030', 'That year is in the future.'),
      ('1850', 'Check the year.'),
    ]) {
      await tester.enterText(find.byType(TextField), typed);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.text(message), findsOneWidget);
    }
  });

  testWidgets('G1 meets the tap-target, label and contrast guidelines', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpFlowScreen(tester, () => GuestAgeGateScreen(now: _now));
    await expectFlowGuidelines(tester);
    semantics.dispose();
  });

  testWidgets(
    'X1 says nothing was saved, offers youth support, and never animates',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final h = await pumpFlowScreen(tester, () => const UnderAgeStopScreen());
      expect(find.text('Attune is for adults'), findsOneWidget);
      expect(
        find.text(
          "You need to be 18 or older to use Attune. We haven't saved anything you entered.",
        ),
        findsOneWidget,
      );
      expect(find.text('Support for young people'), findsOneWidget);
      await expectFlowGuidelines(tester);

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(h.location, '/welcome');
      semantics.dispose();
    },
  );

  testWidgets('X1 starts no animation on its first frame (spec §2.2, §7.4)', (
    tester,
  ) async {
    await pumpFlowScreen(tester, () => const SizedBox());
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const UnderAgeStopScreen(),
      ),
    );
    // A running animation is a ticker, and a ticker is a transient callback.
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets(
    'X1 after a server refusal leads with "We couldn\'t create your account."',
    (tester) async {
      await pumpFlowScreen(
        tester,
        () => const UnderAgeStopScreen(serverRefused: true),
      );
      expect(
        find.textContaining("We couldn't create your account."),
        findsOneWidget,
      );
    },
  );

  group('AgeGateStore', () {
    late SharedPreferences prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
    });

    test(
      'a Keychain block comes back after a reinstall; an expired one goes',
      () async {
        await AgeGateStore(prefs).block();
        // A reinstall: the prefs copy is gone, the Keychain item stays.
        await prefs.remove(AgeGateStore.blockUntilKey);
        expect(AgeGateStore.readBlocked(prefs, DateTime.now()), isFalse);

        await AgeGateStore.restoreBlock(prefs);
        expect(AgeGateStore.readBlocked(prefs, DateTime.now()), isTrue);

        await AgeGateStore.restoreBlock(
          prefs,
          now: () => DateTime.now().add(const Duration(days: 31)),
        );
        expect(prefs.getString(AgeGateStore.blockUntilKey), isNull);
      },
    );

    test('the guest year is cleared once sign-up completes', () async {
      final store = AgeGateStore(prefs);
      await store.passGuestGate(1990);
      expect(await store.guestBirthYear(), 1990);
      await store.clearGuestBirthYear();
      expect(await store.guestBirthYear(), isNull);
      expect(store.guestOk, isTrue, reason: 'the gate stays passed');
    });
  });
}
```

Create `test/features/auth/sign_up/age_gate_backup_test.dart` with exactly:

```dart
// Spec 1 W2a (§3.2, §3.6, review F-5): the guest's birth year never leaves
// the phone in a backup; the under-18 block does, so it usually survives a
// reinstall.
import 'dart:io';

import 'package:attune/features/auth/sign_up/data/age_gate_store.dart';
import 'package:flutter_test/flutter_test.dart';

List<String> _sections(String path) {
  final xml = File(path).readAsStringSync();
  if (!path.contains('extraction')) return [xml];
  return [
    xml.substring(
      xml.indexOf('<cloud-backup>'),
      xml.indexOf('</cloud-backup>'),
    ),
    xml.substring(
      xml.indexOf('<device-transfer>'),
      xml.indexOf('</device-transfer>'),
    ),
  ];
}

void main() {
  const files = [
    'android/app/src/main/res/xml/backup_rules.xml',
    'android/app/src/main/res/xml/data_extraction_rules.xml',
  ];

  test('the age-gate keystore file is excluded everywhere', () {
    for (final path in files) {
      for (final section in _sections(path)) {
        expect(
          section,
          contains(
            '<exclude domain="sharedpref" path="${AgeGateStore.keystoreFile}.xml" />',
          ),
          reason: path,
        );
      }
    }
  });

  test('the default prefs file, which holds the block, is never excluded', () {
    for (final path in files) {
      expect(
        File(path).readAsStringSync(),
        isNot(contains('FlutterSharedPreferences')),
      );
    }
  });
}
```

- [ ] **Step 3: Run them to verify they fail**

```bash
cd /Users/user/attune
flutter test --no-pub test/features/auth/sign_up/guest_age_gate_screen_test.dart test/features/auth/sign_up/age_gate_backup_test.dart 2>&1 | tr '\r' '\n' | grep -E "Error when reading" | head -3
```
Expected: `Error when reading 'lib/features/auth/sign_up/data/age_gate_store.dart'` (and the screens).

- [ ] **Step 4: Write the flow widgets**

Create `lib/features/auth/sign_up/presentation/widgets/flow_colors.dart` with exactly:

```dart
import 'package:attune/app/theme/app_theme.dart';
import 'package:flutter/material.dart';

/// The sign-in screens' accent (Spec 1 §2.3: text contrast at least 4.5:1).
/// The light theme's primary green (#4F9F3A) reads at only 3.3:1 against
/// white, so light mode uses the palette's own darker green
/// (`primaryDark`, #2F6F22, 6.1:1); dark mode keeps the theme's primary.
Color flowAccent(BuildContext context) {
  final theme = Theme.of(context);
  return theme.brightness == Brightness.light
      ? theme.appColors.primaryDark
      : theme.colorScheme.primary;
}
```

Create `lib/features/auth/sign_up/presentation/widgets/flow_buttons.dart` with exactly:

```dart
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// The sign-in screens' buttons (Spec 1 §2.2–§2.3). Material 3 buttons from
/// the theme's colour scheme, at least 48 dp tall, with labels that wrap and
/// follow the phone's text size. Unlike AppButton they never pin the text
/// scale or play an entry animation, which §2.3 and the "never animated"
/// screens (X1, consent) need.
class FlowPrimaryButton extends StatelessWidget {
  const FlowPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;

  /// Shows a small progress ring and takes no taps.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: busy ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: flowAccent(context),
          foregroundColor: colorScheme.onPrimary,
          minimumSize: const Size.fromHeight(48),
          padding: EdgeInsets.symmetric(
            horizontal: Spacing.md.w,
            vertical: Spacing.sm,
          ),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadiusTokens.xlAll,
          ),
        ),
        child:
            busy
                ? SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colorScheme.onPrimary,
                    semanticsLabel: label,
                  ),
                )
                : Text(label, textAlign: TextAlign.center),
      ),
    );
  }
}

class FlowSecondaryButton extends StatelessWidget {
  const FlowSecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: flowAccent(context),
          side: BorderSide(color: flowAccent(context)),
          minimumSize: const Size.fromHeight(48),
          padding: EdgeInsets.symmetric(
            horizontal: Spacing.md.w,
            vertical: Spacing.sm,
          ),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadiusTokens.xlAll,
          ),
        ),
        child: Text(label, textAlign: TextAlign.center),
      ),
    );
  }
}

/// A text link with a 48 dp target.
class FlowTextLink extends StatelessWidget {
  const FlowTextLink({
    super.key,
    required this.label,
    required this.onPressed,
    this.alignment = AlignmentDirectional.center,
  });

  final String label;
  final VoidCallback onPressed;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: flowAccent(context),
          minimumSize: const Size(48, 48),
          padding: EdgeInsets.symmetric(horizontal: Spacing.sm.w),
        ),
        child: Text(label, textAlign: TextAlign.center),
      ),
    );
  }
}
```

Create `lib/features/auth/sign_up/presentation/widgets/flow_frame.dart` with exactly:

```dart
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/ui/text/allow_large_text.dart';
import 'package:attune/core/widgets/app_content_width.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:gap/gap.dart';

/// The shared layout of every Spec 1 sign-in screen: an optional back
/// button, a title read out as a heading, an optional hint, the screen's
/// own body (scrolls at large text), then its actions pinned at the bottom.
/// Large text is let through (AllowLargeText, §2.3); on an iPad the column
/// is form-width.
class FlowFrame extends StatelessWidget {
  const FlowFrame({
    super.key,
    required this.title,
    required this.body,
    this.hint,
    this.actions = const [],
    this.onBack,
  });

  final String title;
  final String? hint;
  final Widget body;

  /// Bottom of the screen, top to bottom, spaced by [Spacing.sm].
  final List<Widget> actions;

  /// Shows a back button when set.
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final loc = AppLocalizations.of(context)!;

    return AllowLargeText(
      child: Scaffold(
        backgroundColor: colorScheme.surface,
        body: SafeArea(
          child: AppContentWidth(
            maxWidth: ContentWidth.form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: 48,
                  child:
                      onBack == null
                          ? null
                          : Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: IconButton(
                              onPressed: onBack,
                              tooltip: loc.flow_back,
                              icon: const BackButtonIcon(),
                            ),
                          ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.symmetric(
                      horizontal: Spacing.lg.w,
                      vertical: Spacing.sm.h,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Semantics(
                          header: true,
                          child: Text(
                            title,
                            style: theme.textTheme.headlineSmall?.copyWith(
                              color: colorScheme.onSurface,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (hint != null) ...[
                          Gap(Spacing.sm.h),
                          Text(
                            hint!,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                        Gap(Spacing.lg.h),
                        body,
                      ],
                    ),
                  ),
                ),
                if (actions.isNotEmpty)
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      Spacing.lg.w,
                      Spacing.sm.h,
                      Spacing.lg.w,
                      Spacing.md.h,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < actions.length; i++) ...[
                          if (i > 0) const Gap(Spacing.sm),
                          actions[i],
                        ],
                      ],
                    ),
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

Create `lib/features/auth/sign_up/presentation/widgets/flow_text_field.dart` with exactly:

```dart
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

/// A labelled text field for the sign-in screens (Spec 1 §2.3).
///
/// The visible [label] sits in the field's own decoration, so a screen
/// reader reads [semanticsLabel] (or the label) as the field's name; the
/// field grows with large text instead of clipping; and a new [errorText]
/// is announced, never shown by colour alone.
class FlowTextField extends StatefulWidget {
  const FlowTextField({
    super.key,
    required this.controller,
    required this.label,
    this.semanticsLabel,
    this.errorText,
    this.hintText,
    this.keyboardType = TextInputType.text,
    this.textInputAction = TextInputAction.next,
    this.inputFormatters,
    this.autofillHints,
    this.autofocus = false,
    this.focusNode,
    this.onSubmitted,
    this.onChanged,
    this.textCapitalization = TextCapitalization.none,
  });

  final TextEditingController controller;
  final String label;
  final String? semanticsLabel;
  final String? errorText;
  final String? hintText;
  final TextInputType keyboardType;
  final TextInputAction textInputAction;
  final List<TextInputFormatter>? inputFormatters;
  final Iterable<String>? autofillHints;
  final bool autofocus;
  final FocusNode? focusNode;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final TextCapitalization textCapitalization;

  @override
  State<FlowTextField> createState() => _FlowTextFieldState();
}

class _FlowTextFieldState extends State<FlowTextField> {
  @override
  void didUpdateWidget(covariant FlowTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    final error = widget.errorText;
    if (error != null && error != oldWidget.errorText) {
      SemanticsService.announce(error, Directionality.of(context));
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      keyboardType: widget.keyboardType,
      textInputAction: widget.textInputAction,
      inputFormatters: widget.inputFormatters,
      autofillHints: widget.autofillHints,
      textCapitalization: widget.textCapitalization,
      onSubmitted: widget.onSubmitted,
      onChanged: widget.onChanged,
      decoration: InputDecoration(
        label: Semantics(
          label: widget.semanticsLabel ?? widget.label,
          child: ExcludeSemantics(child: Text(widget.label)),
        ),
        hintText: widget.hintText,
        // The message in body text with an icon, so it reads at full
        // contrast and never by colour alone (§2.3).
        error:
            widget.errorText == null
                ? null
                : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 18,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        widget.errorText!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
        border: const OutlineInputBorder(),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: flowAccent(context), width: 2),
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: Write the guest year rule and the age gate store**

Create `lib/features/auth/sign_up/domain/guest_year.dart` with exactly:

```dart
/// G1's birth-year rules (Spec 1 §3.2): four digits, not after this year,
/// not before 1900. Under 18 by year alone goes to X1; exactly 18 passes,
/// because A2's full date decides.
enum GuestYearError { fourDigits, future, check }

GuestYearError? validateGuestYear(String text, {required int currentYear}) {
  final value = text.trim();
  if (!RegExp(r'^[0-9]{4}$').hasMatch(value)) return GuestYearError.fourDigits;
  final year = int.parse(value);
  if (year > currentYear) return GuestYearError.future;
  if (year < 1900) return GuestYearError.check;
  return null;
}

bool isUnder18ByYear(int year, {required int currentYear}) =>
    currentYear - year < 18;
```

Create `lib/features/auth/sign_up/data/age_gate_store.dart` with exactly:

```dart
import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The guest birth-year gate (G1) and the under-18 device block (X1),
/// Spec 1 §3.2, §3.6.
///
/// * The guest's year sits in its own keystore file, `attune_age_gate`,
///   which Android backups exclude (`backup_rules.xml`,
///   `data_extraction_rules.xml`); the iOS item is this-device-only. A plain
///   prefs bool says the gate was passed, so the router reads it at once.
/// * The block's end date sits in the plain prefs file, which Android Auto
///   Backup includes, and in the Keychain, which iOS keeps across a
///   reinstall. So it usually survives a reinstall (review F-5): on iOS
///   through the Keychain, on Android only when a backup ran before the
///   uninstall.
class AgeGateStore {
  AgeGateStore(
    this._prefs, {
    FlutterSecureStorage? secure,
    DateTime Function()? now,
  }) : _secure = secure ?? defaultSecure,
       _now = now ?? DateTime.now;

  final SharedPreferences _prefs;
  final FlutterSecureStorage _secure;
  final DateTime Function() _now;

  static const keystoreFile = 'attune_age_gate';
  static const guestOkKey = 'attune.age_gate.guest_ok';
  static const blockUntilKey = 'attune.age_block.until';
  static const _secureYearKey = 'guest_birth_year';
  static const _secureBlockKey = 'age_block_until';
  static const blockLength = Duration(days: 30);

  static const defaultSecure = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
      resetOnError: true,
      sharedPreferencesName: keystoreFile,
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  /// For the router at boot: no await, no keystore.
  static bool readGuestOk(SharedPreferences prefs) =>
      prefs.getBool(guestOkKey) ?? false;

  /// For the router at boot: a block in force on [now].
  static bool readBlocked(SharedPreferences prefs, DateTime now) {
    final until = DateTime.tryParse(prefs.getString(blockUntilKey) ?? '');
    return until != null && now.isBefore(until);
  }

  bool get guestOk => readGuestOk(_prefs);

  bool get isBlocked => readBlocked(_prefs, _now());

  /// G1 passed: the year for A2's pre-fill, and the routing bool.
  Future<void> passGuestGate(int year) async {
    try {
      await _secure.write(key: _secureYearKey, value: '$year');
    } catch (error) {
      // The year is only a pre-fill; the gate still counts as passed.
      debugPrint('[age-gate] year not stored: ${error.runtimeType}');
    }
    await _prefs.setBool(guestOkKey, true);
  }

  Future<int?> guestBirthYear() async {
    try {
      return int.tryParse(await _secure.read(key: _secureYearKey) ?? '');
    } catch (_) {
      return null;
    }
  }

  /// Sign-up completed: the year has done its job (spec §4.8).
  Future<void> clearGuestBirthYear() async {
    try {
      await _secure.delete(key: _secureYearKey);
    } catch (_) {}
  }

  /// X1: 30 days from now, in both places. Never throws.
  Future<void> block() async {
    final until = _now().toUtc().add(blockLength).toIso8601String();
    await _prefs.setString(blockUntilKey, until);
    try {
      await _secure.write(key: _secureBlockKey, value: until);
    } catch (error) {
      debugPrint('[age-gate] keychain block not stored: ${error.runtimeType}');
    }
  }

  /// At boot, before the router reads [readBlocked]: a block the Keychain
  /// kept across a reinstall is copied back to prefs; an expired one is
  /// removed from both. The caller bounds it; it never throws.
  static Future<void> restoreBlock(
    SharedPreferences prefs, {
    FlutterSecureStorage? secure,
    DateTime Function()? now,
  }) async {
    final storage = secure ?? defaultSecure;
    final at = (now ?? DateTime.now)();
    try {
      final stored = await storage.read(key: _secureBlockKey);
      final until = DateTime.tryParse(stored ?? '');
      if (until == null) return;
      if (!at.isBefore(until)) {
        await storage.delete(key: _secureBlockKey);
        await prefs.remove(blockUntilKey);
        return;
      }
      if (prefs.getString(blockUntilKey) == null) {
        await prefs.setString(blockUntilKey, stored!);
      }
    } catch (error) {
      debugPrint('[age-gate] block restore skipped: ${error.runtimeType}');
    }
  }
}

final ageGateStoreProvider = Provider<AgeGateStore>(
  (ref) => AgeGateStore(ref.watch(sharedPreferencesProvider)),
);
```

- [ ] **Step 6: Write G1 and X1**

Create `lib/features/auth/sign_up/presentation/screens/guest_age_gate_screen.dart` with exactly:

```dart
import 'package:attune/app/routing/app_router.dart' show RouteNames;
import 'package:attune/core/metrics/metric_counter.dart';
import 'package:attune/core/providers/routing_providers.dart';
import 'package:attune/features/auth/sign_up/data/age_gate_store.dart';
import 'package:attune/features/auth/sign_up/domain/guest_year.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_frame.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_text_field.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// G1 · the neutral birth-year gate before guest Opinions (Spec 1 §3.2).
/// No default, no list of years, no motion. Under 18 by year opens X1 and
/// starts the 30-day device block; otherwise the year is kept on this phone
/// for A2's pre-fill and the guest home opens.
class GuestAgeGateScreen extends ConsumerStatefulWidget {
  const GuestAgeGateScreen({super.key, this.now});

  /// Tests pin the date.
  final DateTime Function()? now;

  @override
  ConsumerState<GuestAgeGateScreen> createState() => _GuestAgeGateScreenState();
}

class _GuestAgeGateScreenState extends ConsumerState<GuestAgeGateScreen> {
  final _year = TextEditingController();
  GuestYearError? _error;
  bool _busy = false;

  DateTime get _now => (widget.now ?? DateTime.now)();

  @override
  void dispose() {
    _year.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    final currentYear = _now.toUtc().year;
    final error = validateGuestYear(_year.text, currentYear: currentYear);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    setState(() {
      _error = null;
      _busy = true;
    });
    final year = int.parse(_year.text.trim());
    final store = ref.read(ageGateStoreProvider);
    final routing = ref.read(routingNotifierProvider);
    if (isUnder18ByYear(year, currentYear: currentYear)) {
      await store.block();
      routing.setUnderAgeBlocked(true);
      if (mounted) context.go(RouteNames.ageStop);
      return;
    }
    await store.passGuestGate(year);
    routing.setGuestAgeOk(true);
    ref.read(metricCounterProvider).bump(ClientMetricKey.guestAgeOk);
    if (mounted) context.go(RouteNames.home);
  }

  String? _errorText(AppLocalizations loc) => switch (_error) {
    GuestYearError.fourDigits => loc.flow_yearFourDigits,
    GuestYearError.future => loc.flow_yearFuture,
    GuestYearError.check => loc.flow_yearCheck,
    null => null,
  };

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return FlowFrame(
      title: loc.flow_guestAgeTitle,
      hint: loc.flow_guestAgeHint,
      onBack: () => context.go(RouteNames.welcome),
      body: FlowTextField(
        controller: _year,
        label: loc.flow_guestAgeLabel,
        semanticsLabel: loc.flow_guestAgeSemantics,
        errorText: _errorText(loc),
        keyboardType: TextInputType.number,
        textInputAction: TextInputAction.done,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(4),
        ],
        autofocus: true,
        onSubmitted: (_) => _continue(),
      ),
      actions: [
        FlowPrimaryButton(
          label: loc.flow_continue,
          busy: _busy,
          onPressed: _continue,
        ),
      ],
    );
  }
}
```

Create `lib/features/auth/sign_up/presentation/screens/under_age_stop_screen.dart` with exactly:

```dart
import 'package:attune/app/routing/app_router.dart' show RouteNames;
import 'package:attune/core/utils/url_launcher_utils.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_frame.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// X1 · Attune is for adults (Spec 1 §3.6). Never animated: the route opens
/// with no transition and nothing on it moves. No retry, no hint of the
/// cut-off. [serverRefused] is the variant after complete_sign_up refused
/// (`signup:not_eligible`): the client has already signed out.
class UnderAgeStopScreen extends StatelessWidget {
  const UnderAgeStopScreen({super.key, this.serverRefused = false});

  final bool serverRefused;

  /// Before W7's country list: the international helpline directory.
  static const youthSupportUrl = 'https://findahelpline.com';

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final body =
        serverRefused
            ? '${loc.flow_ageStopServerLead} ${loc.flow_ageStopBody}'
            : loc.flow_ageStopBody;
    return FlowFrame(
      title: loc.flow_ageStopTitle,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            body,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurface,
            ),
          ),
          FlowTextLink(
            label: loc.flow_ageStopYouthLink,
            alignment: AlignmentDirectional.centerStart,
            onPressed:
                () => UrlLauncherUtils.launchUrlWithFeedback(
                  context: context,
                  url: youthSupportUrl,
                ),
          ),
        ],
      ),
      actions: [
        FlowSecondaryButton(
          label: loc.flow_close,
          onPressed: () => context.go(RouteNames.welcome),
        ),
      ],
    );
  }
}
```

- [ ] **Step 7: Keep the guest year out of backups**

In `android/app/src/main/res/xml/backup_rules.xml`:

Edit 1 of 2. Replace exactly:

```xml
  chat_prepared/ in filesDir), and the home-screen widgets' data (Together
  and the distance widget; widget spec §4.4), and the story outbox and its
  queued captures (STORIES.md §6.1).
-->
<full-backup-content>
```

with:

```xml
  chat_prepared/ in filesDir), and the home-screen widgets' data (Together
  and the distance widget; widget spec §4.4), and the story outbox and its
  queued captures (STORIES.md §6.1), and the guest's birth year (Spec 1
  §3.2, attune_age_gate). The under-18 block is meant to be backed up and
  lives in the default prefs file, which is not excluded.
-->
<full-backup-content>
```

Edit 2 of 2. Replace exactly:

```xml
    <exclude domain="sharedpref" path="FlutterSecureKeyStorage.xml" />
    <exclude domain="sharedpref" path="attune_safety.xml" />
</full-backup-content>
```

with:

```xml
    <exclude domain="sharedpref" path="FlutterSecureKeyStorage.xml" />
    <exclude domain="sharedpref" path="attune_safety.xml" />
    <exclude domain="sharedpref" path="attune_age_gate.xml" />
</full-backup-content>
```

In `android/app/src/main/res/xml/data_extraction_rules.xml`:

Edit 1 of 3. Replace exactly:

```xml
  chat_prepared/ in filesDir), and the home-screen widgets' data (Together
  and the distance widget; widget spec §4.4), and the story outbox and its
  queued captures (STORIES.md §6.1).
-->
<data-extraction-rules>
```

with:

```xml
  chat_prepared/ in filesDir), and the home-screen widgets' data (Together
  and the distance widget; widget spec §4.4), and the story outbox and its
  queued captures (STORIES.md §6.1), and the guest's birth year (Spec 1
  §3.2, attune_age_gate). The under-18 block is meant to be backed up and
  lives in the default prefs file, which is not excluded.
-->
<data-extraction-rules>
```

Edit 2 of 3. Replace exactly:

```xml
        <exclude domain="sharedpref" path="FlutterSecureKeyStorage.xml" />
        <exclude domain="sharedpref" path="attune_safety.xml" />
    </cloud-backup>
    <device-transfer>
```

with:

```xml
        <exclude domain="sharedpref" path="FlutterSecureKeyStorage.xml" />
        <exclude domain="sharedpref" path="attune_safety.xml" />
        <exclude domain="sharedpref" path="attune_age_gate.xml" />
    </cloud-backup>
    <device-transfer>
```

Edit 3 of 3. Replace exactly:

```xml
        <exclude domain="sharedpref" path="FlutterSecureKeyStorage.xml" />
        <exclude domain="sharedpref" path="attune_safety.xml" />
    </device-transfer>
</data-extraction-rules>
```

with:

```xml
        <exclude domain="sharedpref" path="FlutterSecureKeyStorage.xml" />
        <exclude domain="sharedpref" path="attune_safety.xml" />
        <exclude domain="sharedpref" path="attune_age_gate.xml" />
    </device-transfer>
</data-extraction-rules>
```

- [ ] **Step 8: Run the tests to verify they pass, format the new files**

```bash
cd /Users/user/attune
flutter test --no-pub test/features/auth/sign_up/guest_age_gate_screen_test.dart test/features/auth/sign_up/age_gate_backup_test.dart test/core/android_manifest_test.dart 2>&1 | tr '\r' '\n' | grep -E "All tests passed|Some tests failed" | tail -1
dart format lib/features/auth/sign_up test/helpers/flow_harness.dart test/features/auth/sign_up
flutter analyze --no-pub lib/features/auth/sign_up test/helpers test/features/auth/sign_up 2>&1 | grep -E "^\s*(error|warning) " | head
```
Expected: `All tests passed!` (G1: adult → `/home` with the year kept and `guest_age_ok` counted; under 18 → `/age-stop` with a 30-day block and nothing counted; each inline error; the three guidelines; X1's copy, youth link, Close → `/welcome`, no ticker on its first frame; the Keychain block restored and an expired one removed; both backup files exclude `attune_age_gate.xml` and never the default prefs file); `Formatted … (0 changed)`; no `error`/`warning` line.

- [ ] **Step 9: Mutation check (spec §7.4 "Animate X1")**

```bash
cd /Users/user/attune
cp lib/features/auth/sign_up/presentation/screens/under_age_stop_screen.dart .superpowers/sdd/2026-10-25-spec1-w2/x1.dart.keep
perl -0pi -e 's/    return FlowFrame\(\n      title: loc.flow_ageStopTitle,/    return TweenAnimationBuilder<double>(\n      tween: Tween(begin: 0, end: 1),\n      duration: const Duration(milliseconds: 300),\n      builder: (_, v, child) => Opacity(opacity: v, child: child),\n      child: FlowFrame(\n      title: loc.flow_ageStopTitle,/; s/(\n    \);\n  \}\n\}\n)\z/\n    ),$1/' lib/features/auth/sign_up/presentation/screens/under_age_stop_screen.dart
flutter test --no-pub test/features/auth/sign_up/guest_age_gate_screen_test.dart --plain-name 'X1 starts no animation' 2>&1 | tr '\r' '\n' | grep -E "Expected|Actual" | head -2
cp .superpowers/sdd/2026-10-25-spec1-w2/x1.dart.keep lib/features/auth/sign_up/presentation/screens/under_age_stop_screen.dart && rm .superpowers/sdd/2026-10-25-spec1-w2/x1.dart.keep
```
Expected: `Expected: <0>` / `Actual: <1>` (a ticker on X1's first frame). The file is restored afterwards.

---

### Task 3: WL1 Welcome, the three previews, RI-1/RI-2, and the W2a goldens (W2a; §3.1, §3.8 RI-1/RI-2, D15)

**Files:**
- Create: `lib/features/auth/sign_up/domain/invite_code.dart`, `lib/features/auth/sign_up/domain/country_names.dart`
- Create: `lib/features/auth/sign_up/presentation/widgets/path_preview_sheet.dart`
- Create: `lib/features/auth/sign_up/presentation/screens/welcome_screen.dart`, `invite_landing_screen.dart`
- Create: `test/features/auth/sign_up/welcome_screen_test.dart`, `test/features/auth/sign_up/w2a_goldens_test.dart` (+ `test/features/auth/sign_up/goldens/*.png`, generated)

**Interfaces:**
- Consumes: Task 2's widgets, harness and copy; W1's `datingOpenCountriesProvider` (D15 seam), `ClientMetricKey.welcomePreview*`, `OnboardingStore.storeInviteFromLink`, `OnboardingStore(prefs, scope: OnboardingStore.anonymousScope).pendingInviteCode`; `preferencesServiceProvider` (`setFirstLaunchCompleted`), `RoutingNotifier.completeFirstLaunch`; `PhoneCountries.all`; `BottomSheetUtils.showDocumentationBottomSheet`, `LegalDocumentationData.termsOfService|privacyPolicy`.
- Produces: `normalizeInviteCode(String) → String?`; `formatCountryList(List<String>, {nameOf, pair})`, `countryNameFor(String, {Map<String,String> special})`; `enum PathPreviewKind {relationship, dating, justMe}`, `showPathPreview(context, {kind, onGetStarted})`, `PathPreviewSheet`; `WelcomeScreen` with `static leave(context, ref, location)` and `static signUpLocation(String entry, {String? back}) → '/signup?entry=…[&back=…]'`; `InviteLandingScreen`.

- [ ] **Step 1: Write the failing tests**

Create `test/features/auth/sign_up/welcome_screen_test.dart` with exactly:

```dart
// Spec 1 W2a: WL1 Welcome, its three previews, and RI-1/RI-2.
import 'package:attune/core/services/shared_preferences_service.dart';
import 'package:attune/features/auth/sign_up/domain/country_names.dart';
import 'package:attune/features/auth/sign_up/domain/invite_code.dart';
import 'package:attune/features/auth/sign_up/presentation/screens/invite_landing_screen.dart';
import 'package:attune/features/auth/sign_up/presentation/screens/welcome_screen.dart';
import 'package:attune/features/onboarding/data/onboarding_store.dart';
import 'package:attune/app/routing/routing_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/flow_harness.dart';

void main() {
  test('country lists read as a sentence', () {
    String name(String iso) =>
        countryNameFor(iso, special: const {'GB': 'the UK', 'US': 'the US'});
    String pair(String a, String b) => '$a and $b';
    expect(formatCountryList(const [], nameOf: name, pair: pair), '');
    expect(formatCountryList(const ['GH'], nameOf: name, pair: pair), 'Ghana');
    expect(
      formatCountryList(const ['GB', 'GH'], nameOf: name, pair: pair),
      'the UK and Ghana',
    );
    expect(
      formatCountryList(const ['GH', 'KE', 'GB'], nameOf: name, pair: pair),
      'Ghana, Kenya and the UK',
    );
    expect(countryNameFor('zz'), 'ZZ');
  });

  test('invite codes: six of A-Z and 2-9, any case, spaces ignored', () {
    expect(normalizeInviteCode('k7p 2qm'), 'K7P2QM');
    expect(normalizeInviteCode('K7P2Q'), isNull);
    expect(
      normalizeInviteCode('K7P2Q0'),
      isNull,
      reason: '0 is not in the set',
    );
    expect(normalizeInviteCode('K7P2QM1'), isNull);
  });

  testWidgets('the three ways in, nothing preselected, every gate before typing', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpFlowScreen(tester, () => const WelcomeScreen());
    expect(
      find.text('Love, dating and you, in one calm place.'),
      findsOneWidget,
    );
    for (final label in [
      'In a relationship. A private space for you and your partner. Opens a preview.',
      "Single and open to dating. A few introductions a day. Only when it's mutual. Opens a preview.",
      'Just for me. Your journal, quizzes and Healing. Opens a preview.',
    ]) {
      expect(find.bySemanticsLabel(label), findsOneWidget);
    }
    expect(
      find.text(
        'Attune is for adults (18+) and uses your phone number to sign in.',
      ),
      findsOneWidget,
    );
    await expectFlowGuidelines(tester);
    semantics.dispose();
  });

  for (final (button, target) in [
    ('Get started', '/signup?entry=new'),
    ('I already have an account', '/signup?entry=returning'),
    ('I have an invite', '/invite'),
    ('Read Opinions first', '/guest-age'),
  ]) {
    testWidgets('"$button" marks first launch done and opens $target', (
      tester,
    ) async {
      final h = await pumpFlowScreen(
        tester,
        () => const WelcomeScreen(),
        routing: RoutingNotifier(isFirstLaunch: true, flowV2: true),
      );
      expect(PreferencesService(h.prefs).isFirstLaunch, isTrue);
      await tester.ensureVisible(find.text(button));
      await tester.tap(find.text(button));
      await tester.pumpAndSettle();
      expect(h.location, target);
      expect(PreferencesService(h.prefs).isFirstLaunch, isFalse);
      expect(h.routing.isFirstLaunch, isFalse);
    });
  }

  testWidgets(
    'a card opens its preview; the Dating one names the open countries',
    (tester) async {
      final h = await pumpFlowScreen(
        tester,
        () => const WelcomeScreen(),
        openCountries: const ['GB', 'GH'],
      );
      await tester.tap(find.text('Single and open to dating'));
      await tester.pumpAndSettle();
      expect(find.text('Introductions, not swiping'), findsOneWidget);
      expect(
        find.text('Dating is open in the UK and Ghana. More countries later.'),
        findsOneWidget,
      );
      expect(h.metrics, ['welcome_preview:dating']);

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.text('Introductions, not swiping'), findsNothing);
    },
  );

  testWidgets('with no open-country list the line is left out', (tester) async {
    await pumpFlowScreen(tester, () => const WelcomeScreen());
    await tester.tap(find.text('Single and open to dating'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Dating is open in'), findsNothing);
  });

  testWidgets("a preview's Get started starts sign-up", (tester) async {
    final h = await pumpFlowScreen(tester, () => const WelcomeScreen());
    await tester.tap(find.text('Just for me'));
    await tester.pumpAndSettle();
    expect(find.text('A private space for you'), findsOneWidget);
    await tester.tap(find.text('Get started').last);
    await tester.pumpAndSettle();
    expect(h.location, '/signup?entry=new');
  });

  testWidgets('the preview opens in 300 ms and closes in 200 ms', (
    tester,
  ) async {
    await pumpFlowScreen(tester, () => const WelcomeScreen());
    await tester.tap(find.text('In a relationship'));
    await tester.pump();
    double slide() =>
        tester
            .widget<SlideTransition>(
              find
                  .ancestor(
                    of: find.text('A space for the two of you'),
                    matching: find.byType(SlideTransition),
                  )
                  .first,
            )
            .position
            .value
            .dy;
    await tester.pump(const Duration(milliseconds: 150));
    expect(slide(), greaterThan(0), reason: 'still sliding in');
    await tester.pump(const Duration(milliseconds: 150));
    expect(slide(), 0);

    await tester.tap(find.text('Close'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 190));
    expect(find.text('A space for the two of you'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 10));
    await tester.pump(const Duration(milliseconds: 16));
    expect(find.text('A space for the two of you'), findsNothing);
  });

  testWidgets(
    'with reduce motion the preview fades in 150 ms and never slides',
    (tester) async {
      await pumpFlowScreen(
        tester,
        () => const WelcomeScreen(),
        reduceMotion: true,
      );
      await tester.tap(find.text('In a relationship'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 75));
      expect(
        find.ancestor(
          of: find.text('A space for the two of you'),
          matching: find.byType(SlideTransition),
        ),
        findsNothing,
      );
      await tester.pump(const Duration(milliseconds: 75));
      await tester.pump();
      expect(find.text('A space for the two of you'), findsOneWidget);
    },
  );

  testWidgets('RI-2 asks for the code, refuses a bad one, then shows RI-1', (
    tester,
  ) async {
    final h = await pumpFlowScreen(tester, () => const InviteLandingScreen());
    expect(find.text('Enter your invite code'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'abc');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Codes have 6 letters and numbers. Check it with the person who sent it.',
      ),
      findsOneWidget,
    );

    await tester.enterText(find.byType(TextField), 'k7p 2qm');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text("You've been invited to Attune"), findsOneWidget);
    expect(
      OnboardingStore(
        h.prefs,
        scope: OnboardingStore.anonymousScope,
      ).pendingInviteCode,
      'K7P2QM',
    );
    expect(
      find.textContaining('invited you to a private space'),
      findsOneWidget,
    );

    await tester.tap(find.text('Create an account'));
    await tester.pumpAndSettle();
    expect(h.location, '/signup?entry=invite');
  });

  testWidgets(
    'RI-1 with a code from a link names nobody and offers both ways in',
    (tester) async {
      final h = await pumpFlowScreen(
        tester,
        () => const InviteLandingScreen(),
        prefsValues: {
          'attune.onboarding.anonymous.pending_invite':
              '{"code":"K7P2QM","stored_at":"${DateTime.now().toUtc().toIso8601String()}"}',
        },
      );
      expect(find.text("You've been invited to Attune"), findsOneWidget);
      await tester.tap(find.text('I already have an account'));
      await tester.pumpAndSettle();
      expect(h.location, '/signup?entry=returning');
    },
  );
}
```

Create `test/features/auth/sign_up/w2a_goldens_test.dart` with exactly:

```dart
// Spec 1 §2.3 (W2a): every new screen at text sizes 1.0, 1.3 and 2.0 and
// once right to left. Look at the images when they change: they are the
// review of large text, not just a regression net.
//   flutter test --update-goldens test/features/auth/sign_up/w2a_goldens_test.dart
import 'package:attune/features/auth/sign_up/presentation/screens/guest_age_gate_screen.dart';
import 'package:attune/features/auth/sign_up/presentation/screens/invite_landing_screen.dart';
import 'package:attune/features/auth/sign_up/presentation/screens/under_age_stop_screen.dart';
import 'package:attune/features/auth/sign_up/presentation/screens/welcome_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/flow_harness.dart';

DateTime _now() => DateTime.utc(2026, 10, 25, 12);

void main() {
  testWidgets('WL1 Welcome', (tester) async {
    await expectFlowGoldens(tester, 'welcome', () => const WelcomeScreen());
  });

  testWidgets('WL1 Dating preview', (tester) async {
    await expectFlowGoldens(
      tester,
      'welcome_preview_dating',
      () => const WelcomeScreen(),
      openCountries: const ['GB', 'GH'],
      before: (tester) async {
        await tester.tap(find.text('Single and open to dating'));
        await tester.pumpAndSettle();
      },
    );
  });

  testWidgets('G1 guest age gate, with an error', (tester) async {
    await expectFlowGoldens(
      tester,
      'guest_age_gate_error',
      () => GuestAgeGateScreen(now: _now),
      before: (tester) async {
        await tester.enterText(find.byType(TextField), '94');
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();
      },
    );
  });

  testWidgets('X1 under-18 stop', (tester) async {
    await expectFlowGoldens(
      tester,
      'under_age_stop',
      () => const UnderAgeStopScreen(),
    );
  });

  testWidgets('RI-2 invite code', (tester) async {
    await expectFlowGoldens(
      tester,
      'invite_code',
      () => const InviteLandingScreen(),
    );
  });

  testWidgets('RI-1 invited', (tester) async {
    await expectFlowGoldens(
      tester,
      'invite_landing',
      () => const InviteLandingScreen(),
      prefsValues: {
        'attune.onboarding.anonymous.pending_invite':
            '{"code":"K7P2QM","stored_at":"2026-10-25T10:00:00.000Z"}',
      },
    );
  });
}
```

- [ ] **Step 2: Run them to verify they fail**

```bash
cd /Users/user/attune
flutter test --no-pub test/features/auth/sign_up/welcome_screen_test.dart 2>&1 | tr '\r' '\n' | grep -E "Error when reading" | head -2
```
Expected: `Error when reading 'lib/features/auth/sign_up/domain/country_names.dart'` (and the other new files).

- [ ] **Step 3: Write the two small rules**

Create `lib/features/auth/sign_up/domain/invite_code.dart` with exactly:

```dart
/// RI-2's invite code rule (Spec 1 §3.8): six characters, A–Z and 2–9,
/// case-insensitive, spaces ignored. Returns the code as the server stores
/// it, or null when it can't be one.
String? normalizeInviteCode(String input) {
  final code = input.replaceAll(RegExp(r'\s'), '').toUpperCase();
  return RegExp(r'^[A-Z2-9]{6}$').hasMatch(code) ? code : null;
}
```

Create `lib/features/auth/sign_up/domain/country_names.dart` with exactly:

```dart
import 'package:attune/features/auth/log_in/domain/phone_country.dart';

/// Names a list of ISO 3166-1 alpha-2 codes for a sentence: "Ghana",
/// "Ghana and the UK", "Ghana, Kenya and the UK". [nameOf] names one code;
/// [pair] joins two names in the reader's language.
String formatCountryList(
  List<String> isoCodes, {
  required String Function(String iso) nameOf,
  required String Function(String first, String second) pair,
}) {
  final names = [for (final iso in isoCodes) nameOf(iso)];
  if (names.isEmpty) return '';
  if (names.length == 1) return names.single;
  return pair(names.sublist(0, names.length - 1).join(', '), names.last);
}

/// A country's English name from the phone country list, or [iso] itself
/// when the code is unknown. [special] covers the names a sentence says
/// differently ("the UK", "the US").
String countryNameFor(String iso, {Map<String, String> special = const {}}) {
  final upper = iso.toUpperCase();
  final override = special[upper];
  if (override != null) return override;
  for (final country in PhoneCountries.all) {
    if (country.isoCode == upper) return country.name;
  }
  return upper;
}
```

- [ ] **Step 4: Write the preview sheet**

Create `lib/features/auth/sign_up/presentation/widgets/path_preview_sheet.dart` with exactly:

```dart
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/flags/public_app_config.dart';
import 'package:attune/core/ui/motion/motion_tokens.dart';
import 'package:attune/core/ui/motion/reduce_motion.dart';
import 'package:attune/core/ui/text/allow_large_text.dart';
import 'package:attune/features/auth/sign_up/domain/country_names.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:gap/gap.dart';

/// The three ways in, as Welcome shows them (Spec 1 §3.1).
enum PathPreviewKind { relationship, dating, justMe }

/// Opens a path's preview: static, bundled, no network. In 300 ms, out
/// 200 ms; with reduce motion a 150 ms fade each way (spec §3.1 WL1).
Future<void> showPathPreview(
  BuildContext context, {
  required PathPreviewKind kind,
  required VoidCallback onGetStarted,
}) {
  final loc = AppLocalizations.of(context)!;
  return Navigator.of(context).push(
    _PreviewRoute(
      reduceMotion: reduceMotionOf(context),
      barrierLabel: loc.flow_close,
      builder: (_) => PathPreviewSheet(kind: kind, onGetStarted: onGetStarted),
    ),
  );
}

class _PreviewRoute extends PopupRoute<void> {
  _PreviewRoute({
    required this.reduceMotion,
    required this.barrierLabel,
    required this.builder,
  });

  final bool reduceMotion;
  final WidgetBuilder builder;

  @override
  final String barrierLabel;

  @override
  Color get barrierColor => Colors.black54;

  @override
  bool get barrierDismissible => true;

  @override
  Duration get transitionDuration =>
      reduceMotion ? kReducedMotionFade : const Duration(milliseconds: 300);

  @override
  Duration get reverseTransitionDuration =>
      reduceMotion ? kReducedMotionFade : const Duration(milliseconds: 200);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => builder(context);

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (reduceMotion) return FadeTransition(opacity: animation, child: child);
    final curved = CurvedAnimation(
      parent: animation,
      curve: Easing.emphasizedDecelerate,
      reverseCurve: Easing.emphasizedAccelerate,
    );
    return SlideTransition(
      position: Tween(
        begin: const Offset(0, 1),
        end: Offset.zero,
      ).animate(curved),
      child: child,
    );
  }
}

class PathPreviewSheet extends ConsumerWidget {
  const PathPreviewSheet({
    super.key,
    required this.kind,
    required this.onGetStarted,
  });

  final PathPreviewKind kind;
  final VoidCallback onGetStarted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final openCountries = ref.watch(datingOpenCountriesProvider);
    final (title, lines, icon) = switch (kind) {
      PathPreviewKind.relationship => (
        loc.flow_previewRelationshipTitle,
        [
          loc.flow_previewRelationshipLine1,
          loc.flow_previewRelationshipLine2,
          loc.flow_previewRelationshipLine3,
        ],
        Icons.favorite_outline,
      ),
      PathPreviewKind.dating => (
        loc.flow_previewDatingTitle,
        [
          loc.flow_previewDatingLine1,
          loc.flow_previewDatingLine2,
          loc.flow_previewDatingLine3,
          // Left out when the list is empty or has never been read (D15).
          if (openCountries.isNotEmpty)
            loc.flow_previewDatingCountries(
              formatCountryList(
                openCountries,
                nameOf:
                    (iso) => countryNameFor(
                      iso,
                      special: {
                        'GB': loc.flow_countryUk,
                        'US': loc.flow_countryUs,
                      },
                    ),
                pair: loc.flow_listTwo,
              ),
            ),
        ],
        Icons.people_outline,
      ),
      PathPreviewKind.justMe => (
        loc.flow_previewJustMeTitle,
        [
          loc.flow_previewJustMeLine1,
          loc.flow_previewJustMeLine2,
          loc.flow_previewJustMeLine3,
          loc.flow_previewJustMeLine4,
        ],
        Icons.menu_book_outlined,
      ),
    };

    return AllowLargeText(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: ContentWidth.sheet,
            maxHeight: MediaQuery.sizeOf(context).height * 0.9,
          ),
          child: Material(
            color: colorScheme.surface,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(BorderRadiusTokens.xl),
            ),
            child: SafeArea(
              top: false,
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  Spacing.lg.w,
                  Spacing.lg.h,
                  Spacing.lg.w,
                  Spacing.md.h,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Decorative: the lines below are the readable content.
                    ExcludeSemantics(
                      child: Center(
                        child: CircleAvatar(
                          radius: 36,
                          backgroundColor: colorScheme.primaryContainer,
                          child: Icon(
                            icon,
                            size: IconSizes.lg,
                            color: colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                    ),
                    Gap(Spacing.md.h),
                    Semantics(
                      header: true,
                      child: Text(
                        title,
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: colorScheme.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Gap(Spacing.md.h),
                    for (final line in lines) ...[
                      Text(
                        line,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: colorScheme.onSurface,
                        ),
                      ),
                      Gap(Spacing.sm.h),
                    ],
                    Gap(Spacing.md.h),
                    FlowPrimaryButton(
                      label: loc.flow_welcomeGetStarted,
                      onPressed: () {
                        Navigator.of(context).pop();
                        onGetStarted();
                      },
                    ),
                    const Gap(Spacing.sm),
                    FlowSecondaryButton(
                      label: loc.flow_close,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: Write Welcome and the invite landing**

Create `lib/features/auth/sign_up/presentation/screens/welcome_screen.dart` with exactly:

```dart
import 'package:attune/app/documentations/legal_documentation/data/legal_documentation_data.dart';
import 'package:attune/app/routing/app_router.dart' show RouteNames;
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/metrics/metric_counter.dart';
import 'package:attune/core/providers/routing_providers.dart';
import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/core/utils/bottom_sheet_utils.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_frame.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/path_preview_sheet.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';

/// WL1 · Welcome (`/welcome`, Spec 1 §3.1): the three ways in and every
/// gate before anyone types. Replaces IntroScreen under flow_signin_v2.
/// Nothing is preselected and nothing here touches the network.
class WelcomeScreen extends ConsumerWidget {
  const WelcomeScreen({super.key});

  /// Any button marks first launch done, exactly as IntroScreen does, so
  /// the router doesn't bounce the next route back here.
  static Future<void> leave(
    BuildContext context,
    WidgetRef ref,
    String location,
  ) async {
    await ref.read(preferencesServiceProvider).setFirstLaunchCompleted();
    ref.read(routingNotifierProvider).completeFirstLaunch();
    if (context.mounted) context.go(location);
  }

  /// `/signup?entry=…`, with `back` when the first step's back button
  /// should return somewhere other than Welcome.
  static String signUpLocation(String entry, {String? back}) =>
      Uri(
        path: RouteNames.signUp,
        queryParameters: {'entry': entry, if (back != null) 'back': back},
      ).toString();

  void _preview(BuildContext context, WidgetRef ref, PathPreviewKind kind) {
    ref.read(metricCounterProvider).bump(switch (kind) {
      PathPreviewKind.relationship =>
        ClientMetricKey.welcomePreviewRelationship,
      PathPreviewKind.dating => ClientMetricKey.welcomePreviewDating,
      PathPreviewKind.justMe => ClientMetricKey.welcomePreviewJustMe,
    });
    showPathPreview(
      context,
      kind: kind,
      onGetStarted: () => leave(context, ref, signUpLocation('new')),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return FlowFrame(
      title: loc.flow_welcomeTitle,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PathCard(
            title: loc.flow_pathRelationshipTitle,
            line: loc.flow_pathRelationshipLine,
            onTap: () => _preview(context, ref, PathPreviewKind.relationship),
          ),
          Gap(Spacing.sm.h),
          _PathCard(
            title: loc.flow_pathDatingTitle,
            line: loc.flow_pathDatingLine,
            onTap: () => _preview(context, ref, PathPreviewKind.dating),
          ),
          Gap(Spacing.sm.h),
          _PathCard(
            title: loc.flow_pathJustMeTitle,
            line: loc.flow_pathJustMeLine,
            onTap: () => _preview(context, ref, PathPreviewKind.justMe),
          ),
          Gap(Spacing.lg.h),
          FlowPrimaryButton(
            label: loc.flow_welcomeGetStarted,
            onPressed: () => leave(context, ref, signUpLocation('new')),
          ),
          const Gap(Spacing.sm),
          FlowSecondaryButton(
            label: loc.flow_welcomeHaveAccount,
            onPressed: () => leave(context, ref, signUpLocation('returning')),
          ),
          const Gap(Spacing.sm),
          FlowSecondaryButton(
            label: loc.flow_welcomeHaveInvite,
            onPressed: () => leave(context, ref, RouteNames.invite),
          ),
          FlowTextLink(
            label: loc.flow_welcomeReadOpinions,
            onPressed: () => leave(context, ref, RouteNames.guestAge),
          ),
          Gap(Spacing.md.h),
          Text(
            loc.flow_welcomeFooter,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          Wrap(
            alignment: WrapAlignment.center,
            children: [
              FlowTextLink(
                label: loc.flow_linkTerms,
                onPressed:
                    () => BottomSheetUtils.showDocumentationBottomSheet(
                      context: context,
                      document: LegalDocumentationData.termsOfService(context),
                      showButtons: false,
                    ),
              ),
              FlowTextLink(
                label: loc.flow_linkPrivacy,
                onPressed:
                    () => BottomSheetUtils.showDocumentationBottomSheet(
                      context: context,
                      document: LegalDocumentationData.privacyPolicy(context),
                      showButtons: false,
                    ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One of the three equal cards: a button that opens the path's preview.
class _PathCard extends StatelessWidget {
  const _PathCard({
    required this.title,
    required this.line,
    required this.onTap,
  });

  final String title;
  final String line;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Semantics(
      button: true,
      label: loc.flow_welcomeCardSemantics(title, line),
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: colorScheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadiusTokens.lgAll,
          side: BorderSide(color: colorScheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: EdgeInsets.all(Spacing.md.w),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: colorScheme.onSurface,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Gap(Spacing.xs.h),
                        Text(
                          line,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
```

Create `lib/features/auth/sign_up/presentation/screens/invite_landing_screen.dart` with exactly:

```dart
import 'package:attune/app/routing/app_router.dart' show RouteNames;
import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/features/auth/sign_up/domain/invite_code.dart';
import 'package:attune/features/auth/sign_up/presentation/screens/welcome_screen.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_frame.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_text_field.dart';
import 'package:attune/features/onboarding/data/onboarding_store.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// RI-1 and RI-2 (`/invite`, pre-auth; Spec 1 §3.8). With a code from a
/// link (the anonymous slot, §5.5) it says only that someone invited you:
/// no inviter name before sign-in proves the phone (10 F-10). Without one,
/// it asks for the code first. Joining (RI-3) comes after sign-in, in W4b;
/// until then the signed-in gate accepts the stored code as today.
class InviteLandingScreen extends ConsumerStatefulWidget {
  const InviteLandingScreen({super.key});

  @override
  ConsumerState<InviteLandingScreen> createState() =>
      _InviteLandingScreenState();
}

class _InviteLandingScreenState extends ConsumerState<InviteLandingScreen> {
  final _code = TextEditingController();
  late bool _hasCode;
  bool _invalid = false;

  OnboardingStore get _anonymousStore => OnboardingStore(
    ref.read(sharedPreferencesProvider),
    scope: OnboardingStore.anonymousScope,
  );

  @override
  void initState() {
    super.initState();
    _hasCode = _anonymousStore.pendingInviteCode != null;
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _submitCode() async {
    final code = normalizeInviteCode(_code.text);
    if (code == null) {
      setState(() => _invalid = true);
      return;
    }
    await OnboardingStore.storeInviteFromLink(
      ref.read(sharedPreferencesProvider),
      code,
    );
    if (mounted) {
      setState(() {
        _invalid = false;
        _hasCode = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    void back() => context.go(RouteNames.welcome);

    if (!_hasCode) {
      return FlowFrame(
        title: loc.flow_inviteCodeTitle,
        onBack: back,
        body: FlowTextField(
          controller: _code,
          label: loc.flow_inviteCodeLabel,
          errorText: _invalid ? loc.flow_inviteCodeError : null,
          textCapitalization: TextCapitalization.characters,
          textInputAction: TextInputAction.done,
          inputFormatters: [LengthLimitingTextInputFormatter(12)],
          autofocus: true,
          onSubmitted: (_) => _submitCode(),
        ),
        actions: [
          FlowPrimaryButton(label: loc.flow_continue, onPressed: _submitCode),
        ],
      );
    }

    final theme = Theme.of(context);
    return FlowFrame(
      title: loc.flow_inviteTitle,
      onBack: back,
      body: Text(
        loc.flow_inviteBody,
        style: theme.textTheme.bodyLarge?.copyWith(
          color: theme.colorScheme.onSurface,
        ),
      ),
      actions: [
        FlowPrimaryButton(
          label: loc.flow_inviteCreate,
          onPressed: () => context.go(WelcomeScreen.signUpLocation('invite')),
        ),
        FlowSecondaryButton(
          label: loc.flow_welcomeHaveAccount,
          onPressed:
              () => context.go(WelcomeScreen.signUpLocation('returning')),
        ),
      ],
    );
  }
}
```

- [ ] **Step 6: Run the tests, create the goldens and look at them**

```bash
cd /Users/user/attune
flutter test --no-pub test/features/auth/sign_up/welcome_screen_test.dart 2>&1 | tr '\r' '\n' | grep -E "All tests passed|Some tests failed" | tail -1
flutter test --no-pub --update-goldens test/features/auth/sign_up/w2a_goldens_test.dart 2>&1 | tr '\r' '\n' | grep -E "All tests passed|Some tests failed|overflow" | tail -1
ls test/features/auth/sign_up/goldens | wc -l
flutter test --no-pub test/features/auth/sign_up/w2a_goldens_test.dart 2>&1 | tr '\r' '\n' | grep -E "All tests passed|Some tests failed" | tail -1
```
Expected: `All tests passed!`; `All tests passed!` with no overflow line; `24` images; `All tests passed!` again. Open `welcome.scale2.0.png`, `welcome_preview_dating.scale1.0.png`, `guest_age_gate_error.scale2.0.png` and `under_age_stop.rtl.png` (the Read tool shows images): text is the test font's boxes; check that nothing is clipped at 2.0, the buttons are full width and at least 48 dp tall, the RTL image mirrors the back button, and the Dating preview has its countries line.

- [ ] **Step 7: Format and analyze**

```bash
cd /Users/user/attune
dart format lib/features/auth/sign_up test/features/auth/sign_up
flutter analyze --no-pub lib/features/auth/sign_up test/features/auth/sign_up 2>&1 | grep -E "^\s*(error|warning) " | head
```
Expected: `Formatted … (0 changed)`; no `error`/`warning` line.

---

### Task 4: The router, the boot values, the invite link; W2a gate (W2a; §5.2 main.dart, §5.4, R2, R3)

**Files:**
- Create: `lib/app/routing/sign_in_redirect.dart`
- Create: `lib/features/auth/sign_up/presentation/sign_up_flags.dart`
- Modify: `lib/app/routing/app_router.dart` (imports; the redirect; five routes after `/home`)
- Modify: `lib/app/app.dart` (one listener; one import)
- Modify: `lib/main.dart` (imports; boot values; the invite link's target)
- Create: `test/app/routing/sign_in_redirect_test.dart`

**Interfaces:**
- Consumes: Tasks 1–3; W1's `flowSignInV2Provider`, `PublicAppConfigCache`, `Environment.flowV2Default`; `AgeGateStore.readGuestOk|readBlocked|restoreBlock`.
- Produces: `appRedirect(RoutingNotifier, String location) → String?` (used by `createAppRouter`), `flowV2Redirect(RoutingNotifier, String)`, `inviteLinkLocation(RoutingNotifier) → String`, the sets `firstLaunchAllowedRoutes`, `underAgeBlockedRoutes`, `flowV2OnlyRoutes`; `signInFlowV2Provider` (never throws; off when unreadable); routes `/welcome`, `/signup` (today's `LoginScreen` until Task 8), `/guest-age`, `/invite`, `/age-stop` (`NoTransitionPage`, `?from=server` → the server variant).

- [ ] **Step 1: Write the failing test**

Create `test/app/routing/sign_in_redirect_test.dart` with exactly:

```dart
// Spec 1 W2a (§5.4, R2): the app router's redirect. With flow_signin_v2 off
// it is today's rule for every existing route; with it on, the pre-auth
// allow-list, the guest gate and the under-18 block.
import 'package:attune/app/routing/app_router.dart' show RouteNames;
import 'package:attune/app/routing/routing_notifier.dart';
import 'package:attune/app/routing/sign_in_redirect.dart';
import 'package:flutter_test/flutter_test.dart';

RoutingNotifier _routing({
  bool flowV2 = true,
  bool firstLaunch = false,
  bool signedIn = false,
  bool guestOk = false,
  bool blocked = false,
}) => RoutingNotifier(
  isFirstLaunch: firstLaunch,
  flowV2: flowV2,
  guestAgeOk: guestOk,
  underAgeBlocked: blocked,
  currentUserId: () => signedIn ? 'user-1' : null,
);

/// Routes that exist today, before Spec 1.
const _existing = [
  '/_invisible',
  RouteNames.intro,
  RouteNames.home,
  RouteNames.login,
  RouteNames.onboarding,
  RouteNames.settings,
  RouteNames.safetyResources,
  '/chatScreen',
];

/// Today's rule, written out, so the flag-off branch is compared with it.
String? _today(RoutingNotifier r, String location) {
  if (location == '/_invisible') {
    return r.isFirstLaunch ? RouteNames.intro : RouteNames.home;
  }
  if (r.isFirstLaunch && location != RouteNames.intro) return RouteNames.intro;
  return null;
}

void main() {
  group('flag off: today, byte for byte', () {
    for (final firstLaunch in [true, false]) {
      for (final signedIn in [true, false]) {
        test('first launch $firstLaunch, signed in $signedIn', () {
          final r = _routing(
            flowV2: false,
            firstLaunch: firstLaunch,
            signedIn: signedIn,
          );
          for (final location in _existing) {
            expect(
              appRedirect(r, location),
              _today(r, location),
              reason: location,
            );
          }
        });
      }
    }

    test('a v2-only route reached with the flag off goes where today goes', () {
      for (final location in flowV2OnlyRoutes) {
        expect(appRedirect(_routing(flowV2: false), location), RouteNames.home);
        expect(
          appRedirect(_routing(flowV2: false, firstLaunch: true), location),
          RouteNames.intro,
        );
      }
    });

    test('an invite link keeps today\'s /onboarding', () {
      expect(
        inviteLinkLocation(_routing(flowV2: false)),
        RouteNames.onboarding,
      );
    });
  });

  group('flag on', () {
    test('first launch opens Welcome, not IntroScreen', () {
      expect(
        appRedirect(_routing(firstLaunch: true), '/_invisible'),
        RouteNames.welcome,
      );
      expect(appRedirect(_routing(), '/_invisible'), RouteNames.home);
    });

    test('while first launch is on, only the pre-auth routes are open', () {
      final r = _routing(firstLaunch: true);
      for (final location in [
        RouteNames.welcome,
        RouteNames.signUp,
        RouteNames.guestAge,
        RouteNames.invite,
        RouteNames.ageStop,
        RouteNames.safetyResources,
      ]) {
        expect(appRedirect(r, location), isNull, reason: location);
      }
      for (final location in [
        RouteNames.home,
        RouteNames.onboarding,
        RouteNames.settings,
        RouteNames.login,
      ]) {
        expect(appRedirect(r, location), RouteNames.welcome, reason: location);
      }
    });

    test('every way to IntroScreen lands on Welcome', () {
      expect(appRedirect(_routing(), RouteNames.intro), RouteNames.welcome);
      expect(
        appRedirect(_routing(firstLaunch: true), RouteNames.intro),
        RouteNames.welcome,
      );
    });

    test('a signed-out guest who never passed G1 meets it before Opinions', () {
      expect(appRedirect(_routing(), RouteNames.home), RouteNames.guestAge);
      expect(appRedirect(_routing(guestOk: true), RouteNames.home), isNull);
      expect(appRedirect(_routing(signedIn: true), RouteNames.home), isNull);
    });

    test('G1 is once per install', () {
      expect(
        appRedirect(_routing(guestOk: true), RouteNames.guestAge),
        RouteNames.home,
      );
    });

    test(
      'an under-18 block closes sign-up, invites and G1, even on first launch',
      () {
        for (final firstLaunch in [true, false]) {
          final r = _routing(
            blocked: true,
            firstLaunch: firstLaunch,
            guestOk: true,
          );
          for (final location in underAgeBlockedRoutes) {
            expect(
              appRedirect(r, location),
              RouteNames.ageStop,
              reason: location,
            );
          }
          expect(appRedirect(r, RouteNames.ageStop), isNull);
          expect(appRedirect(r, RouteNames.welcome), isNull);
        }
      },
    );

    test(
      'an invite link opens RI-1 when signed out, /onboarding when signed in',
      () {
        expect(inviteLinkLocation(_routing()), RouteNames.invite);
        expect(
          inviteLinkLocation(_routing(signedIn: true)),
          RouteNames.onboarding,
        );
      },
    );
  });

  test('RoutingNotifier notifies only on a real change', () {
    final r = _routing(flowV2: false);
    var notified = 0;
    r.addListener(() => notified++);
    r.setFlowV2(false);
    r.setGuestAgeOk(false);
    r.setUnderAgeBlocked(false);
    expect(notified, 0);
    r.setFlowV2(true);
    r.setGuestAgeOk(true);
    r.setUnderAgeBlocked(true);
    expect(notified, 3);
  });
}
```

```bash
cd /Users/user/attune
flutter test --no-pub test/app/routing/sign_in_redirect_test.dart 2>&1 | tr '\r' '\n' | grep -E "Error when reading" | head -1
```
Expected: `Error when reading 'lib/app/routing/sign_in_redirect.dart': No such file or directory`.

- [ ] **Step 2: Write the redirect**

Create `lib/app/routing/sign_in_redirect.dart` with exactly:

```dart
import 'package:attune/app/routing/app_router.dart' show RouteNames;
import 'package:attune/app/routing/routing_notifier.dart';

/// Pre-auth routes open while first launch is still on (Spec 1 §5.4).
const firstLaunchAllowedRoutes = <String>{
  RouteNames.welcome,
  RouteNames.signUp,
  RouteNames.guestAge,
  RouteNames.invite,
  RouteNames.ageStop,
  RouteNames.intro,
  RouteNames.safetyResources,
};

/// What X1's device block closes (spec §3.6, §5.4).
const underAgeBlockedRoutes = <String>{
  RouteNames.signUp,
  RouteNames.invite,
  RouteNames.guestAge,
};

/// The routes only the v2 sign-in uses.
const flowV2OnlyRoutes = <String>{
  RouteNames.welcome,
  RouteNames.signUp,
  RouteNames.guestAge,
  RouteNames.invite,
  RouteNames.ageStop,
};

/// The app router's redirect (`createAppRouter`). Null: stay.
///
/// With flow_signin_v2 off it is today's rule, unchanged: first launch
/// shows IntroScreen and nothing else. The one addition is that a v2-only
/// route (reached only if the flag went off mid-session) goes home.
String? appRedirect(RoutingNotifier routing, String location) {
  if (routing.flowV2) return flowV2Redirect(routing, location);

  if (location == '/_invisible') {
    return routing.isFirstLaunch ? RouteNames.intro : RouteNames.home;
  }

  if (routing.isFirstLaunch && location != RouteNames.intro) {
    return RouteNames.intro;
  }

  if (flowV2OnlyRoutes.contains(location)) return RouteNames.home;

  return null;
}

/// Under flow_signin_v2 (spec §5.4).
String? flowV2Redirect(RoutingNotifier routing, String location) {
  if (routing.underAgeBlocked && underAgeBlockedRoutes.contains(location)) {
    return RouteNames.ageStop;
  }
  if (location == '/_invisible') {
    return routing.isFirstLaunch ? RouteNames.welcome : RouteNames.home;
  }
  // Every legacy way to IntroScreen (sign-out, account deletion, the safety
  // sign-out) lands on Welcome instead.
  if (location == RouteNames.intro) return RouteNames.welcome;
  if (routing.isFirstLaunch) {
    return firstLaunchAllowedRoutes.contains(location)
        ? null
        : RouteNames.welcome;
  }
  // G1 is once per install.
  if (location == RouteNames.guestAge && routing.guestAgeOk) {
    return RouteNames.home;
  }
  if (location == RouteNames.home &&
      !routing.isSignedIn &&
      !routing.guestAgeOk) {
    return RouteNames.guestAge;
  }
  return null;
}

/// Where main.dart's invite-link handler goes (spec §5.2, R3): under
/// flow_signin_v2 a signed-out invitee lands on RI-1; anyone signed in, and
/// everyone with the flag off, keeps today's /onboarding, whose gate
/// accepts the stored code.
String inviteLinkLocation(RoutingNotifier routing) =>
    routing.flowV2 && !routing.isSignedIn
        ? RouteNames.invite
        : RouteNames.onboarding;
```

- [ ] **Step 3: Use it in the router and add the routes**

In `lib/app/routing/app_router.dart` (the Games routes, the dating block and every other route stay exactly as they are):

Edit 1 of 3. Replace exactly:

```dart
import 'package:attune/features/auth/intro/intro_screen.dart';
import 'package:attune/features/auth/log_in/presentation/screens/login_screen.dart';
import 'package:attune/features/dating/presentation/screens/dating_dashboard_screen.dart';
import 'package:attune/features/games/paint_ball/presentation/screens/paint_ball_battle_screen.dart';
```

with:

```dart
import 'package:attune/features/auth/intro/intro_screen.dart';
import 'package:attune/features/auth/log_in/presentation/screens/login_screen.dart';
import 'package:attune/app/routing/sign_in_redirect.dart';
import 'package:attune/features/auth/sign_up/presentation/screens/guest_age_gate_screen.dart';
import 'package:attune/features/auth/sign_up/presentation/screens/invite_landing_screen.dart';
import 'package:attune/features/auth/sign_up/presentation/screens/under_age_stop_screen.dart';
import 'package:attune/features/auth/sign_up/presentation/screens/welcome_screen.dart';
import 'package:attune/features/dating/presentation/screens/dating_dashboard_screen.dart';
import 'package:attune/features/games/paint_ball/presentation/screens/paint_ball_battle_screen.dart';
```

Edit 2 of 3. Replace exactly:

```dart
    initialLocation: '/_invisible',
    refreshListenable: routingNotifier,
    redirect: (context, state) {
      if (state.matchedLocation == '/_invisible') {
        return routingNotifier.isFirstLaunch
            ? RouteNames.intro
            : RouteNames.home;
      }

      if (routingNotifier.isFirstLaunch &&
          state.matchedLocation != RouteNames.intro) {
        return RouteNames.intro;
      }

      return null;
    },
    routes: [
      GoRoute(
```

with:

```dart
    initialLocation: '/_invisible',
    refreshListenable: routingNotifier,
    // Spec 1 W2: the first-launch rules and the v2 sign-in rules live in
    // sign_in_redirect.dart (flag off: today's rule, unchanged).
    redirect:
        (context, state) => appRedirect(routingNotifier, state.matchedLocation),
    routes: [
      GoRoute(
```

Edit 3 of 3. Replace exactly:

```dart
        name: 'home',
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
```

with:

```dart
        name: 'home',
        builder: (context, state) => const HomeScreen(),
      ),
      // Spec 1 W2 (§5.4): the v2 sign-in routes, reached only under
      // flow_signin_v2 (the redirect above sends a stray visit home).
      GoRoute(
        path: RouteNames.welcome,
        name: 'welcome',
        builder: (context, state) => const WelcomeScreen(),
      ),
      GoRoute(
        path: RouteNames.signUp,
        name: 'signUp',
        // W2a: today's phone sign-in, so the development app keeps working
        // until W2b's SignUpFlow takes this route over.
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: RouteNames.guestAge,
        name: 'guestAge',
        builder: (context, state) => const GuestAgeGateScreen(),
      ),
      GoRoute(
        path: RouteNames.invite,
        name: 'invite',
        builder: (context, state) => const InviteLandingScreen(),
      ),
      GoRoute(
        path: RouteNames.ageStop,
        name: 'ageStop',
        // Never animated (§2.2): no route transition either.
        pageBuilder:
            (context, state) => NoTransitionPage(
              key: state.pageKey,
              child: UnderAgeStopScreen(
                serverRefused: state.uri.queryParameters['from'] == 'server',
              ),
            ),
      ),
      GoRoute(
```

- [ ] **Step 4: The flag for widgets, and the router following it**

Create `lib/features/auth/sign_up/presentation/sign_up_flags.dart` with exactly:

```dart
import 'package:attune/core/flags/public_app_config.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// flow_signin_v2 for widgets and listeners (Spec 1 §5.3): the effective
/// value from [flowSignInV2Provider], or off when it can't be read at all
/// (no SharedPreferences in a bare test host). A shared screen that only
/// branches on the flag never throws over it.
final signInFlowV2Provider = Provider<bool>((ref) {
  try {
    return ref.watch(flowSignInV2Provider);
  } catch (_) {
    return false;
  }
});
```

In `lib/app/app.dart` (the only change: one listener at the top of `build`):

Edit 1 of 2. Replace exactly:

```dart
import 'package:attune/core/providers/locale_provider.dart';
import 'package:attune/core/providers/routing_providers.dart';
import 'package:attune/core/providers/theme_provider.dart';
import 'package:attune/core/ui/feedback/sound_service.dart';
```

with:

```dart
import 'package:attune/core/providers/locale_provider.dart';
import 'package:attune/core/providers/routing_providers.dart';
import 'package:attune/features/auth/sign_up/presentation/sign_up_flags.dart';
import 'package:attune/core/providers/theme_provider.dart';
import 'package:attune/core/ui/feedback/sound_service.dart';
```

Edit 2 of 2. Replace exactly:

```dart
  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);
    final themeMode = ref.watch(themeModeProvider);
```

with:

```dart
  @override
  Widget build(BuildContext context) {
    // Spec 1 W2a (§5.3, §5.4): the router's sign-in flow follows the live
    // public config once it has been read.
    ref.listen<bool>(
      signInFlowV2Provider,
      (_, next) => ref.read(routingNotifierProvider).setFlowV2(next),
    );
    final router = ref.watch(appRouterProvider);
    final themeMode = ref.watch(themeModeProvider);
```

- [ ] **Step 5: Boot values and the invite link in `main.dart`**

In `lib/main.dart` (`waitForRouterSettled` and the first-launch clear stay exactly as they are, R3):

Edit 1 of 4. Replace exactly:

```dart
import 'package:attune/app/routing/app_router.dart';
import 'package:attune/app/routing/routing_notifier.dart';
import 'package:attune/core/config/env.dart';
import 'package:attune/core/notifications/config/feature/notification_config.dart';
```

with:

```dart
import 'package:attune/app/routing/app_router.dart';
import 'package:attune/app/routing/routing_notifier.dart';
import 'package:attune/app/routing/sign_in_redirect.dart';
import 'package:attune/core/config/env.dart';
import 'package:attune/core/notifications/config/feature/notification_config.dart';
```

Edit 2 of 4. Replace exactly:

```dart
import 'package:attune/features/planning/presentation/screens/planning_home_screen.dart'
    show PlanningHomeTab;
import 'package:attune/features/onboarding/data/onboarding_store.dart';
import 'package:flutter/material.dart';
```

with:

```dart
import 'package:attune/features/planning/presentation/screens/planning_home_screen.dart'
    show PlanningHomeTab;
import 'package:attune/core/flags/public_app_config.dart'
    show PublicAppConfigCache;
import 'package:attune/features/auth/sign_up/data/age_gate_store.dart';
import 'package:attune/features/onboarding/data/onboarding_store.dart';
import 'package:flutter/material.dart';
```

Edit 3 of 4. Replace exactly:

```dart

  final prefs = await SharedPreferences.getInstance();
  final routingNotifier = RoutingNotifier(
    prefs: prefs,
    isFirstLaunch: PreferencesService(prefs).isFirstLaunch,
  );
  final appRouter = createAppRouter(routingNotifier);
```

with:

```dart

  final prefs = await SharedPreferences.getInstance();
  // Spec 1 W2a (§3.6): an under-18 block the iOS Keychain kept across a
  // reinstall is copied back before the router reads it. Bounded: the
  // keystore must never hold the first frame.
  try {
    await AgeGateStore.restoreBlock(prefs).timeout(const Duration(seconds: 1));
  } catch (error) {
    debugPrint('[startup] age block restore skipped: ${error.runtimeType}');
  }
  final routingNotifier = RoutingNotifier(
    prefs: prefs,
    isFirstLaunch: PreferencesService(prefs).isFirstLaunch,
    // Spec 1 §5.3: the last public config this phone read, else the build
    // default; App keeps it current once the config has been fetched.
    flowV2:
        PublicAppConfigCache(prefs).read()?.flowSignInV2 ??
        Environment.flowV2Default,
    guestAgeOk: AgeGateStore.readGuestOk(prefs),
    underAgeBlocked: AgeGateStore.readBlocked(prefs, DateTime.now()),
  );
  final appRouter = createAppRouter(routingNotifier);
```

Edit 4 of 4. Replace exactly:

```dart
  await container.read(preferencesServiceProvider).setFirstLaunchCompleted();
  if (!context.mounted) return;
  container.read(routingNotifierProvider).completeFirstLaunch();
  GoRouter.of(context).go(RouteNames.onboarding);
}

```

with:

```dart
  await container.read(preferencesServiceProvider).setFirstLaunchCompleted();
  if (!context.mounted) return;
  final routing = container.read(routingNotifierProvider);
  routing.completeFirstLaunch();
  // Spec 1 W2a (§5.2, R3): RI-1 for a signed-out invitee under
  // flow_signin_v2, today's /onboarding otherwise.
  GoRouter.of(context).go(inviteLinkLocation(routing));
}

```

- [ ] **Step 6: Run the tests**

```bash
cd /Users/user/attune
flutter test --no-pub test/app/routing/sign_in_redirect_test.dart test/features/chat/chat_screen_view_active_test.dart test/widget_test.dart test/login_profile_test.dart 2>&1 | tr '\r' '\n' | grep -E "All tests passed|Some tests failed" | tail -1
dart format lib/app/routing/sign_in_redirect.dart lib/features/auth/sign_up/presentation/sign_up_flags.dart test/app/routing/sign_in_redirect_test.dart
flutter analyze --no-pub lib/main.dart lib/app test/app 2>&1 | grep -E "^\s*(error|warning) " | head
```
Expected: `All tests passed!` (flag off: today's rule for every existing route, first launch or not, signed in or not; flag on: first launch opens Welcome, the pre-auth allow-list, `/intro` → `/welcome`, the guest gate, G1 once, the under-18 block even on first launch, the invite link's target); `Formatted 3 files (0 changed)`; no `error`/`warning` line in the touched files (`lib/app/app_info/*` carries two older warnings that are not this plan's).

- [ ] **Step 7: Mutation check (flag-off must stay today's)**

```bash
cd /Users/user/attune
cp lib/app/routing/sign_in_redirect.dart .superpowers/sdd/2026-10-25-spec1-w2/redirect.dart.keep
perl -0pi -e 's/  if \(routing.flowV2\) return flowV2Redirect\(routing, location\);/  return flowV2Redirect(routing, location);/' lib/app/routing/sign_in_redirect.dart
flutter test --no-pub test/app/routing/sign_in_redirect_test.dart 2>&1 | tr '\r' '\n' | grep -E "Some tests failed|All tests passed" | tail -1
cp .superpowers/sdd/2026-10-25-spec1-w2/redirect.dart.keep lib/app/routing/sign_in_redirect.dart && rm .superpowers/sdd/2026-10-25-spec1-w2/redirect.dart.keep
```
Expected: `Some tests failed.` (the flag-off group), then the file is restored.

- [ ] **Step 8: W2a regression gate**

```bash
cd /Users/user/attune
flutter test --no-pub 2>&1 | tr '\r' '\n' | grep -E 'All tests passed!|Some tests failed' | tail -1
flutter analyze --no-pub lib test > .superpowers/sdd/2026-10-25-spec1-w2/analyze-w2a.txt 2>&1
comm -13 .superpowers/sdd/2026-10-25-spec1-w2/analyze-errors-baseline.txt <(grep -E '^\s*error ' .superpowers/sdd/2026-10-25-spec1-w2/analyze-w2a.txt | sed -E 's/:[0-9]+:[0-9]+//' | sort -u)
diff <(grep -E 'lib/features/games/|auth_exports\.dart|lib/home/home_screen\.dart|lib/features/opinions/|games_contracts\.sql' .superpowers/sdd/2026-10-25-spec1-w2/git-status-before.txt) <(git status --short | grep -E 'lib/features/games/|auth_exports\.dart|lib/home/home_screen\.dart|lib/features/opinions/|games_contracts\.sql')
```
Expected: `All tests passed!`; the `comm` prints nothing; the `diff` prints nothing.

Manual check (development project, `flow_signin_v2` on, `FLOW_V2_DEFAULT` true): a fresh install opens Welcome; each card opens its preview; "Read Opinions first" opens G1, then guest Opinions; a year under 18 opens X1 and reopening the app lands on X1's routes; "Get started" and "I already have an account" open today's phone sign-in (until Task 8); an invite link opened signed out lands on "You've been invited to Attune".

---

### Task 5: W2b copy, the pure sign-up rules and the device draft (W2b; §3.3 A1–A4, §5.5, P-11, P-12, P-13)

**Files:**
- Modify: `lib/i10n/app_en.arb` (+ regenerate)
- Create: `lib/features/auth/sign_up/domain/display_name_validator.dart`, `birth_date_validator.dart`, `phone_entry.dart`, `default_phone_country.dart`, `resend_ladder.dart`, `otp_failure.dart`, `sign_up_draft.dart`
- Create: `lib/features/auth/sign_up/data/sign_up_draft_store.dart`
- Create: `test/features/auth/sign_up/sign_up_domain_test.dart`, `test/features/auth/sign_up/sign_up_draft_store_test.dart`

**Interfaces:**
- Consumes: `phone_numbers_parser` 9.0.23 (`PhoneNumber.parse`, `metadataByIsoCode`, `metadataLenghtsByIsoCode`), `intl` 0.19 `dateTimePatternMap()`, `PhoneCountries.all`, gotrue's `AuthException`.
- Produces: `enum DisplayNameError {needsLetter, tooLong}`, `normalizeDisplayName(String)`, `validateDisplayName(String) → DisplayNameError?`; `enum BirthDateOrder {dayMonthYear, monthDayYear}`, `enum BirthDateError {dayRange, monthRange, yearDigits, noSuchDate, future, tooOld}`, `birthDateOrderFor(Locale)`, `validateBirthDate({day, month, year, todayUtc}) → ({DateTime? date, BirthDateError? error})`, `ageOn(DateTime birthDate, DateTime todayUtc) → int`, `birthDateExample(BirthDateOrder)`; `enum PhoneEntryError {tooShort, tooLong, wrongCountry}`, `parsePhoneEntry(String input, String isoCode) → ({String? e164, PhoneEntryError? error})`, `formatPhoneForDisplay(String e164)`, `countryOfPhone(String e164)`; `defaultPhoneCountry({String? simIso, String? regionIso, List<PhoneCountry>? countries}) → PhoneCountry?`; `ResendLadder.codeLifetime|waitAfter(int)|remaining({lastSentAt, sendCount, now})|offersOtherChannels(int)|saysUseNewest(int)|isExpired({lastSentAt, now})|clock(Duration)`; `enum OtpSendFailureKind {rateLimited, unavailable, signInOff}`, `OtpSendFailure(kind, {int? minutes})`, `classifyOtpSendError(Object)`, `enum OtpVerifyFailure {wrongCode, expired, rateLimited, unavailable}`, `classifyOtpVerifyError(Object, {lastSentAt, now})`; `enum SignUpEntry {newAccount('new'), returning('returning'), invite('invite')}` with `fromWire`; `SignUpDraft` (`entry`, `deviceNonce`, `createdAt`, `name`, `birthDate`, `phoneE164`, `countryIso`, `channel`, `lastSentAt`, `sendCount`, `verifiedUserId`, `awaitingCode`, `start(entry, {now, random})`, `newNonce([Random?])`, `copyWith`, `withoutCode({bool keepPhone = true})`, `toJson`, `fromJson`); `SignUpDraftStore(prefs, {now})` with `key = 'attune.flow.anonymous.signup_draft'`, `lifetime = 7 days`, `read()`, `static readFrom(prefs, now)`, `write(draft)`, `clear()`; `signUpDraftStoreProvider`.

- [ ] **Step 1: Write the failing tests**

Create `test/features/auth/sign_up/sign_up_domain_test.dart` with exactly:

```dart
// Spec 1 W2b (§3.3, §7.3): the pure sign-up rules.
import 'dart:async';
import 'dart:ui' show Locale;

import 'package:attune/features/auth/log_in/domain/phone_country.dart';
import 'package:attune/features/auth/sign_up/domain/birth_date_validator.dart';
import 'package:attune/features/auth/sign_up/domain/default_phone_country.dart';
import 'package:attune/features/auth/sign_up/domain/display_name_validator.dart';
import 'package:attune/features/auth/sign_up/domain/otp_failure.dart';
import 'package:attune/features/auth/sign_up/domain/phone_entry.dart';
import 'package:attune/features/auth/sign_up/domain/resend_ladder.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phone_numbers_parser/metadata.dart';
import 'package:phone_numbers_parser/phone_numbers_parser.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final _today = DateTime.utc(2026, 10, 25);

String _national(IsoCode iso) => metadataExamplesByIsoCode[iso]!.mobile;

void main() {
  group('display name (A1)', () {
    test('any script, kept as typed, inner spaces collapsed', () {
      expect(validateDisplayName('عائشة'), isNull);
      expect(validateDisplayName('Ɛsi  Ɔbɛng'), isNull);
      expect(normalizeDisplayName('  Ɛsi  Ɔbɛng '), 'Ɛsi Ɔbɛng');
      expect(validateDisplayName('张伟'), isNull);
    });

    test('at least one letter; digits and punctuation alone are refused', () {
      expect(validateDisplayName(''), DisplayNameError.needsLetter);
      expect(validateDisplayName('   '), DisplayNameError.needsLetter);
      expect(validateDisplayName('+233 24 412'), DisplayNameError.needsLetter);
      expect(validateDisplayName('!!'), DisplayNameError.needsLetter);
    });

    test('invisible and direction characters never count or survive', () {
      expect(validateDisplayName('​‮﻿'), DisplayNameError.needsLetter);
      expect(normalizeDisplayName('Ama​‮'), 'Ama');
    });

    test('40 characters at most, counted as the server counts them', () {
      expect(validateDisplayName('a' * 40), isNull);
      expect(validateDisplayName('a' * 41), DisplayNameError.tooLong);
      expect(
        validateDisplayName('${'a' * 39}😀'),
        isNull,
        reason: 'an emoji is one',
      );
    });
  });

  group('date of birth (A2)', () {
    test('field order follows the locale; Ghana reads day first', () {
      expect(
        birthDateOrderFor(const Locale('en', 'US')),
        BirthDateOrder.monthDayYear,
      );
      expect(
        birthDateOrderFor(const Locale('en', 'GB')),
        BirthDateOrder.dayMonthYear,
      );
      expect(
        birthDateOrderFor(const Locale('en', 'GH')),
        BirthDateOrder.dayMonthYear,
      );
      expect(
        birthDateOrderFor(const Locale('en', 'NG')),
        BirthDateOrder.dayMonthYear,
      );
      expect(
        birthDateOrderFor(const Locale('en', 'CA')),
        BirthDateOrder.dayMonthYear,
      );
      expect(
        birthDateOrderFor(const Locale('fr', 'FR')),
        BirthDateOrder.dayMonthYear,
      );
      expect(
        birthDateOrderFor(const Locale('en', 'PH')),
        BirthDateOrder.monthDayYear,
      );
      expect(birthDateExample(BirthDateOrder.dayMonthYear), '27 3 1996');
      expect(birthDateExample(BirthDateOrder.monthDayYear), '3 27 1996');
    });

    test('each mistake has its own message, in reading order', () {
      BirthDateError? e(String d, String m, String y) =>
          validateBirthDate(day: d, month: m, year: y, todayUtc: _today).error;
      expect(e('0', '3', '1996'), BirthDateError.dayRange);
      expect(e('32', '3', '1996'), BirthDateError.dayRange);
      expect(e('', '3', '1996'), BirthDateError.dayRange);
      expect(e('27', '13', '1996'), BirthDateError.monthRange);
      expect(e('27', '3', '96'), BirthDateError.yearDigits);
      expect(e('31', '4', '1996'), BirthDateError.noSuchDate);
      expect(e('29', '2', '2023'), BirthDateError.noSuchDate);
      expect(
        e('29', '2', '2024'),
        isNull,
        reason: 'a leap day exists in a leap year',
      );
      expect(e('26', '10', '2026'), BirthDateError.future);
      expect(e('24', '10', '1906'), BirthDateError.tooOld);
      expect(e('25', '10', '1906'), isNull, reason: 'exactly 120 years');
    });

    test('age on the UTC date, the server rule', () {
      expect(
        ageOn(DateTime.utc(2008, 10, 25), _today),
        18,
        reason: '18th birthday',
      );
      expect(ageOn(DateTime.utc(2008, 10, 26), _today), 17, reason: 'tomorrow');
      expect(ageOn(DateTime.utc(2008, 2, 29), DateTime.utc(2026, 2, 28)), 17);
      expect(ageOn(DateTime.utc(2008, 2, 29), DateTime.utc(2026, 3, 1)), 18);
    });
  });

  group('phone (A3)', () {
    test('a leading national 0 is dropped; the result is E.164', () {
      final national = _national(IsoCode.GH);
      final withZero = parsePhoneEntry('0$national', 'GH');
      expect(withZero.error, isNull);
      expect(withZero.e164, '+233$national');
      expect(parsePhoneEntry(national, 'GH').e164, '+233$national');
      expect(
        parsePhoneEntry('0${_national(IsoCode.GB)}', 'GB').e164,
        '+44${_national(IsoCode.GB)}',
      );
    });

    test('too short, too long, or not that country', () {
      final national = _national(IsoCode.GH);
      expect(
        parsePhoneEntry(national.substring(0, 5), 'GH').error,
        PhoneEntryError.tooShort,
      );
      expect(
        parsePhoneEntry('${national}12', 'GH').error,
        PhoneEntryError.tooLong,
      );
      expect(
        parsePhoneEntry('+44${_national(IsoCode.GB)}', 'GH').error,
        PhoneEntryError.wrongCountry,
      );
      expect(parsePhoneEntry('12', 'GH').error, PhoneEntryError.tooShort);
    });

    test('display form and country of a number', () {
      final e164 = '+233${_national(IsoCode.GH)}';
      expect(formatPhoneForDisplay(e164), startsWith('+233 '));
      expect(countryOfPhone(e164), 'GH');
      expect(countryOfPhone('+44${_national(IsoCode.GB)}'), 'GB');
    });
  });

  group('default country', () {
    test('SIM, then region, then none; never a hard-coded Ghana', () {
      expect(defaultPhoneCountry(simIso: 'gb', regionIso: 'US')?.isoCode, 'GB');
      expect(defaultPhoneCountry(regionIso: 'ng')?.isoCode, 'NG');
      expect(defaultPhoneCountry(), isNull);
      expect(defaultPhoneCountry(simIso: '', regionIso: 'ZZ'), isNull);
      expect(PhoneCountries.all, isNotEmpty);
    });
  });

  group('resend ladder (A4)', () {
    final sent = DateTime.utc(2026, 10, 25, 12);
    test('30 s, then 60 s, then 120 s', () {
      expect(ResendLadder.waitAfter(1), const Duration(seconds: 30));
      expect(ResendLadder.waitAfter(2), const Duration(seconds: 60));
      expect(ResendLadder.waitAfter(3), const Duration(seconds: 120));
      expect(ResendLadder.waitAfter(7), const Duration(seconds: 120));
      expect(
        ResendLadder.remaining(
          lastSentAt: sent,
          sendCount: 2,
          now: sent.add(const Duration(seconds: 45)),
        ),
        const Duration(seconds: 15),
      );
      expect(
        ResendLadder.remaining(lastSentAt: null, sendCount: 0, now: sent),
        Duration.zero,
      );
      expect(ResendLadder.clock(const Duration(seconds: 30)), '0:30');
      expect(ResendLadder.clock(const Duration(seconds: 65)), '1:05');
    });

    test('other channels after the second resend; "newest code" after any', () {
      expect(ResendLadder.offersOtherChannels(2), isFalse);
      expect(ResendLadder.offersOtherChannels(3), isTrue);
      expect(ResendLadder.saysUseNewest(1), isFalse);
      expect(ResendLadder.saysUseNewest(2), isTrue);
    });

    test('a code lives 10 minutes', () {
      expect(
        ResendLadder.isExpired(
          lastSentAt: sent,
          now: sent.add(const Duration(minutes: 10)),
        ),
        isFalse,
      );
      expect(
        ResendLadder.isExpired(
          lastSentAt: sent,
          now: sent.add(const Duration(minutes: 11)),
        ),
        isTrue,
      );
    });
  });

  group('send and verify failures', () {
    test('the hook\'s and Auth\'s limits read as minutes to wait', () {
      final hook = classifyOtpSendError(
        const AuthException('otp:rate_limited:600', statusCode: '429'),
      );
      expect(hook.kind, OtpSendFailureKind.rateLimited);
      expect(hook.minutes, 10);
      final auth = classifyOtpSendError(
        const AuthException(
          'For security purposes, you can only request this after 27 seconds.',
          code: 'over_sms_send_rate_limit',
        ),
      );
      expect(auth.kind, OtpSendFailureKind.rateLimited);
      expect(auth.minutes, 1);
    });

    test('anything else is "couldn\'t send", or sign-in off', () {
      expect(
        classifyOtpSendError(const AuthException('otp:unavailable')).kind,
        OtpSendFailureKind.unavailable,
      );
      expect(
        classifyOtpSendError(TimeoutException('x')).kind,
        OtpSendFailureKind.unavailable,
      );
      expect(
        classifyOtpSendError(
          const AuthException('off', code: 'otp_disabled'),
        ).kind,
        OtpSendFailureKind.signInOff,
      );
    });

    test(
      'a refused code is wrong while fresh and expired after 10 minutes',
      () {
        final sent = DateTime.utc(2026, 10, 25, 12);
        const refusal = AuthException(
          'Token has expired or is invalid',
          code: 'otp_expired',
          statusCode: '403',
        );
        expect(
          classifyOtpVerifyError(
            refusal,
            lastSentAt: sent,
            now: sent.add(const Duration(minutes: 2)),
          ),
          OtpVerifyFailure.wrongCode,
        );
        expect(
          classifyOtpVerifyError(
            refusal,
            lastSentAt: sent,
            now: sent.add(const Duration(minutes: 11)),
          ),
          OtpVerifyFailure.expired,
        );
        expect(
          classifyOtpVerifyError(
            TimeoutException('x'),
            lastSentAt: sent,
            now: sent,
          ),
          OtpVerifyFailure.unavailable,
        );
      },
    );
  });
}
```

Create `test/features/auth/sign_up/sign_up_draft_store_test.dart` with exactly:

```dart
// Spec 1 W2b (§5.5): the device sign-up draft.
import 'dart:convert';
import 'dart:math';

import 'package:attune/features/auth/sign_up/data/sign_up_draft_store.dart';
import 'package:attune/features/auth/sign_up/domain/sign_up_draft.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime.utc(2026, 10, 25, 12);
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  test('a nonce is 16 random bytes, base64url, never repeated', () {
    final a = SignUpDraft.newNonce();
    final b = SignUpDraft.newNonce();
    expect(a, hasLength(22));
    expect(base64Url.decode('$a=='), hasLength(16));
    expect(a, isNot(b));
    expect(SignUpDraft.newNonce(Random(1)), SignUpDraft.newNonce(Random(1)));
  });

  test('the whole draft round-trips, the date of birth as a date', () async {
    final store = SignUpDraftStore(prefs, now: () => now);
    final draft = SignUpDraft.start(SignUpEntry.returning, now: now).copyWith(
      name: 'Ɛsi',
      birthDate: DateTime.utc(1996, 3, 27),
      phoneE164: '+233244123456',
      countryIso: 'GH',
      channel: 'whatsapp',
      lastSentAt: now,
      sendCount: 2,
    );
    await store.write(draft);
    final back = store.read()!;
    expect(back.entry, SignUpEntry.returning);
    expect(back.name, 'Ɛsi');
    expect(back.birthDate, DateTime.utc(1996, 3, 27));
    expect(back.phoneE164, '+233244123456');
    expect(back.channel, 'whatsapp');
    expect(back.sendCount, 2);
    expect(back.deviceNonce, draft.deviceNonce);
    expect(back.awaitingCode, isTrue);
    expect(
      jsonDecode(prefs.getString(SignUpDraftStore.key)!)['birth_date'],
      '1996-03-27',
    );
  });

  test('a draft older than 7 days, or a corrupt one, is gone', () async {
    await SignUpDraftStore(
      prefs,
      now: () => now,
    ).write(SignUpDraft.start(SignUpEntry.newAccount, now: now));
    expect(
      SignUpDraftStore(
        prefs,
        now: () => now.add(const Duration(days: 7)),
      ).read(),
      isNotNull,
    );
    expect(
      SignUpDraftStore(
        prefs,
        now: () => now.add(const Duration(days: 8)),
      ).read(),
      isNull,
    );
    expect(prefs.containsKey(SignUpDraftStore.key), isFalse);

    await prefs.setString(SignUpDraftStore.key, '{not json');
    expect(SignUpDraftStore(prefs, now: () => now).read(), isNull);
  });

  test(
    'verified means no longer awaiting a code; withoutCode restarts the ladder',
    () {
      final draft = SignUpDraft.start(
        SignUpEntry.newAccount,
        now: now,
      ).copyWith(phoneE164: '+447911123456', lastSentAt: now, sendCount: 3);
      expect(draft.copyWith(verifiedUserId: 'u1').awaitingCode, isFalse);
      final reset = draft.withoutCode();
      expect(reset.lastSentAt, isNull);
      expect(reset.sendCount, 0);
      expect(reset.phoneE164, '+447911123456');
      expect(draft.withoutCode(keepPhone: false).phoneE164, isNull);
      expect(reset.deviceNonce, draft.deviceNonce);
    },
  );

  test('the device key never names Dating (D20)', () {
    expect(SignUpDraftStore.key.contains('dating'), isFalse);
  });
}
```

- [ ] **Step 2: Run them to verify they fail**

```bash
cd /Users/user/attune
flutter test --no-pub test/features/auth/sign_up/sign_up_domain_test.dart test/features/auth/sign_up/sign_up_draft_store_test.dart 2>&1 | tr '\r' '\n' | grep -E "Error when reading" | head -2
```
Expected: `Error when reading 'lib/features/auth/sign_up/domain/birth_date_validator.dart'` (and the other new files).

- [ ] **Step 3: Add the W2b copy and regenerate**

In `lib/i10n/app_en.arb` (after Task 2's last key):

The edit. Replace exactly:

```json
  "flow_inviteCodeTitle": "Enter your invite code",
  "flow_inviteCodeLabel": "Invite code",
  "flow_inviteCodeError": "Codes have 6 letters and numbers. Check it with the person who sent it."
}
```

with:

```json
  "flow_inviteCodeTitle": "Enter your invite code",
  "flow_inviteCodeLabel": "Invite code",
  "flow_inviteCodeError": "Codes have 6 letters and numbers. Check it with the person who sent it.",

  "flow_tryAgain": "Try again",
  "flow_nameTitle": "What should we call you?",
  "flow_nameHint": "This is the name your partner sees. Opinions never shows it.",
  "flow_nameLabel": "Your name",
  "flow_nameNeedsLetter": "Add a name with at least one letter.",
  "flow_nameTooLong": "Use 40 characters or fewer.",
  "flow_dobTitle": "What's your date of birth?",
  "flow_dobHint": "We only ever show your age, never your birthday.",
  "flow_dobExample": "For example, {example}",
  "@flow_dobExample": {
    "placeholders": {
      "example": {"type": "String"}
    }
  },
  "flow_dobDay": "Day",
  "flow_dobMonth": "Month",
  "flow_dobYear": "Year",
  "flow_dobDaySemantics": "Day of birth",
  "flow_dobMonthSemantics": "Month of birth",
  "flow_dobYearSemantics": "Year of birth",
  "flow_dobDayRange": "Day must be between 1 and 31.",
  "flow_dobMonthRange": "Month must be between 1 and 12.",
  "flow_dobYearDigits": "Year must have 4 digits.",
  "flow_dobNoSuchDate": "That date doesn't exist. Check the day and month.",
  "flow_dobFuture": "That date is in the future.",
  "flow_dobCheckYear": "Check the year.",
  "flow_dobAge": "that makes you {age}.",
  "@flow_dobAge": {
    "placeholders": {
      "age": {"type": "int"}
    }
  },
  "flow_phoneTitle": "What's your phone number?",
  "flow_phoneHint": "We'll text you a code to sign in. We never show your number to anyone.",
  "flow_phoneLabel": "Phone number",
  "flow_phoneCountrySemantics": "Country, {country}, {code}",
  "@flow_phoneCountrySemantics": {
    "placeholders": {
      "country": {"type": "String"},
      "code": {"type": "String"}
    }
  },
  "flow_phoneChooseCountry": "Choose your country",
  "flow_phoneSend": "Text me a code",
  "flow_phoneTerms": "By continuing you agree to the Terms and Privacy Policy.",
  "flow_phoneTooShort": "Check the number. It looks too short.",
  "flow_phoneTooLong": "Check the number. It looks too long.",
  "flow_phoneWrongCountry": "That doesn't look like a {country} number. Check the country.",
  "@flow_phoneWrongCountry": {
    "placeholders": {
      "country": {"type": "String"}
    }
  },
  "flow_sending": "Sending your code…",
  "flow_sendFailed": "We couldn't send a code right now. Try WhatsApp or a call.",
  "flow_tooManyCodes": "{minutes, plural, =1{Too many codes. Try again in 1 minute.} other{Too many codes. Try again in {minutes} minutes.}}",
  "@flow_tooManyCodes": {
    "placeholders": {
      "minutes": {"type": "int"}
    }
  },
  "flow_phoneUnavailable": "Phone sign-in is unavailable right now. Please try again later.",
  "flow_codeTitle": "Enter the code",
  "flow_codeSubtitle": "We sent a 6-digit code to {number}.",
  "@flow_codeSubtitle": {
    "placeholders": {
      "number": {"type": "String"}
    }
  },
  "flow_codeChangeNumber": "Wrong number? Change it",
  "flow_codeResendIn": "Send a new code in {time}",
  "@flow_codeResendIn": {
    "placeholders": {
      "time": {"type": "String"}
    }
  },
  "flow_codeResend": "Send a new code",
  "flow_codeNewest": "Use the newest code.",
  "flow_codeSemantics": "Verification code, 6 digits",
  "flow_codeWrong": "That code didn't work. Check it and try again.",
  "flow_codeExpired": "That code has expired. Send a new one.",
  "flow_codeAccepted": "Code accepted",
  "flow_codeCheckFailed": "We couldn't check the code right now. Try again.",
  "flow_consentTitle": "Before you start",
  "flow_consentUpdatedTitle": "We've updated our terms",
  "flow_consentAdults": "Attune is for adults. Everyone here is 18 or older.",
  "flow_consentAi": "Some Attune features use AI to give you private suggestions. In a shared space they can read your chat with your partner, and only after you both agree. What it suggests to one of you is never shown to the other.",
  "flow_consentData": "You can download everything you've added, and delete your account, any time.",
  "flow_consentTermsLink": "Terms of use",
  "flow_consentPrivacyLink": "Privacy policy",
  "flow_consentAiLink": "More about AI in Attune",
  "flow_consentAgree": "Agree and continue",
  "flow_consentNotNow": "Not now",
  "flow_signupPhoneRequired": "Phone sign-in is unavailable right now.",
  "flow_saveFailed": "We couldn't save that. Try again.",
  "flow_noAccountTitle": "We couldn't find an Attune account for this number",
  "flow_noAccountBody": "You can create one now.",
  "flow_noAccountCreate": "Create an account",
  "flow_noAccountOtherNumber": "Use a different number",
  "flow_welcomeBack": "Welcome back, {name}.",
  "@flow_welcomeBack": {
    "placeholders": {
      "name": {"type": "String"}
    }
  },
  "flow_welcomeBackNoName": "Welcome back.",
  "flow_joinTitle": "Join Attune",
  "flow_joinBody": "A private space for couples, a few introductions a day for singles, and a journal just for you."
}
```

```bash
cd /Users/user/attune
flutter gen-l10n --arb-dir=lib/i10n --template-arb-file=app_en.arb --output-dir=lib/i10n/generated --output-localization-file=app_localizations.dart --no-synthetic-package > /dev/null
perl -0pi -e "s/\*\*'You\\\\'re browsing/**'You're browsing/" lib/i10n/generated/app_localizations.dart
git diff --numstat lib/i10n/generated | awk '{print $2}' | sort -u
grep -c "flow_" lib/i10n/generated/app_localizations_en.dart
```
Expected: `0` (nothing deleted); `119`.

- [ ] **Step 4: Write the name, date and phone rules**

Create `lib/features/auth/sign_up/domain/display_name_validator.dart` with exactly (the `\u…` escapes stay escapes; write them as typed here, not as characters):

```dart
/// A1's name rule (Spec 1 §3.3): invisible and direction characters
/// dropped and whitespace collapsed (as the server's
/// private.normalize_display_name does), then 1–40 characters with at least
/// one letter in any script. Today's ASCII-only rule is not used.
enum DisplayNameError { needsLetter, tooLong }

final _invisible = RegExp('[\u200B-\u200F\u202A-\u202E\u2060-\u2064\uFEFF]');
final _letter = RegExp(r'\p{L}', unicode: true);

String normalizeDisplayName(String raw) =>
    raw.replaceAll(_invisible, '').replaceAll(RegExp(r'\s+'), ' ').trim();

DisplayNameError? validateDisplayName(String raw) {
  final name = normalizeDisplayName(raw);
  if (!_letter.hasMatch(name)) return DisplayNameError.needsLetter;
  if (name.runes.length > 40) return DisplayNameError.tooLong;
  return null;
}
```

Create `lib/features/auth/sign_up/domain/birth_date_validator.dart` with exactly:

```dart
import 'dart:ui' show Locale;

import 'package:intl/date_time_patterns.dart';

/// A2's date-of-birth rules (Spec 1 §3.3).
enum BirthDateOrder { dayMonthYear, monthDayYear }

enum BirthDateError {
  dayRange,
  monthRange,
  yearDigits,
  noSuchDate,
  future,
  tooOld,
}

/// Regions that write the month first when intl has no pattern for the
/// exact locale (its table has no en_GH, en_NG or en_KE, and plain `en` is
/// the US order).
const _monthFirstRegions = {
  'US',
  'PR',
  'GU',
  'AS',
  'MP',
  'UM',
  'VI',
  'FM',
  'MH',
  'PW',
  'PH',
};

/// Day · Month · Year or Month · Day · Year, from the locale's
/// `DateFormat.yMd` pattern. A year-first pattern (y-MM-dd) reads day
/// first. Without an exact pattern: month first only for the regions that
/// write it so, day first everywhere else.
BirthDateOrder birthDateOrderFor(Locale locale) {
  final patterns = dateTimePatternMap();
  final region = locale.countryCode;
  final key =
      region == null || region.isEmpty
          ? locale.languageCode
          : '${locale.languageCode}_$region';
  final exact = patterns[key]?['yMd'];
  if (exact != null) {
    if (exact.startsWith('y')) return BirthDateOrder.dayMonthYear;
    return exact.indexOf('M') < exact.indexOf('d')
        ? BirthDateOrder.monthDayYear
        : BirthDateOrder.dayMonthYear;
  }
  return region != null && _monthFirstRegions.contains(region)
      ? BirthDateOrder.monthDayYear
      : BirthDateOrder.dayMonthYear;
}

/// Checks the three fields in the order the person reads the errors.
/// [todayUtc] is today's UTC date (spec: stricter at the day boundary).
({DateTime? date, BirthDateError? error}) validateBirthDate({
  required String day,
  required String month,
  required String year,
  required DateTime todayUtc,
}) {
  final d = int.tryParse(day.trim());
  final m = int.tryParse(month.trim());
  if (d == null || d < 1 || d > 31) {
    return (date: null, error: BirthDateError.dayRange);
  }
  if (m == null || m < 1 || m > 12) {
    return (date: null, error: BirthDateError.monthRange);
  }
  if (!RegExp(r'^[0-9]{4}$').hasMatch(year.trim())) {
    return (date: null, error: BirthDateError.yearDigits);
  }
  final y = int.parse(year.trim());
  final date = DateTime.utc(y, m, d);
  if (date.month != m || date.day != d) {
    return (date: null, error: BirthDateError.noSuchDate);
  }
  final today = DateTime.utc(todayUtc.year, todayUtc.month, todayUtc.day);
  if (date.isAfter(today)) return (date: null, error: BirthDateError.future);
  if (date.isBefore(DateTime.utc(today.year - 120, today.month, today.day))) {
    return (date: null, error: BirthDateError.tooOld);
  }
  return (date: date, error: null);
}

/// Whole years on [todayUtc], the server's rule (private.age_on_utc_today):
/// a 29 February birthday turns a year older on 1 March in other years.
int ageOn(DateTime birthDate, DateTime todayUtc) {
  var years = todayUtc.year - birthDate.year;
  final beforeBirthday =
      todayUtc.month < birthDate.month ||
      (todayUtc.month == birthDate.month && todayUtc.day < birthDate.day);
  if (beforeBirthday) years--;
  return years;
}

/// "27 3 1996" or "3 27 1996", for A2's example line.
String birthDateExample(BirthDateOrder order) =>
    order == BirthDateOrder.dayMonthYear ? '27 3 1996' : '3 27 1996';
```

Create `lib/features/auth/sign_up/domain/phone_entry.dart` with exactly:

```dart
import 'package:phone_numbers_parser/metadata.dart';
import 'package:phone_numbers_parser/phone_numbers_parser.dart';

/// A3's number rules (Spec 1 §3.3): parsed for the chosen country with
/// phone_numbers_parser; a leading national 0 is accepted and dropped; the
/// result is E.164.
enum PhoneEntryError { tooShort, tooLong, wrongCountry }

({String? e164, PhoneEntryError? error}) parsePhoneEntry(
  String input,
  String isoCode,
) {
  final iso = _iso(isoCode);
  final digits = input.replaceAll(RegExp(r'\D'), '');
  if (iso == null) return (e164: null, error: PhoneEntryError.wrongCountry);
  if (digits.length < 4) return (e164: null, error: PhoneEntryError.tooShort);

  final PhoneNumber parsed;
  try {
    parsed = PhoneNumber.parse(
      input,
      callerCountry: iso,
      destinationCountry: iso,
    );
  } on PhoneNumberException {
    return (e164: null, error: PhoneEntryError.wrongCountry);
  }
  final expectedCode = metadataByIsoCode[iso]!.countryCode;
  if (parsed.countryCode != expectedCode) {
    return (e164: null, error: PhoneEntryError.wrongCountry);
  }

  final lengths = metadataLenghtsByIsoCode[parsed.isoCode]!;
  final allowed = {...lengths.general, ...lengths.mobile, ...lengths.fixedLine};
  if (allowed.isNotEmpty) {
    final shortest = allowed.reduce((a, b) => a < b ? a : b);
    final longest = allowed.reduce((a, b) => a > b ? a : b);
    if (parsed.nsn.length < shortest) {
      return (e164: null, error: PhoneEntryError.tooShort);
    }
    if (parsed.nsn.length > longest) {
      return (e164: null, error: PhoneEntryError.tooLong);
    }
  }
  if (!parsed.isValid()) {
    return (e164: null, error: PhoneEntryError.wrongCountry);
  }
  return (e164: parsed.international, error: null);
}

/// "+233 24 412 3456", for A4's subtitle and the WhatsApp sheet.
String formatPhoneForDisplay(String e164) {
  try {
    final parsed = PhoneNumber.parse(e164);
    return '+${parsed.countryCode} ${parsed.formatNsn()}';
  } on PhoneNumberException {
    return e164;
  }
}

/// The ISO country of an E.164 number, or null.
String? countryOfPhone(String e164) {
  try {
    return PhoneNumber.parse(e164).isoCode.name;
  } on PhoneNumberException {
    return null;
  }
}

IsoCode? _iso(String code) {
  try {
    return IsoCode.values.byName(code.toUpperCase());
  } on ArgumentError {
    return null;
  }
}
```

Create `lib/features/auth/sign_up/domain/default_phone_country.dart` with exactly:

```dart
import 'package:attune/features/auth/log_in/domain/phone_country.dart';

/// A3's default country (Spec 1 §3.3): the Android SIM's country, else the
/// device region, else none (the picker opens). Never a hard-coded Ghana.
PhoneCountry? defaultPhoneCountry({
  String? simIso,
  String? regionIso,
  List<PhoneCountry>? countries,
}) {
  final all = countries ?? PhoneCountries.all;
  for (final candidate in [simIso, regionIso]) {
    if (candidate == null || candidate.trim().isEmpty) continue;
    final iso = candidate.trim().toUpperCase();
    for (final country in all) {
      if (country.isoCode == iso) return country;
    }
  }
  return null;
}
```

- [ ] **Step 5: Write the ladder and the failure classifiers**

Create `lib/features/auth/sign_up/domain/resend_ladder.dart` with exactly:

```dart
/// A4's resend ladder and code lifetime (Spec 1 §3.3, §4.5).
class ResendLadder {
  const ResendLadder._();

  /// A phone code is valid for 10 minutes (the Auth setting).
  static const codeLifetime = Duration(minutes: 10);

  /// "Send a new code" is available 30 s after the first send, 60 s after
  /// the second and 120 s after every later one.
  static Duration waitAfter(int sendCount) =>
      sendCount <= 1
          ? const Duration(seconds: 30)
          : sendCount == 2
          ? const Duration(seconds: 60)
          : const Duration(seconds: 120);

  static Duration remaining({
    required DateTime? lastSentAt,
    required int sendCount,
    required DateTime now,
  }) {
    if (lastSentAt == null) return Duration.zero;
    final left = lastSentAt.add(waitAfter(sendCount)).difference(now);
    return left.isNegative ? Duration.zero : left;
  }

  /// After the second resend (the third send) A4 also offers WhatsApp and a
  /// call.
  static bool offersOtherChannels(int sendCount) => sendCount >= 3;

  /// After any resend A4 says "Use the newest code." (D11).
  static bool saysUseNewest(int sendCount) => sendCount >= 2;

  static bool isExpired({
    required DateTime lastSentAt,
    required DateTime now,
  }) => now.difference(lastSentAt) > codeLifetime;

  /// "0:30", "1:05".
  static String clock(Duration left) {
    final seconds = left.inSeconds;
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }
}
```

Create `lib/features/auth/sign_up/domain/otp_failure.dart` with exactly:

```dart
import 'dart:async';

import 'package:attune/features/auth/sign_up/domain/resend_ladder.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Why a code wasn't sent, in the words A3/A4 show (Spec 1 §3.3). No
/// vendor is ever named.
enum OtpSendFailureKind {
  /// "Too many codes. Try again in {minutes} minutes."
  rateLimited,

  /// "We couldn't send a code right now. Try WhatsApp or a call."
  unavailable,

  /// "Phone sign-in is unavailable right now. Please try again later."
  signInOff,
}

class OtpSendFailure {
  const OtpSendFailure(this.kind, {this.minutes});

  final OtpSendFailureKind kind;

  /// Whole minutes to wait, at least 1, for [OtpSendFailureKind.rateLimited].
  final int? minutes;
}

final _hookRateLimited = RegExp(r'otp:rate_limited:(\d+)');
final _authWait = RegExp(r'after (\d+) seconds');

/// Classifies a failed `signInWithOtp`. The Send SMS Hook (W2c) answers
/// `otp:rate_limited:{seconds}` or `otp:unavailable`; Auth's own limits
/// answer with their error codes.
OtpSendFailure classifyOtpSendError(Object error) {
  if (error is AuthException) {
    final hook = _hookRateLimited.firstMatch(error.message);
    if (hook != null) {
      return OtpSendFailure(
        OtpSendFailureKind.rateLimited,
        minutes: _minutes(int.parse(hook.group(1)!)),
      );
    }
    if (error.message.contains('otp:unavailable')) {
      return const OtpSendFailure(OtpSendFailureKind.unavailable);
    }
    switch (error.code) {
      case 'over_sms_send_rate_limit':
      case 'over_request_rate_limit':
        final wait = _authWait.firstMatch(error.message);
        return OtpSendFailure(
          OtpSendFailureKind.rateLimited,
          minutes: _minutes(wait == null ? 60 : int.parse(wait.group(1)!)),
        );
      case 'otp_disabled':
      case 'phone_provider_disabled':
      case 'sms_send_failed' when error.message.contains('disabled'):
        return const OtpSendFailure(OtpSendFailureKind.signInOff);
    }
  }
  return const OtpSendFailure(OtpSendFailureKind.unavailable);
}

int _minutes(int seconds) => seconds <= 60 ? 1 : (seconds + 59) ~/ 60;

/// Why a code didn't verify (Spec 1 §3.3 A4).
enum OtpVerifyFailure {
  /// "That code didn't work. Check it and try again."
  wrongCode,

  /// "That code has expired. Send a new one."
  expired,

  /// "Too many codes…" with no minutes: Auth's verify limit.
  rateLimited,

  /// The network or the server: "We couldn't check the code right now."
  unavailable,
}

/// Auth answers `otp_expired` ("Token has expired or is invalid") for a
/// wrong code and an old one alike, so the age of the newest send decides.
OtpVerifyFailure classifyOtpVerifyError(
  Object error, {
  required DateTime? lastSentAt,
  required DateTime now,
}) {
  if (error is AuthException) {
    if (error.code == 'over_request_rate_limit') {
      return OtpVerifyFailure.rateLimited;
    }
    if (error.code == 'otp_expired' ||
        error.code == 'invalid_credentials' ||
        error.statusCode == '403') {
      final expired =
          lastSentAt != null &&
          ResendLadder.isExpired(lastSentAt: lastSentAt, now: now);
      return expired ? OtpVerifyFailure.expired : OtpVerifyFailure.wrongCode;
    }
  }
  if (error is TimeoutException) return OtpVerifyFailure.unavailable;
  return OtpVerifyFailure.unavailable;
}
```

- [ ] **Step 6: Write the draft and its store**

Create `lib/features/auth/sign_up/domain/sign_up_draft.dart` with exactly:

```dart
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

/// How someone entered `/signup` (Spec 1 §5.4).
enum SignUpEntry {
  newAccount('new'),
  returning('returning'),
  invite('invite');

  const SignUpEntry(this.wire);

  final String wire;

  static SignUpEntry fromWire(Object? value) {
    for (final entry in values) {
      if (entry.wire == value) return entry;
    }
    return newAccount;
  }
}

/// A1–A4 held on this phone (Spec 1 §3.3, §5.5): the name, date of birth,
/// number, channel and resend ladder, so closing the app resumes at A4, and
/// the random `device_nonce` sent only to `otp-delivery-intent`. The date of
/// birth never leaves the phone before `complete_sign_up`.
@immutable
class SignUpDraft {
  const SignUpDraft({
    required this.entry,
    required this.deviceNonce,
    required this.createdAt,
    this.name,
    this.birthDate,
    this.phoneE164,
    this.countryIso,
    this.channel = 'sms',
    this.lastSentAt,
    this.sendCount = 0,
    this.verifiedUserId,
  });

  /// A new draft with a fresh 16-byte nonce.
  factory SignUpDraft.start(
    SignUpEntry entry, {
    required DateTime now,
    Random? random,
  }) => SignUpDraft(
    entry: entry,
    deviceNonce: newNonce(random),
    createdAt: now.toUtc(),
  );

  /// 16 random bytes, base64url without padding (22 characters).
  static String newNonce([Random? random]) {
    final source = random ?? Random.secure();
    final bytes = List<int>.generate(16, (_) => source.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  final SignUpEntry entry;
  final String deviceNonce;
  final DateTime createdAt;
  final String? name;

  /// A UTC date (midnight).
  final DateTime? birthDate;
  final String? phoneE164;
  final String? countryIso;

  /// `sms`, `whatsapp` or `voice`: the channel the last code was asked on.
  final String channel;
  final DateTime? lastSentAt;
  final int sendCount;

  /// Set once A4 verified this account, until A5 completes or "Not now".
  final String? verifiedUserId;

  /// A code was sent and not yet verified: reopening resumes at A4.
  bool get awaitingCode => lastSentAt != null && verifiedUserId == null;

  SignUpDraft copyWith({
    SignUpEntry? entry,
    String? name,
    DateTime? birthDate,
    String? phoneE164,
    String? countryIso,
    String? channel,
    DateTime? lastSentAt,
    int? sendCount,
    String? verifiedUserId,
  }) => SignUpDraft(
    entry: entry ?? this.entry,
    deviceNonce: deviceNonce,
    createdAt: createdAt,
    name: name ?? this.name,
    birthDate: birthDate ?? this.birthDate,
    phoneE164: phoneE164 ?? this.phoneE164,
    countryIso: countryIso ?? this.countryIso,
    channel: channel ?? this.channel,
    lastSentAt: lastSentAt ?? this.lastSentAt,
    sendCount: sendCount ?? this.sendCount,
    verifiedUserId: verifiedUserId ?? this.verifiedUserId,
  );

  /// Back to A3 with no code in flight ("Wrong number? Change it", "Use a
  /// different number", "Not now"): the ladder restarts.
  SignUpDraft withoutCode({bool keepPhone = true}) => SignUpDraft(
    entry: entry,
    deviceNonce: deviceNonce,
    createdAt: createdAt,
    name: name,
    birthDate: birthDate,
    phoneE164: keepPhone ? phoneE164 : null,
    countryIso: countryIso,
  );

  Map<String, dynamic> toJson() => {
    'entry': entry.wire,
    'device_nonce': deviceNonce,
    'created_at': createdAt.toUtc().toIso8601String(),
    'name': name,
    'birth_date': birthDate == null ? null : _dateOnly(birthDate!),
    'phone': phoneE164,
    'country': countryIso,
    'channel': channel,
    'last_sent_at': lastSentAt?.toUtc().toIso8601String(),
    'send_count': sendCount,
    'verified_user_id': verifiedUserId,
  };

  /// Null when the payload isn't a draft (a corrupt one is dropped).
  static SignUpDraft? fromJson(Object? json) {
    if (json is! Map) return null;
    final nonce = json['device_nonce'];
    final created = DateTime.tryParse(json['created_at'] as String? ?? '');
    if (nonce is! String || nonce.isEmpty || created == null) return null;
    DateTime? at(Object? value) =>
        value is String ? DateTime.tryParse(value) : null;
    final birth = at(json['birth_date']);
    return SignUpDraft(
      entry: SignUpEntry.fromWire(json['entry']),
      deviceNonce: nonce,
      createdAt: created,
      name: json['name'] as String?,
      birthDate:
          birth == null
              ? null
              : DateTime.utc(birth.year, birth.month, birth.day),
      phoneE164: json['phone'] as String?,
      countryIso: json['country'] as String?,
      channel: json['channel'] as String? ?? 'sms',
      lastSentAt: at(json['last_sent_at']),
      sendCount: json['send_count'] is int ? json['send_count'] as int : 0,
      verifiedUserId: json['verified_user_id'] as String?,
    );
  }

  static String _dateOnly(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}
```

Create `lib/features/auth/sign_up/data/sign_up_draft_store.dart` with exactly:

```dart
import 'dart:convert';

import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/features/auth/sign_up/domain/sign_up_draft.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The sign-up draft on this phone, anonymous scope (Spec 1 §5.5):
/// `attune.flow.anonymous.signup_draft`. Kept until sign-up completes, for
/// 7 days, or until the under-18 stop deletes it (§4.8). Read
/// synchronously, so the router can resume a sign-up at launch.
class SignUpDraftStore {
  SignUpDraftStore(this._prefs, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final SharedPreferences _prefs;
  final DateTime Function() _now;

  static const key = 'attune.flow.anonymous.signup_draft';
  static const lifetime = Duration(days: 7);

  /// The draft, or null when there is none, it is corrupt or it is older
  /// than 7 days (then it is removed).
  SignUpDraft? read() => readFrom(_prefs, _now());

  static SignUpDraft? readFrom(SharedPreferences prefs, DateTime now) {
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return null;
    SignUpDraft? draft;
    try {
      draft = SignUpDraft.fromJson(jsonDecode(raw));
    } catch (_) {
      draft = null;
    }
    if (draft == null || now.difference(draft.createdAt) > lifetime) {
      prefs.remove(key);
      return null;
    }
    return draft;
  }

  Future<void> write(SignUpDraft draft) =>
      _prefs.setString(key, jsonEncode(draft.toJson()));

  Future<void> clear() => _prefs.remove(key);
}

final signUpDraftStoreProvider = Provider<SignUpDraftStore>(
  (ref) => SignUpDraftStore(ref.watch(sharedPreferencesProvider)),
);
```

- [ ] **Step 7: Run the tests to verify they pass, format, analyze**

```bash
cd /Users/user/attune
flutter test --no-pub test/features/auth/sign_up/sign_up_domain_test.dart test/features/auth/sign_up/sign_up_draft_store_test.dart 2>&1 | tr '\r' '\n' | grep -E "All tests passed|Some tests failed" | tail -1
dart format lib/features/auth/sign_up test/features/auth/sign_up
flutter analyze --no-pub lib/features/auth/sign_up test/features/auth/sign_up 2>&1 | grep -E "^\s*(error|warning) " | head
```
Expected: `All tests passed!` (22 tests: any-script names, the letter and length rules, invisible characters; locale order including en_GH/NG/CA; each date error in reading order, leap days, 120 years; ages on the UTC date including 29 February; national 0 dropped, too short/long/other country; SIM → region → none; the ladder 30/60/120 s, alternatives after the second resend, 10-minute codes; the hook's and Auth's limits as minutes; wrong vs expired; the draft round-trip, 7-day expiry, corrupt payload, `withoutCode`, a nonce of 16 bytes); `Formatted … (0 changed)`; no `error`/`warning` line.

---

### Task 6: The account calls, the queued A5, EULA v2, and today's onboarding after a v2 sign-up (W2b; §3.3 A5, §3.14, §3.15 A5c, D8, P-15, P-16)

**Files:**
- Create: `lib/features/auth/sign_up/data/account_service.dart`
- Modify: `lib/features/onboarding/data/onboarding_store.dart` (a `PendingSignUp` class; one key; four methods; one line in `reset`)
- Modify: `lib/features/onboarding/data/onboarding_sync_service.dart` (constructor; the replay before today's flush)
- Modify: `lib/features/auth/data/eula_acceptance_service.dart` (a `version`; numeric comparison; queued consent)
- Modify: `lib/features/auth/presentation/eula_gate.dart` (`versionFor`)
- Modify: `lib/features/onboarding/presentation/screens/onboarding_flow.dart` (`initState`: skip the name step when the name is known)
- Create: `test/helpers/fake_account_gateway.dart`, `test/features/auth/sign_up/sign_up_data_test.dart`

**Interfaces:**
- Consumes: W1's `complete_sign_up`, `get_my_home_state` (`HomeState.fromJson`), `record_eula_acceptance`; `AgeGateStore.block()` (Task 2); `signInFlowV2Provider` (Task 4).
- Produces: `abstract class AccountGateway {rpc(fn, {params}); displayName(userId)}`, `SupabaseAccountGateway`; `enum SignUpRefusal {notEligible, phoneRequired, invalid}`, `SignUpRefused(reason)`, `AccountOffline`; `AccountService(gateway)` with `eulaVersion = '2'`, `homeState()`, `completeSignUp({displayName, birthDate})`, `acceptUpdatedTerms()`, `storedDisplayName(userId)`, `static dateOnly(DateTime)`; `accountServiceProvider`; `PendingSignUp({displayName, birthDate})`; `OnboardingStore.pendingSignUp|savePendingSignUp|clearPendingSignUp|rememberDisplayName`; `OnboardingSyncService({submissionService, accountService, onSignUpNotEligible})`; `EulaAcceptanceService({client, version = currentVersion})` with `v2Version = '2'`, `static needsFor({stored, version})`; `EulaGate.versionFor(BuildContext)`. Test helper `FakeAccountGateway({homeState, name})` with `failWith`, `calls`, `count(fn)`, `static account({hasAccount, needs})`, `static refusal(message)`.

- [ ] **Step 1: Write the failing tests**

Create `test/helpers/fake_account_gateway.dart` with exactly:

```dart
// Spec 1 W2: a scripted AccountGateway for the sign-up tests.
import 'package:attune/features/auth/sign_up/data/account_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FakeAccountGateway implements AccountGateway {
  FakeAccountGateway({this.homeState, this.name});

  /// get_my_home_state's answer.
  Map<String, dynamic>? homeState;
  String? name;

  /// complete_sign_up / record_eula_acceptance throw this, if set.
  Object? failWith;

  final calls = <(String, Map<String, dynamic>?)>[];

  int count(String fn) => calls.where((c) => c.$1 == fn).length;

  @override
  Future<Object?> rpc(String fn, {Map<String, dynamic>? params}) async {
    calls.add((fn, params));
    if (fn == 'get_my_home_state') return homeState;
    if (failWith != null) throw failWith!;
    if (fn == 'complete_sign_up') return {'age': 30, 'created': true};
    return null;
  }

  @override
  Future<String?> displayName(String userId) async => name;

  static Map<String, dynamic> account({
    bool hasAccount = true,
    List<String> needs = const [],
  }) => {
    'has_account': hasAccount,
    'path': null,
    'tab': 'me',
    'path_previous': null,
    'needs': needs,
    'hold': false,
    'eula_version': hasAccount ? '2' : null,
    'dating': {'enabled': false, 'enrolled': false},
    'link': {'state': 'none'},
  };

  static PostgrestException refusal(String message) =>
      PostgrestException(message: message, code: 'P0001');
}
```

Create `test/features/auth/sign_up/sign_up_data_test.dart` with exactly:

```dart
// Spec 1 W2b (§3.3, §3.14): the sign-up RPCs, the queued A5 and its
// replay, EULA v2, and today's onboarding not asking the name twice.
import 'dart:async';

import 'package:attune/features/auth/data/eula_acceptance_service.dart';
import 'package:attune/features/auth/presentation/eula_gate.dart';
import 'package:attune/features/auth/sign_up/data/account_service.dart';
import 'package:attune/features/auth/sign_up/data/age_gate_store.dart';
import 'package:attune/features/auth/sign_up/presentation/sign_up_flags.dart';
import 'package:attune/features/onboarding/data/onboarding_store.dart';
import 'package:attune/features/onboarding/data/onboarding_submission_service.dart';
import 'package:attune/features/onboarding/data/onboarding_sync_service.dart';
import 'package:attune/features/onboarding/domain/home_state.dart';
import 'package:attune/features/onboarding/domain/onboarding_models.dart';
import 'package:attune/features/onboarding/presentation/screens/onboarding_flow.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../helpers/fake_account_gateway.dart';

class _NoSubmission implements OnboardingSubmissionService {
  int calls = 0;

  @override
  Future<void> submit({
    required OnboardingMode mode,
    required String displayName,
    required List<int> attachmentAnswers,
    required List<String> anchors,
  }) async => calls++;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences prefs;
  late OnboardingStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    store = OnboardingStore(prefs, scope: 'user.u1');
  });

  group('AccountService', () {
    test('complete_sign_up sends the name, the date and EULA 2', () async {
      final gateway = FakeAccountGateway();
      await AccountService(
        gateway,
      ).completeSignUp(displayName: 'Ɛsi', birthDate: DateTime.utc(1996, 3, 7));
      expect(gateway.calls.single.$1, 'complete_sign_up');
      expect(gateway.calls.single.$2, {
        'p_display_name': 'Ɛsi',
        'p_birth_date': '1996-03-07',
        'p_eula_version': '2',
      });
    });

    test('each refusal is told apart from a transient failure', () async {
      Future<Object?> outcome(Object failure) async {
        final gateway = FakeAccountGateway()..failWith = failure;
        try {
          await AccountService(
            gateway,
          ).completeSignUp(displayName: 'A', birthDate: DateTime.utc(1990));
          return null;
        } catch (error) {
          return error;
        }
      }

      expect(
        ((await outcome(FakeAccountGateway.refusal('signup:not_eligible')))
                as SignUpRefused)
            .reason,
        SignUpRefusal.notEligible,
      );
      expect(
        ((await outcome(FakeAccountGateway.refusal('signup:phone_required')))
                as SignUpRefused)
            .reason,
        SignUpRefusal.phoneRequired,
      );
      expect(
        ((await outcome(FakeAccountGateway.refusal('signup:invalid_name')))
                as SignUpRefused)
            .reason,
        SignUpRefusal.invalid,
      );
      expect(
        await outcome(FakeAccountGateway.refusal('upstream timeout')),
        isA<AccountOffline>(),
      );
      expect(await outcome(TimeoutException('slow')), isA<AccountOffline>());
    });

    test('the home state is read through the W1 model', () async {
      final gateway = FakeAccountGateway(
        homeState: FakeAccountGateway.account(needs: ['consent', 'path']),
      );
      final state = await AccountService(gateway).homeState();
      expect(state.hasAccount, isTrue);
      expect(state.needs, [HomeNeed.consent, HomeNeed.path]);
    });

    test('A5c records EULA 2', () async {
      final gateway = FakeAccountGateway();
      await AccountService(gateway).acceptUpdatedTerms();
      expect(gateway.calls.single.$1, 'record_eula_acceptance');
      expect(gateway.calls.single.$2, {'p_version': '2'});
    });
  });

  group('the queued A5', () {
    final pending = PendingSignUp(
      displayName: 'Ama',
      birthDate: DateTime.utc(1990, 1, 2),
    );

    test('round-trips in the account scope and is cleared by reset', () async {
      await store.savePendingSignUp(pending);
      expect(store.pendingSignUp!.displayName, 'Ama');
      expect(store.pendingSignUp!.birthDate, DateTime.utc(1990, 1, 2));
      expect(OnboardingStore(prefs, scope: 'user.other').pendingSignUp, isNull);
      await store.reset();
      expect(store.pendingSignUp, isNull);
    });

    test(
      'is replayed before today\'s onboarding submission, then cleared',
      () async {
        final gateway = FakeAccountGateway();
        final submission = _NoSubmission();
        await store.savePendingSignUp(pending);
        await OnboardingSyncService(
          submissionService: submission,
          accountService: AccountService(gateway),
        ).flush(store);
        expect(gateway.count('complete_sign_up'), 1);
        expect(store.pendingSignUp, isNull);
      },
    );

    test('offline it stays for the next launch', () async {
      final gateway =
          FakeAccountGateway()..failWith = TimeoutException('offline');
      await store.savePendingSignUp(pending);
      await OnboardingSyncService(
        submissionService: _NoSubmission(),
        accountService: AccountService(gateway),
      ).flush(store);
      expect(store.pendingSignUp, isNotNull);
    });

    test('an under-18 refusal drops it and runs the stop', () async {
      final gateway =
          FakeAccountGateway()
            ..failWith = FakeAccountGateway.refusal('signup:not_eligible');
      var stopped = 0;
      await store.savePendingSignUp(pending);
      await OnboardingSyncService(
        submissionService: _NoSubmission(),
        accountService: AccountService(gateway),
        onSignUpNotEligible: () async => stopped++,
      ).flush(store);
      expect(store.pendingSignUp, isNull);
      expect(stopped, 1);
      expect(
        AgeGateStore.readBlocked(prefs, DateTime.now()),
        isFalse,
        reason: 'the injected stop replaced the default',
      );
    });
  });

  group('EULA v2', () {
    test('asks only for a missing or older version, compared as numbers', () {
      expect(
        EulaAcceptanceService.needsFor(stored: null, version: '1'),
        isTrue,
      );
      expect(
        EulaAcceptanceService.needsFor(stored: '1', version: '1'),
        isFalse,
      );
      expect(
        EulaAcceptanceService.needsFor(stored: '2', version: '1'),
        isFalse,
        reason: 'never asks someone to step down',
      );
      expect(EulaAcceptanceService.needsFor(stored: '1', version: '2'), isTrue);
      expect(
        EulaAcceptanceService.needsFor(stored: 'v1', version: '1'),
        isTrue,
      );
      expect(EulaAcceptanceService().version, '1');
    });

    testWidgets('EulaGate asks for v2 under flow_signin_v2, v1 otherwise', (
      tester,
    ) async {
      late String on;
      late String off;
      late String bare;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [signInFlowV2Provider.overrideWithValue(true)],
          child: MaterialApp(
            home: Builder(
              builder: (context) {
                on = EulaGate.versionFor(context);
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [signInFlowV2Provider.overrideWithValue(false)],
          child: MaterialApp(
            home: Builder(
              builder: (context) {
                off = EulaGate.versionFor(context);
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              bare = EulaGate.versionFor(context);
              return const SizedBox();
            },
          ),
        ),
      );
      expect((on, off, bare), ('2', '1', '1'));
    });
  });

  group("today's onboarding after a v2 sign-up", () {
    Widget app(OnboardingStore store) => ProviderScope(
      child: ScreenUtilInit(
        designSize: const Size(375, 812),
        builder:
            (_, __) => MaterialApp(
              home: OnboardingFlow(store: store, onComplete: () {}),
            ),
      ),
    );

    testWidgets('skips the name step when A1 already took the name', (
      tester,
    ) async {
      await store.rememberDisplayName('عائشة');
      await tester.pumpWidget(app(store));
      await tester.pumpAndSettle();
      expect(find.text('What should Attune call you?'), findsNothing);
      expect(find.text('Are you single or in a relationship?'), findsOneWidget);
    });

    testWidgets('with no name stored it starts at the name step, as today', (
      tester,
    ) async {
      await tester.pumpWidget(app(store));
      await tester.pumpAndSettle();
      expect(find.text('What should Attune call you?'), findsOneWidget);
    });
  });
}
```

```bash
cd /Users/user/attune
flutter test --no-pub test/features/auth/sign_up/sign_up_data_test.dart 2>&1 | tr '\r' '\n' | grep -E "Error when reading|isn't defined" | head -2
```
Expected: `Error when reading 'lib/features/auth/sign_up/data/account_service.dart'`.

- [ ] **Step 2: Write the account service**

Create `lib/features/auth/sign_up/data/account_service.dart` with exactly:

```dart
import 'dart:async';
import 'dart:io';

import 'package:attune/features/onboarding/domain/home_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// The server calls behind sign-up (Spec 1 §3.3, §3.4, §4.3 W1b), so the
/// flow can be tested without a backend.
abstract class AccountGateway {
  Future<Object?> rpc(String fn, {Map<String, dynamic>? params});

  /// The account's own `users.display_name` (own-row SELECT), or null.
  Future<String?> displayName(String userId);
}

class SupabaseAccountGateway implements AccountGateway {
  SupabaseAccountGateway([SupabaseClient? client]) : _client = client;

  final SupabaseClient? _client;

  SupabaseClient get _db => _client ?? Supabase.instance.client;

  @override
  Future<Object?> rpc(String fn, {Map<String, dynamic>? params}) =>
      _db.rpc(fn, params: params);

  @override
  Future<String?> displayName(String userId) async {
    final row =
        await _db
            .from('users')
            .select('display_name')
            .eq('id', userId)
            .maybeSingle();
    return row?['display_name'] as String?;
  }
}

/// complete_sign_up's refusals (spec §3.3 A5).
enum SignUpRefusal {
  /// `signup:not_eligible`: under 18 on the server's UTC date. X1.
  notEligible,

  /// `signup:phone_required`: no verified phone on the Auth user.
  phoneRequired,

  /// Any other `signup:*` refusal: retrying can't help.
  invalid,
}

class SignUpRefused implements Exception {
  const SignUpRefused(this.reason);

  final SignUpRefusal reason;
}

/// The server couldn't be reached (or answered with a transient error):
/// the call can be queued and replayed.
class AccountOffline implements Exception {
  const AccountOffline();
}

class AccountService {
  AccountService(this._gateway);

  final AccountGateway _gateway;

  static const timeout = Duration(seconds: 15);

  /// The EULA version A5 and A5c record (spec §3.3, §3.15).
  static const eulaVersion = '2';

  Future<HomeState> homeState() async {
    final data = await _call('get_my_home_state');
    if (data is! Map) throw const AccountOffline();
    return HomeState.fromJson(Map<String, dynamic>.from(data));
  }

  /// A5: the account in one transaction, phone from Auth (D8). Idempotent,
  /// so a queued call can be replayed.
  Future<void> completeSignUp({
    required String displayName,
    required DateTime birthDate,
  }) async {
    await _call(
      'complete_sign_up',
      params: {
        'p_display_name': displayName,
        'p_birth_date': dateOnly(birthDate),
        'p_eula_version': eulaVersion,
      },
    );
  }

  /// A5c for an account that accepted an older EULA (spec §3.15).
  Future<void> acceptUpdatedTerms() async {
    await _call('record_eula_acceptance', params: {'p_version': eulaVersion});
  }

  /// For "Welcome back, {name}." Null when unreadable.
  Future<String?> storedDisplayName(String userId) async {
    try {
      return await _gateway.displayName(userId).timeout(timeout);
    } catch (_) {
      return null;
    }
  }

  Future<Object?> _call(String fn, {Map<String, dynamic>? params}) async {
    try {
      return await _gateway.rpc(fn, params: params).timeout(timeout);
    } on PostgrestException catch (error) {
      final message = error.message;
      if (message.startsWith('signup:not_eligible')) {
        throw const SignUpRefused(SignUpRefusal.notEligible);
      }
      if (message.startsWith('signup:phone_required')) {
        throw const SignUpRefused(SignUpRefusal.phoneRequired);
      }
      if (message.startsWith('signup:')) {
        throw const SignUpRefused(SignUpRefusal.invalid);
      }
      throw const AccountOffline();
    } on TimeoutException {
      throw const AccountOffline();
    } on SocketException {
      throw const AccountOffline();
    } on http.ClientException {
      throw const AccountOffline();
    }
  }

  static String dateOnly(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}

final accountServiceProvider = Provider<AccountService>(
  (ref) => AccountService(SupabaseAccountGateway()),
);
```

- [ ] **Step 3: Queue A5 in the account's onboarding store**

In `lib/features/onboarding/data/onboarding_store.dart` (add keys, rename none, §5.6 R4):

Edit 1 of 4. Replace exactly:

```dart
}

DateTime _systemNow() => DateTime.now();

```

with:

```dart
}

/// A5's complete_sign_up, queued when the phone was offline (Spec 1 §3.3,
/// §3.14) and replayed by OnboardingSyncService. The consent it carries is
/// already given; the date of birth leaves the phone only in the replay.
class PendingSignUp {
  const PendingSignUp({required this.displayName, required this.birthDate});

  final String displayName;

  /// A UTC date.
  final DateTime birthDate;

  Map<String, dynamic> toJson() => {
    'display_name': displayName,
    'birth_date': birthDate.toUtc().toIso8601String(),
  };

  static PendingSignUp? fromJson(Object? json) {
    if (json is! Map) return null;
    final name = json['display_name'];
    final date = DateTime.tryParse(json['birth_date'] as String? ?? '');
    if (name is! String || name.isEmpty || date == null) return null;
    return PendingSignUp(
      displayName: name,
      birthDate: DateTime.utc(date.year, date.month, date.day),
    );
  }
}

DateTime _systemNow() => DateTime.now();

```

Edit 2 of 4. Replace exactly:

```dart
  static const _displayNameKey = 'display_name';
  static const _pendingSubmissionKey = 'pending_submission';

  /// The legacy unscoped invite key: read once, moved to the anonymous slot,
```

with:

```dart
  static const _displayNameKey = 'display_name';
  static const _pendingSubmissionKey = 'pending_submission';
  static const _pendingSignUpKey = 'pending_sign_up';

  /// The legacy unscoped invite key: read once, moved to the anonymous slot,
```

Edit 3 of 4. Replace exactly:

```dart
    return _prefs.remove(_key(_pendingSubmissionKey));
  }

  OnboardingMode? get mode {
```

with:

```dart
    return _prefs.remove(_key(_pendingSubmissionKey));
  }

  /// Spec 1 W2b: A5's call, owed to the server (this account's scope).
  PendingSignUp? get pendingSignUp {
    final raw = _prefs.getString(_key(_pendingSignUpKey));
    if (raw == null || raw.isEmpty) return null;
    try {
      return PendingSignUp.fromJson(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  Future<void> savePendingSignUp(PendingSignUp pending) => _prefs.setString(
    _key(_pendingSignUpKey),
    jsonEncode(pending.toJson()),
  );

  Future<void> clearPendingSignUp() => _prefs.remove(_key(_pendingSignUpKey));

  /// Spec 1 W2b: the name A1 took (or the account already had), so today's
  /// onboarding doesn't ask for it again (see OnboardingFlow.initState).
  Future<void> rememberDisplayName(String name) =>
      _prefs.setString(_key(_displayNameKey), name);

  OnboardingMode? get mode {
```

Edit 4 of 4. Replace exactly:

```dart
    await _prefs.remove(_key(_displayNameKey));
    await _prefs.remove(_key(_pendingSubmissionKey));
    await _prefs.remove(_key(_pendingInviteKey));
    await _prefs.remove(pendingInviteCodeKey);
```

with:

```dart
    await _prefs.remove(_key(_displayNameKey));
    await _prefs.remove(_key(_pendingSubmissionKey));
    await _prefs.remove(_key(_pendingSignUpKey));
    await _prefs.remove(_key(_pendingInviteKey));
    await _prefs.remove(pendingInviteCodeKey);
```

- [ ] **Step 4: Replay it before today's onboarding submission**

In `lib/features/onboarding/data/onboarding_sync_service.dart` (today's flush body is unchanged; `HomeScreen` already calls `flush(store)` on launch, resume and sign-in):

Edit 1 of 3. Replace exactly:

```dart
import 'package:attune/features/onboarding/data/onboarding_store.dart';
import 'package:attune/features/onboarding/data/onboarding_submission_service.dart';
import 'package:flutter/foundation.dart';

/// Replays an onboarding submission that never reached the server.
```

with:

```dart
import 'package:attune/features/auth/sign_up/data/account_service.dart';
import 'package:attune/features/auth/sign_up/data/age_gate_store.dart';
import 'package:attune/features/onboarding/data/onboarding_store.dart';
import 'package:attune/features/onboarding/data/onboarding_submission_service.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Replays an onboarding submission that never reached the server.
```

Edit 2 of 3. Replace exactly:

```dart
/// so replaying it is safe even if part of the original attempt did land.
class OnboardingSyncService {
  OnboardingSyncService({OnboardingSubmissionService? submissionService})
    : _submissionService = submissionService ?? OnboardingSubmissionService();

  final OnboardingSubmissionService _submissionService;

  /// Flushes [store]'s pending submission, if any. Silent no-op when there is
  /// nothing owed. Failures are swallowed and the payload is KEPT, so the next
  /// launch tries again.
  Future<void> flush(OnboardingStore store) async {
    final pending = store.pendingSubmission;
    if (pending == null) return;
```

with:

```dart
/// so replaying it is safe even if part of the original attempt did land.
class OnboardingSyncService {
  OnboardingSyncService({
    OnboardingSubmissionService? submissionService,
    AccountService? accountService,
    Future<void> Function()? onSignUpNotEligible,
  }) : _submissionService = submissionService ?? OnboardingSubmissionService(),
       _accountService = accountService,
       _onSignUpNotEligible = onSignUpNotEligible ?? _blockAndSignOut;

  final OnboardingSubmissionService _submissionService;
  final AccountService? _accountService;
  final Future<void> Function() _onSignUpNotEligible;

  /// Flushes [store]'s pending submission, if any. Silent no-op when there is
  /// nothing owed. Failures are swallowed and the payload is KEPT, so the next
  /// launch tries again.
  Future<void> flush(OnboardingStore store) async {
    // Spec 1 W2b: the account itself first (A5 queued offline), so the
    // users row exists before today's onboarding writes land.
    await _flushSignUp(store);

    final pending = store.pendingSubmission;
    if (pending == null) return;
```

Edit 3 of 3. Replace exactly:

```dart
    }
  }
}
```

with:

```dart
    }
  }

  /// Replays A5's complete_sign_up (idempotent). A refusal can't succeed on
  /// a retry, so the payload goes; an under-18 refusal also blocks this
  /// phone and signs out, as X1's server variant does (spec §3.3 A5).
  /// Offline: kept for the next launch.
  Future<void> _flushSignUp(OnboardingStore store) async {
    final pending = store.pendingSignUp;
    if (pending == null) return;
    try {
      final accounts =
          _accountService ?? AccountService(SupabaseAccountGateway());
      await accounts.completeSignUp(
        displayName: pending.displayName,
        birthDate: pending.birthDate,
      );
      await store.clearPendingSignUp();
      debugPrint('[onboarding] pending sign-up synced');
    } on SignUpRefused catch (refused) {
      await store.clearPendingSignUp();
      debugPrint('[onboarding] pending sign-up refused: ${refused.reason.name}');
      if (refused.reason == SignUpRefusal.notEligible) {
        await _onSignUpNotEligible();
      }
    } catch (error) {
      debugPrint('[onboarding] pending sign-up kept: ${error.runtimeType}');
    }
  }

  static Future<void> _blockAndSignOut() async {
    try {
      await AgeGateStore(await SharedPreferences.getInstance()).block();
      await Supabase.instance.client.auth.signOut();
    } catch (error) {
      debugPrint('[onboarding] age refusal handling failed: ${error.runtimeType}');
    }
  }
}
```

- [ ] **Step 5: EULA v2 under the flag, never a step down, a queued A5 counts**

In `lib/features/auth/data/eula_acceptance_service.dart` (LoginScreen passes its own service, which keeps `currentVersion` `'1'`):

Edit 1 of 4. Replace exactly:

```dart
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

```

with:

```dart
import 'package:attune/features/onboarding/data/onboarding_store.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

```

Edit 2 of 4. Replace exactly:

```dart
/// or write their own acceptance.
class EulaAcceptanceService {
  EulaAcceptanceService({SupabaseClient? client}) : _client = client;

  final SupabaseClient? _client;

  static const timeout = Duration(seconds: 15);
```

with:

```dart
/// or write their own acceptance.
class EulaAcceptanceService {
  EulaAcceptanceService({SupabaseClient? client, this.version = currentVersion})
    : _client = client;

  final SupabaseClient? _client;

  /// The version this check asks for and records: [currentVersion] with
  /// flow_signin_v2 off, [v2Version] with it on (EulaGate picks).
  final String version;

  /// Spec 1 W2b (§3.3 A5, §5.2): the EULA v2 that A5 shows. Counsel
  /// approves its text before flow_signin_v2 is on in production.
  static const v2Version = '2';

  static const timeout = Duration(seconds: 15);
```

Edit 3 of 4. Replace exactly:

```dart
  Future<bool> needsAcceptance() async {
    final client = _safeClient;
    if (client == null || client.auth.currentUser == null) return true;

    try {
      final accepted = await client
          .rpc('get_eula_acceptance')
          .timeout(timeout);
      return accepted != currentVersion;
    } catch (error) {
      debugPrint('[eula] acceptance check failed: ${error.runtimeType}');
```

with:

```dart
  Future<bool> needsAcceptance() async {
    final client = _safeClient;
    final user = client?.auth.currentUser;
    if (client == null || user == null) return true;

    // Spec 1 W2b: A5's consent is queued for the server (PendingSignUp) —
    // given already, so today's onboarding never asks a second time.
    if (await _consentQueued(user.id)) return false;

    try {
      final accepted = await client
          .rpc('get_eula_acceptance')
          .timeout(timeout);
      return needsFor(stored: accepted, version: version);
    } catch (error) {
      debugPrint('[eula] acceptance check failed: ${error.runtimeType}');
```

Edit 4 of 4. Replace exactly:

```dart

    await client
        .rpc('record_eula_acceptance', params: {'p_version': currentVersion})
        .timeout(timeout);
  }
}
```

with:

```dart

    await client
        .rpc('record_eula_acceptance', params: {'p_version': version})
        .timeout(timeout);
  }

  /// A stored version at or above [version] needs nothing, compared as
  /// numbers: an account that accepted v2 is never asked to step down to v1.
  /// No version, or one that isn't a number, asks.
  static bool needsFor({required Object? stored, required String version}) {
    final accepted = int.tryParse('${stored ?? ''}');
    final wanted = int.tryParse(version) ?? 0;
    return accepted == null || accepted < wanted;
  }

  static Future<bool> _consentQueued(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return OnboardingStore(
            prefs,
            scope: '${OnboardingStore.userScopePrefix}.$userId',
          ).pendingSignUp !=
          null;
    } catch (_) {
      return false;
    }
  }
}
```

In `lib/features/auth/presentation/eula_gate.dart`:

Edit 1 of 3. Replace exactly:

```dart
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/auth/data/eula_acceptance_service.dart';

/// The outcome of a consent check.
```

with:

```dart
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/auth/data/eula_acceptance_service.dart';
import 'package:attune/features/auth/sign_up/presentation/sign_up_flags.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The outcome of a consent check.
```

Edit 2 of 3. Replace exactly:

```dart
  const EulaGate._();

  /// Returns [EulaOutcome.accepted] when the user may proceed — either they
  /// had already accepted the current version, or they accepted it just now.
```

with:

```dart
  const EulaGate._();

  /// Spec 1 W2b (§5.2): EULA v2 under flow_signin_v2, v1 otherwise.
  static String versionFor(BuildContext context) {
    try {
      final container = ProviderScope.containerOf(context, listen: false);
      return container.read(signInFlowV2Provider)
          ? EulaAcceptanceService.v2Version
          : EulaAcceptanceService.currentVersion;
    } catch (_) {
      return EulaAcceptanceService.currentVersion;
    }
  }

  /// Returns [EulaOutcome.accepted] when the user may proceed — either they
  /// had already accepted the current version, or they accepted it just now.
```

Edit 3 of 3. Replace exactly:

```dart
    EulaAcceptanceService? service,
  }) async {
    final eulaService = service ?? EulaAcceptanceService();

    if (!await eulaService.needsAcceptance()) return EulaOutcome.accepted;
```

with:

```dart
    EulaAcceptanceService? service,
  }) async {
    final eulaService =
        service ?? EulaAcceptanceService(version: versionFor(context));

    if (!await eulaService.needsAcceptance()) return EulaOutcome.accepted;
```

- [ ] **Step 6: Today's onboarding doesn't ask the name again**

In `lib/features/onboarding/presentation/screens/onboarding_flow.dart` (with no name stored — every flag-off arrival — it starts at the name step exactly as today):

The edit. Replace exactly:

```dart
    if (widget.acceptedPendingInvite) {
      _mode = OnboardingMode.couples;
    }
  }
```

with:

```dart
    if (widget.acceptedPendingInvite) {
      _mode = OnboardingMode.couples;
    }
    // Spec 1 W2b: a v2 sign-up already took the name (any script, A1), so
    // the name step is skipped; its ASCII-only rule would refuse many
    // names A1 accepts. Only a v2 sign-up writes this before onboarding.
    final knownName = widget.store.displayName;
    if (knownName != null && knownName.trim().isNotEmpty) {
      _nameController.text = knownName;
      _step = widget.acceptedPendingInvite ? _anchorsStep + 1 : _modeStep;
    }
  }
```

- [ ] **Step 7: Run the tests to verify they pass**

```bash
cd /Users/user/attune
flutter test --no-pub test/features/auth/sign_up/sign_up_data_test.dart test/features/onboarding test/onboarding_flow_test.dart test/login_profile_test.dart 2>&1 | tr '\r' '\n' | grep -E "All tests passed|Some tests failed" | tail -1
dart format lib/features/auth/sign_up/data/account_service.dart test/helpers/fake_account_gateway.dart test/features/auth/sign_up/sign_up_data_test.dart
flutter analyze --no-pub lib/features/auth lib/features/onboarding test/features/auth test/helpers 2>&1 | grep -E "^\s*(error|warning) " | grep -v "login_screen_options\|ask2_flow\|intelligence_intro_step\|invite_card" | head
```
Expected: `All tests passed!` (including today's `onboarding_pending_sync_test.dart` and `onboarding_flow_test.dart`, unchanged); `Formatted 3 files (0 changed)`; no new `error`/`warning` line (the four filtered files carry older warnings).

---

### Task 7: The SIM country, the code field and the step screens (W2b; §3.3 A1–A5, N1, §2.3, P-19, P-21)

**Files:**
- Create: `lib/core/platform/sim_country.dart`
- Modify: `android/app/src/main/kotlin/com/barsopus/attune/MainActivity.kt` (two imports; one channel)
- Create: `lib/features/auth/sign_up/presentation/widgets/one_time_code_field.dart`
- Create: `lib/features/auth/sign_up/presentation/steps/name_step.dart`, `birth_date_step.dart`, `phone_step.dart`, `code_step.dart`, `consent_step.dart`, `no_account_step.dart`
- Create: `test/core/platform/sim_country_test.dart`, `test/features/auth/sign_up/one_time_code_field_test.dart`, `test/features/auth/sign_up/w2b_goldens_test.dart` (+ goldens)

**Interfaces:**
- Consumes: Tasks 2 and 5; `PhoneCountryPickerSheet`, `BottomSheetUtils`, `MyDateFormat.toDate|join`, `AboutAttuneDocs`, `DocumentationTabView`, `LegalDocumentationData`.
- Produces: `SimCountry.channel` (`attune/device`), `SimCountry.read({TargetPlatform? platform}) → Future<String?>`; `typedef DeviceCountries = ({String? sim, String? region})`, `deviceCountryProvider`; `OneTimeCodeField({required controller, required semanticsLabel, required onCompleted, focusNode, enabled, errorText, errorCount, accepted, autofocus})`; `NameStep({onSubmit, onBack, initialName})`; `BirthDateStep({order, todayUtc, onSubmit, onBack, initialDate, initialYear})`; `PhoneStep({initialCountry, onSend(e164, iso), onBack, initialNational, busy, sendError})`; `CodeStep({phoneE164, lastSentAt, sendCount, now, onCode, onResend, onChangeNumber, errorText, errorCount, accepted, busy, onRetry})`; `ConsentStep({onAgree, onNotNow, updatedTerms, busy, errorText})`; `NoAccountStep({onCreate, onOtherNumber})`; `WelcomeBackStep({firstName})`.

- [ ] **Step 1: Write the failing tests**

Create `test/core/platform/sim_country_test.dart` with exactly:

```dart
// Spec 1 W2b (§3.3 A3): the SIM country channel.
import 'dart:io';

import 'package:attune/core/platform/sim_country.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(SimCountry.channel, null));

  test('Android: the SIM country, upper case', () async {
    messenger.setMockMethodCallHandler(SimCountry.channel, (call) async {
      expect(call.method, 'simCountryIso');
      return 'gh';
    });
    expect(await SimCountry.read(platform: TargetPlatform.android), 'GH');
  });

  test('no SIM, a junk answer or a missing channel reads as none', () async {
    messenger.setMockMethodCallHandler(SimCountry.channel, (_) async => '');
    expect(await SimCountry.read(platform: TargetPlatform.android), isNull);
    messenger.setMockMethodCallHandler(
      SimCountry.channel,
      (_) async => 'ghana',
    );
    expect(await SimCountry.read(platform: TargetPlatform.android), isNull);
    messenger.setMockMethodCallHandler(
      SimCountry.channel,
      (_) async => throw PlatformException(code: 'x'),
    );
    expect(await SimCountry.read(platform: TargetPlatform.android), isNull);
  });

  test('iOS never asks', () async {
    var asked = false;
    messenger.setMockMethodCallHandler(SimCountry.channel, (_) async {
      asked = true;
      return 'GB';
    });
    expect(await SimCountry.read(platform: TargetPlatform.iOS), isNull);
    expect(asked, isFalse);
  });

  test('MainActivity answers simCountryIso on attune/device', () {
    final kotlin =
        File(
          'android/app/src/main/kotlin/com/barsopus/attune/MainActivity.kt',
        ).readAsStringSync();
    expect(kotlin, contains('"attune/device"'));
    expect(kotlin, contains('"simCountryIso"'));
    expect(kotlin, contains('simCountryIso'));
    expect(kotlin, isNot(contains('READ_PHONE_STATE')));
  });
}
```

Create `test/features/auth/sign_up/one_time_code_field_test.dart` with exactly:

```dart
// Spec 1 W2b (§3.3 A4): one field, six boxes, autofill, digits only.
import 'package:attune/features/auth/sign_up/presentation/widgets/one_time_code_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(
  TextEditingController controller,
  List<String> completed, {
  String? error,
  int errorCount = 0,
  bool reduceMotion = false,
}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: reduceMotion),
    child: Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: OneTimeCodeField(
          controller: controller,
          semanticsLabel: 'Verification code, 6 digits',
          onCompleted: completed.add,
          errorText: error,
          errorCount: errorCount,
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('one text field, labelled, asking for a one-time code', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_host(TextEditingController(), []));
    expect(find.byType(TextField), findsOneWidget);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.autofillHints, [AutofillHints.oneTimeCode]);
    expect(field.keyboardType, TextInputType.number);
    expect(
      find.bySemanticsLabel('Verification code, 6 digits'),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets(
    'a pasted or autofilled code fills all six boxes and completes once',
    (tester) async {
      final controller = TextEditingController();
      final completed = <String>[];
      await tester.pumpWidget(_host(controller, completed));
      await tester.enterText(find.byType(TextField), '12a34 5678');
      await tester.pump();
      expect(controller.text, '123456', reason: 'digits only, six at most');
      expect(completed, ['123456']);
      for (final digit in ['1', '2', '3', '4', '5', '6']) {
        expect(find.text(digit), findsOneWidget);
      }
      controller.text = '123456';
      await tester.pump();
      expect(completed, ['123456'], reason: 'the same code is not sent twice');
    },
  );

  testWidgets(
    'a wrong code shakes twice and is announced; reduce motion keeps still',
    (tester) async {
      final controller = TextEditingController(text: '111111');
      await tester.pumpWidget(_host(controller, []));
      await tester.pumpWidget(
        _host(
          controller,
          [],
          error: "That code didn't work. Check it and try again.",
          errorCount: 1,
        ),
      );
      await tester.pump(const Duration(milliseconds: 60));
      final moving = tester.widget<Transform>(
        find
            .ancestor(
              of: find.byType(Stack).first,
              matching: find.byType(Transform),
            )
            .first,
      );
      expect(moving.transform.getTranslation().x, isNot(0));
      await tester.pumpAndSettle();
      expect(
        find.text("That code didn't work. Check it and try again."),
        findsOneWidget,
      );

      await tester.pumpWidget(_host(controller, [], reduceMotion: true));
      await tester.pumpWidget(
        _host(controller, [], error: 'x', errorCount: 2, reduceMotion: true),
      );
      await tester.pump(const Duration(milliseconds: 60));
      expect(tester.binding.transientCallbackCount, 0);
    },
  );
}
```

Create `test/features/auth/sign_up/w2b_goldens_test.dart` with exactly:

```dart
// Spec 1 §2.3 (W2b): every sign-up step at text sizes 1.0, 1.3 and 2.0 and
// once right to left. Look at the images when they change.
//   flutter test --update-goldens test/features/auth/sign_up/w2b_goldens_test.dart
import 'package:attune/features/auth/log_in/domain/phone_country.dart';
import 'package:attune/features/auth/sign_up/domain/birth_date_validator.dart';
import 'package:attune/features/auth/sign_up/presentation/steps/birth_date_step.dart';
import 'package:attune/features/auth/sign_up/presentation/steps/code_step.dart';
import 'package:attune/features/auth/sign_up/presentation/steps/consent_step.dart';
import 'package:attune/features/auth/sign_up/presentation/steps/name_step.dart';
import 'package:attune/features/auth/sign_up/presentation/steps/no_account_step.dart';
import 'package:attune/features/auth/sign_up/presentation/steps/phone_step.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/flow_harness.dart';

final _now = DateTime.utc(2026, 10, 25, 12);
final _ghana = PhoneCountries.all.firstWhere((c) => c.isoCode == 'GH');

void main() {
  testWidgets('A1 name', (tester) async {
    await expectFlowGoldens(
      tester,
      'step_name',
      () => NameStep(initialName: 'Ɛsi', onSubmit: (_) {}, onBack: () {}),
    );
  });

  testWidgets('A2 date of birth, confirmed', (tester) async {
    await expectFlowGoldens(
      tester,
      'step_birth_date',
      () => BirthDateStep(
        order: BirthDateOrder.dayMonthYear,
        todayUtc: _now,
        initialDate: DateTime.utc(1991, 11, 8),
        onSubmit: (_) {},
        onBack: () {},
      ),
    );
  });

  testWidgets('A3 phone, with a send error', (tester) async {
    await expectFlowGoldens(
      tester,
      'step_phone',
      () => PhoneStep(
        initialCountry: _ghana,
        initialNational: '244123456',
        sendError: "We couldn't send a code right now. Try WhatsApp or a call.",
        onSend: (_, __) {},
        onBack: () {},
      ),
    );
  });

  testWidgets('A4 code, after a resend, with a wrong code', (tester) async {
    await expectFlowGoldens(
      tester,
      'step_code',
      () => CodeStep(
        phoneE164: '+233244123456',
        lastSentAt: _now,
        sendCount: 2,
        now: () => _now,
        errorText: "That code didn't work. Check it and try again.",
        errorCount: 1,
        onCode: (_) {},
        onResend: () {},
        onChangeNumber: () {},
      ),
    );
  });

  testWidgets('A5 consent', (tester) async {
    await expectFlowGoldens(
      tester,
      'step_consent',
      () => ConsentStep(onAgree: () {}, onNotNow: () {}),
    );
  });

  testWidgets('A5c updated terms', (tester) async {
    await expectFlowGoldens(
      tester,
      'step_consent_updated',
      () => ConsentStep(updatedTerms: true, onAgree: () {}, onNotNow: () {}),
    );
  });

  testWidgets('N1 no account', (tester) async {
    await expectFlowGoldens(
      tester,
      'step_no_account',
      () => NoAccountStep(onCreate: () {}, onOtherNumber: () {}),
    );
  });
}
```

```bash
cd /Users/user/attune
flutter test --no-pub test/core/platform/sim_country_test.dart test/features/auth/sign_up/one_time_code_field_test.dart 2>&1 | tr '\r' '\n' | grep -E "Error when reading" | head -2
```
Expected: `Error when reading 'lib/core/platform/sim_country.dart'` and `…one_time_code_field.dart`.

- [ ] **Step 2: The SIM country, Dart and Android**

Create `lib/core/platform/sim_country.dart` with exactly:

```dart
import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The SIM card's country (Spec 1 §3.3 A3, W2b): Android's
/// `TelephonyManager.getSimCountryIso` through MainActivity's
/// `attune/device` channel. No permission, nothing stored or sent. iOS has
/// no equivalent and answers null.
class SimCountry {
  const SimCountry._();

  static const channel = MethodChannel('attune/device');

  /// Upper-case ISO 3166-1 alpha-2, or null.
  static Future<String?> read({TargetPlatform? platform}) async {
    if ((platform ?? defaultTargetPlatform) != TargetPlatform.android) {
      return null;
    }
    try {
      final iso = await channel
          .invokeMethod<String>('simCountryIso')
          .timeout(const Duration(seconds: 1));
      if (iso == null || !RegExp(r'^[A-Za-z]{2}$').hasMatch(iso)) return null;
      return iso.toUpperCase();
    } catch (_) {
      return null;
    }
  }
}

/// The SIM's and the device region's countries, for A3's default.
typedef DeviceCountries = ({String? sim, String? region});

final deviceCountryProvider = FutureProvider<DeviceCountries>((ref) async {
  final region = PlatformDispatcher.instance.locale.countryCode;
  return (
    sim: await SimCountry.read(),
    region: region == null || region.isEmpty ? null : region.toUpperCase(),
  );
});
```

In `android/app/src/main/kotlin/com/barsopus/attune/MainActivity.kt` (the screenshot and quick-exit channels are unchanged):

Edit 1 of 3. Replace exactly:

```kotlin
package com.barsopus.attune

import android.content.Intent
import android.database.ContentObserver
```

with:

```kotlin
package com.barsopus.attune

import android.content.Context
import android.content.Intent
import android.database.ContentObserver
```

Edit 2 of 3. Replace exactly:

```kotlin
import android.os.Looper
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
```

with:

```kotlin
import android.os.Looper
import android.provider.MediaStore
import android.telephony.TelephonyManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
```

Edit 3 of 3. Replace exactly:

```kotlin
        }

        // Quick exit (Spec 2; research 06 §3 F3 (2)): leave AND drop the
        // task, so Attune is not left in Recents. The only method on this
```

with:

```kotlin
        }

        // Spec 1 W2b (§3.3 A3): the SIM's country, for the phone step's
        // default. Needs no permission; nothing is stored or sent.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "attune/device")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "simCountryIso" -> {
                        val telephony =
                            getSystemService(Context.TELEPHONY_SERVICE) as? TelephonyManager
                        val iso = telephony?.simCountryIso
                        result.success(
                            if (iso != null && iso.length == 2) iso.uppercase() else null,
                        )
                    }
                    else -> result.notImplemented()
                }
            }

        // Quick exit (Spec 2; research 06 §3 F3 (2)): leave AND drop the
        // task, so Attune is not left in Recents. The only method on this
```

- [ ] **Step 3: The one-field code input**

Create `lib/features/auth/sign_up/presentation/widgets/one_time_code_field.dart` with exactly:

```dart
import 'dart:math' as math;

import 'package:attune/core/ui/motion/motion_tokens.dart';
import 'package:attune/core/ui/motion/reduce_motion.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

/// A4's code field (Spec 1 §3.3): ONE text field, drawn as six boxes, so
/// the system's one-time-code autofill (AutofillHints.oneTimeCode, and the
/// Android SMS listener in W2c) fills it in one go. Digits only, at most six;
/// [onCompleted] fires once per complete code. A wrong code shakes the boxes
/// twice when motion is allowed; an accepted one shows a check that fades
/// in over 150 ms.
class OneTimeCodeField extends StatefulWidget {
  const OneTimeCodeField({
    super.key,
    required this.controller,
    required this.semanticsLabel,
    required this.onCompleted,
    this.focusNode,
    this.enabled = true,
    this.errorText,
    this.errorCount = 0,
    this.accepted = false,
    this.autofocus = true,
  });

  static const length = 6;

  final TextEditingController controller;

  /// "Verification code, 6 digits".
  final String semanticsLabel;
  final ValueChanged<String> onCompleted;
  final FocusNode? focusNode;
  final bool enabled;
  final String? errorText;

  /// Bump to shake again for a new wrong code.
  final int errorCount;
  final bool accepted;
  final bool autofocus;

  @override
  State<OneTimeCodeField> createState() => _OneTimeCodeFieldState();
}

class _OneTimeCodeFieldState extends State<OneTimeCodeField>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
  );
  String? _lastCompleted;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
  }

  @override
  void didUpdateWidget(covariant OneTimeCodeField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
    }
    if (widget.errorCount != oldWidget.errorCount && widget.errorText != null) {
      SemanticsService.announce(widget.errorText!, Directionality.of(context));
      _lastCompleted = null;
      if (!reduceMotionOf(context)) _shake.forward(from: 0);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _shake.dispose();
    super.dispose();
  }

  void _changed() {
    final code = widget.controller.text;
    setState(() {});
    if (code.length == OneTimeCodeField.length && code != _lastCompleted) {
      _lastCompleted = code;
      widget.onCompleted(code);
    } else if (code.length < OneTimeCodeField.length) {
      _lastCompleted = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final code = widget.controller.text;
    final hasError = widget.errorText != null;
    final boxHeight =
        52 * MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0);

    Widget box(int index) {
      final filled = index < code.length;
      final active = index == code.length && widget.enabled;
      final color =
          hasError
              ? colorScheme.error
              : active
              ? flowAccent(context)
              : colorScheme.outline;
      return Expanded(
        child: Container(
          height: boxHeight,
          margin: const EdgeInsetsDirectional.symmetric(horizontal: 4),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color, width: active || hasError ? 2 : 1),
          ),
          child: Text(
            filled ? code[index] : '',
            style: theme.textTheme.headlineSmall?.copyWith(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AnimatedBuilder(
          animation: _shake,
          builder: (context, child) {
            final t = _shake.value;
            final dx = math.sin(t * math.pi * 4) * 8 * (1 - t);
            return Transform.translate(offset: Offset(dx, 0), child: child);
          },
          child: Stack(
            children: [
              ExcludeSemantics(
                child: Directionality(
                  // Digits read left to right in every language.
                  textDirection: TextDirection.ltr,
                  child: Row(
                    children: [
                      for (var i = 0; i < OneTimeCodeField.length; i++) box(i),
                    ],
                  ),
                ),
              ),
              Positioned.fill(
                child: Semantics(
                  label: widget.semanticsLabel,
                  child: TextField(
                    controller: widget.controller,
                    focusNode: widget.focusNode,
                    enabled: widget.enabled,
                    autofocus: widget.autofocus,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.done,
                    autofillHints: const [AutofillHints.oneTimeCode],
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(OneTimeCodeField.length),
                    ],
                    showCursor: false,
                    enableInteractiveSelection: false,
                    style: const TextStyle(color: Colors.transparent),
                    // The boxes behind are the field's look: the theme's
                    // borders and fill must not draw over them.
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                      errorBorder: InputBorder.none,
                      focusedErrorBorder: InputBorder.none,
                      filled: false,
                      isCollapsed: true,
                      counterText: '',
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        AnimatedOpacity(
          opacity: widget.accepted ? 1 : 0,
          duration: kSelectionDuration,
          child: Icon(Icons.check_circle, color: flowAccent(context), size: 32),
        ),
        if (hasError)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.error_outline, size: 18, color: colorScheme.error),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  widget.errorText!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }
}
```

- [ ] **Step 4: A1 and A2**

Create `lib/features/auth/sign_up/presentation/steps/name_step.dart` with exactly:

```dart
import 'package:attune/features/auth/sign_up/domain/display_name_validator.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_frame.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_text_field.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';

/// A1 · Your name (Spec 1 §3.3).
class NameStep extends StatefulWidget {
  const NameStep({
    super.key,
    required this.onSubmit,
    required this.onBack,
    this.initialName,
  });

  final String? initialName;
  final ValueChanged<String> onSubmit;
  final VoidCallback onBack;

  @override
  State<NameStep> createState() => _NameStepState();
}

class _NameStepState extends State<NameStep> {
  late final _name = TextEditingController(text: widget.initialName ?? '');
  DisplayNameError? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _continue() {
    final error = validateDisplayName(_name.text);
    setState(() => _error = error);
    if (error == null) widget.onSubmit(normalizeDisplayName(_name.text));
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return FlowFrame(
      title: loc.flow_nameTitle,
      hint: loc.flow_nameHint,
      onBack: widget.onBack,
      body: FlowTextField(
        controller: _name,
        label: loc.flow_nameLabel,
        errorText: switch (_error) {
          DisplayNameError.needsLetter => loc.flow_nameNeedsLetter,
          DisplayNameError.tooLong => loc.flow_nameTooLong,
          null => null,
        },
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        autofillHints: const [AutofillHints.givenName],
        onSubmitted: (_) => _continue(),
      ),
      actions: [
        FlowPrimaryButton(label: loc.flow_continue, onPressed: _continue),
      ],
    );
  }
}
```

Create `lib/features/auth/sign_up/presentation/steps/birth_date_step.dart` with exactly:

```dart
import 'package:attune/core/utils/date_formatter.dart';
import 'package:attune/features/auth/sign_up/domain/birth_date_validator.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_frame.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_text_field.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

/// A2 · Date of birth (Spec 1 §3.3): three labelled numeric fields in the
/// locale's order, no defaults (the year only from G1). Checked on the
/// phone; the date leaves it only with complete_sign_up.
class BirthDateStep extends StatefulWidget {
  const BirthDateStep({
    super.key,
    required this.order,
    required this.todayUtc,
    required this.onSubmit,
    required this.onBack,
    this.initialDate,
    this.initialYear,
  });

  final BirthDateOrder order;
  final DateTime todayUtc;
  final DateTime? initialDate;

  /// G1's year, when the guest gate was passed on this phone.
  final int? initialYear;
  final ValueChanged<DateTime> onSubmit;
  final VoidCallback onBack;

  @override
  State<BirthDateStep> createState() => _BirthDateStepState();
}

class _BirthDateStepState extends State<BirthDateStep> {
  late final _day = TextEditingController(
    text: widget.initialDate?.day.toString() ?? '',
  );
  late final _month = TextEditingController(
    text: widget.initialDate?.month.toString() ?? '',
  );
  late final _year = TextEditingController(
    text:
        widget.initialDate?.year.toString() ??
        widget.initialYear?.toString() ??
        '',
  );
  BirthDateError? _error;
  DateTime? _valid;

  @override
  void initState() {
    super.initState();
    _check(showError: false);
  }

  @override
  void dispose() {
    _day.dispose();
    _month.dispose();
    _year.dispose();
    super.dispose();
  }

  ({DateTime? date, BirthDateError? error}) _result() => validateBirthDate(
    day: _day.text,
    month: _month.text,
    year: _year.text,
    todayUtc: widget.todayUtc,
  );

  void _check({required bool showError}) {
    final result = _result();
    setState(() {
      _valid = result.date;
      if (showError) _error = result.error;
      if (result.date != null) _error = null;
    });
    if (showError && result.error != null) {
      SemanticsService.announce(
        _message(AppLocalizations.of(context)!, result.error!),
        Directionality.of(context),
      );
    }
  }

  void _continue() {
    _check(showError: true);
    final date = _result().date;
    if (date != null) widget.onSubmit(date);
  }

  String _message(AppLocalizations loc, BirthDateError error) =>
      switch (error) {
        BirthDateError.dayRange => loc.flow_dobDayRange,
        BirthDateError.monthRange => loc.flow_dobMonthRange,
        BirthDateError.yearDigits => loc.flow_dobYearDigits,
        BirthDateError.noSuchDate => loc.flow_dobNoSuchDate,
        BirthDateError.future => loc.flow_dobFuture,
        BirthDateError.tooOld => loc.flow_dobCheckYear,
      };

  Widget _field(
    TextEditingController controller,
    String label,
    String semantics,
    int maxLength,
  ) => FlowTextField(
    controller: controller,
    label: label,
    semanticsLabel: semantics,
    keyboardType: TextInputType.number,
    inputFormatters: [
      FilteringTextInputFormatter.digitsOnly,
      LengthLimitingTextInputFormatter(maxLength),
    ],
    onChanged: (_) => _check(showError: false),
  );

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final day = _field(_day, loc.flow_dobDay, loc.flow_dobDaySemantics, 2);
    final month = _field(
      _month,
      loc.flow_dobMonth,
      loc.flow_dobMonthSemantics,
      2,
    );
    final year = _field(_year, loc.flow_dobYear, loc.flow_dobYearSemantics, 4);
    final ordered =
        widget.order == BirthDateOrder.dayMonthYear
            ? [day, month, year]
            : [month, day, year];
    // At large text three fields side by side get too narrow for their
    // labels, so they stack (§2.3).
    final stacked = MediaQuery.textScalerOf(context).scale(1) > 1.5;
    final valid = _valid;

    return FlowFrame(
      title: loc.flow_dobTitle,
      hint: loc.flow_dobHint,
      onBack: widget.onBack,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (stacked)
            for (final field in ordered) ...[field, const SizedBox(height: 12)]
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: ordered[0]),
                const SizedBox(width: 12),
                Expanded(child: ordered[1]),
                const SizedBox(width: 12),
                Expanded(flex: 2, child: ordered[2]),
              ],
            ),
          const SizedBox(height: 8),
          Text(
            loc.flow_dobExample(birthDateExample(widget.order)),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 18,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    _message(loc, _error!),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (valid != null) ...[
            const SizedBox(height: 12),
            Semantics(
              liveRegion: true,
              child: Text(
                MyDateFormat.join([
                  MyDateFormat.toDate(valid),
                  loc.flow_dobAge(ageOn(valid, widget.todayUtc)),
                ]),
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
          ],
        ],
      ),
      actions: [
        FlowPrimaryButton(label: loc.flow_continue, onPressed: _continue),
      ],
    );
  }
}
```

- [ ] **Step 5: A3 and A4**

Create `lib/features/auth/sign_up/presentation/steps/phone_step.dart` with exactly:

```dart
import 'dart:async';

import 'package:attune/core/utils/bottom_sheet_utils.dart';
import 'package:attune/features/auth/log_in/domain/phone_country.dart';
import 'package:attune/features/auth/log_in/presentation/widgets/phone_country_picker_sheet.dart';
import 'package:attune/features/auth/sign_up/domain/phone_entry.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_colors.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_frame.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_text_field.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

/// A3 · Phone (Spec 1 §3.3). The country defaults to the SIM's, else the
/// device region's, else none and the picker opens. W2b sends by SMS only.
class PhoneStep extends StatefulWidget {
  const PhoneStep({
    super.key,
    required this.initialCountry,
    required this.onSend,
    required this.onBack,
    this.initialNational = '',
    this.busy = false,
    this.sendError,
  });

  final PhoneCountry? initialCountry;
  final String initialNational;

  /// A valid number, E.164, and its country.
  final void Function(String e164, String countryIso) onSend;
  final VoidCallback onBack;
  final bool busy;

  /// A failed send, in the words to show.
  final String? sendError;

  @override
  State<PhoneStep> createState() => _PhoneStepState();
}

class _PhoneStepState extends State<PhoneStep> {
  late final _number = TextEditingController(text: widget.initialNational);
  late PhoneCountry? _country = widget.initialCountry;
  PhoneEntryError? _error;
  Timer? _slow;
  bool _showSending = false;

  /// No country is selected: matches no row in the picker.
  static const _none = PhoneCountry(
    isoCode: '',
    name: '',
    dialCode: '',
    flag: '',
    example: '',
  );

  @override
  void initState() {
    super.initState();
    if (_country == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _pickCountry();
      });
    }
  }

  @override
  void didUpdateWidget(covariant PhoneStep oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.busy && !oldWidget.busy) {
      // Any wait over 400 ms says what is happening (§2.2).
      _slow = Timer(const Duration(milliseconds: 400), () {
        if (mounted) setState(() => _showSending = true);
      });
    } else if (!widget.busy && oldWidget.busy) {
      _slow?.cancel();
      _showSending = false;
    }
    final error = widget.sendError;
    if (error != null && error != oldWidget.sendError) {
      SemanticsService.announce(error, Directionality.of(context));
    }
  }

  @override
  void dispose() {
    _slow?.cancel();
    _number.dispose();
    super.dispose();
  }

  Future<void> _pickCountry() => BottomSheetUtils.showDocumentationBottomSheet(
    context: context,
    padding: 0,
    widget: PhoneCountryPickerSheet(
      selectedCountry: _country ?? _none,
      onCountrySelected: (country) {
        if (mounted) setState(() => _country = country);
      },
    ),
  );

  /// The valid number and its country, or null (and the error shown).
  (String, String)? _validNumber() {
    final country = _country;
    if (country == null) {
      _pickCountry();
      return null;
    }
    final result = parsePhoneEntry(_number.text, country.isoCode);
    setState(() => _error = result.error);
    final e164 = result.e164;
    return e164 == null ? null : (e164, country.isoCode);
  }

  void _send() {
    final number = _validNumber();
    if (number != null) widget.onSend(number.$1, number.$2);
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final country = _country;
    return FlowFrame(
      title: loc.flow_phoneTitle,
      hint: loc.flow_phoneHint,
      onBack: widget.onBack,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            label:
                country == null
                    ? loc.flow_phoneChooseCountry
                    : loc.flow_phoneCountrySemantics(
                      country.name,
                      country.dialCode,
                    ),
            excludeSemantics: true,
            child: OutlinedButton(
              onPressed: widget.busy ? null : _pickCountry,
              style: OutlinedButton.styleFrom(
                foregroundColor: theme.colorScheme.onSurface,
                minimumSize: const Size.fromHeight(48),
                alignment: AlignmentDirectional.centerStart,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      country == null
                          ? loc.flow_phoneChooseCountry
                          : '${country.flag}  ${country.name} (${country.dialCode})',
                    ),
                  ),
                  const Icon(Icons.keyboard_arrow_down),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          FlowTextField(
            controller: _number,
            label: loc.flow_phoneLabel,
            hintText: country?.example,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.telephoneNumberNational],
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[\d\s\-\+\(\)]')),
            ],
            autofocus: country != null,
            errorText: switch (_error) {
              PhoneEntryError.tooShort => loc.flow_phoneTooShort,
              PhoneEntryError.tooLong => loc.flow_phoneTooLong,
              PhoneEntryError.wrongCountry => loc.flow_phoneWrongCountry(
                country?.name ?? '',
              ),
              null => null,
            },
            onSubmitted: (_) => _send(),
          ),
          const SizedBox(height: 12),
          Text(
            loc.flow_phoneTerms,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (widget.sendError != null) ...[
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 18,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    widget.sendError!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (_showSending) ...[
            const SizedBox(height: 16),
            LinearProgressIndicator(color: flowAccent(context)),
            const SizedBox(height: 8),
            Semantics(
              liveRegion: true,
              child: Text(loc.flow_sending, style: theme.textTheme.bodyMedium),
            ),
          ],
        ],
      ),
      actions: [
        FlowPrimaryButton(
          label: loc.flow_phoneSend,
          busy: widget.busy,
          onPressed: _send,
        ),
      ],
    );
  }
}
```

Create `lib/features/auth/sign_up/presentation/steps/code_step.dart` with exactly:

```dart
import 'dart:async';

import 'package:attune/features/auth/sign_up/domain/phone_entry.dart';
import 'package:attune/features/auth/sign_up/domain/resend_ladder.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_frame.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/one_time_code_field.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';

/// A4 · Code (Spec 1 §3.3). The flow owns what happens to a code; this
/// shows the field, the resend ladder and the outcome.
class CodeStep extends StatefulWidget {
  const CodeStep({
    super.key,
    required this.phoneE164,
    required this.lastSentAt,
    required this.sendCount,
    required this.now,
    required this.onCode,
    required this.onResend,
    required this.onChangeNumber,
    this.errorText,
    this.errorCount = 0,
    this.accepted = false,
    this.busy = false,
    this.onRetry,
  });

  final String phoneE164;
  final DateTime? lastSentAt;
  final int sendCount;
  final DateTime Function() now;
  final ValueChanged<String> onCode;
  final VoidCallback onResend;
  final VoidCallback onChangeNumber;
  final String? errorText;
  final int errorCount;
  final bool accepted;
  final bool busy;

  /// Shown as "Try again" when the code was accepted but the account
  /// couldn't be read (offline right after verifying).
  final VoidCallback? onRetry;

  @override
  State<CodeStep> createState() => _CodeStepState();
}

class _CodeStepState extends State<CodeStep> {
  final _code = TextEditingController();
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant CodeStep oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A new code was sent: the old digits mean nothing now.
    if (widget.sendCount != oldWidget.sendCount) _code.clear();
  }

  @override
  void dispose() {
    _tick?.cancel();
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final left = ResendLadder.remaining(
      lastSentAt: widget.lastSentAt,
      sendCount: widget.sendCount,
      now: widget.now(),
    );
    return FlowFrame(
      title: loc.flow_codeTitle,
      hint: loc.flow_codeSubtitle(formatPhoneForDisplay(widget.phoneE164)),
      onBack: widget.onChangeNumber,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FlowTextLink(
            label: loc.flow_codeChangeNumber,
            alignment: AlignmentDirectional.centerStart,
            onPressed: widget.onChangeNumber,
          ),
          const SizedBox(height: 8),
          OneTimeCodeField(
            controller: _code,
            semanticsLabel: loc.flow_codeSemantics,
            enabled: !widget.busy && !widget.accepted,
            errorText: widget.errorText,
            errorCount: widget.errorCount,
            accepted: widget.accepted,
            onCompleted: widget.onCode,
          ),
          if (ResendLadder.saysUseNewest(widget.sendCount)) ...[
            const SizedBox(height: 8),
            Text(loc.flow_codeNewest, style: theme.textTheme.bodyMedium),
          ],
          const SizedBox(height: 16),
          if (left > Duration.zero)
            Text(
              loc.flow_codeResendIn(ResendLadder.clock(left)),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          else
            FlowTextLink(
              label: loc.flow_codeResend,
              alignment: AlignmentDirectional.centerStart,
              onPressed: widget.busy ? () {} : widget.onResend,
            ),
        ],
      ),
      actions: [
        if (widget.onRetry != null)
          FlowPrimaryButton(
            label: loc.flow_tryAgain,
            busy: widget.busy,
            onPressed: widget.onRetry,
          ),
      ],
    );
  }
}
```

- [ ] **Step 6: A5/A5c, N1 and "Welcome back"**

Create `lib/features/auth/sign_up/presentation/steps/consent_step.dart` with exactly:

```dart
import 'package:attune/app/documentations/legal_documentation/data/legal_documentation_data.dart';
import 'package:attune/app/documentations/user_manual/data/about_attune_docs.dart';
import 'package:attune/app/documentations/user_manual/widgets/documentation_tab_view.dart';
import 'package:attune/core/utils/bottom_sheet_utils.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_frame.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';

/// A5 · Before you start (EULA v2), and A5c "We've updated our terms" for
/// an account that accepted an older version (Spec 1 §3.3, §3.15). Never
/// animated. Bullet 2 is checked against the live AI features by the owner
/// and privacy counsel before production (W2 gate).
class ConsentStep extends StatelessWidget {
  const ConsentStep({
    super.key,
    required this.onAgree,
    required this.onNotNow,
    this.updatedTerms = false,
    this.busy = false,
    this.errorText,
  });

  final VoidCallback onAgree;
  final VoidCallback onNotNow;
  final bool updatedTerms;
  final bool busy;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    Widget bullet(String text) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: Text('•  ', style: theme.textTheme.bodyLarge),
          ),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
    return FlowFrame(
      title:
          updatedTerms ? loc.flow_consentUpdatedTitle : loc.flow_consentTitle,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          bullet(loc.flow_consentAdults),
          bullet(loc.flow_consentAi),
          bullet(loc.flow_consentData),
          Wrap(
            children: [
              FlowTextLink(
                label: loc.flow_consentTermsLink,
                onPressed:
                    () => BottomSheetUtils.showDocumentationBottomSheet(
                      context: context,
                      document: LegalDocumentationData.termsOfService(context),
                      showButtons: false,
                    ),
              ),
              FlowTextLink(
                label: loc.flow_consentPrivacyLink,
                onPressed:
                    () => BottomSheetUtils.showDocumentationBottomSheet(
                      context: context,
                      document: LegalDocumentationData.privacyPolicy(context),
                      showButtons: false,
                    ),
              ),
              FlowTextLink(
                label: loc.flow_consentAiLink,
                onPressed:
                    () => BottomSheetUtils.showDocumentationBottomSheet(
                      context: context,
                      widget: DocumentationTabView(
                        module: AboutAttuneDocs(),
                        showDocumentationFirst: true,
                      ),
                    ),
              ),
            ],
          ),
          if (errorText != null) ...[
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 18,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Semantics(
                    liveRegion: true,
                    child: Text(errorText!, style: theme.textTheme.bodyMedium),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
      actions: [
        FlowPrimaryButton(
          label: loc.flow_consentAgree,
          busy: busy,
          onPressed: onAgree,
        ),
        FlowSecondaryButton(
          label: loc.flow_consentNotNow,
          onPressed: busy ? null : onNotNow,
        ),
      ],
    );
  }
}
```

Create `lib/features/auth/sign_up/presentation/steps/no_account_step.dart` with exactly:

```dart
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_frame.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';

/// N1 · No account (Spec 1 §3.4): said only after the code proved the
/// number (10 F-10).
class NoAccountStep extends StatelessWidget {
  const NoAccountStep({
    super.key,
    required this.onCreate,
    required this.onOtherNumber,
  });

  final VoidCallback onCreate;
  final VoidCallback onOtherNumber;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return FlowFrame(
      title: loc.flow_noAccountTitle,
      body: Text(
        loc.flow_noAccountBody,
        style: theme.textTheme.bodyLarge?.copyWith(
          color: theme.colorScheme.onSurface,
        ),
      ),
      actions: [
        FlowPrimaryButton(label: loc.flow_noAccountCreate, onPressed: onCreate),
        FlowSecondaryButton(
          label: loc.flow_noAccountOtherNumber,
          onPressed: onOtherNumber,
        ),
      ],
    );
  }
}

/// "Welcome back, {name}." for a second, then home (spec §3.3 A4).
class WelcomeBackStep extends StatelessWidget {
  const WelcomeBackStep({super.key, required this.firstName});

  final String? firstName;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final name = firstName;
    return FlowFrame(
      title:
          name == null || name.isEmpty
              ? loc.flow_welcomeBackNoName
              : loc.flow_welcomeBack(name),
      body: const SizedBox.shrink(),
    );
  }
}
```

- [ ] **Step 7: Run the tests, create the goldens and look at them**

```bash
cd /Users/user/attune
flutter test --no-pub test/core/platform/sim_country_test.dart test/features/auth/sign_up/one_time_code_field_test.dart 2>&1 | tr '\r' '\n' | grep -E "All tests passed|Some tests failed" | tail -1
flutter test --no-pub --update-goldens test/features/auth/sign_up/w2b_goldens_test.dart 2>&1 | tr '\r' '\n' | grep -E "All tests passed|Some tests failed|overflow" | tail -1
ls test/features/auth/sign_up/goldens | wc -l
dart format lib/core/platform lib/features/auth/sign_up test/core/platform test/features/auth/sign_up
flutter analyze --no-pub lib/core/platform lib/features/auth/sign_up test/core/platform test/features/auth/sign_up 2>&1 | grep -E "^\s*(error|warning) " | head
```
Expected: `All tests passed!` (7: the SIM channel, its junk and missing cases, iOS never asks, MainActivity answers on `attune/device` without READ_PHONE_STATE; one labelled field asking for a one-time code, a pasted code completes once, a wrong code shakes and reduce motion keeps still); `All tests passed!` with no overflow; `52` images; `Formatted … (0 changed)`; no `error`/`warning`. Open `step_code.scale2.0.png`, `step_birth_date.scale2.0.png` (stacked fields at large text) and `step_consent.rtl.png`: the six boxes have no field outline drawn over them, nothing is clipped, the consent screen has its three bullets and both buttons.

---

### Task 8: The coordinator, `SignUpFlow`, and the resume rule (W2b; §3.3, §3.4, §3.6, §5.4, §5.5, P-14, P-17, P-18, P-33)

**Files:**
- Create: `lib/features/auth/sign_up/data/sign_up_gateways.dart`, `lib/features/auth/sign_up/data/sign_up_coordinator.dart`
- Create: `lib/features/auth/sign_up/presentation/screens/sign_up_flow.dart`
- Modify: `lib/app/routing/routing_notifier.dart` (`signUpToResume`; one import)
- Modify: `lib/app/routing/sign_in_redirect.dart` (the resume rule; `/login` → `/welcome`)
- Modify: `lib/app/routing/app_router.dart` (`/signup` builds `SignUpFlow`; two imports)
- Create: `test/helpers/fake_sign_up.dart`, `test/features/auth/sign_up/sign_up_coordinator_test.dart`, `test/features/auth/sign_up/sign_up_flow_test.dart`
- Modify: `test/app/routing/sign_in_redirect_test.dart` (imports; a W2b group)

**Interfaces:**
- Consumes: Tasks 2, 5, 6, 7; W1's `HomeState`, `HomeNeed.consent`, metric keys `signupStarted|signupStepName|signupStepDob|signupStepPhone|signupAgeStop`; `PasswordlessAuthService.requestPhoneOtp|verifyPhoneOtp|currentUser`; `authOperationsProvider` (`signOut`, the app's full sign-out).
- Produces: `abstract class CodeSender {send({phoneE164, channel, deviceNonce})}`, `BuiltInSmsCodeSender`; `abstract class SignUpAuth {currentUserId; verify({phoneE164, code}); signOut()}`, `AppSignUpAuth`; `codeSenderProvider`, `signUpAuthProvider`; `enum SignUpStepId {name, birthDate, phone, code, consent, consentUpdate, noAccount, welcomeBack}`; `sealed class VerifyOutcome` (`VerifiedNew(next)`, `VerifiedExisting({firstName, needsConsent})`, `VerifiedUnresolved`, `VerifyFailed(failure)`); `enum CompleteOutcome {done, queued, notEligible, phoneRequired, failed}`; `SignUpCoordinator({drafts, sender, auth, accounts, ageGate, onboardingStoreFor, metrics, now})` with `draft`, `todayUtc`, `start(entry)`, `afterBirthDate`, `saveName`, `guestBirthYear`, `saveBirthDate → bool`, `sendCode({phoneE164, countryIso, channel = 'sms'}) → OtpSendFailure?`, `verify(code)`, `resolveVerified()`, `complete()`, `acceptUpdatedTerms()`, `notNow()`, `useDifferentNumber()`, `changeNumber()`; `signUpClockProvider`, `signUpCoordinatorProvider`; `SignUpFlow({required SignUpEntry entry, String? backTo})`; `RoutingNotifier.signUpToResume`. Test helpers `FakeCodeSender` (`sent`, `failNext`), `FakeSignUpAuth({userId, goodCode, verifiesAs})` (`signOuts`).

- [ ] **Step 1: Write the failing tests**

Create `test/helpers/fake_sign_up.dart` with exactly:

```dart
// Spec 1 W2b: scripted Auth and code sending for the sign-up tests.
import 'package:attune/features/auth/sign_up/data/sign_up_gateways.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FakeCodeSender implements CodeSender {
  final sent = <(String phone, String channel, String nonce)>[];

  /// Thrown by the next send, if set (then cleared).
  Object? failNext;

  @override
  Future<void> send({
    required String phoneE164,
    required String channel,
    required String deviceNonce,
  }) async {
    final failure = failNext;
    if (failure != null) {
      failNext = null;
      throw failure;
    }
    sent.add((phoneE164, channel, deviceNonce));
  }
}

class FakeSignUpAuth implements SignUpAuth {
  FakeSignUpAuth({
    this.userId,
    this.goodCode = '123456',
    this.verifiesAs = 'u1',
  });

  String? userId;
  String goodCode;
  String verifiesAs;
  int signOuts = 0;

  @override
  String? get currentUserId => userId;

  @override
  Future<String?> verify({
    required String phoneE164,
    required String code,
  }) async {
    if (code != goodCode) {
      throw const AuthException(
        'Token has expired or is invalid',
        code: 'otp_expired',
        statusCode: '403',
      );
    }
    userId = verifiesAs;
    return verifiesAs;
  }

  @override
  Future<void> signOut() async {
    signOuts++;
    userId = null;
  }
}
```

Create `test/features/auth/sign_up/sign_up_coordinator_test.dart` with exactly:

```dart
// Spec 1 W2b (§3.3, §3.4, §3.6, §7.3): the sign-up's decisions — resume
// at A4, under 18 writes nothing, an existing account discards the draft,
// N1, the queued A5 and the server's under-18 refusal.
import 'dart:async';

import 'package:attune/core/metrics/metric_counter.dart';
import 'package:attune/features/auth/sign_up/data/account_service.dart';
import 'package:attune/features/auth/sign_up/data/age_gate_store.dart';
import 'package:attune/features/auth/sign_up/data/sign_up_coordinator.dart';
import 'package:attune/features/auth/sign_up/data/sign_up_draft_store.dart';
import 'package:attune/features/auth/sign_up/domain/otp_failure.dart';
import 'package:attune/features/auth/sign_up/domain/sign_up_draft.dart';
import 'package:attune/features/onboarding/data/onboarding_store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../helpers/fake_account_gateway.dart';
import '../../../helpers/fake_sign_up.dart';

final _now = DateTime.utc(2026, 10, 25, 12);
final _adult = DateTime.utc(1996, 3, 27);
const _phone = '+233244123456';

class _Rig {
  _Rig(
    this.prefs, {
    String? signedInAs,
    Map<String, dynamic>? home,
    String? name,
  }) : auth = FakeSignUpAuth(userId: signedInAs),
       gateway = FakeAccountGateway(homeState: home, name: name);

  final SharedPreferences prefs;
  final sender = FakeCodeSender();
  final FakeSignUpAuth auth;
  final FakeAccountGateway gateway;
  final metrics = <String>[];

  SignUpDraftStore get drafts => SignUpDraftStore(prefs, now: () => _now);
  OnboardingStore store(String uid) =>
      OnboardingStore(prefs, scope: 'user.$uid');

  SignUpCoordinator coordinator() => SignUpCoordinator(
    drafts: drafts,
    sender: sender,
    auth: auth,
    accounts: AccountService(gateway),
    ageGate: AgeGateStore(prefs, now: () => _now),
    onboardingStoreFor: store,
    metrics: MetricCounter((key) async => metrics.add(key)),
    now: () => _now,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  Future<SignUpCoordinator> throughCode(_Rig rig) async {
    final c = rig.coordinator();
    expect(c.start(SignUpEntry.newAccount), SignUpStepId.name);
    await c.saveName('Ɛsi');
    expect(await c.saveBirthDate(_adult), isTrue);
    expect(c.afterBirthDate, SignUpStepId.phone);
    expect(await c.sendCode(phoneE164: _phone, countryIso: 'GH'), isNull);
    return c;
  }

  test('a new account: name, date, phone, code, consent, done', () async {
    final rig = _Rig(
      prefs,
      home: FakeAccountGateway.account(hasAccount: false),
    );
    final c = await throughCode(rig);
    expect(rig.sender.sent.single.$1, _phone);
    expect(rig.sender.sent.single.$3, c.draft.deviceNonce);
    expect(c.draft.sendCount, 1);

    final outcome = await c.verify('123456');
    expect(outcome, isA<VerifiedNew>());
    expect((outcome as VerifiedNew).next, SignUpStepId.consent);

    expect(await c.complete(), CompleteOutcome.done);
    expect(rig.gateway.count('complete_sign_up'), 1);
    expect(
      rig.drafts.read(),
      isNull,
      reason: 'the draft goes once the account exists',
    );
    expect(rig.store('u1').displayName, 'Ɛsi');
    expect(rig.store('u1').pendingSignUp, isNull);
    expect(rig.metrics, [
      'signup_started',
      'signup_step:name',
      'signup_step:dob',
      'signup_step:phone',
    ]);
  });

  test('under 18 at A2 writes nothing anywhere and blocks the phone', () async {
    final rig = _Rig(prefs);
    final c = rig.coordinator();
    c.start(SignUpEntry.newAccount);
    await c.saveName('Kid');
    expect(await c.saveBirthDate(DateTime.utc(2008, 10, 26)), isFalse);
    expect(rig.sender.sent, isEmpty);
    expect(rig.gateway.calls, isEmpty);
    expect(rig.drafts.read(), isNull);
    expect(AgeGateStore.readBlocked(prefs, _now), isTrue);
    expect(rig.metrics.last, 'signup_age_stop');
  });

  test('an 18th birthday on the UTC date gets in', () async {
    final rig = _Rig(prefs);
    final c = rig.coordinator();
    c.start(SignUpEntry.newAccount);
    expect(await c.saveBirthDate(DateTime.utc(2008, 10, 25)), isTrue);
  });

  test('closing the app after a code was sent resumes at A4', () async {
    final rig = _Rig(prefs);
    await throughCode(rig);
    final reopened = rig.coordinator();
    expect(reopened.start(SignUpEntry.newAccount), SignUpStepId.code);
    expect(reopened.draft.name, 'Ɛsi');
    expect(reopened.draft.sendCount, 1);
  });

  test(
    'verified but closed before A5 resumes at A5 for that account only',
    () async {
      final rig = _Rig(
        prefs,
        home: FakeAccountGateway.account(hasAccount: false),
      );
      final c = await throughCode(rig);
      await c.verify('123456');
      expect(
        rig.coordinator().start(SignUpEntry.newAccount),
        SignUpStepId.consent,
      );
      rig.auth.userId = 'someone-else';
      expect(
        rig.coordinator().start(SignUpEntry.newAccount),
        SignUpStepId.name,
      );
    },
  );

  test('an existing account discards the typed name and date', () async {
    final rig = _Rig(
      prefs,
      home: FakeAccountGateway.account(needs: ['consent']),
      name: 'Kofi Mensah',
    );
    final c = await throughCode(rig);
    final outcome = await c.verify('123456') as VerifiedExisting;
    expect(outcome.firstName, 'Kofi');
    expect(outcome.needsConsent, isTrue);
    expect(rig.drafts.read(), isNull);
    expect(rig.gateway.count('complete_sign_up'), 0);
    expect(rig.store('u1').displayName, 'Kofi Mensah');

    await c.acceptUpdatedTerms();
    expect(rig.gateway.calls.last.$1, 'record_eula_acceptance');
  });

  test('a stored phone number is never used as a first name', () async {
    final rig = _Rig(
      prefs,
      home: FakeAccountGateway.account(),
      name: '+233 24 412',
    );
    final c = await throughCode(rig);
    final outcome = await c.verify('123456') as VerifiedExisting;
    expect(outcome.firstName, isNull);
  });

  test('returning with no account: N1, then name and date, then A5', () async {
    final rig = _Rig(
      prefs,
      home: FakeAccountGateway.account(hasAccount: false),
    );
    final c = rig.coordinator();
    expect(c.start(SignUpEntry.returning), SignUpStepId.phone);
    await c.sendCode(phoneE164: _phone, countryIso: 'GH');
    final outcome = await c.verify('123456') as VerifiedNew;
    expect(outcome.next, SignUpStepId.noAccount);
    await c.saveName('Ama');
    await c.saveBirthDate(_adult);
    expect(
      c.afterBirthDate,
      SignUpStepId.consent,
      reason: 'the number is already verified',
    );
  });

  test(
    'N1 "Use a different number" signs out and forgets the number',
    () async {
      final rig = _Rig(
        prefs,
        home: FakeAccountGateway.account(hasAccount: false),
      );
      final c = rig.coordinator();
      c.start(SignUpEntry.returning);
      await c.sendCode(phoneE164: _phone, countryIso: 'GH');
      await c.verify('123456');
      await c.useDifferentNumber();
      expect(rig.auth.signOuts, 1);
      expect(c.draft.phoneE164, isNull);
      expect(c.draft.verifiedUserId, isNull);
    },
  );

  test('offline at A5 the call is queued and the flow carries on', () async {
    final rig = _Rig(
      prefs,
      home: FakeAccountGateway.account(hasAccount: false),
    );
    final c = await throughCode(rig);
    await c.verify('123456');
    rig.gateway.failWith = TimeoutException('offline');
    expect(await c.complete(), CompleteOutcome.queued);
    expect(rig.store('u1').pendingSignUp!.displayName, 'Ɛsi');
    expect(rig.store('u1').pendingSignUp!.birthDate, _adult);
    expect(rig.drafts.read(), isNull);
  });

  test("the server's under-18 refusal signs out, forgets and blocks", () async {
    final rig = _Rig(
      prefs,
      home: FakeAccountGateway.account(hasAccount: false),
    );
    final c = await throughCode(rig);
    await c.verify('123456');
    rig.gateway.failWith = FakeAccountGateway.refusal('signup:not_eligible');
    expect(await c.complete(), CompleteOutcome.notEligible);
    expect(rig.auth.signOuts, 1);
    expect(rig.drafts.read(), isNull);
    expect(AgeGateStore.readBlocked(prefs, _now), isTrue);
  });

  test('"Not now" signs out and leaves nothing to resume', () async {
    final rig = _Rig(
      prefs,
      home: FakeAccountGateway.account(hasAccount: false),
    );
    final c = await throughCode(rig);
    await c.verify('123456');
    await c.notNow();
    expect(rig.auth.signOuts, 1);
    final draft = rig.drafts.read()!;
    expect(draft.awaitingCode, isFalse);
    expect(draft.verifiedUserId, isNull);
    expect(draft.name, 'Ɛsi', reason: 'A1–A3 keep their 7 days');
    expect(rig.gateway.count('complete_sign_up'), 0);
  });

  test('a wrong code and a failed send are told apart', () async {
    final rig = _Rig(prefs);
    final c = await throughCode(rig);
    final wrong = await c.verify('000000') as VerifyFailed;
    expect(wrong.failure, OtpVerifyFailure.wrongCode);

    rig.sender.failNext = const AuthException('otp:rate_limited:120');
    final failure = await c.sendCode();
    expect(failure!.kind, OtpSendFailureKind.rateLimited);
    expect(failure.minutes, 2);
    expect(c.draft.sendCount, 1, reason: 'a failed resend changes nothing');

    expect(await c.sendCode(), isNull);
    expect(c.draft.sendCount, 2);
  });

  test('a new number restarts the ladder', () async {
    final rig = _Rig(prefs);
    final c = await throughCode(rig);
    await c.sendCode();
    expect(c.draft.sendCount, 2);
    await c.changeNumber();
    expect(
      await c.sendCode(phoneE164: '+447911123456', countryIso: 'GB'),
      isNull,
    );
    expect(c.draft.sendCount, 1);
    expect(c.draft.phoneE164, '+447911123456');
  });
}
```

Create `test/features/auth/sign_up/sign_up_flow_test.dart` with exactly:

```dart
// Spec 1 W2b (§3.3, §3.4, §7.3): /signup on screen — the whole new-account
// path, the under-18 stop, a returning account, resume at A4, and consent
// shown without motion.
import 'dart:convert';

import 'package:attune/app/routing/routing_notifier.dart';
import 'package:attune/core/platform/sim_country.dart';
import 'package:attune/features/auth/sign_up/data/account_service.dart';
import 'package:attune/features/auth/sign_up/data/age_gate_store.dart';
import 'package:attune/features/auth/sign_up/data/sign_up_draft_store.dart';
import 'package:attune/features/auth/sign_up/data/sign_up_gateways.dart';
import 'package:attune/features/auth/sign_up/domain/sign_up_draft.dart';
import 'package:attune/features/auth/sign_up/presentation/screens/sign_up_flow.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/fake_account_gateway.dart';
import '../../../helpers/fake_sign_up.dart';
import '../../../helpers/flow_harness.dart';

final _now = DateTime.utc(2026, 10, 25, 12);

List<Override> _deps(
  FakeCodeSender sender,
  FakeSignUpAuth auth,
  FakeAccountGateway gateway,
) => [
  codeSenderProvider.overrideWithValue(sender),
  signUpAuthProvider.overrideWithValue(auth),
  accountServiceProvider.overrideWithValue(AccountService(gateway)),
  signUpClockProvider.overrideWithValue(() => _now),
  deviceCountryProvider.overrideWith((ref) async => (sim: 'GH', region: null)),
];

Future<void> _type(WidgetTester tester, String label, String text) async {
  await tester.enterText(find.widgetWithText(TextField, label), text);
  await tester.pump();
}

Future<void> _tapText(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text).last);
  await tester.tap(find.text(text).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a new account from A1 to home', (tester) async {
    final sender = FakeCodeSender();
    final auth = FakeSignUpAuth();
    final gateway = FakeAccountGateway(
      homeState: FakeAccountGateway.account(hasAccount: false),
    );
    final h = await pumpFlowScreen(
      tester,
      () => const SignUpFlow(entry: SignUpEntry.newAccount),
      overrides: _deps(sender, auth, gateway),
    );

    expect(find.text('What should we call you?'), findsOneWidget);
    await _type(tester, 'Your name', 'Ɛsi');
    await _tapText(tester, 'Continue');

    expect(find.text("What's your date of birth?"), findsOneWidget);
    await _type(tester, 'Day', '27');
    await _type(tester, 'Month', '3');
    await _type(tester, 'Year', '1996');
    expect(
      find.text('Wednesday, March 27, 1996 - that makes you 30.'),
      findsOneWidget,
    );
    await _tapText(tester, 'Continue');

    expect(find.text("What's your phone number?"), findsOneWidget);
    expect(
      find.textContaining('Ghana (+233)'),
      findsOneWidget,
      reason: 'the SIM country',
    );
    await _type(tester, 'Phone number', '0244123456');
    await _tapText(tester, 'Text me a code');
    expect(sender.sent.single.$1, '+233244123456');

    expect(find.text('Enter the code'), findsOneWidget);
    expect(find.text('Send a new code in 0:30'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '123456');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(find.text('Before you start'), findsOneWidget);
    await _tapText(tester, 'Agree and continue');
    expect(h.location, '/home');
    expect(gateway.count('complete_sign_up'), 1);
    expect(SignUpDraftStore.readFrom(h.prefs, _now), isNull);
  });

  testWidgets('under 18 at A2 opens X1 and nothing is sent', (tester) async {
    final sender = FakeCodeSender();
    final gateway = FakeAccountGateway();
    final h = await pumpFlowScreen(
      tester,
      () => const SignUpFlow(entry: SignUpEntry.newAccount),
      overrides: _deps(sender, FakeSignUpAuth(), gateway),
    );
    await _type(tester, 'Your name', 'Kid');
    await _tapText(tester, 'Continue');
    await _type(tester, 'Day', '1');
    await _type(tester, 'Month', '1');
    await _type(tester, 'Year', '2012');
    await _tapText(tester, 'Continue');

    expect(h.location, '/age-stop');
    expect(h.routing.underAgeBlocked, isTrue);
    expect(AgeGateStore.readBlocked(h.prefs, DateTime.now()), isTrue);
    expect(sender.sent, isEmpty);
    expect(gateway.calls, isEmpty);
    expect(SignUpDraftStore.readFrom(h.prefs, _now), isNull);
  });

  testWidgets('a returning account: "Welcome back, Kofi." then home', (
    tester,
  ) async {
    final gateway = FakeAccountGateway(
      homeState: FakeAccountGateway.account(),
      name: 'Kofi',
    );
    final h = await pumpFlowScreen(
      tester,
      () => const SignUpFlow(entry: SignUpEntry.returning),
      overrides: _deps(FakeCodeSender(), FakeSignUpAuth(), gateway),
    );
    expect(find.text("What's your phone number?"), findsOneWidget);
    await _type(tester, 'Phone number', '244123456');
    await _tapText(tester, 'Text me a code');
    await tester.enterText(find.byType(TextField), '123456');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Welcome back, Kofi.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(h.location, '/home');
  });

  testWidgets('a returning number with no account sees N1', (tester) async {
    final gateway = FakeAccountGateway(
      homeState: FakeAccountGateway.account(hasAccount: false),
    );
    await pumpFlowScreen(
      tester,
      () => const SignUpFlow(entry: SignUpEntry.returning),
      overrides: _deps(FakeCodeSender(), FakeSignUpAuth(), gateway),
    );
    await _type(tester, 'Phone number', '244123456');
    await _tapText(tester, 'Text me a code');
    await tester.enterText(find.byType(TextField), '123456');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(
      find.text("We couldn't find an Attune account for this number"),
      findsOneWidget,
    );
    await _tapText(tester, 'Create an account');
    expect(find.text('What should we call you?'), findsOneWidget);
  });

  testWidgets('a wrong code says so and keeps the person on A4', (
    tester,
  ) async {
    await pumpFlowScreen(
      tester,
      () => const SignUpFlow(entry: SignUpEntry.returning),
      overrides: _deps(
        FakeCodeSender(),
        FakeSignUpAuth(),
        FakeAccountGateway(),
      ),
    );
    await _type(tester, 'Phone number', '244123456');
    await _tapText(tester, 'Text me a code');
    await tester.enterText(find.byType(TextField), '999999');
    await tester.pumpAndSettle();
    expect(
      find.text("That code didn't work. Check it and try again."),
      findsOneWidget,
    );
    expect(find.text('Enter the code'), findsOneWidget);
  });

  testWidgets('reopened with a code on its way, the flow opens at A4', (
    tester,
  ) async {
    final draft = SignUpDraft.start(SignUpEntry.newAccount, now: _now).copyWith(
      name: 'Ama',
      birthDate: DateTime.utc(1990, 1, 1),
      phoneE164: '+233244123456',
      countryIso: 'GH',
      lastSentAt: _now,
      sendCount: 1,
    );
    await pumpFlowScreen(
      tester,
      () => const SignUpFlow(entry: SignUpEntry.newAccount),
      prefsValues: {SignUpDraftStore.key: jsonEncodeDraft(draft)},
      overrides: _deps(
        FakeCodeSender(),
        FakeSignUpAuth(),
        FakeAccountGateway(),
      ),
    );
    expect(find.text('Enter the code'), findsOneWidget);
  });

  testWidgets('consent appears at once, with no step animation', (
    tester,
  ) async {
    final draft = SignUpDraft.start(SignUpEntry.newAccount, now: _now).copyWith(
      name: 'Ama',
      birthDate: DateTime.utc(1990, 1, 1),
      phoneE164: '+233244123456',
      lastSentAt: _now,
      sendCount: 1,
      verifiedUserId: 'u1',
    );
    await pumpFlowScreen(
      tester,
      () => const SignUpFlow(entry: SignUpEntry.newAccount),
      prefsValues: {SignUpDraftStore.key: jsonEncodeDraft(draft)},
      overrides: _deps(
        FakeCodeSender(),
        FakeSignUpAuth(userId: 'u1'),
        FakeAccountGateway(),
      ),
    );
    expect(find.text('Before you start'), findsOneWidget);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('"Not now" signs out and goes back to Welcome', (tester) async {
    final draft = SignUpDraft.start(SignUpEntry.newAccount, now: _now).copyWith(
      name: 'Ama',
      birthDate: DateTime.utc(1990, 1, 1),
      phoneE164: '+233244123456',
      lastSentAt: _now,
      sendCount: 1,
      verifiedUserId: 'u1',
    );
    final auth = FakeSignUpAuth(userId: 'u1');
    final h = await pumpFlowScreen(
      tester,
      () => const SignUpFlow(entry: SignUpEntry.newAccount),
      prefsValues: {SignUpDraftStore.key: jsonEncodeDraft(draft)},
      overrides: _deps(FakeCodeSender(), auth, FakeAccountGateway()),
    );
    await _tapText(tester, 'Not now');
    expect(auth.signOuts, 1);
    expect(h.location, '/welcome');
    expect(
      RoutingNotifier(prefs: h.prefs, currentUserId: () => null).signUpToResume,
      isFalse,
    );
  });
}

String jsonEncodeDraft(SignUpDraft draft) =>
    const JsonEncoder().convert(draft.toJson());
```

In `test/app/routing/sign_in_redirect_test.dart`:

Edit 1 of 2. Replace exactly:

```dart
// it is today's rule for every existing route; with it on, the pre-auth
// allow-list, the guest gate and the under-18 block.
import 'package:attune/app/routing/app_router.dart' show RouteNames;
import 'package:attune/app/routing/routing_notifier.dart';
import 'package:attune/app/routing/sign_in_redirect.dart';
import 'package:flutter_test/flutter_test.dart';

RoutingNotifier _routing({
```

with:

```dart
// it is today's rule for every existing route; with it on, the pre-auth
// allow-list, the guest gate and the under-18 block.
import 'dart:convert';

import 'package:attune/app/routing/app_router.dart' show RouteNames;
import 'package:attune/app/routing/routing_notifier.dart';
import 'package:attune/app/routing/sign_in_redirect.dart';
import 'package:attune/features/auth/sign_up/data/sign_up_draft_store.dart';
import 'package:attune/features/auth/sign_up/domain/sign_up_draft.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

RoutingNotifier _routing({
```

Edit 2 of 2. Replace exactly:

```dart
    expect(notified, 3);
  });
}
```

with:

```dart
    expect(notified, 3);
  });

  group('W2b: a sign-up in progress, and LoginScreen', () {
    late SharedPreferences prefs;
    final now = DateTime.now().toUtc();

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
    });

    RoutingNotifier withDraft(SignUpDraft draft, {String? userId}) {
      prefs.setString(SignUpDraftStore.key, jsonEncode(draft.toJson()));
      return RoutingNotifier(
        prefs: prefs,
        flowV2: true,
        guestAgeOk: true,
        currentUserId: () => userId,
      );
    }

    final codeSent = SignUpDraft.start(
      SignUpEntry.newAccount,
      now: now,
    ).copyWith(phoneE164: '+233244123456', lastSentAt: now, sendCount: 1);

    test(
      'a code on its way: launch, home and onboarding resume at /signup',
      () {
        final r = withDraft(codeSent);
        for (final location in [
          '/_invisible',
          RouteNames.home,
          RouteNames.onboarding,
        ]) {
          expect(appRedirect(r, location), RouteNames.signUp, reason: location);
        }
        expect(appRedirect(r, RouteNames.signUp), isNull);
      },
    );

    test(
      'verified and signed in as that account: back to A5, never today\'s onboarding',
      () {
        final r = withDraft(
          codeSent.copyWith(verifiedUserId: 'u1'),
          userId: 'u1',
        );
        expect(appRedirect(r, RouteNames.onboarding), RouteNames.signUp);
        expect(appRedirect(r, RouteNames.home), RouteNames.signUp);
      },
    );

    test('another account, no code, or no draft: nothing to resume', () {
      expect(
        appRedirect(
          withDraft(codeSent.copyWith(verifiedUserId: 'u1'), userId: 'u2'),
          RouteNames.home,
        ),
        isNull,
      );
      expect(
        appRedirect(
          withDraft(SignUpDraft.start(SignUpEntry.newAccount, now: now)),
          RouteNames.home,
        ),
        isNull,
      );
      expect(appRedirect(_routing(guestOk: true), RouteNames.home), isNull);
    });

    test('the flag off ignores a draft entirely', () {
      prefs.setString(SignUpDraftStore.key, jsonEncode(codeSent.toJson()));
      final r = RoutingNotifier(prefs: prefs, currentUserId: () => null);
      expect(appRedirect(r, RouteNames.home), isNull);
    });

    test('LoginScreen is replaced by Welcome', () {
      expect(appRedirect(_routing(), RouteNames.login), RouteNames.welcome);
      expect(appRedirect(_routing(flowV2: false), RouteNames.login), isNull);
    });
  });
}
```

```bash
cd /Users/user/attune
flutter test --no-pub test/features/auth/sign_up/sign_up_coordinator_test.dart 2>&1 | tr '\r' '\n' | grep -E "Error when reading" | head -2
flutter test --no-pub test/app/routing/sign_in_redirect_test.dart 2>&1 | tr '\r' '\n' | grep -E "All tests passed|Some tests failed" | tail -1
```
Expected: `Error when reading 'lib/features/auth/sign_up/data/sign_up_coordinator.dart'` (and the gateways); then `Some tests failed.` (the W2b group: nothing resumes yet, `/login` stays).

- [ ] **Step 2: The gateways and the coordinator**

Create `lib/features/auth/sign_up/data/sign_up_gateways.dart` with exactly:

```dart
import 'package:attune/features/auth/data/passwordless_auth_service.dart';
import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Sends a phone code (Spec 1 §3.3 A3). W2b: Supabase's built-in SMS
/// provider, always by SMS. W2c replaces it with the delivery intent plus
/// the Send SMS Hook.
abstract class CodeSender {
  /// [channel] is `sms`, `whatsapp` or `voice`; [deviceNonce] is the
  /// draft's. Throws what `signInWithOtp` throws.
  Future<void> send({
    required String phoneE164,
    required String channel,
    required String deviceNonce,
  });
}

class BuiltInSmsCodeSender implements CodeSender {
  BuiltInSmsCodeSender(this._auth);

  final PasswordlessAuthService _auth;

  @override
  Future<void> send({
    required String phoneE164,
    required String channel,
    required String deviceNonce,
  }) async {
    final result = await _auth.requestPhoneOtp(phoneE164);
    if (!result.isConfigured) {
      throw const AuthException('not configured', code: 'otp_disabled');
    }
  }
}

/// The Auth calls the flow makes, so it can be tested without a backend.
abstract class SignUpAuth {
  String? get currentUserId;

  /// The verified account's id, or null when Auth returned none.
  Future<String?> verify({required String phoneE164, required String code});

  /// The app's full sign-out (wipes and push release included).
  Future<void> signOut();
}

class AppSignUpAuth implements SignUpAuth {
  AppSignUpAuth(this._ref, [PasswordlessAuthService? auth])
    : _auth = auth ?? PasswordlessAuthService();

  final Ref _ref;
  final PasswordlessAuthService _auth;

  @override
  String? get currentUserId => _auth.currentUser?.id;

  @override
  Future<String?> verify({
    required String phoneE164,
    required String code,
  }) async =>
      (await _auth.verifyPhoneOtp(phoneNumber: phoneE164, token: code)).userId;

  @override
  Future<void> signOut() => _ref.read(authOperationsProvider).signOut();
}

final codeSenderProvider = Provider<CodeSender>(
  (ref) => BuiltInSmsCodeSender(PasswordlessAuthService()),
);

final signUpAuthProvider = Provider<SignUpAuth>((ref) => AppSignUpAuth(ref));
```

Create `lib/features/auth/sign_up/data/sign_up_coordinator.dart` with exactly:

```dart
import 'dart:async';

import 'package:attune/core/metrics/metric_counter.dart';
import 'package:attune/features/auth/sign_up/data/account_service.dart';
import 'package:attune/features/auth/sign_up/data/age_gate_store.dart';
import 'package:attune/features/auth/sign_up/data/sign_up_draft_store.dart';
import 'package:attune/features/auth/sign_up/data/sign_up_gateways.dart';
import 'package:attune/features/auth/sign_up/domain/birth_date_validator.dart';
import 'package:attune/features/auth/sign_up/domain/otp_failure.dart';
import 'package:attune/features/auth/sign_up/domain/sign_up_draft.dart';
import 'package:attune/features/onboarding/data/onboarding_store.dart';
import 'package:attune/features/onboarding/domain/home_state.dart';

/// The steps `/signup` can show (Spec 1 §3.3, §3.4).
enum SignUpStepId {
  name,
  birthDate,
  phone,
  code,
  consent,
  consentUpdate,
  noAccount,
  welcomeBack,
}

/// Where a verified code leads.
sealed class VerifyOutcome {
  const VerifyOutcome();
}

/// A new account: A5 (or N1 when A1/A2 weren't asked, the returning way).
class VerifiedNew extends VerifyOutcome {
  const VerifiedNew(this.next);

  final SignUpStepId next;
}

/// An existing account: the typed name and date are discarded.
class VerifiedExisting extends VerifyOutcome {
  const VerifiedExisting({required this.firstName, required this.needsConsent});

  final String? firstName;

  /// EULA older than v2: A5c first.
  final bool needsConsent;
}

/// The code was accepted but the account couldn't be read: try again.
class VerifiedUnresolved extends VerifyOutcome {
  const VerifiedUnresolved();
}

class VerifyFailed extends VerifyOutcome {
  const VerifyFailed(this.failure);

  final OtpVerifyFailure failure;
}

enum CompleteOutcome {
  /// The account exists.
  done,

  /// Offline: queued as PendingSignUp, the flow carries on (§3.14).
  queued,

  /// `signup:not_eligible`: signed out, draft gone, device blocked. X1.
  notEligible,

  /// `signup:phone_required`.
  phoneRequired,

  /// Anything else the server refused.
  failed,
}

/// The sign-up's decisions, apart from any widget (Spec 1 §3.3, §3.4,
/// §3.6, §5.5). Every step writes the draft, so closing the app resumes.
class SignUpCoordinator {
  SignUpCoordinator({
    required SignUpDraftStore drafts,
    required CodeSender sender,
    required SignUpAuth auth,
    required AccountService accounts,
    required AgeGateStore ageGate,
    required OnboardingStore Function(String userId) onboardingStoreFor,
    required MetricCounter metrics,
    required DateTime Function() now,
  }) : _drafts = drafts,
       _sender = sender,
       _auth = auth,
       _accounts = accounts,
       _ageGate = ageGate,
       _onboardingStoreFor = onboardingStoreFor,
       _metrics = metrics,
       _now = now;

  final SignUpDraftStore _drafts;
  final CodeSender _sender;
  final SignUpAuth _auth;
  final AccountService _accounts;
  final AgeGateStore _ageGate;
  final OnboardingStore Function(String userId) _onboardingStoreFor;
  final MetricCounter _metrics;
  final DateTime Function() _now;

  late SignUpDraft _draft;

  SignUpDraft get draft => _draft;

  DateTime get todayUtc {
    final now = _now().toUtc();
    return DateTime.utc(now.year, now.month, now.day);
  }

  /// Loads or starts the draft and says where the flow opens.
  SignUpStepId start(SignUpEntry entry) {
    final existing = _drafts.read();
    final userId = _auth.currentUserId;
    if (existing != null &&
        userId != null &&
        existing.verifiedUserId == userId) {
      _draft = existing;
      return _hasNameAndDate ? SignUpStepId.consent : SignUpStepId.noAccount;
    }
    if (existing != null && userId == null && existing.awaitingCode) {
      _draft = existing;
      return SignUpStepId.code;
    }
    _draft = (existing ?? SignUpDraft.start(entry, now: _now())).copyWith(
      entry: entry,
    );
    if (existing == null) {
      _metrics.bump(ClientMetricKey.signupStarted);
    }
    unawaited(_save());
    return entry == SignUpEntry.returning
        ? SignUpStepId.phone
        : SignUpStepId.name;
  }

  bool get _hasNameAndDate => _draft.name != null && _draft.birthDate != null;

  /// After A2: A5 when the code was already verified (N1's "Create an
  /// account"), otherwise A3.
  SignUpStepId get afterBirthDate =>
      _draft.verifiedUserId != null ? SignUpStepId.consent : SignUpStepId.phone;

  Future<void> saveName(String name) async {
    _draft = _draft.copyWith(name: name);
    _metrics.bump(ClientMetricKey.signupStepName);
    await _save();
  }

  /// G1's year, for A2's pre-fill.
  Future<int?> guestBirthYear() => _ageGate.guestBirthYear();

  /// False: under 18 on today's UTC date. Nothing was sent anywhere; the
  /// draft is deleted and the phone blocked for 30 days (§3.6).
  Future<bool> saveBirthDate(DateTime birthDate) async {
    if (ageOn(birthDate, todayUtc) < 18) {
      _metrics.bump(ClientMetricKey.signupAgeStop);
      await _drafts.clear();
      await _ageGate.block();
      return false;
    }
    _draft = _draft.copyWith(birthDate: birthDate);
    _metrics.bump(ClientMetricKey.signupStepDob);
    await _save();
    return true;
  }

  /// A3's send, or A4's resend when [phoneE164] is null. Null on success.
  Future<OtpSendFailure?> sendCode({
    String? phoneE164,
    String? countryIso,
    String channel = 'sms',
  }) async {
    final firstToThisNumber =
        phoneE164 != null && phoneE164 != _draft.phoneE164;
    var draft =
        firstToThisNumber
            ? _draft.withoutCode().copyWith(
              phoneE164: phoneE164,
              countryIso: countryIso,
            )
            : _draft;
    final phone = draft.phoneE164;
    if (phone == null) {
      return const OtpSendFailure(OtpSendFailureKind.unavailable);
    }
    try {
      await _sender.send(
        phoneE164: phone,
        channel: channel,
        deviceNonce: draft.deviceNonce,
      );
    } catch (error) {
      return classifyOtpSendError(error);
    }
    if (draft.sendCount == 0) _metrics.bump(ClientMetricKey.signupStepPhone);
    draft = draft.copyWith(
      channel: channel,
      lastSentAt: _now(),
      sendCount: draft.sendCount + 1,
    );
    _draft = draft;
    await _save();
    return null;
  }

  /// A4: verifies, then asks the server which account this number is.
  Future<VerifyOutcome> verify(String code) async {
    final phone = _draft.phoneE164;
    if (phone == null) return const VerifyFailed(OtpVerifyFailure.unavailable);
    final String? userId;
    try {
      userId = await _auth.verify(phoneE164: phone, code: code);
    } catch (error) {
      return VerifyFailed(
        classifyOtpVerifyError(
          error,
          lastSentAt: _draft.lastSentAt,
          now: _now(),
        ),
      );
    }
    if (userId == null) {
      return const VerifyFailed(OtpVerifyFailure.unavailable);
    }
    _draft = _draft.copyWith(verifiedUserId: userId);
    await _save();
    return resolveVerified();
  }

  /// The account behind the verified number (also A4's "Try again").
  Future<VerifyOutcome> resolveVerified() async {
    final userId = _draft.verifiedUserId ?? _auth.currentUserId;
    if (userId == null) return const VerifyFailed(OtpVerifyFailure.unavailable);
    final HomeState state;
    try {
      state = await _accounts.homeState();
    } catch (_) {
      return const VerifiedUnresolved();
    }
    if (!state.hasAccount) {
      return VerifiedNew(
        _hasNameAndDate ? SignUpStepId.consent : SignUpStepId.noAccount,
      );
    }
    // An existing account: what was typed here is discarded (§3.3 A4).
    await _drafts.clear();
    final stored = await _accounts.storedDisplayName(userId);
    final firstName = _firstName(stored);
    if (stored != null && firstName != null) {
      await _onboardingStoreFor(userId).rememberDisplayName(stored.trim());
    }
    return VerifiedExisting(
      firstName: firstName,
      needsConsent: state.needs.contains(HomeNeed.consent),
    );
  }

  /// A5: the account, or the call queued when offline.
  Future<CompleteOutcome> complete() async {
    final userId = _auth.currentUserId;
    final name = _draft.name;
    final birthDate = _draft.birthDate;
    if (userId == null || name == null || birthDate == null) {
      return CompleteOutcome.failed;
    }
    var outcome = CompleteOutcome.done;
    try {
      await _accounts.completeSignUp(displayName: name, birthDate: birthDate);
    } on SignUpRefused catch (refused) {
      switch (refused.reason) {
        case SignUpRefusal.notEligible:
          await _auth.signOut();
          await _drafts.clear();
          await _ageGate.block();
          return CompleteOutcome.notEligible;
        case SignUpRefusal.phoneRequired:
          return CompleteOutcome.phoneRequired;
        case SignUpRefusal.invalid:
          return CompleteOutcome.failed;
      }
    } on AccountOffline {
      await _onboardingStoreFor(userId).savePendingSignUp(
        PendingSignUp(displayName: name, birthDate: birthDate),
      );
      outcome = CompleteOutcome.queued;
    }
    await _onboardingStoreFor(userId).rememberDisplayName(name);
    await _ageGate.clearGuestBirthYear();
    await _drafts.clear();
    return outcome;
  }

  /// A5c: EULA v2 for an existing account. Throws AccountOffline.
  Future<void> acceptUpdatedTerms() => _accounts.acceptUpdatedTerms();

  /// A5's "Not now": signed out, nothing written. A1–A3 stay on the phone
  /// (their 7 days), but no code is pending, so nothing resumes by itself.
  Future<void> notNow() async {
    await _auth.signOut();
    _draft = _draft.withoutCode();
    await _save();
  }

  /// N1's "Use a different number": signed out, back to A3.
  Future<void> useDifferentNumber() async {
    await _auth.signOut();
    _draft = _draft.withoutCode(keepPhone: false);
    await _save();
  }

  /// A4's "Wrong number? Change it": back to A3, the ladder restarts.
  Future<void> changeNumber() async {
    _draft = _draft.withoutCode();
    await _save();
  }

  Future<void> _save() => _drafts.write(_draft);

  /// A first name, never a phone number stored as a name.
  static String? _firstName(String? stored) {
    final first = (stored ?? '').trim().split(RegExp(r'\s+')).first;
    if (first.isEmpty || RegExp(r'^\+?[0-9 ()-]*$').hasMatch(first)) {
      return null;
    }
    return first;
  }
}
```

- [ ] **Step 3: The flow**

Create `lib/features/auth/sign_up/presentation/screens/sign_up_flow.dart` with exactly:

```dart
import 'dart:async';

import 'package:attune/app/routing/app_router.dart' show RouteNames;
import 'package:attune/core/metrics/metric_counter.dart';
import 'package:attune/core/platform/sim_country.dart';
import 'package:attune/core/providers/routing_providers.dart';
import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/core/ui/motion/motion_tokens.dart';
import 'package:attune/core/ui/motion/shared_axis_step.dart';
import 'package:attune/features/auth/log_in/domain/phone_country.dart';
import 'package:attune/features/auth/sign_up/data/account_service.dart';
import 'package:attune/features/auth/sign_up/data/age_gate_store.dart';
import 'package:attune/features/auth/sign_up/data/sign_up_coordinator.dart';
import 'package:attune/features/auth/sign_up/data/sign_up_draft_store.dart';
import 'package:attune/features/auth/sign_up/data/sign_up_gateways.dart';
import 'package:attune/features/auth/sign_up/domain/birth_date_validator.dart';
import 'package:attune/features/auth/sign_up/domain/default_phone_country.dart';
import 'package:attune/features/auth/sign_up/domain/otp_failure.dart';
import 'package:attune/features/auth/sign_up/domain/sign_up_draft.dart';
import 'package:attune/features/auth/sign_up/presentation/steps/birth_date_step.dart';
import 'package:attune/features/auth/sign_up/presentation/steps/code_step.dart';
import 'package:attune/features/auth/sign_up/presentation/steps/consent_step.dart';
import 'package:attune/features/auth/sign_up/presentation/steps/name_step.dart';
import 'package:attune/features/auth/sign_up/presentation/steps/no_account_step.dart';
import 'package:attune/features/auth/sign_up/presentation/steps/phone_step.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_frame.dart';
import 'package:attune/features/onboarding/data/onboarding_store.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phone_numbers_parser/phone_numbers_parser.dart';

/// The clock the flow reads; tests pin it.
final signUpClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

final signUpCoordinatorProvider = Provider.autoDispose<SignUpCoordinator>((
  ref,
) {
  final prefs = ref.watch(sharedPreferencesProvider);
  final now = ref.watch(signUpClockProvider);
  return SignUpCoordinator(
    drafts: SignUpDraftStore(prefs, now: now),
    sender: ref.watch(codeSenderProvider),
    auth: ref.watch(signUpAuthProvider),
    accounts: ref.watch(accountServiceProvider),
    ageGate: ref.watch(ageGateStoreProvider),
    onboardingStoreFor:
        (userId) => OnboardingStore(
          prefs,
          scope: '${OnboardingStore.userScopePrefix}.$userId',
        ),
    metrics: ref.watch(metricCounterProvider),
    now: now,
  );
});

/// `/signup` (Spec 1 §3.3, §3.4): A1–A5, N1 and "Welcome back" in one
/// route, stepped with the shared-axis transition. [entry] is how the
/// person came in; a draft on this phone can resume where it stopped.
class SignUpFlow extends ConsumerStatefulWidget {
  const SignUpFlow({super.key, required this.entry, this.backTo});

  final SignUpEntry entry;

  /// Where the first step's back button goes (`/welcome` by default).
  final String? backTo;

  @override
  ConsumerState<SignUpFlow> createState() => _SignUpFlowState();
}

class _SignUpFlowState extends ConsumerState<SignUpFlow> {
  late final SignUpCoordinator _c = ref.read(signUpCoordinatorProvider);
  late SignUpStepId _step;
  bool _forward = true;
  bool _busy = false;
  String? _error;
  int _errorCount = 0;
  bool _accepted = false;
  bool _unresolved = false;
  int? _guestYear;
  String? _welcomeName;

  @override
  void initState() {
    super.initState();
    _step = _c.start(widget.entry);
    // A3's default country, read early so it is ready by then.
    ref.read(deviceCountryProvider.future).ignore();
    _c.guestBirthYear().then((year) {
      if (mounted && year != null) setState(() => _guestYear = year);
    });
  }

  AppLocalizations get _loc => AppLocalizations.of(context)!;

  void _go(SignUpStepId step, {bool forward = true}) => setState(() {
    _forward = forward;
    _step = step;
    _error = null;
    _accepted = false;
    _unresolved = false;
  });

  void _leave() => context.go(widget.backTo ?? RouteNames.welcome);

  void _back() {
    switch (_step) {
      case SignUpStepId.name:
        _leave();
      case SignUpStepId.birthDate:
        _go(SignUpStepId.name, forward: false);
      case SignUpStepId.phone:
        widget.entry == SignUpEntry.returning && _c.draft.name == null
            ? _leave()
            : _go(SignUpStepId.birthDate, forward: false);
      case SignUpStepId.code:
        _changeNumber();
      case SignUpStepId.consent:
      case SignUpStepId.consentUpdate:
      case SignUpStepId.noAccount:
      case SignUpStepId.welcomeBack:
        // Signed in by now: only the screen's own buttons leave.
        break;
    }
  }

  String _sendError(OtpSendFailure failure) => switch (failure.kind) {
    OtpSendFailureKind.rateLimited => _loc.flow_tooManyCodes(
      failure.minutes ?? 1,
    ),
    OtpSendFailureKind.unavailable => _loc.flow_sendFailed,
    OtpSendFailureKind.signInOff => _loc.flow_phoneUnavailable,
  };

  Future<void> _send(String e164, String iso, {String channel = 'sms'}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final failure = await _c.sendCode(
      phoneE164: e164,
      countryIso: iso,
      channel: channel,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (failure != null) {
      setState(() => _error = _sendError(failure));
      return;
    }
    _go(SignUpStepId.code);
  }

  Future<void> _resend({String channel = 'sms'}) async {
    setState(() => _busy = true);
    final failure = await _c.sendCode(channel: channel);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (failure != null) {
        _error = _sendError(failure);
        _errorCount++;
      } else {
        _error = null;
      }
    });
  }

  Future<void> _changeNumber() async {
    await _c.changeNumber();
    if (mounted) _go(SignUpStepId.phone, forward: false);
  }

  Future<void> _verify(String code) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final outcome = await _c.verify(code);
    if (!mounted) return;
    await _afterVerify(outcome);
  }

  Future<void> _retryResolve() async {
    setState(() => _busy = true);
    final outcome = await _c.resolveVerified();
    if (mounted) await _afterVerify(outcome);
  }

  Future<void> _afterVerify(VerifyOutcome outcome) async {
    if (outcome is VerifyFailed) {
      HapticFeedback.mediumImpact();
      setState(() {
        _busy = false;
        _error = switch (outcome.failure) {
          OtpVerifyFailure.wrongCode => _loc.flow_codeWrong,
          OtpVerifyFailure.expired => _loc.flow_codeExpired,
          OtpVerifyFailure.rateLimited => _loc.flow_tooManyCodes(1),
          OtpVerifyFailure.unavailable => _loc.flow_codeCheckFailed,
        };
        _errorCount++;
      });
      return;
    }
    if (outcome is VerifiedUnresolved) {
      setState(() {
        _busy = false;
        _unresolved = true;
        _error = _loc.flow_codeCheckFailed;
        _errorCount++;
      });
      return;
    }
    // Accepted: the check fades in, holds, then the flow moves on.
    setState(() {
      _busy = false;
      _accepted = true;
      _error = null;
    });
    SemanticsService.announce(
      _loc.flow_codeAccepted,
      Directionality.of(context),
    );
    await Future<void>.delayed(kCodeAcceptedHold);
    if (!mounted) return;
    switch (outcome) {
      case VerifiedNew(:final next):
        _go(next);
      case VerifiedExisting(:final firstName, :final needsConsent):
        _welcomeName = firstName;
        needsConsent ? _go(SignUpStepId.consentUpdate) : await _welcomeBack();
      default:
        break;
    }
  }

  Future<void> _welcomeBack() async {
    _go(SignUpStepId.welcomeBack);
    await Future<void>.delayed(const Duration(seconds: 1));
    if (mounted) context.go(RouteNames.home);
  }

  Future<void> _agree() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    if (_step == SignUpStepId.consentUpdate) {
      try {
        await _c.acceptUpdatedTerms();
      } catch (_) {
        if (mounted) {
          setState(() {
            _busy = false;
            _error = _loc.flow_saveFailed;
          });
        }
        return;
      }
      if (mounted) await _welcomeBack();
      return;
    }
    final outcome = await _c.complete();
    if (!mounted) return;
    switch (outcome) {
      case CompleteOutcome.done:
      case CompleteOutcome.queued:
        context.go(RouteNames.home);
      case CompleteOutcome.notEligible:
        ref.read(routingNotifierProvider).setUnderAgeBlocked(true);
        context.go('${RouteNames.ageStop}?from=server');
      case CompleteOutcome.phoneRequired:
        setState(() {
          _busy = false;
          _error = _loc.flow_signupPhoneRequired;
        });
      case CompleteOutcome.failed:
        setState(() {
          _busy = false;
          _error = _loc.flow_saveFailed;
        });
    }
  }

  Future<void> _notNow() async {
    setState(() => _busy = true);
    await _c.notNow();
    if (mounted) context.go(RouteNames.welcome);
  }

  Future<void> _useDifferentNumber() async {
    await _c.useDifferentNumber();
    if (mounted) _go(SignUpStepId.phone, forward: false);
  }

  PhoneCountry? _initialCountry(DeviceCountries? device) {
    final saved = _c.draft.countryIso;
    return defaultPhoneCountry(
      simIso: saved ?? device?.sim,
      regionIso: device?.region,
    );
  }

  String _initialNational() {
    final e164 = _c.draft.phoneE164;
    if (e164 == null) return '';
    try {
      return PhoneNumber.parse(e164).nsn;
    } catch (_) {
      return '';
    }
  }

  Widget _stepWidget() {
    final draft = _c.draft;
    switch (_step) {
      case SignUpStepId.name:
        return NameStep(
          initialName: draft.name,
          onBack: _back,
          onSubmit: (name) async {
            await _c.saveName(name);
            _go(SignUpStepId.birthDate);
          },
        );
      case SignUpStepId.birthDate:
        return BirthDateStep(
          order: birthDateOrderFor(Localizations.localeOf(context)),
          todayUtc: _c.todayUtc,
          initialDate: draft.birthDate,
          initialYear: _guestYear,
          onBack: _back,
          onSubmit: (date) async {
            final adult = await _c.saveBirthDate(date);
            if (!mounted) return;
            if (!adult) {
              ref.read(routingNotifierProvider).setUnderAgeBlocked(true);
              context.go(RouteNames.ageStop);
              return;
            }
            _go(_c.afterBirthDate);
          },
        );
      case SignUpStepId.phone:
        final device = ref.watch(deviceCountryProvider);
        if (device.isLoading) {
          // The SIM answers within a second; the country picker must not
          // open before it has.
          return FlowFrame(
            title: _loc.flow_phoneTitle,
            hint: _loc.flow_phoneHint,
            onBack: _back,
            body: const SizedBox.shrink(),
          );
        }
        return PhoneStep(
          initialCountry: _initialCountry(device.valueOrNull),
          initialNational: _initialNational(),
          busy: _busy,
          sendError: _error,
          onBack: _back,
          onSend: _send,
        );
      case SignUpStepId.code:
        final now = ref.read(signUpClockProvider);
        return CodeStep(
          phoneE164: draft.phoneE164 ?? '',
          lastSentAt: draft.lastSentAt,
          sendCount: draft.sendCount,
          now: now,
          busy: _busy,
          accepted: _accepted,
          errorText: _error,
          errorCount: _errorCount,
          onCode: _verify,
          onResend: _resend,
          onChangeNumber: _changeNumber,
          onRetry: _unresolved ? _retryResolve : null,
        );
      case SignUpStepId.consent:
      case SignUpStepId.consentUpdate:
        return ConsentStep(
          updatedTerms: _step == SignUpStepId.consentUpdate,
          busy: _busy,
          errorText: _error,
          onAgree: _agree,
          onNotNow: _notNow,
        );
      case SignUpStepId.noAccount:
        return NoAccountStep(
          onCreate: () => _go(SignUpStepId.name),
          onOtherNumber: _useDifferentNumber,
        );
      case SignUpStepId.welcomeBack:
        return WelcomeBackStep(firstName: _welcomeName);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Consent, the under-18 stop and the account screens are never
    // animated (§2.2): they replace the previous step at once.
    final still =
        _step == SignUpStepId.consent || _step == SignUpStepId.consentUpdate;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child:
          still
              ? KeyedSubtree(key: ValueKey(_step), child: _stepWidget())
              : SharedAxisStep(
                stepKey: _step,
                forward: _forward,
                child: _stepWidget(),
              ),
    );
  }
}
```

- [ ] **Step 4: Resume, `/login`, and `/signup` builds the flow**

In `lib/app/routing/routing_notifier.dart`:

Edit 1 of 2. Replace exactly:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
```

with:

```dart
import 'dart:async';

import 'package:attune/features/auth/sign_up/data/sign_up_draft_store.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
```

Edit 2 of 2. Replace exactly:

```dart
  bool get isSignedIn => currentUserId != null;


  void setFlowV2(bool value) {
```

with:

```dart
  bool get isSignedIn => currentUserId != null;

  /// A sign-up this phone should go back to (Spec 1 §3.3): signed out with
  /// a code on its way (A4), or signed in as the account A4 just verified
  /// and not yet through A5. Read from the draft at each redirect.
  bool get signUpToResume {
    final prefs = _prefs;
    if (prefs == null) return false;
    final draft = SignUpDraftStore.readFrom(prefs, DateTime.now());
    if (draft == null) return false;
    final userId = currentUserId;
    return userId == null
        ? draft.awaitingCode
        : draft.verifiedUserId == userId;
  }

  void setFlowV2(bool value) {
```

In `lib/app/routing/sign_in_redirect.dart`:

Edit 1 of 2. Replace exactly:

```dart
  RouteNames.invite,
  RouteNames.guestAge,
};

```

with:

```dart
  RouteNames.invite,
  RouteNames.guestAge,
};

/// Where a resumable sign-up is picked up from (W2b).
const _resumeFrom = <String>{
  '/_invisible',
  RouteNames.home,
  RouteNames.onboarding,
};

```

Edit 2 of 2. Replace exactly:

```dart
    return RouteNames.ageStop;
  }
  if (location == '/_invisible') {
    return routing.isFirstLaunch ? RouteNames.welcome : RouteNames.home;
  }
  // Every legacy way to IntroScreen (sign-out, account deletion, the safety
  // sign-out) lands on Welcome instead.
  if (location == RouteNames.intro) return RouteNames.welcome;
  if (routing.isFirstLaunch) {
    return firstLaunchAllowedRoutes.contains(location)
```

with:

```dart
    return RouteNames.ageStop;
  }
  // A sign-up in progress comes back where it stopped (W2b): at A4 after
  // the app was closed, or at A5 for an account A4 already verified, which
  // today's onboarding must never create without the date of birth.
  if (_resumeFrom.contains(location) && routing.signUpToResume) {
    return RouteNames.signUp;
  }
  if (location == '/_invisible') {
    return routing.isFirstLaunch ? RouteNames.welcome : RouteNames.home;
  }
  // Every legacy way to IntroScreen (sign-out, account deletion, the safety
  // sign-out) and to LoginScreen (OnboardingGate's signed-out branch) lands
  // on Welcome instead.
  if (location == RouteNames.intro || location == RouteNames.login) {
    return RouteNames.welcome;
  }
  if (routing.isFirstLaunch) {
    return firstLaunchAllowedRoutes.contains(location)
```

In `lib/app/routing/app_router.dart` (today's `/login` route stays: it still serves the flag-off flow):

Edit 1 of 2. Replace exactly:

```dart
import 'package:attune/app/routing/sign_in_redirect.dart';
import 'package:attune/features/auth/sign_up/presentation/screens/guest_age_gate_screen.dart';
import 'package:attune/features/auth/sign_up/presentation/screens/invite_landing_screen.dart';
import 'package:attune/features/auth/sign_up/presentation/screens/under_age_stop_screen.dart';
import 'package:attune/features/auth/sign_up/presentation/screens/welcome_screen.dart';
```

with:

```dart
import 'package:attune/app/routing/sign_in_redirect.dart';
import 'package:attune/features/auth/sign_up/presentation/screens/guest_age_gate_screen.dart';
import 'package:attune/features/auth/sign_up/domain/sign_up_draft.dart';
import 'package:attune/features/auth/sign_up/presentation/screens/invite_landing_screen.dart';
import 'package:attune/features/auth/sign_up/presentation/screens/sign_up_flow.dart';
import 'package:attune/features/auth/sign_up/presentation/screens/under_age_stop_screen.dart';
import 'package:attune/features/auth/sign_up/presentation/screens/welcome_screen.dart';
```

Edit 2 of 2. Replace exactly:

```dart
        path: RouteNames.signUp,
        name: 'signUp',
        // W2a: today's phone sign-in, so the development app keeps working
        // until W2b's SignUpFlow takes this route over.
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
```

with:

```dart
        path: RouteNames.signUp,
        name: 'signUp',
        builder:
            (context, state) => SignUpFlow(
              entry: SignUpEntry.fromWire(state.uri.queryParameters['entry']),
              backTo: state.uri.queryParameters['back'],
            ),
      ),
      GoRoute(
```

- [ ] **Step 5: Run the tests to verify they pass**

```bash
cd /Users/user/attune
flutter test --no-pub test/features/auth/sign_up/sign_up_coordinator_test.dart test/features/auth/sign_up/sign_up_flow_test.dart test/app/routing/sign_in_redirect_test.dart test/features/chat/chat_screen_view_active_test.dart 2>&1 | tr '\r' '\n' | grep -E "All tests passed|Some tests failed" | tail -1
dart format lib/features/auth/sign_up lib/app/routing/sign_in_redirect.dart test/helpers/fake_sign_up.dart test/features/auth/sign_up test/app/routing/sign_in_redirect_test.dart
flutter analyze --no-pub lib/app lib/features/auth/sign_up test/app test/helpers test/features/auth/sign_up 2>&1 | grep -E "^\s*(error|warning) " | grep -v "app_info" | head
```
Expected: `All tests passed!` (the coordinator: a new account end to end with its four metrics; under 18 at A2 writes nothing and blocks; an 18th birthday on the UTC date gets in; resume at A4; resume at A5 only for that account; an existing account discards the draft and remembers the name; a phone stored as a name never greets; N1 then A5 without a second code; "Use a different number"; offline A5 queued; the server's under-18 refusal; "Not now"; wrong code vs a rate-limited resend; a new number restarts the ladder. The flow on screen: A1 → A5 → `/home`; under 18 → `/age-stop` with nothing sent; "Welcome back, Kofi." then `/home` after a second; N1; a wrong code; reopened at A4; consent with no ticker; "Not now" → `/welcome` with nothing to resume. The router: resume from launch, home and onboarding; the verified account only; flag off ignores a draft; `/login` → `/welcome`); `Formatted … (0 changed)`; no `error`/`warning`.

- [ ] **Step 6: Mutation checks (the under-18 stop on the phone; the resume rule)**

```bash
cd /Users/user/attune
cp lib/features/auth/sign_up/data/sign_up_coordinator.dart .superpowers/sdd/2026-10-25-spec1-w2/coordinator.dart.keep
perl -0pi -e 's/if \(ageOn\(birthDate, todayUtc\) < 18\) \{/if (false) {/' lib/features/auth/sign_up/data/sign_up_coordinator.dart
flutter test --no-pub test/features/auth/sign_up/sign_up_coordinator_test.dart --plain-name 'under 18 at A2' 2>&1 | tr '\r' '\n' | grep -E "Some tests failed|All tests passed" | tail -1
cp .superpowers/sdd/2026-10-25-spec1-w2/coordinator.dart.keep lib/features/auth/sign_up/data/sign_up_coordinator.dart
cp lib/app/routing/sign_in_redirect.dart .superpowers/sdd/2026-10-25-spec1-w2/redirect.dart.keep
perl -0pi -e 's/  if \(_resumeFrom.contains\(location\) && routing.signUpToResume\) \{\n    return RouteNames.signUp;\n  \}\n//' lib/app/routing/sign_in_redirect.dart
flutter test --no-pub test/app/routing/sign_in_redirect_test.dart 2>&1 | tr '\r' '\n' | grep -E "Some tests failed|All tests passed" | tail -1
cp .superpowers/sdd/2026-10-25-spec1-w2/redirect.dart.keep lib/app/routing/sign_in_redirect.dart
rm .superpowers/sdd/2026-10-25-spec1-w2/*.keep
```
Expected: `Some tests failed.` twice; both files restored. (The second mutant leaves `_resumeFrom` unused, which only warns.)

---

### Task 9: "Join Attune" on the guest tab; W2b gate (W2b; §3.2 G2, §5.2 login_profile.dart)

**Files:**
- Create: `lib/features/auth/sign_up/presentation/widgets/join_attune_panel.dart`
- Modify: `lib/features/auth/log_in/presentation/screens/login_profile.dart` (`ConsumerStatefulWidget`; one flag read; the hello-to-invite block behind `if (!flowV2)`, not re-indented)
- Create: `test/features/auth/sign_up/login_profile_v2_test.dart`
- Modify: `test/features/auth/sign_up/w2b_goldens_test.dart` (one golden)

**Interfaces:**
- Consumes: `signInFlowV2Provider`, `WelcomeScreen.signUpLocation(entry, {back})`, the flow widgets.
- Produces: `JoinAttunePanel` (title, body, "Get started" → `/signup?entry=new&back=/home`, "I already have an account" → `…returning…`, "I have an invite" → `/invite`).

- [ ] **Step 1: Write the failing test**

Create `test/features/auth/sign_up/login_profile_v2_test.dart` with exactly:

```dart
// Spec 1 W2b (§3.2 G2): the guest's sign-in tab. With flow_signin_v2 on it
// is "Join Attune" and the three ways in; off, it is today's screen.
import 'package:attune/features/auth/log_in/presentation/screens/login_profile.dart';
import 'package:attune/features/auth/sign_up/presentation/sign_up_flags.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/join_attune_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/flow_harness.dart';

void main() {
  testWidgets('flag on: Join Attune and the three ways in', (tester) async {
    final semantics = tester.ensureSemantics();
    final h = await pumpFlowScreen(
      tester,
      () => const Scaffold(body: LoginProfile()),
      overrides: [signInFlowV2Provider.overrideWithValue(true)],
    );
    expect(find.text('Join Attune'), findsOneWidget);
    expect(
      find.text(
        'A private space for couples, a few introductions a day for singles, and a journal just for you.',
      ),
      findsOneWidget,
    );
    expect(find.text('Continue with phone number'), findsNothing);

    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();
    expect(Uri.parse(h.location).path, '/signup');
    expect(Uri.parse(h.location).queryParameters, {
      'entry': 'new',
      'back': '/home',
    });
    semantics.dispose();
  });

  testWidgets('the panel meets the tap-target, label and contrast guidelines', (
    tester,
  ) async {
    // On its own: the legal link LoginProfile keeps under it is today's and
    // is left for the W10 accessibility pass.
    final semantics = tester.ensureSemantics();
    await pumpFlowScreen(
      tester,
      () =>
          const Scaffold(body: SingleChildScrollView(child: JoinAttunePanel())),
    );
    await expectFlowGuidelines(tester);
    semantics.dispose();
  });

  for (final (button, entry) in [('I already have an account', 'returning')]) {
    testWidgets('flag on: "$button" opens sign-up as $entry', (tester) async {
      final h = await pumpFlowScreen(
        tester,
        () => const Scaffold(body: LoginProfile()),
        overrides: [signInFlowV2Provider.overrideWithValue(true)],
      );
      await tester.tap(find.text(button));
      await tester.pumpAndSettle();
      expect(Uri.parse(h.location).queryParameters['entry'], entry);
    });
  }

  testWidgets('flag on: "I have an invite" opens /invite', (tester) async {
    final h = await pumpFlowScreen(
      tester,
      () => const Scaffold(body: LoginProfile()),
      overrides: [signInFlowV2Provider.overrideWithValue(true)],
    );
    await tester.ensureVisible(find.text('I have an invite'));
    await tester.tap(find.text('I have an invite'));
    await tester.pumpAndSettle();
    expect(h.location, '/invite');
  });

  testWidgets("flag off: today's screen, unchanged", (tester) async {
    await pumpFlowScreen(
      tester,
      () => const Scaffold(body: LoginProfile()),
      overrides: [signInFlowV2Provider.overrideWithValue(false)],
    );
    expect(find.text('Continue with phone number'), findsOneWidget);
    expect(find.text('Invite a friend'), findsOneWidget);
    expect(find.text('Join Attune'), findsNothing);
  });
}
```

In `test/features/auth/sign_up/w2b_goldens_test.dart`:

Edit 1 of 2. Replace exactly:

```dart
import 'package:attune/features/auth/sign_up/presentation/steps/no_account_step.dart';
import 'package:attune/features/auth/sign_up/presentation/steps/phone_step.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
```

with:

```dart
import 'package:attune/features/auth/sign_up/presentation/steps/no_account_step.dart';
import 'package:attune/features/auth/sign_up/presentation/steps/phone_step.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/join_attune_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
```

Edit 2 of 2. Replace exactly:

```dart
    );
  });
}
```

with:

```dart
    );
  });

  testWidgets('G2 Join Attune', (tester) async {
    await expectFlowGoldens(
      tester,
      'join_attune',
      () => const Scaffold(
        body: SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(16),
            child: JoinAttunePanel(),
          ),
        ),
      ),
    );
  });
}
```

```bash
cd /Users/user/attune
flutter test --no-pub test/features/auth/sign_up/login_profile_v2_test.dart 2>&1 | tr '\r' '\n' | grep -E "Error when reading" | head -1
```
Expected: `Error when reading 'lib/features/auth/sign_up/presentation/widgets/join_attune_panel.dart'`.

- [ ] **Step 2: The panel and LoginProfile**

Create `lib/features/auth/sign_up/presentation/widgets/join_attune_panel.dart` with exactly:

```dart
import 'package:attune/app/routing/app_router.dart' show RouteNames;
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/ui/text/allow_large_text.dart';
import 'package:attune/features/auth/sign_up/presentation/screens/welcome_screen.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';

/// G2 · the guest's sign-in tab under flow_signin_v2 (Spec 1 §3.2): "Join
/// Attune" and the three ways in. Back from the first sign-up step returns
/// to this tab.
class JoinAttunePanel extends StatelessWidget {
  const JoinAttunePanel({super.key});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return AllowLargeText(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Gap(Spacing.lg.h),
          Semantics(
            header: true,
            child: Text(
              loc.flow_joinTitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall?.copyWith(
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Gap(Spacing.md.h),
          Text(
            loc.flow_joinBody,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurface,
            ),
          ),
          Gap(Spacing.lg.h),
          FlowPrimaryButton(
            label: loc.flow_welcomeGetStarted,
            onPressed:
                () => context.go(
                  WelcomeScreen.signUpLocation('new', back: RouteNames.home),
                ),
          ),
          const Gap(Spacing.sm),
          FlowSecondaryButton(
            label: loc.flow_welcomeHaveAccount,
            onPressed:
                () => context.go(
                  WelcomeScreen.signUpLocation(
                    'returning',
                    back: RouteNames.home,
                  ),
                ),
          ),
          const Gap(Spacing.sm),
          FlowSecondaryButton(
            label: loc.flow_welcomeHaveInvite,
            onPressed: () => context.go(RouteNames.invite),
          ),
        ],
      ),
    );
  }
}
```

In `lib/features/auth/log_in/presentation/screens/login_profile.dart` (the hello, overview, phone button and invite button move unchanged inside `else ...[ … ]`; keep their indentation as it is, don't re-indent or format the file):

Edit 1 of 4. Replace exactly:

```dart
import 'package:attune/app/documentations/user_manual/models/documentation_model.dart';
import 'package:attune/features/auth/intro/widgets/intro_guide_widget.dart';

class LoginProfile extends StatefulWidget {
  const LoginProfile({super.key});

  @override
  State<LoginProfile> createState() => _LoginProfileState();
}

class _LoginProfileState extends State<LoginProfile> {
  late ScrollController _scrollController;
  List<DocumentationModule> modules = [];
```

with:

```dart
import 'package:attune/app/documentations/user_manual/models/documentation_model.dart';
import 'package:attune/features/auth/intro/widgets/intro_guide_widget.dart';
import 'package:attune/features/auth/sign_up/presentation/sign_up_flags.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/join_attune_panel.dart';

class LoginProfile extends ConsumerStatefulWidget {
  const LoginProfile({super.key});

  @override
  ConsumerState<LoginProfile> createState() => _LoginProfileState();
}

class _LoginProfileState extends ConsumerState<LoginProfile> {
  late ScrollController _scrollController;
  List<DocumentationModule> modules = [];
```

Edit 2 of 4. Replace exactly:

```dart

    final overview = loc.authGuestOverview(AppConstants.appName);

    return Material(
```

with:

```dart

    final overview = loc.authGuestOverview(AppConstants.appName);
    // Spec 1 W2b (§3.2 G2): under flow_signin_v2 this tab is "Join Attune"
    // with the three ways in; the topic cards and the legal link stay.
    final flowV2 = ref.watch(signInFlowV2Provider);

    return Material(
```

Edit 3 of 4. Replace exactly:

```dart
                      ),
                    ),
                    Gap(Spacing.lg.h),
                    Center(
```

with:

```dart
                      ),
                    ),
                    if (flowV2)
                      const JoinAttunePanel()
                    else ...[
                    Gap(Spacing.lg.h),
                    Center(
```

Edit 4 of 4. Replace exactly:

```dart
                    ),

                    // Gap(Spacing.xl.h),
                    Gap(Spacing.xxl.h),
```

with:

```dart
                    ),

                    ],
                    // Gap(Spacing.xl.h),
                    Gap(Spacing.xxl.h),
```

- [ ] **Step 3: Run the tests and the goldens**

```bash
cd /Users/user/attune
flutter test --no-pub test/features/auth/sign_up/login_profile_v2_test.dart test/login_profile_test.dart test/widget_test.dart 2>&1 | tr '\r' '\n' | grep -E "All tests passed|Some tests failed" | tail -1
flutter test --no-pub --update-goldens test/features/auth/sign_up/w2b_goldens_test.dart --plain-name 'G2 Join Attune' 2>&1 | tr '\r' '\n' | grep -E "All tests passed|Some tests failed" | tail -1
flutter test --no-pub test/features/auth/sign_up/ 2>&1 | tr '\r' '\n' | grep -E "All tests passed|Some tests failed" | tail -1
dart format lib/features/auth/sign_up/presentation/widgets/join_attune_panel.dart test/features/auth/sign_up
```
Expected: `All tests passed!` (flag on: "Join Attune", its body, the three targets and the guidelines on the panel; flag off: today's "Continue with phone number" and "Invite a friend"; `login_profile_test.dart` and `widget_test.dart` unchanged and green); `All tests passed!`; `All tests passed!` with every golden matching; `Formatted … (0 changed)`.

- [ ] **Step 4: W2b regression gate**

```bash
cd /Users/user/attune
flutter test --no-pub 2>&1 | tr '\r' '\n' | grep -E 'All tests passed!|Some tests failed' | tail -1
flutter analyze --no-pub lib test > .superpowers/sdd/2026-10-25-spec1-w2/analyze-w2b.txt 2>&1
comm -13 .superpowers/sdd/2026-10-25-spec1-w2/analyze-errors-baseline.txt <(grep -E '^\s*error ' .superpowers/sdd/2026-10-25-spec1-w2/analyze-w2b.txt | sed -E 's/:[0-9]+:[0-9]+//' | sort -u)
diff <(grep -E 'lib/features/games/|auth_exports\.dart|lib/home/home_screen\.dart|lib/features/opinions/|games_contracts\.sql' .superpowers/sdd/2026-10-25-spec1-w2/git-status-before.txt) <(git status --short | grep -E 'lib/features/games/|auth_exports\.dart|lib/home/home_screen\.dart|lib/features/opinions/|games_contracts\.sql')
```
Expected: `All tests passed!`; the `comm` prints nothing; the `diff` prints nothing.

Manual check (development project, flag on, W1 deployed): a new number through A1–A5 lands in today's onboarding with the name step skipped and no second consent; the account has a date of birth (`select count(*) from public.account_birthdates where user_id = '<id>'` = 1); killing the app after the code is accepted and reopening returns to "Before you start"; a returning account sees "Welcome back, {name}."; an account on EULA v1 sees "We've updated our terms" first; an under-18 date of birth opens X1 with no code sent; the guest Tab 2 shows "Join Attune".

---

### Task 10: Migration 7, `otp_delivery`, and its contract (W2c; §4.2, §4.3 W2c, §4.6 `otp-purge`, §4.8, §7.1, review S-3, P-22, P-23)

**Files:**
- Create: `supabase/migrations/20261025110000_otp_delivery.sql`
- Create: `supabase/migrations/20261025110010_otp_delivery_grants.sql`
- Create: `supabase/tests/otp_delivery_contracts.sql`
- Modify: `scripts/local_pg_grants.sql` (append; edited, never run)

**Interfaces:**
- Consumes: W1's `private.bump_metric_internal(text)` and the `otp_refused:` prefix; `extensions.digest`; `cron.schedule` / `cron.unschedule` (the `20260907120000` pattern).
- Produces: tables `private.otp_delivery_intents (phone_hmac, channel, platform, locale, device_hash, created_at)`, `private.otp_intent_attempts (kind 'ip'|'number', key_hash, created_at)`, `private.otp_send_events (id, phone_hmac, channel, route, country_code, rule_prefix, created_at)`, `private.otp_routes (country_code, channel, provider 'twilio'|'arkesel'|'meta', priority, enabled)`, `private.otp_destination_rules (calling_code_prefix, rule, max_sends_per_hour)` with seeds; `public.otp_record_intent(p_phone_hmac text, p_channel text, p_platform text, p_locale text, p_device_hash text, p_ip_hash text DEFAULT NULL) → jsonb {stored, reason?}` (service_role); `public.otp_take_send_decision(p_phone_hmac text, p_country text, p_calling_prefix text) → jsonb {allowed, reason, channel, platform, routes:[{channel, provider}], retry_after_s}` (service_role); `private.otp_refusal(text, interval)`, `private.otp_routes_for(text, text)`, `private.otp_purge()` (no grants); cron `otp-purge` (`37 * * * *`). Refusal reasons: `invalid`, `blocked`, `number_hourly`, `number_daily`, `prefix_hourly`, `no_route`.

- [ ] **Step 1: Write the failing contract**

Create `supabase/tests/otp_delivery_contracts.sql` with exactly:

```sql
-- supabase/tests/otp_delivery_contracts.sql
-- Spec 1 W2c (§4.2, §4.3 W2c, §7.1, review S-3): phone-code delivery. A
-- channel request is honoured only when fresh, capped and from one device;
-- per-number, per-day and per-prefix limits; blocked destinations; routes
-- by country; retention; no client access. One BEGIN ... ROLLBACK.
-- Run only on attune_spec3a:
--   psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/otp_delivery_contracts.sql
-- Numbers never appear: fixtures are SHA-256 hex of a label, standing in
-- for the edge functions' HMACs. Every refusal is checked by its reason.
BEGIN;

CREATE FUNCTION pg_temp.h(p text) RETURNS text LANGUAGE sql AS $$
  SELECT encode(extensions.digest(p, 'sha256'), 'hex');
$$;

-- An intent written directly, at a chosen age. (plpgsql, so the helpers
-- can be created before the migration and section A says what is missing.)
CREATE FUNCTION pg_temp.intent(p_number text, p_device text, p_channel text, p_age interval,
                               p_platform text DEFAULT 'android') RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO private.otp_delivery_intents (phone_hmac, channel, platform, locale, device_hash, created_at)
  VALUES (pg_temp.h(p_number), p_channel, p_platform, 'en', pg_temp.h(p_device), clock_timestamp() - p_age);
END $$;

-- A past send, at a chosen age.
CREATE FUNCTION pg_temp.sent(p_number text, p_age interval, p_prefix text DEFAULT '+233') RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO private.otp_send_events (phone_hmac, channel, route, country_code, rule_prefix, created_at)
  VALUES (pg_temp.h(p_number), 'sms', 'twilio', 'GH', p_prefix, clock_timestamp() - p_age);
END $$;

CREATE FUNCTION pg_temp.decide(p_number text, p_country text DEFAULT 'GH', p_prefix text DEFAULT '+233244')
RETURNS jsonb LANGUAGE plpgsql AS $$
BEGIN
  RETURN public.otp_take_send_decision(pg_temp.h(p_number), p_country, p_prefix);
END $$;

-- =====================================================================
-- A. Objects and grants: the edge functions' two calls are service role
--    only; tables and helpers are closed to every client.
-- =====================================================================
DO $$
DECLARE
  v_table text;
BEGIN
  IF to_regprocedure('public.otp_take_send_decision(text,text,text)') IS NULL
     OR to_regprocedure('public.otp_record_intent(text,text,text,text,text,text)') IS NULL
     OR to_regprocedure('private.otp_purge()') IS NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: W2c objects are missing (otp_take_send_decision, otp_record_intent, otp_purge)';
  END IF;
  IF has_function_privilege('anon', 'public.otp_take_send_decision(text,text,text)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.otp_take_send_decision(text,text,text)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.otp_record_intent(text,text,text,text,text,text)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.otp_record_intent(text,text,text,text,text,text)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'private.otp_purge()', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.otp_take_send_decision(text,text,text)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.otp_record_intent(text,text,text,text,text,text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: OTP function grants are wrong';
  END IF;
  FOREACH v_table IN ARRAY ARRAY['private.otp_delivery_intents', 'private.otp_intent_attempts',
                                 'private.otp_send_events', 'private.otp_routes',
                                 'private.otp_destination_rules'] LOOP
    IF has_table_privilege('anon', v_table, 'SELECT') OR has_table_privilege('anon', v_table, 'INSERT')
       OR has_table_privilege('authenticated', v_table, 'SELECT')
       OR has_table_privilege('authenticated', v_table, 'INSERT')
       OR has_table_privilege('authenticated', v_table, 'UPDATE') THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: a client can reach %', v_table;
    END IF;
  END LOOP;
END $$;

-- =====================================================================
-- B. Intents (review S-3): a request, never a requirement.
-- =====================================================================
DO $$
DECLARE
  v jsonb;
BEGIN
  -- B1. No intent: SMS, on the country's routes (Ghana direct first).
  v := pg_temp.decide('b1');
  IF NOT (v ->> 'allowed')::boolean OR v ->> 'channel' <> 'sms' OR v ->> 'platform' <> 'other'
     OR v -> 'routes' <> '[{"channel": "sms", "provider": "arkesel"}, {"channel": "sms", "provider": "twilio"}]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: no intent did not mean SMS by the Ghana routes: %', v;
  END IF;

  -- B2. A fresh intent from one device moves the code, with SMS behind it.
  PERFORM pg_temp.intent('b2', 'phone-a', 'whatsapp', interval '5 seconds');
  v := pg_temp.decide('b2', 'GB', '+447911');
  IF v ->> 'channel' <> 'whatsapp' OR v ->> 'platform' <> 'android'
     OR v -> 'routes' <> '[{"channel": "whatsapp", "provider": "meta"}, {"channel": "sms", "provider": "twilio"}]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a fresh single-device intent was not honoured: %', v;
  END IF;

  -- B3. Older than 60 seconds: SMS (its platform still shapes the text).
  PERFORM pg_temp.intent('b3', 'phone-a', 'voice', interval '90 seconds');
  v := pg_temp.decide('b3');
  IF v ->> 'channel' <> 'sms' OR v ->> 'platform' <> 'android' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a stale intent moved the code: %', v;
  END IF;

  -- B4. Two devices asked for one number within 10 minutes: SMS.
  PERFORM pg_temp.intent('b4', 'phone-a', 'sms', interval '5 minutes');
  PERFORM pg_temp.intent('b4', 'stranger', 'whatsapp', interval '3 seconds');
  v := pg_temp.decide('b4');
  IF v ->> 'channel' <> 'sms' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an opposed intent moved the code: %', v;
  END IF;

  -- B5. An intent older than 10 minutes doesn't oppose anything.
  PERFORM pg_temp.intent('b5', 'old-phone', 'sms', interval '11 minutes');
  PERFORM pg_temp.intent('b5', 'phone-a', 'voice', interval '2 seconds');
  v := pg_temp.decide('b5');
  IF v ->> 'channel' <> 'voice'
     OR v -> 'routes' <> '[{"channel": "voice", "provider": "twilio"}, {"channel": "sms", "provider": "arkesel"}, {"channel": "sms", "provider": "twilio"}]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an expired intent still counted: %', v;
  END IF;
END $$;

DO $$
DECLARE
  v jsonb;
  v_i integer;
BEGIN
  -- B6. The 7th intent for a number in an hour isn't stored, and the send
  --     falls back to SMS (the six stored ones are no longer fresh).
  FOR v_i IN 1..6 LOOP
    v := public.otp_record_intent(pg_temp.h('b6'), 'whatsapp', 'ios', 'en-GB', pg_temp.h('phone-a'), NULL);
    IF NOT (v ->> 'stored')::boolean THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: intent % of 6 was refused: %', v_i, v;
    END IF;
  END LOOP;
  UPDATE private.otp_delivery_intents SET created_at = created_at - interval '2 minutes'
   WHERE phone_hmac = pg_temp.h('b6');
  v := public.otp_record_intent(pg_temp.h('b6'), 'whatsapp', 'ios', 'en-GB', pg_temp.h('phone-a'), NULL);
  IF (v ->> 'stored')::boolean OR v ->> 'reason' <> 'number_cap' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the 7th intent in an hour was stored: %', v;
  END IF;
  v := pg_temp.decide('b6');
  IF v ->> 'channel' <> 'sms' OR v ->> 'platform' <> 'ios' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: past the cap the send was not SMS: %', v;
  END IF;

  -- B7. One IP: 10 requests an hour, then nothing is stored.
  FOR v_i IN 1..10 LOOP
    v := public.otp_record_intent(pg_temp.h('b7-' || v_i), 'sms', 'android', 'en', pg_temp.h('d'), pg_temp.h('ip-1'));
  END LOOP;
  v := public.otp_record_intent(pg_temp.h('b7-11'), 'sms', 'android', 'en', pg_temp.h('d'), pg_temp.h('ip-1'));
  IF (v ->> 'stored')::boolean OR v ->> 'reason' <> 'ip_limit' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the 11th request from one IP was stored: %', v;
  END IF;

  -- B8. Malformed input is refused quietly, never raised.
  v := public.otp_record_intent('not-a-hash', 'whatsapp', 'ios', 'en', pg_temp.h('d'), NULL);
  IF (v ->> 'stored')::boolean OR v ->> 'reason' <> 'invalid' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a malformed intent was stored: %', v;
  END IF;
  v := public.otp_record_intent(pg_temp.h('b8'), 'carrier-pigeon', 'ios', 'en', pg_temp.h('d'), NULL);
  IF (v ->> 'stored')::boolean THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an unknown channel was stored';
  END IF;

  -- B9. A stored locale keeps only safe characters; an unknown platform is "other".
  PERFORM public.otp_record_intent(pg_temp.h('b9'), 'sms', 'symbian', 'en-GB<script>', pg_temp.h('d'), NULL);
  IF NOT EXISTS (SELECT 1 FROM private.otp_delivery_intents
                  WHERE phone_hmac = pg_temp.h('b9') AND platform = 'other' AND locale = 'en-GBscript') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: platform or locale was stored as sent';
  END IF;
END $$;

-- =====================================================================
-- C. Limits and destinations.
-- =====================================================================
DO $$
DECLARE
  v jsonb;
  v_i integer;
  v_before bigint;
  v_after bigint;
BEGIN
  -- C1. Six sends an hour per number; the 7th waits for the oldest to age out.
  FOR v_i IN 1..6 LOOP
    PERFORM pg_temp.sent('c1', make_interval(mins => 50 - v_i));
  END LOOP;
  SELECT coalesce(sum(count), 0) INTO v_before FROM public.metric_counters
   WHERE key = 'otp_refused:number_hourly';
  v := pg_temp.decide('c1');
  SELECT coalesce(sum(count), 0) INTO v_after FROM public.metric_counters
   WHERE key = 'otp_refused:number_hourly';
  IF (v ->> 'allowed')::boolean OR v ->> 'reason' <> 'number_hourly'
     OR (v ->> 'retry_after_s')::int NOT BETWEEN 600 AND 780 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the 7th send in an hour was not refused with its wait: %', v;
  END IF;
  IF v_after <> v_before + 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a refusal did not bump otp_refused:number_hourly';
  END IF;
  IF (SELECT count(*) FROM private.otp_send_events WHERE phone_hmac = pg_temp.h('c1')) <> 6 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a refused send was recorded';
  END IF;

  -- C2. Fifteen a day per number.
  FOR v_i IN 1..15 LOOP
    PERFORM pg_temp.sent('c2', make_interval(hours => 2 + v_i));
  END LOOP;
  v := pg_temp.decide('c2');
  IF (v ->> 'allowed')::boolean OR v ->> 'reason' <> 'number_daily' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the 16th send in a day was not refused: %', v;
  END IF;

  -- C3. A prefix's hourly cap, across numbers.
  INSERT INTO private.otp_destination_rules VALUES ('+299999', 'allow', 2);
  PERFORM pg_temp.sent('c3-a', interval '10 minutes', '+299999');
  PERFORM pg_temp.sent('c3-b', interval '5 minutes', '+299999');
  v := pg_temp.decide('c3-c', 'GL', '+2999991');
  IF (v ->> 'allowed')::boolean OR v ->> 'reason' <> 'prefix_hourly' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a prefix past its hourly cap was sent to: %', v;
  END IF;

  -- C4. +999 (parked numbers) and the longest matching prefix decide.
  v := pg_temp.decide('c4', 'XX', '+999123');
  IF (v ->> 'allowed')::boolean OR v ->> 'reason' <> 'blocked' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: +999 was not blocked: %', v;
  END IF;
  v := pg_temp.decide('c4-b', 'GB', '+447012');
  IF (v ->> 'allowed')::boolean OR v ->> 'reason' <> 'blocked' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: +4470 was not blocked under +44: %', v;
  END IF;
  v := pg_temp.decide('c4-c', 'GB', '+447911');
  IF NOT (v ->> 'allowed')::boolean THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a UK mobile was blocked: %', v;
  END IF;

  -- C5. An allowed send is recorded with its route, country and rule.
  IF NOT EXISTS (SELECT 1 FROM private.otp_send_events
                  WHERE phone_hmac = pg_temp.h('c4-c') AND route = 'twilio'
                    AND country_code = 'GB' AND rule_prefix = '+44' AND channel = 'sms') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the allowed send was not recorded as sent';
  END IF;

  -- C6. A switched-off route is skipped; with no SMS route at all, refused.
  UPDATE private.otp_routes SET enabled = false WHERE country_code = 'GH' AND provider = 'arkesel';
  v := pg_temp.decide('c6');
  IF v -> 'routes' <> '[{"channel": "sms", "provider": "twilio"}]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a disabled route was used: %', v;
  END IF;
  UPDATE private.otp_routes SET enabled = false WHERE channel = 'sms';
  v := pg_temp.decide('c6-b');
  IF (v ->> 'allowed')::boolean OR v ->> 'reason' <> 'no_route' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a send with no route was allowed: %', v;
  END IF;
  UPDATE private.otp_routes SET enabled = true;

  -- C7. A malformed prefix or HMAC is refused, never raised.
  v := public.otp_take_send_decision('nope', 'GH', '+233');
  IF v ->> 'reason' <> 'invalid' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a malformed decision request was not refused: %', v;
  END IF;
END $$;

-- =====================================================================
-- D. Retention and its cron (§4.6, §4.8).
-- =====================================================================
DO $$
BEGIN
  PERFORM pg_temp.intent('d-old', 'x', 'sms', interval '11 minutes');
  PERFORM pg_temp.intent('d-new', 'x', 'sms', interval '1 minute');
  PERFORM pg_temp.sent('d-old', interval '25 hours');
  PERFORM pg_temp.sent('d-new', interval '23 hours');
  INSERT INTO private.otp_intent_attempts VALUES ('ip', pg_temp.h('d-old'), clock_timestamp() - interval '61 minutes');
  PERFORM private.otp_purge();
  IF EXISTS (SELECT 1 FROM private.otp_delivery_intents WHERE phone_hmac = pg_temp.h('d-old'))
     OR NOT EXISTS (SELECT 1 FROM private.otp_delivery_intents WHERE phone_hmac = pg_temp.h('d-new'))
     OR EXISTS (SELECT 1 FROM private.otp_send_events WHERE phone_hmac = pg_temp.h('d-old'))
     OR NOT EXISTS (SELECT 1 FROM private.otp_send_events WHERE phone_hmac = pg_temp.h('d-new'))
     OR EXISTS (SELECT 1 FROM private.otp_intent_attempts WHERE key_hash = pg_temp.h('d-old')) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: otp_purge kept or removed the wrong rows';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM cron.job
                  WHERE jobname = 'otp-purge' AND schedule = '37 * * * *'
                    AND command = 'SELECT private.otp_purge()') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: otp-purge is not scheduled';
  END IF;
END $$;

ROLLBACK;
```

- [ ] **Step 2: Run it to verify it fails**

```bash
cd /Users/user/attune
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/otp_delivery_contracts.sql; echo "exit=$?"
```
Expected: `ERROR:  CONTRACT VIOLATED: W2c objects are missing (otp_take_send_decision, otp_record_intent, otp_purge)`, `exit=3`.

- [ ] **Step 3: Write the migration**

Create `supabase/migrations/20261025110000_otp_delivery.sql` with exactly:

```sql
-- Spec 1 W2c, migration 7 (spec §4.7 #7): otp_delivery.
--   * private.otp_delivery_intents: a request to send a number's next code
--     by WhatsApp or a call instead of SMS. Never a requirement (review
--     S-3): honoured only while under 60 s old, within 6 a number an hour,
--     and when every intent for the number in 10 minutes came from one
--     device (its hashed nonce). Anything doubtful goes by SMS.
--   * private.otp_intent_attempts: the per-IP (10 an hour) and per-number
--     (6 an hour) intent counters, so intents themselves can go after 10
--     minutes.
--   * private.otp_send_events: the per-number (6 an hour, 15 a day) and
--     per-prefix hourly send limits; kept 24 hours.
--   * private.otp_routes / private.otp_destination_rules: providers by
--     country and channel, and allow/block rules by calling-code prefix
--     (longest match wins; '*' is the default).
--   * public.otp_record_intent, public.otp_take_send_decision: service role
--     only (the otp-delivery-intent and send-sms-hook edge functions);
--     private.otp_purge and its own cron, otp-purge (W2c tables only, §4.6).
-- No phone number is stored anywhere: only HMACs (OTP_HMAC_KEY, held by the
-- edge functions) and SHA-256 hashes.
-- Grants in 20261025110010_otp_delivery_grants.sql.
BEGIN;
SET LOCAL lock_timeout = '5s';

CREATE TABLE IF NOT EXISTS private.otp_delivery_intents (
  phone_hmac text NOT NULL CONSTRAINT otp_delivery_intents_phone_hmac_check
    CHECK (phone_hmac ~ '^[0-9a-f]{64}$'),
  channel text NOT NULL CONSTRAINT otp_delivery_intents_channel_check
    CHECK (channel IN ('sms', 'whatsapp', 'voice')),
  platform text NOT NULL CONSTRAINT otp_delivery_intents_platform_check
    CHECK (platform IN ('ios', 'android', 'other')),
  locale text NOT NULL DEFAULT '' CONSTRAINT otp_delivery_intents_locale_check
    CHECK (locale ~ '^[A-Za-z0-9_-]{0,35}$'),
  device_hash text NOT NULL CONSTRAINT otp_delivery_intents_device_hash_check
    CHECK (device_hash ~ '^[0-9a-f]{64}$'),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY (phone_hmac, created_at)
);

CREATE TABLE IF NOT EXISTS private.otp_intent_attempts (
  kind text NOT NULL CONSTRAINT otp_intent_attempts_kind_check CHECK (kind IN ('ip', 'number')),
  key_hash text NOT NULL CONSTRAINT otp_intent_attempts_key_hash_check
    CHECK (key_hash ~ '^[0-9a-f]{64}$'),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE INDEX IF NOT EXISTS otp_intent_attempts_key_idx
  ON private.otp_intent_attempts (kind, key_hash, created_at);

CREATE TABLE IF NOT EXISTS private.otp_send_events (
  id bigserial PRIMARY KEY,
  phone_hmac text NOT NULL CONSTRAINT otp_send_events_phone_hmac_check
    CHECK (phone_hmac ~ '^[0-9a-f]{64}$'),
  channel text NOT NULL CONSTRAINT otp_send_events_channel_check
    CHECK (channel IN ('sms', 'whatsapp', 'voice')),
  route text NOT NULL,
  country_code text NOT NULL CONSTRAINT otp_send_events_country_check
    CHECK (country_code ~ '^[A-Z]{2}$'),
  rule_prefix text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE INDEX IF NOT EXISTS otp_send_events_phone_idx ON private.otp_send_events (phone_hmac, created_at);
CREATE INDEX IF NOT EXISTS otp_send_events_prefix_idx ON private.otp_send_events (rule_prefix, created_at);
CREATE INDEX IF NOT EXISTS otp_send_events_created_idx ON private.otp_send_events (created_at);

CREATE TABLE IF NOT EXISTS private.otp_routes (
  country_code text NOT NULL CONSTRAINT otp_routes_country_check
    CHECK (country_code ~ '^([A-Z]{2}|\*)$'),
  channel text NOT NULL CONSTRAINT otp_routes_channel_check
    CHECK (channel IN ('sms', 'whatsapp', 'voice')),
  -- One adapter each in supabase/functions/send-sms-hook/providers.ts.
  provider text NOT NULL CONSTRAINT otp_routes_provider_check
    CHECK (provider IN ('twilio', 'arkesel', 'meta')),
  priority smallint NOT NULL DEFAULT 1,
  enabled boolean NOT NULL DEFAULT true,
  PRIMARY KEY (country_code, channel, provider)
);

CREATE TABLE IF NOT EXISTS private.otp_destination_rules (
  calling_code_prefix text PRIMARY KEY CONSTRAINT otp_destination_rules_prefix_check
    CHECK (calling_code_prefix ~ '^(\+[0-9]{1,6}|\*)$'),
  rule text NOT NULL CONSTRAINT otp_destination_rules_rule_check CHECK (rule IN ('allow', 'block')),
  max_sends_per_hour integer CONSTRAINT otp_destination_rules_cap_check
    CHECK (max_sends_per_hour IS NULL OR max_sends_per_hour > 0)
);

-- Routes: Ghana direct first for GH, the global provider everywhere else
-- (spec §4.5). The owner changes these rows, not code, to re-route.
INSERT INTO private.otp_routes (country_code, channel, provider, priority) VALUES
  ('GH', 'sms', 'arkesel', 1),
  ('GH', 'sms', 'twilio', 2),
  ('*', 'sms', 'twilio', 1),
  ('*', 'whatsapp', 'meta', 1),
  ('*', 'voice', 'twilio', 1)
ON CONFLICT (country_code, channel, provider) DO NOTHING;

-- Destinations (spec §4.2): +999 is the parked-number range (W6a); the
-- other blocks are the international premium-rate and satellite ranges
-- toll fraud uses, plus the UK personal-number and premium ranges and the
-- North American 900s. The owner adds the provider's fraud list. Launch
-- countries get explicit hourly caps; every other prefix uses '*'.
INSERT INTO private.otp_destination_rules (calling_code_prefix, rule, max_sends_per_hour) VALUES
  ('+999', 'block', NULL),
  ('+979', 'block', NULL),
  ('+881', 'block', NULL),
  ('+882', 'block', NULL),
  ('+883', 'block', NULL),
  ('+870', 'block', NULL),
  ('+4470', 'block', NULL),
  ('+449', 'block', NULL),
  ('+1900', 'block', NULL),
  ('+233', 'allow', 1000),
  ('+44', 'allow', 1000),
  ('+1', 'allow', 1000),
  ('+234', 'allow', 300),
  ('+254', 'allow', 300),
  ('*', 'allow', 100)
ON CONFLICT (calling_code_prefix) DO NOTHING;

-- One refusal: counted (otp_refused:{reason}) and shaped for the hook.
CREATE OR REPLACE FUNCTION private.otp_refusal(p_reason text, p_wait interval)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  PERFORM private.bump_metric_internal('otp_refused:' || p_reason);
  RETURN jsonb_build_object(
    'allowed', false,
    'reason', p_reason,
    'channel', NULL,
    'platform', NULL,
    'routes', '[]'::jsonb,
    'retry_after_s', CASE WHEN p_wait IS NULL THEN NULL
                          ELSE greatest(1, ceil(extract(epoch FROM p_wait))::integer) END);
END;
$$;

-- The ordered providers for a channel: the country's own rows first, then
-- the defaults, each provider once.
CREATE OR REPLACE FUNCTION private.otp_routes_for(p_country text, p_channel text)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT coalesce(
    jsonb_agg(jsonb_build_object('channel', p_channel, 'provider', x.provider)
              ORDER BY x.specific DESC, x.priority, x.provider),
    '[]'::jsonb)
    FROM (SELECT DISTINCT ON (r.provider) r.provider, r.priority, (r.country_code <> '*') AS specific
            FROM private.otp_routes AS r
           WHERE r.enabled AND r.channel = p_channel AND r.country_code IN (p_country, '*')
           ORDER BY r.provider, (r.country_code <> '*') DESC, r.priority) AS x;
$$;

-- otp-delivery-intent (spec §4.3 W2c): stores a channel request, unless the
-- IP has made 10 requests this hour or the number already has 6 stored.
-- Never raises: the endpoint answers 204 whatever happens here.
CREATE OR REPLACE FUNCTION public.otp_record_intent(
  p_phone_hmac text,
  p_channel text,
  p_platform text,
  p_locale text,
  p_device_hash text,
  p_ip_hash text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_now constant timestamptz := clock_timestamp();
BEGIN
  IF p_phone_hmac IS NULL OR p_phone_hmac !~ '^[0-9a-f]{64}$'
     OR p_device_hash IS NULL OR p_device_hash !~ '^[0-9a-f]{64}$'
     OR p_channel IS NULL OR p_channel NOT IN ('sms', 'whatsapp', 'voice')
     OR (p_ip_hash IS NOT NULL AND p_ip_hash !~ '^[0-9a-f]{64}$') THEN
    RETURN jsonb_build_object('stored', false, 'reason', 'invalid');
  END IF;

  IF p_ip_hash IS NOT NULL THEN
    INSERT INTO private.otp_intent_attempts (kind, key_hash, created_at)
    VALUES ('ip', p_ip_hash, v_now);
    IF (SELECT count(*) FROM private.otp_intent_attempts AS a
         WHERE a.kind = 'ip' AND a.key_hash = p_ip_hash
           AND a.created_at > v_now - interval '1 hour') > 10 THEN
      RETURN jsonb_build_object('stored', false, 'reason', 'ip_limit');
    END IF;
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended('otp:' || p_phone_hmac, 0));
  IF (SELECT count(*) FROM private.otp_intent_attempts AS a
       WHERE a.kind = 'number' AND a.key_hash = p_phone_hmac
         AND a.created_at > v_now - interval '1 hour') >= 6 THEN
    RETURN jsonb_build_object('stored', false, 'reason', 'number_cap');
  END IF;

  DELETE FROM private.otp_delivery_intents AS i
   WHERE i.phone_hmac = p_phone_hmac AND i.created_at < v_now - interval '10 minutes';
  INSERT INTO private.otp_delivery_intents (phone_hmac, channel, platform, locale, device_hash, created_at)
  VALUES (p_phone_hmac,
          p_channel,
          CASE WHEN p_platform IN ('ios', 'android') THEN p_platform ELSE 'other' END,
          left(regexp_replace(coalesce(p_locale, ''), '[^A-Za-z0-9_-]', '', 'g'), 35),
          p_device_hash,
          v_now)
  ON CONFLICT (phone_hmac, created_at) DO NOTHING;
  INSERT INTO private.otp_intent_attempts (kind, key_hash, created_at)
  VALUES ('number', p_phone_hmac, v_now);
  RETURN jsonb_build_object('stored', true);
END;
$$;

-- send-sms-hook (spec §4.3 W2c): may this number get a code now, by which
-- channel, through which providers? The destination rule (longest prefix),
-- then 6 an hour and 15 a day per number, then the prefix's hourly cap,
-- then the channel: the newest intent counts only if it is under 60 s old
-- and every intent for the number in the last 10 minutes has the same
-- device hash; otherwise SMS (review S-3). Records the send it allows.
CREATE OR REPLACE FUNCTION public.otp_take_send_decision(
  p_phone_hmac text,
  p_country text,
  p_calling_prefix text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_now constant timestamptz := clock_timestamp();
  v_country constant text :=
    CASE WHEN upper(coalesce(p_country, '')) ~ '^[A-Z]{2}$' THEN upper(p_country) ELSE 'XX' END;
  v_prefix constant text := coalesce(p_calling_prefix, '');
  v_rule private.otp_destination_rules%ROWTYPE;
  v_rule_prefix text;
  v_cap integer;
  v_count integer;
  v_oldest timestamptz;
  v_newest private.otp_delivery_intents%ROWTYPE;
  v_devices integer;
  v_channel text := 'sms';
  v_platform text := 'other';
  v_routes jsonb;
  v_fallback jsonb := '[]'::jsonb;
BEGIN
  IF p_phone_hmac IS NULL OR p_phone_hmac !~ '^[0-9a-f]{64}$' OR v_prefix !~ '^\+[0-9]{1,15}$' THEN
    RETURN private.otp_refusal('invalid', NULL);
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('otp:' || p_phone_hmac, 0));

  SELECT * INTO v_rule FROM private.otp_destination_rules AS r
   WHERE r.calling_code_prefix <> '*'
     AND left(v_prefix, length(r.calling_code_prefix)) = r.calling_code_prefix
   ORDER BY length(r.calling_code_prefix) DESC
   LIMIT 1;
  IF NOT FOUND THEN
    SELECT * INTO v_rule FROM private.otp_destination_rules AS r WHERE r.calling_code_prefix = '*';
  END IF;
  v_rule_prefix := coalesce(v_rule.calling_code_prefix, '*');
  IF v_rule.rule = 'block' THEN
    RETURN private.otp_refusal('blocked', NULL);
  END IF;

  SELECT count(*), min(e.created_at) INTO v_count, v_oldest
    FROM private.otp_send_events AS e
   WHERE e.phone_hmac = p_phone_hmac AND e.created_at > v_now - interval '1 hour';
  IF v_count >= 6 THEN
    RETURN private.otp_refusal('number_hourly', v_oldest + interval '1 hour' - v_now);
  END IF;
  SELECT count(*), min(e.created_at) INTO v_count, v_oldest
    FROM private.otp_send_events AS e
   WHERE e.phone_hmac = p_phone_hmac AND e.created_at > v_now - interval '24 hours';
  IF v_count >= 15 THEN
    RETURN private.otp_refusal('number_daily', v_oldest + interval '24 hours' - v_now);
  END IF;

  v_cap := coalesce(
    v_rule.max_sends_per_hour,
    (SELECT r.max_sends_per_hour FROM private.otp_destination_rules AS r WHERE r.calling_code_prefix = '*'));
  IF v_cap IS NOT NULL THEN
    SELECT count(*), min(e.created_at) INTO v_count, v_oldest
      FROM private.otp_send_events AS e
     WHERE e.rule_prefix = v_rule_prefix AND e.created_at > v_now - interval '1 hour';
    IF v_count >= v_cap THEN
      RETURN private.otp_refusal('prefix_hourly', v_oldest + interval '1 hour' - v_now);
    END IF;
  END IF;

  SELECT * INTO v_newest FROM private.otp_delivery_intents AS i
   WHERE i.phone_hmac = p_phone_hmac AND i.created_at > v_now - interval '10 minutes'
   ORDER BY i.created_at DESC
   LIMIT 1;
  IF FOUND THEN
    v_platform := v_newest.platform;
    SELECT count(DISTINCT i.device_hash) INTO v_devices
      FROM private.otp_delivery_intents AS i
     WHERE i.phone_hmac = p_phone_hmac AND i.created_at > v_now - interval '10 minutes';
    IF v_newest.created_at > v_now - interval '60 seconds' AND v_devices = 1 THEN
      v_channel := v_newest.channel;
    END IF;
  END IF;

  v_routes := private.otp_routes_for(v_country, v_channel);
  IF v_channel <> 'sms' AND jsonb_array_length(v_routes) = 0 THEN
    v_channel := 'sms';
    v_routes := private.otp_routes_for(v_country, 'sms');
  END IF;
  IF v_channel <> 'sms' THEN
    v_fallback := private.otp_routes_for(v_country, 'sms');
  END IF;
  IF jsonb_array_length(v_routes) + jsonb_array_length(v_fallback) = 0 THEN
    RETURN private.otp_refusal('no_route', NULL);
  END IF;

  INSERT INTO private.otp_send_events (phone_hmac, channel, route, country_code, rule_prefix, created_at)
  VALUES (p_phone_hmac, v_channel, (v_routes || v_fallback) -> 0 ->> 'provider', v_country, v_rule_prefix, v_now);

  RETURN jsonb_build_object(
    'allowed', true,
    'reason', NULL,
    'channel', v_channel,
    'platform', v_platform,
    'routes', v_routes || v_fallback,
    'retry_after_s', NULL);
END;
$$;

-- Retention (spec §4.8): intents 10 minutes, counters 1 hour, send events
-- 24 hours. Names only W2c tables (§4.6, review I-1).
CREATE OR REPLACE FUNCTION private.otp_purge()
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
AS $$
  DELETE FROM private.otp_delivery_intents WHERE created_at < clock_timestamp() - interval '10 minutes';
  DELETE FROM private.otp_intent_attempts WHERE created_at < clock_timestamp() - interval '1 hour';
  DELETE FROM private.otp_send_events WHERE created_at < clock_timestamp() - interval '24 hours';
$$;

DO $$
BEGIN
  PERFORM cron.unschedule('otp-purge');
EXCEPTION WHEN OTHERS THEN
  NULL;
END $$;
SELECT cron.schedule('otp-purge', '37 * * * *', $cron$SELECT private.otp_purge()$cron$);

-- Revoked here as well as in the twin (the W1 precedent): the hosted
-- default privileges grant a new function and a new table to anon and
-- authenticated, and a late twin must not leave a code's channel or a
-- send limit writable by a client.
REVOKE ALL ON private.otp_delivery_intents, private.otp_intent_attempts, private.otp_send_events,
              private.otp_routes, private.otp_destination_rules
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON SEQUENCE private.otp_send_events_id_seq FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.otp_refusal(text, interval) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.otp_routes_for(text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.otp_purge() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.otp_record_intent(text, text, text, text, text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.otp_take_send_decision(text, text, text) FROM PUBLIC, anon, authenticated;

COMMIT;
```

- [ ] **Step 4: Write the grants twin**

Create `supabase/migrations/20261025110010_otp_delivery_grants.sql` with exactly:

```sql
-- Spec 1 W2c: grants for 20261025110000_otp_delivery.sql. The two decisions
-- are the edge functions' (service role); everything else is server-only.
BEGIN;
REVOKE ALL ON private.otp_delivery_intents, private.otp_intent_attempts, private.otp_send_events,
              private.otp_routes, private.otp_destination_rules
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON SEQUENCE private.otp_send_events_id_seq FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.otp_refusal(text, interval) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.otp_routes_for(text, text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.otp_purge() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.otp_record_intent(text, text, text, text, text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.otp_take_send_decision(text, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.otp_record_intent(text, text, text, text, text, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.otp_take_send_decision(text, text, text) TO service_role;
COMMIT;
```

- [ ] **Step 5: Apply both twice, then run the contract**

```bash
cd /Users/user/attune
for i in 1 2; do
  psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/migrations/20261025110000_otp_delivery.sql > /dev/null; echo "migration exit=$?"
  psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/migrations/20261025110010_otp_delivery_grants.sql; echo "grants exit=$?"
done
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/otp_delivery_contracts.sql; echo "exit=$?"
psql -X -d attune_spec3a -Atc "select jobname, schedule, command from cron.job where jobname = 'otp-purge'"
```
Expected: four `… exit=0` (the second pass prints `NOTICE: relation … already exists, skipping` lines); `exit=0` with no `ERROR`; `otp-purge|37 * * * *|SELECT private.otp_purge()`.

- [ ] **Step 6: Mutation check (spec §7.4: the decision uses the newest intent regardless of device or age)**

```bash
cd /Users/user/attune
sed "s/    IF v_newest.created_at > v_now - interval '60 seconds' AND v_devices = 1 THEN/    IF true THEN/" supabase/migrations/20261025110000_otp_delivery.sql > .superpowers/sdd/2026-10-25-spec1-w2/otp_mutant.sql
grep -c "IF true THEN" .superpowers/sdd/2026-10-25-spec1-w2/otp_mutant.sql
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f .superpowers/sdd/2026-10-25-spec1-w2/otp_mutant.sql > /dev/null
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/otp_delivery_contracts.sql 2>&1 | grep ERROR
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/migrations/20261025110000_otp_delivery.sql > /dev/null; echo "restored exit=$?"
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/otp_delivery_contracts.sql; echo "exit=$?"
rm .superpowers/sdd/2026-10-25-spec1-w2/otp_mutant.sql
```
Expected: `1`; then `ERROR:  CONTRACT VIOLATED: a stale intent moved the code: {"reason": null, "routes": [{"channel": "voice", "provider": "twilio"}, …], "allowed": true, "channel": "voice", …}`; `restored exit=0`; `exit=0`.

- [ ] **Step 7: Add the twin to the local harness (edit only, never run)**

In `scripts/local_pg_grants.sql`, at the end:

The edit. Replace exactly:

```sql
-- Spec 1 W1c: identity health and the unfinished sign-up list, service role only.
\i supabase/migrations/20261025100510_identity_health_grants.sql
```

with:

```sql
-- Spec 1 W1c: identity health and the unfinished sign-up list, service role only.
\i supabase/migrations/20261025100510_identity_health_grants.sql

-- Spec 1 W2c: phone-code delivery is server-only; the two decisions are the
-- edge functions' (service role).
\i supabase/migrations/20261025110010_otp_delivery_grants.sql
```

- [ ] **Step 8: Run tests**

```bash
cd /Users/user/attune
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/identity_foundation_contracts.sql; echo "identity exit=$?"
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/otp_delivery_contracts.sql; echo "otp exit=$?"
```
Expected: `identity exit=0`; `otp exit=0`.

---

### Task 11: The shared phone helpers, Standard Webhooks, and `otp-delivery-intent` (W2c; §3.3 A3, §4.1 rule 5, §4.5, §7.2, P-24, P-25, P-28)

**Files:**
- Create: `supabase/functions/_shared/otp_phone.ts`, `supabase/functions/_shared/otp_phone.test.ts`
- Create: `supabase/functions/_shared/standard_webhooks.ts`, `supabase/functions/_shared/standard_webhooks.test.ts`
- Create: `supabase/functions/otp-delivery-intent/handler.ts`, `index.ts`, `handler.test.ts`
- Modify: `supabase/config.toml` (append)

**Interfaces:**
- Consumes: `constantTimeEqual`, `serviceRoleClient` (`_shared/attune_auth.ts`); Task 10's `otp_record_intent`.
- Produces: `canonicalPhone(raw: unknown) → string | null` (`'+'` and digits), `hmacHex(key, message)`, `sha256Hex(bytes)`, `phoneHmac(key, phone)`, `callingPrefix(phone)` (first 7 characters), `countryOf(phone)` (`GH|NG|KE|GB|CA|US|XX`), `decodeNonce(raw) → Uint8Array | null`; `TOLERANCE_SECONDS`, `verifyStandardWebhook(secret, headers, body, nowSeconds) → Promise<boolean>`; `interface IntentRecord`, `interface IntentDeps {hmacKey, record, log}`, `handleIntent(req, deps) → Response` (always 204).

- [ ] **Step 1: Write the failing tests**

Create `supabase/functions/_shared/otp_phone.test.ts` with exactly:

```ts
// Spec 1 W2c: the phone helpers the two code functions share.
import { callingPrefix, canonicalPhone, countryOf, decodeNonce, phoneHmac, sha256Hex } from "./otp_phone.ts";

function eq(actual: unknown, expected: unknown, what: string) {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(`${what}: expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`);
  }
}

Deno.test("the app's +E.164 and Auth's bare digits are one number", async () => {
  eq(canonicalPhone("+233 24 412 3456"), "+233244123456", "app form");
  eq(canonicalPhone("233244123456"), "+233244123456", "Auth form");
  eq(
    await phoneHmac("k", canonicalPhone("+233 24 412 3456")!),
    await phoneHmac("k", canonicalPhone("233244123456")!),
    "same HMAC",
  );
  eq(canonicalPhone("12"), null, "too short");
  eq(canonicalPhone("0244123456"), null, "a national number is not E.164");
  eq(canonicalPhone(42), null, "not a string");
});

Deno.test("country and prefix, never the whole number", () => {
  eq(countryOf("+233244123456"), "GH", "Ghana");
  eq(countryOf("+447911123456"), "GB", "UK");
  eq(countryOf("+14165550123"), "CA", "Toronto");
  eq(countryOf("+12025550123"), "US", "Washington");
  eq(countryOf("+2348031234567"), "NG", "Nigeria");
  eq(countryOf("+33612345678"), "XX", "elsewhere");
  eq(callingPrefix("+233244123456"), "+233244", "prefix");
});

Deno.test("a device nonce is 16 bytes of base64url, hashed", async () => {
  const bytes = new Uint8Array(16).fill(7);
  const nonce = btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
  eq(decodeNonce(nonce)?.length, 16, "decoded");
  eq(decodeNonce("short"), null, "too short");
  eq(decodeNonce(undefined), null, "missing");
  eq((await sha256Hex(bytes)).length, 64, "hex digest");
});
```

Create `supabase/functions/_shared/standard_webhooks.test.ts` with exactly:

```ts
// Spec 1 W2c: Standard Webhooks signatures (Auth's HTTP hooks).
import { verifyStandardWebhook } from "./standard_webhooks.ts";

// The published test vector.
const SECRET = "v1,whsec_MfKQ9r8GKYqrTwjUPD8ILPZIo2LaLaSw";
const BODY = '{"test": 2432232314}';
const headers = (signature: string, timestamp = "1614265330") =>
  new Headers({
    "webhook-id": "msg_p5jXN8AQM9LWM0D4loKWxJek",
    "webhook-timestamp": timestamp,
    "webhook-signature": signature,
  });
const GOOD = "v1,g0hM9SsE+OTPJTGt/tmIKtSyZlE3uFJELVlNIOLJ1OE=";

Deno.test("the published vector verifies, alone or among others", async () => {
  if (!(await verifyStandardWebhook(SECRET, headers(GOOD), BODY, 1614265330))) {
    throw new Error("the vector failed");
  }
  if (!(await verifyStandardWebhook(SECRET, headers(`v1,AAAA ${GOOD}`), BODY, 1614265330))) {
    throw new Error("a second signature was ignored");
  }
});

Deno.test("a changed body, a wrong secret, an old timestamp or no header fails", async () => {
  const checks: [string, Promise<boolean>][] = [
    ["body", verifyStandardWebhook(SECRET, headers(GOOD), '{"test": 1}', 1614265330)],
    ["secret", verifyStandardWebhook("v1,whsec_AAAAAAAAAAAAAAAAAAAAAAAA", headers(GOOD), BODY, 1614265330)],
    ["too old", verifyStandardWebhook(SECRET, headers(GOOD), BODY, 1614265330 + 301)],
    ["no signature", verifyStandardWebhook(SECRET, new Headers(), BODY, 1614265330)],
    ["wrong version", verifyStandardWebhook(SECRET, headers(GOOD.replace("v1,", "v2,")), BODY, 1614265330)],
  ];
  for (const [what, check] of checks) {
    if (await check) throw new Error(`${what}: verified`);
  }
});
```

Create `supabase/functions/otp-delivery-intent/handler.test.ts` with exactly:

```ts
// Spec 1 W2c (§4.5, §7.2): the delivery intent endpoint.
import { handleIntent, type IntentRecord } from "./handler.ts";

const NONCE = btoa(String.fromCharCode(...new Uint8Array(16).fill(9)))
  .replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");

function rig(hmacKey: string | null = "test-key", fail = false) {
  const records: IntentRecord[] = [];
  const logs: string[] = [];
  return {
    records,
    logs,
    deps: {
      hmacKey: hmacKey ?? undefined,
      record: (intent: IntentRecord) => {
        if (fail) return Promise.reject(new Error("db down"));
        records.push(intent);
        return Promise.resolve();
      },
      log: (category: string) => logs.push(category),
    },
  };
}

const request = (body: unknown, ip = "203.0.113.9") =>
  new Request("http://x/otp-delivery-intent", {
    method: "POST",
    headers: { "x-forwarded-for": `${ip}, 10.0.0.1` },
    body: typeof body === "string" ? body : JSON.stringify(body),
  });

const good = { phone: "+233 24 412 3456", channel: "whatsapp", platform: "android", locale: "en-GH", device_nonce: NONCE };

Deno.test("a good request is stored as hashes only, and answered 204", async () => {
  const r = rig();
  const response = await handleIntent(request(good), r.deps);
  if (response.status !== 204) throw new Error(`status ${response.status}`);
  const stored = r.records[0];
  if (!stored || stored.p_channel !== "whatsapp" || stored.p_platform !== "android") {
    throw new Error(`stored ${JSON.stringify(stored)}`);
  }
  for (const value of [stored.p_phone_hmac, stored.p_device_hash, stored.p_ip_hash]) {
    if (!/^[0-9a-f]{64}$/.test(value)) throw new Error(`not a hash: ${value}`);
  }
  const text = JSON.stringify(stored) + r.logs.join(" ");
  for (const secret of ["233244123456", "203.0.113.9", NONCE]) {
    if (text.includes(secret)) throw new Error(`${secret} leaked`);
  }
});

Deno.test("204 whatever happens, and nothing stored for a bad request", async () => {
  for (const body of [
    "{not json",
    { ...good, device_nonce: undefined },
    { ...good, device_nonce: "too-short" },
    { ...good, channel: "pigeon" },
    { ...good, phone: "12" },
  ]) {
    const r = rig();
    const response = await handleIntent(request(body), r.deps);
    if (response.status !== 204) throw new Error(`status ${response.status} for ${JSON.stringify(body)}`);
    if (r.records.length !== 0) throw new Error(`stored ${JSON.stringify(body)}`);
  }
  const noKey = rig(null);
  if ((await handleIntent(request(good), noKey.deps)).status !== 204 || noKey.records.length !== 0) {
    throw new Error("stored without OTP_HMAC_KEY");
  }
  const failing = rig("k", true);
  if ((await handleIntent(request(good), failing.deps)).status !== 204) {
    throw new Error("a database failure changed the answer");
  }
});

Deno.test("an unknown platform is other; the locale is cut to 35 characters", async () => {
  const r = rig();
  await handleIntent(request({ ...good, platform: "symbian", locale: "x".repeat(60) }), r.deps);
  if (r.records[0].p_platform !== "other" || r.records[0].p_locale.length !== 35) {
    throw new Error(JSON.stringify(r.records[0]));
  }
});

Deno.test("the endpoint logs nothing but categories", async () => {
  const handler = await Deno.readTextFile(new URL("./handler.ts", import.meta.url));
  const index = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
  if (/console\./.test(handler)) throw new Error("the handler logs directly");
  if (/console\.log\([^)]*(phone|nonce|ip)\b/.test(index)) throw new Error("index logs a value");
});
```

```bash
cd /Users/user/attune/supabase/functions
deno test --allow-read _shared/otp_phone.test.ts _shared/standard_webhooks.test.ts otp-delivery-intent/ 2>&1 | grep -E "Cannot find module|Type checking failed" | head -2
```
Expected: `TS2307 [ERROR]: Cannot find module 'file:///…/_shared/otp_phone.ts'.` and `error: Type checking failed.`

- [ ] **Step 2: Write the shared helpers**

Create `supabase/functions/_shared/otp_phone.ts` with exactly:

```ts
// supabase/functions/_shared/otp_phone.ts
//
// Spec 1 W2c (§4.1 rule 5, §4.5): what the two phone-code functions share.
// A number is only ever HMACed (OTP_HMAC_KEY) or reduced to its country and
// leading digits; it is never logged or stored as is.

/// '+' and digits, or null when it can't be an E.164 number. Auth stores a
/// phone without the '+', the app sends it with one: both HMAC alike.
export function canonicalPhone(raw: unknown): string | null {
  if (typeof raw !== "string") return null;
  const digits = raw.replace(/\D/g, "");
  if (digits.length < 7 || digits.length > 15 || digits.startsWith("0")) return null;
  return `+${digits}`;
}

function hex(bytes: ArrayBuffer): string {
  return Array.from(new Uint8Array(bytes))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

/// HMAC-SHA256 of [message] under [key], lower-case hex.
export async function hmacHex(key: string, message: string): Promise<string> {
  const cryptoKey = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(key),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  return hex(await crypto.subtle.sign("HMAC", cryptoKey, new TextEncoder().encode(message)));
}

export async function sha256Hex(bytes: Uint8Array): Promise<string> {
  return hex(await crypto.subtle.digest("SHA-256", new Uint8Array(bytes)));
}

/// The phone's HMAC, as private.otp_* tables store it.
export function phoneHmac(key: string, phone: string): Promise<string> {
  return hmacHex(key, phone);
}

/// The leading digits the destination rules match on: '+' and at most six
/// digits. Enough for the longest rule, too few to identify anyone.
export function callingPrefix(phone: string): string {
  return phone.slice(0, 7);
}

/// Canadian area codes (NANP): +1 numbers outside them count as US.
const CANADA = new Set([
  "204", "226", "236", "249", "250", "257", "263", "289", "306", "343", "354",
  "365", "367", "368", "382", "403", "416", "418", "428", "431", "437", "438",
  "450", "460", "468", "474", "506", "514", "519", "548", "579", "581", "584",
  "587", "604", "613", "639", "647", "672", "683", "705", "709", "742", "753",
  "778", "780", "782", "807", "819", "825", "867", "873", "879", "902", "905",
]);

/// The launch countries (GH, GB, US, CA, NG, KE) by calling code; every
/// other number is 'XX' and uses the default routes.
export function countryOf(phone: string): string {
  if (phone.startsWith("+233")) return "GH";
  if (phone.startsWith("+234")) return "NG";
  if (phone.startsWith("+254")) return "KE";
  if (phone.startsWith("+44")) return "GB";
  if (phone.startsWith("+1")) return CANADA.has(phone.slice(2, 5)) ? "CA" : "US";
  return "XX";
}

/// The app's device nonce: 16 random bytes, base64url without padding.
export function decodeNonce(raw: unknown): Uint8Array | null {
  if (typeof raw !== "string" || !/^[A-Za-z0-9_-]{22}$/.test(raw)) return null;
  const base64 = raw.replace(/-/g, "+").replace(/_/g, "/") + "==";
  try {
    const bytes = Uint8Array.from(atob(base64), (c) => c.charCodeAt(0));
    return bytes.length === 16 ? bytes : null;
  } catch {
    return null;
  }
}
```

Create `supabase/functions/_shared/standard_webhooks.ts` with exactly:

```ts
// supabase/functions/_shared/standard_webhooks.ts
//
// Verifies a Standard Webhooks signature (https://www.standardwebhooks.com),
// the scheme Supabase Auth signs its HTTP hooks with. No dependency: the
// HMAC is WebCrypto's, the comparison constant-time.
import { constantTimeEqual } from "./attune_auth.ts";

/// Five minutes either way, the standard's tolerance.
export const TOLERANCE_SECONDS = 5 * 60;

/// [secret] as the dashboard shows it: "v1,whsec_<base64>".
export async function verifyStandardWebhook(
  secret: string,
  headers: Headers,
  body: string,
  nowSeconds: number,
): Promise<boolean> {
  const id = headers.get("webhook-id");
  const timestamp = headers.get("webhook-timestamp");
  const signatures = headers.get("webhook-signature");
  if (!id || !timestamp || !signatures || !/^\d+$/.test(timestamp)) return false;
  if (Math.abs(nowSeconds - Number(timestamp)) > TOLERANCE_SECONDS) return false;

  const encoded = secret.replace(/^v1,/, "").replace(/^whsec_/, "");
  let key: Uint8Array;
  try {
    key = Uint8Array.from(atob(encoded), (c) => c.charCodeAt(0));
  } catch {
    return false;
  }
  if (key.length === 0) return false;
  const cryptoKey = await crypto.subtle.importKey(
    "raw",
    new Uint8Array(key),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signed = await crypto.subtle.sign(
    "HMAC",
    cryptoKey,
    new TextEncoder().encode(`${id}.${timestamp}.${body}`),
  );
  const expected = btoa(String.fromCharCode(...new Uint8Array(signed)));
  return signatures
    .split(" ")
    .some((entry) => entry.startsWith("v1,") && constantTimeEqual(entry.slice(3), expected));
}
```

- [ ] **Step 3: Write the intent endpoint**

Create `supabase/functions/otp-delivery-intent/handler.ts` with exactly:

```ts
// supabase/functions/otp-delivery-intent/handler.ts
//
// Spec 1 W2c (§3.3 A3, §4.3, §4.5, review S-3): the app asks for its next
// code to go by WhatsApp or a call. Stored only as HMACs and hashes, and
// only ever a request: send-sms-hook honours it when fresh, capped and
// from one device, and sends by SMS otherwise.
//
// Always 204, whatever happened (the answer never says whether a number is
// known or whether anything was stored). Logs categories only: never the
// number, the nonce or the IP.
import { canonicalPhone, decodeNonce, hmacHex, phoneHmac, sha256Hex } from "../_shared/otp_phone.ts";

export interface IntentRecord {
  p_phone_hmac: string;
  p_channel: string;
  p_platform: string;
  p_locale: string;
  p_device_hash: string;
  p_ip_hash: string;
}

export interface IntentDeps {
  /// OTP_HMAC_KEY. Unset: nothing is stored, so every code goes by SMS.
  hmacKey: string | undefined;
  record(intent: IntentRecord): Promise<void>;
  log(category: string): void;
}

const CHANNELS = new Set(["sms", "whatsapp", "voice"]);

export const noContent = () => new Response(null, { status: 204 });

export async function handleIntent(req: Request, deps: IntentDeps): Promise<Response> {
  if (req.method !== "POST") return noContent();
  let body: Record<string, unknown>;
  try {
    const parsed = await req.json();
    if (!parsed || typeof parsed !== "object") return noContent();
    body = parsed as Record<string, unknown>;
  } catch {
    deps.log("intent:bad_json");
    return noContent();
  }

  const phone = canonicalPhone(body.phone);
  const channel = typeof body.channel === "string" && CHANNELS.has(body.channel) ? body.channel : null;
  const nonce = decodeNonce(body.device_nonce);
  if (!phone || !channel || !nonce) {
    deps.log("intent:invalid");
    return noContent();
  }
  if (!deps.hmacKey) {
    deps.log("intent:not_configured");
    return noContent();
  }

  const platform = body.platform === "ios" || body.platform === "android" ? body.platform : "other";
  const locale = typeof body.locale === "string" ? body.locale.slice(0, 35) : "";
  const ip = (req.headers.get("x-forwarded-for") ?? "").split(",")[0].trim() || "unknown";
  try {
    await deps.record({
      p_phone_hmac: await phoneHmac(deps.hmacKey, phone),
      p_channel: channel,
      p_platform: platform,
      p_locale: locale,
      p_device_hash: await sha256Hex(nonce),
      p_ip_hash: await hmacHex(deps.hmacKey, `ip:${ip}`),
    });
    deps.log("intent:recorded");
  } catch {
    deps.log("intent:record_failed");
  }
  return noContent();
}
```

Create `supabase/functions/otp-delivery-intent/index.ts` with exactly:

```ts
// supabase/functions/otp-delivery-intent/index.ts — see handler.ts.
// Public (verify_jwt = false in supabase/config.toml): the app calls it
// before sign-in. Per-IP and per-number caps live in otp_record_intent.
import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { serviceRoleClient } from "../_shared/attune_auth.ts";
import { handleIntent } from "./handler.ts";

serve((req) =>
  handleIntent(req, {
    hmacKey: Deno.env.get("OTP_HMAC_KEY"),
    record: async (intent) => {
      const { error } = await serviceRoleClient().rpc("otp_record_intent", intent);
      if (error) throw new Error("otp_record_intent_failed");
    },
    log: (category) => console.log("otp-delivery-intent", category),
  })
);
```

- [ ] **Step 4: Both functions are called without a user JWT**

In `supabase/config.toml`, at the end:

The edit. Replace exactly:

```toml
[functions.calendar-feed]
verify_jwt = false
```

with:

```toml
[functions.calendar-feed]
verify_jwt = false

# Spec 1 W2c: called by the app before sign-in; per-IP and per-number caps
# live in otp_record_intent.
[functions.otp-delivery-intent]
verify_jwt = false

# Spec 1 W2c: called by Supabase Auth (Send SMS Hook) with a Standard
# Webhooks signature (SEND_SMS_HOOK_SECRET), not a user JWT.
[functions.send-sms-hook]
verify_jwt = false

# Spec 1 W2c: the Send SMS Hook is switched on per project in the dashboard
# (owner deploy checklist), never from this file: enabled here, every
# `supabase start` (CI included) would need SEND_SMS_HOOK_SECRET set, and a
# `supabase config push` would carry it to the project. To try it on a local
# stack, uncomment and export the secret first:
# [auth.hook.send_sms]
# enabled = true
# uri = "http://host.docker.internal:54321/functions/v1/send-sms-hook"
# secrets = "env(SEND_SMS_HOOK_SECRET)"
```

- [ ] **Step 5: Run the Deno tests to verify they pass**

```bash
cd /Users/user/attune/supabase/functions
deno test --allow-read _shared/otp_phone.test.ts _shared/standard_webhooks.test.ts otp-delivery-intent/ 2>&1 | grep -E "passed|failed" | tail -1
deno check otp-delivery-intent/index.ts 2>&1 | grep -E "error|Check" | head -2
deno lint otp-delivery-intent _shared/otp_phone.ts _shared/standard_webhooks.ts 2>&1 | tail -1
```
Expected: `ok | 9 passed | 0 failed`; `Check …otp-delivery-intent/index.ts` and no `error`; `Checked 5 files`.

---

### Task 12: `send-sms-hook` (W2c; §3.3 A3/A4, §4.5, §7.2, review S-3, P-26, P-27)

**Files:**
- Create: `supabase/functions/send-sms-hook/messages.ts`, `providers.ts`, `handler.ts`, `index.ts`, `handler.test.ts`

**Interfaces:**
- Consumes: Task 11's helpers; Task 10's `otp_take_send_decision`; W1's `bump_metric_server`.
- Produces: `smsText(otp, platform, androidAppHash?)`, `voiceText(otp)`; `type DeliveryResult = "sent" | "failed" | "unconfigured"`, `interface OutgoingCode {channel, to, otp, text}`, `type Deliverer`, `PROVIDER_TIMEOUT_MS = 2500`, `twilio(env, fetch)`, `meta(env, fetch)`, `arkesel(env, fetch)`, `providersFrom(env, fetch)`; `interface Route`, `interface Decision`, `interface HookDeps {hookSecret, hmacKey, decide, providers, androidAppHashes, bump, nowSeconds, log}`, `DELIVERY_BUDGET_MS = 4500`, `handleSendSms(req, deps) → Response` (200 `{}` when sent; `{error:{http_code, message}}` with `otp:rate_limited:{seconds}` (429) or `otp:unavailable` otherwise).

- [ ] **Step 1: Write the failing test**

Create `supabase/functions/send-sms-hook/handler.test.ts` with exactly:

```ts
// Spec 1 W2c (§4.5, §7.2): the Send SMS Hook — signature, channel routing,
// failover, the SMS fallback, the two message shapes, +999, rate limits,
// and no number or code in the logs.
import { type Decision, handleSendSms, type HookDeps } from "./handler.ts";
import { smsText, voiceText } from "./messages.ts";
import { arkesel, meta, type OutgoingCode, twilio } from "./providers.ts";

const SECRET_BYTES = new Uint8Array(24).fill(5);
const SECRET = `v1,whsec_${btoa(String.fromCharCode(...SECRET_BYTES))}`;
const NOW = 1_800_000_000;
const PHONE = "233244123456";
const OTP = "561166";

async function signed(payload: unknown, secret = SECRET_BYTES): Promise<Request> {
  const body = JSON.stringify(payload);
  const key = await crypto.subtle.importKey("raw", secret, { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const signature = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(`msg_1.${NOW}.${body}`));
  return new Request("http://x/send-sms-hook", {
    method: "POST",
    headers: {
      "webhook-id": "msg_1",
      "webhook-timestamp": String(NOW),
      "webhook-signature": `v1,${btoa(String.fromCharCode(...new Uint8Array(signature)))}`,
    },
    body,
  });
}

const payload = (phone = PHONE) => ({ user: { id: "u1", phone }, sms: { otp: OTP } });

function decision(over: Partial<Decision> = {}): Decision {
  return {
    allowed: true,
    reason: null,
    channel: "sms",
    platform: "ios",
    routes: [{ channel: "sms", provider: "arkesel" }, { channel: "sms", provider: "twilio" }],
    retry_after_s: null,
    ...over,
  };
}

type Outcome = "sent" | "failed" | "unconfigured";

function rig(answer: Decision, outcomes: Record<string, Outcome> = {}) {
  const delivered: (OutgoingCode & { provider: string })[] = [];
  const bumps: string[] = [];
  const logs: string[] = [];
  const asked: [string, string, string][] = [];
  const provider = (name: string) => (code: OutgoingCode) => {
    delivered.push({ ...code, provider: name });
    return Promise.resolve(outcomes[name] ?? "sent");
  };
  const deps: HookDeps = {
    hookSecret: SECRET,
    hmacKey: "test-key",
    decide: (hmac, country, prefix) => {
      asked.push([hmac, country, prefix]);
      return Promise.resolve(answer);
    },
    providers: { arkesel: provider("arkesel"), twilio: provider("twilio"), meta: provider("meta") },
    androidAppHashes: ["FA+9qCX9VSu"],
    bump: (key) => {
      bumps.push(key);
      return Promise.resolve();
    },
    nowSeconds: () => NOW,
    log: (category) => logs.push(category),
  };
  return { deps, delivered, bumps, logs, asked };
}

async function errorOf(response: Response): Promise<string | null> {
  if (response.status === 200) return null;
  const body = await response.json();
  return `${response.status} ${body.error.message}`;
}

Deno.test("a signed SMS goes by the first route, counted by country and route", async () => {
  const r = rig(decision());
  const response = await handleSendSms(await signed(payload()), r.deps);
  if (response.status !== 200) throw new Error(await errorOf(response) ?? "");
  if (r.delivered.length !== 1 || r.delivered[0].provider !== "arkesel") {
    throw new Error(JSON.stringify(r.delivered));
  }
  if (r.bumps.join() !== "otp_sent:gh:sms:arkesel") throw new Error(r.bumps.join());
  const [hmac, country, prefix] = r.asked[0];
  if (!/^[0-9a-f]{64}$/.test(hmac) || country !== "GH" || prefix !== "+233244") {
    throw new Error(JSON.stringify(r.asked));
  }
});

Deno.test("a bad or missing signature, or no secret, sends nothing", async () => {
  const wrongKey = rig(decision());
  const response = await handleSendSms(await signed(payload(), new Uint8Array(24).fill(6)), wrongKey.deps);
  if (await errorOf(response) !== "401 unauthorized" || wrongKey.delivered.length) {
    throw new Error("a wrong signature was accepted");
  }
  const noSecret = rig(decision());
  noSecret.deps.hookSecret = undefined;
  if (await errorOf(await handleSendSms(await signed(payload()), noSecret.deps)) !== "500 otp:unavailable") {
    throw new Error("no secret did not fail closed");
  }
  const noKey = rig(decision());
  noKey.deps.hmacKey = undefined;
  if (await errorOf(await handleSendSms(await signed(payload()), noKey.deps)) !== "500 otp:unavailable") {
    throw new Error("no HMAC key did not fail closed");
  }
});

Deno.test("a failed route fails over to the next; all failing is otp:unavailable", async () => {
  const r = rig(decision(), { arkesel: "failed" });
  await handleSendSms(await signed(payload()), r.deps);
  if (r.delivered.map((d) => d.provider).join() !== "arkesel,twilio" || r.bumps.join() !== "otp_sent:gh:sms:twilio") {
    throw new Error(JSON.stringify(r.delivered));
  }
  const none = rig(decision(), { arkesel: "unconfigured", twilio: "failed" });
  if (await errorOf(await handleSendSms(await signed(payload()), none.deps)) !== "503 otp:unavailable") {
    throw new Error("all routes failing did not answer otp:unavailable");
  }
});

Deno.test("WhatsApp and voice failures fall back to SMS", async () => {
  for (const channel of ["whatsapp", "voice"] as const) {
    const provider = channel === "whatsapp" ? "meta" : "twilio";
    const r = rig(
      decision({
        channel,
        routes: [{ channel, provider }, { channel: "sms", provider: "arkesel" }],
      }),
      { [provider]: "failed" },
    );
    await handleSendSms(await signed(payload()), r.deps);
    const last = r.delivered.at(-1)!;
    if (last.channel !== "sms" || r.bumps.join() !== "otp_sent:gh:sms:arkesel") {
      throw new Error(`${channel}: ${JSON.stringify(r.delivered)}`);
    }
  }
});

Deno.test("a decision of SMS never uses another channel", async () => {
  const r = rig(decision({
    channel: "sms",
    routes: [{ channel: "whatsapp", provider: "meta" }, { channel: "sms", provider: "twilio" }],
  }));
  await handleSendSms(await signed(payload()), r.deps);
  if (r.delivered.some((d) => d.channel !== "sms")) throw new Error(JSON.stringify(r.delivered));
});

Deno.test("iOS and Android message shapes, and the voice words", async () => {
  if (smsText(OTP, "ios", "FA+9qCX9VSu") !==
      "Your Attune code is 561166. It expires in 10 minutes. Don't share it.\n\n@invite.attune.barsopus.com #561166") {
    throw new Error(smsText(OTP, "ios", undefined));
  }
  if (smsText(OTP, "other", undefined) !== smsText(OTP, "ios", undefined)) throw new Error("other is not the iOS shape");
  if (smsText(OTP, "android", "FA+9qCX9VSu") !==
      "<#> Your Attune code is 561166. It expires in 10 minutes. Don't share it.\nFA+9qCX9VSu") {
    throw new Error(smsText(OTP, "android", "FA+9qCX9VSu"));
  }
  if (voiceText(OTP) !== "Your Attune code is 5, 6, 1, 1, 6, 6. Again: 5, 6, 1, 1, 6, 6.") {
    throw new Error(voiceText(OTP));
  }
  const r = rig(decision({ platform: "android" }));
  await handleSendSms(await signed(payload()), r.deps);
  if (!r.delivered[0].text.startsWith("<#> ")) throw new Error("the Android shape was not used");
});

Deno.test("+999 is refused before any decision; rate limits answer with the wait", async () => {
  const parked = rig(decision());
  const response = await handleSendSms(await signed(payload("999123456789012")), parked.deps);
  if (await errorOf(response) !== "400 otp:unavailable" || parked.asked.length || parked.delivered.length) {
    throw new Error("a parked number reached a provider");
  }
  const limited = rig(decision({ allowed: false, reason: "number_hourly", routes: [], retry_after_s: 754 }));
  if (await errorOf(await handleSendSms(await signed(payload()), limited.deps)) !== "429 otp:rate_limited:754") {
    throw new Error("a rate limit was not passed on");
  }
  const blocked = rig(decision({ allowed: false, reason: "blocked", routes: [] }));
  if (await errorOf(await handleSendSms(await signed(payload()), blocked.deps)) !== "400 otp:unavailable") {
    throw new Error("a blocked destination was not refused");
  }
});

Deno.test("no number and no code ever reach the logs", async () => {
  const r = rig(decision(), { arkesel: "failed" });
  await handleSendSms(await signed(payload()), r.deps);
  const logs = r.logs.join(" ");
  if (logs.includes(PHONE) || logs.includes(OTP)) throw new Error(logs);
  for (const file of ["handler.ts", "providers.ts", "index.ts"]) {
    const source = await Deno.readTextFile(new URL(`./${file}`, import.meta.url));
    if (/console\.(log|error)\([^)]*(phone|otp|code\.to|text)\b/.test(source)) {
      throw new Error(`${file} logs a value`);
    }
  }
});

Deno.test("providers: unconfigured without secrets; the right request with them", async () => {
  const calls: { url: string; init: RequestInit }[] = [];
  const fetchFn = (url: string, init: RequestInit) => {
    calls.push({ url, init });
    return Promise.resolve(new Response("{}", { status: 200 }));
  };
  const code: OutgoingCode = { channel: "sms", to: "+233244123456", otp: OTP, text: "hello" };
  const none = (_: string) => undefined;
  for (const provider of [twilio(none, fetchFn), meta(none, fetchFn), arkesel(none, fetchFn)]) {
    if (await provider(code) !== "unconfigured") throw new Error("ran without secrets");
  }
  if (calls.length) throw new Error("called a provider without secrets");

  const env = (name: string) => ({
    TWILIO_ACCOUNT_SID: "AC1", TWILIO_AUTH_TOKEN: "t", TWILIO_SMS_FROM: "+15550000000",
    TWILIO_VOICE_FROM: "+15550000001", WHATSAPP_ACCESS_TOKEN: "w", WHATSAPP_PHONE_NUMBER_ID: "99",
    ARKESEL_API_KEY: "a", ARKESEL_SENDER_ID: "Attune",
  } as Record<string, string>)[name];
  if (await twilio(env, fetchFn)(code) !== "sent" || !calls[0].url.endsWith("/Accounts/AC1/Messages.json")) {
    throw new Error(JSON.stringify(calls[0]));
  }
  await twilio(env, fetchFn)({ ...code, channel: "voice", text: "Your Attune code is 5 & 6" });
  if (!calls[1].url.endsWith("/Calls.json") || !String(calls[1].init.body).includes("5+%26amp%3B+6")) {
    throw new Error(String(calls[1].init.body));
  }
  await meta(env, fetchFn)({ ...code, channel: "whatsapp" });
  const whatsapp = JSON.parse(String(calls[2].init.body));
  if (whatsapp.to !== "233244123456" || whatsapp.template.components[0].parameters[0].text !== OTP) {
    throw new Error(String(calls[2].init.body));
  }
  await arkesel(env, fetchFn)(code);
  const ghana = JSON.parse(String(calls[3].init.body));
  if (ghana.sender !== "Attune" || ghana.recipients[0] !== "233244123456") throw new Error(String(calls[3].init.body));

  const failing = (_: string, __: RequestInit) => Promise.resolve(new Response("no", { status: 500 }));
  if (await twilio(env, failing)(code) !== "failed") throw new Error("a 500 was sent");
  const throwing = (_: string, __: RequestInit) => Promise.reject(new Error("network"));
  if (await arkesel(env, throwing)(code) !== "failed") throw new Error("a network error was sent");
});
```

```bash
cd /Users/user/attune/supabase/functions
deno test --allow-read send-sms-hook/ 2>&1 | grep -E "Cannot find module|Type checking failed" | head -2
```
Expected: `TS2307 [ERROR]: Cannot find module 'file:///…/send-sms-hook/handler.ts'.` and `error: Type checking failed.`

- [ ] **Step 2: The words**

Create `supabase/functions/send-sms-hook/messages.ts` with exactly:

```ts
// supabase/functions/send-sms-hook/messages.ts
//
// Spec 1 §4.5: the code's words, per channel. No vendor, no name.

/// iOS fills the code from the domain-bound last line (and `other` gets the
/// same text); Android's SMS Retriever needs "<#>" first and the app's
/// 11-character hash last. Without a hash, Android gets the plain text and
/// the app's consent prompt reads it instead.
export function smsText(
  otp: string,
  platform: string,
  androidAppHash: string | undefined,
): string {
  const line = `Your Attune code is ${otp}. It expires in 10 minutes. Don't share it.`;
  if (platform === "android" && androidAppHash) {
    return `<#> ${line}\n${androidAppHash}`;
  }
  return `${line}\n\n@invite.attune.barsopus.com #${otp}`;
}

/// Read out twice, a digit at a time.
export function voiceText(otp: string): string {
  const digits = otp.split("").join(", ");
  return `Your Attune code is ${digits}. Again: ${digits}.`;
}
```

- [ ] **Step 3: The providers**

Create `supabase/functions/send-sms-hook/providers.ts` with exactly:

```ts
// supabase/functions/send-sms-hook/providers.ts
//
// Spec 1 W2c (§4.5): one adapter per provider named in private.otp_routes.
// Each says "sent", "failed" (the next route is tried) or "unconfigured"
// (its secrets aren't set: skipped). Secrets are the owner's environment
// variables; nothing here logs a number, a code or a response body.

export type DeliveryResult = "sent" | "failed" | "unconfigured";

export interface OutgoingCode {
  channel: "sms" | "whatsapp" | "voice";
  /// E.164, with the '+'.
  to: string;
  otp: string;
  /// The words for SMS and voice (messages.ts); WhatsApp uses its template.
  text: string;
}

export type Deliverer = (code: OutgoingCode) => Promise<DeliveryResult>;

type Env = (name: string) => string | undefined;
type Fetch = (input: string, init: RequestInit) => Promise<Response>;

/// Each call is bounded: the hook's whole answer must fit Auth's timeout.
export const PROVIDER_TIMEOUT_MS = 2500;

async function post(fetchFn: Fetch, url: string, init: RequestInit): Promise<DeliveryResult> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), PROVIDER_TIMEOUT_MS);
  try {
    const response = await fetchFn(url, { ...init, method: "POST", signal: controller.signal });
    await response.body?.cancel();
    return response.ok ? "sent" : "failed";
  } catch {
    return "failed";
  } finally {
    clearTimeout(timer);
  }
}

function xmlEscape(text: string): string {
  return text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}

/// SMS and voice through Twilio's REST API.
export function twilio(env: Env, fetchFn: Fetch): Deliverer {
  return (code) => {
    const sid = env("TWILIO_ACCOUNT_SID");
    const token = env("TWILIO_AUTH_TOKEN");
    if (!sid || !token) return Promise.resolve("unconfigured");
    const auth = `Basic ${btoa(`${sid}:${token}`)}`;
    const base = `https://api.twilio.com/2010-04-01/Accounts/${sid}`;
    const form = new URLSearchParams({ To: code.to });
    if (code.channel === "sms") {
      const service = env("TWILIO_MESSAGING_SERVICE_SID");
      const from = env("TWILIO_SMS_FROM");
      if (service) form.set("MessagingServiceSid", service);
      else if (from) form.set("From", from);
      else return Promise.resolve("unconfigured");
      form.set("Body", code.text);
      return post(fetchFn, `${base}/Messages.json`, {
        headers: { Authorization: auth, "Content-Type": "application/x-www-form-urlencoded" },
        body: form.toString(),
      });
    }
    if (code.channel === "voice") {
      const from = env("TWILIO_VOICE_FROM");
      if (!from) return Promise.resolve("unconfigured");
      form.set("From", from);
      form.set("Twiml", `<Response><Say>${xmlEscape(code.text)}</Say></Response>`);
      return post(fetchFn, `${base}/Calls.json`, {
        headers: { Authorization: auth, "Content-Type": "application/x-www-form-urlencoded" },
        body: form.toString(),
      });
    }
    return Promise.resolve("failed");
  };
}

/// WhatsApp through Meta's Cloud API, with the approved authentication
/// template (copy-code button; Android one-tap is set on the template).
export function meta(env: Env, fetchFn: Fetch): Deliverer {
  return (code) => {
    const token = env("WHATSAPP_ACCESS_TOKEN");
    const phoneId = env("WHATSAPP_PHONE_NUMBER_ID");
    if (!token || !phoneId) return Promise.resolve("unconfigured");
    if (code.channel !== "whatsapp") return Promise.resolve("failed");
    return post(fetchFn, `https://graph.facebook.com/v21.0/${phoneId}/messages`, {
      headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        messaging_product: "whatsapp",
        to: code.to.replace(/^\+/, ""),
        type: "template",
        template: {
          name: env("WHATSAPP_TEMPLATE_NAME") ?? "attune_code",
          language: { code: env("WHATSAPP_TEMPLATE_LANGUAGE") ?? "en" },
          components: [
            { type: "body", parameters: [{ type: "text", text: code.otp }] },
            {
              type: "button",
              sub_type: "url",
              index: "0",
              parameters: [{ type: "text", text: code.otp }],
            },
          ],
        },
      }),
    });
  };
}

/// SMS inside Ghana through Arkesel (the registered alphanumeric sender).
export function arkesel(env: Env, fetchFn: Fetch): Deliverer {
  return (code) => {
    const key = env("ARKESEL_API_KEY");
    const sender = env("ARKESEL_SENDER_ID");
    if (!key || !sender) return Promise.resolve("unconfigured");
    if (code.channel !== "sms") return Promise.resolve("failed");
    return post(fetchFn, "https://sms.arkesel.com/api/v2/sms/send", {
      headers: { "api-key": key, "Content-Type": "application/json" },
      body: JSON.stringify({
        sender,
        message: code.text,
        recipients: [code.to.replace(/^\+/, "")],
      }),
    });
  };
}

export function providersFrom(env: Env, fetchFn: Fetch = fetch): Record<string, Deliverer> {
  return { twilio: twilio(env, fetchFn), meta: meta(env, fetchFn), arkesel: arkesel(env, fetchFn) };
}
```

- [ ] **Step 4: The hook**

Create `supabase/functions/send-sms-hook/handler.ts` with exactly:

```ts
// supabase/functions/send-sms-hook/handler.ts
//
// Spec 1 W2c (§3.3 A3/A4, §4.3, §4.5, review S-3): Supabase Auth's Send SMS
// Hook. Auth hands over the number and the code; this decides the channel
// and the providers through otp_take_send_decision, then delivers: the
// chosen channel's routes in order, then SMS. A channel other than SMS is
// used only when the decision chose it. "+999" (parked numbers) is refused
// before anything else. A refusal is the hook error the app reads:
// `otp:rate_limited:{seconds}` or `otp:unavailable`.
//
// Logs categories only: never the number or the code.
import { callingPrefix, canonicalPhone, countryOf, phoneHmac } from "../_shared/otp_phone.ts";
import { verifyStandardWebhook } from "../_shared/standard_webhooks.ts";
import { smsText, voiceText } from "./messages.ts";
import type { Deliverer, OutgoingCode } from "./providers.ts";

export interface Route {
  channel: "sms" | "whatsapp" | "voice";
  provider: string;
}

export interface Decision {
  allowed: boolean;
  reason: string | null;
  channel: "sms" | "whatsapp" | "voice" | null;
  platform: string | null;
  routes: Route[];
  retry_after_s: number | null;
}

export interface HookDeps {
  /// SEND_SMS_HOOK_SECRET ("v1,whsec_…"). Unset: every send fails closed.
  hookSecret: string | undefined;
  /// OTP_HMAC_KEY. Unset: every send fails closed (no limits without it).
  hmacKey: string | undefined;
  decide(phoneHmac: string, country: string, prefix: string): Promise<Decision>;
  providers: Record<string, Deliverer>;
  /// ANDROID_SMS_APP_HASHES, comma-separated; the first (the release
  /// signing key's) goes in Android messages.
  androidAppHashes: string[];
  bump(key: string): Promise<void>;
  nowSeconds(): number;
  log(category: string): void;
}

/// The whole answer must fit inside Auth's hook timeout.
export const DELIVERY_BUDGET_MS = 4500;

const RATE_REASONS = new Set(["number_hourly", "number_daily", "prefix_hourly"]);

function hookError(status: number, message: string): Response {
  return new Response(JSON.stringify({ error: { http_code: status, message } }), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

const unavailable = (status = 503) => hookError(status, "otp:unavailable");

export async function handleSendSms(req: Request, deps: HookDeps): Promise<Response> {
  if (req.method !== "POST") return hookError(405, "method_not_allowed");
  const body = await req.text();
  if (!deps.hookSecret) {
    deps.log("hook:not_configured");
    return unavailable(500);
  }
  if (!(await verifyStandardWebhook(deps.hookSecret, req.headers, body, deps.nowSeconds()))) {
    deps.log("hook:bad_signature");
    return hookError(401, "unauthorized");
  }

  let payload: { user?: { phone?: unknown }; sms?: { otp?: unknown } };
  try {
    payload = JSON.parse(body);
  } catch {
    deps.log("hook:bad_json");
    return unavailable(400);
  }
  const phone = canonicalPhone(payload.user?.phone);
  const otp = typeof payload.sms?.otp === "string" && /^\d{4,10}$/.test(payload.sms.otp)
    ? payload.sms.otp
    : null;
  if (!phone || !otp) {
    deps.log("hook:bad_payload");
    return unavailable(400);
  }
  if (phone.startsWith("+999")) {
    deps.log("hook:parked_number");
    return unavailable(400);
  }
  if (!deps.hmacKey) {
    deps.log("hook:no_hmac_key");
    return unavailable(500);
  }

  const country = countryOf(phone);
  let decision: Decision;
  try {
    decision = await deps.decide(await phoneHmac(deps.hmacKey, phone), country, callingPrefix(phone));
  } catch {
    deps.log("hook:decision_failed");
    return unavailable();
  }
  if (!decision.allowed) {
    deps.log(`hook:refused:${decision.reason}`);
    if (decision.reason && RATE_REASONS.has(decision.reason)) {
      return hookError(429, `otp:rate_limited:${Math.max(1, decision.retry_after_s ?? 60)}`);
    }
    return unavailable(400);
  }

  const allowedChannels = new Set(["sms", decision.channel]);
  const appHash = deps.androidAppHashes[0];
  const started = Date.now();
  for (const route of decision.routes) {
    if (!allowedChannels.has(route.channel)) continue;
    if (Date.now() - started > DELIVERY_BUDGET_MS) break;
    const deliver = deps.providers[route.provider];
    if (!deliver) continue;
    const code: OutgoingCode = {
      channel: route.channel,
      to: phone,
      otp,
      text: route.channel === "voice"
        ? voiceText(otp)
        : route.channel === "sms"
        ? smsText(otp, decision.platform ?? "other", appHash)
        : "",
    };
    const result = await deliver(code);
    deps.log(`hook:${route.channel}:${route.provider}:${result}`);
    if (result === "sent") {
      try {
        await deps.bump(`otp_sent:${country.toLowerCase()}:${route.channel}:${route.provider}`);
      } catch {
        // A metric never fails a send.
      }
      return new Response("{}", { status: 200, headers: { "Content-Type": "application/json" } });
    }
  }
  deps.log("hook:all_routes_failed");
  return unavailable();
}
```

Create `supabase/functions/send-sms-hook/index.ts` with exactly:

```ts
// supabase/functions/send-sms-hook/index.ts — see handler.ts.
// Called by Supabase Auth (Send SMS Hook), signed with
// SEND_SMS_HOOK_SECRET; verify_jwt = false in supabase/config.toml.
import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { serviceRoleClient } from "../_shared/attune_auth.ts";
import { type Decision, handleSendSms } from "./handler.ts";
import { providersFrom } from "./providers.ts";

serve((req) => {
  const db = serviceRoleClient();
  return handleSendSms(req, {
    hookSecret: Deno.env.get("SEND_SMS_HOOK_SECRET"),
    hmacKey: Deno.env.get("OTP_HMAC_KEY"),
    decide: async (phoneHmac, country, prefix) => {
      const { data, error } = await db.rpc("otp_take_send_decision", {
        p_phone_hmac: phoneHmac,
        p_country: country,
        p_calling_prefix: prefix,
      });
      if (error || !data) throw new Error("otp_take_send_decision_failed");
      return data as Decision;
    },
    providers: providersFrom((name) => Deno.env.get(name)),
    androidAppHashes: (Deno.env.get("ANDROID_SMS_APP_HASHES") ?? "")
      .split(",")
      .map((hash) => hash.trim())
      .filter((hash) => hash.length === 11),
    bump: async (key) => {
      await db.rpc("bump_metric_server", { p_key: key });
    },
    nowSeconds: () => Math.floor(Date.now() / 1000),
    log: (category) => console.log("send-sms-hook", category),
  });
});
```

- [ ] **Step 5: Run the Deno tests to verify they pass**

```bash
cd /Users/user/attune/supabase/functions
deno test --allow-read send-sms-hook/ 2>&1 | grep -E "passed|failed" | tail -1
deno check send-sms-hook/index.ts 2>&1 | grep -E "error|Check" | head -2
deno lint send-sms-hook 2>&1 | tail -1
```
Expected: `ok | 9 passed | 0 failed`; `Check …send-sms-hook/index.ts` and no `error`; `Checked 5 files`.

- [ ] **Step 6: Mutation check (a decision of SMS never uses another channel)**

```bash
cd /Users/user/attune/supabase/functions
cp send-sms-hook/handler.ts ../../.superpowers/sdd/2026-10-25-spec1-w2/hook.ts.keep
sed -i '' 's/    if (!allowedChannels.has(route.channel)) continue;//' send-sms-hook/handler.ts
deno test --allow-read send-sms-hook/ 2>&1 | grep -E "FAILED|passed" | head -2
cp ../../.superpowers/sdd/2026-10-25-spec1-w2/hook.ts.keep send-sms-hook/handler.ts && rm ../../.superpowers/sdd/2026-10-25-spec1-w2/hook.ts.keep
deno test --allow-read send-sms-hook/ 2>&1 | grep -E "passed|failed" | tail -1
```
Expected: `a decision of SMS never uses another channel ... FAILED` and `FAILED | 8 passed | 1 failed`; after the restore `ok | 9 passed | 0 failed`.

---

### Task 13: The app sends through the hook: intent, WhatsApp, a call, autofill; W2c gate and W2 group gate (W2c; §3.3 A3/A4, §5.1, §5.2, P-20, P-29)

**Files:**
- Modify: `pubspec.yaml`, `pubspec.lock` (`flutter pub add`)
- Modify: `lib/i10n/app_en.arb` (+ regenerate)
- Create: `lib/features/auth/sign_up/data/otp_delivery_service.dart`, `lib/features/auth/sign_up/data/sms_code_listener.dart`
- Modify: `lib/features/auth/sign_up/data/sign_up_gateways.dart` (the sender provider)
- Modify: `lib/features/auth/sign_up/presentation/steps/phone_step.dart`, `code_step.dart`, `lib/features/auth/sign_up/presentation/screens/sign_up_flow.dart`
- Modify: `lib/features/auth/data/passwordless_auth_service.dart` (remove the debug phone log)
- Modify: `ios/Runner/Runner.entitlements` (`webcredentials`)
- Modify: `test/helpers/fake_sign_up.dart`, `test/features/auth/sign_up/sign_up_flow_test.dart`
- Create: `test/features/auth/sign_up/sign_up_channels_test.dart`, `test/features/auth/sign_up/w2c_goldens_test.dart` (+ goldens)

**Interfaces:**
- Consumes: Tasks 8 and 11 (the endpoint name `otp-delivery-intent`, its body `{phone, channel, platform, locale, device_nonce}`); `SmartAuth.instance.getSmsWithRetrieverApi|getSmsWithUserConsentApi|removeSmsRetrieverApiListener|removeUserConsentApiListener` (`smart_auth` 3.2.0; `SmartAuthResult<SmartAuthSms>`, `.hasData`, `.requireData.code`).
- Produces: `typedef IntentPoster`, `OtpDeliveryService({postIntent, auth, platform, locale})` implementing `CodeSender` (`intentTimeout = 4 s`, `static platformName([TargetPlatform?])`); `abstract class SmsCodeListener {next(); stop()}`, `SmartAuthCodeListener({platform, release})`, `smsCodeListenerProvider`; `PhoneStep.onSendWhatsApp`; `CodeStep.lastChannel|onTryWhatsApp|onCallMe|autofillCode`. Test helper `FakeSmsCodeListener` (`arrive(code)`, `stops`).

- [ ] **Step 1: Add `smart_auth`**

```bash
cd /Users/user/attune
flutter pub add 'smart_auth:^3.2.0'
git diff --stat pubspec.yaml pubspec.lock
```
Expected: `Changed 1 dependency!`; `pubspec.yaml | 1 +` and `pubspec.lock | 8 ++++++++` (nothing else moves; if another package changes version, stop and report).

- [ ] **Step 2: Add the W2c copy and regenerate**

In `lib/i10n/app_en.arb`:

The edit. Replace exactly:

```json
  "flow_welcomeBackNoName": "Welcome back.",
  "flow_joinTitle": "Join Attune",
  "flow_joinBody": "A private space for couples, a few introductions a day for singles, and a journal just for you."
}
```

with:

```json
  "flow_welcomeBackNoName": "Welcome back.",
  "flow_joinTitle": "Join Attune",
  "flow_joinBody": "A private space for couples, a few introductions a day for singles, and a journal just for you.",

  "flow_phoneWhatsApp": "Send by WhatsApp instead",
  "flow_whatsAppTitle": "Is WhatsApp on {number}?",
  "@flow_whatsAppTitle": {
    "placeholders": {
      "number": {"type": "String"}
    }
  },
  "flow_whatsAppBody": "We'll send the code to WhatsApp on this number. If WhatsApp is on a different number, we'll text you instead.",
  "flow_whatsAppYes": "Yes, send it to WhatsApp",
  "flow_whatsAppNo": "No, text me",
  "flow_codeTryWhatsApp": "Try WhatsApp",
  "flow_codeCallMe": "Call me with the code",
  "flow_codeCalling": "We're calling {number} now. The code is read out twice.",
  "@flow_codeCalling": {
    "placeholders": {
      "number": {"type": "String"}
    }
  }
}
```

```bash
cd /Users/user/attune
flutter gen-l10n --arb-dir=lib/i10n --template-arb-file=app_en.arb --output-dir=lib/i10n/generated --output-localization-file=app_localizations.dart --no-synthetic-package > /dev/null
perl -0pi -e "s/\*\*'You\\\\'re browsing/**'You're browsing/" lib/i10n/generated/app_localizations.dart
git diff --numstat lib/i10n/generated | awk '{print $2}' | sort -u
grep -c "flow_" lib/i10n/generated/app_localizations_en.dart
```
Expected: `0`; `127`.

- [ ] **Step 3: Write the failing tests**

In `test/helpers/fake_sign_up.dart`:

Edit 1 of 2. Replace exactly:

```dart
// Spec 1 W2b: scripted Auth and code sending for the sign-up tests.
import 'package:attune/features/auth/sign_up/data/sign_up_gateways.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

```

with:

```dart
// Spec 1 W2b: scripted Auth and code sending for the sign-up tests.
import 'dart:async';

import 'package:attune/features/auth/sign_up/data/sign_up_gateways.dart';
import 'package:attune/features/auth/sign_up/data/sms_code_listener.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

```

Edit 2 of 2. Replace exactly:

```dart
    userId = null;
  }
}
```

with:

```dart
    userId = null;
  }
}

/// W2c: Android's SMS listener, driven by the test.
class FakeSmsCodeListener implements SmsCodeListener {
  Completer<String?> _next = Completer<String?>();
  int stops = 0;

  /// The SMS arrives.
  void arrive(String code) {
    if (!_next.isCompleted) _next.complete(code);
  }

  @override
  Future<String?> next() {
    if (_next.isCompleted) _next = Completer<String?>();
    return _next.future;
  }

  @override
  Future<void> stop() async {
    stops++;
  }
}
```

In `test/features/auth/sign_up/sign_up_flow_test.dart` (the flow now listens for an SMS on A4; tests give it a listener that never fires):

Edit 1 of 2. Replace exactly:

```dart
import 'package:attune/features/auth/sign_up/data/sign_up_draft_store.dart';
import 'package:attune/features/auth/sign_up/data/sign_up_gateways.dart';
import 'package:attune/features/auth/sign_up/domain/sign_up_draft.dart';
import 'package:attune/features/auth/sign_up/presentation/screens/sign_up_flow.dart';
```

with:

```dart
import 'package:attune/features/auth/sign_up/data/sign_up_draft_store.dart';
import 'package:attune/features/auth/sign_up/data/sign_up_gateways.dart';
import 'package:attune/features/auth/sign_up/data/sms_code_listener.dart';
import 'package:attune/features/auth/sign_up/domain/sign_up_draft.dart';
import 'package:attune/features/auth/sign_up/presentation/screens/sign_up_flow.dart';
```

Edit 2 of 2. Replace exactly:

```dart
  signUpClockProvider.overrideWithValue(() => _now),
  deviceCountryProvider.overrideWith((ref) async => (sim: 'GH', region: null)),
];

```

with:

```dart
  signUpClockProvider.overrideWithValue(() => _now),
  deviceCountryProvider.overrideWith((ref) async => (sim: 'GH', region: null)),
  smsCodeListenerProvider.overrideWithValue(FakeSmsCodeListener()),
];

```

Create `test/features/auth/sign_up/sign_up_channels_test.dart` with exactly:

```dart
// Spec 1 W2c (§3.3 A3/A4, §4.5): the delivery intent before every code,
// WhatsApp and a call, Android autofill, and the iOS domain-bound code.
import 'dart:convert';
import 'dart:io';

import 'package:attune/core/platform/sim_country.dart';
import 'package:attune/features/auth/data/passwordless_auth_service.dart';
import 'package:attune/features/auth/sign_up/data/account_service.dart';
import 'package:attune/features/auth/sign_up/data/otp_delivery_service.dart';
import 'package:attune/features/auth/sign_up/data/sign_up_draft_store.dart';
import 'package:attune/features/auth/sign_up/data/sign_up_gateways.dart';
import 'package:attune/features/auth/sign_up/data/sms_code_listener.dart';
import 'package:attune/features/auth/sign_up/domain/sign_up_draft.dart';
import 'package:attune/features/auth/sign_up/presentation/screens/sign_up_flow.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../helpers/fake_account_gateway.dart';
import '../../../helpers/fake_sign_up.dart';
import '../../../helpers/flow_harness.dart';

final _now = DateTime.utc(2026, 10, 25, 12);

class _Auth extends PasswordlessAuthService {
  _Auth({this.configured = true});

  final bool configured;
  final asked = <String>[];

  @override
  Future<PasswordlessAuthResult> requestPhoneOtp(
    String phoneNumber, {
    OtpChannel channel = OtpChannel.sms,
  }) async {
    asked.add('$phoneNumber/${channel.name}');
    return PasswordlessAuthResult(isConfigured: configured);
  }
}

List<Override> _deps(
  FakeCodeSender sender,
  FakeSmsCodeListener listener, {
  Map<String, dynamic>? home,
}) => [
  codeSenderProvider.overrideWithValue(sender),
  signUpAuthProvider.overrideWithValue(FakeSignUpAuth()),
  accountServiceProvider.overrideWithValue(
    AccountService(
      FakeAccountGateway(
        homeState: home ?? FakeAccountGateway.account(hasAccount: false),
      ),
    ),
  ),
  signUpClockProvider.overrideWithValue(() => _now),
  deviceCountryProvider.overrideWith((ref) async => (sim: 'GH', region: null)),
  smsCodeListenerProvider.overrideWithValue(listener),
];

void main() {
  group('OtpDeliveryService', () {
    test('the intent goes first, then the code, always asked as SMS', () async {
      final order = <String>[];
      final auth = _Auth();
      final service = OtpDeliveryService(
        postIntent: (body) async => order.add('intent ${jsonEncode(body)}'),
        auth: auth,
        platform: () => 'android',
        locale: () => 'en-GH',
      );
      await service.send(
        phoneE164: '+233244123456',
        channel: 'whatsapp',
        deviceNonce: 'n' * 22,
      );
      expect(order.single, contains('"channel":"whatsapp"'));
      expect(order.single, contains('"device_nonce":"${'n' * 22}"'));
      expect(order.single, contains('"platform":"android"'));
      expect(auth.asked, ['+233244123456/sms']);
    });

    test('a failed or slow intent never stops the code', () async {
      final auth = _Auth();
      await OtpDeliveryService(
        postIntent: (_) => Future.error(Exception('down')),
        auth: auth,
        platform: () => 'ios',
        locale: () => 'en',
      ).send(
        phoneE164: '+447911123456',
        channel: 'voice',
        deviceNonce: 'n' * 22,
      );
      expect(auth.asked, ['+447911123456/sms']);
    });

    test('phone sign-in switched off reads as such', () async {
      final service = OtpDeliveryService(
        postIntent: (_) async {},
        auth: _Auth(configured: false),
        platform: () => 'ios',
        locale: () => 'en',
      );
      expect(
        () => service.send(
          phoneE164: '+447911123456',
          channel: 'sms',
          deviceNonce: 'x',
        ),
        throwsA(
          isA<AuthException>().having((e) => e.code, 'code', 'otp_disabled'),
        ),
      );
    });

    test('platform names', () {
      expect(OtpDeliveryService.platformName(TargetPlatform.iOS), 'ios');
      expect(
        OtpDeliveryService.platformName(TargetPlatform.android),
        'android',
      );
      expect(OtpDeliveryService.platformName(TargetPlatform.macOS), 'other');
    });
  });

  test(
    'iOS never listens for an SMS; it fills from the domain-bound line',
    () async {
      expect(
        await SmartAuthCodeListener(platform: TargetPlatform.iOS).next(),
        isNull,
      );
      final entitlements =
          File('ios/Runner/Runner.entitlements').readAsStringSync();
      expect(
        entitlements,
        contains('<string>webcredentials:invite.attune.barsopus.com</string>'),
      );
      expect(
        entitlements,
        contains('<string>applinks:invite.attune.barsopus.com</string>'),
      );
    },
  );

  test('the phone number is never printed (spec §5.2)', () {
    final source =
        File(
          'lib/features/auth/data/passwordless_auth_service.dart',
        ).readAsStringSync();
    expect(source, isNot(contains('signInWithOtp phone=')));
  });

  test('both functions are public to their callers, not JWT-checked', () {
    final config = File('supabase/config.toml').readAsStringSync();
    expect(
      config,
      contains('[functions.otp-delivery-intent]\nverify_jwt = false'),
    );
    expect(config, contains('[functions.send-sms-hook]\nverify_jwt = false'));
    expect(
      RegExp(r'^\[auth\.hook', multiLine: true).hasMatch(config),
      isFalse,
      reason: 'the hook is switched on in the dashboard, never from this file',
    );
  });

  testWidgets(
    'A3: "Send by WhatsApp instead" asks first, then sends by WhatsApp',
    (tester) async {
      final sender = FakeCodeSender();
      await pumpFlowScreen(
        tester,
        () => const SignUpFlow(entry: SignUpEntry.returning),
        overrides: _deps(sender, FakeSmsCodeListener()),
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Phone number'),
        '244123456',
      );
      await tester.tap(find.text('Send by WhatsApp instead'));
      await tester.pumpAndSettle();
      expect(find.text('Is WhatsApp on +233 24 412 3456?'), findsOneWidget);
      await tester.tap(find.text('Yes, send it to WhatsApp'));
      await tester.pumpAndSettle();
      expect(sender.sent.single.$2, 'whatsapp');
      expect(find.text('Enter the code'), findsOneWidget);
    },
  );

  testWidgets('A3: "No, text me" sends by SMS', (tester) async {
    final sender = FakeCodeSender();
    await pumpFlowScreen(
      tester,
      () => const SignUpFlow(entry: SignUpEntry.returning),
      overrides: _deps(sender, FakeSmsCodeListener()),
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Phone number'),
      '244123456',
    );
    await tester.tap(find.text('Send by WhatsApp instead'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('No, text me'));
    await tester.pumpAndSettle();
    expect(sender.sent.single.$2, 'sms');
  });

  testWidgets(
    'A4: after the second resend, WhatsApp and a call; the call says so',
    (tester) async {
      final sender = FakeCodeSender();
      final draft = SignUpDraft.start(
        SignUpEntry.returning,
        now: _now,
      ).copyWith(
        phoneE164: '+233244123456',
        countryIso: 'GH',
        lastSentAt: _now.subtract(const Duration(minutes: 5)),
        sendCount: 3,
      );
      await pumpFlowScreen(
        tester,
        () => const SignUpFlow(entry: SignUpEntry.returning),
        prefsValues: {SignUpDraftStore.key: jsonEncode(draft.toJson())},
        overrides: _deps(sender, FakeSmsCodeListener()),
      );
      expect(find.text('Try WhatsApp'), findsOneWidget);
      await tester.tap(find.text('Call me with the code'));
      await tester.pumpAndSettle();
      expect(sender.sent.single.$2, 'voice');
      expect(
        find.text(
          "We're calling +233 24 412 3456 now. The code is read out twice.",
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('A4: before the second resend there are no other channels', (
    tester,
  ) async {
    final draft = SignUpDraft.start(SignUpEntry.returning, now: _now).copyWith(
      phoneE164: '+233244123456',
      lastSentAt: _now.subtract(const Duration(minutes: 5)),
      sendCount: 2,
    );
    await pumpFlowScreen(
      tester,
      () => const SignUpFlow(entry: SignUpEntry.returning),
      prefsValues: {SignUpDraftStore.key: jsonEncode(draft.toJson())},
      overrides: _deps(FakeCodeSender(), FakeSmsCodeListener()),
    );
    expect(find.text('Send a new code'), findsOneWidget);
    expect(find.text('Try WhatsApp'), findsNothing);
    expect(find.text('Call me with the code'), findsNothing);
  });

  testWidgets('A4: an SMS read by Android fills the code and verifies it', (
    tester,
  ) async {
    final listener = FakeSmsCodeListener();
    final draft = SignUpDraft.start(SignUpEntry.newAccount, now: _now).copyWith(
      name: 'Ama',
      birthDate: DateTime.utc(1990, 1, 1),
      phoneE164: '+233244123456',
      lastSentAt: _now,
      sendCount: 1,
    );
    await pumpFlowScreen(
      tester,
      () => const SignUpFlow(entry: SignUpEntry.newAccount),
      prefsValues: {SignUpDraftStore.key: jsonEncode(draft.toJson())},
      overrides: _deps(FakeCodeSender(), listener),
    );
    listener.arrive('123456');
    // The SMS reaches the flow, the flow the step, the step the field.
    await tester.pump();
    await tester.pump();
    await tester.pump();
    for (final digit in ['1', '2', '3', '4', '5', '6']) {
      expect(
        find.text(digit),
        findsOneWidget,
        reason: 'the code filled the boxes',
      );
    }
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(find.text('Before you start'), findsOneWidget);
    expect(
      listener.stops,
      greaterThan(0),
      reason: 'the listener stops after A4',
    );
  });
}
```

Create `test/features/auth/sign_up/w2c_goldens_test.dart` with exactly:

```dart
// Spec 1 §2.3 (W2c): A3 with WhatsApp, the WhatsApp question, and A4 with
// the other channels and the call line, at 1.0, 1.3, 2.0 and right to left.
//   flutter test --update-goldens test/features/auth/sign_up/w2c_goldens_test.dart
import 'package:attune/features/auth/log_in/domain/phone_country.dart';
import 'package:attune/features/auth/sign_up/presentation/steps/code_step.dart';
import 'package:attune/features/auth/sign_up/presentation/steps/phone_step.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/flow_harness.dart';

final _now = DateTime.utc(2026, 10, 25, 12);
final _ghana = PhoneCountries.all.firstWhere((c) => c.isoCode == 'GH');

PhoneStep _phone() => PhoneStep(
  initialCountry: _ghana,
  initialNational: '244123456',
  onSend: (_, __) {},
  onSendWhatsApp: (_, __) {},
  onBack: () {},
);

void main() {
  testWidgets('A3 with WhatsApp', (tester) async {
    await expectFlowGoldens(tester, 'step_phone_whatsapp', _phone);
  });

  testWidgets('A3 WhatsApp question', (tester) async {
    await expectFlowGoldens(
      tester,
      'step_phone_whatsapp_sheet',
      _phone,
      before: (tester) async {
        await tester.tap(find.text('Send by WhatsApp instead'));
        await tester.pumpAndSettle();
      },
    );
  });

  testWidgets('A4 after the second resend, calling', (tester) async {
    await expectFlowGoldens(
      tester,
      'step_code_channels',
      () => CodeStep(
        phoneE164: '+233244123456',
        lastSentAt: _now.subtract(const Duration(minutes: 3)),
        sendCount: 3,
        now: () => _now,
        lastChannel: 'voice',
        onCode: (_) {},
        onResend: () {},
        onChangeNumber: () {},
        onTryWhatsApp: () {},
        onCallMe: () {},
      ),
    );
  });
}
```

```bash
cd /Users/user/attune
flutter test --no-pub test/features/auth/sign_up/sign_up_channels_test.dart 2>&1 | tr '\r' '\n' | grep -E "Error when reading" | head -2
```
Expected: `Error when reading 'lib/features/auth/sign_up/data/otp_delivery_service.dart'` and `…sms_code_listener.dart`.

- [ ] **Step 4: The sender and the SMS listener**

Create `lib/features/auth/sign_up/data/otp_delivery_service.dart` with exactly:

```dart
import 'dart:async';

import 'package:attune/features/auth/data/passwordless_auth_service.dart';
import 'package:attune/features/auth/sign_up/data/sign_up_gateways.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Posts the delivery intent to `otp-delivery-intent` (W2c).
typedef IntentPoster = Future<void> Function(Map<String, dynamic> body);

/// A3/A4's sending under the Send SMS Hook (Spec 1 §3.3, §4.5, review S-3):
/// first the delivery intent — the channel wanted, this phone's platform
/// and locale, and the draft's random `device_nonce` — then the code itself,
/// always asked for as SMS. The hook moves it to WhatsApp or a call only
/// when the intent is fresh, capped and from this one device. A failed
/// intent never stops the code: it then simply goes by SMS. Without the
/// hook (W2b, or a project where it is off) Supabase's own SMS sends it.
class OtpDeliveryService implements CodeSender {
  OtpDeliveryService({
    required IntentPoster postIntent,
    required PasswordlessAuthService auth,
    required String Function() platform,
    required String Function() locale,
  }) : _postIntent = postIntent,
       _auth = auth,
       _platform = platform,
       _locale = locale;

  final IntentPoster _postIntent;
  final PasswordlessAuthService _auth;
  final String Function() _platform;
  final String Function() _locale;

  static const intentTimeout = Duration(seconds: 4);

  @override
  Future<void> send({
    required String phoneE164,
    required String channel,
    required String deviceNonce,
  }) async {
    try {
      await _postIntent({
        'phone': phoneE164,
        'channel': channel,
        'platform': _platform(),
        'locale': _locale(),
        'device_nonce': deviceNonce,
      }).timeout(intentTimeout);
    } catch (error) {
      debugPrint('[otp] delivery intent skipped: ${error.runtimeType}');
    }
    final result = await _auth.requestPhoneOtp(phoneE164);
    if (!result.isConfigured) {
      throw const AuthException('not configured', code: 'otp_disabled');
    }
  }

  static String platformName([TargetPlatform? platform]) => switch (platform ??
      defaultTargetPlatform) {
    TargetPlatform.iOS => 'ios',
    TargetPlatform.android => 'android',
    _ => 'other',
  };
}
```

Create `lib/features/auth/sign_up/data/sms_code_listener.dart` with exactly:

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smart_auth/smart_auth.dart';

/// Android's code autofill for A4 (Spec 1 §3.3, W2c): the SMS Retriever in
/// release builds (the message ends with the release key's app hash), the
/// one-tap User Consent prompt otherwise. No SMS permission either way. iOS
/// fills the code itself from `AutofillHints.oneTimeCode` and the
/// domain-bound last line, so it never listens here.
abstract class SmsCodeListener {
  /// The next code that arrives, or null (cancelled, none, not Android).
  Future<String?> next();

  Future<void> stop();
}

class SmartAuthCodeListener implements SmsCodeListener {
  SmartAuthCodeListener({TargetPlatform? platform, bool? release})
    : _android = (platform ?? defaultTargetPlatform) == TargetPlatform.android,
      _release = release ?? kReleaseMode;

  final bool _android;
  final bool _release;

  @override
  Future<String?> next() async {
    if (!_android) return null;
    try {
      final result =
          _release
              ? await SmartAuth.instance.getSmsWithRetrieverApi()
              : await SmartAuth.instance.getSmsWithUserConsentApi();
      return result.hasData ? result.requireData.code : null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> stop() async {
    if (!_android) return;
    try {
      await (_release
          ? SmartAuth.instance.removeSmsRetrieverApiListener()
          : SmartAuth.instance.removeUserConsentApiListener());
    } catch (_) {}
  }
}

final smsCodeListenerProvider = Provider<SmsCodeListener>(
  (ref) => SmartAuthCodeListener(),
);
```

In `lib/features/auth/sign_up/data/sign_up_gateways.dart` (`BuiltInSmsCodeSender` stays: it is what W2b ran on):

Edit 1 of 2. Replace exactly:

```dart
import 'package:attune/features/auth/data/passwordless_auth_service.dart';
import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
```

with:

```dart
import 'dart:ui' show PlatformDispatcher;

import 'package:attune/features/auth/data/passwordless_auth_service.dart';
import 'package:attune/features/auth/sign_up/data/otp_delivery_service.dart';
import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
```

Edit 2 of 2. Replace exactly:

```dart
}

final codeSenderProvider = Provider<CodeSender>(
  (ref) => BuiltInSmsCodeSender(PasswordlessAuthService()),
);

```

with:

```dart
}

/// W2c: the delivery intent first, then the code (OtpDeliveryService).
final codeSenderProvider = Provider<CodeSender>(
  (ref) => OtpDeliveryService(
    postIntent:
        (body) => Supabase.instance.client.functions.invoke(
          'otp-delivery-intent',
          body: body,
        ),
    auth: PasswordlessAuthService(),
    platform: OtpDeliveryService.platformName,
    locale: () => PlatformDispatcher.instance.locale.toLanguageTag(),
  ),
);

```

- [ ] **Step 5: WhatsApp on A3; WhatsApp, a call and autofill on A4**

In `lib/features/auth/sign_up/presentation/steps/phone_step.dart`:

Edit 1 of 5. Replace exactly:

```dart
import 'dart:async';

import 'package:attune/core/utils/bottom_sheet_utils.dart';
import 'package:attune/features/auth/log_in/domain/phone_country.dart';
```

with:

```dart
import 'dart:async';

import 'package:attune/core/ui/text/allow_large_text.dart';
import 'package:attune/core/utils/bottom_sheet_utils.dart';
import 'package:attune/features/auth/log_in/domain/phone_country.dart';
```

Edit 2 of 5. Replace exactly:

```dart
    this.busy = false,
    this.sendError,
  });

```

with:

```dart
    this.busy = false,
    this.sendError,
    this.onSendWhatsApp,
  });

```

Edit 3 of 5. Replace exactly:

```dart
  /// A failed send, in the words to show.
  final String? sendError;

  @override
```

with:

```dart
  /// A failed send, in the words to show.
  final String? sendError;

  /// W2c: "Send by WhatsApp instead", after the person confirms WhatsApp is
  /// on this number. Null hides it.
  final void Function(String e164, String countryIso)? onSendWhatsApp;

  @override
```

Edit 4 of 5. Replace exactly:

```dart
    final number = _validNumber();
    if (number != null) widget.onSend(number.$1, number.$2);
  }

```

with:

```dart
    final number = _validNumber();
    if (number != null) widget.onSend(number.$1, number.$2);
  }

  /// "Is WhatsApp on {number}?": yes sends by WhatsApp, no by SMS.
  Future<void> _sendWhatsApp() async {
    final number = _validNumber();
    final onWhatsApp = widget.onSendWhatsApp;
    if (number == null || onWhatsApp == null) return;
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final yes = await BottomSheetUtils.showDocumentationBottomSheet<bool>(
      context: context,
      maxHeight: MediaQuery.sizeOf(context).height * 0.6,
      widget: AllowLargeText(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: Text(
                  loc.flow_whatsAppTitle(formatPhoneForDisplay(number.$1)),
                  style: theme.textTheme.titleLarge,
                ),
              ),
              const SizedBox(height: 12),
              Text(loc.flow_whatsAppBody, style: theme.textTheme.bodyLarge),
              const SizedBox(height: 24),
              Builder(
                builder:
                    (sheet) => FlowPrimaryButton(
                      label: loc.flow_whatsAppYes,
                      onPressed: () => Navigator.of(sheet).pop(true),
                    ),
              ),
              const SizedBox(height: 8),
              Builder(
                builder:
                    (sheet) => FlowSecondaryButton(
                      label: loc.flow_whatsAppNo,
                      onPressed: () => Navigator.of(sheet).pop(false),
                    ),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || yes == null) return;
    yes
        ? onWhatsApp(number.$1, number.$2)
        : widget.onSend(number.$1, number.$2);
  }

```

Edit 5 of 5. Replace exactly:

```dart
          onPressed: _send,
        ),
      ],
    );
```

with:

```dart
          onPressed: _send,
        ),
        if (widget.onSendWhatsApp != null)
          FlowSecondaryButton(
            label: loc.flow_phoneWhatsApp,
            onPressed: widget.busy ? null : _sendWhatsApp,
          ),
      ],
    );
```

In `lib/features/auth/sign_up/presentation/steps/code_step.dart`:

Edit 1 of 4. Replace exactly:

```dart
    this.busy = false,
    this.onRetry,
  });

```

with:

```dart
    this.busy = false,
    this.onRetry,
    this.lastChannel = 'sms',
    this.onTryWhatsApp,
    this.onCallMe,
    this.autofillCode,
  });

```

Edit 2 of 4. Replace exactly:

```dart
  /// couldn't be read (offline right after verifying).
  final VoidCallback? onRetry;

  @override
```

with:

```dart
  /// couldn't be read (offline right after verifying).
  final VoidCallback? onRetry;

  /// W2c: the channel the newest code was asked on; `voice` shows the
  /// calling line.
  final String lastChannel;

  /// W2c: after the second resend, "Try WhatsApp" and "Call me with the
  /// code" (null hides them).
  final VoidCallback? onTryWhatsApp;
  final VoidCallback? onCallMe;

  /// W2c: a code Android's SMS listener read; it fills the field.
  final String? autofillCode;

  @override
```

Edit 3 of 4. Replace exactly:

```dart
    // A new code was sent: the old digits mean nothing now.
    if (widget.sendCount != oldWidget.sendCount) _code.clear();
  }

```

with:

```dart
    // A new code was sent: the old digits mean nothing now.
    if (widget.sendCount != oldWidget.sendCount) _code.clear();
    final autofill = widget.autofillCode;
    if (autofill != null && autofill != oldWidget.autofillCode) {
      // After this frame: a full code verifies at once, and the flow's
      // state must not change while it is building.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _code.text = autofill;
      });
    }
  }

```

Edit 4 of 4. Replace exactly:

```dart
              ),
            )
          else
            FlowTextLink(
              label: loc.flow_codeResend,
              alignment: AlignmentDirectional.centerStart,
              onPressed: widget.busy ? () {} : widget.onResend,
            ),
        ],
      ),
```

with:

```dart
              ),
            )
          else ...[
            FlowTextLink(
              label: loc.flow_codeResend,
              alignment: AlignmentDirectional.centerStart,
              onPressed: widget.busy ? () {} : widget.onResend,
            ),
            if (ResendLadder.offersOtherChannels(widget.sendCount)) ...[
              if (widget.onTryWhatsApp != null)
                FlowTextLink(
                  label: loc.flow_codeTryWhatsApp,
                  alignment: AlignmentDirectional.centerStart,
                  onPressed: widget.busy ? () {} : widget.onTryWhatsApp!,
                ),
              if (widget.onCallMe != null)
                FlowTextLink(
                  label: loc.flow_codeCallMe,
                  alignment: AlignmentDirectional.centerStart,
                  onPressed: widget.busy ? () {} : widget.onCallMe!,
                ),
            ],
          ],
          if (widget.lastChannel == 'voice') ...[
            const SizedBox(height: 12),
            Semantics(
              liveRegion: true,
              child: Text(
                loc.flow_codeCalling(formatPhoneForDisplay(widget.phoneE164)),
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ],
        ],
      ),
```

In `lib/features/auth/sign_up/presentation/screens/sign_up_flow.dart`:

Edit 1 of 6. Replace exactly:

```dart
import 'package:attune/features/auth/sign_up/data/sign_up_draft_store.dart';
import 'package:attune/features/auth/sign_up/data/sign_up_gateways.dart';
import 'package:attune/features/auth/sign_up/domain/birth_date_validator.dart';
import 'package:attune/features/auth/sign_up/domain/default_phone_country.dart';
```

with:

```dart
import 'package:attune/features/auth/sign_up/data/sign_up_draft_store.dart';
import 'package:attune/features/auth/sign_up/data/sign_up_gateways.dart';
import 'package:attune/features/auth/sign_up/data/sms_code_listener.dart';
import 'package:attune/features/auth/sign_up/domain/birth_date_validator.dart';
import 'package:attune/features/auth/sign_up/domain/default_phone_country.dart';
```

Edit 2 of 6. Replace exactly:

```dart
class _SignUpFlowState extends ConsumerState<SignUpFlow> {
  late final SignUpCoordinator _c = ref.read(signUpCoordinatorProvider);
  late SignUpStepId _step;
  bool _forward = true;
```

with:

```dart
class _SignUpFlowState extends ConsumerState<SignUpFlow> {
  late final SignUpCoordinator _c = ref.read(signUpCoordinatorProvider);
  late final SmsCodeListener _listener;
  late SignUpStepId _step;
  bool _forward = true;
```

Edit 3 of 6. Replace exactly:

```dart
  int? _guestYear;
  String? _welcomeName;

  @override
  void initState() {
    super.initState();
    _step = _c.start(widget.entry);
    // A3's default country, read early so it is ready by then.
    ref.read(deviceCountryProvider.future).ignore();
```

with:

```dart
  int? _guestYear;
  String? _welcomeName;
  String? _autofill;

  @override
  void initState() {
    super.initState();
    _listener = ref.read(smsCodeListenerProvider);
    _step = _c.start(widget.entry);
    if (_step == SignUpStepId.code) _listenForCode();
    // A3's default country, read early so it is ready by then.
    ref.read(deviceCountryProvider.future).ignore();
```

Edit 4 of 6. Replace exactly:

```dart
  AppLocalizations get _loc => AppLocalizations.of(context)!;

  void _go(SignUpStepId step, {bool forward = true}) => setState(() {
    _forward = forward;
    _step = step;
    _error = null;
    _accepted = false;
    _unresolved = false;
  });

  void _leave() => context.go(widget.backTo ?? RouteNames.welcome);
```

with:

```dart
  AppLocalizations get _loc => AppLocalizations.of(context)!;

  void _go(SignUpStepId step, {bool forward = true}) {
    setState(() {
      _forward = forward;
      _step = step;
      _error = null;
      _accepted = false;
      _unresolved = false;
      _autofill = null;
    });
    step == SignUpStepId.code ? _listenForCode() : _stopListening();
  }

  /// W2c: Android reads the code from the SMS (no permission) and fills A4.
  Future<void> _listenForCode() async {
    final code = await _listener.next();
    if (!mounted || _step != SignUpStepId.code || code == null) return;
    setState(() => _autofill = code);
  }

  void _stopListening() {
    unawaited(_listener.stop());
  }

  @override
  void dispose() {
    _stopListening();
    super.dispose();
  }

  void _leave() => context.go(widget.backTo ?? RouteNames.welcome);
```

Edit 5 of 6. Replace exactly:

```dart
          onBack: _back,
          onSend: _send,
        );
      case SignUpStepId.code:
```

with:

```dart
          onBack: _back,
          onSend: _send,
          onSendWhatsApp: (e164, iso) => _send(e164, iso, channel: 'whatsapp'),
        );
      case SignUpStepId.code:
```

Edit 6 of 6. Replace exactly:

```dart
          onChangeNumber: _changeNumber,
          onRetry: _unresolved ? _retryResolve : null,
        );
      case SignUpStepId.consent:
```

with:

```dart
          onChangeNumber: _changeNumber,
          onRetry: _unresolved ? _retryResolve : null,
          lastChannel: draft.channel,
          onTryWhatsApp: () => _resend(channel: 'whatsapp'),
          onCallMe: () => _resend(channel: 'voice'),
          autofillCode: _autofill,
        );
      case SignUpStepId.consent:
```

- [ ] **Step 6: No phone number in the logs; the iOS code domain**

In `lib/features/auth/data/passwordless_auth_service.dart` (§5.2; nothing else in the file changes, so LoginScreen behaves as today):

The edit. Replace exactly:

```dart
    if (client == null) {
      return const PasswordlessAuthResult(isConfigured: false);
    }

    // TEMP debug: log the exact E.164 string sent to Supabase, so the value can
    // be compared byte-for-byte against the dashboard test-number entry. A common
    // Ghana pitfall is a leftover leading 0 (+2330501201544 vs +233501201544).
    // Remove before release.
    if (kDebugMode) {
      debugPrint('[AUTH] signInWithOtp phone="${phoneNumber.trim()}"');
    }

```

with:

```dart
    if (client == null) {
      return const PasswordlessAuthResult(isConfigured: false);
    }

```

In `ios/Runner/Runner.entitlements` (the code SMS ends `@invite.attune.barsopus.com #123456`; iOS offers it only for an app with this domain under `webcredentials`):

The edit. Replace exactly:

```xml
	<array>
		<string>applinks:invite.attune.barsopus.com</string>
	</array>
	<key>aps-environment</key>
```

with:

```xml
	<array>
		<string>applinks:invite.attune.barsopus.com</string>
		<string>webcredentials:invite.attune.barsopus.com</string>
	</array>
	<key>aps-environment</key>
```

- [ ] **Step 7: Run the tests, create the goldens, look at them**

```bash
cd /Users/user/attune
flutter test --no-pub test/features/auth/sign_up/sign_up_channels_test.dart test/features/auth/sign_up/sign_up_flow_test.dart test/core/ios_push_capability_test.dart 2>&1 | tr '\r' '\n' | grep -E "All tests passed|Some tests failed" | tail -1
flutter test --no-pub --update-goldens test/features/auth/sign_up/w2c_goldens_test.dart 2>&1 | tr '\r' '\n' | grep -E "All tests passed|Some tests failed|overflow" | tail -1
ls test/features/auth/sign_up/goldens | wc -l
dart format lib/features/auth/sign_up test/helpers/fake_sign_up.dart test/features/auth/sign_up
flutter analyze --no-pub lib/features/auth test/features/auth test/helpers 2>&1 | grep -E "^\s*(error|warning) " | grep -v "login_screen_options" | head
```
Expected: `All tests passed!` (the intent goes first and the code is always asked as SMS; a failed intent never stops it; sign-in switched off reads as such; platform names; iOS never listens and the entitlement is there; no phone number printed; both functions `verify_jwt = false` and no `[auth.hook` table in `config.toml`; "Send by WhatsApp instead" asks, then sends by WhatsApp, "No, text me" by SMS; after the second resend "Try WhatsApp" and "Call me with the code", the call line; none before; an SMS read by Android fills the boxes, verifies and the listener stops); `All tests passed!` with no overflow; `68` images; `Formatted … (0 changed)`; no new `error`/`warning`. Open `step_phone_whatsapp_sheet.scale2.0.png` and `step_code_channels.rtl.png`.

- [ ] **Step 8: Build the Android app once (the new plugin compiles with this Gradle setup)**

```bash
cd /Users/user/attune
flutter build apk --debug --no-pub 2>&1 | tail -2
```
Expected: `✓ Built build/app/outputs/flutter-apk/app-debug.apk`. If the build can't run here (no Android SDK on this machine), write that in the task report; the owner's checklist repeats it.

- [ ] **Step 9: W2c regression gate — SQL**

```bash
cd /Users/user/attune
for f in supabase/tests/*.sql; do
  if psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f "$f" >/dev/null 2>&1; then echo "PASS $(basename "$f")"; else echo "FAIL $(basename "$f")"; fi
done > .superpowers/sdd/2026-10-25-spec1-w2/sql-after-w2c.txt
comm -13 <(grep '^FAIL' .superpowers/sdd/2026-10-25-spec1-w2/sql-baseline.txt | sort) <(grep '^FAIL' .superpowers/sdd/2026-10-25-spec1-w2/sql-after-w2c.txt | sort)
grep -E "identity_foundation|otp_delivery" .superpowers/sdd/2026-10-25-spec1-w2/sql-after-w2c.txt
```
Expected: the `comm` prints nothing; `PASS identity_foundation_contracts.sql` and `PASS otp_delivery_contracts.sql`.

- [ ] **Step 10: W2c regression gate — Deno and Flutter**

```bash
cd /Users/user/attune/supabase/functions
deno test --allow-read _shared/otp_phone.test.ts _shared/standard_webhooks.test.ts otp-delivery-intent/ send-sms-hook/ accept-invite/ purge-unfinished-signups/ 2>&1 | grep -E "passed|failed" | tail -1
cd /Users/user/attune
flutter test --no-pub 2>&1 | tr '\r' '\n' | grep -E 'All tests passed!|Some tests failed' | tail -1
flutter analyze --no-pub lib test > .superpowers/sdd/2026-10-25-spec1-w2/analyze-w2c.txt 2>&1
comm -13 .superpowers/sdd/2026-10-25-spec1-w2/analyze-errors-baseline.txt <(grep -E '^\s*error ' .superpowers/sdd/2026-10-25-spec1-w2/analyze-w2c.txt | sed -E 's/:[0-9]+:[0-9]+//' | sort -u)
diff <(grep -E 'lib/features/games/|auth_exports\.dart|lib/home/home_screen\.dart|lib/features/opinions/|games_contracts\.sql' .superpowers/sdd/2026-10-25-spec1-w2/git-status-before.txt) <(git status --short | grep -E 'lib/features/games/|auth_exports\.dart|lib/home/home_screen\.dart|lib/features/opinions/|games_contracts\.sql')
```
Expected: `ok | … passed | 0 failed` (18 new plus the existing accept-invite and purge tests); `All tests passed!`; both `comm` and `diff` print nothing.

- [ ] **Step 11: Run tests**

Steps 9–10 are the final gate. Hand the owner the checklist below. **The W2 group gate (spec §8) is all owner work**: providers contracted, MTN sender ID, Meta template, real-carrier tests in GH/UK/US/CA, the A5 AI line and EULA v2 text approved by counsel, `webcredentials` in the association file, the store listing. Only then may `flow_signin_v2` be switched on in production (its `private.flag_production_gates` row enforces that once the project reads `production`).

---

## Owner deploy checklist (the plan never runs any of this)

1. **Order.** W1 is deployed first (its migrations, functions and the `FLOW_V2_DEFAULT` key; W1 checklist). W2a and W2b are app-only; W2c adds two migrations and two functions. On the development project `flow_signin_v2` is already on (W1's dev script), so **installing a W2a build switches development to Welcome at once**; W2b's build then signs up through the new flow by Supabase's built-in SMS. Nothing changes on a project where the flag is off.
2. **Server (W2c).** `supabase db push` applies `20261025110000_otp_delivery.sql` and its twin. Afterwards, in the SQL editor: `select jobname, schedule from cron.job where jobname = 'otp-purge';` → `otp-purge | 37 * * * *`; `select has_function_privilege('authenticated', 'public.otp_take_send_decision(text,text,text)', 'EXECUTE');` → `f`.
3. **Functions.** `supabase functions deploy otp-delivery-intent` and `supabase functions deploy send-sms-hook` (both read `verify_jwt = false` from `supabase/config.toml`; add `--no-verify-jwt` if your CLI ignores it). Deploying them changes nothing until the hook is switched on (step 6): the app's intent is stored and unused, and Supabase's built-in SMS keeps sending.
4. **Secrets** (`supabase secrets set …`, per project; never in the repo):
   - `OTP_HMAC_KEY` — 32+ random bytes (`openssl rand -base64 48`). Unset: no intent is stored and the hook refuses every send (`otp:unavailable`).
   - `SEND_SMS_HOOK_SECRET` — the `v1,whsec_…` value the dashboard generates in step 6.
   - SMS and voice: `TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN`, and `TWILIO_MESSAGING_SERVICE_SID` (or `TWILIO_SMS_FROM`), `TWILIO_VOICE_FROM`.
   - Ghana direct: `ARKESEL_API_KEY`, `ARKESEL_SENDER_ID` (the MTN-registered alphanumeric sender). Confirm the endpoint `https://sms.arkesel.com/api/v2/sms/send` and its body (`sender`, `message`, `recipients`) against your Arkesel account docs during the real-carrier test; if you contract another Ghana provider, the adapter in `send-sms-hook/providers.ts` and the `otp_routes_provider_check` constraint change together.
   - WhatsApp: `WHATSAPP_ACCESS_TOKEN`, `WHATSAPP_PHONE_NUMBER_ID`, optionally `WHATSAPP_TEMPLATE_NAME` (default `attune_code`) and `WHATSAPP_TEMPLATE_LANGUAGE` (default `en`).
   - `ANDROID_SMS_APP_HASHES` — the 11-character SMS Retriever hash of the **release** signing key first (comma-separated if you add others). Compute it with Google's script: `keytool -exportcert -alias <alias> -keystore <release.jks> | xxd -p | tr -d "[:space:]" | echo -n com.barsopus.attune "$(cat)" | sha256sum | tr -d "[:space:]-" | xxd -r -p | base64 | cut -c1-11`. For Play App Signing, use the key Play shows under App integrity.
5. **Auth settings** (dashboard → Authentication, development project first): phone OTP length 6, expiry 600 s, per-number frequency 30 s; raise the project's SMS hourly limit for worldwide sign-up; confirm the plan offers the Send SMS Hook (spec §4.5, review F-2).
6. **Switch on the Send SMS Hook only after step 4's provider secrets are set** (otherwise every sign-in fails with "We couldn't send a code right now"): Authentication → Hooks → Send SMS → HTTPS, URL `https://<project-ref>.supabase.co/functions/v1/send-sms-hook`, generate the secret, copy it into `SEND_SMS_HOOK_SECRET`, save. Then sign in once on a test phone: the edge function log shows `hook:sms:<provider>:sent` and `select key, count from public.metric_counters where key like 'otp_sent:%' and day = current_date;` shows the send. Don't run `supabase config push` expecting it to carry the hook: `config.toml` keeps that block commented (P-28).
7. **Destinations.** Add your providers' fraud-list prefixes and tune caps in the SQL editor, e.g. `insert into private.otp_destination_rules values ('+881', 'block', null) on conflict (calling_code_prefix) do update set rule = excluded.rule;` and `update private.otp_destination_rules set max_sends_per_hour = 2000 where calling_code_prefix = '+233';`. Routes likewise: `update private.otp_routes set enabled = false where country_code = 'GH' and provider = 'arkesel';` moves Ghana to Twilio at once.
8. **Meta.** An approved WhatsApp **authentication** template named as in `WHATSAPP_TEMPLATE_NAME`, with the copy-code button (and Android one-tap autofill: package `com.barsopus.attune`, the step-4 hash).
9. **iOS.** In `attune-invite-web`, the `apple-app-site-association` on `invite.attune.barsopus.com` gains `"webcredentials": { "apps": ["<TEAMID>.com.barsopus.attune"] }` next to `applinks`; the Associated Domains capability already exists for the App ID. Without it iOS still delivers the SMS, but doesn't offer the code above the keyboard.
10. **Android build.** `flutter build appbundle --release` once after Task 13 to confirm `smart_auth` (Play services auth) builds with the release config; release builds use the SMS Retriever, so the hash in step 4 must match the key that signs what users install.
11. **Copy and counsel (W2 gate).** Privacy counsel checks A5's bullet 2 sentence by sentence against the live AI features, and approves the EULA v2 text; when the approved EULA text differs from today's `eulaContent`, update `LegalDocumentationData.eula` (and its ARB key) before production. Optionally supply the three preview illustrations (WebP, ≤ 60 KB each); swapping the icon in `path_preview_sheet.dart` for an `Image.asset` is a one-line change per path.
12. **Real-carrier tests (W2 gate, spec §7.5):** codes by SMS, WhatsApp and voice on MTN, Telecel, AirtelTigo (Ghana); EE, Vodafone, O2 (UK); a US and a Canadian carrier; a dual-SIM Android with WhatsApp on the other SIM; Android autofill with the release build; iOS autofill from the SMS and the WhatsApp notification.
13. **Store listing (S0)** updated (W2 gate).
14. **Production switch-on, last:** when items 8–13 are done on the production project, `select public.record_flag_gate_evidence('flow_signin_v2', '<review ref>');` as the service role, then `update public.feature_flags set enabled = true where key = 'flow_signin_v2';`. A production build with `FLOW_V2_DEFAULT` unset shows IntroScreen on its very first launch and Welcome from the moment the config has been read.

## Spec coverage (self-review)

| Spec item | Where |
|---|---|
| §2.2 motion tokens, `SharedAxisStep`, never-animated X1 and consent | Task 1; Task 2 Step 9; Task 8 (`consent appears at once`) |
| §2.3 `AllowLargeText`, goldens 1.0/1.3/2.0/RTL, three guidelines, announced errors | Tasks 1, 2, 3, 7, 9, 13 |
| §3.1 WL1 + previews (D15 open countries), first-launch flag | Task 3 |
| §3.2 G1; G2 copy | Task 2; Task 9 (label: P-2; G3: P-1) |
| §3.3 A1–A5 incl. draft resume at A4, under-18 writes nothing, existing account discards the draft, offline A5 queued, "Not now" | Tasks 5–8 |
| §3.3 A3 SIM country, WhatsApp sheet; A4 ladder, newest code, other channels after the second resend, call copy, autofill | Tasks 5, 7, 8, 13 |
| §3.4 returning account, N1 | Task 8 |
| §3.6 X1, 30-day block, Keychain + backed-up prefs | Tasks 2, 4 |
| §3.8 RI-1/RI-2 (moved earlier, P-3) | Task 3 |
| §3.14 queued `complete_sign_up` replay | Task 6 |
| §3.15 A5c (`consent`); A2/A1/A6 interstitials | Task 8 (P-15: the rest is W3a) |
| §4.2/§4.3 W2c tables and functions, §4.6 `otp-purge`, §4.8 retention | Task 10 (P-22) |
| §4.5 `otp-delivery-intent`, `send-sms-hook`, auth settings, `config.toml` | Tasks 11, 12; checklist 4–6 (P-28) |
| §5.2 `main.dart`, router, LoginProfile, EULA v2, sync service, passwordless log, entitlements, backup rules, `pubspec` | Tasks 2, 4, 6, 8, 9, 13 |
| §5.4 routes, first-launch allow-list, guest gate, under-18 block, `RoutingNotifier` state | Tasks 1, 4, 8 |
| §7.1 `otp_delivery_contracts.sql`; §7.2 Deno hook and intent tests; §7.3 validators, flows; §7.4 mutants (S-3 intent, Animate X1) | Tasks 10–12; Tasks 5, 8; Task 2 Step 9, Task 10 Step 6 |
| §8 W2 group gate | Task 13 Step 11; checklist 8–14 |
| §9 risks: redirect storms (latch untouched), pre-auth routes bouncing to `/intro`, someone moving another person's code | Not edited `home_screen.dart`; Task 4; Task 10 |

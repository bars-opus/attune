# 05 — From store page to first value: first open, sign-in, choosing a path and onboarding

**Researcher:** 05 · **Date:** 2026-10-24 · **Scope:** store listing → first open → sign-in → "What brings you to Attune?" → the first session of each path (In a relationship / Single and open to dating / Just for me). This covers permissions, question design, motion, accessibility and measurement.
**Builds on:** `2026-10-16-couples-research/01-market-reviews.md` (market complaints) and `06-synthesis-roadmap.md` (§3 safety floor, §4.0 measurement, §5 couple profile, §9 what not to build). This document does not repeat them.

---

## 1. How this was researched

**Method**
1. **Repo baseline (read-only).** Read the code and docs behind today's first run:
   - `lib/features/auth/**`, `lib/features/onboarding/**` and `lib/app/routing/app_router.dart`;
   - `lib/core/notifications/services/onesignal_service.dart`, `lib/core/ui/motion/*` and `lib/app/theme/design_tokens.dart`;
   - `AUTH_ONBOARDING_ENGINE.md`, `ATTUNE_MASTER_SPEC.md` §8.8 and decisions 18/23/26/29, and `DATING_MODE_SPEC.md` §4.1;
   - the dating age-verification migration and the 2026-07-10 chat motion spec.
2. **Primary platform and standards sources, fetched this session:**
   - Apple: App Review Guidelines 4.8 and 5.1.1; HIG pages on Onboarding, Privacy, Managing accounts and Motion; App Store product-page guidance.
   - Android: developer docs on runtime permissions, notification permission, location, the photo picker and Play Age Signals.
   - Meta's WhatsApp authentication-template docs.
   - Supabase docs on identity linking, the Send SMS Hook and passkeys.
   - Twilio Verify best practices and fraud docs.
   - GOV.UK Design System pages on dates, form structure and equality information.
   - The FTC's COPPA FAQ and W3C WCAG 2.3.3.
   - Flutter's M3 motion constants, read from the local Flutter SDK `motion.dart`.
3. **Research literature:**
   - Villar, Callegaro & Yang 2013 (meta-analysis of progress indicators);
   - Tan et al. CHI 2014 (permission explanations);
   - Lee & Narayanan 2021 (recycled phone numbers);
   - Spiel, Haimson & Lottridge 2019 (gender questions);
   - Mavletova & Couper (mobile survey paging vs scrolling).
4. **Industry data:**
   - FIDO Passkey Index (Oct 2025);
   - Airship push opt-in medians, via a secondary source;
   - AppsFlyer retention data, via Braze;
   - Baymard;
   - DataReportal Digital 2026 Ghana, StatCounter (Ghana, Sept 2026) and the cable.co.uk data-price study.
5. **App Store reviews (Anecdote grade).** I pulled 745 reviews (Paired 200, Agapé 200, Lasting 150, Bumble 150, Flamme 45) from Apple's public RSS feed, which is the same method as `01` §0. I keyword-tagged them for sign-up, OTP, onboarding length, invites, gender/pronouns and solo use, then hand-read every hit.
6. **Product teardowns (Weak grade).** Appcues GoodUX, RevenueCat, Pratt IxD critiques, Lazyweb and UX Collective, used for Headspace, Calm, Duolingo, Noom and Finch.

**Limits (read before relying on this)**
- **The shared web-search budget ran out partway through.** Items I could not verify this session are marked **[unverified]**:
  - Ghana's median mobile speed (Ookla);
  - GSMA's usage-gap figures;
  - a single-source claim that Google requires dating apps to block declared minors;
  - Google's "emerging markets" app-size multiplier, where the primary page returned 403;
  - how Tinder and Hinge route non-binary users in matching;
  - the status of Ghana's anti-LGBTQ bill after June 2026;
  - Stoic and Daylio onboarding, which I did not reach.
- **Apple's RSS feed throttled.** Only 15 of the 70 pages requested came back. Hinge and Between returned nothing.
- **No primary user research.** I ran no interviews or usability tests with Ghanaian or diaspora users and did no device testing. Competitor flows come from teardowns, not from installing the apps.
- **Attune has no live store listing or real users**, so the "store promise vs first screen" analysis is prescriptive, not diagnostic.

**Evidence grades:**
- **S** (Strong): meta-analysis, large RCT or large dataset.
- **M** (Moderate): peer-reviewed study, large survey or official platform policy.
- **W** (Weak): single small study, press or vendor claim.
- **A** (Anecdote): reviews or forum posts.

---

## 2. Baseline: what Attune's first run does today

| Step | Today (file) | Issue for the new flow |
|---|---|---|
| First open | `IntroScreen` shows "Welcome to Attune", a horizontal list of user-manual modules, a legal link and "Get Started" → Home with Opinions as a guest (`intro_screen.dart`, `app_router.dart` redirect while `isFirstLaunch`). | Guest Opinions already gives value before sign-up (good). Nothing previews the three paths. The intro carousel shows manual modules, not the store promise. |
| Sign-in entry | Chat tab → `LoginProfile` → legal bottom sheet → `LoginScreen`. | Fine. Legal consent and AI disclosure need one clear moment (decision 29: "disclosure is not deferred"). |
| Phone OTP | SMS by default plus a WhatsApp toggle (`login_phone_step.dart`), 60 s resend cooldown (`login_screen.dart` `_otpResendCooldown`), `AutofillHints.oneTimeCode` on every box (`verification_code_field.dart`), and a country picker defaulting to Ghana (`phone_country.dart`). | **Voice fallback is a stated launch requirement (`AUTH_ONBOARDING_ENGINE.md`) but is not in code.** No escalating resend schedule and no automatic channel switch. |
| Name | `ProfileSetupStep` requires ≥2 matches of `[a-zA-Z]`. | **Rejects names written only in non-Latin scripts** (Arabic, Chinese, Amharic, Devanagari…), which conflicts with "worldwide". The subtitle still says "Opinions and forums stay anonymous", and Forums are being removed. |
| Fork | `OnboardingModeStep`: "Are you single or in a relationship?" with two options; subtitle "This first choice routes your entire Attune experience." | Two options, not three. The subtitle makes the choice sound irreversible. |
| Single track | 26-item attachment quiz + 3 anchors **before Home** (`onboarding_flow.dart`), "about 3–5 minutes" + "2–3 minutes". | 5–8 minutes of questions before any value (see §3.5). |
| Couples track | Invite/waiting (`CouplesWaitingStep`), 48 h reflection, day-7 pivot (Spec 5). | Matches decision 29. The couple profile does not exist yet (03 inventory: "couple types absent"). |
| Notifications | `OneSignalService` calls `_maybeAskForPermission()` straight after `_sdk.login(userId)`, so **the OS prompt fires right after sign-in**. | No context, against both platforms' guidance (§3.6). Android counts two denials as permanent. |
| Date of birth | Not collected at sign-up. Dating has a **backend-only** `verify_dating_age()` writer (`20260712140000_dating_age_verification_writer.sql`). The spec says DOB is "never client-editable". | Owner now wants DOB for everyone at sign-up. Self-declared DOB is a *declared* age. Dating may still need a stronger level (§5.1). |
| Motion | The onboarding card advances over **900 ms** (`onboarding_deck_card.dart` `_advanceDuration`). Reduce-motion is respected (`reduceMotionOf`). | The app's own motion language says 150–320 ms (`2026-07-10-chat-delight-motion-design.md` §2 rule 4). |
| Analytics | Only `sentry_flutter`; no product-analytics SDK (`pubspec.yaml`). | Good starting point for privacy-preserving measurement (§3.9). |
| SDK versions | `supabase_flutter: ^2.1.0`. | Passkeys need `supabase_flutter` ≥ 2.15.0 (§3.2.4). |

---

## 3. Findings

### 3.1 Store page → first open

**What the store page can promise, and where.**
- Apple shows up to 10 screenshots. "The first one to three images will appear in search results when no app preview is available." Previews can run up to 30 s, "autoplay with muted audio", and should use footage captured on the device. The subtitle is 30 characters. Screenshots should be "captured from your app's UI." ([Apple, product page](https://developer.apple.com/app-store/product-page/)) **M**
- Apple's onboarding guidance:
  - design a flow that's "fast, fun, and optional";
  - "Teach through interactivity";
  - "Postpone nonessential setup flows";
  - "Avoid displaying licensing details within your onboarding flow… Let the App Store display agreements";
  - "Don't let large downloads hinder onboarding."

  Source: [Apple HIG, Onboarding](https://developer.apple.com/design/human-interface-guidelines/onboarding). **M**

**Promise–reality mismatch is a named failure in this category.**
- Agapé's ads didn't mention its three-connection gate: "Learning this as I was trying to sign up was really disheartening" (Microbiolab, 2023-11). "Sad I need to rope others in to try… I can't even get through the sign up process" (QuantumPug, 2024-09). (App Store RSS) **A**. The `01` corpus found 25 such reviews (`01` §2.1). **A**
- Bumble: "It makes you set up your entire profile then locks you out if you don't agree to accept facial recognition" (Herrrrbbb, 2026-10-10). **A** The lesson: **disclose every gate (18+, phone number, partner needed or not, Dating verification) before the person invests time.**
- Lasting asked for a rating before the user had done anything: "Literally asked for a review before we ever started… all it's done is ask for a subscription payment and a rating" (MrMattBarr, 2019). **A** Apple: "Prefer letting people experience your app… before prompting them for ratings or purchases" ([HIG Onboarding](https://developer.apple.com/design/human-interface-guidelines/onboarding)). **M**

**First-session stakes**

| Data point | Value | Grade |
|---|---|---|
| Cross-industry retention (2025–26 aggregates) | ≈25–26% day 1, 11–13% day 7, 5–7% day 30. Quashbugs notes these trace back to older AppsFlyer (2021) and Statista (2020) data ([Quashbugs](https://quashbugs.com/blog/app-retention-rate-statistics)). | W |
| Dating apps, day 30 (AppsFlyer data via Braze) | 4.0% iOS, 2.7% Android ([Braze](https://www.braze.com/resources/articles/mobile-app-retention)) | W–M |
| AppsFlyer 2025 retention report | 2024 retention "flat to slightly down" vs 2023, ≈11K apps, 10.6B installs ([AppsFlyer](https://appsflyer.com/?p=453529)) | M (large vendor dataset) |

I found no category data for relationship-wellness apps. **Unknown.**

**Value before sign-up**
- Apple 5.1.1(v): "If your app doesn't include significant account-based features, let people use it without a login" ([App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)). **M** Attune's chat, journal and Dating are account-based, so requiring an account is allowed. HIG still says "Delay sign-in for as long as possible. People often abandon apps when they're forced to sign in before they can do anything useful" ([HIG, Managing accounts](https://developer.apple.com/design/human-interface-guidelines/managing-accounts)). **M**
- Duolingo moved sign-up after the first lesson. A former growth lead recalls "about a 20% increase in DAUs" ([Taplytics, quoting First Round interview](https://taplytics.com/blog/duolingo-ab-test-onboarding)). **W** (recollected, not published by Duolingo.)
- Baymard: 18% of US shoppers abandoned a checkout because "the site wanted me to create an account" ([Baymard](https://baymard.com/lists/cart-abandonment-rate)). **M** (large survey, e-commerce context.)
- Agapé: "Pretty but too long for onboarding. Not interested in providing all my personal detail to just look around" (floridaStyles, 2023-12). **A**
- Attune already lets guests read Opinions (owner decision). The gap is that a guest cannot see what each path *is* before giving a phone number.

**Install size and data cost (Ghana-first)**
- Google Play found install conversion falls about **1% per extra 6 MB** for apps under 100 MB, with a larger effect in emerging markets ([Google Play, 2017](https://medium.com/googleplaydev/shrinking-apks-growing-installs-5d3fcba23ce2), confirmed from the search snippet; the page returned 403). **M**. The exact emerging-market multiplier is **[unverified]**.
- Ghana:
  - 1 GB of mobile data averaged **US$0.40** in 2023 ([cable.co.uk dataset](https://bestbroadbanddeals.co.uk/mobiles/worldwide-data-pricing/)). **M** It is cheap in dollars, but the cost relative to income and small bundle sizes still matter **[unverified for current tariffs]**.
  - 26.3 M internet users (74.6% penetration). 96% of connections are 3G-or-better *capable*, which is not the same as being used ([DataReportal 2026](https://datareportal.com/reports/digital-2026-ghana)). **M**
  - Android ≈ **70.8%**, iOS ≈ 29.1% of mobile web traffic (Sept 2026) ([StatCounter](https://gs.statcounter.com/os-market-share/mobile/ghana)). **M** This measures traffic, not installed devices.
- Apple HIG: "include enough media… to prevent people from having to wait for downloads" ([HIG Onboarding](https://developer.apple.com/design/human-interface-guidelines/onboarding)). **M**

**Screenshot conventions for relationship and dating apps.** I found no systematic study. **Unknown.**
- `01` documents a two-sided representation tension: queer couples praised Paired's inclusive imagery, and conservative couples asked to hide it (`01` §2.1). **A**
- For Ghana this becomes a **legal** question if the anti-LGBTQ bill becomes law (§3.5.6). It goes to the owner as an open question (Q12).

### 3.2 Sign-in

#### 3.2.1 Phone OTP: channels

| Channel | Reach | Autofill | Failure modes | Evidence |
|---|---|---|---|---|
| **SMS** | Any phone, no data needed | **Android:** SMS Retriever gives zero-tap autofill but needs an 11-character app hash in the message. SMS User Consent gives one tap with no hash. Neither needs `READ_SMS` ([Google](https://developers.google.com/identity/sms-retriever/choose-an-api)) **M**. **iOS:** `oneTimeCode` autofill, best with the origin-bound ending `@domain #123456` ([web.dev](https://web.dev/articles/sms-otp-form)) **M** | Carrier routing, MTN Ghana sender-ID registration (enforced since July 2026), Firebase +233 bug (`AUTH_ONBOARDING_ENGINE.md`) **M (internal)**. A cluster of Bumble 1★ reviews in Sept 2026: "doesn't send the verification code… never let me create the account", "I tried 2 of my phone numbers and nothing" (4 reviews in 3 days) **A** | |
| **WhatsApp** | Needs WhatsApp and data on that number. 93% of Ghanaian internet users used WhatsApp (Q3 2024) ([Statista](https://statista.com/statistics/1171534/leading-social-media-platforms-ghana)) **W–M** | Authentication templates offer copy-code, **one-tap** (Android, "the preferred solution") and **zero-tap** (Android). **iOS 26+ offers keyboard autofill from the WhatsApp notification with no integration.** Text is fixed and preset. Expiry footer allows 1–90 min ([Meta](https://developers.facebook.com/docs/whatsapp/business-management-api/authentication-templates)) **M** | WhatsApp often runs on a different SIM from the one typed (dual-SIM is common) **[hypothesis, test in Ghana]**. Meta advises: "Tell users the code goes to their WhatsApp number" **M** | |
| **Voice call** | Any phone; useful for low literacy and failed SMS routes | None (user listens) | Cost; misheard digits | Required automatic fallback per `AUTH_ONBOARDING_ENGINE.md` **M (internal)**. Twilio's reference flow includes "voice channel fallback" ([Twilio](https://www.twilio.com/docs/verify/developer-best-practices)) **M** |

**Plumbing**
- Supabase's native phone providers do not offer voice. The **Send SMS Hook** "replaces Supabase's built-in SMS sending". Documented uses include "routing through a regional provider, using channels like WhatsApp, and failing over to a second provider" and adding an app hash to the body ([Supabase](https://supabase.com/docs/guides/auth/auth-hooks/send-sms-hook)). **M**
- Supabase defaults: one OTP per 60 s, OTP expiry 1 h, 30 SMS/hour (project-wide default in the CLI config) ([Supabase phone login](https://supabase.com/docs/guides/auth/phone-login)). **M**
- Twilio recommends "1 request / 30 seconds per phone number with exponential backoff", 6-digit codes, a 10-minute validity, and separate country-code and number fields ([Twilio](https://www.twilio.com/docs/verify/developer-best-practices)). **M**
- **Toll fraud ("SMS pumping")** gets worse when sign-up is worldwide. Twilio's controls are Fraud Guard (blocks suspicious destination prefixes), Geo Permissions ("disabling every country you do not plan to message") and rate limits per country group ([Twilio](https://www.twilio.com/docs/verify/preventing-toll-fraud)). **M** A Send-SMS-Hook route needs equivalent controls in the Edge Function.

#### 3.2.2 Country picker and number entry
- Attune already parses numbers with `phone_numbers_parser` and defaults to Ghana. Twilio advises separate country-code and number fields and E.164 storage. **M**
- Ghanaians commonly write numbers in national format (`024 123 4567`); the leading `0` must be dropped after `+233` **[practice; low risk]**. A diaspora user will often have a UK/US SIM but think of themselves as Ghanaian. **The default country should come from the SIM or the device region, not from IP or a hard-coded Ghana.**

#### 3.2.3 Adding Apple/Google later without duplicate accounts
- **Apple 4.8, verbatim:** apps that use "a third-party or social login service (such as… Google Sign-In…) to set up or authenticate the user's primary account… must also offer as an equivalent option another login service" that limits data to name and email, allows a private email, and doesn't use interactions for ads without consent. The exemption "Your app exclusively uses your company's own account setup and sign-in systems" covers phone OTP today ([App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)). **M** **Adding Google Sign-In on iOS triggers 4.8**, and Sign in with Apple is the simplest way to comply. Reviewers sometimes interpret this inconsistently ([Apple forum](https://developer.apple.com/forums/thread/765145)). **A**
- **Supabase linking:**
  - "Supabase Auth automatically links identities with the same email address."
  - Manual linking is beta, must be enabled, and needs a signed-in user. Native Apple and Google use `linkIdentityWithIdToken()` in Dart.
  - `unlinkIdentity()` needs at least two identities.
  - The docs don't cover phone-only users ([Supabase](https://supabase.com/docs/guides/auth/auth-identity-linking)). **M**
  - **Inference:** an Attune account is phone-only and has no email, so an Apple or Google sign-in started **while signed out** creates a **second, separate user**. Apple's private relay email makes email matching impossible anyway. **Duplicates are avoided only if the phone stays the anchor identity and new methods are linked from a signed-in session.**
- HIG: when someone deletes an account created with Sign in with Apple, revoke the tokens ([HIG Managing accounts](https://developer.apple.com/design/human-interface-guidelines/managing-accounts)). **M**

#### 3.2.4 Passkeys
- FIDO Passkey Index (Oct 2025): **93%** sign-in success vs 63% for "other methods", and **8.5 s vs 31.2 s** average sign-in time ([FIDO](https://fidoalliance.org/wp-content/uploads/2025/10/FIDO-Passkey-Index-October-2025.pdf)). **M** (consortium member data; "other methods" includes OTP and social login.)
- Supabase passkeys went to **beta on 2026-05-28**. They use discoverable credentials, so no phone or username is typed. Registration "requires an existing, confirmed, non-anonymous user". Client support needs `supabase_flutter` ≥ 2.15.0 ([Supabase changelog](https://supabase.com/changelog/46458-passkeys-for-supabase-auth-beta), [docs](https://supabase.com/docs/guides/auth/passkeys)). **M**
- Apple HIG: "If you don't use Sign in with Apple… prefer using a passkey" ([HIG](https://developer.apple.com/design/human-interface-guidelines/managing-accounts)). **M**
- **Fit for Attune:** passkeys work as a *second* method added after the phone account exists. For returning users they mean faster re-sign-in with no SMS cost and no roaming-SIM problem for the diaspora.
- **IPV caveat:** a passkey synced to a shared or partner-controlled Google or iCloud account is an access path. It belongs in F7 "Where you're signed in" (06 §3). **[inference from 06 threat model]**

#### 3.2.5 Recycled phone numbers
- Lee & Narayanan (Princeton CITP, 2021) sampled 259 numbers available to new subscribers at two US carriers. **171** were tied to existing accounts on popular sites, **100** to leaked credentials, and 215 were "recycled and vulnerable" to at least one attack. The FCC estimates about 35 M US numbers are disconnected each year ([project](https://recyclednumbers.cs.princeton.edu/), [CITP blog](https://blog.citp.princeton.edu/2021/05/03/phone-number-recycling-creates-serious-security-and-privacy-risks-to-millions-of-people/)). **M**
- **Ghana:** MTN said SIMs deactivated in the 2023 re-registration drive would be **recycled** if not reactivated, and blocked 5.4 M ([Graphic](https://www.graphic.com.gh/news/general-news/telcos-remove-unregistered-sim-cards-from-database-today.html), [Developing Telecoms](https://developingtelecoms.com/telecom-business/telecom-regulation/14922-ghana-sets-hard-deadline-for-sim-registration.html)). **M** I found no standing NCA inactivity-to-reassignment period. **Unknown.**
- **How messengers handle it:**
  - WhatsApp: an account "unused for 45 days and then… newly activated on a different mobile device" is treated as recycled, and old profile data is removed ([WhatsApp FAQ](https://whatsapp.com/faq/en/general/24068052)). **M**
  - Signal: an optional **Registration Lock PIN** blocks re-registration and expires after 7 days of inactivity ([Signal](https://support.signal.org/hc/en-us/articles/360007059792)). **M**
- **Why it matters more for Attune:** a recycled number that signs in by OTP would open someone else's couple chat, journal and Dating history. For an intimacy app this is a top-severity confidentiality failure.

### 3.3 Path choice: how multi-mode apps fork

| App | How it forks | Switching later | What to take | Grade |
|---|---|---|---|---|
| Bumble | Date / BFF / Bizz modes in one app. BFF moved to a standalone app in July 2023 ("Bumble For Friends"); Bizz is being "phased out across all countries" ([BusinessWire](https://www.businesswire.com/news/home/20230726935186/en/Bumble-Inc.-Introduces-Bumble-For-Friends-Friendship-finding-App), [Bumble help](https://support.bumble.com/hc/en-us/articles/30208230972189-Availability-of-Bumble-Bizz)) | Delete Date mode and keep the others (older help page) | Modes with **separate profiles** were eventually split apart. Attune's paths should share one *personal* core, not three profiles. | M (press/help) |
| Hinge | Dating only. Gender: Man / Woman / Non-binary, plus "more than 50" specific identities and a write-in. Preferences "are not visible to anyone else" ([Hinge help](https://help.hinge.co/hc/en-us/articles/4407404339603-How-did-Hinge-decide-which-gender-options-to-include), [2025 LGBTQ report](https://hinge.co/press/2025-LGBTQ-Report)) | Edit preferences any time | Model for the gender question (§5.2) | M |
| Headspace | Early question: what brought you here (4 reasons) ([Appcues](https://goodux.appcues.com/blog/headspaces-mindful-onboarding-sequence)) | Profile | Intent framing | W |
| Calm | "What brings you to Calm?" multi-select (sleep, stress…) then experience level ([Appcues](https://goodux.appcues.com/blog/calm-app-new-user-experience)) | Settings | Teardowns criticise "personalisation" steps that change nothing | W |
| Duolingo | Language → "how did you hear" → level → "why are you learning" → daily goal → notifications → lesson; "over 50 distinct steps" ([UX Collective](https://uxdesign.cc/duolingos-onboarding-2-years-on-3cbccad139f7)) | Settings | Goal before value has been criticised; the push ask comes before the first lesson | W |
| Noom | Very long quiz (40 to 113 screens, depending on source) before the paywall ([RevenueCat](https://www.revenuecat.com/blog/growth/web-to-app-onboarding-funnel)) | — | **Do not copy.** The claimed conversion lift has no controlled evidence, and the sunk-cost framing conflicts with SOUL. | W |
| Finch | Egg, pet name, pronouns, traits, then more questions; 46 steps ([Lazyweb](https://lazyweb.com/canvas/flows/finch/onboarding)). A critique says it "overwhelms users whose primary goal is to 'start self-care quickly'" ([Pratt IxD 2026](https://ixd.prattsi.org/2026/02/design-critique-finch-self-care-pet-ios-app/)) | — | Delight is not the same as length | W |
| Lasting / Relish | Both work solo. Lasting: "many people who use Lasting are using it alone" ([GMA 2018](https://ws.goodmorningamerica.com/family/story/meet-lasting-dating-app-couples-55333167)). Relish is "designed to be used individually or as a couple" ([DatingAdvice](https://www.datingadvice.com/for-women/relish-a-relationship-training-app-for-couples)) | Add partner later | The couples path must be useful alone | W |
| Flamme | Onboarding asked what to work on (communication, money, family) → "This app thinks every couple has issues!" (`01` §2.1) | — | Never ask about problems at onboarding (`06` §5.2, §9) | A |
| Agapé | Free tier gated behind 3 connections | — | Never gate value on recruiting others | A (25 reviews, `01`) |
| Stoic, Daylio, Paired (exact first screens) | **Not reached this session** | — | — | Unknown |

**Benchmarks on how many questions**
- An automated capture of 119 quiz-style apps found an average of **3.9** question screens, p90 of 10, and a long tail to 65. Their rule: "if a question doesn't change the plan, feed, or paywall, cut it" ([Lazyweb](https://www.lazyweb.com/research/onboarding-flow-length-benchmark-steps.md)). **W**

**Inclusive phrasing.** "What brings you to…" asks about **intent**, not status. That matters because:
- people who are partnered but whose partner won't join, separated, widowed, or in a situationship need somewhere to go;
- "Just for me" must explicitly welcome partnered people. The journal and Healing are not "for singles".

Agapé has a poly triad praising it ("Most of the apps out there are for monogamous… only", 2024-08) **A**. Attune's relationship model is a dyad. It should neither claim otherwise nor ask exclusivity questions.

### 3.4 Couples-app onboarding

**When to invite**
- Cupla's invite link is part of the initial onboarding ([Cupla help](https://help.cupla.app/article/9-how-do-i-invite-my-partner)). **W**
- Paired adds the anniversary later from the Us tab, after pairing ([Paired help](https://support.paired.com/en/articles/164640-how-can-i-add-or-edit-special-dates-and-anniversaries)). **M** (its own docs).
- Counter apps (Been Together, Together–Love Counter) ask for the start date at setup. **W**
- Decision 29 already puts the invite at the end of Ask 1 with no AI vocabulary. Nothing found contradicts it.

**What they collect.** The start date or anniversary dominates. Paired users ask for "filters for relevance (married, kids, orientation)" (`01` §2.1). **A** `06` §5.1 already defines the field model (stage, distance, intent, household), and the owner has since fixed the stage values (BRIEF).

**The partner who never joins**
- Lasting: "Unsubscribe | refusal of partner to participate" (2019). **A**
- Paired: "when one of my partners refused to fully participate…" (2026-04). **A**
- Coral: "my husband kept ignoring it" (`01` §2.3). **A**
- Attune already has the 48 h solo reflection and the day-7 pivot (MASTER_SPEC §8.8, Spec 5).
- Market lesson: the inviter must get **value on day 0 without the partner**, and never a wall.

**Pronouns and partner references**
- Three Paired reviews in 2026 object to the app calling a spouse "they": "My wife is a woman and the questions use 'they'… It's distracting" (DifferentiatedW, 2026-01); "it kept referring to me and my husband as 'them/they'" (Keahdb30, 2026-05); "Very Woke… they them pronouns" (OG-Money, 2026-05). **A**
- Implication: copy should **use names** (and the couple's chosen chat name, per memory `couple_name_wording`). Then no pronoun question is needed in the Relationship path at all.

**Shared profile editing conflicts.** I found no market evidence on how couples apps resolve disagreements about shared fields. **Unknown.** `06` §5.3 rule 6 already sets "shared fields change silently (no activity feed)".

**Ghana and West Africa**
- Customary marriage is legally recognised in Ghana (Customary Marriage and Divorce (Registration) Law, 1985, PNDCL 112). The "engagement" ceremony is often the customary marriage itself, with a church or civil wedding later. **M (statute), [not re-fetched; cultural reviewer to confirm usage].**
- So "Engaged" vs "Married" is ambiguous locally, and some couples have **two** marriage dates.
- Many unmarried couples do not live together for religious or family reasons. "Apart" must not read as a lesser stage.

### 3.5 Progressive profiling and question design

#### 3.5.1 One question per screen vs forms
- GOV.UK: "Start by splitting the form so that each page has just one thing." This helps people "understand what you're asking", "use the service on a mobile device" and "recover easily from form errors". It also lets teams "save answers as users go" and "capture analytics for each question". Put eligibility questions first ([GOV.UK Service Manual](https://www.gov.uk/service-manual/design/form-structure)). **M** (official, qualitative)
- Mobile-survey experiments (Mavletova & Couper, ~2,100 completes, Russian panel): scrolling or grouping was faster with fewer technical problems. **Breakoff differences were not significant** ([slides](https://cts.hse.ru/data/2014/04/03/1275940820/Mavletova_Couper_Mobile_7-th_MESS_Workshop_2013.pdf)). **M–W**
- **Synthesis:** one thing per page gives comprehension and error recovery. Grouping saves time. Neither reliably changes drop-off. Use one question per screen for anything sensitive or that branches. Group only fields that are parts of one answer (day/month/year).

#### 3.5.2 Progress indicators
- Villar, Callegaro & Yang (2013, *Social Science Computer Review* 31(6):744–762), a meta-analysis of 32 experiments:
  - constant-speed indicators did **not** reduce drop-off, and **increased** it where incentives were small;
  - **fast-to-slow** indicators reduced drop-off; **slow-to-fast** increased it ([City Research Online](https://openaccess.city.ac.uk/id/eprint/14427/)). **S–M** (meta-analysis; one informal critique of coding.)
- **Implication:** in very short flows, a progress bar adds nothing. Where one is shown, front-load the easy questions.

#### 3.5.3 Skip and "prefer not to say"
- GOV.UK puts "Prefer not to say" on each sensitive question, after an "or" divider, with an explainer: "These questions are optional." It also says to explain "why you're asking, and what you'll do with the answers" ([GOV.UK equality information](https://design-system.service.gov.uk/patterns/equality-information/)). **M**

#### 3.5.4 Date of birth and the age gate
- **Input:** "memorable dates such as dates of birth should be collected with the Date input component": three text fields (day, month, year), an example with day ≥ 13 and month ≤ 9, and "a calendar must never be the only input option" ([GOV.UK dates](https://design-system.service.gov.uk/patterns/dates/), [date input](https://design-system.service.gov.uk/components/date-input/)). **M**
- **Neutral age gate (FTC COPPA FAQ):**
  - ask neutrally;
  - the field "does not default to an age 13 or over";
  - don't hint that features are unavailable to younger users;
  - don't use an "I am over 12" checkbox;
  - don't offer a drop-down of only qualifying birth years;
  - block back-button re-entry with "technical means, such as a cookie" ([FTC](https://www.ftc.gov/business-guidance/resources/complying-coppa-frequently-asked-questions)). **M**

  The FTC's NGL order applied a neutral gate at **18** ([ZwillGen](https://www.zwillgen.com/ftc-state-ag/were-not-gonna-lie-ftcs-settlement-contains-novel-requirement-neutral-age-gate-u18/)). **W–M**
- **Platform age signals:**
  - Apple's **Declared Age Range** API returns an age range without a birthdate. Under Texas SB 2420, Apple began applying the requirements to new Texas accounts on **2026-06-04**. Utah (2026-05-07) and Louisiana (2026-07-01) are reported to follow ([9to5Mac](https://9to5mac.com/2026/06/03/apple-says-texas-app-store-age-assurance-rules-start-tomorrow-after-court-ruling/), [AppleInsider](https://appleinsider.com/articles/26/06/03/age-verification-now-mandatory-for-app-store-users-in-texas)). **M**
  - Google's **Play Age Signals** (beta) returns signals in Brazil (from 2026-03-17) and Texas (accounts after 2026-05-28). Its terms say the signal may be used "only to provide age-appropriate content and experiences", **not** for "advertising, marketing, user profiling, or analytics" ([Android](https://developer.android.com/google/play/age-signals/overview)). **M**
  - A single blog claims Google has required dating apps to use "Restrict Declared Minors" since 2026-01-28 ([qawerk](https://qawerk.com/blog/google-play-age-verification-usa-state-laws/)). **W [unverified]**
- **Internal constraint:** `DATING_MODE_SPEC.md` §4.1 says DOB is "Never display; derive age server-side", corrected "through protected flow". The dating migration forbids any client-writable age. **M (internal)**

#### 3.5.5 Gender and pronouns
- Spiel, Haimson & Lottridge (ACM *Interactions*, 2019) say to avoid binary-only categories, avoid assuming, and avoid one-size-fits-all. Their earlier recommendation was to ask whether people are "a man, woman, and/or something else", with the last option revealing free text ([Deep Blue](https://deepblue.lib.umich.edu/items/ff7e9621-9059-4672-a56c-89c6b17fcf13)). **M**
- GOV.UK keeps sex, gender identity and sexual orientation as separate optional questions, each with "Prefer not to say". It notes the data "is likely to be special category personal data", needs data-protection sign-off, and that gender identity "can change over time", so people need a way to update it ([GOV.UK](https://design-system.service.gov.uk/patterns/equality-information/)). **M**
- Hinge: three top-level options plus 50+ specific identities and a write-in; preferences invisible to others (§3.3). **M**
- **How non-binary users are routed in other apps' matching** ("show me to people looking for…"): **[unverified this session]**.

#### 3.5.6 Sensitive questions: trust copy and LGBTQ+ safety
- **Explaining why raises consent.**
  - Tan et al. (CHI 2014, n=772): permission requests with developer explanations were "significantly more likely to be approved". Only about 19% of 4,400 iOS apps included one ([paper](https://blues.cs.berkeley.edu/wp-content/uploads/2014/07/p91-tan.pdf)). **M**
  - A Google study of Android users reports deny rates roughly **halved** with explanations ([Google Research](https://research.google/pubs/pub50646/), via search snippet). **W–M**
- **Grindr's tiered approach for high-risk countries:** distance turned off, free safety features, weekly risk alerts, and warnings that "law enforcement has been known to use social media apps… for potential entrapment" ([Grindr](https://grindr.com/blog/mitigating-risk-for-the-global-grindr-community), [Grindr help](https://help.grindr.com/hc/en-us/articles/1500009290262-Safety-tips)). **M** (company policy.)
- **Ghana:**
  - Parliament passed the Human Sexual Rights and Family Values Bill on **2026-05-29**. Reported provisions include up to 3 years' imprisonment for identifying as LGBTQ and a "duty to report" ([PinkNews](https://www.thepinknews.com/2026/06/01/ghanas-parliament-approves-anti-lgbtq-bill-that-criminalises-identifying-as-queer/), [ABC7/AP](https://abc7.com/post/ghanas-parliament-passes-controversial-new-anti-lgbtq-bill/14479690/), [Wikipedia](https://en.wikipedia.org/wiki/Ghanaian_anti-LGBTQ_bill)). **M**
  - The President said in 2025 he would sign it if passed ([GNA](https://gna.org.gh/2025/11/i-will-sign-anti-lgbtq-bill-if-passed-by-parliament-mahama/)). **M**
  - **Assent status after June 2026: [unverified].**
  - Implications: "Who you want to meet" is orientation data and could become evidence. The safety notes must also cover "duty to report" risk from people you know, not only police entrapment.

### 3.6 Permissions priming

| Rule | Apple | Android | Grade |
|---|---|---|---|
| Ask in context | "Request permission only when your app clearly needs access… Ideally, wait… until people actually use an app feature" ([HIG Privacy](https://developer.apple.com/design/human-interface-guidelines/privacy)) | "Ask for a permission in context, when the user starts to interact with the feature" ([Android](https://developer.android.com/training/permissions/requesting)) | M |
| Pre-permission screen | **"Include only one button"**, titled like "Continue" or "Next", never "Allow". **"Don't include additional actions… like offering an option to close or cancel"** (HIG Privacy) | Educational UI when `shouldShowRequestPermissionRationale()` is true, **with "a 'cancel' or 'no thanks' button"** | M |
| Denial | Respect it; 5.1.1(iv): "not attempt to manipulate, trick, or force… provide alternative solutions" ([Guidelines](https://developer.apple.com/app-store/review/guidelines/)) | Denying twice is "considered a permanent denial". "Don't link to system settings in an effort to convince the user." "Persistent nagging… is not respectful" | M |
| Notifications | **Provisional authorisation**: quiet "trial" delivery to Notification Center with no prompt ([Apple](https://developer.apple.com/documentation/usernotifications/asking-permission-to-use-notifications)) | Android 13+: "notifications are off by default" on new installs. Good triggers are user actions, or "after the user has launched the app a few times" ([Android](https://developer.android.com/develop/ui/views/notifications/notification-permission)) | M |
| Location | Location button gives one-time access ([HIG](https://developer.apple.com/design/human-interface-guidelines/privacy)) | Approximate is "within about 3 square kilometers". The app "should still work when the user grants only approximate" ([Android](https://developer.android.com/develop/sensors-and-location/location/permissions)) | M |
| Photos / contacts | 5.1.1(iii): "use the out-of-process picker or a share sheet rather than requesting full access to protected resources like Photos or Contacts" | The photo picker grants "only selected images"; backport to Android 4.4 through Play services ([Android](https://developer.android.com/training/data-storage/shared/photopicker)) | M |

- **Opt-in rates (Airship medians, via secondary source):** Android **59.5% (2024) → 53.3% (2025)**; iOS about 49% in both years. The Android decline is tied to the Android 13 runtime permission ([Admiral Media summarising Airship](https://admiral.media/push-notification-strategy-mobile-apps/), [Airship 2026](https://www.airship.com/mobile-app-push-notification-benchmarks-for-2026/)). **W–M**
- **The platforms conflict on pre-permission screens.** Apple forbids a cancel on a full pre-alert screen. Android's rationale UI requires one. **Resolution:** don't use full-screen pre-alerts. Put the ask *inside the feature*: one line of reason plus a single "Turn on" button. Dismissing is just carrying on with the screen, so Apple sees no "cancel" on a pre-alert and Android has a natural "no thanks".
- **Attune today:** the push prompt fires right after sign-in (§2). That burns the iOS one-shot and one of Android's two denials before the user knows why notifications matter.

### 3.7 Motion and animation

**Tokens.** Flutter's `Durations` and `Easing` mirror M3. Values read from the local Flutter SDK `packages/flutter/lib/src/material/motion.dart` ([API](https://api.flutter.dev/flutter/material/Durations-class.html)). **M**

| Token | ms | | Easing | Cubic |
|---|---|---|---|---|
| short1–4 | 50 / 100 / 150 / 200 | | `emphasizedDecelerate` | (0.05, 0.7, 0.1, 1.0) |
| medium1–4 | 250 / 300 / 350 / 400 | | `emphasizedAccelerate` | (0.3, 0.0, 0.8, 0.15) |
| long1–4 | 450 / 500 / 550 / 600 | | `standard` | (0.2, 0.0, 0.0, 1.0) |
| extralong1–4 | 700 / 800 / 900 / 1000 | | `standardDecelerate` / `standardAccelerate` | (0,0,0,1) / (0.3,0,1,1) |

**Guidance**
- **Material motion system.** **Shared axis** is for elements with "a spatial or navigational link". An **onboarding flow runs along x**, a stepper along y, and parent–child navigation along z. The x and y axes slide and fade about **30 dp**. Pairs of transitions share a `forward` flag so back navigation reverses ([Material](https://material.io/design/motion/the-motion-system.html), [MaterialSharedAxis](https://developer.android.com/reference/com/google/android/material/transition/platform/MaterialSharedAxis)). **M**
- **Apple:** "Make motion optional… avoid using it as the only way to communicate important information… when the Reduce Motion accessibility setting is on, be sure to minimize or eliminate animations." "Don't add motion for the sake of adding motion" ([HIG Motion](https://developer.apple.com/design/human-interface-guidelines/motion)). App Store Connect also says: "don't remove or modify all animations prematurely" ([criteria](https://developer.apple.com/help/app-store-connect/manage-app-accessibility/reduced-motion-evaluation-criteria)). **M**
- **WCAG 2.3.3 (AAA):** "Motion animation triggered by interaction can be disabled". Opacity, colour and blur changes alone are **not** motion animation, and vestibular reactions include "dizziness, nausea and headaches" ([W3C](https://www.w3.org/WAI/WCAG22/Understanding/animation-from-interactions.html)). **M** So a short cross-fade is a legitimate reduce-motion fallback.
- **Response-time limits:** 0.1 s feels instant, 1 s keeps flow, 10 s loses attention (Nielsen, *Usability Engineering* 1993; [NN/g](https://www.nngroup.com/articles/response-times-3-important-limits/)). **M** [not re-fetched]
- **Attune's own motion language:**
  - "Serves communication or feedback, never decoration";
  - "Durations live in the 150–320 ms band";
  - reduce-motion renders "the end-state with at most a short fade";
  - "Calm by default… A couple in a painful moment must never be met with confetti" (`docs/superpowers/specs/2026-07-10-chat-delight-motion-design.md` §1.1, §2).

  The 900 ms onboarding card advance breaks this band.
- **Lottie and Rive.** I found no independent performance benchmark this session. **Unknown.** General Android guidance for low-end devices is to watch memory and app size ([Build for Billions](https://developer.android.com/docs/quality-guidelines/build-for-billions)). **M**
- **Fake "building your plan…" loading screens.** A common pattern in Noom-style funnels; the "10–20% conversion boost" claim has no source ([RevenueCat](https://www.revenuecat.com/blog/growth/web-to-app-onboarding-funnel)). **W** Operational transparency can raise perceived value (Buell & Norton 2011, *Management Science* 57(9)) **M [not re-fetched]**, but a **fake** wait is manipulation and conflicts with SOUL.

### 3.8 Accessibility and low-end devices
- **Low-end Android and slow networks.** Android's Build for Billions groups the work into connectivity ("optimizing images, optimizing networking"), device capability ("efficient memory use"), data cost ("reducing app size and offering configurable network settings"), battery and UI/localisation ([Android](https://developer.android.com/docs/quality-guidelines/build-for-billions)). **M**
- **Offline tolerance.** Attune already completes onboarding locally and replays it through `OnboardingSyncService` ("a bad network can never trap the user in the flow", `onboarding_flow.dart`). This is the right pattern. Extend it to DOB, path and couple-profile writes. OTP itself needs a network.
- **Screen readers and split OTP boxes.** The current field is six boxes with autofill on every box (`verification_code_field.dart`). I found no study on screen-reader use of segmented OTP inputs this session **[unverified practitioner concern]**. Test with TalkBack and VoiceOver. A single underlying field with drawn boxes is the low-risk build.
- **Large text.** F16 (06 §3) already requires Dynamic Type to accessibility sizes without truncation. The onboarding screens must pass at 200%.
- **RTL.** Attune ships en/de/es/fr/it/pt (`lib/i10n`) with no RTL locale yet. Shared-axis direction must flip under `Directionality.rtl` (Material's "forward" is defined as content moving left in LTR). **[inference]**
- **Literacy and register.**
  - The partner invite already provides multiple registers: straight English, Pidgin-inflected and plain-spoken (MASTER_SPEC §8.8).
  - The voice OTP fallback also helps people who struggle to read an SMS.
  - Icons paired with words help; never icons alone.

### 3.9 Measurement without invasive tracking
- **Constraints already set:**
  - 06 §4.0 forbids "per-couple engagement dashboards… any metric that rewards time-in-app" and allows aggregate harm signals (for example uninstall within 72 h).
  - 06 §5.3 rule 7 shows special-category values only as aggregate counts above n = 50.
  - Play Age Signals forbids use "for… analytics" (§3.5.4).
  - GOV.UK notes one-thing-per-page lets teams "capture analytics for each question". Per-step counts need no per-user tracking.
- **The gap.** Attune has no product-analytics SDK, only Sentry. Server-side aggregate counters are therefore the least invasive option *and* the cheapest. Which metrics follow in Implication 22.

---

## 4. Recommended canonical first-run sequences

**Principles applied:**
- disclose gates first (§3.1);
- value before sign-up through guest Opinions and path previews (§3.1);
- the phone stays the anchor identity (§3.2.3);
- one question per screen and only what the chosen path needs (§3.5);
- permissions only in context (§3.6);
- no AI vocabulary before a couple is linked (decision 29);
- nothing is a type or a score (permanent rule).

### 4.0 Shared start (all paths)

| # | Screen | Collects | Required | Notes |
|---|---|---|---|---|
| W0 | **Launch** | — | — | Native splash ≤ 1 s; no looping animation. |
| W1 | **Welcome** | nothing | — | "Love, dating and you, in one calm place." Three equal path cards, each opening a **static preview sheet** (sample couple space, how introductions work, a journal page). Buttons: **Get started**, **I already have an account**, **I have an invite**. Text link: **Read Opinions first** (guest). Line: "Attune is for adults (18+) and uses your phone number to sign in." |
| A1 | **Your name** | display name | Required | "What should we call you?" Any script (`\p{L}`), 1–40 chars; held locally until verified. |
| A2 | **Date of birth** | DOB | Required | Neutral gate (§5.1). Checked **on the device**. Under 18 → kind stop screen; nothing leaves the device. |
| A3 | **Phone number** | phone (E.164) | Required | Country from SIM/region; national format accepted. "We'll text you a code" with a quiet "Send by WhatsApp instead". Inline line: "By continuing you agree to the Terms and Privacy Policy." |
| A4 | **Code** | — | Required | Autofill (§3.2.1). Resend unlocks at **30 s**, then 60 s, then 120 s. After the second resend: "Try WhatsApp" / "Call me with the code" (voice). "Wrong number? Change it". 10-minute code validity. |
| A5 | **Before you start** (consent) | consent record | Required | Three plain bullets: 18+; your data and how AI is used to help you (decision 29 disclosure); you can delete everything. The full documents are linked. The server writes DOB (protected, write-once RPC), name and consent here, before anything else. |
| A6 | **What brings you to Attune?** | path | Required (changeable) | **In a relationship**: "A private space for you and your partner." **Single and open to dating**: "A few introductions a day. Only when it's mutual." **Just for me**: "Your journal, quizzes and Healing. Single, partnered or in between." Footer: "You can change this any time. Your journal and quizzes are yours whichever you choose." No preselection; equal visual weight. |

- **Target:** median ≤ 90 s from Get started to A6. Measure it (§3.9).
- **Returning user ("I already have an account"):** phone → code using `shouldCreateUser:false` → (dormancy check, §5.0) → Home on their last path. If no account exists: "We couldn't find an Attune account for this number. Create one?" → A1–A2 → A4 (code) → A5 → A6.
- **Invitee:** an invite link or code. On iOS, without an attribution SDK, the person types a short code; Android can pass it through the Play Install Referrer **[not re-fetched]**. Then W1 shows "You've been invited to Attune", followed by A1–A5. **A6 is skipped and path = Relationship**, with a small "Not what you expected? Choose another way to use Attune". Then accept → linked.

### 4.1 Path R: In a relationship

| # | Step | Collects | Required | Permission asked | First value |
|---|---|---|---|---|---|
| R1 | **Invite your partner** | invite (share sheet, WhatsApp first; QR for same room; code) | Optional ("Invite later") | **None.** Share sheet only; never contacts. | Preview of exactly what the partner will see. What-to-say text in registers (MASTER_SPEC §8.8). |
| R2 | **Heads-up?** (inline row on the sent screen) | — | Optional | **Notifications here**: "Get a heads-up when {name} joins." iOS: one-button inline control. Android: system dialog, rationale only if needed. | — |
| R3 | **Your space while you wait** (Home, not a wall) | optional "About us" card (§5.4–5.8): stage, together since, married year, living, children, one per screen, each skippable | Optional | — | **Day-0 value alone:** journal note, a quiz "about you, for you", the About-us card, and the read-receipts-off line (F4). Then 48 h reflection and day-7 pivot as already built. |
| R4 | **Linked** | — | — | — | One calm "You're both here" moment (§6). Chat opens. Both partners see the About-us card; either can edit (silent, unattributed, 06 §5.3). |
| R5 | Later | — | — | Location only inside Map, when opened | Ask 2 per decision 29 (no change). |

### 4.2 Path D: Single and open to dating

| # | Step | Collects | Required | Permission asked | Notes / first value |
|---|---|---|---|---|---|
| D0 | **Gentle wait check** (server) | — | — | — | Only if a relationship ended *inside Attune*: offer Healing first, not forced (owner decision). |
| D1 | **How Dating works** | — | — | — | One screen covering: a few introductions a day; "Interested" is private; a match only when both say yes; a separate dating chat; safety tools. **Every gate is disclosed here** (verification, photos, region availability), never after setup (Bumble lesson, §3.1). "Set up later" lands on the personal Home with a Dating card. |
| D2 | **Which best describes you?** | gender | Required for Dating | — | §5.2 |
| D3 | **Who would you like to meet?** | men / women / everyone | Required | — | §5.3, with the country-aware safety note before saving. |
| D4 | **Where are you?** | city/region, typed | Required | **Optional** "Use my approximate location" (coarse only, never precise) | Manual entry is the default (5.1.1(iv) alternative). |
| D5 | **What are you looking for?** | intention (dating spec values) | Required | — | — |
| D6 | **Photos** | photos | Per dating spec | **None** with the system photo picker. Camera only on "Take a photo". | — |
| D7 | **This is what others see** | — | — | — | Preview shows age, never DOB; no gender unless chosen; never "who you want to meet". |
| D8 | **Tell me about matches** (inline) | — | Optional | **Notifications here**: "We'll let you know when there's a mutual match, at most once a day." | First introductions, or "Your first introductions arrive tomorrow morning", plus something to do now (journal or quiz). |

### 4.3 Path J: Just for me

| # | Step | Collects | Required | Permission asked | First value |
|---|---|---|---|---|---|
| J1 | **Personal Home immediately** | — | — | — | One first-action card: **Write your first note** or **Take a 3-minute quiz**. |
| J2 | Optional, later | quiz answers, anchors (today's Track A content) | Optional | — | The attachment quiz is offered, not a gate. It carries the caveat and is self-facing (F9). |
| J3 | **Reminder?** (only if they set one) | — | Optional | **Notifications here**, only when the person creates a reminder | — |

**Switching paths later.** Settings → "How you use Attune". The personal layer (journal, quizzes, Healing) is **always on underneath**. Relationship and Dating are add-ons that cannot both be *active* at once. Rules:
- **Relationship → Dating:** needs the relationship ended or unlinked, plus the gentle-wait rule.
- **Dating → Relationship:** pauses Dating and its visibility immediately. A matched pair links into Relationship Mode through the owner's existing rule.
- Every switch is silent to everyone else.

---

## 5. Question-by-question guide

### 5.0 Cross-cutting rules
- One question per screen. Each optional question has **Skip** in the same place.
- Every screen states **why we ask** in one line, with a "More about this" sheet for detail (Tan et al. 2014, §3.5.6).
- No question ever produces a type, label or score (permanent rule). No field is ever inferred or pre-filled from messages, games or AI (06 §5.2).
- Shared couple fields: either partner edits, changes are silent and unattributed, and no notification is sent (06 §5.3). Personal fields stay private to their owner.
- **None** of these answers goes to analytics (§3.9) or into AI prompts (06 §5.3 rule 2).
- **Dormancy rule for recycled numbers** (from §3.2.5): an OTP sign-in from a **new device** after **≥ 180 days** without sign-in does not restore data straight away. It asks for the account's PIN or passkey if one is set. If none is set, it asks for the date of birth on file. Failing that, the person sees one neutral choice: **"I'm new to Attune"**. That starts a fresh account and moves the old account to a support-only recovery hold. The screen must not reveal anything about the old account's contents, partner or path. Offer a sign-in PIN or passkey **after** the first week, never during onboarding.

### 5.1 Date of birth (everyone, A2)

| Aspect | Recommendation | Evidence |
|---|---|---|
| Wording | "What's your date of birth?" Hint: "Attune is for adults. We only ever show your age, never your birthday." | Owner decision; GOV.UK hint pattern |
| Control | **Three numeric fields** with visible labels, ordered by the locale's convention (Ghana/UK: Day · Month · Year; US: Month · Day · Year). Example "e.g. 27 3 1996". No date wheel as the only input. | GOV.UK dates **M** |
| Neutrality | No default value, no pre-filled year, no list of only qualifying years. **Do not say "18+" on this screen beyond the hint.** "Are you 18?" is never a yes/no question. | FTC COPPA FAQ **M** |
| Confirmation | After a valid entry, show inline "That makes you 29." Self-correction is allowed **once** within 7 days, and only if Dating is not on; otherwise use the protected support flow. | DATING_MODE_SPEC §4.1 (protected correction) |
| Under 18 | Calm stop screen: "Attune is for adults (18 and over). We haven't saved anything you entered." Link to country-routed youth support (F10). A **local flag** blocks re-entry on this install for 30 days. The phone was never asked, so nothing is stored server-side. | FTC "cookie" re-entry guidance **M** |
| Errors | Specific fixes: "Day must be between 1 and 31", "That date is in the future", "Check the year". | GOV.UK error pattern |
| Storage | Protected table under `auth.uid()`-only RLS, written once by RPC after A4. Age is derived server-side. Never in `public.users`, analytics, exports to others, or AI prompts. Assurance level = **declared**. | DATING_MODE_SPEC §4.1 |
| Platform signals | Where law requires it (Texas, Utah, Louisiana, Brazil…), also read Apple Declared Age Range / Play Age Signals. Use them only for age-appropriate access, never analytics. If the signal conflicts with the DOB, the stricter one wins. | §3.5.4 **M** |
| Culture | Some older users may not know an exact date **[hypothesis; cultural reviewer]**. Accept their best-known date; never ask for documents at sign-up. Dating verification is the dating researcher's call. | — |

### 5.2 Gender (Dating only, D2; not asked at sign-up)

| Aspect | Recommendation | Evidence |
|---|---|---|
| Why not at sign-up | Relationship and Just-for-me don't need it. Attune's copy uses **names, not pronouns**, which removes the Paired "they/them" complaint at the source. | §3.4 **A**; data minimisation 5.1.1(iii) **M** |
| Wording | "Which best describes you?" Options: **Woman · Man · Non-binary**. "Add something more specific" reveals a list plus a write-in (30 chars). | Spiel et al. 2019 **M**; Hinge **M** |
| "Prefer not to say" | Not offered here because matching needs it. Say so plainly: "We use this only to introduce you to people who want to meet someone like you." Skipping D2 means Dating stays off. | GOV.UK (explain why) **M** |
| Non-binary routing | Ask: "Show me to people looking for: Men · Women · Everyone" (multi-select). **[market pattern unverified; dating researcher to confirm]** | — |
| Visibility | Shown on the Dating profile **only by explicit choice**, with nothing preselected. | DATING_MODE_SPEC §4.1 |
| Pronouns | Optional field, Dating profile only, free text with suggestions. | — |
| Change | Editable any time; applies to new introductions only. | GOV.UK ("can change over time") **M** |

### 5.3 Who you want to meet (D3)

| Aspect | Recommendation | Evidence |
|---|---|---|
| Wording | "Who would you like to meet?" **Men · Women · Everyone** (single choice). | Owner decision |
| Trust copy | "Only you can see this. It's never on your profile. We only introduce people who'd both like to meet." | Owner decision; Hinge preferences invisible **M** |
| Country-aware safety note | Shown **before saving**, in the app, for people whose region (D4) or SIM country carries legal or entrapment risk. Factual and calm, for example: "In some countries, including [country], relationships between people of the same gender can carry legal risk, and people have been targeted through dating apps. Here's what Attune does to protect you, and what you can do." It never blocks. It is not logged (showing the note would itself reveal orientation). Ghana: also mention risks from people you know ("duty to report"). | Grindr tiers **M**; Ghana bill **M**; status after June **[unverified]** |
| Storage | Dating preferences under strict RLS. Never displayed, exported to others, sent to analytics, or used in AI. Deletable when Dating is turned off. | 06 §5.3 rule 7; DATING_MODE_SPEC §4.1, analytics ban line 612 |

### 5.4 Relationship stage (About-us card, R3/R4, either partner)

| Aspect | Recommendation |
|---|---|
| Wording | "How would you describe where you two are?" |
| Options | **Dating** · **Engaged** ("planning to marry") · **Married** ("any kind of marriage: customary, religious or civil") · **Something else** (write-in, 40 chars, "in your words"). Skip. |
| Why line | "So what Attune suggests fits you two. Either of you can change this, and it's never used to score or type you." |
| Culture | In Ghana the "engagement" ceremony is often the customary marriage, so the helper text matters. Couples choose; Attune never corrects them. **Cultural reviewer to confirm wording.** |
| Never | No "Is this your only partner?", no divorce history, no "how happy are you". 06 §9: onboarding never asks about problems. |
| Storage | Shared `relationships` row; silent edits; used only for content relevance (06 §5.1 `stage`, values updated to the owner's set). |

### 5.5 Together since

| Aspect | Recommendation |
|---|---|
| Wording | "When did you two get together?" |
| Control | Month + Year (required if answering), with "Add the day" optional. "Not sure of the month" → year only. Skip. |
| Why line | "So we can remember your anniversary with you, if you'd like." |
| Edge cases | On-and-off couples: "Use whichever date feels right to you both." Cannot be in the future. Never checked against ages; no inference. |
| Use | Anniversary reminder **only if opted in**. **No running "together for N days" counter by default** (no-counter stance, 06 §5.4/§8). |
| Conflict | Last edit wins, silently. The "Edited" line shows no name (06 §5.3 rule 6). |

### 5.6 Married year (only if stage = Married)

| Aspect | Recommendation |
|---|---|
| Wording | "What year did you marry?" (year only, optional) |
| Multiple ceremonies | "Had more than one ceremony? Add another" lets them add one more labelled year (for example "Customary 2019", "Church 2021"). This addresses Ghana's two-date pattern (§3.4). |
| Never | No ceremony type is required. No year-based comparison or score. |

### 5.7 Living arrangement

| Aspect | Recommendation |
|---|---|
| Wording | "Where do you two live?" |
| Options | **Together** · **Apart, nearby** · **Long distance**. Skip. |
| Why line | "So plans, maps and reminders fit how you live." |
| Notes | No option ranks above another. "Apart, nearby" is common and normal (religious and family norms in Ghana). A long-distance end date is **not** asked here; it lives in Plans/Map (06 B8, `distance_ends_on`). |

### 5.8 Children

| Aspect | Recommendation |
|---|---|
| Wording | "Are there children in your life together?" |
| Options | **No** · **Yes** · **We're expecting** · Skip. If Yes, optional ages, multi-select bands: Under 2 · 2–5 · 6–12 · 13–17 · 18+. No names, counts or whose child. |
| Avoid | "No children *yet*". "Do you want children?" (couples). Any fertility question. Any automatic follow-up by date (for example a "baby arrived?" prompt), which matters for pregnancy loss (06 quiet states). |
| Why line | "So ideas and reminders suit your family." |
| Storage | Shared household field (06 §5.1 `household`); silent edits; never in AI prompts. |

---

## 6. Motion spec sketch

All values use Flutter `Durations.*` and `Easing.*`. No raw `Duration` at call sites (design gate in `AUTH_ONBOARDING_ENGINE.md`). Every transition is interruptible, and input is never blocked longer than 100 ms.

| Moment | Pattern | Duration | Easing | Reduce motion | Notes |
|---|---|---|---|---|---|
| Splash → Welcome | Fade | `short4` 200 ms | `standardDecelerate` | Instant | Splash ≤ 1 s |
| Welcome path card → preview sheet | Bottom sheet | Enter `medium2` 300 / exit `short4` 200 | `emphasizedDecelerate` / `emphasizedAccelerate` | Cross-fade 150 ms | Static preview images, bundled |
| **Step forward (A1→A6, D1→D8, About-us)** | **Shared axis X**, 30 dp | `medium2` 300 ms | Slide: `Curves.easeInOutCubicEmphasized`. Outgoing fade 0–90 ms `emphasizedAccelerate`; incoming fade 90–300 ms `emphasizedDecelerate` | **Cross-fade 150 ms (opacity only, which is not motion under WCAG 2.3.3)** | Flips under RTL |
| Step back | Shared axis X reversed | `medium1` 250 ms | Same | Cross-fade 150 ms | Back is slightly quicker |
| Option select (path card, chip) | State layer + check icon | `short3` 150 ms | `standard` | Instant | `HapticFeedback.selectionClick` |
| Button press | Scale 0.98 | `short2` 100 ms | `standard` | None | — |
| OTP wrong code | Error colour + message + haptic; optional 2-cycle shake | `medium2` 300 ms | `standard` | **No shake** | Never rely on motion alone (HIG) |
| OTP accepted | Check fades in, 400 ms hold, auto-advance | `short4` + 400 ms | `standardDecelerate` | Check shown, auto-advance | — |
| Resend countdown | Plain text tick each second | — | — | — | Swap the `AnimatedRollingCounter` for plain text under reduce motion |
| Any wait > 400 ms | Indeterminate linear indicator + words ("Sending your code…") | — | — | Static text | **No fake waits**; nothing shown under 400 ms to avoid flicker |
| Path chosen → first path screen | Container transform (card grows into screen) | `medium4` 400 ms | `emphasizedDecelerate` | Cross-fade 150 ms | The single "arrival" flourish |
| **Partner linked / first mutual match** | Two avatars settle together with the existing spring (`kSettleDuration` 280 ms, `kSettleCurve`), then the line appears; one light haptic | ≤ `long4` 600 ms total | Spring settle | Static avatars + text | Once only. Event-driven, never content-driven. **No confetti** (motion spec §1.1). |
| Under-18 stop, safety notes, consent | **No motion** | — | — | — | Calm, readable, nothing playful |
| Onboarding deck card (existing quiz) | Reduce 900 ms to ≤ 320 ms, or keep it only in the optional quiz | ≤ 320 ms | Existing curves | Existing instant path | Brings it back inside the app's own band |

**Illustration and animation assets.**
- Bundle them; no network fetch in onboarding.
- Lottie files ≤ 50 KB each. Play once, never loop.
- Skip them on `isLowRamDevice` and under reduce motion.
- **[unverified]:** no Lottie vs Rive benchmark was found; decide on device tests.

**Progress indicators.**
- None in A1–A6: six short screens, and constant bars don't help (Villar 2013).
- About-us and Dating setup use step dots ("2 of 5") with the easiest questions first.

---

## 7. Implications for Attune

1. **Replace the two-option fork with "What brings you to Attune?" and three equal paths, changeable any time.** Drop "routes your entire Attune experience". This matches the owner decision, intent framing (Headspace/Calm, §3.3) and the "Just for me if partnered" inclusion.
2. **Model paths as a personal base plus one add-on (Relationship *or* Dating), not three modes with three profiles.** Bumble split modes into separate apps because one-app-many-profiles got confusing (§3.3, **M**). A shared personal core keeps the journal, quizzes and Healing continuous across switches.
3. **Make Welcome promise exactly what the store page shows, with no-data previews of each path and the guest Opinions link.** HIG says delay sign-in and Duolingo moved sign-up later (§3.1, **M/W**). Promise–reality gaps are a documented failure (Agapé, Bumble, **A**).
4. **Disclose every gate before any investment:** 18+, phone, and Dating's verification/photo rules on D1. Bumble 2026 review (**A**); FTC neutral-gate guidance limits *how* 18+ is mentioned (§5.1).
5. **New accounts: name → DOB (on-device check) → phone → code → consent → path.** A minor never hands over a phone number (data minimisation, 5.1.1(iii) **M**; FTC re-entry guidance **M**). DOB goes into a protected write-once store, matching DATING_MODE_SPEC §4.1.
6. **Build the DOB input as three numeric fields in locale order, with no defaults and an inline "That makes you 29" confirmation.** GOV.UK dates and FTC neutrality (**M**).
7. **Fix the name validator to accept any script (`\p{L}`).** `[a-zA-Z]` rejects many real names, and Attune is worldwide (§2).
8. **Route OTP through the Supabase Send SMS Hook: Ghana-direct SMS first, then an automatic voice fallback, with WhatsApp as a user-chosen alternative.** The internal launch requirement (voice) is missing in code. The Hook supports regional routing and failover (**M**). Meta's one-tap/zero-tap and iOS 26 autofill make WhatsApp low-friction (**M**). Bumble's Sept 2026 OTP failures show the cost (**A**).
9. **Resend at 30 s / 60 s / 120 s, 10-minute codes, channel switch after the second resend, and per-number, per-IP and per-country-group rate limits plus destination allow-lists for toll fraud.** Twilio guidance (**M**); worldwide sign-up raises pumping risk.
10. **Add SMS autofill properly:** Android SMS Retriever with an app hash appended by the Hook, User Consent as fallback; iOS origin-bound `@domain #code` (**M**). Re-test screen-reader behaviour of the six-box field, or move to one field with drawn boxes (§3.8).
11. **Default the country from the SIM or device region; accept national format with a leading 0; store E.164.** Diaspora SIMs; Twilio guidance (**M**).
12. **Keep the phone as the anchor identity. Add Apple and Google only by *linking* from Settings while signed in, and require phone verification for any account started with Apple or Google.** Supabase auto-links by email only, and phone-only users have none (**M**). Adding Google on iOS triggers 4.8, so ship Sign in with Apple in the same release (**M**).
13. **Ship passkeys before Apple/Google, as optional fast re-sign-in offered after week 1, and list them in F7 "Where you're signed in".** 93% vs 63% success and 8.5 s vs 31.2 s (FIDO **M**). Supabase beta needs `supabase_flutter` ≥ 2.15 (**M**). The IPV caveat comes from 06.
14. **Adopt the recycled-number dormancy rule (§5.0): new device plus ≥ 180 days triggers a PIN/passkey/DOB challenge, otherwise a neutral "I'm new to Attune" fresh start.** 171 of 259 recycled US numbers were tied to existing accounts (**M**); Ghana recycled deactivated SIMs (**M**); WhatsApp (45 days) and Signal (lock PIN) precedents (**M**).
15. **Move the push prompt out of sign-in and into three contextual moments:** partner-join heads-up (R2), mutual-match notice (D8), and a self-set reminder (J3). Today's prompt fires right after login (`onesignal_service.dart`). Both platforms say ask in context, and Android counts two denials as permanent (**M**). ⚠ **Regression risk:** `onesignal_service.dart` is shared core. Re-test chat push, safety-lock suppression and sign-out release paths.
16. **Never request contacts. Use the share sheet for invites and the system photo picker for Dating photos (no permission). Location is manual city entry by default, with optional approximate only and never precise.** 5.1.1(iii) and Android approximate-location guidance (**M**). This also avoids contact-graph exposure for people hiding app use (06 safety).
17. **Use inline, single-button permission asks instead of full-screen pre-alerts.** This satisfies Apple ("one button, no cancel") and Android ("no thanks"), because dismissing is simply continuing (§3.6, **M**).
18. **Make the Track A attachment quiz and anchors optional after landing; don't gate Home behind 5–8 minutes of questions.** HIG says postpone nonessential setup (**M**); the median quiz app asks ~4 questions (**W**); the Agapé "too long" review (**A**). The quiz stays available, self-facing, with the F9 caveat. ⚠ This contradicts MASTER_SPEC §8.8 Track A ("quiz stays up front") and needs the owner's amendment (Q3).
19. **Couples: invite is the main but skippable action; day-0 value alone; the About-us card goes in the waiting space and after linking, never before the invite.** Decision 29; Lasting and Relish solo use (**W**); Agapé forced invites (**A**). Each About-us question is one per screen and skippable, with silent shared edits (06 §5.3).
20. **Use the couple's names in all partner-referring copy and ask no pronoun question in Relationship mode. Pronouns are optional and Dating-only.** Paired "they/them" complaints (**A**); minimisation (**M**).
21. **Write the stage options for West African reality:** "Married (any kind: customary, religious or civil)", allow a second ceremony year, and treat "Apart, nearby" as normal. Customary marriage is legally recognised in Ghana (**M**, cultural reviewer to confirm wording).
22. **Instrument onboarding with server-side aggregate counters only. Measure:**
    - step reached and step completed per step;
    - OTP request → verified, by channel and country (operational);
    - median seconds from Get started to A6, and to first value, in buckets;
    - path chosen and **path switched within 7 or 30 days** (signals a wrong first choice);
    - invite sent → accepted, and median hours;
    - partner-not-joined at day 7;
    - under-18 stops (count only);
    - permission grant rate by *context*;
    - uninstall within 72 h (06 harm signal).

    Rules:
    - Daily buckets with no user or device IDs, no answers, and no orientation or gender values.
    - Display only cells ≥ n = 50.
    - No session replay or attribution SDKs.
    - Age signals are never used.

    Evidence: 06 §4.0, §5.3 rule 7 (internal); Play Age Signals terms (**M**).
23. **Motion: shared-axis X at 300 ms with the M3 emphasized curves; opacity-only cross-fade under reduce motion; one content-blind celebration per path; cut the 900 ms deck advance to ≤ 320 ms.** M3/Material, HIG, WCAG 2.3.3 and Attune's own motion spec (**M**/internal).
24. **Bundle every onboarding asset (no remote media), keep Lottie ≤ 50 KB and skip it on low-RAM devices; set an onboarding network budget of the OTP plus three small writes.** Google Play size–conversion data (**M**); Ghana is Android-heavy (≈71%, **M**); HIG says avoid downloads during onboarding (**M**).
25. **Update stale copy:** remove "forums" from the name screen subtitle (Forums are being removed per BRIEF), and the legal line from the intro.

---

## 8. Open questions for the owner

| # | Question | Recommendation |
|---|---|---|
| Q1 | Ask DOB **before** the phone number for new accounts (minors never give a number), or after the code like most dating apps? | **Before** (Implication 5). The returning-user path skips it. |
| Q2 | SMS route: build the Send SMS Hook with a Ghana-direct provider plus voice fallback now, or keep Twilio-style WhatsApp/SMS only? | **Build the Hook now.** Voice fallback is already a written launch requirement, and real-carrier testing (MTN/Telecel/AirtelTigo) stays a release gate. |
| Q3 | Make the 26-question quiz + anchors optional for Just-for-me (amends MASTER_SPEC §8.8 Track A)? | **Yes.** Offer it on Home as "Take a 3-minute look at how you connect", self-facing with the F9 caveat. |
| Q4 | Should an invited partner skip the path screen (preset to Relationship)? | **Yes**, with a small "choose another way" escape. Never force acceptance. |
| Q5 | Gender asked only in Dating (not at sign-up)? | **Yes.** Names-not-pronouns copy removes the need elsewhere. |
| Q6 | How non-binary members are shown in matching ("Show me to people looking for…") | Adopt the multi-select pattern **pending the dating researcher's confirmation** (market pattern unverified here). |
| Q7 | When to offer the couple profile ("About us")? | **During the wait and after linking**, never before the invite. One question per screen, every one skippable. |
| Q8 | Recycled-number rule: 180-day dormancy + new device → PIN/passkey, else DOB, else "I'm new to Attune" fresh start with a recovery hold. Accept? | **Accept, at 180 days.** Revisit with real Ghana carrier recycling data. Never reveal anything about the old account. |
| Q9 | Order of new sign-in methods | **Passkeys first** (fast re-sign-in, no 4.8 trigger). Then Apple + Google together, always **linked** to the phone anchor. |
| Q10 | Move the push prompt from post-login to contextual moments (shared core file)? | **Yes**, with a regression pass on chat push, safety lock and sign-out (Implication 15). |
| Q11 | Running "together for N days" counter? | **Off by default.** Anniversary reminders only, opt-in (no-counter stance, 06). |
| Q12 | Store imagery and localised listings for Ghana if the anti-LGBTQ bill becomes law (assent status unverified) | **Get legal advice before the Ghana listing goes live.** Keep inclusive options *inside* the product with the strongest safety notes. Localise imagery per market rather than erase. |
| Q13 | If Dating isn't available in a person's country, or its flag is off: hide the path or show "coming soon"? | **Show it as "Not in your area yet"** with "Just for me" suggested. Hiding it makes the store promise false (§3.1). |
| Q14 | DOB self-correction: allow once within 7 days (if Dating is off), else support? | **Yes.** Typos are common, and Dating's protected correction rule still holds once Dating is on. |

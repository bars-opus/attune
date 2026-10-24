# 11 — Synthesis and decisions: the whole app flow, Dating Mode, and Opinions after Forums

**Date:** 2026-10-24 · **Role:** synthesiser · **Status:** decision document for the owner; the three specs are written from it. Read-only pass: no app files were changed.

**Inputs, read in full:** 01 (dating apps: data and onboarding), 02 (11,502 reviews), 03 (dating science), 04 (safety and law), 05 (onboarding and first open), 06 (Attune code audit), 07 (Opinions without Forums), 08 (citation check), 09 (19 everyday simulations), 10 (22 risk simulations), `BRIEF.md`, and `2026-10-16-couples-research/06-synthesis-roadmap.md` (cited as **CR-06**).

**Conventions**
- `04 §2.2.1` = file 04 in this folder, that section. `09 P4` = everyday person 4. `10 S3` = risk scenario 3. `10 F-1` = code fact 1 in file 10. `08 A1` = citation-check correction A1.
- **08's Corrected and Contradicted items override the originals everywhere below.** The ones that change a decision are applied in place and marked "(08 A…)".
- Evidence grades come from the source files (Strong / Moderate / Weak / Anecdote). Simulations in 09 and 10 are hypotheses to test, not evidence; they are used to find failure points.
- `S1 W3` = Spec 1, wave 3 (§11).
- **Precedence:** `ATTUNE_SOUL.md`, `ATTUNE_THESIS.md`, the Master Spec and the permanent constraints win until the amendments in Q20 are approved. Where a decision needs an amendment it says so.

---

## 0. One-page summary

**What we'll build**
- **One app, three ways in.** After signing in, people answer "What brings you to Attune?": *In a relationship*, *Single and open to dating*, or *Just for me*. Everyone keeps a private personal space (journal, quizzes, Healing) whichever path they pick. They can switch at any time, and nobody else is told.
- **A short, reliable sign-up.** Name and date of birth are entered on the phone first, then the phone number and a code, then one consent screen. A person under 18 is stopped before they hand over a phone number. Codes go by SMS, with a voice call and WhatsApp as backups, because a lost code is the biggest reason people give up (09 rank 1; 02 §2.3).
- **A couple space that's useful before the partner joins**, with an "About us" profile either partner can edit. It holds when you got together, your stage (customary marriage included, with room for two ceremonies), where you live, and children. It is never a type and never a score.
- **Dating Mode built properly.** A few introductions a day, a match only when both people say yes, a separate text-only chat that hides phone numbers until both agree to swap, and a real age and identity check before anyone is introduced.
- **Opinions as a safe, anonymous place to write.** Each post can't be linked to the author's other posts. Dislikes, reposts and public scores go. A filter blocks phone numbers and slurs, and a "Need support now?" link is always there.
- **Forums removed** in three steps. **Games are not touched.**

**What we won't build:** swiping or browsing; "who liked you" lists; paid boosts or paying to reply; compatibility percentages or personality matching; streaks or "It's a match!" bursts; location or distance; photos, video or calls in the dating chat for now; stored face templates; AI-written messages or AI safety checks; fields for ethnicity, tribe, income or body type; same-gender introductions in countries where they are dangerous, at launch (§8).

**The 10 biggest decisions**
1. **Paths, not modes.** The personal space is always on. Relationship and Dating are add-ons that can never both be active. The path is stored on the account (05 Impl 2; 06 §2.3).
2. **Two layers of age check.** A date of birth for everyone, stored privately and shown only as an age. On top of that, Dating requires a live video selfie with an age estimate (ID fallback) before any introduction. A typed date of birth alone never unlocks Dating (04 §2.2.1; 10 S2; 08 A2, A3).
3. **Dating opens country by country, not worldwide on day one.** It opens in Ghana (men–women introductions only) and the UK at launch. Everywhere else people see an honest "Not in your area yet" (04 Q3; 10 §3.5).
4. **Same-gender introductions are off in Ghana and every high-risk country at launch.** This is enforced on the server and nothing about it is stored. It is reconsidered after a Ghanaian legal opinion, consultation with LGBTQ+ groups, and the full set of protections being built (10 S3; 03 Q3; 08 A1).
5. **Matching uses only what people tell us they want:** intention, children, how much faith matters, place. There's no attachment or personality scoring. At most 3 introductions a day, and nothing rather than padding (03 §2.1, §3(b); 02 §2.4).
6. **A safer first conversation.** The dating chat is separate and text-only. Contacts stay masked until both people tap "Swap contacts". Scam and sextortion warnings go only to the person at risk. "Close kindly" replaces ghosting (04 Impl 21–25; 10 F-11; 03 §3(c)).
7. **Fair enforcement that can't be dodged.** A restricted person sees the reason and can appeal once to a human. Accounts are held only for serious, corroborated reports. Deleting an account no longer wipes a ban or a report, and the phone number the safety checks rely on can't be quietly rewritten from the app (02 §2.2 P4; 10 F-1, F-2).
8. **"About us" is shared and honest about edits.** Either partner can edit. Both see the current answers, plus a quiet "Changed by Yaw · 12 Nov" line. There's no notification and no feed (09 Q2; 06 Q4).
9. **The gentle wait after a breakup in Attune** lasts as long as the 30-day goodbye window, plus a private reflection. Healing is offered, never required. There's no readiness score and no 8-week timer (03 §2.8; 09 P15).
10. **Opinions becomes truly anonymous and gentle:** a separate handle on each post, no author pages, supportive reactions that only the author sees, and moderation that explains itself (07 Impl 1–13; 10 S12).

**Launch countries (recommendation, Q1)**

| Country | App available | Dating at launch | Same-gender introductions |
|---|---|---|---|
| **Ghana** | Yes | **Yes, pilot:** Greater Accra and Ashanti first, then all 16 regions | **No** (honest note and resources) |
| **United Kingdom** | Yes, after the Online Safety Act assessments | **Yes**, once the age check is a UK-recognised method | Yes |
| **United States** | Yes, after the Apple and Google age-signal work (Texas law in force, 08 A2) | Later: biometric consent and state laws first | Yes, when on |
| **Canada** | Yes | Phase 2 | Yes, when on |
| Nigeria, Kenya | Phase 2 | Phase 2, men–women only | No |
| EU | Later (EU representative, DPIA) | Later | — |
| India, Australia | Not yet (India's 2-hour intimate-image takedown rule; Australia's new code, 08 A4–A5) | — | — |
| Everywhere else | Added country by country with a checklist | "Not in your area yet" | — |

**Outside the code, start now:**
- a Ghanaian legal opinion on the bill's final text;
- UK Online Safety Act assessments;
- a data-protection impact assessment;
- Ghana Data Protection Commission registration;
- a named moderator who reads Twi, Ga and Pidgin;
- clinician, cultural, LGBTQ+ and domestic-violence reviewers;
- an age-check vendor (§7.2).

**Size:** Spec 1 (flow, identity, couple profile, Opinions) **10 waves** · Spec 2 (Dating) **10 waves, plus voice calls later** · Spec 3 (forum removal) **3 waves**. **Order:** forum removal waves 1–2 → Spec 1 → Spec 2 → the forum table drop (§11).

---

## 1. Owner decisions already made

### 1.1 Binding decisions and how the research treats them

| Decision (BRIEF) | Verdict | Note |
|---|---|---|
| Three paths after sign-in; Dating can be switched on later | **Keep** | Model as a personal base plus one add-on (05 Impl 2). |
| Phone-code sign-in; Apple/Google later | **Keep** | The phone stays the identity anchor. New methods are only ever *linked* from a signed-in account, and a phone is required for Dating and couple invites (06 Impl 12; 05 §3.2.3). |
| Guests can read Opinions | **Keep, with a birth-year gate** | Guests read but can't profile anyone. No author histories (07 Impl 14; 09 Q12). |
| DOB for everyone at sign-up; 18+; only age shown | **Keep, but not sufficient alone** | See T2. |
| Shared couple profile, either partner edits (together since / stage + married year / living / children) | **Keep** | Add customary-marriage helper text and a second ceremony year (05 §5.4–5.6; 09 P2). Edit visibility: see T6. |
| Never a type or a score | **Keep** | A contract test proves no function maps profile fields to a label (06 §2.2.4 #3). |
| Dating worldwide | **Revisit** | See T1. |
| A few curated introductions a day; double opt-in | **Keep** | Numbers in §4.4. |
| Who you want to meet: men / women / everyone, never shown, mutual only, country-aware safety notes | **Keep the field; revisit "notes only"** | See T3. |
| Separate dating chat with stronger safety; a matched pair can link into Relationship Mode | **Keep** | Text only in v1. The link needs both people to confirm (§4.7). |
| Gentle wait only after an ending inside Attune; Healing offered, not forced | **Keep; set its length** | See T4. |
| Forums: remove screens, jobs and notifications now; drop tables later. Opinions stays | **Keep** | Opinions stays, but is redesigned (T5). |
| Don't touch in-chat Games | **Keep** | Dating chat gets its own screen, never a mode of `ChatScreen` (06 §2.8). |
| Fresh start: no real users | **Keep** | Lets `users.mode` go without a backfill. Test devices still hold old prefs (06 R4). |

### 1.2 Tensions: where research suggests revisiting a decision

| # | Tension | Recommendation | Why | Owner Q |
|---|---|---|---|---|
| **T1** | **"Worldwide"** vs a launch in Ghana (men–women) and the UK (10 §3.5; 04 Q3) | **Build it worldwide-capable, and switch it on country by country.**<br>• The code is country-aware everywhere: ISO country, per-country region lists, a tier table, per-country resources, locale date formats.<br>• Dating turns on per country through a checklist.<br>• Everywhere else the app says plainly "Dating isn't open in {country} yet", on the store page and in the Welcome preview, with a "Tell me when it's here" option and no waitlist. | • Each country brings its own legal regime: Texas app-store law is in force (08 A2), India requires 2-hour takedown of intimate images (08 A4), Australia's code names dating services (08 A5), and the UK requires a highly effective age check (04 §2.2.1).<br>• A solo team can't meet them all on day one.<br>• Dubai Arjun (09 P8) shows that a "worldwide" promise with Dating off is a 1★ review. | Q1 |
| **T2** | **DOB for everyone** vs what age assurance needs | **Two layers.**<br>(a) Everyone gives a neutral DOB, held privately; under-18 stops on the device.<br>(b) Dating activation requires liveness plus facial age estimation (challenge age 25) plus an ID fallback, for every Dating user in every country.<br>Also:<br>• read Apple Declared Age Range and Play Age Signals where law requires (US now);<br>• turn on Google Play's Restrict Minor Access for the whole app;<br>• a birth-year gate for guests;<br>• an age check inside `accept-invite`. | • Self-declared DOB is not a highly effective age check under Ofcom's rules (04 §2.2.1).<br>• Texas has been enforced since 4 Jun 2026 (08 A2).<br>• Google requires Restrict Minor Access for dating apps (08 A3).<br>• The EU allows self-declaration only while Attune is a micro or small enterprise (08 A6).<br>• A 16-year-old types 2006 (10 S2).<br>• Today an invite links a minor before any check (10 S16). | Q3, Q4 |
| **T3** | **Country notes** vs off in high-risk countries | **In Ghana and every Tier 1 or Tier 2 country, same-gender introductions are off at launch.** The server refuses them, and no gender/preference pair from those countries is sent, logged or counted. People there see honest copy and resources. In Tier 3 countries, notes plus protections apply.<br>**Reconsider only after:**<br>• a Ghanaian legal opinion on the *reconsidered* bill text;<br>• consultation with Ghanaian LGBTQ+ groups;<br>• every Tier 1 protection being built: photos withheld until mutual interest, caps, dragnet detection, liveness. | • Every same-gender introduction discloses preference: double-blind protects interest, not preference (04 §2.1.8).<br>• An entrapment gang can enumerate a thin pool in months (10 S3).<br>• The duty to report is confirmed in the passed text, and the platform-owner clause is unconfirmed (08 A1).<br>• 04 Q1 ("on, with protections") is the honest counter-argument: switching it off pushes people to riskier apps. That is why "off" comes with honest copy and a stated path back. | Q2 |
| **T4** | **Gentle wait length** (today 8 weeks, a readiness score above 70, every Healing stage) | **The wait lasts as long as the shared space's 30-day read-only window** (shorter if both partners seal it). Add a private 3-question readiness reflection, offer Healing, and use no score. The ex-exclusion stays mandatory. No wait at all for people whose relationship ended outside Attune. | • No study supports an imposed wait. Rebounds can help anxiously attached people (03 §2.8).<br>• A hard timer pushed Abena (09 P15) towards re-registering on another SIM, which defeats the ex-exclusion.<br>• The 30-day window gives a reason ("you don't date while your ex can still read your shared space") rather than an arbitrary number.<br>• Needs a recorded clinical note under spec §2.1's gate-erosion clause (04 C1, Q10). | Q12 |
| **T5** | **"Opinions stays"** vs research recommending a redesign | **Keep Opinions; change its social layer.** Per-post handles; no author pages, follows, dislikes, reposts or quotes; author-only reactions; a pre-post filter; a crisis link; moderation notices with an appeal. | • Today a partner can tap one recognised post and read the author's whole history, and so can guests (07 §2.1 #3; 10 S12).<br>• The Apple 1.2 filter is required and missing (07 §2.1 #1).<br>• Dislikes degrade communities (Cheng 2014, Strong). | Q9 |
| **T6** | **Couple-profile edits:** silent and unattributed (CR-06 §5.3 rule 6; 05 §5.3) vs attributed (06 Q4; 09 Q2) | **Attributed, quietly.** One line per field, "Changed by Yaw · 12 Nov". No push, no feed, no history list. | With only two people, an unattributed edit is a fiction and caused a spat (09 P1). This amends CR-06 §5.3 rule 6 for the four shared "About us" fields only. | Q8 |
| **T7** | **CR-06 §5 profile fields** (stage new/established/…, intent, household, per-partner faith/sex gates) vs the owner's four fields | **Build the owner's four fields now.** The CR-06 per-partner gates (faith, sexual content, health…) stay deferred with CR-06 Spec 6. | The owner's set is binding and narrower. No research here requires the wider set before launch. | Q8 |
| **T8** | **Master Spec decision 11** ("Opinions is the default home for singles") and **§8.8 Track A** (the 26-question quiz up front) | **Just for me** lands on its own space, with Opinions one tap away. **Guests** still land on Opinions. The quiz becomes optional. | • Ruminating, recently separated people shouldn't land in other people's pain (07 Q1; Sbarra 2013, verified 08 07-1).<br>• Five to eight minutes of questions before any value (05 Impl 18). | Q6, Q20 |
| **T9** | **Voice "later"** vs 02 Q7 and 03 Q5 (early in-app voice) | **Text-only chat in v1; voice is a later Spec 2 wave.** Masking keeps numbers private meanwhile. | 10 §3.3 ranks voice P2, and it adds a calls stack to moderate. 03's evidence (text is the weakest first modality) is real, so measure first-meeting conversion and add voice once moderation capacity is known. | Q15 |

---

## 2. The whole app flow, screen by screen

### 2.0 Rules that apply to every screen

**Motion** (05 §6; Flutter M3 tokens; the app's own 150–320 ms band):
- **Step forward:** shared-axis X, 30 dp, `Durations.medium2` (300 ms), emphasized curves.
- **Back:** reversed at 250 ms.
- **Path chosen:** container transform at 400 ms.
- **A linked partner or first mutual match:** one settle, at most 600 ms, once only.
- **Selection:** 150 ms, with `selectionClick`.
- **Reduce motion:** an opacity-only 150 ms cross-fade.
- **Never animated:** the under-18 stop, consent, country or safety notes, the gentle wait, endings, scam or report cards, "not in your area", expired invites.
- **No confetti and no fake loading screens.**
- Lottie files are under 50 KB and skipped on low-RAM devices.

**Copy:**
- Use names, never pronouns: the partner's name, and the couple's chosen chat name (`coupleNameProvider`).
- Every sensitive screen has one "why we ask" line and a "More about this" sheet (Tan 2014, 05 §3.5.6).
- Skip sits in the same place on every optional question.

**Permissions:**
- No contacts permission, ever.
- Photos come through the system picker.
- Notifications are asked inline, in context, with one "Turn on" button (05 §3.6).

**Accessibility, from the first wave, not at the end:**
- every new screen opts in to large text up to 2.0× (§2.13);
- every control has a semantic label, enforced in widget tests;
- touch targets are at least 44 dp and contrast at least 4.5:1;
- shared-axis direction flips under right-to-left text.

**Analytics:** server-side aggregate counters only (§9).

### 2.1 Store page and first open

| # | Screen | Shows | Collects | Req. | Stored | Motion | Evidence |
|---|---|---|---|---|---|---|---|
| S0 | **Store listing** | A subtitle of 30 characters or fewer. The first 3 screenshots, captured from the app, show the three paths, with couples of different ages, including married people over 50. Lines: "Adults 18+ · sign in with your phone number · Dating open in Ghana and the UK". Imagery localised per market, with legal advice before the Ghana listing. | — | — | — | Optional preview using on-device footage | 05 §3.1, Q12; 09 P2, P8 |
| W0 | **Native splash** | Logo | — | — | — | 200 ms fade; at most 1 s; the first frame never waits on the network | 05 §6; 09 P11 (`main.dart:46,123-128`) |
| W1 | **Welcome** (replaces `IntroScreen` and its manual carousel) | "Love, dating and you, in one calm place."<br>• Three equal path cards, each opening a bundled static preview: what a partner sees; how introductions work, including "Open in: Ghana, UK"; a journal page.<br>• Buttons: **Get started**, **I already have an account**, **I have an invite**; link: **Read Opinions first**.<br>• Line: "Attune is for adults (18+) and uses your phone number to sign in." | — | — | First-launch flag (prefs) | Sheet 300 ms in, 200 ms out | 05 §4.0 W1, Impl 3–4; 06 §2.1.2 #1 |

**Regression:** the router forces every route to `/intro` while `isFirstLaunch` is true (`app_router.dart:422-425`). The new pre-auth routes must be allow-listed, and the invite deep link must still clear the flag (06 R2, R3).

### 2.2 Guest

| # | Screen | Shows | Collects | Req. | Stored | Motion | Evidence |
|---|---|---|---|---|---|---|---|
| G1 | **Birth-year gate** (once) | "What year were you born?" Numeric, with no default. Under 18: a calm stop ("Attune is for adults…") with a youth-support link, and a 30-day block on this install. | Birth year | Required to read | Device only, in the backup-excluded keystore (the Spec 2 safety-key pattern) plus the iOS Keychain. It pre-fills A2's year. | None | 09 Q12, P13, P17; 05 §5.1 (FTC neutral gate) |
| G2 | **Guest Opinions** | Read-only Discover, threads and tags. No author histories, reactions, votes or poll results. "Sign in to write". Quick exit visible. | — | — | — | Standard | 07 Impl 14; 10 S12 |
| G3 | **Guest → sign-up** | A guest action ("react", "write") opens A1. A draft is kept on the device. After A6, the person lands back on that compose screen once. | Draft (device) | — | Device | Container transform back to compose | 09 P13 fix 1 |

### 2.3 Sign-in: a new account

Order: **name → DOB → phone → code → consent.** DOB comes before the phone so that a minor never hands over a number (05 Q1; 09 Q1, P17). It's held on the device and written to the server after the code is verified (Q4).

| # | Screen | Shows | Collects | Req. | Stored | Motion | Evidence |
|---|---|---|---|---|---|---|---|
| A1 | **Your name** | "What should we call you?" Any script (`\p{L}`), 1–40 characters. No "forums" copy. | Display name | Required | Device until A4, then `users.display_name` and `profiles.display_name` (games read it) | Shared-axis X | 05 Impl 7, 25; 06 §2.8 |
| A2 | **Date of birth** | Three labelled numeric fields in locale order (Ghana/UK: Day · Month · Year; US: Month · Day · Year), no defaults, an example. Hint: "We only ever show your age, never your birthday." Confirmation names the month in words: **"8 November 1991 — that makes you 34."** Specific errors ("Day must be between 1 and 31"). Under 18: a stop that says nothing was saved, plus a 30-day block on the device. | DOB | Required | Device until A5, then `account_birthdates` via `set_my_birth_date` (§3.2) | None on the stop | 05 §5.1; 09 P6, P17; 02 Impl 11 |
| A3 | **Phone** | Country from the SIM or device region, never hard-coded Ghana. National format with a leading 0 accepted. "We'll text you a code" + "Send by WhatsApp instead". The WhatsApp choice asks: **"Is WhatsApp on +233 24 …?"** Inline: "By continuing you agree to the Terms and Privacy Policy." | Phone (E.164), channel | Required | Supabase Auth `auth.users.phone` | — | 05 A3, Impl 11; 09 P3 |
| A4 | **Code** | One field drawn as six boxes, labelled "Verification code, 6 digits".<br>• Autofill: Android SMS Retriever hash, iOS origin-bound code, WhatsApp one-tap.<br>• Resend at 30 s, then 60 s, then 120 s. After the second resend: "Try WhatsApp" / "Call me with the code" (voice).<br>• Codes valid for 10 minutes; either of the last two works. "Wrong number? Change it".<br>• A1–A3 are kept, so reopening resumes here. | — | Required | — | Accepted: check fades in, 400 ms hold, auto-advance. Wrong: colour, message and haptic; shake only if motion is on | 05 A4, Impl 8–10; 09 P1–P3, P12; 02 Impl 9 |
| A5 | **Before you start** (EULA v2) | Three plain bullets, with the full documents linked:<br>• Attune is for adults;<br>• what AI reads and when, in words a 63-year-old could repeat back;<br>• you can download and delete everything. | Consent record | Required | `record_eula_acceptance` v2 creates the `users` row (phone from the JWT). Then `set_my_birth_date`, then the name. Writes queue and replay if offline. | None | 05 A5; 06 Impl 1; 09 P2 fix 7 |

**A returning user** ("I already have an account"):
- A3 → A4. **A code is always sent.**
- Only after the code proves ownership: an existing account goes to the dormancy check (§2.11) and then home on the last path. No account gives "We couldn't find an Attune account for this number. Create one?", then A1, A2, A5, A6.
- This creates no number-lookup oracle (10 F-10, S5).
- If someone on "Get started" turns out to have an account, the typed name and DOB are discarded and never overwrite the stored ones.

**The invitee** is covered in §2.5 (RI).

### 2.4 "What brings you to Attune?"

| # | Screen | Shows | Collects | Req. | Stored | Motion | Evidence |
|---|---|---|---|---|---|---|---|
| A6 | **Path** | Three equal cards, nothing preselected:<br>• **In a relationship:** "A private space for you and your partner."<br>• **Single and open to dating:** "A few introductions a day. Only when it's mutual." Plus "Not open in {country} yet" where it's off.<br>• **Just for me:** "Your journal, quizzes and Healing. Single, partnered or in between."<br><br>Footer: "You can change this any time. Your journal and quizzes are yours whichever you choose." Link: **"My partner already invited me"**. | Path | Required (changeable) | `users.path` via `set_my_path`; `onboarding_profiles.completed_at` | 150 ms selection, then a 400 ms container transform | 05 A6, §3.3; 09 P1, P8 |

### 2.5 Path R: In a relationship

| # | Screen | Shows | Collects | Req. | Stored | Motion | Evidence |
|---|---|---|---|---|---|---|---|
| R1 | **Invite your partner** | • Share sheet with WhatsApp first; QR code for the same room; the code itself.<br>• Messages in three registers (straight English, Pidgin-inflected, plain-spoken). **Every message carries the code in plain text plus "Open Attune → I have an invite → K7P2QM".**<br>• A preview of exactly what the partner will see.<br>• "Invite later" · "My partner already invited me". | Invite | Optional | `relationships` pending row (7-day TTL) | — | 05 R1; 09 P1 fix 1–2; MASTER_SPEC §8.8 |
| R2 | **Heads-up** (inline on the sent screen) | "Get a heads-up when {name} joins" | Push permission | Optional | OS / OneSignal | — | 05 R2, Impl 15 |
| R3 | **Your space while you wait** (the home, not a wall) | • A first note; "a quiz about you, for you"; the **About us** card (AU1–AU5 below).<br>• A read-receipts-off line.<br>• **48 h:** a private reflection space.<br>• **Day 7:** Keep waiting / Use Attune on my own for now / **Send a new invite**.<br>• **Never a Dating entry on this path.** | Drafts | Optional | `couple_profile_drafts` (§3.4) | — | 05 R3; 09 P4 fix 1–3; CR-06 F4 |
| R4 | **Linked** | "You're both here", once on each phone. Chat opens. The About-us draft moves to `couple_profiles`, visible to both. Inline: "Get notified when {name} messages you". | Push permission | Optional | `relationships` active | Avatars settle, at most 600 ms, one light haptic | 05 §6; 09 §3.3 |
| R5 | Later | Ask 2 (now **saves each answer** and resumes). Location is asked only inside Map. | — | — | — | — | 09 P2 fix 4 |

**About us** (AU): one question per screen, every one skippable, step dots "2 of 5", easiest first. Shown during the wait and after linking, never before the invite (05 Q7).

| # | Question | Options | Helper text | Evidence |
|---|---|---|---|---|
| AU1 | "How would you describe where you two are?" | Dating · Engaged · Married · Something else (in your words, 40 characters) | Engaged: "planning to marry, including after the knocking and before the wedding". Married: "any kind of marriage: customary, religious or civil". **Wording to be confirmed by the cultural reviewer.** | 05 §5.4; 09 P3 fix 4; 01 §2.6 (08 01-11 verified) |
| AU2 | "When did you two get together?" | Month + year. "Add the day" is optional; "Not sure of the month" accepts a year only. No future dates. For couples who met through Dating, a **match-date chip** they can tap (never pre-filled). | "Use whichever date feels right to you both." | 05 §5.5; 09 Q11 |
| AU3 | "What year did you marry?" (only if Married) | A year, plus "Had more than one ceremony? Add another" (at most 2, each optionally labelled customary / church / mosque / civil / other) | — | 05 §5.6; 09 P2 |
| AU4 | "Where do you two live?" | Together · Apart, nearby · Long distance | No option ranks above another | 05 §5.7 |
| AU5 | "Are there children in your life together?" | No · Yes · We're expecting. If Yes, optional age bands: under 2 · 2–5 · 6–12 · 13–17 · 18+. No names or counts. | No "yet", no fertility questions, no follow-ups by date | 05 §5.8 |
| AU6 | "Remember your anniversary?" | Off / Together since / a ceremony date | **The single source** for Together's "Add your anniversary" reminder | 06 Impl 5; 09 P2 fix 5 |

**RI: the invitee**
- **Arriving:**
  - Link → store → install. Android passes the code through the Play Install Referrer (05 §4.0, not re-fetched); on iOS the code is typed.
  - Before sign-in the screen says only **"You've been invited to Attune"**. The inviter's name is shown only after the code is verified, so the 6-character code is never a pre-auth name lookup. This applies the 10 F-10 principle.
- **Signing up:** A1 → A2 → A3 → A4 → A5. The path is preset to Relationship (A6 is skipped), with a small "Not what you expected? Choose another way".
- **Accepting.** `accept-invite` now:
  - checks the age from `account_age()` on the server (it refuses with a neutral error);
  - requires a verified phone;
  - **withdraws the acceptor's own pending invite in the same transaction** (06 Impl 1; 10 S16; 09 P1 fix 3).
- **Today's order changes:** the gate currently accepts *before* the name step (`onboarding_gate.dart:41-44`). The new order is to accept after A5, and the pending code key is scoped per user (06 R3, R4).
- **An expired code:** "This invite has expired. Ask {name} to send a new one", with a one-tap WhatsApp message (09 P4 fix 5).

**The partner who never joins** (09 P4; 05 §3.4):

| When | Inviter sees | Rule |
|---|---|---|
| Day 0–2 | A first note, the quiz, About us, and the 48 h reflection space | Day-0 value alone; never a wall |
| Day 7 | Keep waiting / Use Attune on my own for now / Send a new invite (with an option to send to a different number) | "On my own" **keeps the path as Relationship with link state *none*.** It never shows Dating, and the About-us draft survives |
| Day 30 | One line: "Want to send {name} a new invite?", never again unless asked | Codes are never renewed silently (a long-lived code can be accepted by whoever holds it) |
| Content gap | Solo "Working on us, on my own" content (a private Love map, conversation starters, the one-person parts of the conflict toolkit) | **Follow-up content, not in these specs.** Owner Q7 |

### 2.6 Path D: Single and open to dating

Spec 2 builds this; Spec 1 builds the entry point. Order: where → consent → you → who. This follows 09 §3.1, except that **"you" comes before "who"**: the country note, and the rule in countries where same-gender introductions are off, both need the person's own gender first.

| # | Screen | Shows | Collects | Req. | Stored | Motion | Evidence |
|---|---|---|---|---|---|---|---|
| D0 | **Gentle-wait check** (only if it applies) | If the person's relationship ended inside Attune and the 30-day window is still open: "Before you begin" (3 private reflection questions, never scored), "Healing is here if you want it", and "Dating opens for you on {date}". Copy: "This pause is because your relationship ended here. It isn't a judgement about you." | Reflection (optional) | — | Own-only; deleted on exit | None | 03 Impl 13; 09 P15; T4 |
| D1 | **How Dating works** | • Up to 3 introductions a day; "Interested" is private; a match only when both say yes; a separate chat.<br>• **Every gate disclosed:** a video selfie with an age check, 2+ photos, the **exact day of the first introductions**, where Dating is open.<br>• Actions: Set up Dating / **Not ready? Use Attune just for me** / Set up later (one quiet card, no banner).<br>• Where Dating is closed: "Dating isn't open in {country} yet" + "Tell me when it's here". | Notify-me opt-in | — | Aggregate count per country | Shared-axis X | 05 D1; 02 §2.6 (Bumble face-check lesson); 09 P5, P8, P14 |
| D2 | **What are you looking for?** (one screen) | • Marriage · A committed relationship · Companionship, at my own pace · Not sure yet.<br>• If Marriage: an inline timeline (next year or two / a few years / no set timeline).<br>• A required line: **"I'm not married and not in a relationship."**<br>• Optional "Married before? Never / Divorced / Widowed", hidden by default with a per-field "show on my profile". | Intention, timeline, attestation, marital history | Intention and attestation | `dating_profiles` | Step dots | 01 Impl 1–2, 12; 09 Q4, P7; 02 Q5 |
| D3 | **Where are you?** | • Country (ISO, from the SIM) + region from a per-country list: all 16 Ghana regions, UK regions and cities.<br>• An optional mega-city "side" (Accra / Tema; Lagos Island / Mainland).<br>• "Also open to people in…", off and hidden until the account is verified and at least 14 days old. | Country, region, side | Country and region | `dating_profiles` | — | 04 Impl 2, 20; 09 P5, P11, Q8, Q17 |
| D4 | **Your answers stay private** (explicit consent) | • The purpose (introductions only).<br>• Who sees what: never who you want to meet; gender only if you choose.<br>• How to withdraw: Exit deletes everything.<br>• "Nothing from your journal, quizzes or Healing is used to introduce you." | Consent (versioned) | Required | `dating_consent_events` | None | 04 Impl 13; 09 P9 fix 2; GDPR Art. 9(2)(a) |
| D5 | **Which best describes you?** | Woman · Man · Non-binary · "Add something more specific" (a list plus a 30-character write-in). **Where same-gender introductions are off:** Woman / Man only, plus honest copy and resources for anyone this doesn't fit (Q2). | Gender identity | Required | `dating_profiles`, encrypted in the application; `gender_visible = false` | — | 05 §5.2; 08 05-5; 10 S3 |
| D6 | **Who would you like to meet?** | • Men · Women · Everyone (stored as an explicit full set). "Only you can see this. It's never on your profile."<br>• **Country note before saving** when the effective tier is 1 or 2 (§4.8.2). It is shown on the device and never logged. In Ghana it also mentions "people you know" (the duty to report, 08 A1).<br>• **Where off:** the other gender, with "In {country}, Attune introduces men and women to each other for now. Why?" | Who you want to meet | Required | `dating_preferences`, encrypted in the application | None on the note | 05 §5.3; 04 Impl 3; 10 S3 |
| D7 | **Children** | Have: yes/no. Want: yes/no/open, with an optional "must match". "I'd rather not meet people who have children" is allowed; **a filter to *seek* parents is never offered.** | Have, want, dealbreaker | Have and want | `dating_profiles` | — | 01 Impl 10; 10 S22 |
| D8 | **Faith** (optional) | • "My faith", from a region-aware list (Christian with an optional denomination, Muslim, Traditional, Hindu, Sikh, Buddhist, Jewish, Other, None, Prefer not to say).<br>• "How much does sharing a faith matter?": doesn't matter / nice / must share. "Must share" becomes a symmetric dealbreaker.<br>• "Show on my profile" off by default. | Faith, importance, denomination, visibility | Optional (Skip) | `dating_profiles`, encrypted in the application | — | 01 Impl 9; 02 Q4; 09 P5, P8, Q14 |
| D9 | **Photos** | • 2–6 photos through the system picker; **resized on the device**; EXIF stripped; moderated.<br>• "Photos with children can't be used on Dating. Crop to just you?"<br>• "Show my photos after we're both interested", **available from account day 30**. | Photos | 2 required | Private bucket; signed URLs | Upload progress in words | 01 §3.1; 09 P6, P11; 10 Q11 |
| D10 | **Prompts** | 2 of 3, with suggestions | Prompts | 2 required | `dating_profiles` | — | 02 L4; 09 P7 |
| D11 | **Verify it's you** | • A live video selfie: liveness, an age estimate (challenge age 25), and a match against **every** profile photo.<br>• Audio and haptic guidance; tips on light and glasses; a photosensitivity warning if light challenges are used. Resumable.<br>• Under 25 by estimate, or two failed captures: the **ID fallback** (for example the Ghana Card) or **human review within 24 h**.<br>• "The video is deleted at once. We keep only pass or fail." | Pass/fail, method, time | Required | `dating_age_verifications` (service role only) | A calm "You're verified" check | 04 Impl 9, 19; 10 S1, S2; 09 P11, P12, Q13 |
| D12 | **This is what others see** | First name, **age (never DOB)**, region, intention, prompts, photos. Gender only if chosen; never who you want to meet. Inline: "Tell me about matches, at most once a day." | Push permission | Optional | OS | Cross-fade | 05 D7–D8 |
| D13 | **Ready** | • "Your first introductions arrive **Thursday at 7 pm**", with an adjustable drop time.<br>• One "get ready" item: the first-date guide, the journal or a quiz.<br>• "Does anyone else use this phone?" → a PIN on every open, or the Dating lock.<br>• In Tier 1/2 countries: "Some people like their apps to look plain" (discreet icon). | Drop time, lock choice | Optional | Own settings | None | 09 §3.1 #5–6; 10 S17; 04 Q11 |

**The 72-hour cool-off runs from account creation (A5), not from activation** (09 Q3). Same-country introductions are the default.

### 2.7 Path J: Just for me

| # | Screen | Shows | Collects | Req. | Stored | Motion | Evidence |
|---|---|---|---|---|---|---|---|
| J1 | **Me home, straight away** | One first-action card: **Write your first note** / **Take a 3-minute look at how you connect** (the old Track A quiz, now optional, with the F9 caveat). A journal-lock offer at the first entry. | — | — | — | "Saved, just for you" in text only | 05 J1–J2, Q3; CR-06 F11 (7) |
| J2 | **Healing** | Entry text: **"After a breakup or a loss"**. Bereavement routes to grief resources (F10 `grief`). | — | — | — | — | 09 P7, Q15 |
| J3 | **Reminder** | "Remind me to write on Sundays" → **the push ask happens here** | Push permission | Optional | OS | — | 05 J3 |
| J4 | **More ways to use Attune** | **One neutral row** opening a sheet that offers Relationship or Dating. It replaces the two rows "Invite a partner" and "Turn on Dating". | — | — | — | — | 09 P19 fix 1 |
| J5 | **"Attune asks"** | A weekly self-focused prompt card linking into Opinions | — | — | — | — | 07 §2.9 |

### 2.8 Each path's home (two-tab shell kept, Master Spec decision 11)

| Who | Tab 1 | Tab 2 (default) | Notes |
|---|---|---|---|
| Guest | **Opinions** (Discover) | Sign in (the current `LoginProfile` shell, with new copy) | G1 gate first |
| Relationship, linked | Opinions | **Chat**: `ChatHomeScreen`, with the Plans card first | As today |
| Relationship, pending / on my own / paused | Opinions | **Chat**: the waiting space (R3) | **Paused stays on the Relationship home** (06 §2.3). Never Dating |
| Dating | Opinions | **Me**, with the Dating section on top: today's introductions, "arrive Thursday 7 pm" or "not open here yet"; matches; dating chats. Then **Your space**: journal, quizzes, Healing | **Label "Me", not "Dating"**: launch users are in a Tier 1 country and phone checking is common (10 S5, S17, S19; 07 §2.7). An optional **Dating lock** puts the Dating section behind the PIN. Q6 |
| Just for me | Opinions | **Me** (J1–J5) | Not Opinions (T8) |

**Regression:** add the path to `_HomeGateData`. Keep the onboarding redirect latch and the `ModalRoute.isCurrent` guard exactly as they are. `HomeWidget` applies `initialTabIndex` only in `initState`, so a path change needs a keyed rebuild (06 §2.7, R1).

### 2.9 Switching paths

Settings → **How you use Attune**. The personal layer is always on underneath. Relationship and Dating are never both active. **Every switch is silent to everyone else** (05 §4.3).

| From → to | What happens | Evidence |
|---|---|---|
| Just for me → Relationship | "Invite a partner" → path = relationship (pending). **Withdrawing the invite returns the person to their previous path** (`users.path_previous`). | 09 P14 fix 3 |
| Dating (active) → Relationship | First a confirmation: **"Inviting a partner pauses Dating. Continue?"** The relationship guard then pauses Dating. | 09 P14 fix 4; 06 §2.4 |
| Dating → Just for me | Dating is **paused** silently and hidden at once. Exit, a hard delete, is offered separately. | 03 Impl 12; 10 Q10 |
| Just for me → Dating | D0 → D1 … D13 | — |
| Wrong first choice | D1's "Not ready? Use Attune just for me" switches in one tap | 09 P14 fix 1 |
| Relationship (linked) → anything | Needs Pause or End (the lifecycle from Spec 3a). See §2.10. | CR-06 F1 |
| Any switch | The Opinions status label for **future** posts re-derives. No partner, match or ex is ever told. | 06 Q7; 10 S18 |

### 2.10 Ending → gentle wait → Dating

1. **End:** no push to the other partner. Both see a warm ending card, a 30-day read-only window and an export. The former-partner exclusion is written both ways (CR-06 F1; 10 F-12; 06 §2.4).
2. **During the window:** the home shows the ending card and Your space. **No Dating prompt appears anywhere on the home**, which fixes `chat_couples_locked_screen.dart:255-258,371-384`. Dating stays reachable through Settings (09 P15 fix 2).
3. **Choosing Dating early:** D0 shows the reflection, Healing, and "Dating opens for you on {window end}". The wait ends when the window closes for both, or earlier if both seal (T4, Q12).
4. **After that,** Dating follows the normal flow. The ex-exclusion applies forever, and generation **refuses to run** if the exclusion key is missing (10 S6).
5. **Measure:** account deletions within 7 days of seeing the D0 screen, as an aggregate proxy for evasion (09 P15 fix 4).

### 2.11 Recycled numbers and new devices

| Rule | Detail | Evidence |
|---|---|---|
| **Dormancy rule** | A sign-in from a **new device after at least 180 days without a sign-in** doesn't open any data. A passkey challenges the person if one is set, once passkeys exist. Otherwise it shows one neutral choice, **"I'm new to Attune"**: that starts a fresh account and puts the old one into a support-only recovery hold. **The DOB alone never unlocks anything.** The screen reveals nothing about the old account. | 05 §5.0, §3.2.5; 10 S7 (overrides 05's DOB step); Lee & Narayanan 2021 (M) |
| **New-device Dating re-verification** | On every new-device sign-in, a selfie is compared with the person's approved photos (existing CompareFaces) **before any Dating screen renders.** This covers recycled numbers and SIM swaps. | 10 S5, S7 |
| **Existing protections** | The new-device notice and "Sign out all other devices" (Spec 2 F7) | 10 S7 |
| **Support policy** | Support **never confirms or denies** that an account exists, except under valid legal process | 10 S5; 04 Impl 8 |
| **Later** | Passkeys offered after week 1, as fast re-sign-in and as the dormancy challenge (post-launch; `supabase_flutter` 2.15 or later). FIDO Oct 2026 Index: 93% vs 78% success (08 05-10). | 05 Impl 13, Q9 |

### 2.12 Offline and low-data

| Need | Decision | Evidence |
|---|---|---|
| A bad network can't trap anyone in onboarding | Extend `OnboardingSyncService` replay to the DOB, path and About-us writes. A1–A3 are kept on the device. `accept-invite` and Dating wait for the DOB to be written on the server. | 05 §3.8; 09 P1 fix 4 |
| The first frame never waits on the network | Check whether `Supabase.initialize` (30 s timeout, awaited) blocks on a token refresh. If it can, start from the local session and refresh in the background. Regression risk: shared `main.dart`. | 09 P11 fix 2 |
| App size | Measure it, then set a budget: split ABIs or an app bundle, and load heavy modules (Mapbox) on demand | 05 §3.1 (1% fewer installs per 6 MB, M; 08 05-6) |
| Data saver for Dating | Text-first introduction cards with photos on tap; D1 states the approximate data use; photos resized before upload | 09 P11 fix 3–4 |
| Unreliable pushes (Transsion phones) | Introductions last **7 days** and always show when the app opens. Nothing depends on a push arriving. | 09 P11 fix 6 |
| Liveness on 2 GB phones | Resumable, with a human fallback within 24 h | 09 P11 fix 5 |
| Share my plan | Also sent as plain SMS text | 09 P11 fix 8 |
| Journal | Verify that it saves offline and syncs later | 09 P9 fix 3 |

### 2.13 Accessibility, including the text-scale clamp fix plan

**Today:** `lib/app/app_shell.dart:34-35` wraps every route in `MediaQuery.withClampedTextScaling(maxScaleFactor: 1.0)`. The phone's text size is ignored app-wide, against CR-06 F16 and 05 §3.8. That shuts out Kwadwo (63), Helen (52) and every low-vision user (09 P2, P7). The 6-box code field has no semantics (`verification_code_field.dart:161-172`), and liveness guidance is visual only (09 P12).

**Plan (four stages; Q11):**
1. **Opt-in wrapper for new screens (S1 W2 onwards).**
   - A small `AllowLargeText` widget re-reads the platform scaler (`MediaQueryData.fromView(View.of(context)).textScaler`) and clamps it to 2.0 for its subtree. This is needed because a nested `withClampedTextScaling` cannot rise above the parent's 1.0.
   - Every new onboarding, About-us, Me and Dating screen is built and golden-tested at 1.0, 1.3 and 2.0 from day one.
2. **Audit existing surfaces (S1 W10).**
   - Order: chat, Opinions, Together/Planning, Settings, Healing, journal.
   - Golden tests at the same three scales, fixing truncation and overflow.
   - Check how `ScreenUtil`'s `fontSizeResolver` and `minTextAdapt` (`screen_util_config.dart`) compound with the system scale, and the iPad 1.25× cap (memory: iPad layout).
3. **Raise the root clamp to 2.0** once the audited surfaces pass. Games keep a local 1.0 clamp if their layouts can't flex, so **Games aren't touched**: they're only wrapped.
4. **Device matrix before switch-on:** TalkBack, VoiceOver, 200% text, Android Go.

**Regression risk:** the root shell wraps every route, so every screen reflows. That is why the raise comes last and behind the audit.

**Also:**
- one labelled code field;
- accessible liveness: audio and haptic cues, plus the human fallback;
- undo lasts until the next action, or at least 20 s when a screen reader is on (WCAG 2.2.1);
- photo rejections name which photo;
- optional photo captions the person writes themselves (09 P12);
- the 900 ms onboarding card advance cut to 320 ms or less (05 §6);
- `Semantics` and the Flutter accessibility guidelines (`labeledTapTargetGuideline`, `androidTapTargetGuideline`, `textContrastGuideline`) in widget tests.

---

## 3. Data model

### 3.1 Storage and RLS principles

1. **Private by default.**
   - New per-user tables use RLS with `REVOKE ALL FROM PUBLIC, anon, authenticated`.
   - Writes go only through `SECURITY DEFINER SET search_path = ''` RPCs that derive the actor on the server.
   - This copies `dating_age_verifications` (06 §2.2.4).
2. **`users` gets column grants, never a table-level UPDATE.** The client may write only `display_name`, `avatar_url` and `timezone`. Any new column is otherwise client-writable (`20260724120000:13`; 06 R6; 10 F-1).
3. **Nothing new goes on `profiles`.** Every signed-in user can read it (`20260713120000:57-60`). It keeps `display_name` and `avatar_url` because 8 game call sites read them (06 §2.8).
4. **Nothing new goes on `relationships`.** It has no client UPDATE and a column-level SELECT list, so new columns would be invisible (06 R7). Shared couple data lives in `couple_profiles`, readable by members only, with RPC writes and a Together change signal.
5. **Special-category data stays in Dating tables only:**
   - gender identity, who you want to meet, faith, and marital history;
   - **encrypted in the application** with a server-held key;
   - never in logs, analytics, push payloads, admin list views, support tools or AI prompts;
   - never readable by the client for another user;
   - a DPIA covers it (04 Impl 13; 01 Impl 5; CJEU C-184/20, 08 04-36).
6. **Deletion deletes**, with three exceptions that survive as **keyed phone HMACs**, named in the privacy policy (10 S15):
   - enforcement records;
   - blocks;
   - anonymised reports.
7. **CI canaries, not one-off tests:**
   - a dating RLS/RPC canary;
   - a storage-bucket policy test;
   - secret scanning;
   - a contract test proving no type or score is derived from couple-profile fields;
   - the delete → re-register → tamper test (04 Impl 17; 10 S6).

   The `analysis_sessions` incident shows RLS regressions happen here.
8. **No analytics SDK.** Server-side aggregate counters only, daily buckets, displayed at n ≥ 50 or more, never with special-category values or age signals (05 Impl 22; Play Age Signals terms).

### 3.2 Identity

**`public.users`**

| Field | Type / values | Written by | Read by | Notes |
|---|---|---|---|---|
| `id` | uuid → `auth.users` | `record_eula_acceptance` | Own row | — |
| `phone` | E.164 | **A definer trigger from `auth.users` only**; no client grant | Own row | **All HMACs are computed from `auth.users.phone`, never from this column** (10 F-1, S6). Stop the onboarding upsert writing it in the same release (06 R6). |
| `display_name` | 1–40 characters, any script | Client (column grant) | Own row; others via `profiles` | — |
| `avatar_url`, `timezone` | — | Client (column grant) | Own row | — |
| `path` | `relationship` / `dating` / `just_me` | `set_my_path` | Own row | The home the person chose, not an authority. Link state stays in `relationships.status`; Dating state in `dating_enrollments.state`. |
| `path_previous`, `path_chosen_at` | — | `set_my_path` | Own row | Undo after a withdrawn invite |
| `eula_version`, `eula_accepted_at` | `'2'` | `record_eula_acceptance` | Own row | v2 adds 18+, Opinions content rules and the AI disclosure |
| ~~`mode`~~ | — | — | — | **Retired.** Nothing reads it. Stop all 8 writers: the onboarding upsert, the invite functions' `ensureUserRow`, and the dating activate/pause/exit/delete RPCs. Drop the column (06 §2.3, Impl 3). |

**`public.account_birthdates`** (new, private):
- **Fields:**
  - `user_id` (PK);
  - `birth_date`;
  - `source` (`self_declared`);
  - `declared_at`;
  - `corrected_at`.
- **RPCs:**
  - `set_my_birth_date(date)` returns the age. It refuses under 18 with an opaque error and refuses a second set.
  - `get_my_age()`.
  - An internal, ungranted `account_age(uuid)` for `accept-invite` and Dating.
- **Corrections:** **one self-correction within 7 days, and only while Dating is not active.** After that, corrections go through support (05 Q14).
- **Exposure:** the DOB is never displayed or exported to anyone else. The user's own export includes it.
- **Never written into `dating_age_verifications`:** the sign-up DOB is a declaration, not assurance (04 C3).

**`dating_age_verifications`** (exists, service role only):
- method (`fae` / `id` / `human`);
- result;
- challenge age;
- decided-at time;
- the vendor reference.

It stores **no images and no face template** (04 Q8; 08 04-34: Tinder keeps a FaceMap, Attune deliberately doesn't).

**`profiles.relationship_status`: stop writing it.** It is public to every signed-in user and goes stale at once (06 §2.2.1). The Opinions label moves to a private own-row setting and is **stamped onto the post on the server at posting time** (§5.4).

**`onboarding_profiles`:**
- drop `mode`;
- `attachment_answers` and `anchors` become optional;
- `completed_at` is set at A6;
- the Ask 2 fields stay.

**Small tables:**
- `pending_invite_code` is scoped per user (06 R4).
- `metric_counters(day, key, count)` is written through one definer RPC (§9).

### 3.3 Identity and abuse fixes from 10 (P0)

| Fix | Change | Evidence |
|---|---|---|
| The phone can't be rewritten | `users` column grants. `phone` is written only from `auth.users`. `dating_phone_hmac()` reads `auth.users.phone`. | 10 F-1, S6 (the bypass is inferred from the grant at `20260724120000:13`) |
| Generation fails closed | `run_dating_candidate_generation` refuses to run when the exclusion key is missing. The health check already reports it. | 10 F-9, S6 |
| Enforcement survives deletion | `prepare_account_deletion` writes `enforcement_records{phone_hmac, restriction_type, confirmed_report_count, expires_at}`. It is checked at account creation (an Opinions posting ban carries over) and at `activate_dating_profile`. Retention is **2 years**, subject to counsel (Q5). | 10 F-2, S1, Q4 |
| Reports survive either side's deletion | `dating_reports.target_user_id` and `reporter_user_id` become `ON DELETE SET NULL`, with `target_phone_hmac` added. The reporter is anonymised, never deleted. | 10 F-2, S8, S15 |
| Blocks survive re-registration | Blocks are also stored as phone-HMAC pairs. **The "no repeat pair" history is *not* kept for deleted accounts:** pair history can reveal orientation (S15), and re-introduction to someone who declined is minor harm. | 10 F-3, S10 |
| Never introduce me to these numbers | `dating_never_introduce(owner_user_id, phone_hmac)`. A symmetric hard filter; the owner of the number is never notified. | 10 S5, Q7 |
| Activation is actually possible | Build the writer for `gender_identity`, `gender_preferences`, `region_preferences` and `intention_preferences`. Store "everyone" as an explicit set, removing the conflict between the activation predicate and generation. | 06 §2.4, Impl 6 |

### 3.4 Shared couple profile

`couple_profile_drafts(user_id PK, …same fields…)`:
- own-row;
- the inviter fills it while waiting;
- it is **moved into `couple_profiles` inside the `accept-invite` transaction**, so a withdrawn invite never wipes it (09 P4 fix 7).

`couple_profiles(relationship_id PK → relationships ON DELETE CASCADE)`:

| Field | Values | Notes |
|---|---|---|
| `together_since` | date + `together_since_precision` (`day` / `month` / `year`) | **Never rendered as an elapsed counter**; countdowns to togetherness are allowed (CR-06 §5.4) |
| `stage` | `dating` / `engaged` / `married` / `other` | — |
| `stage_words` | Up to 40 characters, only for `other` | The couple's own words |
| `ceremonies` | Up to 2 × `{year, label?}` (label: customary / church / mosque / civil / other) | Only when `married` |
| `living` | `together` / `apart_nearby` / `long_distance` | `distance_ends_on` stays in Plans/Map |
| `children` | `none` / `yes` / `expecting` / `prefer_not_to_say` | — |
| `child_age_bands` | Subset of `under2`, `2to5`, `6to12`, `13to17`, `18plus` | Optional. No names, counts or whose child |
| `anniversary_source` | `off` / `together_since` / `ceremony_1` / `ceremony_2` | Drives Together's reminder (one source) |
| `<field>_changed_by`, `<field>_changed_at` | uuid → `auth.users ON DELETE SET NULL`, timestamptz | Drives "Changed by Yaw · 12 Nov" (dates via `MyDateFormat`) |
| `updated_at` | — | — |

**Edit-history visibility:**
- Both partners always see the live values plus one attribution line per field.
- **No push, no activity feed, no history list.**
- *Optional, P2:* when partners flip the same field back and forth twice within a week, show once: "You two see this differently, and that's fine. 'Something else' lets you use your own words" (09 P3 fix 4).

**Writes and lifecycle:**
- **Writes:** only `update_couple_profile(relationship_id, patch)`, which checks active, non-archived membership, validates each key, locks the row and bumps `together_change_signals` so both phones refetch.
- **Lifecycle:** read-only during the ending window, then archived and purged with the relationship. Included in the per-relationship export (`20261018120000:128-137`).
- **Never** in AI prompts, analytics, widgets or push bodies.
- **Never a type or a score:** no derived column, plus a contract test.

### 3.5 Dating profile fields

| Field | Values | Visible on profile | Filter? | Category | Evidence |
|---|---|---|---|---|---|
| Age | Derived on the server from the DOB | Yes (age only) | Symmetric age range, 18–99. For ages 18–20 the default is at most 7 years older | — | 01 Impl 19; 03 Q6; 06 §2.4 |
| Country, region, side | ISO; per-country list; optional side | Region | Same country by default; region preference "my area / my region / anywhere in my country" | — | 04 Impl 2; 06 Q9 |
| Open abroad | List of countries; off | No | Cross-border only if both have opted in, both are verified, and both accounts are 14+ days old | — | 04 Impl 20; 09 Q17 |
| Intention | Marriage / committed / companionship / not sure | Yes | Symmetric, through a compatibility matrix set in configuration | — | 01 Impl 1; 09 Q4 |
| Marriage timeline | 3 values, only for Marriage | Optional | Shared ground only | — | 01 Impl 2 |
| Not-married attestation | bool + time | No | Required; re-asked on any change | — | 01 Impl 12; 02 Q5 |
| Marital history | Never / divorced / widowed | Per-field toggle, off | No | Sensitive (Kenya) | 01 Impl 12; 09 P7 |
| Gender identity | Woman / man / non-binary + specific/write-in | Only by choice (`gender_visible = false`) | Symmetric | **Art. 9**, encrypted | 05 §5.2 |
| Who you want to meet | Explicit set of men and/or women | **Never** | Symmetric | **Art. 9**, encrypted | BRIEF; 04 Impl 4 |
| Children have / want | yes/no; yes/no/open | Yes | Want can be a dealbreaker; "has" can only be *excluded*, never sought | — | 01 Impl 10; 10 S22 |
| Faith, importance, denomination | Region-aware list; 3 levels | Toggle, off | "Must share" dealbreaker | **Art. 9**, encrypted | 01 Impl 9; 09 Q14 |
| Family involvement | "How involved do you want family to be?" | Shared ground only | No | — | 03 Impl 15 (asked after the first introduction) |
| Photos | 2–6 approved | Yes; "after mutual interest" option from day 30 | Never ranked | Biometric at verification (transient) | 01 Impl 8; 10 Q11 |
| Prompts | 2–3 | Yes | No | — | — |
| Pronouns | Optional free text | Yes, if given | No | — | 05 §5.2 |
| Verification | Pass/fail + time | No public badge (no over-trust) | Required before the first introduction | — | 04 §2.7 #6 |
| Drop time, lock, digest | Settings | No | — | — | 09 P6 |

### 3.6 Configuration and shared safety tables

| Table | Purpose |
|---|---|
| `country_safety_config` | Per country, versioned: `tier` (1/2/3), `dating_enabled`, `same_gender_enabled`, `region_list`, `resources_verified_at`, `legal_checklist`, `source_url`, `reviewed_at`. Reviewed quarterly at minimum; the Ghana row is re-reviewed after the bill's second consideration, not on assent (04 §2.1.6; 08 A1). |
| `support_resources` (F10 v2) | `country_code` + category (emergency, dv, crisis, sexual_assault, sextortion, lgbtq_legal, grief, child_safety…); emergency number first; **an expired `verified_at` blocks release**; offline cache (CR-06 F10; 04 G9) |
| `enforcement_records`, `dating_block_hmacs`, `dating_never_introduce` | §3.3 |
| `metric_counters` | §9 |

### 3.7 What we do NOT collect, and why

| Not collected | Why | Evidence |
|---|---|---|
| Gender at sign-up; pronouns outside Dating | Relationship and Just for me don't need them; copy uses names | 05 §5.2; CR-06 §1.2 |
| An orientation label | "Who you want to meet" is the minimum needed; a label adds outing risk | 04 Impl 4 |
| Contacts | Not needed (the share sheet covers invites); a contact-graph exposure risk | 05 Impl 16 |
| GPS, precise location, distance | Trilateration in 6 of 15 apps (KU Leuven); Raw leak | 04 §2.1.5 |
| Ethnicity, tribe, caste | Special category everywhere; contested filters; a bias amplifier | 01 Impl 11, Q9; 02 §2.3 |
| Income, education or job (v1), height, body type, weight | Fraud lure; hierarchy; body-image harm | 01 §3.2; 03 (d) |
| Health, HIV, disability | The Grindr cases; special category | 04 Impl 14 |
| Zodiac, personality type, camera roll | No predictive value; inference creep | 03 (a); 01 Impl 15 |
| Children's names, photos or ages on a dating profile | 12.4% report requests to exploit children (AIC, Strong) | 03 §2.9 |
| Face templates, selfie video, ID images | Breach and legal liability (Tea, BIPA); pass/fail is enough | 04 Q8; 08 04-34 |
| IP location history | Processed in the moment for the effective tier, never stored | 04 Impl 1 |
| "What do you want to work on?" in couples onboarding | "This app thinks every couple has issues" | CR-06 §9 |
| Reasons for ending; the history of who you were introduced to after deletion | Not needed; it can reveal orientation | 10 S15 |

---

## 4. Dating Mode design

**Theory of change.** Attune helps single people meet a few well-filtered, verified people. It helps them reach a first meeting soon, where both feel responded to, and then decide, rather than slide, into what comes next. It never keeps them browsing. Success is leaving (03 (e); Joel 2020, Strong; 02 L1).

### 4.1 Who can use it (eligibility)

| Gate | Rule | Replaces |
|---|---|---|
| Age | Every Dating user worldwide passes D11 (liveness + estimate + CompareFaces) before any introduction | Today's `verify_dating_age` has no caller (06 §2.4) |
| Country | The Dating country is enabled, **and** the session's IP country is not a disabled country | No country awareness (04 G1) |
| Relationship guard | A pending, active or paused relationship blocks Dating (keep `dating_has_relationship`) | — |
| Gentle wait | Only after an ending inside Attune, for the 30-day window (T4) | **The Healing gate** (readiness above 70, all stages, 8 weeks) in `get_dating_eligibility`, `activate_dating_profile` and `dating_candidate_is_current` (06 Impl 7) |
| Trust friction | A 72 h cool-off from account creation; caps; same country by default | The Healing journey's accidental anti-scam cost (04 C2) |
| One person, one account | Attestation, terms, and a duplicate-account signal sent to moderation (never to a partner) | 10 S18 |

### 4.2 Matching: what is feasible, and the values people state

1. **Symmetric hard filters** (keep `dating_pair_passes_hard_filters` and extend it):
   - age ranges both ways;
   - gender and preference both ways, **only where `same_gender_enabled` allows it**;
   - same country unless both people opted into each other's country;
   - region preference;
   - the intention matrix;
   - want-children and faith dealbreakers;
   - phone-HMAC blocks, the former-partner exclusion and the never-introduce list;
   - no repeat pair, and a cooldown after a previous match.
2. **Ranking after the filters:**
   - feasibility first (intention, children, place);
   - then the **number of explicit shared values** (intention, timeline, children, how much faith matters, family involvement);
   - then **exposure balancing with bounded randomisation**.

   **Not used:**
   - attachment, communication or conflict-style distance (remove them from `dating_alignment_v1` and its snapshots);
   - quiz answers (remove the historical-data consent);
   - popularity, activity, reply speed;
   - anything derived from photos (03 §2.1, (a); Dyrenforth 2010, Strong; Joel 2017).
3. **"Why you two were introduced"**, renamed from "Alignment preview":
   - two or three overlaps the people stated themselves ("You both said marriage, in the next year or two");
   - always the line "**Attune can't predict chemistry; meeting is how you find out.**"

   Perceived similarity drives liking at a first meeting (Tidwell 2013).
4. **Fairness audit:** exposure and mutual-interest rates by country, region, age band and gender. Aggregate only. No race data collected (02 Impl 20).

### 4.3 Thin pools

- Never relax filters to fill a day.
- The empty state is honest: "No good fit today. Attune is still small in {city}. We'll introduce you when there's a good fit."
- Widening is offered as **a choice the person makes**: age range, region, abroad (02 Impl 15; 09 P6).

### 4.4 Introductions per day and queue caps (configuration, not constants)

| Setting | Value | Evidence |
|---|---|---|
| New introductions | **At most 3 a day**, delivered once at a time the person picks (default 19:00 local) | 03 (b); 02 Q2; 01 Impl 14 |
| Waiting | **At most 6** | 03 (b) |
| Pause | New introductions pause while **3 pre-date conversations are open** | 03 (b); Forrai 2023 |
| Lifetime | **7 days**, with **no countdown copy**; missed days don't stack; no refresh | 01 Impl 14; 09 P11; 03 (d) |
| First introduction | 72 h or more after account creation, and after D11 passes | 09 Q3; 04 Impl 19 |
| Actions | **Interested** / **Not for me**; undo for 5 s (or until the next action, at least 20 s with a screen reader); no rewind | 03 Impl 4; 09 P12 |
| Rate limit | `act_on_dating_introduction` at 30 a day (exists) | 10 S10 |
| Engine | A **daily** cohort key (today's weekly key silently caps a daily schedule, 06 R12), partitioned by country | 06 Impl 8 |
| Payload | First name, **age**, region, intention, prompts, "why you two", and approved photos through short-lived signed URLs (the counterpart photo read path is new). **Not cached on the device.** | 06 §2.4; 10 S19 |

### 4.5 Double opt-in and the match moment

- Keep the double-blind, viewer-scoped introduction state and the atomic match (Fable C3 fix).
- Nobody is ever told they were declined.
- **A mutual match:** a quiet, warm screen with no burst, no "It's a match", no counter (01 Impl 16; 03 (d)).
- **Push:** at most one a day, as a digest, always **neutral text: "You have something new in Attune"**. This replaces "New mutual match" (`20260816120001:89-92`; 10 F-4). Quiet hours apply (CR-06 F6).

### 4.6 From match to first conversation

**The dating chat:**
- a new `dating_messages` table with its own outbox and worker;
- its own screen, **never `ChatScreen`**, which embeds Games;
- never fed to the couples AI (`DATING_CHAT_SAFETY_SPEC.md` §9; 06 §2.4).

| Element | Design | Evidence |
|---|---|---|
| Modality | **Text only in v1.** No images, voice notes, video or clickable links. Voice calls come in a later wave (T9). | 04 Q5, Impl 25; UK cyberflashing priority offence |
| Contact masking | Phone numbers (including mobile-money and NUBAN formats, and numbers written as words), emails, URLs and @handles are **masked on the server until both people tap "Swap contacts"**. Swap is offered from 72 h after the match; **it never lifts by itself.** A one-time card at Swap: "On WhatsApp, Attune can't help inside the chat. Sextortion often starts with a video call." Amend chat spec §4.1 so these rule-based presentation rules are allowed; delivery stays fail-open. | 10 F-11, S8; 04 Impl 21, C5 |
| Guided first conversation | Three or more reciprocal question pairs, each revealed after both people answer, deepening gently, every one skippable, plus a "follow-up question" tip. Reviewed templates only; nothing written by AI. | 03 §3(c) 1; Sprecher 2013; Huang 2017 |
| Safety families | The existing deterministic, recipient-only, fail-open families, plus:<br>• **Ghana, Nigeria and diaspora money lexicon:** MoMo, airtime, "send me small", transport fare, data bundle, recharge card, the "sent by mistake" reversal scam, crypto, gift cards, customs fees;<br>• a **sextortion card** ("Don't pay. Keep the messages. Report here and to CSA 292 or your local line");<br>• later (P1): `meet_private_pressure` and `child_access`. | 04 Impl 22–23; 10 S1, S8, S9, S21, S22 |
| Normaliser | Keep Unicode letters (`\p{L}`). Fold Akan letters (ɛ, ɔ) only by reviewed rules. Zero-width characters become spaces. Golden fixtures in English, Pidgin and Twi spellings. | 10 F-5 (`chat_safety.ts:65-72`) |
| Blocks | Enforced in RLS, not the UI. A stale client cannot send after a block. | 10 S10; spec §4.4 |
| Timebox | Around day 7–10: "Plan a first meet?". Around day 21 with no plan: "Keep chatting, or close kindly?", **suppressed after either person taps "we met"**. No countdowns. | 03 §3(c) 4; Ramirez 2015; 09 P10 |
| Meeting kit | Public place; your own transport; **Share my plan** (time and place, **never the match's name or photo**, also as SMS text); an after-date check-in only the user sees. "Get help" shows emergency numbers behind a confirmation, plus a pre-written message **the user sends herself** to a trusted contact. Nothing is sent automatically. | 04 Impl 28–29; 10 S21; permanent constraint 3 |
| Close kindly | One tap sends a reviewed closing message and archives the chat. Silent unmatch stays available for safety. | 03 §3(c) 6; Navarro 2020 |
| Retention | Chat deleted at match close plus a **30-day evidence window**. Reports can be filed from match history for 30 days; a report snapshots the last N messages. | 04 Impl 8, 27; 10 S8 |

### 4.7 Match → couple link

1. **The request:** an in-chat **"Become a couple on Attune"**. It lives in a Dating-side request record and **creates no pending `relationships` row**, which would pause one person's Dating early (09 P10).
2. **Confirming:** each person sees a private "**What are we agreeing to?**": "Your Dating profiles pause for both of you; you'll share a private space; either of you can end it at any time." Then each confirms (03 Impl 14; Stanley 2006).
3. **Linking:** on the second confirmation, the server creates the active relationship using the invite exchange's code, in one transaction. **Dating pauses for both at that moment.** Both paths become Relationship, and the settle animation plays: "You decided together."
4. **Other conversations:** the other person in any other open dating chat sees a neutral "This conversation has ended", with no reason.
5. **First messages:** an optional joint "**Keep our first messages**" copies them into a read-only "How we met" card. Otherwise they are deleted on schedule (09 Q10).
6. **About us:** "Together since" offers the match date as a chip they can tap.
7. **Later:** 30 days after linking, "Delete your Dating profile and preferences?" (04 Impl 8).

### 4.8 Safety

#### 4.8.1 Age and identity

**Age assurance:**
- one flow for every country: liveness + facial age estimation (challenge age 25) + CompareFaces against every photo + an ID fallback + human review within 24 h (D11);
- **mandatory before enabling the UK**, with a method Ofcom recognises as highly effective;
- vendors must provide skin-tone and West African error data; NIST shows higher error for women (08 04-31);
- the fallback rate is measured by age band (Q3).

**Underage:**
- An `underage_risk` report puts the account into `age_review`, removes it from generation, and **closes its matches**.
- `age_verification_invalid` also closes matches (04 G14).
- A large gap between declared and estimated age puts the **whole account** under review (10 S2).

**Images:** CSAM hash-matching on every upload, with an escalation runbook to NCMEC, the IWF and Ghana's CSA (10 S16; 04 Impl 24). The shared service is built in S1 W7.

**Biometric consent:**
- Art. 9 explicit consent for EU and UK users.
- **BIPA written consent plus a public retention schedule before US Dating opens.**
- Texas CUBI needs consent, but not written (08 04-38).

#### 4.8.2 Country switches and same-gender rules

- **Effective tier, for notes and protections** = the highest of phone country, Dating country and session IP country (IP processed in the moment).
- **Same-gender availability** needs both the Dating country **and** the current IP country to have `same_gender_enabled`.
  - A traveller entering a disabled country has same-gender visibility auto-hidden and sees a one-time **in-app** note, **never a push**.
  - A phone-country tier that's higher than where the person lives triggers the note and the PIN and discreet-icon offers, not a block. Dual-SIM diaspora users keep their home SIMs (10 S4; 04 Impl 1). Q2.
- **At launch:** off in Ghana and every Tier 1 or Tier 2 country; on in the UK.
- **Tier lists:** 04 §2.1.6. Niger's ordinance number is unconfirmed (08 04-8).
- **Enforcement:** server-side, before transmission. No RPC, log or analytics event carries a gender/preference pair from a country where it's off (10 §3.1 rank 1).
- **Kill switches:** per country, for Dating and for same-gender matching. A change takes effect at the next generation run.
- **Watchlist:** Ghana's second consideration, Kenya's Family Protection Bill, Senegal, Türkiye (04 Impl 6).
- **If it is ever switched on in a Tier 1 country:**
  - name and photos withheld until mutual interest;
  - verified accounts at least 30 days old only;
  - a weekly cap for new accounts;
  - a dragnet throttle;
  - the LGBTQ+ block in the first-date guide (04 Impl 3; 10 S3).

#### 4.8.3 On the device

- **Neutral pushes everywhere.**
- **Quick exit wipes the Dating caches:** introductions, matches, photos, chat. Today it doesn't (04 G10; `quick_exit_service.dart:46-69`).
- `FLAG_SECURE` on Dating screens; no saves to the gallery.
- An optional Dating lock.
- A **discreet icon offered to everyone**, prompted in Tier 1/2. F8 was already deferred "to pre-Ghana launch" (04 Q11; memory: Spec 2 status).
- Later (P1): Travel mode, meaning hide me and keep no local Dating data.
- A duress PIN is P2, after legal review (10 S19).

#### 4.8.4 Reporting, appeals and the moderation runbook

| Tier | Categories | Automatic step (driven by a report, never by a phrase) | Human target |
|---|---|---|---|
| **P0** | Underage risk, CSAM, credible threat to life, child safety | Interim hold **with corroboration** (two independent reporters, or a matching tier-3 `age_signal` trigger; a CSAM hash hit holds at once); hidden from introductions; the reporter's match closes | 4 h or less in staffed hours; 24 h at most |
| **P1** | Sextortion; a romance scam with a money request; threats; a suspected set-up or entrapment profile | Removed from new generation | 24 h or less |
| **P2** | Harassment, explicit content, impersonation, **hiding a relationship** | The reporter is auto-blocked | 48 h or less |
| **P3** | Spam, other | — | 72 h or less |

**Rules:**
- **Never an automatic ban from one report or one phrase.**
- **The restricted person sees the category and gets one human appeal**, reviewed by someone else (or by the owner after 24 h when working solo). Who reported, and what they wrote, is never revealed. This amends `DATING_MODE_SPEC` §8 and chat spec §5.1 (02 Impl 4; 10 S11; DSA Art. 17, verified 08 07-33).
- Reports from someone whose own messages to the reported person tripped `sexual_pressure` or `financial_request` count for less.
- **Reports about someone's gender identity never trigger action.**
- Nationality, network or name is **never** a risk signal (02 Impl 5).

**Tools and people:**
- **Console:** photos and verifications needing review, reports, restrictions, appeals, and the Opinions queue.
- **People:** the owner as safety owner, plus one contracted moderator who reads Twi, Ga and Pidgin, with named out-of-hours P0 cover. Size the pilot to that capacity (10 Q12).
- **Escalation:**
  - imminent threat → police in the user's country (always a human decision);
  - CSAM → NCMEC / IWF / CSA;
  - sextortion → CSA 292, with the victim's consent.
- **Publish:** a law-enforcement request policy (valid legal process only; Attune can hand over only what it keeps) and a quarterly transparency summary (04 Impl 30, Q12).

#### 4.8.5 Leaving

| Action | Effect |
|---|---|
| **Pause** | Hidden silently and at once; reversible |
| **Exit** | **Hard-deletes** the profile, preferences, gender, faith, photos and messages. After the evidence window, introductions and matches become records with no pair attached. Only the consent-event minimum counsel requires is kept (10 F-6, Q10). |
| **Account deletion** | Cascades, except enforcement records, HMAC blocks and anonymised reports (§3.3) |
| **Export** | Includes **your own** Dating data (profile, preferences, consents), never another person's. The contract test at `data_export_contracts.sql:229-233` changes (06 Q13; Q17). |

### 4.9 Existing dating code: keep, change, replace or remove (06 §2.4)

| Keep | Change | Replace | Remove |
|---|---|---|---|
| • Flags (kill switches)<br>• Enrollment state machine and consent events<br>• Symmetric hard filters<br>• Double-blind introductions and atomic match<br>• Former-partner HMAC exclusion (**provision the Vault key**)<br>• Photo pipeline (private bucket, EXIF strip, Vision)<br>• Rekognition CompareFaces<br>• Guided first date, private reflections<br>• Block, unmatch and report RPCs<br>• `dating_mutual_match` routing | • Age gate source → assurance results<br>• Age bounds 18–70 → 18–99<br>• Introduction payload: add age and photos<br>• Matches screen: add the chat entry<br>• Dashboard and manual copy (today they promise a Healing gate)<br>• Report categories<br>• `get_my_dating_matches`: include 30 days of history for reports<br>• Reasons that close a match: add `age_verification_invalid`<br>• Exit and delete semantics<br>• Report and restriction foreign keys → `SET NULL` + HMAC<br>• Mutual-match push text → neutral<br>• Spec §6.4 weekly → daily | • Healing gate → ended-in-Attune window<br>• Ghana 6-city list → country + region<br>• Free-text intention → enum<br>• Weekly cohort → daily per country<br>• Trait-distance scoring → stated-values overlaps<br>• Static 3-country resources → F10<br>• ASCII-only normaliser → Unicode | • "I confirm I am 18" checkbox<br>• Historical-data consent checkbox<br>• `users.mode = 'dating'` writes<br>• Required non-empty preference arrays (store explicit sets instead) |

---

## 5. Opinions after Forums

### 5.1 Keep, soften, add, remove (07 §3 table; owner Qs 9–10)

| Feature | Verdict | Change | Evidence |
|---|---|---|---|
| Text only, 5,000 characters; polls with results hidden until you vote; saves; 15-minute edit; delete any time; hide; mute | **Keep** | Mute resolves the author on the server from the post id | 07 §3 |
| HMAC handle, `user_id` never exposed | **Keep the plumbing, change the scope** | **A handle per post and per comment** (`HMAC(user_id ‖ content_id)`). Amend decision 21 ("daily-rotating") to "unlinkable per post". | 07 Impl 1; 10 S12; 06 §2.6 |
| Author profile, follower count, follow author | **Remove** | The Following feed becomes "Topics I follow" | 07 Impl 1; SOUL §9 |
| Public like count | **Soften** | Supportive reactions ("I relate", "Sending strength", "This helped"); the **author alone** sees a gentle total; never used in ranking | 07 Impl 3; Muchnik 2013 |
| Dislike (posts and comments), comment likes | **Remove** | Hide covers "not for me" | Cheng 2014 (Strong, verified 08 07-2) |
| Reposts, quotes, engagement screen, live public counts | **Remove** | Stop broadcasting counts; leave the shared `count_broadcast_channel` code in place | 07 Impl 5 |
| Discover ranking `(likes − dislikes) + comments×2` | **Change** | Recency + a boost for **posts with no reply yet** + tag diversity | 07 Impl 4; Brady 2017 |
| Comments | **Keep, gentle** | Norms shown above the box; a non-blocking reconsider prompt on harsh words; author controls: comments off / "Just listening, no advice" / remove a comment | 07 Impl 6; Katsaros 2022; Matias 2019 |
| Compose | **Add** | • Self-focused placeholder: "What happened, and how did it feel for you?"<br>• **An audience reminder**: "Your partner or people you know may read Opinions."<br>• "Keep this private (save to my journal)".<br>• Drafts that persist.<br>• "Post later" as an option, **not a default nudge**: 08 07-26 found the delay was "beneficial and annoying", and the audience reminder is what worked.<br>• Honest privacy copy. | 07 Impl 9–11; 08 07-26 |
| Push previews of comment text; "2h ago" timestamps | **Change** | "Someone replied to your post"; "today" or "this week" | 07 Impl 12 |
| Tags | **Keep, extend** | Tag mute; add family and in-laws, money, faith (cultural reviewer) | 07 Impl 16 |
| "Attune asks" weekly prompt | **Add** | Clinician-reviewed and self-focused. Measured as a quality choice: the Panoply evidence is Weak–Moderate (08 A7). | 07 §2.9; 08 A7 |
| Forums tab, topics, sides, voted topics, insight counters | **Remove** | Polls are the successor to debates | 07 §2.9; Spec 3 |

### 5.2 The content filter

- **Deterministic, before posting:** on posts, comments, poll options and edits.
- **Blocks:**
  - contact details: +233/0XX XXX XXXX, +234/080…, emails, URLs, @handles, numbers written as words;
  - a reviewed slur list including Twi, Ga, Ewe, Hausa and Pidgin terms;
  - explicit sexual terms.
- **Explains itself:** each block gives a specific reason, which reduces future removals (Jhaver 2019).
- **Shares the Unicode normaliser** with the dating chat.
- **Why:** required by Apple 1.2, promised in FORUM.md and the Master Spec, and absent in the code (07 §2.1 #1).

### 5.3 Crisis routing (author-only; never an LLM; never blocks posting)

| Piece | When | Evidence |
|---|---|---|
| **"Need support now?"** link in compose and on every post menu, available whatever anyone types; routed by country (F10) | **Launch minimum** | 07 Q5; 10 S13 |
| A **"Someone may be at risk"** report reason that goes to the **human** priority queue. Never an automatic message to the author (Reddit-style weaponisation). | Launch minimum | 07 Impl 8 |
| **Journal:** `self_disclosure` runs on save **before any Gemini call**. On a match, the provider is skipped and the writer sees a private card that offers support "in case" and never asserts anything. **Until this is wired, pause the journal analysis call.** | **Launch minimum** | 10 F-7, Q14; CR-06 F11; 09 P9 fix 4 |
| An author-only Opinions detector that shows a private card after posting | After its own clinical spec (SAFETY §1.4) | 07 Impl 8 |

### 5.4 Moderation and labels

**Moderation:**
- Auto-hide at **3 distinct reporters**, or **2** for "Identifies a real person" or "Someone may be at risk".
- A removal notice that names the rule, plus **one human appeal**.
- A published contact email.
- "We review reports as quickly as we can" until there's a staffed SLA.
- Keep the ban ladder (3 confirmed → 7 days). Add escalation and carry-over by phone HMAC (07 Impl 13; §3.3).

**Status label:**
- Relationship path → "In a relationship"; Dating → "Single"; Just for me → the person chooses (In a relationship / Single / Not saying).
- A per-post "Don't show my status". "Open" is retired.
- Stamped on the server at posting time from a private setting, **never read from public `profiles`** (07 Impl 15; 06 Q7).

**Separation rules:**
- Never link an Opinions post to a Dating profile.
- Never show a couple-level signal ("your partner posted").

**Ghana:** a country-aware compose note in Tier 1/2. The Ghana legal opinion also covers Attune's exposure as host, including defamation (07 Q8).

---

## 6. Forum removal

**Order (06 §2.5.7):**

1. **Client release (S3 W1).**
   - **First**, route the `forum_topic_activated`, `forum_activity` and `forum_quiet` notification taps to home (`notification_config.dart:163-172`). Otherwise a stale push throws once the routes are gone.
   - Then remove:
     - the Forums tab and the outer tab bar and `IndexedStack` in `opinions_tab.dart`;
     - the topic option in `create_content_chooser.dart` and `create_content_fab.dart`;
     - the Forums tab in `tag_browse_screen.dart`;
     - the debate, side-selection and insight routes;
     - `ForumDocs`; the manual guard needs 33 or more topics and 34 remain;
     - forum copy: the onboarding line, the l10n `mutedItemSubtitle` and the tag search hint.
   - Delete `lib/features/forums/**` (18 files), `forum_home.dart` and the forum cache test.
   - Edit `widget_test.dart` and the routing test.
2. **Stop the producers, the same week (S3 W2).**
   - Unschedule `activate-topics-sweep` and `forum-quiet-check`, **and the untracked `mark-quiet-forums` (jobid 3), by name**.
   - Undeploy both edge functions and delete the 3 operator scripts.
   - Revoke EXECUTE on the forum RPCs, including the anon grants from `20260821120000`.
   - Mark queued forum notifications `cancelled`.
   - Add a health check that no forum cron is scheduled.
3. **Drop, after one release in the field (S3 W3).**
   - Views, then about 30 forum-only functions, then the 8 tables.
   - Then `post_polls.topic_id` and its CHECK.
   - Then the `topic` branch of `assert_can_post` and the `forum_post` branch of `admin_confirm_content_removal`.
   - Optionally rename `forum_reports` → `content_reports` and `enqueue_forum_notification` → `enqueue_community_notification`, with every caller in the same migration.
   - Update `security_lockdown_contracts.sql:17`.

**Must stay** (they serve Opinions or Games; 06 §2.5.6):

| Object | Why |
|---|---|
| `forum_reports` | Every opinion and comment report goes here |
| `admin_confirm_content_removal`, `profiles.banned_until` | Opinions removals and bans |
| `private.assert_can_post` | Opinions rate limits (only the topic branch goes) |
| `private.enqueue_forum_notification`; the `forum_content_removed` and `forum_posting_banned` types | Every Opinions notification and moderation notice |
| `post_polls`, `poll_options`, `poll_votes`, `PollCard`, poll repo and providers | Polls on opinions |
| `tags`, `opinion_tags`, `tag_follows`, `TagChipRow`, `TagPicker` | Opinion tags |
| `FeedCacheStore`, shimmers, `relationship_status_display.dart`, `count_broadcast_channel.dart` | Shared with Opinions or chat |
| `ThemeColors.against` | Used by the couple map painter |
| The forum-only parameters on `UniversalBubble` and `ChatTextField` | Shared with chat and **Games** (`game_message_bubble.dart`); don't "clean" them |
| `process-scheduled-notifications` payload allowlist | Until the forum notification rows are gone |
| `FORUM.md` | §4 documents Opinions; mark §5 retired |

---

## 7. Must-have before launch

"Before launch" means before any real user, and for Dating items before the pilot. Type: **C** = code, **P** = policy, **H** = human.

### 7.1 Build items

| # | Item | Type | Evidence | Where |
|---|---|---|---|---|
| 1 | `users.phone` not client-writable; HMACs from `auth.users`; pending invite key scoped per user | C | 10 F-1, S6, S17; 06 R4 | S1 W1 |
| 2 | DOB before the phone, checked on the device, written once on the server; an age check in `accept-invite`, which runs after the DOB | C | 06 Impl 1; 10 S16; 05 §5.1 | S1 W2, W4 |
| 3 | Sign-in never reveals whether an account exists before the code is verified | C | 10 F-10 | S1 W2 |
| 4 | Voice OTP fallback and WhatsApp-number check through the Send SMS Hook; toll-fraud rate limits and destination allow-lists | C + H (provider) | 05 Impl 8–9; 02 Impl 9; 09 rank 1 | S1 W2 |
| 5 | Dating never shown on the Relationship path or in the ending window; one neutral "More ways" row; confirmation before Dating pauses | C | 09 P4, P15, P19, P14 | S1 W3 |
| 6 | Push permission asked only in context | C | 05 Impl 15 | S1 W3 |
| 7 | Labelled single code field; semantics tests; text-scale opt-in on new screens; root clamp raised after the audit | C | 09 rank 5; CR-06 F16 | S1 W2, W10 |
| 8 | Dormancy rule with no DOB-only unlock; support never confirms an account | C + P | 10 S7, S5 | S1 W6 |
| 9 | Play Restrict Minor Access + 18+ ratings; Apple Declared Age Range and Play Age Signals before the US listing | C + H (console) | 08 A2, A3 | S1 W6 |
| 10 | CSAE standards page, named child-safety contact, "Report a concern about a child" | P + H | 04 §2.2.2 (Google Play, M) | S1 W6 |
| 11 | CSAM hash-matching on every upload pipeline (couples media, stories, avatars, Dating photos) + escalation runbook | C + H (vendor) | 10 S16; 04 Impl 24 | S1 W7 |
| 12 | Support resources v2: routed by country, emergency number first, CSA 292, sextortion, StopNCII, help that isn't the police, `verified_at` blocks release | C + H | 04 G9; CR-06 F10; 10 S8 | S1 W7 |
| 13 | Opinions: per-post handles, no guest author histories, neutral push previews | C | 10 S12; 07 Impl 1, 12 | S1 W8 |
| 14 | Opinions pre-post filter; removal notice with rule and appeal; contact email; thresholds 3/2 | C + P | Apple 1.2; 07 Impl 7, 13 | S1 W9 |
| 15 | "Need support now?" + an at-risk report reason; journal `self_disclosure` before Gemini (or analysis paused) | C + H (clinician) | 10 F-7, S13; 07 Q5 | S1 W9 |
| 16 | Same-gender off in Tier 1/2, server-enforced, nothing stored; country table and kill switches | C + P + H (legal) | 10 rank 1 | S2 W1, W3 |
| 17 | Enforcement records, HMAC blocks and anonymised reports survive deletion; generation refuses without the key; exit hard-deletes | C + H (counsel) | 10 rank 2, rank 11 | S2 W1 |
| 18 | Activation fixed: preference writers, explicit "everyone" set | C | 06 Impl 6 | S2 W1 |
| 19 | Encryption in the application for gender, preferences and faith; admin views exclude them; RLS canary in CI; bucket test; secret scanning; no analytics SDK | C | 04 Impl 13, 17; 10 S20 | S2 W1 |
| 20 | Healing gate replaced by the ended-in-Attune window | C + H (clinician) | 06 Impl 7; 04 C1 | S2 W2 |
| 21 | Liveness + age estimate + CompareFaces + ID and human fallbacks; underage holds close matches; Dating re-verification on a new device | C + H (vendor) | 10 rank 3, rank 9 | S2 W4, W7 |
| 22 | Trust friction: 72 h cool-off, 3/day cap, same country by default, cross-border opt-in after 14 days, both verified | C | 10 rank 8; 09 Q17 | S2 W5 |
| 23 | "Never introduce me to these numbers" | C + H (DV copy) | 10 rank 6 | S2 W5 |
| 24 | Dating chat to spec: masking until mutual Swap, Ghana/diaspora lexicon, Unicode normaliser, sextortion card, RLS blocks | C + H | 10 rank 7 | S2 W6 |
| 25 | Reporting: 30 days of history, evidence snapshot, new categories, corroborated P0 holds, category + appeal, console, runbook | C + P + H | 10 rank 4 | S2 W7 |
| 26 | Device discretion: neutral pushes, quick exit wipes Dating caches, `FLAG_SECURE`, no gallery saves, PIN prompt, discreet icon | C | 10 rank 5; 04 G10 | S2 W8 |
| 27 | One-person rules: attestation, terms, children never a filter to seek | P | 10 rank 16 | S2 W3, W7 |

### 7.2 Human, legal and clinical gates (start now; they are the critical path)

| Gate | Who | Blocks | Evidence |
|---|---|---|---|
| **Ghana legal opinion on the *reconsidered* bill text.** Covers: same-gender matching, the platform-owner clause, owner/staff/moderator exposure, Opinions hosting, defamation, and imagery on the store listing. | Ghanaian counsel | The Ghana listing; S2 W3 and W10 | 08 A1; 04 Q1; 07 Q8; 05 Q12 |
| **Ghana DPC registration** | Owner | Any Ghanaian user | 04 Impl 16 |
| **UK Online Safety Act** illegal-harms and children's-access assessments (the whole app is user-to-user: Opinions, chat); **highly effective age assurance** for Dating; a UK representative | UK counsel | The UK listing; UK Dating | 04 §2.2.1 (08 04-13 verified) |
| **DPIA** (Art. 35: orientation, faith, biometrics) and the Art. 9 consent wording | Privacy counsel | Any Dating switch-on | 04 Impl 13 |
| **US:** BIPA consent and a retention schedule; app-store age laws; NCMEC reporting duty | US counsel | US Dating; the US listing (age signals) | 04 Impl 15; 08 A2 |
| Retention of enforcement records (2 years) and what survives deletion; export scope | Counsel (Ghana, UK/EU) | S2 W1 and W9 switch-on | 10 Q4; 06 Q13 |
| Law-enforcement request policy; transparency summary | Counsel | S2 W10 | 04 Q12 |
| **Named safety owner, a moderator who reads Twi, Ga and Pidgin, out-of-hours P0 cover** | Owner | S1 W9 (Opinions queue); S2 W7 and W10 | 10 Q12; 07 Q7 |
| **Clinician:** gentle-wait copy and length; `self_disclosure` corpus and crisis cards; "Attune asks" prompts; the Opinions detector spec | Couples clinician + suicide-prevention reviewer | S1 W9; S2 W2 | CR-06 F11; 04 Q10 |
| **DV specialist:** "never introduce me" copy, the sextortion card, "Get help", the dormancy screen | DV specialist | S2 W5–W6; S1 W6 | 10 §3.4 |
| **LGBTQ+ safety reviewer** (West African context): country notes, off-country copy, LGBTQ+ resources | Reviewer | S2 W3 | 02 Q10; 10 S3 |
| **Ghanaian cultural reviewer** (+ faith advisers): stage helper text, intentions, faith lists, married/polygamy wording, scam lexicon (Twi/Ga/Ewe/Pidgin), school-age cues, slur list, new tags | Reviewers | S1 W5 and W9; S2 W3 and W6 | 05 §3.4; 10 S1, S2, S9 |
| **Age-check vendor** (liveness + estimation, West African error data, recognised for the UK) and **ID vendor** (Ghana Card) | Owner | S2 W4 | 04 Q2 (vendor claims unverified, 08 04-32) |
| CSAM hash-matching vendor eligibility (PhotoDNA, Google CSAI or Thorn Safer) | Owner | S1 W7 | 08 04-47 (unverified) |
| `DATING_CHAT_SAFETY_SPEC.md` §12 sign-off | Safety owner | S2 W6 | 06 Q18 |
| Spec amendments approved (Q20) | Owner | Writing the specs | 06 Impl 16 |
| Real-carrier OTP tests (MTN, Telecel, AirtelTigo; UK, US and Canadian carriers) | Owner + devices | S1 W2 switch-on | 02 Impl 9; 05 Q2 |
| Accessibility and device matrix (TalkBack, VoiceOver, 200%, Android Go, 3 OEMs) | Owner | S1 W10; S2 W10 | 09 rank 5 |
| External penetration test | Vendor | S2 W10 | 04 Impl 17 |
| Exclusion Vault key provisioned | Owner (ops) | S2 W5 | 06 §2.4 |
| Close the 6 decision-relevant unverified rows: Ghana final text, Pew harassment by gender, "unmatch erases chat", Noonlight, CSAM vendor terms, Apple in-app purchase in Ghana | Researcher | Before the specs are finalised | 08 D Q3 |

---

## 8. What NOT to build

| Don't build | Why | Evidence |
|---|---|---|
| Swipe decks, infinite feeds, browsing or searching the pool | Rejection mind-set; compulsive use is the strongest harm signal | 03 (d); Pronk & Denissen 2020; Cela & Wood 2026 (g = .44) |
| "Likes you" queues, admirer counts, profile-view lists | A desirability hierarchy; undermines double opt-in | 03 (d); Bruch & Newman 2018 |
| Paywalls on replying, seeing a match, being introduced, being seen, or on safety; paid boosts; fees per introduction | The #1 pain (14% of low reviews); a curated app's billing failures | 02 P1, §2.4, Impl 1–2 |
| Compatibility percentages; trait-distance; attachment or personality matching; love languages | No pair-predictive validity | 03 §2.1; Joel 2017; Dyrenforth 2010 |
| Ranking on popularity, activity or attractiveness; features derived from photos; camera-roll scans | Hierarchy, not fit; body-image harm | 03 (a); 01 Impl 15 |
| Read receipts, typing indicators, "online now", last active in the dating chat | Ghosting anxiety; monitoring | 03 (d); CR-06 §9 |
| Streaks, match counters, "It's a match!" bursts | Compulsivity; sliding rather than deciding | 03 (d); motion spec §1.1 |
| "Someone liked you" pushes; telling someone they were declined; urgency timers | Compulsive checking; rejection sensitivity | 03 (d) |
| Nudging people onto WhatsApp; masking that lifts by itself | Moving across platforms raises risk; scammers wait | AIC TI 704; 10 F-11 |
| Children's photos, names or ages; "has children" as a filter to seek on | Child-exploitation requests (12.4%) | 03 §2.9; 10 S22 |
| Any public sign of who someone wants to meet, or of being on Dating | Entrapment; outing | 04 §2.1; 03 Impl 18 |
| Same-gender introductions in Tier 1/2 at launch; Grindr-style risk-alert *pushes* | Enumeration; duty to report; the push itself is evidence | 10 S3, S4 |
| A mandatory wait for everyone; readiness scores | No evidence; encourages evasion | 03 §2.8; 09 P15 |
| LLM safety detection; AI-written messages; AI conversational onboarding | Permanent constraint; inauthentic responsiveness | 01 Impl 15; constraint 6 |
| Ethnicity, tribe, caste, income, politics, HIV, body type, zodiac | Special category or a fraud lure | 01 Impl 11 |
| GPS, distance, neighbourhood-level location | Trilateration | 04 §2.1.5 |
| Stored face templates (v1) | Biometric breach and legal liability | 04 Q8 |
| In-app video; media in the dating chat (v1) | Moderation burden; the cyberflashing duty | 04 Q5 |
| Guardian or wali accounts; casual or non-monogamy intentions (v1) | Thin pool; cultural review first | 03 Q4, Q7; 01 Q1 |
| Invite gates; numbered waitlists | Resented across League, Raya and Known | 02 Impl 13 |
| Auto-ban from one report or one phrase; nationality or name as a risk signal | The West African "banned for saying no" pattern | 02 P4, Impl 5 |
| Any "is my partner on Dating?" lookup; any partner signal; a "no account found" answer before the code | Surveillance; enumeration | 10 S5, S18, F-10 |
| A duress PIN (v1) | Could be read as obstruction; legal review first | 10 S19 |
| Opinions: dislikes, reposts, quotes, author pages, follower counts, engagement ranking, sides, voted topics, insight counters, trigger-warning labels, auto "get them help" messages | Judgment and comparison mechanics; outing risk | 07 §3; Cheng 2014; 08 07-24 |
| A 26-question quiz before Home; fake "building your plan…" waits; a push prompt at sign-in; a contacts permission | Delays value; manipulation; burns the one permission ask | 05 Impl 15–18, §3.7 |
| A couple type or score of any kind | Permanent rule | BRIEF; CR-06 §9 |

---

## 9. Metrics

**Rules** (05 Impl 22; CR-06 §4.0):
- server-side aggregates in daily buckets;
- no user or device IDs, no answers, no gender, preference, faith or age-signal values;
- shown only at n ≥ 50;
- no session replay, attribution or analytics SDK;
- accessibility is covered by the test matrix, never measured per user.

| Area | Metric | Target or use |
|---|---|---|
| Sign-in | Code requested → verified, by carrier, channel and country; use of voice fallback; median seconds to code | Per-carrier success as a launch gate |
| Sign-in | Get started → A6, median | 90 s or less |
| Sign-in | Under-18 stops (count only) | — |
| Path | Path chosen; **switched within 7 and 30 days**, by from→to pair | A wrong-first-choice signal |
| Invite | Sent → accepted within 24 h and 7 days; code typed vs link opened; duplicate invites created by invitees; expired-code hits | — |
| Couples | Partner not joined at day 7 and day 30; "Send a new invite" use; "on my own" retention at day 30 | — |
| Permissions | Grant rate by *context* | — |
| Dating funnel | Completion of each D step; A6 → D11 pass; **A5 → first introduction** | 72 h or less |
| Verification | First-try pass; fallback rate by age band and device RAM class; time to decision | Under 24 h |
| Pool | "No good fit today" by city per week; introductions per active person; "not in your area" by country | Picks the next country |
| Outcomes | Mutual interest per introduction; "we met" conversion; median time to meet; share of chats ended with Close kindly; Dating → Relationship links | Meet within 7–21 days (03 (e)) |
| Wellbeing (opt-in panel) | Better / same / worse each month; perceived responsiveness after the first conversation and first date | Must not worsen |
| Safety | Reports and blocks per 1,000 matches; money-card and masking events; dragnet flags; P0 time to human review; interim holds; **overturned enforcement by country**; repeat-offender rate | P0 human review in 4 h or less |
| Gentle wait | Share who start on the earliest date; account deletions within 7 days of D0 | An evasion proxy |
| Opinions | % of posts with a supportive reply or reaction within 24 h; reports per 100 posts; removals and overturned appeals; self-deletes within 24 h; journal saves vs posts; crisis-resource displays (count only) | Supportive reply rate rising |
| Harm | Uninstall within 72 h; quick-exit activations (count only) | — |
| **Anti-metrics** (watched, never optimised) | Sessions a day, time in the app, introductions viewed | — |

---

## 10. Consolidated owner questions

Merged and de-duplicated from 01 Q1–12, 02 Q1–11, 03 Q1–11, 04 Q1–12, 05 Q1–14, 06 Q1–19, 07 Q1–12, 08 D1–3, 09 Q1–17 and 10 Q1–15. They are ordered by how much they block the specs. Smaller items those files raised are decided in §2–§5 and need no answer unless the owner disagrees.

| # | Question | Recommendation | Cost if accepted | Cost of the alternative | Blocks |
|---|---|---|---|---|---|
| **Q1** | Where does the app launch, and where does Dating open? | The app in **Ghana, UK, US and Canada**; Dating in **Ghana (men–women; pilot in Greater Accra and Ashanti first) and the UK** (after HEAA); US Dating next. Availability stated on the store page and in Welcome (T1). | Diaspora outside these four countries waits; legal work in 4 regimes | **Worldwide on day one:** dozens of regimes at once (India 2 h, Australia's code, EU representative, US states), or quiet non-compliance | Everything (legal, store, S1 W6, S2 W10) |
| **Q2** | Same-gender introductions in Ghana and Tier 1/2 at launch? | **Off**, server-enforced, nothing stored, honest copy and resources. In off countries own gender is Woman/Man only (no write-in kept). Same-gender availability keys on the Dating country plus where the person is right now. | LGBTQ+ Ghanaians underserved and may use riskier apps; non-binary users there can't use Dating | **On with protections (04 Q1):** a target list under a duty-to-report law; possible platform-owner liability; all Tier 1 protections must be built first | S2 W1, W3; Ghana legal brief |
| **Q3** | Age check for Dating, and which vendor? | **Liveness + facial age estimation (challenge age 25) + CompareFaces + an ID fallback (Ghana Card) + human review within 24 h, for every Dating user.** Shortlist a UK-recognised estimation vendor plus Smile ID for the ID route; decide on their West African error data. | A fee per check; most 18–24-year-olds go to the ID fallback; a contract lead time | **DOB only:** the UK is impossible (Ofcom), minors get in (10 S2), Play requires more (08 A3) | S2 W4; DPIA |
| **Q4** | DOB before the phone number (05) or after the code (06)? | **Before**, held on the device and written after the code. | One screen before the phone | **After:** minors hand over phone numbers; an invitee could be linked before their age is known | S1 W2 |
| **Q5** | Lock identity and keep enforcement after deletion? | **Yes:** `users.phone` not client-writable; HMACs from `auth.users`; enforcement records, HMAC blocks and anonymised reports kept for **2 years** after deletion, named in the privacy policy. | Counsel sign-off; a privacy-policy line; a little data kept after deletion | **No:** deleting an account becomes ban evasion and evidence destruction (10 F-2); a re-registered ex escapes the exclusion (10 S6) | S1 W1; S2 W1 |
| **Q6** | Navigation and labels? | Keep the **two-tab shell**. Tab 2 = **Chat** (Relationship) or **Me** (Dating and Just for me; Dating is a section inside Me, with an optional Dating lock). Just for me lands on Me; guests land on Opinions behind a birth-year gate. | Dating is a little less prominent | **A "Dating" tab:** visible on checked or shared phones in a Tier 1 launch country (10 S5, S17) | S1 W3 |
| **Q7** | Path rules for couples? | "On my own for now" **stays Relationship** (never shows Dating); "Send a new invite" replaces "Invite someone else"; withdrawing an invite returns to the previous path; confirm before an invite pauses Dating. Solo "Working on us, on my own" content as a follow-up. | The solo content is new work, outside these specs | **Today's behaviour:** a married woman whose husband ignored the invite is shown a Dating button (09 P4) | S1 W3, W4 |
| **Q8** | Couple-profile details? | The owner's four fields, plus customary-marriage helper text (cultural review), up to **2 ceremony years**, optional child age bands, one anniversary source, and **"Changed by Yaw · 12 Nov"** (no push, no feed). Amends CR-06 §5.3 rule 6. | A small amendment; the cultural review of the wording | **Silent edits:** "who changed it?" spats (09 P1). **One marriage year:** fails Ghana's two-ceremony reality (09 P2) | S1 W5 |
| **Q9** | Redesign Opinions' anonymity and feedback? | **Yes:** per-post handles; remove author pages, follows, dislikes, reposts and quotes; supportive reactions with totals only the author sees; Discover re-ranked. Amend decision 21. | Lose "followable voices"; drop the repost and quote tables later | **Keep as is:** a partner can read the author's whole history from one post, and so can guests (10 S12) | S1 W8 |
| **Q10** | The Opinions and journal safety minimum? | **Before launch:** the pre-post filter, "Need support now?", an at-risk report reason, thresholds 3/2, a notice with an appeal, a named daily review slot. **The journal's Gemini analysis is paused until `self_disclosure` runs first.** The Opinions detector follows its own clinical spec. | Clinician and cultural-review lead time; journal insights paused for a while | **Launch without:** an Apple 1.2 rejection; a suicidal journal entry gets an AI "insight" (10 F-7) | S1 W9 |
| **Q11** | Raise the text-scale clamp (1.0 → 2.0)? | **Yes, in stages:** an opt-in wrapper on new screens now, then an audit and golden tests of existing surfaces, then raising the root clamp. | Every screen reflows; a layout-fix pass | **Keep 1.0:** 50+ and low-vision users are shut out (09 P2, P7); fails CR-06 F16 | S1 W2, W10 |
| **Q12** | How long is the gentle wait? | **The 30-day ending window** (shorter if both seal), plus a 3-question private reflection and Healing offered. No score. | A clinical note under spec §2.1 | **8 weeks (today):** people re-register on another SIM and escape the exclusion (09 P15). **No wait:** contradicts the owner's decision | S2 W2 |
| **Q13** | Dating profile set? | **Intentions:** Marriage · A committed relationship · Companionship, at my own pace · Not sure yet (no casual).<br>**Married people:** anyone currently married in any form (including customary or polygynous) or separated but not divorced is excluded, with an attestation and a "hiding a relationship" report.<br>**Faith:** optional, region-aware, "must share" as a dealbreaker.<br>**Age range:** 18–99, with at most +7 years by default for ages 18–20.<br>**Photo hiding:** "photos after mutual interest" from account day 30. | Faith adds special-category scope to the DPIA; married polygynous users can't use Dating | **Six intentions:** fragments a thin pool (01 §3.5). **No faith field:** faith users leave (02 §2.3). **Silent marriage policy:** both kinds of complaint (02 Q5) | S2 W1, W3 |
| **Q14** | Cadence numbers? | At most 3 a day at a chosen time; at most 6 waiting; a pause at 3 open chats; a **7-day** lifetime with no countdown; a **72 h cool-off from account creation**; cross-border opt-in only for verified accounts 14+ days old. Pilot 2 vs 3 a day. | Slow starts in thin cities | **Weekly batch (today's spec):** contradicts "a few a day". **Shorter lifetime:** low-data users miss introductions (09 P11) | S2 W5 |
| **Q15** | Dating chat scope? | **Text only**; masking until **both** tap Swap (offered from 72 h); a 30-day evidence window; joint "keep our first messages"; **voice calls in a later wave.** Amend chat spec §4.1. | No early voice check that someone is real (02 Q7) | **72 h automatic unmasking:** scammers just wait (10 F-11). **Media now:** the cyberflashing duty plus a moderation load | S2 W6 |
| **Q16** | Enforcement transparency and holds? | **Show the category plus one human appeal; interim holds only for corroborated P0 reports;** no automatic bans. Amend `DATING_MODE_SPEC` §8 and chat spec §5.1. | Appeal workload; a second reviewer needed | **"Never reveal the cause":** the #1 West African pain (02 P4). **No holds:** a 3 a.m. P0 waits for morning | S2 W7 |
| **Q17** | Exit and export? | **Exit hard-deletes everything in Dating; the export includes your own Dating data.** | Counsel check; a contract-test change | **Exit as a flag (today):** orientation data stays (10 F-6); GDPR Art. 15 exposure | S2 W1, W9 |
| **Q18** | Apple/Google sign-in later? | A **phone stays required for Dating and couple invites**; new methods are only linked from a signed-in account; **passkeys first** (post-launch), then Apple + Google together (Apple 4.8). | Some friction for people who prefer social sign-in | **Phone optional:** the ex-exclusion and enforcement keys break; duplicate accounts (05 §3.2.3) | Design only now |
| **Q19** | Who does the human work? | **Name now:** the safety owner, a moderator who reads Twi, Ga and Pidgin, out-of-hours P0 cover, and the §7.2 reviewers (clinician, DV, LGBTQ+, cultural, faith, counsel). Size the pilot to moderator capacity. | Cost and lead time | **Building first:** nothing can switch on; report copy promises reviews nobody does (Fable L5) | All switch-ons |
| **Q20** | Approve the amendments? | Approve:<br>• `ATTUNE_SOUL.md:73` ("a forum");<br>• Master Spec decisions 11, 18, 20, 21, 22, 23 and 25, §2 (modes → paths), §8.8 Track A, §9;<br>• `AUTH_ONBOARDING_ENGINE.md` (order, voice OTP, no Ask 2 preview);<br>• `DATING_MODE_SPEC.md` §2, §2.1, §3.1, §4.1, §6.1, §6.4 and §8;<br>• `DATING_CHAT_SAFETY_SPEC.md` §4.1 and §5.1;<br>• `FORUM.md` §5 retired;<br>• CR-06 §5.3 rule 6. | Owner review time | **Specs and code drift again** (06 §2.1.7) | Final spec sign-off |

---

## 11. Proposed delivery

**Order:** **Spec 3 W1–W2** (forum removal; small, no human gates, and it clears the same Opinions files S1 W8 edits) → **Spec 1 W1–W10** → **Spec 2 W1–W10** → **Spec 3 W3** (the table drop, after one release on every test device) → **Spec 2 W11** (voice, after the pilot). The human gates in §7.2 start on day one, in parallel.

**Total:** 23 waves, plus one later.

**Not touched by any wave:**
- Games (folders, routes, `ChatScreen`'s game entry points, `UniversalBubble` parameters, the `auth_exports.dart` barrel);
- `profiles.display_name` and its public read;
- the `relationships` grants model;
- the `home_screen.dart` redirect latch;
- the existing Safety PIN and quick exit, which are extended, not rewritten.

Only new files are formatted, never existing ones (repo rule).

### Spec 1: the whole app flow, identity and data model, couple profile, Opinions changes · **10 waves**

| Wave | Contents (one line) | Depends on | Gate before switch-on |
|---|---|---|---|
| **W1** Identity foundation | `users` column grants + phone from `auth.users`; `users.path` + `set_my_path`; `users.mode` retired with all 8 writers; `account_birthdates` + RPCs; EULA v2 record; per-user invite key; `metric_counters`; health checks for missing DOB or path | — (runs after Spec 3 W1–W2 by order, not by need) | None. Regression: change the onboarding upsert in the same release (06 R6) |
| **W2** Sign-in v2 | Welcome + previews; guest birth-year gate; A1–A5; returning-user flow without enumeration; A1–A3 kept on the device; Send SMS Hook (Ghana-direct SMS, voice, WhatsApp, app hash, rate limits); single labelled code field; motion tokens; large-text wrapper | W1 | **[GATE] SMS/voice provider + real-carrier tests** |
| **W3** Paths and homes | A6; path-aware Home (latch untouched, keyed rebuild); Me home (J1–J5); Relationship home states; Dating entry stub and "not here yet"; Settings → How you use Attune (switch, undo, confirm); no Dating on the Relationship path or in the ending window; paused stays Relationship; contextual push asks (`onesignal_service.dart` regression pass); copy without "forums" | W2 | None |
| **W4** Couples flow | Invite messages carrying the code; "My partner already invited me"; invitee order with DOB before accept; `accept-invite` checks age and phone and withdraws the acceptor's own invite; generic pre-auth invite screen; expired-code screen; day-7 "Send a new invite"; "on my own" state; Android Install Referrer; Ask 2 saves as it goes | W3 | None. Regression: `main.dart` invite deep link (06 R3) |
| **W5** Couple profile | `couple_profile_drafts` → `couple_profiles` + RPC + change signal + "Changed by" line + export + no-type contract test; About-us AU1–AU6 UI; one anniversary source | W4 | **[GATE] Cultural review of the stage and helper wording** |
| **W6** Age, store compliance, recycled numbers | Dormancy rule + recovery hold; hardened under-18 block; Apple Declared Age Range / Play Age Signals; Play Restrict Minor Access + ratings; CSAE page + child-safety contact + "Report a concern about a child" | W2 | **[GATE] CSAE page published and contact named (owner)** |
| **W7** Resources v2 + image safety | F10 country-routed resource model (`verified_at` blocks release); CSAM hash-matching service on every upload pipeline + escalation runbook | W1 | **[GATE] Resource numbers verified per launch country; hash-vendor approval** |
| **W8** Opinions v2: anonymity and feedback | Per-post and per-comment handles; author pages, follows, dislikes, reposts, quotes and live counts removed; author-only reactions; Discover re-rank; private status label stamped on the server + per-post hide; coarse times; neutral pushes; audience reminder; honest privacy copy | W3; Spec 3 W1 | None |
| **W9** Opinions safety + crisis routing | Pre-post filter + Unicode normaliser; reconsider prompt; author controls; drafts / keep private / post later; report reasons + thresholds 3/2; notice + appeal + contact email; review queue v0; "Need support now?"; journal `self_disclosure` before Gemini (analysis paused until then); tag mute + new tags; country-aware compose note | W8, W7 | **[GATE] Cultural slur list and tags; clinician crisis copy; named daily reviewer** |
| **W10** Accessibility, low data, cleanup | Large-text audit + golden tests, then the root clamp raised to 2.0; first frame not waiting on the network; app-size budget and split ABIs; reduce-motion pass (900 → 320 ms or less); RTL check; dead auth/shell code removed in a separate commit; approved doc amendments applied | W1–W9 | **[GATE] Device matrix (TalkBack, VoiceOver, 200%, Android Go)** |

### Spec 2: Dating Mode · **10 waves (+1 later)**

| Wave | Contents (one line) | Depends on | Gate before switch-on |
|---|---|---|---|
| **W1** Dating data, identity, deletion | HMACs from `auth.users`; enforcement records, HMAC blocks, reports `SET NULL` + HMAC; generation refuses without the key; exit hard-deletes and delete anonymises; new profile columns + encryption in the application; preference writers + activation fix; `country_safety_config` + effective tier; never-introduce table; old checkboxes and `mode` writes removed; CI canaries (delete → re-register → tamper, RLS, bucket, secrets) | S1 W1 | **[GATE] Counsel on retention** |
| **W2** Eligibility and gentle wait | Healing predicates replaced in 3 places by the ended-in-Attune window; D0 reflection; cool-off from account creation; spec §2.1 amendment recorded | W1 | **[GATE] Clinical note on the length and copy** |
| **W3** Dating setup UI | D1–D13; per-country region lists and city sides; region-aware faith lists; off-country rendering (nothing sent); "anyone else use this phone?" + Dating lock; discreet-icon offer; "Not ready?"; not-here + notify-me; manual's Dating docs updated | W2; S1 W3 | **[GATE] Cultural review (intentions, faith, married wording); LGBTQ+ reviewer (notes); Ghana legal opinion confirms the Ghana switch state** |
| **W4** Verification and age assurance | Liveness + estimation (challenge age 25) + CompareFaces against every photo; ID and human fallbacks within 24 h; accessible, resumable capture; new-device re-verification; underage and `age_verification_invalid` close matches | W3 | **[GATE] Vendor contracts; DPIA; UK-recognised method before the UK** |
| **W5** Matching and introductions | Ranking on stated values (trait dimensions removed); daily per-country cohorts; caps 3/6/3; 7-day lifetime; honest empty days; "Why you two were introduced"; Interested / Not for me + accessible undo; counterpart photos by signed URL; age in the payload; never-introduce UI; cross-border rules; neutral daily digest; no on-device cache; data-saver cards | W4 | **[GATE] Exclusion Vault key provisioned** |
| **W6** Dating chat | `dating_messages` + outbox + its own screen; text only; masking until mutual Swap; Ghana/Nigeria/diaspora lexicon + Unicode normaliser + sextortion card; RLS blocks; guided first conversation; plan-a-meet / Share my plan / after-date check-in / Get help; Close kindly; 30-day retention | W5 | **[GATE] Chat spec §12 sign-off; DV copy; cultural lexicon fixtures** |
| **W7** Reporting, enforcement, moderation | Categories + 30-day history + evidence snapshot; P0–P3 SLAs; corroborated holds; restricted screen with category + appeal; credibility weighting; console (photos, verifications, reports, appeals, Opinions queue); escalation runbook; transparency summary; law-enforcement policy | W6; S1 W9 | **[GATE] Safety owner, moderator and out-of-hours cover named; counsel on the law-enforcement policy** |
| **W8** Device discretion and travel | Neutral pushes (replacing "New mutual match"); quick exit wipes Dating caches; `FLAG_SECURE`; no gallery saves; Dating lock; discreet icon for everyone; traveller detection + auto-hide + in-app note | W5 | None |
| **W9** Couple link + export | In-chat "Become a couple" with a private "what are we agreeing to"; both confirm; Dating pauses for both at confirmation; other chats close neutrally; keep first messages; path → Relationship; together-since chip; 30-day delete offer; export includes your own Dating data | W6; S1 W5 | **[GATE] Counsel on export scope** |
| **W10** Pilot readiness and switch-on | Per-country checklist; flags on for Ghana (Greater Accra + Ashanti, men–women) and the UK; aggregate dashboards; runbook drill; store listing "Dating open in…" | W1–W9 | **[GATE] Ghana legal opinion, DPC registration, UK OSA + HEAA, DPIA, pen test passed, moderator live** |
| *W11 (later)* Voice | In-app voice calls with mutual opt-in and a one-time safety card (check whether the Sendbird contract covers calls) | Pilot data on moderation capacity | **[GATE] Moderation capacity measured** |

### Spec 3: Forum removal · **3 waves**

| Wave | Contents (one line) | Depends on | Gate |
|---|---|---|---|
| **W1** Client removal | Notification taps routed to home **first**; Forums tab, chooser option, tag-browse tab, routes, `ForumDocs` and copy removed; 18 files + `forum_home.dart` + cache test deleted; tests edited; every §6 keep item untouched | — | None |
| **W2** Stop producers | 3 crons unscheduled by name (including the untracked `mark-quiet-forums`); 2 edge functions undeployed and 3 scripts deleted; EXECUTE revoked (including anon); queued forum notifications cancelled; "no forum cron" health check | W1 released | None |
| **W3** Drop | Views → ~30 functions → 8 tables → `post_polls.topic_id` + CHECK → forum branches of `assert_can_post` and `admin_confirm_content_removal` → optional renames → contract test updated | W2 + one release on every test device | None |

---

## 12. Owner rulings (2026-10-24, after reading this document)

These override the recommendations above wherever they differ.

| Q | Ruling |
|---|---|
| **Q1 Launch** | **The app is available worldwide from day one** (couples, Just for me, Opinions). **Dating opens in Ghana** (Greater Accra + Ashanti first, men–women) **and the UK**. Everywhere else shows "Dating isn't open in {country} yet" plus "Tell me when it's here". The non-dating parts must therefore meet worldwide age and store rules from day one: S1 W6 (Apple Declared Age Range / Play Age Signals, Restrict Minor Access, CSAE page) is a launch item, not country-gated. |
| **Q2 Same-gender** | Off in Ghana and every Tier 1/2 country (server-enforced, nothing stored; honest note and resources). **On in the UK** and other safe countries. Reconsidered after the Ghanaian legal opinion and the Tier 1 protections. |
| **Q13 Dating rules** | As recommended. Four intentions (Marriage / A committed relationship / Companionship, at my own pace / Not sure yet), no casual. Anyone currently married in any form, or separated and not divorced, is excluded, with an attestation and a "hiding a relationship" report. |
| **Q9 Opinions redesign** | **Keep Opinions as it is for now: OPEN FOR DEBATE.** Some people want to keep hearing from a specific anonymous voice, and reactions show which content to promote. Per-post handles, author-page removal, dislike/repost/quote removal and author-only reactions are **deferred, not decided**. S1 W8 is out of scope until the owner reopens it. |
| **Q10 Safety minimum** | **Add both:** (1) the pre-post content filter (contact info, slurs, explicit content; Apple 1.2), a "Need support now?" link and an "at risk" report reason; (2) the Journal's Gemini insight paused until the hard-coded `self_disclosure` crisis check runs first. These go in S1 W9 without the redesign items. |
| **Q6 Navigation** | Two tabs. Tab 2 = **Chat** on the Relationship path, and **Me** on Dating and Just for me. Dating is a section inside Me, with an optional Dating lock. |
| **Q3 Age check** | Liveness + facial age estimation (challenge age 25) + ID fallback (e.g. Ghana Card) + human review within 24 h. Vendors: a UK-recognised estimation vendor plus Smile ID (or equivalent). |
| **Q19 People / switch-on** | The owner lines up the safety owner, moderator, counsel (a lawyer is in mind) and reviewers **in parallel**. **Everything, Dating included, is built and switched ON in development for full testing**; there's no immediate launch. **Production** switch-on still waits for the §7.2 gates. |
| **Q4, Q5, Q7, Q8, Q11, Q12, Q14–Q18, Q20** | **Accepted as written.** |
| **Q18 Sign-in** | **Phone-number sign-in only** (the owner's preference). There's no Apple/Google/passkey work in these specs. Apple guideline 4.8 doesn't apply to phone-only sign-in. The design keeps the phone as the identity anchor and leaves a seam for linking other methods later. If they're ever needed, the owner has a working Apple + Google sign-in in another project to clone and adapt. |
| **Spec order** | Write all three specs back to back (Spec 1, then Spec 2, then Spec 3). The owner reviews all three. Build order as in §11: Spec 3 W1–W2 → Spec 1 → Spec 2 → Spec 3 W3 → voice later. |
| **Q19b Test project** (2026-10-24, after cross-spec review R-6) | **The current Supabase project (`mrgjtyacrzfylawyzabm`) is the development/testing project until launch.** It has no real users, so everything is switched on there, Dating included. Before launch, the owner flips it to production mode (or creates a separate production project). Production mode is when the production gates are enforced, through the launch checklist and the server-side environment setting. |

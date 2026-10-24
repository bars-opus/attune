# 01 — Dating and matchmaking products: what they collect, how onboarding goes, how the data is used

Researcher 01 · 2026-10-24 · Brief: `BRIEF.md` (this folder)

Source IDs in square brackets, such as [S12], point to the numbered source list at the end, where each source has a URL and an evidence grade. `[UNVERIFIED]` marks prior knowledge that could not be re-checked in this run (see §1.3). Treat those items as leads, not findings.

---

## 0. Top findings

1. **Intention is the one structured field every serious product converged on.** Each uses it as a filter and shows it on the profile: Hinge (6 options plus a separate relationship-type field), Tinder (6 options), Bumble (up to 2 shown) and Muzz (marriage plus when you plan to involve family). In Tinder's test, more than 50% of users chose to display a goal [S11]. No outcome evidence shows that matching on intention leads to better relationships. Attune's `relationship_intention` is free text of 1–80 characters, yet it feeds an exact-match hard filter (§4.1).
2. **Curated products deliver 1–10 introductions a day, and heavy onboarding costs roughly 1 in 5 sign-ups.** Hinge "Most Compatible" sends 1 a day, The League 5 a day, Coffee Meets Bagel about 5–10 (weak source), and Facebook "Meet Cute" 1 a week. Hinge accepts that about 20% of potential users don't finish its detailed onboarding [S7]. eHarmony cut its questionnaire from about 450 items to 80 (about 20 minutes) [S26, S27].
3. **In West Africa, apps are a minority route to a partner, and trust is the gap they fail to fill.** About 1 in 10 Nigerians met a partner on an app, against about 4 in 10 through events or friend introductions (Zikoko 2026, n>10,000) [S48]. Across 27 African countries, 29% met through family or friends; Bumble is popular in Ghana; Tinder leads in Kenya and South Africa [S47]. Live-stream matchmakers, admin-run Facebook groups and vetted human matchmakers fill the trust gap [S53, S54]. Ghana's losses to romance fraud and sextortion are large and rising [S55]. Tinder says mandatory liveness checks cut exposure to bad actors by more than 60% (vendor claim) [S15].
4. **"Who you want to meet" is special-category data everywhere Attune will launch.** That holds under GDPR Art. 9, POPIA s.26 and (unverified) the Ghana, Nigeria and Kenya Acts. A Norwegian appeal court held that merely being on a gay dating app reveals sexual orientation, and upheld Grindr's NOK 65m fine [S61]. Ghana's parliament passed the anti-LGBTQ+ bill in late May 2026. It includes a "duty to report" and awaited presidential assent at the last report [S56]. Entrapment through dating apps is documented in Nigeria, Ghana and South Africa [S57, S58]. Grindr's five-tier country system is the working model for country-aware safety [S59].
5. **The best products ask sensitive questions in separate parts.** Each answer can be shown or hidden ("Visible on profile", Hinge [S3]). Your own answer, what you'd accept and how much it matters are separate questions (OkCupid [S23]). Any preference can be made a dealbreaker (Hinge [S10]). Every list has a "not listed / prefer not to say" option (Hinge [S4]). The intention is re-confirmed regularly (Tinder, weekly [S11]). Integrity fields lock once set (Shaadi: date of birth, marital status and religion can be edited only once [S43]). Photos stay private until the user chooses to share them, and a family chaperone can join the chat (Muzz [S38]).

---

## 1. How this was researched

### 1.1 Sources and method
- **Primary/official pages:** help centres (Hinge, Tinder, Bumble, Shaadi), App Store listings (Muzz), product pages (Timeleft, Tawkify), Grindr's own risk-tier write-up, and statute text (GDPR Art. 9, POPIA s.26).
- **Systematic reviews:** Mozilla *Privacy Not Included* on dating apps (April 2024) [S63]; Article 19 on LGBTQ app abuse in MENA (2018) [S62].
- **Surveys and market data:** Sagaci Research pan-African panel (n=13,557, Oct 2024) [S47]; Zikoko/TechCabal *State of Love* Nigeria (n>10,000, 2026) [S48]; Sensor Tower quarterly app summaries for Ghana, Nigeria, Kenya and South Africa [S49–S52].
- **Trade and tech press, plus Wikipedia,** for feature launches, numbers and history. Graded Weak.
- **The Attune repo, read-only:** `lib/architecture/DATING_MODE_SPEC.md`, `lib/architecture/DATING_MODE_CULTURAL_REVIEW_PACKET.md`, the dating migrations and `lib/architecture/attune/ATTUNE_RISK_SOLUTIONS.md` [S73].
- **Not done, per the brief:** no sign-ups or logins and no installs. Step orders therefore come from help centres and third-party walkthroughs, not first-hand recordings.

### 1.2 Grades
- **Strong:** meta-analysis, large RCT or large dataset.
- **Moderate:** peer-reviewed study, large survey, official policy, statute or court ruling.
- **Weak:** single small study, press, or vendor claim.
- **Anecdote:** reviews and forum posts.

Most product facts in this file are **Weak**, because they are vendor claims or press reports. That is the nature of the area: companies don't publish their onboarding funnels.

### 1.3 Limits (read before relying on this)
- **The web-search budget ran out mid-run.** The cap of 200 searches is shared by all parallel researchers. Coverage of the following is therefore thin and marked `[UNVERIFIED]`:
  - Known, Sitch, Amata, Keeper and Thursday;
  - Salams, Upward, Dil Mil and Tantan;
  - Pairs and Omiai;
  - Three Day Rule and Kelleher;
  - the Ghana, Nigeria and Kenya statute texts;
  - design writing on onboarding motion.

  A follow-up run could close these gaps.
- **Blocked pages:**
  - Several official help centres returned HTTP 403 (Hinge, Tinder AI-matching, Article 19, Pew). Their content here comes from search-result extracts of those pages.
  - Built for Mars' Hinge teardown is behind a paywall [S76].
  - The Article 19 PDF could not be text-extracted locally.
- **Sensor Tower's African "top 5" posts are AI-written summaries of model estimates,** and they disagree across platforms. Use them for "which apps appear", not for magnitudes.
- **No public onboarding-funnel data** exists beyond Hinge's ~20% non-completion figure [S7]. Every "time to complete" figure is a vendor claim or a reviewer's estimate.
- **Option lists change often.** Hinge, Tinder and Bumble all rename intention and gender options, so verify current labels before copying any of them.

---

## 2. Findings

### 2.1 Mainstream products: sign-up, onboarding, length

| Product | Sign-up | Onboarding steps in order (R = required, O = optional) | Length / drop-off | Src |
|---|---|---|---|---|
| **Tinder** | Phone, Apple, Google or Facebook; SMS verification in every case | Name (R; permanent), DOB (R), gender (R; optional "show on profile"), orientation (up to 3 terms; optional show), who to see (R), relationship goal (O), distance (R; 1–100 mi), lifestyle: drink/smoke/workout/pets (O), interests (~5), photos (R; min 2), Face Check video selfie (R in a growing list of markets) | About 5 min (walkthrough estimate) | [S13][S14][S15] |
| **Hinge** | Phone; Facebook dropped in 2018 | Name, DOB, location, gender (Man/Woman/Non-binary, then "Add your gender identity"), sexuality ("Not listed" option), who to date, dating intentions, relationship type, height, ethnicity, children/family plans, hometown, work, school, religion, politics, vices (drinking, smoking, marijuana, drugs). Each vital/virtue has a "Visible on profile" toggle. Photos R (4–6, depending on local rules). 3 prompts R. Voice and video prompts O | **~20% of potential users don't finish** (CEO Jackie Jantos, June 2026) | [S3][S4][S6][S7][S8] |
| **Bumble** | Phone; originally Facebook only | Gender, intention (up to 2 shown), then "My basics": work, education, location, hometown, height, activity level, star sign, drinking, smoking, kids (have/want), religion, politics, family plans. Support copy calls religion and politics "more personal… completely up to you". Up to 5 interest badges, prompts, bio, photos. Selfie verification (2016); ID verification option (2025). **2026:** "Bee" AI onboarding chat (typed or voice) and chapter-based profiles | n/a | [S18][S19][S20][S21][S22] |
| **OkCupid** | Free registration | Identity (22 genders, 20 orientations, pronouns), basics, then match questions (4,000+ available; 50–100 suggested to start) | n/a | [S23][S24][S25] |
| **Match** | n/a | Relationship status (incl. separated, widowed), body type, kids (have / want), income: "totally optional" | Reviewer: "some of those questions I do not even know the answer to" (Anecdote) | [S28] |
| **eHarmony** | n/a | 80-question Compatibility Quiz (personality, values, communication, goals); progress can be saved | ~20 min (vendor) vs 30–45 min (Vice). History: ~450 items, then ~150 (2017); quiz optional from 2016 | [S26][S27] |
| **Coffee Meets Bagel** | Phone or Facebook | SMS/email verification, then age, height, **ethnicity, religion**, then photos (≥3 recommended), prompts, preferences | 10–15 min (weak) | [S29] |
| **Badoo** | Registration required | Choose purpose: date / chat / new friends. Pose-matching photo verification | n/a | [S31] |
| **Happn** | n/a | Location-led: feed of people you've physically crossed paths with | n/a | [S32] |
| **Facebook Dating** | Inside a Facebook account, as a separate profile | Filters: location (≤100 km), children, religion, age, height. Age verification added 2022. AI dating assistant (Sept 2025, US/CA) | n/a | [S33] |
| **Raya** | Application linked to Instagram | Background, profession, interests, photo montage, then review | ~8% of applicants accepted (Business Insider via Wikipedia) | [S34] |
| **The League** | LinkedIn and Facebook | Profiles reviewed on alma mater, profession, industry, neighbourhood and age. Preferences: gender, age, height, distance, education, **religion, ethnicity** | Waitlist ~420k; 10–20% accepted (2017) | [S35] |
| **Lox Club** | Application | Every application reviewed by an 8-person committee for "cultural fit [rather] than social status" | ~2-week waitlist (2020); 20,000 waiting (2021) | [S36] |
| **Boo** | `[UNVERIFIED]` personality-type (16-type) matching | — | Listed in SA's top 5 (2025) | [S52] |

### 2.2 Data-point matrix (what each collects)

● = collected as a structured field · ◐ = optional / partial · ○ = not a field, or not found · F = usable as a filter

| Field | Tinder | Hinge | Bumble | OkCupid | Match | eHarmony | CMB | FB Dating | League | Muzz | Shaadi |
|---|---|---|---|---|---|---|---|---|---|---|---|
| DOB / age | ● F | ● F | ● F | ● F | ● | ● (min 21 historically) | ● F | ● F | ● F | ● | ● (edit once) |
| Gender (count) | ● Man/Woman/Beyond Binary; more in tests | ● 3 top-level + 50+ specific | ● | ● 22 | ● | ● (binary until 2010) | ● | ● | ● | ● | ● (edit once) |
| Sexuality / interested in | ◐ up to 3 terms; display optional | ● (21 options, Mexico 2025) | ● | ● 20 | ● | ● | ● | ● | ● | n/a (M–F) | n/a (M–F) |
| Intention | ◐ 6 options | ● 6 + relationship type | ● ≤2 shown | ◐ | ○ | implicit (long-term) | ○ | ○ | ○ | ● marriage timing | implicit (marriage) |
| Location / distance | ● GPS, 1–100 mi | ● precise; background collection per policy [S63] | ● F free | ● | ● | ● F | ● | ● ≤100 km | ● | ● F | ● |
| Height | ○ | ● (Hinge+ F) | ● (paid F) | ◐ | ◐ | ○ | ● | ● F | ● F | ○ | ● (edit once) |
| Education / job | ◐ | ● (Hinge+ F) | ● (paid F) | ◐ | ◐ | ○ | ◐ | ○ | ● vetted | ● F | ● |
| Religion | ○ (not used in ranking [S12]) | ● F | ● (paid F) | ◐ | ◐ | ○ | ● | ● F | ● F | ● sect + "how practising" F | ● (edit once) |
| Ethnicity | ○ (not used [S12]) | ● F (free per review) | ○ | ◐ | ◐ | ○ | ● | ○ | ● F | ● F | ● community/caste |
| Politics | ○ | ● (Hinge+ F) | ● (paid F) | ◐ | ○ | ○ | ○ | ○ | ○ | ○ | ○ |
| Kids (have / want) | ○ | ● (Hinge+ F) | ● (paid F) | ◐ | ● | ○ | ○ | ● F | ○ | ● timeline | ● |
| Drink / smoke / drugs | ◐ lifestyle | ● vices (Hinge+ F) | ● | ◐ | ◐ | ○ | ○ | ○ | ○ | ◐ | ● diet / drink / smoke `[UNVERIFIED]` |
| Languages | ○ | ● | ○ | ◐ | ○ | ○ | ○ | ○ | ○ | ● F | ● mother tongue (edit once) |
| Marital status | ○ | ○ | ○ | ○ | ● | rejects married applicants | ○ | ○ | ○ | `[UNVERIFIED]` | ● (edit once) |
| Prompts / bio | ● | ● 3 R | ● | ● | ● | ● | ● | ● | ● | ● 3 icebreakers | ● |
| Photos | ● ≥2 | ● 4–6 R | ● | ● | ● | ● | ● ≥3 rec. | ● | ● | ● private until ready | ● |
| Voice / video | ○ | ◐ voice prompts, video | ○ | ○ | ○ | ○ | ○ | ○ | ○ | ◐ profile video, voice notes | ○ |
| Verification | Face Check (mandatory in many markets) | selfie | selfie + ID option | ○ | ○ | ○ | phone + optional photo | age verification | LinkedIn | **selfie for every profile** + ID badge | mobile |
| Psychometrics | ◐ Chemistry Q&A (+ camera-roll scan, opt-in) | ○ | ◐ Bee chat (2026) | ● questions | ○ | ● 80 Q | ○ | ○ | ○ | ◐ personality | horoscope `[UNVERIFIED]` |

Sources: Tinder [S12–S17]; Hinge [S3–S10]; Bumble [S18–S22]; OkCupid [S23–S25]; Match [S28]; eHarmony [S26, S27]; CMB [S29]; FB Dating [S33]; The League [S35]; Muzz [S38–S42]; Shaadi [S43, S44].

### 2.3 Matching, daily volume and business model

| Product | Filters vs ranking vs dealbreakers | Recommendations per day | Business model | Src |
|---|---|---|---|---|
| Tinder | Ranking leans most on **activity** ("active at the same time"), then proximity, then age, distance and gender preferences, then profile content and "anonymized cues from photos". Tinder says it doesn't use social status, religion or ethnicity. **Chemistry** (2026): curated daily recommendations from a question set plus an opt-in camera-roll scan, with insights shown in an "Insights Hub" where users can review and delete them | Open card stack, plus daily Chemistry picks | Freemium subscriptions (tiers not re-verified) | [S12][S16][S17] |
| Hinge | Preferences are filters. Each can be made a **dealbreaker**: core ones free, advanced ones on Hinge+. **Most Compatible** has been built on Gale–Shapley stable matching since 2018 and uses mutual dealbreakers, recent activity and like patterns. "8× more likely to lead to a date" is a vendor claim | Most Compatible 1 a day (expires after 24 h); free likes 8 a day | Hinge+ / HingeX. Direct revenue $691m in 2025 | [S8][S9][S10] |
| Bumble | Free filters: age and distance. Advanced Filters on any badge are paid. Completing your basics makes you visible to people using filters. **Bee** (2026) learns values, goals, communication style and intentions in conversation, then suggests matches. The swipe is being phased out in select markets from Q4 2026 | Card stack (being replaced) | Freemium (Boost / Premium) | [S18][S21] |
| OkCupid | For each question: your answer, the answers you'd accept, and importance (irrelevant / a little / somewhat / very). Third-party write-ups give weights of 0/1/10/50/250. Match % is the geometric mean of both sides' satisfaction | Browse plus stacks | Freemium | [S23][S24] |
| eHarmony | Quiz-based matching on "core traits and values" plus behavioural data. "The Two Of You Together" explains matches (2017). Matches are shown regardless of whether the other person pays | Curated list | Paid subscription. Australian regulator sued over a "subscription trap" (2023) | [S27] |
| Coffee Meets Bagel | Curated "Suggested" list at noon; unanswered suggestions expire | ~5–10 a day (weak; earlier 1 a day, then up to 21 for men; conflicting) | "Beans" currency plus Premium ($15–35 a month) | [S29] |
| Facebook Dating | Filters (location, children, religion, age, height); "Lucky Match" widens them. AI assistant takes plain-language requests and uses only what's on the profile (Meta's claim). **Meet Cute** surprise match (opt-out) | 1 a week (Meet Cute) | Free (Meta) | [S33] |
| The League | Curated admission, plus preferences that include height, education, religion and ethnicity | **5 a day** | Paid tiers; paying lets you skip the waitlist | [S35] |
| Muzz | Filters: location, interests, profession, ethnicity, language, education, "how practicing" | Feed | Gold / Premium subscriptions. Vendor claim: 90% find a partner without paying | [S38][S41] |
| Tawkify (human) | Matchmaker intake; every candidate gets a video screening and a criminal-record screening | A few curated dates | High-ticket packages (price not listed) | [S67] |

### 2.4 Intentional, slow and curated products, and AI matchmakers (2024–2026)

| Product | Mechanism | What it collects | Notes | Src |
|---|---|---|---|---|
| Hinge Most Compatible | 1 a day, Gale–Shapley-derived, 24 h expiry | Likes and passes, dealbreakers | The longest-running curated feature at scale | [S8][S9] |
| CMB daily limit | Noon delivery; expiry; a 7-day chat window (one source) | Standard profile plus ethnicity and religion | Built in 2012 as a "one bagel a day" product | [S29][S30] |
| Timeleft | Weekly dinners for 6 strangers, matched on a 3-step personality quiz ("Logic and facts" vs "Emotions and feelings"), age range and language | A few questions; dietary needs at booking | Runs in 200+ cities in 52 countries; "Singles" and "Women-only" dinners | [S37] |
| Tinder Chemistry | Q&A onboarding plus an opt-in camera-roll scan; Insights Hub to review and delete | Personality signals and image-derived cues | Tested in AU/NZ, then US/CA (2026) | [S16][S17] |
| Bumble Bee | Conversational onboarding (typed or voice), then suggested matches; chapter-based profiles | Values, goals, communication style, lifestyle, intentions | Announced March 2026; beta "soon" | [S21] |
| FB Dating assistant / Meet Cute | Natural-language search; profile coaching; weekly surprise match | Existing profile data only (Meta's claim) | US/CA, September 2025 | [S33] |
| Thursday | `[UNVERIFIED]` App opened only on Thursdays, then reportedly moved to in-person events | — | — | — |
| Known, Sitch, Amata, Keeper | `[UNVERIFIED]` AI-matchmaker startups. Known is reported to use a long **voice-interview** onboarding; Sitch reportedly charges per set of matches | — | Leads only; verify before citing | — |

**Pattern.** The 2025–2026 incumbents (Tinder, Bumble, Facebook) are all moving toward **onboarding by conversation or questions, then a few curated picks a day**. Two of them (Tinder's camera-roll scan, Bumble's Bee) **expand** the data they collect through inference. That is the opposite of what Attune's spec allows: no photo-derived attributes, and explanations generated only from scored features (`DATING_MODE_SPEC.md` §4.3, §6.2) [S73].

### 2.5 Faith- and culture-based products

| Product | Sign-up / verification | Fields that differ from mainstream apps | How sensitive data is handled | Src |
|---|---|---|---|---|
| **Muzz** (UK; 20M+ community; "1M+ marriages" vendor claim) | **Selfie verification for every profile** (since 2016); optional ID, which earns a blue badge; human moderation | Sect; **level of practice**; marriage and children timeframe; **"Marriage Intentions"** (when you plan to involve your family and marry); ethnicity, language, profession | **Photos private until you choose to share them / blurred except for chosen matches**; **screenshot blocking**; **Wali/chaperone** can join conversations; in-person events (Lahore, 2024) | [S38][S39][S40][S41][S42] |
| **Shaadi.com** (India / diaspora, marriage-intent) | Mobile verification; Google sign-up on Android | Compulsory fields, with "Other" offered when religion, caste, mother tongue or profession isn't listed; a **Family** section; partner preferences. "Profile created by": self / parents / sibling / friend / relative (weak source) | **Religion, community, DOB, gender, height, marital status and mother tongue can be edited only once after registration** | [S43][S44] |
| **Jeevansathi** | n/a | Horoscope status (a user complaint says it can be wrong on manglik status) | — | weak; `[UNVERIFIED]` |
| **Christian Mingle** (Spark Networks) | n/a | Denomination (10 named plus interdenominational / non-denominational / "not sure yet") | Same-sex matching only since 2016, after a lawsuit. Mozilla: its policy allows collecting "sexual life experiences" | [S45][S63] |
| **JSwipe** (Spark) | n/a | Level of observance / denomination; **kashrut** (kosher observance); orientation | Matches expire. Mutual match plays an **animated Jewish-wedding illustration** | [S46] |
| **Lox Club** | Committee review | Culturally Jewish, open to all | — | [S36] |
| Salams, Upward, Dil Mil, Tantan, Pairs/Omiai | `[UNVERIFIED]` Salams (Muslim) and Upward (Christian) mirror Muzz and Christian Mingle. Dil Mil targets the South Asian diaspora. Tantan is Chinese and owned by Hello Group. Japanese apps (Pairs, Omiai) must by law verify that users are adults with ID before messaging, and commonly ask for a marriage timeline and income | — | — | — |

**Pattern.** Marriage-intent and faith products share three habits:
- They **collect more sensitive fields** (sect, how practising, caste, family details) because those fields decide matches in those communities.
- They **add privacy controls around them**: photo privacy, chaperones, screenshot blocking.
- They **treat the timeline as a first-class field** ("when do you want to marry / involve family").

They also **lock identity-grade fields** against gaming (Shaadi).

### 2.6 Africa and the diaspora: what people actually use

| Signal | Finding | Grade | Src |
|---|---|---|---|
| App use overall | 28% of African adults have ever used a dating app (27 countries, n=13,557, Oct 2024). Kenya 38%, Cameroon 39%, Egypt 10%. Usage roughly equal by gender; the core users are 26–45. 43% use apps "to make new friends" | Moderate (large online panel; online-only bias) | [S47] |
| Which apps, by country | **Ghana: Bumble popular.** Tinder leads in Kenya, South Africa, Tanzania, Zambia and Zimbabwe. Dating.com is strongest in **Nigeria**, Uganda and Zambia. Badoo leads in francophone Central/West Africa | Moderate (same panel) | [S47] |
| Ghana downloads | Q1 2024: Tinder ~93–110K active users; Bumble and Badoo next. By Q3 2024, live-chat apps (SOYO, Poppo, iHappy, VSChat, SweetMeet) dominate the "dating" top 5 | Weak (AI-summarised estimates) | [S49] |
| Nigeria / Kenya downloads | Tinder and Badoo steady; live-chat apps (SOYO, Only Spark, iHappy, SweetMeet) top the Android charts | Weak | [S50][S51] |
| South Africa | Tinder ~200K weekly active users; Hinge (~38K) and Bumble (~37.5K) next (Q2 2025). The top 5 also includes Badoo and Boo | Weak | [S52] |
| How Nigerians meet | ~1 in 10 met a partner on a dating app; ~4 in 10 through **events or friend introductions** (church, parties); social media ranks third. 62% are in relationships with no clear label | Moderate (n>10,000; method not inspected) | [S48] |
| How Africans meet | 29% of those in relationships met through **family or friends**, 17% through education | Moderate | [S47] |
| Trust substitutes | **Creator-led live matchmaking** (TikTok, Bigo Live; one host has 300K followers), sold as anti-impersonation ("viewers can see the person is real"). An **admin-mediated Facebook group** in northern Nigeria (4,500 members; 32 marriages). **Kano matchmaking sites** that hide clients behind AI-altered photos until paid registration. **Lagos Matchmaker** (Instagram, then WhatsApp; vetting and tiered membership) | Weak / Anecdote | [S53][S54] |
| Fraud environment (Ghana) | Online fraud, romance scams included, caused ~GH¢12.87m in losses (Jan–Sep 2025), ~47% of complaints to the Cyber Security Authority (CSA). Sextortion losses rose ~5× (GH¢104k to GH¢499k, Jan–Apr 2024 vs 2025). EOCO had ~107 active romance-fraud cases. In December 2025, 32 people were arrested in a romance-scam hub raid in Kasoa | Moderate–Weak (official figures via press) | [S55] |
| LGBTQ+ legal risk | Ghana's Human Sexual Rights and Family Values Bill passed parliament (late May 2026), with up to 3 years for identifying as LGBTQ+, a "duty to report" and penalties for "allies". At the last report it awaited presidential assent | Moderate (multiple outlets) | [S56] |
| Entrapment | **"Kito"** entrapment in Nigeria (fake queer profiles used to lure, rob, film and extort). Two men arrested in Kasoa, Ghana (2019) for using Grindr to lure and extort men. Johannesburg Grindr kidnappings linked to 86 similar cases | Weak / Anecdote | [S57][S58] |

**What this means:**
- West Africans **trust introductions through people and places**, and distrust strangers on apps.
- Fraud and entrapment are the main threats, not only harassment.
- The diaspora layer (Ghana–UK/US/Canada) matters. Muzz's largest markets after the UK are Morocco and Pakistan, which shows faith-diaspora products travel [S40].

`[UNVERIFIED]` cultural context worth confirming with the Ghanaian reviewer:
- Ghana's 2021 census puts Christians at about 71% and Muslims at about 20%.
- Customary marriage ("knocking", family-to-family) is the normal route to marriage.
- Customary and Islamic marriages can lawfully be polygynous.

### 2.7 LGBTQ+ products and safety by design in hostile countries

| Product | Safety-by-design | Data lessons | Src |
|---|---|---|---|
| **Grindr** | **Five country risk tiers** (built from ILGA reports plus local queer networks). Tiers 3–4: "Show distance" **disabled**, free safety features, weekly or daily risk alerts. Tier 5: banned or blocked. Screenshot blocking, **expiring photos** and **unsend** were built for high-risk countries and then released to everyone. App icon can be **disguised as a notepad or clock** (built with Article 19 and the Guardian Project). Distance was disabled in some countries from 2014 | 2014: distances allowed **trilateration** of exact location; 2016: still possible with distance hidden. 2018: HIV status and test dates reached vendors (SINTEF). 2020–21: ad-network sharing led to the **NOK 65m GDPR fine, upheld on appeal on 21 Oct 2025**. The court held that the App ID **revealing use of the app is itself sexual-orientation data**. Location data sold through ad networks led to a priest being outed (WSJ/Pillar, via Mozilla) | [S59][S60][S61][S63] |
| **HER** | Gender verification (historically through Facebook); up to 35 gender identities; pose selfie ("not foolproof") | — | [S65] |
| **Taimi** | Human-moderated "verified" labels; **Taimi Protect** (Face ID / fingerprint / passcode) | **Removed an HIV-status block filter after backlash** | [S66] |
| **Lex** | Text-first, personality-led | Mozilla's "Best Of" in 2024 for privacy. Mozilla advised against signing up with Instagram, because linking lets both companies collect more | [S64] |
| Article 19 (MENA research with Grindr) | Recommendations: **secure sign-up, invisibility and encryption, geolocation removal, emergency reporting**. "Just having a dating app on your device can be enough to get arrested", because police search phones | — | [S62] |

### 2.8 Human matchmaking and family introductions (reference model)

| Service | Intake | Vetting | Introductions | Feedback | Src |
|---|---|---|---|---|---|
| **Tawkify** (US) | **1-hour onboarding call**; matchmaker learns "values and what you want" | **Video screening and criminal-record screening for 100% of candidates** | Curated in-person or video dates | Client reports how each date went; the matchmaker adjusts | [S67] |
| **Lagos Matchmaker** | Instagram first contact, then WhatsApp | Staff vet clients; tiered membership | Human-made | — | [S54] |
| **Kano sites** | Paid registration | Photos hidden behind AI-altered images until registration | Human-made | — | [S54] |
| **Muzz Wali / chaperone** | — | Family member joins the chat | — | Family as a check | [S38][S41] |
| **Shaadi "created by parent"** | Family can run the profile | Mobile verification | Family-mediated | — | [S44] (weak) |
| Three Day Rule, Kelleher | `[UNVERIFIED]` In-person intake interview, high fees, matchmaker-written introductions | — | — | — | — |

**The traditional model.** A trusted intermediary hears your values and dealbreakers privately and vets the other person. They make a **few** introductions, each with a reason, and adjust after feedback. Attune's curated, double-opt-in introductions with an explained Alignment preview (`DATING_MODE_SPEC.md` §4.2) already match the "few, with a reason" part. **What's missing is vetting** (liveness / identity) and a **visible trust signal**, which live matchmakers and admin-run groups supply.

### 2.9 Marital status, "already in a relationship" and returning after a breakup

| Situation | What products do | Src |
|---|---|---|
| Currently married | eHarmony **rejected** applicants: ~30% of ~1M rejections (by 2007) were already married. It also rejected people under 60 who had married more than 4 times, and people who failed a depression screen. Mainstream apps (Tinder, Hinge, Bumble) don't ask | [S27] |
| Marital history | Match asks relationship status (incl. separated, widowed). Shaadi asks marital status and **locks it after one edit** (the Scribd list gives unmarried / divorcee / widow). Muzz: `[UNVERIFIED]` | [S28][S43][S44] |
| Non-monogamy / partnered | Hinge "Relationship Type": monogamy / non-monogamy / figuring out. Tinder Explore has a "Non-Monogamy" category. Bumble offers "ethical non-monogamy" | [S2][S11][S20] |
| Leaving because it worked | Hinge "We Met" (2018): members privately confirm a first date. "Designed to be deleted" branding | [S8] |
| Returning after a breakup | **No product found that gates re-entry after a breakup.** eHarmony's depression screen is the nearest precedent for readiness-based exclusion, and it was a source of controversy | [S27] |

**Implication:** Attune's gentle wait applies only to relationships that ended inside Attune (owner decision). It has **no market precedent**, so its effect is unknown, and it should be measured (implication 13).

### 2.10 Onboarding length, drop-off and motion

**Length and drop-off (all the public data found):**
- Hinge: ~20% of potential users don't finish, a deliberate trade-off [S7].
- Tinder: ~5 min [S14] (weak).
- CMB: 10–15 min [S29] (weak).
- eHarmony: 80 questions, ~20 min (vendor) vs 30–45 min (Vice) [S26].
- Tawkify: a 1-hour call [S67].
- OkCupid: 50–100 questions suggested [S24].
- Timeleft: 3-step quiz [S37].
- Raya: 8% accepted [S34]. The League: 10–20% accepted [S35].

**Motion and interaction patterns that appear in the sources** (design write-ups were mostly unreachable; see §1.3):
- **Tinder:** intention shown as a coloured **emoji banner** at the top of the profile [S11]. 2026: full-screen photos and "updated visual design elements" [S16].
- **Hinge:** you must **like a specific photo or prompt**, not the whole person. This interaction makes the first message about something concrete [S8]. Built for Mars describes Hinge's interface as designed to keep you "inside a cycle" through social scarcity (paywalled) [S76].
- **JSwipe:** an **animated Jewish-wedding illustration** on a mutual match [S46]. It celebrates cultural identity, but it is still a reward burst.
- **Bumble 2026:** **chapter-based** narrative profiles [S21].
- **Timeleft:** a visible **"Step 1 of 3"** progress label on the quiz [S37].
- `[UNVERIFIED]`:
  - one question per screen with a progress bar is the industry default;
  - Tinder's physics-based card swipe with LIKE/NOPE stamps and a full-screen "It's a Match";
  - Known's animated voice "orb".

None of these are allowed under Attune's rules: no confetti, swiping, scarcity timers or variable rewards (`DATING_MODE_SPEC.md` §1) [S73].

---

## 3. Synthesis

### 3.1 Minimum viable data set for good curated introductions

The required set is **exactly what the symmetric hard filters, the 18+ rule and safety need**, plus a small human layer. Everything else is optional and progressive. This mirrors the human-matchmaker split: intake covers values and dealbreakers, vetting covers identity, and the rest comes out in conversation.

| Tier | Field | Why | Evidence |
|---|---|---|---|
| **Required** | DOB → age (shown as age only) | 18+ gate; age-range filter | Owner decision; all products |
| Required | Own gender | Hard filter | All products |
| Required | Who you want to meet (men / women / everyone) | Hard filter, mutual only | Owner decision; [S12] |
| Required | City/region + "open to long distance / abroad" | Coarse location (no GPS); diaspora | [S33] (100 km), Grindr trilateration [S60], Mozilla [S63] |
| Required | Intention (fixed enum, ≤4 options) | Hard filter; most-adopted field | [S1][S11][S20] |
| Required | Not married / not in a relationship (attestation) | eHarmony precedent; Attune pauses dating when in a relationship | [S27]; spec §3.4 |
| Required | 2+ moderated photos | Humanises; safety | Tinder min 2 [S14]; Hinge 4–6 [S6] |
| Required before first introduction | Liveness selfie | Fraud and impersonation (Ghana) | [S15][S38][S55] |
| Required | 2–3 prompts (or bio) | The "with a reason" layer; Hinge's like-a-prompt | [S6][S8] |
| **Strongly recommended** | Children: have / want (dealbreaker-capable) | Decisive for marriage-minded users; asked by Hinge, Bumble, Match, Muzz, FB | [S3][S18][S28][S33][S42] |
| Strongly recommended | Faith + "how much sharing it matters" (optional, explicit consent) | Decisive in faith communities; Muzz, Christian Mingle, JSwipe | [S38][S45][S46]; special category |
| Strongly recommended | Marriage timeline (only if intention = marriage) | Muzz Marriage Intentions; fits Ghana | [S42] |
| **Nice to have** | Languages, education, work, hometown, drink/smoke, interests, height (display only) | Conversation fuel; not decisive | [S3][S18] |
| **Not in v1** | Ethnicity/tribe, income, politics, HIV/health, body type, zodiac, camera-roll inference | Special category or fraud lure; low value for curated intros; already excluded by spec §4.1 / §6.1 | [S12][S63][S66]; spec |

Attune's quiz dimensions (attachment, communication, conflict) already provide the psychometric layer that eHarmony and OkCupid collect at sign-up. So Attune doesn't need a long sign-up questionnaire.

### 3.2 Fields that cause friction, discomfort or safety risk

| Field | Friction / harm | Evidence |
|---|---|---|
| Sexual orientation / who to meet | **Legal and entrapment risk** (Ghana bill, kito, Kasoa). Special category. Simply holding it reveals orientation (Grindr ruling) | [S56][S57][S58][S61] |
| Precise location / distance | Trilateration; background collection; data sold through ad networks | [S60][S63] |
| Photos | Screenshots (Raya warns and removes; Muzz and Grindr block). EXIF time and place metadata (FB Dating, CMB) | [S34][S38][S59][S63] |
| App presence itself | Phones searched at arrests; Article 19 calls for "invisibility" | [S62] |
| HIV / health | Shared with vendors (2018). Taimi's HIV filter drew backlash | [S60][S66] |
| Ethnicity / caste / tribe | Special category everywhere. Lists are always incomplete (Shaadi needs an "Other"). Filtering on it is contested | [S43][S68–S72] |
| Religion / politics | Bumble frames them as "more personal… up to you". Politics is paywalled as a filter on Hinge and Bumble, which suggests it is a monetisation lever, not core | [S10][S18][S19] |
| Kids / marital status | "Some of those questions I do not even know the answer to" (Match reviewer, Anecdote). Marital status is *sensitive* under Kenya's Act `[UNVERIFIED]` | [S28][S70] |
| Long questionnaires | eHarmony shrank from ~450 to 80 items; Hinge loses ~20% to detailed onboarding | [S7][S27] |
| Identity labels | OkCupid removed "sapiosexual" after backlash; label sets need upkeep and a "not listed" option | [S24][S4] |
| Income | Collected by Match and Shaadi. Reasoning, not evidence: it is a lure for romance-fraud targeting in a high-fraud market | [S28][S55] |

### 3.3 Data-protection classes

| Data | GDPR Art. 9 [S68] | POPIA s.26 (SA) [S69] | Ghana Act 843 `[UNVERIFIED]` [S71] | Nigeria NDPA 2023 `[UNVERIFIED]` [S72] | Kenya DPA 2019 `[UNVERIFIED]` [S70] |
|---|---|---|---|---|---|
| Sexual orientation / sex life (incl. who you want to meet; using an LGBTQ app) | **Yes** | **Yes** (sex life) | **Yes** (sexual life) | **Yes** (sex life) | **Yes** (sex, sexual orientation) |
| Religion / belief | **Yes** | **Yes** | **Yes** | **Yes** | **Yes** (conscience, belief) |
| Race / ethnicity / tribe | **Yes** | **Yes** | **Yes** (incl. tribal origin) | **Yes** | **Yes** (race, ethnic social origin) |
| Political opinion | **Yes** | **Yes** | **Yes** | **Yes** | not explicit (check) |
| Health (HIV, disability, mental health) | **Yes** | **Yes** | **Yes** | **Yes** | **Yes** |
| Biometric (face template for verification) | **Yes** (when used to uniquely identify) | **Yes** | check | **Yes** | **Yes** |
| Marital status, family details (children, spouse) | No | No | No | No | **Yes** |
| Criminal record (background checks) | Art. 10 (separate) | **Yes** | **Yes** | check | check |

**Key ruling.** Borgarting Court of Appeal, 21 Oct 2025: an app identifier that reveals someone uses a gay dating app is Art. 9 data [S61]. For Attune, this means the fact that a user has Dating Mode on, combined with their own gender and who they want to meet, is special-category data. It must never reach analytics or advertising SDKs. That matches the SDK-audit deliverable already in `ATTUNE_RISK_SOLUTIONS.md` [S73]. Mozilla found that 80% of dating apps may share or sell personal data, and that most collect geolocation by default [S63].

### 3.4 How the best products ask sensitive questions

| Pattern | Who | Use in Attune |
|---|---|---|
| **Per-field "Visible on profile" toggle** | Hinge [S3]; Tinder show-gender / show-orientation [S13] | Default *hidden* for faith, children and gender; "who you want to meet" is never visible (owner decision) |
| **Split self / acceptable / importance** | OkCupid [S23] | For faith and children, ask: "Mine", "Who I'd meet" and "How much it matters" (doesn't matter / nice / must). "Must" becomes the dealbreaker |
| **Dealbreaker toggle per preference** | Hinge [S10] | Free for everyone; never a paid lever (no monetised filtering) |
| **Short list + specific add-on + "not listed"** | Hinge gender [S4]; Shaadi "Other" [S43] | Gender: Woman / Man + private "describe it myself"; faith: short list + "Other" + "Prefer not to say" |
| **Frame as personal, up to you** | Bumble [S19] | Copy on every special-category screen; skip is a first-class button |
| **Periodic re-confirmation of intention** | Tinder, weekly [S11] | Monthly or on resume-from-pause (no weekly nags; Attune has no streaks) |
| **Lock integrity fields** | Shaadi (edit once) [S43]; Tinder name permanent [S14] | DOB locked (correction through support); marital attestation re-asked on any change |
| **Photos private until ready; chaperone** | Muzz [S38][S40] | "Show my photos after we're both interested" setting; Wali-style trusted person as a later option |
| **Explicit consent screen for special categories** | GDPR Art. 9(2)(a) [S68] | One consent per category (faith, who-to-meet), recorded in the existing `dating_consent_events` table |

### 3.5 Intention taxonomies

| Product | Options | Display | Filter | Re-check |
|---|---|---|---|---|
| Hinge [S1][S2] | Life partner · Long-term · Long-term, open to short · Short-term, open to long · Short-term · Figuring out my dating goals. **Plus** relationship type: Monogamy / Non-monogamy / Figuring out | Profile (virtues) | Yes (dealbreaker) | — |
| Tinder [S11] | Long-term partner · Long-term, open to short · Short-term, open to long · Short-term fun · New friends · Still figuring it out | Emoji banner on top | Explore categories | **Weekly prompt** |
| Bumble [S20] | Commitment: Marriage · Relationship · Something casual · Don't know yet. Intentions also cover life partner, intimacy without commitment and ethical non-monogamy | Up to 2 shown | Paid filter | — |
| Badoo [S31] | Date · Chat · New friends | — | Mode | — |
| Muzz [S42] | Marriage-only, plus **when to involve family and marry** | Profile | Yes | — |
| eHarmony / Shaadi / Pairs | Implicit long-term / marriage; Pairs adds a timeline `[UNVERIFIED]` | — | — | — |

**What works (evidence is thin and all from vendors):**
- More than 50% of Tinder testers chose to show a goal, and 72% of members say they want "someone who knows what they want" [S11].
- 65% of Hinge daters said the feature helped their decisions [S1].
- **Unknown:** whether filtering on intention improves outcomes. No independent study was found.

**What to take from it (reasoning, not evidence):**
- Six options fragment a small pool. With Attune's thin, gated pool (spec §2.1), each extra intention value cuts the number of eligible pairs.
- The products aimed at serious relationships (Hinge, Muzz) keep a "figuring it out" escape hatch but put serious options first.
- Marriage-intent products add **timing**, which is more useful than another label.

---

## 4. Implications for Attune

1. **Make intention a fixed enum and enforce it on the server.** Today `relationship_intention` is free text of 1–80 characters (`save_dating_profile_draft`, migration `20260705210000`). Yet `dating_pair_passes_hard_filters` in `20260933170000` exact-matches it against `intention_preferences`. One stray variant silently drops a user from every pool. Proposed set: **Marriage · A committed relationship · Long-term, taking it slowly · Not sure yet**. Show it on the profile; use it as a symmetric filter. *Why:* every serious product uses a fixed set [S1][S11][S20]; a thin pool can't absorb fragmentation (§3.5); repo [S73].
2. **Add an optional marriage timeline**, shown only when the intention is Marriage: "In the next year or two · In a few years · No set timeline". Never make it a dealbreaker by default. *Why:* Muzz's Marriage Intentions fits marriage-intent cultures, including Ghana's family-led route [S42][S48] (cultural fit to be confirmed by the Ghanaian reviewer).
3. **Keep the required onboarding to about 8 screens, under 5 minutes.**
   - Screens: intention → who you want to meet (with country note) → own gender → city + "open to long distance/abroad" → children (have/want) → 2 photos → 2–3 prompts → liveness check.
   - Everything else is progressive, after the first introduction.
   - DOB is already collected at sign-up (owner decision).
   - *Why:* Hinge's detailed setup loses ~20% [S7]; eHarmony cut its quiz by about 80% [S27]; Attune's quizzes already carry the psychometric load (§3.1).
4. **Require a liveness selfie before the first introduction is shown,** and award a "Photo verified" mark.
   - Store the result and a timestamp. Delete the video. Keep no reusable face template unless the owner chooses duplicate-account detection, which needs separate explicit consent because biometric data is special-category.
   - Never feed it into ranking (spec §4.3).
   - *Why:* Ghana's fraud and sextortion trend [S55]; Tinder's claimed −60% exposure to bad actors and −40% reports [S15]; Muzz verifies every profile [S38]; GDPR / POPIA biometric class [S68][S69].
5. **Treat "who you want to meet" as Art. 9 data from day one.**
   - Server-side only, under `auth.uid()` RLS.
   - Never in analytics events, crash breadcrumbs, push payloads or AI prompts.
   - Store "everyone" as explicit values, not as an empty array. Today empty means "no restriction" in the filter, and readiness requires non-empty arrays: keep it that way.
   - Never derive it, and never show it.
   - *Why:* Grindr ruling [S61]; Mozilla's 80% sharing figure [S63]; the risk doc's SDK audit [S73].
6. **Ship country-aware safety tiers modelled on Grindr's five-level, ILGA-based system.**
   - Tier ≥3 countries (Ghana once the bill is law; Nigeria; others per ILGA) get:
     - a plain-language safety note before choosing "who you want to meet";
     - the PIN and quick-exit prompt (Spec 2 already built);
     - discreet notification text ("You have something new");
     - screenshot blocking and expiring photos in dating chat;
     - a reminder that no distance is ever shown.
   - Don't hide or remove options by country. Users decide; the app informs.
   - *Why:* [S56][S57][S58][S59][S62].
7. **Ask the safety question about the app's presence on the phone.** Offer a disguised icon or an innocuous app name for Dating Mode users in tier ≥3. The Attune icon covers this only if Attune itself is innocuous; Dating Mode must not show on the lock screen or in widgets. *Why:* Article 19 says having the app installed is itself an arrest risk [S62]; Grindr's disguised icon [S59].
8. **Allow "show my photos after we're both interested"** as a per-user setting. The other side sees prompts, the Alignment preview and the verified mark first. *Why:* Muzz photo privacy and blur [S38][S40]. It fits faith users, public figures and LGBTQ+ users, and spec §4.2 already puts photos after the preview.
9. **Faith: optional, with explicit consent.** Ask "My faith" (short list: Christian, Muslim, Traditional, Other, None, Prefer not to say) and "How much does sharing a faith matter to you?". The answer "Must share" becomes a symmetric dealbreaker. Show faith on the profile only if the user toggles it on. This needs the spec §4.1 review ("documented necessity"); this research is the necessity case. *Why:* decisive in faith communities [S38][S45][S46]; special category everywhere [S68–S72]; OkCupid's split pattern [S23].
10. **Children: have / want, dealbreaker-capable,** under the same split pattern. *Why:* asked by Hinge, Bumble, Match, Muzz and FB Dating [S3][S18][S28][S33][S42].
11. **Don't collect ethnicity/tribe, income, politics, health/HIV, body type or zodiac in v1, and don't scan the camera roll.** *Why:* special category or fraud lure; Tinder itself excludes religion and ethnicity from ranking [S12]; Taimi's HIV-filter backlash [S66]; the spec already forbids image-derived attributes [S73].
12. **Marital status: a required attestation, "I'm not married and not in a relationship".** Add an optional "Married before?" (Never / Divorced / Widowed), hidden by default. Lock the attestation; any change re-runs eligibility. Kenya treats marital status as sensitive, so apply the same protection. *Why:* eHarmony's rejection precedent [S27]; Shaadi locks the field [S43]; Kenya DPA [S70].
13. **Measure the gentle wait,** because no product does anything like it (§2.9). Compare mutual-interest rate, block/report rate and self-reported comfort for users who took the wait or Healing against those who didn't. Collect this as aggregate, consented counts only, never per user. *Why:* no precedent; owner decision.
14. **Change spec §6.4 from a weekly batch to a daily drop.** Up to 3 introductions a day at a fixed local time, each expiring in 7 days. Fewer when the pool is thin, and never padded by relaxing filters (spec §6.4 already says this). *Why:* the owner's "few a day"; Hinge 1/day [S9], League 5/day [S35], CMB noon and expiry [S29].
15. **Don't use conversational AI onboarding** (Bumble Bee, Tinder Chemistry) in v1. *Why:* both widen what is inferred [S16][S17][S21]; Attune's spec requires reasons drawn only from scored features, and the risk doc commits to non-conversational AI under the 2026 companion-chatbot laws [S73].
16. **Onboarding motion:**
    - One question per screen, with a visible "x of 8" progress label.
    - The per-field "Visible on profile" toggle animates the preview card, so users see what is public.
    - Introductions arrive with a calm cross-fade; there is no "It's a match" burst. A mutual match gets a quiet, warm screen.
    - Every transition has a reduced-motion fallback (F16).
    - *Why:* [S8][S11][S37][S46]; spec §1 bans confetti and variable reward.
17. **Measure the funnel from day one,** with no special-category data in events:
    - step-level completion (benchmark: Hinge's ~80% finish [S7]);
    - time to the first introduction;
    - verification pass rate;
    - mutual-interest rate by intention;
    - block/report rate by country tier, aggregated server-side.
18. **Plan a trust signal that suits West Africa** for after v1. Options: Timeleft- or Muzz-style community events, a "vouched by a friend" signal, or an optional trusted-person (Wali-style) role. Don't build it before the core works. *Why:* introductions through people and places dominate [S47][S48]; live and admin-mediated matchmaking fills the trust gap [S53][S54]; Muzz events and Wali [S38][S40].
19. **Small schema note:** `dating_preferences` caps ages at 18–70. That excludes older singles, who are a real segment for a worldwide product. Revisit the cap on purpose (repo [S73]).

---

## 5. Open questions for the owner

| # | Question | Recommendation |
|---|---|---|
| Q1 | Which intention options? | **4 options:** Marriage · A committed relationship · Long-term, taking it slowly · Not sure yet. Drop casual, friends and non-monogamy for Dating Mode. They don't fit curated introductions toward a relationship, and they fragment a thin pool. |
| Q2 | Own-gender options for a Ghana-first launch, given the bill? | **Woman / Man**, plus a private optional "I'd describe it differently" (free text). It is never shown, gets the same protection as who-to-meet, and comes with a country note. Get counsel's view on holding such data if the bill becomes law. |
| Q3 | Make liveness verification mandatory? | **Yes, before the first introduction.** Store a pass/fail result only; no face template unless duplicate-account detection is wanted, which needs separate consent. |
| Q4 | Allow faith as a dealbreaker? | **Yes, optional, with explicit consent and the spec §4.1 review.** Without it, faith communities will leave for Muzz or Christian Mingle. |
| Q5 | "Photos after we're both interested" setting? | **Yes, opt-in per user**, with the verified mark always visible. |
| Q6 | Married or separated users, and customary or polygynous marriages? | **Exclude anyone currently married in any form, or separated but not divorced, in v1.** Confirm the wording with the Ghanaian cultural reviewer. |
| Q7 | Daily drop or weekly batch? | **Daily, up to 3, at a fixed local time, with 7-day expiry.** Update spec §6.4. |
| Q8 | Diaspora: match across countries by default? | **Same country by default**, with opt-in "open to someone abroad / long distance" and a "home country" field for diaspora users. |
| Q9 | Collect ethnicity or tribe? | **No, in v1.** If the cultural review asks for it later, it is self-description only and never a filter. |
| Q10 | AI conversational onboarding? | **No, in v1.** Revisit only after the deterministic Alignment preview is calibrated. |
| Q11 | Trusted-person (Wali-style) role or events? | **Defer.** Ship "share my date plan with a trusted contact" first, since it is a safety feature; revisit after the pilot. |
| Q12 | A follow-up research run to close the `[UNVERIFIED]` gaps (AI matchmakers, Japanese apps, Ghana/Nigeria/Kenya statute texts, motion write-ups)? | **Yes, before the spec is finalised.** It takes about 30 searches, and the statute texts matter most. |

---

## Sources

Grades: **S** Strong · **M** Moderate · **W** Weak · **A** Anecdote. "(extract)" means read from a search-result extract because a direct fetch was blocked.

| ID | Source | Grade |
|---|---|---|
| S1 | TechCrunch, "Hinge Dating Intentions", 2022-06-23 — https://techcrunch.com/?p=2341754 | W (vendor stats via press) |
| S2 | TechCrunch, Hinge Relationship Type, 2022-11-16 — https://techcrunch.com/2022/11/16/hinges-new-feature-is-a-small-win-for-users-in-non-monogamy-relationships/amp/ | W |
| S3 | Hinge Help, "How do I edit my profile" — https://help.hinge.co/hc/en-us/articles/360011053094-how-do-i-edit-my-profile (extract) | M (official) |
| S4 | Hinge Help, "Gender and Sexuality on Profiles" — https://help.hinge.co/hc/en-us/articles/36311196515731-Gender-and-Sexuality-on-Profiles (extract); LOS40 México 2025-09-24 (50+ genders, 21 orientations) — https://los40.com.mx/2025/09/24/hinge-llega-a-mexico-para-fomentar-relaciones-autenticas-y-duraderas-todos-los-detalles/?outputType=amp | M / W |
| S5 | Hinge press, "Prompts for LGBTQ daters" — https://hinge.co/press/prompts-for-lgbtq-daters | W (vendor) |
| S6 | Hinge Help Center via extract (4–6 photos by local rules + 3 prompts); see S3 | M (extract) |
| S7 | Global Dating Insights, "Hinge CEO: intentional dating and onboarding…", 2026-06-30 — https://www.globaldatinginsights.com/featured/hinge-ceo-intentional-dating-and-onboarding-set-hinge-apart/ | W (exec statement) |
| S8 | Wikipedia, Hinge (app) — https://en.wikipedia.org/wiki/Hinge_(app) | W |
| S9 | TechCrunch 2018, Most Compatible — https://techcrunch.com/?p=1668547 ; Swipestats — https://www.swipestats.io/blog/hinge-most-compatible | W |
| S10 | Swipestats, Hinge subscription guide — https://www.swipestats.io/blog/hinge-subscription ; The Everygirl — https://theeverygirl.com/hinge-preferred-review/ | W |
| S11 | TechCrunch, "Tinder launches Relationship Goals", 2022-12-14 — https://techcrunch.com/2022/12/14/tinder-launches-relationship-goals-feature ; GDI Explore — https://www.globaldatinginsights.com/news/tinder-expands-explore-page-to-help-users-find-compatible-matches/ | W |
| S12 | Tinder Help, "Powering Tinder: The Method Behind Our Matching" — https://www.help.tinder.com/hc/en-us/articles/7606685697037-Powering-Tinder-The-Method-Behind-Our-Matching (extract) | M (official) |
| S13 | Tinder Help, Gender & Sexual Orientation — https://www.help.tinder.com/hc/en-us/articles/15668360470669-Gender-Sexual-Orientation (extract) | M (official) |
| S14 | Swipestats, "How to Create a Tinder Account", 2026-06-13 — https://www.swipestats.io/blog/create-tinder-account | W |
| S15 | GDI, "Tinder rolls out mandatory Face Check for new UK users", 2026-03-26 — https://www.globaldatinginsights.com/featured/tinder-rolls-out-mandatory-face-check-for-new-uk-users/ ; Bitdefender (face map retention) — https://www.bitdefender.com/en-us/blog/hotforsecurity/tinder-face-check-us-states-what-it-means-for-you | W (vendor figures) |
| S16 | Mediaweek, Tinder Sparks 2026 keynote — https://www.mediaweek.com.au/tinder-unveils-biggest-product-overhaul-in-years-at-sparks-2026-keynote | W |
| S17 | ContentGrip, Tinder Chemistry — https://www.contentgrip.com/tinder-ai-chemistry-matching/ ; Storyboard18 (camera roll) — https://www.storyboard18.com/amp/digital/tinder-turns-to-ai-and-camera-roll-access-to-understand-users-better-83786.htm | W |
| S18 | Bumble, "Basic Info and Interest Badges" — https://bumble.com/the-buzz/bumble-badges | M (official) |
| S19 | Bumble Support (religion/politics "more personal") — https://support.bumble.com/hc/en-us/articles/28530815473949 (extract) | M (extract) |
| S20 | GDI, Bumble freemium filters — https://www.globaldatinginsights.com/news/bumble-introduces-freemium-filters/ ; LinkedIn post on Bumble's 2024 evolution — https://uk.linkedin.com/in/kreska | W |
| S21 | GDI, "Bumble unveils AI assistant Bee and chapter-based profiles", 2026-03-13 — https://www.globaldatinginsights.com/featured/bumble-unveils-ai-assistant-bee-and-chapter-based-profiles/ ; TechCrunch 2026-03-12 — https://techcrunch.com/2026/03/12/bumble-introduces-an-ai-dating-assistant-bee/ ; Lets Data Science — https://letsdatascience.com/news/bumble-replaces-swipe-with-ai-matchmaking-5a8de514 | W |
| S22 | Wikipedia, Bumble (app) — https://en.wikipedia.org/wiki/Bumble_(app) | W |
| S23 | Plus Magazine (Cambridge), "Looking for love" (OkCupid maths) — https://plus.maths.org/content/looking-love ; HackerEarth — https://hackerearth.com/practice/notes/okcupids-matching-algorithm-1 | W |
| S24 | Wikipedia, OkCupid — https://en.wikipedia.org/wiki/OkCupid | W |
| S25 | The Advocate 2015 — https://advocate.com/politics/media/2015/06/29/okcupid-launches-new-gender-inclusive-identity-project ; Match Group — https://mtch.com/?p=1497 | W |
| S26 | eharmony.ca, "What is the Compatibility Quiz" — https://www.eharmony.ca/tour/what-is-the-compatibility-quiz/ ; Vice review — https://www.vice.com/en/via/eharmony-review/ | W |
| S27 | Wikipedia, eHarmony — https://en.wikipedia.org/wiki/EHarmony | W |
| S28 | DatingAdvice, "Sign up for Match" — https://www.datingadvice.com/online-dating/sign-up-for-match ; Daily Evergreen review — https://dailyevergreen.com/116808/mint/dating-app-review-match-com/ | W / A |
| S29 | Swipestats, CMB review (2026-02-22) — https://www.swipestats.io/blog/coffee-meets-bagel-review ; Business Strategy Hub — https://bstrategyhub.com/how-does-coffee-meet-bagel-work/ | W |
| S30 | Wikipedia, Coffee Meets Bagel — https://en.wikipedia.org/wiki/Coffee_Meets_Bagel | W |
| S31 | Wikipedia, Badoo — https://en.wikipedia.org/wiki/Badoo | W |
| S32 | Wikipedia, Happn — https://en.wikipedia.org/wiki/Happn | W |
| S33 | Wikipedia, Facebook Dating — https://en.wikipedia.org/wiki/Facebook_Dating ; TechRadar, Meet Cute — https://www.techradar.com/ai-platforms-assistants/metas-facebook-dating-gets-smarter-with-ai-matchmaking-and-surprise-weekly-meet-cutes | W |
| S34 | Wikipedia, Raya (app) — https://en.wikipedia.org/wiki/Raya_(app) | W |
| S35 | Wikipedia, The League (app) — https://en.wikipedia.org/wiki/The_League_(app) | W |
| S36 | Wikipedia, Lox Club — https://en.wikipedia.org/wiki/Lox_Club | W |
| S37 | Timeleft — https://www.timeleft.com/ | W (vendor) |
| S38 | App Store, "Muzz: Where Muslims Marry" — https://apps.apple.com/us/app/muzz-where-muslims-marry/id969997496 | W (vendor) |
| S39 | Wikipedia, Muzz — https://en.wikipedia.org/wiki/Muzz_(dating_app) | W |
| S40 | Arab News Pakistan, 2024-08-24 — https://www.arabnews.pk/pakistan/pakistani-singles-search-for-spouses-in-person-on-marriage-app-for-muslims-2568634 | W / A |
| S41 | GDI, "Muzz officially launches in India", 2026-04-23 — https://www.globaldatinginsights.com/featured/muzz-officially-launches-in-indias-muslim-marriage-market/ | W |
| S42 | Seneweb (sect, practice, marriage timeframe) — https://www.seneweb.com/en/news/Societe/saint-valentin-pour-trouver-lame-soeur-a-chaque-religion-ses-applis_n_483387.html ; ProPakistani #NiyyatSaafHai (Marriage Intentions) — https://propakistani.pk/lens/muzz-launches-bold-new-campaign-niyyatsaafhai/ | W |
| S43 | Shaadi Support: compulsory fields — https://support.shaadi.com/support/solutions/articles/48000962494 ; edit limits — https://support.shaadi.com/support/solutions/articles/48000755435-i-want-to-edit-the-details-on-my-profile ; registration — https://support.shaadi.com/support/solutions/articles/48000962393-how-can-i-register-on-shaadi-com- ; "not listed" — https://support.shaadi.com/support/solutions/articles/48000962495 ; family — https://support.shaadi.com/support/solutions/articles/48001202981 | M (official) |
| S44 | Scribd upload listing Shaadi form options — https://www.scribd.com/document/876647984/Community | A |
| S45 | Wikipedia, Christian Mingle — https://en.wikipedia.org/wiki/Christian_Mingle | W |
| S46 | Wikipedia, JSwipe — https://en.wikipedia.org/wiki/JSwipe | W |
| S47 | Sagaci Research, online dating in Africa (SagaPoll, n=13,557, 27 countries, Oct 2024; updated Jun 2025) — https://sagaciresearch.com/?p=21066 | M (large online panel) |
| S48 | TechCabal on Zikoko *State of Love* 2026 (n>10,000 Nigerians) — https://techcabal.com/2026/03/02/zikoko-state-of-love-report/ (extract) ; Blueprint — https://blueprint.ng/one-in-2-nigerians-admit-to-cheating-zikokos-state-of-love-report-reveals/ | M (large survey; method not inspected) |
| S49 | Sensor Tower Ghana Q1 2024 — https://sensortower.com/blog/2024-q1-unified-top-5-dating-units-gh-64c9b6bbe1714cfff1c9d0e8 ; Q3 2024 — https://sensortower.com/blog/2024-q3-unified-top-5-dating-units-gh-64c9b6bbe1714cfff1c9d0e8 | W (AI-written estimates) |
| S50 | Sensor Tower Nigeria Q1 2024 — https://sensortower.com/blog/2024-q1-unified-top-5-dating-units-ng-64c9b6bbe1714cfff1c9d0e8 ; Q4 2024 Android — https://sensortower.com/blog/2024-q4-android-top-5-dating-units-ng-64c9b6bbe1714cfff1c9d0e8 | W |
| S51 | Sensor Tower Kenya Q2 2024 — https://sensortower.com/blog/2024-q2-unified-top-5-dating-units-ke-64c9b6bbe1714cfff1c9d0e8 ; Q3 2024 Android — https://sensortower.com/blog/2024-q3-android-top-5-dating-units-ke-64c9b6bbe1714cfff1c9d0e8 | W |
| S52 | Sensor Tower South Africa Q2 2025 — https://sensortower.com/blog/2025-q2-unified-top-5-dating-revenue-za-64c9b6bbe1714cfff1c9d0e8 ; News24, 2026-01-08 — https://www.news24.com/truelove/she-lives/relationships/how-to-navigate-dating-apps-in-mzanzi-20260108-0796 | W |
| S53 | BusinessDay (Nigeria), creator-led live matchmaking — https://businessday.ng/?p=1166143 | W |
| S54 | Prime Progress (northern Nigeria FB group) — https://primeprogressng.com/?p=3447 ; AFP via Nordot (Kano) — https://nordot.app/1394939234981675141 ; TechPoint (Lagos Matchmaker) — https://techpoint.africa/feature/didi-warmate-lagos-matchmaker/ | W / A |
| S55 | NewsGhana (CSA figures) — https://www.newsghana.com.gh/romance-scams-are-draining-ghanaian-women-of-millions-and-feeding-criminal-networks/ ; Rainbow Radio (sextortion, CSA) — https://rainbowradioonline.com/2025/05/02/financial-loses-through-blackmail-sextortion-near-gh%C2%A2500000-in-early-2025-csa/ ; Citi Newsroom (EOCO) — https://www.citinewsroom.com/2025/03/eoco-raises-alarm-over-rising-romance-scams/ ; Starr FM (Kasoa raid) — https://starrfm.com.gh/kasoa-romance-scam-32-nigerians-arrested ; ModernGhana (CSA H1 2025) — https://www.modernghana.com/news/1467172/cybercrime-in-ghana-a-growing-digital-threat.html | M–W (official figures via press) |
| S56 | PinkNews 2026-06-01 — https://www.thepinknews.com/2026/06/01/ghanas-parliament-approves-anti-lgbtq-bill-that-criminalises-identifying-as-queer/ ; ABC7 — https://abc7news.com/ghanas-parliament-passes-controversial-new-anti-lgbtq-bill/14479690/ ; Wikipedia — https://en.wikipedia.org/wiki/Ghanaian_anti-LGBTQ_bill | M (multiple outlets) |
| S57 | PinkNews 2023 (kito) — https://www.thepinknews.com/2023/05/15/nigeria-lgbtq-dating-apps-kito-robbery/ ; Thomson Reuters Foundation via Devdiscourse — https://www.devdiscourse.com/article/entertainment/2920977-feature-i-had-been-set-up-lgbtq-nigerians-battle-dating-app-traps | W / A |
| S58 | Citi Newsroom 2019 (Kasoa) — https://citinewsroom.com/2019/01/15/two-arrested-in-kasoa-for-blackmailing-and-defrauding-gay-men/ ; LA Blade 2023 (Johannesburg) — https://www.losangelesblade.com/2023/09/26/seven-men-linked-to-kidnapping-of-grindr-users-in-south-africa-arrested/ | W |
| S59 | Grindr, "Assessing and Mitigating Risk for the Global Grindr Community" (2021, updated 2026-10-18) — https://grindr.com/blog/mitigating-risk-for-the-global-grindr-community | W (vendor; primary) |
| S60 | Wikipedia, Grindr — https://en.wikipedia.org/wiki/Grindr ; PinkNews 2019 — https://www.thepinknews.com/2019/12/12/grindr-new-safety-features-gay-bi-homophobia-lgbt-hate-countries-scott-chen/ ; netzpolitik — https://netzpolitik.org/?p=230445 | W |
| S61 | Forbrukerrådet, "Grindr loses appeal" — https://www.forbrukerradet.no/news-in-english/grindr-loses-appeal/ ; PPC Land — https://ppc.land/norwegian-court-upholds-eu6-5m-grindr-fine-for-data-sharing-violations/ | M (court ruling) |
| S62 | Article 19, *Apps, arrests and abuse in Egypt, Lebanon and Iran* (Feb 2018) — https://www.article19.org/resources/apps-arrests-abuse-egypt-lebanon-iran/ (extract) | M (NGO qualitative research) |
| S63 | Mozilla Foundation, *Privacy Not Included* dating apps, 2024-04-23 — https://www.mozillafoundation.org/en/blog/everything-but-your-mothers-maiden-name-mozilla-research-finds-majority-of-dating-apps-more-data-hungry-and-invasive-than-ever/ | M (systematic policy review) |
| S64 | Mozilla PNI, Lex — https://www.mozillafoundation.org/en/privacynotincluded/lex/ (extract) | M (extract) |
| S65 | 7x7 (HER) — https://www.7x7.com/lesbian-dating-app-dattch-rebrands-and-expands-as-her-1787164428.html ; Swipestats HER review — https://www.swipestats.io/blog/her-dating-app-review | W |
| S66 | Wikipedia, Taimi — https://wikipedia.com/wiki/Taimi ; Taimi FAQ — https://www.slimfaq.com/taimi/4171-taimi-protect/17467-what-is-taimi-protect | W |
| S67 | Tawkify, How it works — https://www.tawkify.com/how-it-works | W (vendor) |
| S68 | GDPR Art. 9 — https://gdpr-info.eu/art-9-gdpr/ | M (statute) |
| S69 | POPIA s.26 — https://popia.co.za/section-26-prohibition-on-processing-of-special-personal-information/ | M (statute) |
| S70 | Kenya Data Protection Act 2019, s.2 "sensitive personal data" — http://kenyalaw.org/kl/fileadmin/pdfdownloads/Acts/2019/TheDataProtectionAct__No24of2019.pdf (fetch blocked; content from prior knowledge) | `[UNVERIFIED]` — verify with counsel |
| S71 | Ghana Data Protection Act 2012 (Act 843), "special personal data" (not fetched) | `[UNVERIFIED]` — verify with counsel |
| S72 | Nigeria Data Protection Act 2023, "sensitive personal data" (not fetched) | `[UNVERIFIED]` — verify with counsel |
| S73 | Attune repo (read-only): `lib/architecture/DATING_MODE_SPEC.md` §1, §2.1, §3.4, §4.1–4.3, §5, §6.1–6.4; `lib/architecture/DATING_MODE_CULTURAL_REVIEW_PACKET.md`; `supabase/migrations/20260705210000_dating_mode_v1_2_hardening.sql` (`dating_profile_ready`, `save_dating_profile_draft`); `supabase/migrations/20260933170000_dating_candidate_generation.sql` (`dating_pair_passes_hard_filters`, symmetric hard filters); `lib/architecture/attune/ATTUNE_RISK_SOLUTIONS.md` §5 (regulatory perimeter, SDK audit) | Internal |
| S76 | Built for Mars, Hinge case study (intro only; body paywalled) — https://builtformars.com/case-studies/hinge | W |

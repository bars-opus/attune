# 04 — Dating safety, trust and law, worldwide

**Researcher:** 04 · **Date:** 2026-10-24 · **Programme:** Flow + Dating research (see `BRIEF.md`)
**Scope:** safety, trust and legal requirements for a curated-introductions dating mode with phone sign-in, date of birth for everyone, a private "who you want to meet", country-aware safety notes and a separate dating chat, launched worldwide with Ghana and the diaspora first.

**Evidence grades** (from the brief): **[S]** Strong (meta-analysis, large RCT, large dataset) · **[M]** Moderate (peer-reviewed study, large survey, official policy or statute) · **[W]** Weak (single small study, press, vendor claim) · **[A]** Anecdote.
**[BK]** marks a claim taken from my background knowledge and **not re-verified in this session** (see §1 limits). Treat every [BK] item as something to check before relying on it.

---

## 1. How this was researched

**Repo (read-only):**
- `lib/architecture/DATING_MODE_SPEC.md` v1.3
- `DATING_CHAT_SAFETY_SPEC.md` (draft, 2026-09-04)
- `DATING_MODE_DATING_CHAT_SAFETY_PLAN.md`
- `DATING_MODE_CULTURAL_REVIEW_PACKET.md`
- `DATING_MODE_RELEASE_READINESS_CHECKLIST.md`
- `docs/reviews/DATING_REVIEW_FABLE.md`, including the two fix re-reviews
- `docs/superpowers/specs/2026-08-02-dating-photo-verification-design.md`
- `AUTH_ONBOARDING_ENGINE.md`, sections on phone and OTP
- The dating migration list, and a grep of the gender, preference and region columns and of `20260933170000_dating_candidate_generation.sql`
- `lib/features/safety/**`: quick exit and the resources screen
- `lib/features/dating/presentation/screens/dating_verification_screen.dart`
- Couples research `06-synthesis-roadmap.md`, safety floor F10–F17

**Web:**
- About 60 web searches and about 45 page fetches, covering:
  - legal databases: Human Dignity Trust and ILGA World;
  - rights reports: HRW and Amnesty;
  - regulators: Ofcom, the European Commission, FTC, Datatilsynet, Ghana CSA and the Ghana DPC;
  - platform and store policy: Apple and Google;
  - vendor pages: Yoti, AWS and Smile ID;
  - company newsrooms: Grindr, Tinder, Hinge and Bumble;
  - large datasets: NCMEC/Thorn, FTC Consumer Sentinel, Action Fraud and Pew;
  - investigative press: The Guardian, TechCrunch, Thomson Reuters Foundation and Meduza.

**Limits, stated plainly:**
1. **The search budget ran out partway through.** It is a cap shared across the parallel researchers. After that I used page fetches only, and several were blocked or timed out:
   - unreachable: eSafety, RAINN, Hornet support, Persona, Veriff, Kenya Law, the NDPA PDF and the Datatilsynet decision page;
   - unreadable: the ILGA database, which renders via JavaScript.

   So the following rest on background knowledge and are tagged **[BK]**:
   - statute section numbers for Ghana, Nigeria, Kenya and India;
   - the Australian code's detailed clauses;
   - a few product facts: Tinder Face Check, Noonlight/Garbo and Bumble Deception Detector.
2. **HER.** I found nothing on its country-specific protections. Unknown.
3. **Ghana's bill.** The final text of the May 2026 version was not available. Provisions are quoted from coverage of the 2024 text plus reporting on the 2025/26 revisions.
4. **No legal advice.** This is research, not legal advice. Several implications call for a Ghanaian and a UK/EU lawyer.
5. **No user data.** No Ghanaian user interviews were possible.

---

## 2. Findings

### 2.1 Same-gender relationships: legal and entrapment risk

#### 2.1.1 The global legal picture

| Finding | Grade | Source |
|---|---|---|
| 65 UN member States criminalise consensual same-sex acts. The total rose in 2025 for the first time in almost a decade (Burkina Faso criminalised; Trinidad & Tobago reversed decriminalisation). | [M] | [ILGA World, 1 Jun 2026](https://ilga.org/news/pride-month-2026-lgbti-maps-data/) |
| Death penalty: legally prescribed in 7 UN member States, plus 5 more without full legal certainty. | [M] | ILGA World, as above |
| Senegal tightened its law, "triggering arrests and violence". Malaysia blocked LGBTI dating-app websites. At least 63 States restrict LGBTI expression; Kazakhstan and Belarus adopted "propaganda"-style bans. Türkiye is reportedly drafting a ban on "conduct contrary to biological sex". | [M] | ILGA World, as above |
| The Human Dignity Trust lists **66 jurisdictions**: 33 Africa, 22 Asia, 5 Caribbean/Americas, 6 Pacific. It tags death penalty in 12, including Nigeria (northern states), Uganda, Mauritania, Somalia, Iran, Saudi Arabia, Yemen, Afghanistan, Brunei, Qatar, UAE and Pakistan; for some of these it is only a legal possibility. It counts women criminalised in 41–42. | [M] | [Human Dignity Trust map, 2026](https://www.humandignitytrust.org/lgbt-the-law/map-of-criminalisation/) |
| The count gap (65 vs 66) is consistent with Niger. Its new penal code (Ordonnance 2026-09) was gazetted on 11 Jun 2026, after ILGA's post, with 5–10 years reported; AFP reports up to 20. | [W] | [Human Dignity Trust news](https://www.humandignitytrust.org/news/niger-criminalises-same-sex-intimacy-for-the-first-time-in-its-history/); [Front Line Defenders](https://frontlinedefenders.org/es/node/9319) |

**Regional reading for Attune.**
- **West Africa is where the trend is worsening fastest:**
  - Mali criminalised in Dec 2024;
  - Burkina Faso in 2025;
  - Niger in 2026;
  - Senegal doubled its maximum to 10 years in Mar 2026;
  - Ghana's bill passed Parliament in May 2026 (§2.1.2).
- **Every diaspora hub is legal:** UK, US, Canada, Germany, Netherlands, Italy, South Africa.
- **Gulf migrant destinations carry the death penalty or severe penalties:** UAE, Qatar, Saudi Arabia.

#### 2.1.2 Ghana's anti-LGBTQ bill (2021–2026)

| Date | Event | Grade | Source |
|---|---|---|---|
| Current law | Criminal Offences Act 1960 s.104 "unnatural carnal knowledge": a misdemeanour, reported as up to 3 years. | [W] | [PinkNews 2019](https://thepinknews.com/2019/01/15/two-arrested-grindr-blackmail-rob-gay-men-ghana/); s.104 itself is [BK] |
| 28 Feb 2024 | Parliament passed the Promotion of Proper Human Sexual Rights and Ghanaian Family Values Bill. | [M] | [Wikipedia summary](https://en.wikipedia.org/wiki/Ghanaian_anti-LGBTQ_bill) |
| 18 Dec 2024 | Supreme Court dismissed the challenges. | [M] | Wikipedia, as above |
| Dissolution | President Akufo-Addo never assented, and the bill lapsed when Parliament dissolved. | [M] | [Pulse GH](https://pulse.com.gh/story/ghana-parliament-reconsider-anti-lgbtq-bill-bagbin-2026102314181010523) |
| 2025–Feb 2026 | Reintroduced as the Human Sexual Rights and Family Values Bill, 2025. | [W] | [ModernGhana timeline](https://www.modernghana.com/blogs/1497726/the-legislative-journey-of-ghanas-human-sexual.html) |
| 29 May 2026 | Parliament passed it by voice vote. Critics question quorum: about 32 of 276 MPs were reportedly present. | [W] | [openDemocracy](https://www.opendemocracy.net/ghanas-anti-lgbtq-bill-passes-amid-chaos-as-laws-backers-call-for-recall/); [GNA](https://gna.org.gh/2026/05/the-anti-lgbtq-bill-ghanas-most-divisive-law-in-a-decade/) |
| 1 Jun 2026 | President Mahama at Chatham House: "there's still quite a while to go before that bill becomes law". The Attorney-General will review it first. | [W] | [Citi Newsroom](https://www.citinewsroom.com/2026/06/anti-lgbtq-bill-still-far-from-becoming-law-mahama/) |
| 23 Oct 2026 | Speaker Bagbin: the bill will get a "second consideration" at the next meeting to fix errors in last-minute amendments, then be passed. **Not law as of today.** | [W] | [Pulse GH, 23 Oct 2026](https://pulse.com.gh/story/ghana-parliament-reconsider-anti-lgbtq-bill-bagbin-2026102314181010523) |

**Provisions reported for the 2024 text** ([Wikipedia](https://en.wikipedia.org/wiki/Ghanaian_anti-LGBTQ_bill), [W]):
- up to 3 years for same-sex relations and for *identifying* as LGBTQ;
- 3–5 years for "promoting" or supporting LGBTQ activities;
- 6 months to 1 year for a public show of same-sex romance.

Two points matter most for Attune:
- **Digital platforms:** owners of "digital platforms or physical premises" where LGBT+ groups organise are treated as promoters.
- **2025/26 changes (as reported):** exemptions for health workers, lawyers and journalists; promotion penalties raised to 5–10 years ([JURIST via search summary](https://www.jurist.org/news/2026/06/ghana-dispatch-parliament-passes-anti-lgbtq-bill-awaits-presidential-approval/), [W]).

**Implication:** if the bill is enacted with that platform clause, offering same-gender matching inside Ghana could expose Attune's owner, and any Ghana-based staff, to prosecution. That needs a Ghanaian legal opinion before launch (§4 Q1).

#### 2.1.3 How app-based entrapment actually works

| Country | Documented pattern | Grade | Source |
|---|---|---|---|
| **Ghana** | Organised gangs of 2–15 people use a shared "playbook". They pose as gay on Grindr, Facebook, TikTok, Snapchat and WhatsApp groups, lure victims to isolated places, beat and rob them, record nude videos and forced "confessions", then blackmail them and post the videos. Cases reported to Rightify Ghana rose to **300 in 2024** (3× the previous year); >120 in early 2025, plus >200 at two other groups. Grindr is named most often. Police are indifferent or extort victims further. | [W] investigative press | [The Guardian, 10 Oct 2025, republished by 76crimes](https://76crimes.com/2026/01/29/torture-blackmail-extortion-the-dangers-of-queer-online-dating-in-ghana/) |
| Ghana | 2019: two men arrested for using Grindr to rob men at knifepoint and film them for blackmail. 2022: Rightify director kidnapped for ransom by an "organized anti-gay group". | [W] | [Attitude](https://www.attitude.co.uk/news/world/two-men-arrested-after-using-grindr-to-rob-and-blackmail-men-in-ghana-298016); [76crimes 2022](https://76crimes.com/2022/08/28/ghana-homophobes-kidnap-lgbtq-rights-leader/) |
| **Nigeria** | "Kito": violent entrapment via dating apps by organised gangs working from serviced apartments with POS machines. One victim was asked for ₦1m under threat of exposure. Up to 14 years under federal law means victims rarely report. | [W] | [Context/Thomson Reuters Foundation, Apr 2024](https://www.context.news/digital-rights/lgbtq-nigerians-using-apps-like-grindr-caught-in-dating-traps) |
| **Egypt** | Police create fake profiles on Grindr, WhosHere, Facebook and WhatsApp, arrest people at meetings, and search their phones. All 15 people HRW interviewed reported abuse in custody. Charges are brought under the "debauchery" law. WhosHere removed its "seeking same sex" option in Egypt. | [M] HRW; [W] press | [NBC on HRW 2020](https://www.nbcnews.com/feature/nbc-out/egyptian-officials-systemically-abuse-torture-gays-rights-group-says-n1244755); [Telegraph 2023](https://www.pressreader.com/uk/the-daily-telegraph/20230131/281973201794615) |
| **Egypt, Iraq, Jordan, Lebanon, Tunisia** | Security forces entrap people on social media and dating apps, and use photos, chats and app presence found on phones as the basis for prosecution. Private individuals extort and out people too. Based on 90 interviews with affected people plus 30 expert interviews. | [M] | [HRW, "All This Terror Because of a Photo", 21 Feb 2023](https://www.hrw.org/report/2023/02/21/all-terror-because-photo/digital-targeting-and-its-offline-consequences-lgbt) |
| **Tunisia** | At least 84 arrests between 26 Sep 2024 and 31 Jan 2025, probably about a third of real cases. Phones were "taken and searched illegally". From Jul 2025, 71 arrests and 32 sentenced, with dating-app messages used as evidence. | [M] Amnesty; [W] NGO counts | [Amnesty, Feb 2025](https://www.amnesty.org/en/latest/news/2025/02/tunisia-authorities-step-up-crackdown-on-lgbti-individuals-with-wave-of-arrests/); [76crimes/Damj, Nov 2025](https://76crimes.com/2025/11/06/more-than-70-arrested-in-tunisias-anti-lgbt-crackdown/) |
| **Lebanon** | Abuse at military checkpoints when soldiers recognised the Grindr icon on a phone. This led to Grindr's disguised icon, built with Article 19 and The Guardian Project. | [W] | [Grindr risk blog](https://grindr.com/blog/mitigating-risk-for-the-global-grindr-community) |
| **Morocco** | Apr 2020: an influencer urged 600k+ followers to make fake Grindr and PlanetRomeo profiles to out men. Up to 100 were outed, people were evicted, and suicides were reported. PlanetRomeo removed profiles created after 13 Apr. | [W] | [NBC News 2020](https://www.nbcnews.com/news/amp/ncna1195866) |
| **Russia** | "International LGBT movement" declared extremist (Nov 2023). In Dagestan in 2024, the police anti-extremism centre forced a man to entrap others via Hornet. Apr 2026: 16 men arrested over a VK queer-dating group, charged with extremism. | [W] | [Novaya Gazeta, Jul 2024](https://novayagazeta.eu/en/articles/2024/07/01/gay-man-arrested-in-dagestan-says-police-offered-him-money-to-entrap-other-men-en-news); [Meduza, 30 Apr 2026](https://meduza.io/en/news/2026/04/30/report-russian-police-arrest-16-men-over-queer-dating-group-on-russian-social-network-vk-charging-them-with-extremism) |
| **Indonesia** | 2025 raids under the pornography law: Jakarta (56 arrested), Bogor (75, HIV-tested) and Surabaya (34). Phones were seized as evidence. Grindr rates Indonesia Level 5 (blocked). | [M] Amnesty; [W] press | [Amnesty AU](https://www.amnesty.org.au/indonesia-lgbti-people-must-be-released-after-discriminatory-police-raid/); [Indoleft](https://www.indoleft.org/news/2025-06-24/police-raid-gay-party-at-villa-in-puncak-75-people-arrested.html) |
| **Malaysia** | Grindr and Blued websites blocked on 25 Feb 2026; the regulator is weighing action against the apps. Penalties up to 20 years plus whipping. | [W] | [PinkNews, 25 Feb 2026](https://www.thepinknews.com/2026/02/25/malaysia-blocks-grindr-and-blued-and-may-limit-more-lgbtq-dating-apps/) |
| **Uganda** | The Anti-Homosexuality Act 2023 includes the death penalty for "aggravated homosexuality". The Constitutional Court upheld it on 3 Apr 2024, striking only ss.3(2)(c), 9, 11(2)(d) and 14, including the duty to report. | [M] | [HRW, Apr 2024](https://www.hrw.org/news/2024/04/04/uganda-court-upholds-anti-homosexuality-act) |
| South Africa (legal) | A student was held hostage after a dating-app "date" (2023). Legal countries also have lure-robbery gangs. | [W] | [IOL 2023](https://iol.co.za/the-star/news/2023-09-22-wits-student-taken-hostage-looking-for-love/) |

**The common mechanics, which Attune's design must break:**
1. **A fake profile** is created to find people who seek the same gender.
2. **A fast move to an in-person meeting** follows, often at a private address.
3. **Violence, filming and extortion** follow the meeting, with payment by mobile money or bank transfer.
4. **The phone is searched** at arrest, at checkpoints or by family. App presence, chats and photos become evidence.

Rigot's analysis of digital evidence in Egypt, Lebanon and Tunisia found that device-derived evidence dominates these prosecutions ([Belfer Center, "Digital Crime Scenes", 2022](https://www.belfercenter.org/publication/digital-crime-scenes-role-digital-evidence-persecution-lgbtq-people-egypt-lebanon-and), [M]; detail [BK]). **On-device minimisation is therefore as important as server-side protection.**

#### 2.1.4 What LGBTQ-serving apps do

| App | Protection | Grade | Source |
|---|---|---|---|
| **Grindr** | A **five-tier country system** built from the ILGA State-Sponsored Homophobia report, ILGA-Europe Rainbow Map and local networks:<br>• **L5** (app banned or blocked: Indonesia, Turkey, North Korea): safety resources translated into local languages.<br>• **L4** (active emergency, e.g. Egypt 2017, Syria): Show Distance disabled, free safety features, **daily** risk push alerts.<br>• **L3** ("extremely unsafe"): distance disabled, **weekly** alerts.<br>• **L2** (e.g. Eswatini, Singapore): resources only.<br>• **L1** (e.g. Malta): nothing tier-specific.<br>Published 2021; page updated 18 Oct 2026. | [W] company | [Grindr blog](https://grindr.com/blog/mitigating-risk-for-the-global-grindr-community) |
| Grindr | Discreet icon (notepad or calculator), now global; PIN; unsend; expiring photos; screenshot blocking, all released to every user "because users anywhere can become targets". | [W] | Same; [Global Dating Insights](https://www.globaldatinginsights.com/news/grindr-makes-discreet-icon-safety-feature-available-worldwide/) |
| Grindr | "Holistic Security Guide" in English, French, Spanish, Arabic, Russian, **Nigerian Pidgin**, Kiswahili and Bahasa Indonesia. | [W] | [SBS](https://www.sbs.com.au/voices/article/grindr-has-introduced-protections-for-users-in-anti-lgbt-countries/db6vwrkr7); the guide page itself returned 404 |
| Grindr (2014) | Distance hidden by default in Russia, Egypt, Saudi Arabia, Nigeria, Liberia, Sudan and Zimbabwe. Researchers bypassed it by spoofing location, because **the server still returned the data**. Grid *ordering* still leaks approximate distance. | [W] | [CSO Online 2014](https://www.csoonline.com/article/2604777/grindr-vulnerability-places-men-in-harms-way.html) |
| **Hornet** | Distance shown randomised and can be switched off. Unverified users' messages go to a separate requests inbox. Its anti-LGBTQ-country guide says to log out and delete the app when not in a safe place. | [W] | [Hornet support (search snippet)](https://hornetapp.com/contributors/support/article/safety-tips-anti-lgbtq-country); [New America](https://newamerica.org/weekly/queer-dating-apps-need-protect-their-users-better) |
| **Tinder** "Traveler Alert" (2019) | In about 70 criminalising countries, LGBTQ users are **hidden automatically** and can choose to become visible. Gender identity and orientation stay hidden even when visible. | [W] | [NBC News 2019](https://www.nbcnews.com/feature/nbc-out/tinder-introduces-safety-feature-protect-lgbtq-travelers-n1034191) |
| **WhosHere** | Removed "seeking same sex" in Egypt. | [W] | Telegraph 2023, above |
| **HER** | **Unknown.** No sources found. | — | — |

#### 2.1.5 Location is the most-exploited leak

- **KU Leuven, 2024.** Dhondt and Le Pochat studied 15 dating apps. All 15 leaked some sensitive data beyond what users publish. Six were open to trilateration: Badoo, Bumble, Grindr, happn, Hinge and Hily. Grindr narrowed users to a 111 × 111 m area, and "oracle trilateration" reached about 2 m ([TechCrunch, Jul 2024](https://techcrunch.com/2024/07/31/bumble-and-hinge-allowed-stalkers-to-pinpoint-users-locations-down-to-2-meters-researchers-say), [M]; the paper's venue was not confirmed this session).
- **Raw, May 2025.** An IDOR flaw exposed street-level coordinates alongside dates of birth and sexual preferences ([TechCrunch](https://techcrunch.com/2025/05/02/dating-app-raw-exposed-users-location-data-personal-information/), [W]).
- **Attune is already structurally better here.** It stores a coarse `city_region_code` and never GPS or distance (spec §4.1, §13.1). But the column is **free text of 1–80 characters** (`20260705210000:460`). That means a user can type a neighbourhood, and the server cannot derive a country risk tier from it (§2.7).

#### 2.1.6 Country list with risk tiers

**Tier criteria.** These are proposed rules, explicit so they can be versioned and reviewed:
- **Tier 1, Severe:** same-sex acts criminalised **and** one or more of the following:
  - the death penalty in law;
  - documented state or organised entrapment via apps or devices since 2020;
  - app or website blocking amid a crackdown.
  
  A country is also Tier 1 if same-sex acts are *not* criminalised but state entrapment via apps is documented.
- **Tier 2, High:** criminalised, with no Tier 1 marker found *in this research*; or not criminalised but under a "propaganda" law or state platform suppression. A missing marker means none was found, not that the country is safe.
- **Tier 3, Standard:** everywhere else. Universal protections still apply. Some Tier 3 countries carry vigilante or lure-robbery risk (South Africa, above).

**Tier 1 — Severe**

| Country | Basis | Source |
|---|---|---|
| **Ghana** | Criminalised. Bill passed May 2026, assent pending and reconsideration announced. Organised gang entrapment via apps. | HDT; Pulse GH 23 Oct 2026; Guardian 10 Oct 2025 |
| **Nigeria** | Criminalised (14 years); death penalty in northern Sharia states; "kito" entrapment. | HDT; Context/TRF Apr 2024 |
| **Egypt** | De facto ("debauchery" law); police fake profiles; device searches. | HRW 2020, 2023 |
| **Tunisia** | Art. 230; arrest waves 2024–25; dating-app messages used as evidence. | HDT; Amnesty Feb 2025; Damj via 76crimes |
| **Lebanon** | Art. 534; digital targeting; checkpoint phone checks. | HDT; HRW 2023; Grindr blog |
| **Morocco** | Art. 489; 2020 mass outing via fake app profiles. | HDT; NBC 2020 |
| **Iraq** | Criminalised (2024 amendment, [BK]); digital targeting. | HDT; HRW 2023 |
| **Jordan** | Not criminalised, but security-force digital targeting is documented. | HRW 2023 |
| **Russia** | Not criminalised; LGBT "extremism" ruling; police entrapment via Hornet and VK. | Novaya Gazeta 2024; Meduza 2026 |
| **Indonesia** | Criminalised in parts (HDT); Grindr L5 (blocked); 2025 raids. | HDT; Grindr; Amnesty AU 2025 |
| **Malaysia** | Criminalised (up to 20 years + whipping); Grindr and Blued websites blocked 2026. | HDT; PinkNews Feb 2026; ILGA 2026 |
| **Türkiye** | Not criminalised; Grindr blocked (L5); criminalisation reform reported. | Grindr blog; ILGA 2026 |
| **Uganda** | AHA 2023 with death penalty; upheld 2024. | HDT; HRW Apr 2024 |
| **Senegal** | Maximum doubled to 10 years plus a promotion offence (Mar 2026); arrests and violence. | [TimesLive/Reuters, 12 Mar 2026](https://www.timeslive.co.za/news/africa/2026-03-12-senegal-doubles-maximum-penalty-for-same-sex-activity-to-10-years-jail/); ILGA 2026 |
| **Niger** | First criminalisation in 2026 (5–10 years, reports up to 20). | HDT; FLD; AFP Jun 2026 |
| **Mali** | Criminalised from Dec 2024 (new penal code). | [HDT Mali profile](https://www.humandignitytrust.org/country-profile/mali) |
| **Burkina Faso** | First criminalisation in 2025. | ILGA 2026 |
| **Iran, Saudi Arabia, Yemen, Afghanistan, Brunei, Mauritania, Somalia, Qatar, UAE, Pakistan** | Death penalty in law; for some, only a legal possibility. | HDT |
| **Syria** | Criminalised; Grindr L4 example (emergency). | HDT; Grindr blog |

**Tier 2 — High**

| Group | Countries | Source |
|---|---|---|
| Criminalised, Africa | Algeria, Burundi, Cameroon, Chad, Comoros, Eritrea, Eswatini, Ethiopia, Guinea, **Kenya** (Family Protection Bill pending, [CIVICUS](https://lens.civicus.org/interview/the-family-protection-bill-threatens-to-escalate-violence-against-lgbtqi-people/)), Liberia, Libya, Malawi, Sierra Leone, South Sudan, Sudan, Tanzania, The Gambia, Togo, Zambia, Zimbabwe | HDT |
| Criminalised, Asia | Bangladesh, Kuwait, Maldives, Myanmar, Oman, Palestine (Gaza), Sri Lanka, Turkmenistan, Uzbekistan | HDT |
| Criminalised, Caribbean | Grenada, Guyana, Jamaica, Saint Vincent & the Grenadines, **Trinidad & Tobago** (re-criminalised 2025) | HDT; ILGA 2026 |
| Criminalised, Pacific | Kiribati, Papua New Guinea, Samoa, Solomon Islands, Tonga, Tuvalu | HDT |
| Propaganda or suppression | Belarus, Kazakhstan ("propaganda" bans); China (platform suppression; Blued removed from the App Store in China, Nov 2025, [SCMP](https://www.scmp.com/news/asia/southeast-asia/article/3344601/malaysia-blocks-grindr-blued-amid-rising-lgbtq-restrictions)) | ILGA 2026 |

**Tier 3 — Standard.** All other countries, including every diaspora hub: UK, Ireland, US, Canada, Germany, Netherlands, Italy, France, South Africa.

**Keeping this list current.** It should become versioned server configuration, with `source_url` and `reviewed_at` on each row. Laws changed in five countries in 2025–26 alone: Burkina Faso, Trinidad, Senegal, Niger and Saint Lucia. ILGA updates annually, so a quarterly review is the minimum.

#### 2.1.7 Design patterns that keep people safe (evidence → pattern)

| Pattern | Evidence it addresses | Attune status |
|---|---|---|
| **Orientation never public**: no label; gender shown only by explicit choice; preference never displayed | Outing via profile; Tinder hides orientation in criminalising countries | ✅ Spec §4.1; `gender_visible` defaults to false; preferences never in payloads |
| **No exact location or distance; no distance-sorted grid** | Trilateration (KU Leuven); server-side leak (Grindr 2014) | ✅ City/region only. ⚠️ Free-text field (§2.7) |
| **Auto-hide in high-risk places, with opt-in visibility** | Tinder Traveler Alert | ❌ No country awareness |
| **Country risk alerts and resources by tier** | Grindr L3/L4 alerts | ❌ Resources are a static 3-country list (`safety_resources_screen.dart:121–148`); F10 country routing not built |
| **Discreet icon** | Beirut checkpoints (Grindr/Article 19) | ❌ Not found in code |
| **PIN / app lock** | Device seizure | ✅ Spec 2 PIN |
| **Panic wipe / quick exit** that clears caches | Device searches (HRW 2023, Rigot 2022) | ✅ Quick exit to a neutral screen; wipes Together, Map and Stories caches. ❌ **No dating caches in the wipe list** (`quick_exit_service.dart:46–69`) |
| **Disappearing or unsendable messages; screenshot blocking; no auto-save to gallery** | Chat evidence used in prosecutions | ❌ Dating chat not built |
| **Content-free notifications** | Lock-screen outing | ✅ Generic match push (spec §7; Fable M4) |
| **Neutral app identity** | Icon or name recognition | ✅ "Attune" does not say dating — a real advantage over Grindr |
| **Verify before meeting; video call; meet in public; never a private address first** | The universal lure-robbery mechanic | Partly: the guided-date guide exists; no LGBTQ-specific content |
| **Remove the same-gender option where it cannot be made safe** | WhosHere, Egypt | Open question (§4 Q1) |

#### 2.1.8 The structural risk specific to curated, symmetric matching

Attune's hard filter is symmetric: a pair is introduced only if *each* person's `gender_preferences` admits the other's `gender_identity` (`20260933170000_dating_candidate_generation.sql:119–126`). This is correct, and it is what "only mutual matches are introduced" means.

**The consequence is that every same-gender introduction tells the recipient that the other person seeks their gender.** Double-blind *interest* (fixed in Fable C3) does not protect *preference*: the introduction card itself discloses it, along with the first name, age, region and (once built) photos.

A police or gang account seeking men, in Accra, therefore receives a steady stream of verified men who seek men in Accra. Each introduction is an outing event. A few introductions a day across several phone-verified accounts is a slow but complete enumeration tool. Neither grid apps nor this design escape that, but Attune can slow and blunt it:
- withhold photos until mutual interest for same-gender introductions in Tier 1/2;
- cap same-gender introductions for new accounts;
- detect "dragnet" accounts that say Interested to every introduction;
- require liveness.

See Implications 3 and 4.

---

### 2.2 Age verification and minimum-age law

#### 2.2.1 What "18+ with date of birth at sign-up" requires, by jurisdiction

Date of birth at sign-up is **self-declaration**. That alone is acceptable in some places and not in others.

| Jurisdiction | Is self-declared DOB enough for a dating service? | What else is required or expected | Grade / source |
|---|---|---|---|
| **UK — Online Safety Act** | **No.** Ofcom does not count self-declaration as "highly effective age assurance" (HEAA). Ofcom expects most services to conclude children are likely to access them, unless they already use HEAA and can evidence it. Without HEAA a dating service must assume child access and comply with the children's risk-assessment and Protection of Children duties (in force Jul 2025). | Methods that can count as HEAA:<br>• photo-ID matching;<br>• facial age estimation;<br>• mobile-network checks;<br>• email-based estimation;<br>• digital ID;<br>• open banking.<br>Children's access assessments were due 16 Apr 2025. In Dec 2025 **more than 1 in 10 15–17-year-olds were still using three major dating apps** despite their checks. Ofcom wants "challenge-age approaches and liveness detection". A service is in scope if it has a significant number of UK users or targets the UK — the diaspora makes that likely. | [M] [Ofcom age assurance](https://ofcom.org.uk/online-safety/illegal-and-harmful-content/age-assurance); [SCL on Ofcom's final guidance](https://www.scl.org/ofcom-publishes-final-guidance-on-age-checks-to-protect-children-online/); [W] [VerifyMy on Ofcom's Jul 2026 report](https://verifymy.io/blog/ofcom-age-assurance-report-2026/); "links with UK" test [BK] |
| **EU — DSA and GDPR** | Probably not, for a dating platform of any size. | DSA Art. 28 guidelines (14 Jul 2025) recommend effective age assurance: **verification** for adult content, gambling or a national minimum age, **estimation** otherwise. Methods must be "accurate, reliable, robust, non-intrusive, non-discriminatory". The EU age-verification app blueprint is the reference. I recall the final text also recommends verification where the terms set 18+ because of identified risks ([BK]; verify). **Micro and small enterprises are exempt** from Art. 28 and most Section 3 duties (Art. 19, [BK]), but Art. 16 notice-and-action and Art. 17 statements of reasons still apply ([BK]). GDPR Art. 8: digital consent age 13–16. | [M] [European Commission, 14 Jul 2025](https://digital-strategy.ec.europa.eu/en/library/commission-publishes-guidelines-protection-minors) |
| **US — federal** | Yes, for COPPA, if the screen is neutral. | COPPA covers under-13s with actual knowledge. FTC guidance says an age screen must be **neutral**: don't hint at the cut-off and don't allow an easy retry ([BK]). | [BK] |
| **US — states** | No. Platform age signals must also be honoured. | App Store Accountability Acts:<br>• **Texas SB 2420**: effective 1 Jan 2026, but a court challenge was filed and an injunction was reported ([BK], verify);<br>• **Utah** and **Louisiana**: later in 2026;<br>• **California AB 1043**: device-level age signals from 2027 ([BK]).<br>Apple now asks new Texas accounts to confirm 18+; under-18s go into Family Sharing with parental consent. Developers must adopt the **Declared Age Range API**. | [M] [Apple Developer News, 8 Oct 2025](https://developer.apple.com/news/?id=btkirlj8) |
| **Australia** | Not addressed in the sources reached. | The Online Dating Industry Code started on 1 Oct 2024, with enforcement from 1 Apr 2025. It is voluntary, and its signatories are Match, Bumble, Grindr, eharmony, Spark, RSVP and Meet Group. It requires systems to detect online-enabled harm, action against violators up to bans, transparency reports on terminated accounts, faster police escalation for imminent threats, a Code Oversight Body and compliance ratings. I found no age-assurance clause; the full text was not reached. Separately, eSafety removal notices carry a **24-hour** deadline under the Online Safety Act 2021 ([BK]). | [M] [Dept. of Infrastructure](https://www.infrastructure.gov.au/department/media/news/new-industry-code-now-operational-make-online-dating-safer); [Mondaq](https://www.mondaq.com/australia/compliance/1560880/staying-safe-while-finding-love-online-australian-government-appoints-dating-safety-oversight-body-and-implements-new-voluntary-online-safety-code-for-dating-services) |
| **Ghana** | No age-verification mandate found. | Data Protection Act 2012 (Act 843):<br>• **all data controllers must register** with the DPC ([M] [dpc.gov.gh](https://dpc.gov.gh/registration));<br>• s.37 restricts "special personal data", including sexual life, religious belief, ethnic origin and health, and processing of children's data ([BK]).<br>Cybersecurity Act 2020 (Act 1038) offences ([BK] section numbers):<br>• indecent images of children;<br>• cyberstalking of a child;<br>• **sexual extortion**;<br>• **non-consensual sharing of intimate images**.<br>Age of majority is 18. | [M] DPC; statute detail [BK] |
| **Nigeria** | Probably yes at sign-up, with a mechanism required for children. | NDPA 2023: sexual orientation and sex life are sensitive data. Processing a child's (<18) data needs parental consent and "appropriate mechanisms" for age verification "taking into account available technology" (s.30–31, [BK]). | [BK] |
| **Kenya** | Same as Nigeria. | Data Protection Act 2019: "sensitive personal data" includes sex life and sexual orientation (s.2). Child data needs age-verification and parental-consent mechanisms (s.33). Registration with the ODPC. | [BK] |
| **India** | No, if a minor is likely. | DPDP Act 2023 s.9: **verifiable parental consent** for under-18s, and no tracking or behavioural monitoring of children. DPDP Rules notified Nov 2025, phased in over about 18 months. IT Rules 2021: a grievance officer; **24-hour takedown for non-consensual intimate imagery** (r.3(2)(b)). | [BK] |

**Bottom line.**
- Self-declared DOB at sign-up is fine as the **universal screen**.
- **Dating activation needs a real age-assurance step** in the UK (required). It is the defensible choice in the EU and India, and good practice everywhere.
- Attune already plans a camera-only selfie at Dating setup, so the marginal cost is low: add liveness and facial age estimation to that same capture.

#### 2.2.2 App store rules for dating apps

| Store | Requirement | Grade / source |
|---|---|---|
| Apple 1.2 (user-generated content) | Must offer:<br>• "a method for filtering objectionable material";<br>• "a mechanism to report offensive content and **timely responses**";<br>• "the ability to **block** abusive users";<br>• "published contact information".<br>Random or anonymous chat and "hot-or-not" objectification are banned. | [M] [App Store Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) |
| Apple 1.1.4 | "Hookup" apps that may facilitate prostitution or trafficking are prohibited. | [M] same |
| Apple 4.3(b) | Dating is a saturated category. New dating apps must be "meaningfully different". Attune's psychology-first, couples-plus-dating framing helps. | [M] same |
| Apple 5.1.1 | Consent for data collection; minimisation; **in-app account deletion**; a privacy policy saying how to revoke consent. | [M] same |
| Apple age rating | Dating apps were historically rated 17+, now 18+ under the 2025 rating scheme. This matches "Attune is 18+". | [BK] |
| Google Play Child Safety Standards | Apply to **Social and Dating** apps. Requires:<br>• a published, globally accessible CSAE standards page linked in Play Console;<br>• an in-app feedback mechanism;<br>• action on CSAM;<br>• compliance with child-safety laws;<br>• a **named child-safety point of contact**. | [M] [Google Play policy](https://support.google.com/googleplay/android-developer/answer/14747720) |
| Google Play (other) | User-generated content policy: in-app reporting and blocking. Data-deletion policy: an in-app and web deletion path. | [BK] |

#### 2.2.3 Verification vendors and approaches

| Vendor or approach | Approach | Notes for Attune | Grade / source |
|---|---|---|---|
| **AWS Rekognition Face Liveness** | Video-selfie liveness. Detects printed photos, masks, screen replay, and **injection and deepfake** "bypass" attacks. Billed per check. Returns a selfie frame for `CompareFaces` or age estimation. | Attune **already uses Rekognition CompareFaces** (`verify-dating-profile`). Liveness was deferred to v2 in the photo spec §7 and slots in before the same call. | [W] vendor: [AWS](https://aws.amazon.com/rekognition/face-liveness/) |
| **Yoti** | Facial age estimation (FAE) plus document checks plus digital ID. | July 2025 white paper:<br>• mean error 1.1 years for ages 13–17;<br>• 99.3% of 13–17s estimated under 21;<br>• "no discernible bias" across three skin-tone groups (TPR 99.6 / 99.0 / 98.9%);<br>• "all information is instantly deleted".<br>Widely used for UK HEAA. Its challenge age works by sending anyone estimated under the threshold to a fallback check. | [W] vendor: [Yoti](https://www.yoti.com/blog/yoti-age-estimation-white-paper/) |
| NIST FATE age estimation (independent) | Benchmarks FAE algorithms. | Error rates vary by sex and region of birth; independent bias data matters for a Ghana-first app. | [M] [NIST FATE](https://pages.nist.gov/frvt/html/frvt_age_estimation.html); NIST IR 8525 (2024) detail [BK] |
| **Persona, Veriff, Onfido (Entrust), Incode** | Configurable selfie plus document plus liveness; most offer FAE. Persona and Veriff serve dating apps. | Pages unreachable this session; capabilities [BK]. Ask each for skin-tone and West-African error data and for **Ghana Card** support. | [BK] |
| **Smile ID** | Africa-focused. "Government database checks where available, documents plus biometrics where required"; re-authentication; AML screening. No public pricing. | The likeliest ID fallback for Ghana and Nigeria (Ghana Card, NIN). Coverage not confirmed this session. | [W] vendor: [smile.id](https://smile.id/) |
| Phone or SIM checks | Phone OTP. | Weak against determined fakes. Ghana's SIM re-registration linked SIMs to the Ghana Card ([BK]), which makes a phone a moderate identity anchor *in Ghana only*. | [BK] |

**Tinder Face Check (2025)** is a mandatory video-selfie liveness step plus a stored face map to catch duplicate and banned accounts, rolled out in Colombia, India, Canada and California, then wider. It shows the industry direction, but it **stores biometric templates** ([BK]). Attune's current design deliberately stores none (photo spec §4); keep that unless the owner decides otherwise (§4 Q8).

---

### 2.3 Data protection for sensitive data

| Finding | Grade / source |
|---|---|
| **GDPR Art. 9** prohibits processing "data concerning a natural person's sex life or sexual orientation", religious belief, racial or ethnic origin and health, except under Art. 9(2). For a dating app the only realistic basis is **explicit consent** (9(2)(a)): specific, informed, separate from the terms, and withdrawable. Large-scale processing of special categories needs a **DPIA** (Art. 35). A non-EU controller targeting EU users needs an **Art. 27 representative**. Breach notification is due within 72 hours (Art. 33). | [M] statute; [BK] for article detail |
| The CJEU (C-184/20, *OT*, 1 Aug 2022) held that data which **indirectly** reveals sexual orientation is special-category data. For Attune, own gender plus "interested in" reveals orientation; so can being introduced to a same-gender person. | [M] case law; [BK] |
| **Grindr, Norway.** The DPA fined Grindr NOK 65m (2021) for sharing GPS, IP, advertising ID and gender with ad partners without valid consent. It held that "data revealing the fact that someone is a Grindr user strongly indicates that they belong to a sexual minority", so that data is special category. Upheld by the Court of Appeal in Oct 2025, which also called Grindr's "we don't sell data" claim "clearly misleading". | [M] regulator decision, via [Posteo](https://posteo.de/en/news/grindr-to-pay-millions-after-sharing-user-data) |
| **Grindr, UK.** £26m settlement (2 Sep 2026) with about 12,000 UK users over alleged sharing of **HIV status** with third parties, with no admission of liability. | [W] [PinkNews, Sep 2026](https://www.thepinknews.com/2026/09/07/grindr-settlement-uk-2026/) |
| Ghana Act 843, NDPA 2023 and Kenya DPA 2019 all treat sex life or sexual orientation, religion, ethnicity and health as special or sensitive. Some US state privacy laws treat sexual orientation as "sensitive data" requiring **opt-in** consent: Colorado, Connecticut, Virginia and Texas. | [BK] |
| **Biometrics.** Face geometry from `CompareFaces` and liveness is biometric data:<br>• special category under GDPR when used to identify;<br>• under **Illinois BIPA** and **Texas CUBI**, it needs written informed consent and a public retention and destruction schedule before collection, even if the data is transient. | [BK] |

**2025 dating-app leaks: what actually failed**

| Incident | What leaked | Root cause | Attune's equivalent control |
|---|---|---|---|
| **Tea** (Jul 2025) | About 72,000 images, including about **13,000 verification selfies and photo IDs**, with EXIF location; then 1m+ DMs. | A "legacy" Firebase bucket, open, holding data that should have been deleted. | ✅ The verification selfie is deleted in the same edge-function call (photo spec §8). [W] [Tea statement via Simon Willison](https://simonwillison.net/2025/Jul/26/official-statement-from-tea/); [BleepingComputer](https://bleepingcomputer.com/news/security/tea-app-leak-worsens-with-second-database-exposing-user-chats) |
| **M.A.D Mobile** (Jan–Mar 2025): BDSM People, Chica, Pink, Brish, Translove | About 1.5m images from 800–900k users, including **verification images, photos removed by moderators, and DM photos**. | **Hard-coded secrets** in the app gave access to unprotected Google Cloud buckets. It took more than two months to fix after notice. | ✅ Private bucket, signed URLs, no secrets in the client. ⚠️ No secret-scanning gate is evidenced. [W] [Malwarebytes](https://www.malwarebytes.com/de/blog/news/2025/04/intimate-images-from-kink-and-lgbtq-dating-apps-left-exposed-online); [TechRadar](https://www.techradar.com/pro/security/major-dating-app-data-breach-may-have-exposed-1-5-million-private-user-images-online) |
| **Raw** (May 2025) | Dates of birth, sexual preferences, street-level location. | An IDOR flaw; no third-party audit; false claim of end-to-end encryption. | ✅ RPC-only reads with server-derived actor; four-account contract test (Fable C1). [W] TechCrunch |
| **Grindr** (2018–2026) | Location, gender, user status and HIV status, sent to ad and analytics partners. | SDK data sharing. | ✅ No dating data in analytics (spec §13.3). Keep **all ad and analytics SDKs off dating surfaces**. |

**In-repo signal.** Project memory records a past RLS mistake: `analysis_sessions` was anon-readable and needed an urgent lockdown migration (MEMORY index, "Spec 3b deletion status"). RLS regressions happen here; dating tables need a CI canary, not a one-off test.

**Phone numbers as identifiers: the risks** (all [BK] unless noted)
- **Reverse lookup.** Truecaller-style apps are ubiquitous in Ghana, Nigeria, Kenya and India and turn a number into a name instantly. A shared number is a full de-anonymisation, and early sharing is also the scam move off-platform (§2.4).
- **Number recycling** by carriers. A new owner of an ex-partner's recycled number could be falsely excluded by the phone-HMAC rule. That is rare and fails safe. A user who changes number escapes the exclusion, a known residual already documented in Fable C4.
- **SIM-swap fraud** is common where mobile money is the target. SMS OTP alone protects a dating account weakly.
- **Enumeration.** A sign-in endpoint that distinguishes "registered" from "new" lets an attacker test whether a known number uses Attune.
- **HMAC.** Phone numbers have low entropy, so an unkeyed hash is brute-forceable. Attune uses HMAC with a server secret (`dating_phone_hmac`), which is correct as long as the key stays server-side ([M] in-repo, Fable C4 fix).

---

### 2.4 Fraud and abuse

#### 2.4.1 Scale

| Metric | Value | Grade / source |
|---|---|---|
| US, FTC 2022 | About 70,000 reports; **$1.3bn** lost; median $4,400. 40% said contact began on social media, 19% on a dating site or app. Crypto plus bank wires were more than 60% of losses. Stock lies: "military base abroad", "offshore oil rig", "crypto investor", sudden emergencies. Scammers "quickly moved conversations to WhatsApp, Google Chat, or Telegram". | [S] dataset (under-reported): [FTC Data Spotlight, Feb 2023](https://www.ftc.gov/news-events/data-visualizations/data-spotlight/2023/02/romance-scammers-favorite-lies-exposed) |
| US, FTC 2025 | Romance losses **up 22%**, about $2,020 per person. The page prints the total as "$1.48 million"; given earlier years of $1.1–1.3bn, this is almost certainly **$1.48bn**. Contested pending FTC correction. | [S]/contested: [FTC consumer alert, May 2026](https://consumer.ftc.gov/consumer-alerts/2026/05/new-trends-reports-imposter-scams) |
| US, FBI IC3 2024 | About 17,900 romance and confidence complaints; about **$672m**. | [S] via [Newsweek](https://www.newsweek.com/fbi-warns-romance-scams-netting-millions-ahead-of-valentines-day-11492179) |
| UK, Action Fraud 2024/25 | 9,449 reports (+9%); **£106m** (+18%); average loss £11,222; most reports from people aged 50–59. Calendar 2025 (Report Fraud): 10,784 reports (+29%); over £102m. | [S] police data via [FStech](https://fstech.co.uk/fst/Romance_Fraud_Victims_Lost_Over_102m_Last_Year_Finds_City_Of_London_Police.php) |
| Ghana, CSA | Online fraud, Q1 2025: 305 cases vs 194 a year earlier; losses GH¢4.4m vs GH¢2.4m. Sextortion/blackmail, Jan–Apr: GH¢499,044 lost in 2025 vs GH¢103,663 (155 cases) in 2024. Modus operandi:<br>• fake attractive profiles;<br>• explicit video calls, secretly recorded;<br>• ransom paid by **mobile money**;<br>• conversations moved to **WhatsApp, Telegram or Signal**.<br>Advice: don't pay, keep evidence, report to **292** (call or text), WhatsApp 0501603111, report@csa.gov.gh. | [M] official: [CSA alert, 2 May 2025](https://www.csa.gov.gh/cert-gh-alert38.php); [Citi, Oct 2025](https://citinewsroom.com/2025/10/gh%C2%A219m-lost-to-cybercrime-in-nine-months-csa/) |
| West Africa, INTERPOL | Operation Jackal III (Apr–Jul 2024): 300 arrests, $3m seized, 720 accounts blocked, Black Axe money mules. Jackal IV (Nov 2025–Jun 2026): 58 arrests, 263 suspects identified, 22 countries. These groups drive "a significant share" of global romance, crypto-investment and business-email-compromise fraud. | [M] [INTERPOL 2026](https://www.interpol.int/ar/1/1/2026/58-arrests-in-global-effort-to-dismantle-West-African-organized-crime-groups); [JURIST 2024](https://www.jurist.org/news/2024/07/interpol-arrests-300-people-in-west-africa-organised-crime-groups/) |
| "Sakawa" and "Yahoo boys" | Ghanaian and Nigerian cybercrime subcultures (sakawa adds a ritual layer). Attune's Ghana-first brand is attractive both to local scammers targeting the diaspora and foreigners, and to people from outside targeting Ghanaians. | Context [BK]; consistent with INTERPOL and CSA |
| Pig-butchering | Chainalysis 2024: pig-butchering revenue up about 40% year on year; deposits up about 210%; approaches often begin on dating apps; run from Southeast Asian scam compounds. UNODC: $88–114bn in losses across East/Southeast Asia and Oceania in 2025; at least 80 nationalities among compound workers. | [W] industry; [W] secondary: [NBC/Chainalysis](https://www.nbcmiami.com/news/business/money-report/crypto-scams-likely-hit-a-new-record-in-2024-driven-by-pig-butchering-and-ai-says-chainalysis/3542952/); [Sumsub on UNODC](https://sumsub.com/media/news/southeast-asian-scam-losses-reached-114-billion-last-year-un/) |
| Sextortion, NCMEC | **More than 50,000** financial sextortion reports in 2025 (137 a day), up from more than 36,000 in 2024. | [S] [NCMEC, 2026](https://us.missingkids.org/blog/2026/ncmec-releases-new-sextortion-data-2025) |
| Sextortion, Thorn/NCMEC | About 812 reports a week, more than two-thirds financially motivated. **47% tied to Nigeria and Côte d'Ivoire.** 90% of victims are boys aged 14–17. Demands are rapid, with countdowns. First contact on Instagram or Snapchat, then moved to Snapchat, GChat, WhatsApp or Telegram. Payment by Cash App or gift cards. | [S] [Thorn & NCMEC, Jun 2024](https://www.thorn.org/research/library/financial-sextortion/) |
| Encounter rate | 52% of US online daters think they have met a scammer (63% of men under 50). | [M] [Pew, Feb 2023, n=6,034](https://www.pewresearch.org/internet/2023/02/02/from-looking-for-love-to-swiping-the-field-online-dating-in-the-u-s/) |

**What this means for a worldwide app.** The classic romance-scam script is **cross-border**: the claimed soldier or oil-rig worker abroad, the diaspora contact, the crypto "mentor". **Worldwide availability does not require cross-border introductions.** Same-country introductions by default remove most of the script (Implication 20).

#### 2.4.2 Detection and prevention that works

| Control | Evidence | Grade |
|---|---|---|
| **Selfie liveness plus photo consistency** | Defeats stolen-photo catfishing and most AI-generated profiles. A generated face must pass a live, injection-resistant capture *and* match every profile photo. Industry is moving to mandatory liveness (Tinder Face Check, [BK]). AI-image detectors on their own are unreliable ([BK]). | [W]/[BK] |
| **Keep conversations on-platform early** | FTC: fast moves to WhatsApp/Telegram. CSA: moves to WhatsApp/Telegram/Signal. Thorn: secondary platforms. | [S]/[M] |
| **Never send money** education at the moment it matters | FTC lies list; Attune's `financial_request` family names the pattern (spec §4.2). | [S] |
| **Rate and first-message limits** | Bumble Deception Detector and other ML filters claim very high spam and fake blocking ([BK], vendor). Attune's curated few-a-day introductions cap a scammer's reach by design, which is the strongest limit available. | [BK] |
| **Same-message-to-many detection** | Scam scripts are copy-pasted across targets. A deterministic hash of each normalised opening message, counted across distinct matches, is cheap, non-LLM and hard to evade. | design inference [W] |
| **IP country vs stated city mismatch** | A stated city of Accra with sessions from another country is a classic signal. Process it transiently; never store it as location history. | [BK] |
| **Report → action SLAs** | Apple: "timely responses". OSA: swift removal. Australia: 24-hour removal notices ([BK]). India: 24-hour NCII takedown ([BK]). | [M]/[BK] |

---

### 2.5 Harassment and safety in chat and on dates

| Finding | Grade / source |
|---|---|
| Among US online daters (Pew, Jul 2022, n=6,034):<br>• **38%** received unsolicited explicit messages or images (**56%** of women under 50; **56%** of LGB users);<br>• 30% were contacted again after saying no;<br>• 24% were called offensive names;<br>• 6% were threatened with harm;<br>• 48% had at least one of these. | [M] [Pew 2023](https://www.pewresearch.org/internet/2023/02/02/from-looking-for-love-to-swiping-the-field-online-dating-in-the-u-s/) |
| **UK cyberflashing.** An offence under s.66A Sexual Offences Act 2003, inserted by OSA s.187; up to 2 years. Made an **OSA priority offence on 8 Jan 2026**: in-scope services must take "proportionate measures to prevent users from encountering unsolicited nude images" and minimise how long they stay up. Fines up to 10% of global revenue. The government cites Bumble's auto-blur as an example. | [M] [GOV.UK](https://www.gov.uk/government/news/stronger-laws-for-tech-firms-to-ensure-you-dont-see-unsolicited-nudes); [RPC](https://www.rpclegal.com/snapshots/technology-digital/winter-2025/cyberflashing-crackdown-under-the-uks-online-safety-act/) |
| **US state laws.** Texas HB 2789 (2019) made unsolicited lewd images an offence. Virginia SB 493 (2022) and California SB 53 created civil actions. Bumble lobbied for all three. | [W] [Bumble](https://bumble.com/en/the-buzz/bumble-open-source-private-detector-ai-cyberflashing-dick-pics) |
| **Bumble Private Detector.** Blurs likely nudes in chat; the recipient chooses to view, block or report. Claims more than 98% accuracy. **Open-sourced under Apache 2.0** (`github.com/bumble-tech/private-detector`). | [W] vendor, same source |
| **Tinder "Are You Sure?"** (sender nudge) cut inappropriate wording by more than 10%. **"Does This Bother You?"** (recipient prompt) **raised reports of inappropriate messages by 46%**. | [W] [Tinder, May 2021](https://www.tinderpressroom.com/2021-05-20-Tinder-Introduces-Are-You-Sure-,-an-Industry-First-Feature-That-is-Stopping-Harassment-Before-It-Starts) |
| **Hinge Your Turn Limits** (global 18 Sep 2024): users must reply to or end waiting conversations before getting new ones. Responsiveness rose 20%. This is a quality and burnout measure, not a safety one. | [W] [Hinge](https://hinge.co/press/your-turn-limits) |
| **Tinder Share My Date** (22 Apr 2024): sends the date's location, time **and a photo of the match** to friends via a link. ⚠️ For a same-gender date in a Tier 1 country, this would out the match to a third party. | [W] [Tinder press](https://www.tinderpressroom.com/news?item=122564) |
| Noonlight panic-button integration (Tinder, 2020) and Garbo background checks (Match, 2021) existed and were later wound down. Background checks depend on US criminal-record data that is unavailable for West Africa. | [BK] |
| **Report evidence after unmatch.** A 2019 Columbia Journalism Investigations/ProPublica investigation, and later 2025 reporting on Match Group, found that unmatching erases the conversation and frustrates reports. The reporter must be able to report *after* the other person unmatches or blocks. | [BK] |
| Survivor and advocate guidance. eSafety and RAINN pages were **unreachable** this session. The common, long-standing guidance ([BK]):<br>• video call before meeting;<br>• meet in public;<br>• arrange your own transport;<br>• tell a friend the plan;<br>• don't share your home or work address early;<br>• watch your drink;<br>• leave if uncomfortable;<br>• never send money;<br>• keep the chat on-platform.<br>Ghana CSA adds: don't pay extortion, preserve evidence, report to 292. | [M] CSA; rest [BK] |
| Ghana DOVVSU. Attune lists "055 100 0900" (`safety_resources_screen.dart:122`). **I could not verify this number.** F10 already requires `verified_at` before release. | unverified |

---

### 2.6 Moderation at scale for a small team

What a solo developer, plus perhaps one contracted moderator, can realistically run:

| Layer | What to use | Why it fits a small team |
|---|---|---|
| **1. Prevention by design** (the largest lever) | Few curated introductions a day; double opt-in; no browsing; text-only dating chat in v1; contact exchange as a mutual action; liveness at entry; same-country by default. | Each one cuts the *volume* of harm to moderate, not just its severity. A scammer's reach is capped at a few introductions a day. |
| **2. Deterministic automation** (no LLM, per the permanent constraint) | The existing phrase-family engine with the dating config; rate limits (already in DB); opening-message duplicate hashing; IP-country mismatch; "Interested to everyone" dragnet flags. All of these route to a queue and never auto-ban. | Testable, reviewable and explainable. Consistent with dating chat spec §5.1. |
| **3. Image safety** | Google Vision SafeSearch (already in the photo pipeline); Rekognition CompareFaces plus **Face Liveness**; **CSAM hash-matching** on every upload (Microsoft PhotoDNA or Google Content Safety API for qualifying organisations, Thorn Safer as a paid service, [BK]); optional **StopNCII** hash integration for adult NCII ([BK]). | Hash-matching is near-zero false positive and supports the Google CSAE policy and any US provider's NCMEC reporting duty (18 USC 2258A, [BK]). |
| **4. Human review** | Owner as safety owner, plus one trained Ghana-based moderator who reads Twi, Ga and Pidgin scam scripts; a minimal admin console (there is **no admin UI** for any queue today, per photo spec §4). | Language and culture matter: scam playbooks are local (Guardian 2025). |
| **5. Escalation** | Imminent threat to life → police in the user's country (a human decision, never automated). CSAM → NCMEC CyberTipline / IWF or NCA / Ghana CSA. Sextortion → CSA 292 and the user's local police. | Spec §5.3 already says threat-to-life escalation is human. |
| **6. External moderation services**, when volume demands | Hive or Sightengine (per-call image and text classification); Checkstep or Tremau (DSA/OSA compliance tooling); BPO moderation later. | Pay per use; no fixed headcount ([BK]). |

**Proposed severity tiers and SLAs.** This is a proposal; pilot data should set the final numbers:

| Tier | Report categories | Immediate automatic step (report-driven, never phrase-trigger-driven) | Human-review target |
|---|---|---|---|
| P0 | `underage_risk`, CSAM, credible threat to life | Interim `age_review` / `moderation_hold`; hide from all introductions; close the reporter's match | ≤ 4 h in staffed hours; ≤ 24 h maximum |
| P1 | Sextortion, `romance_scam` with a money request, threats | Remove from new introduction generation | ≤ 24 h |
| P2 | Harassment, explicit images, impersonation | Reporter auto-blocks | ≤ 48 h |
| P3 | Spam, other | — | ≤ 72 h |

**Weaponised false reports are limited structurally.** Only people you matched with can report you, and matching requires double opt-in.

**Volume is unknown.** I found no public reports-per-1,000-users benchmark. Measure it in a capped pilot and staff to the measurement.

---

### 2.7 Attune's existing dating safety design

#### What is already right (keep)

1. **A separate dating-chat safety system.** It has stranger-threat rule families (`sexual_pressure`, `harassment_abuse`, `threat_intimidation`, `financial_request`, `contact_migration_pressure`, `age_signal`, `identity_inconsistency`). Sensitivity can only rise in the first 14 days of a match, never decay. Tier-3 inferences are silent and go to moderation. The design is fail-open, recipient-only and non-LLM, with a separate table and outbox (`DATING_CHAT_SAFETY_SPEC.md` §2–§8). This matches the evidence: scams and sextortion are short-arc, stranger, cross-platform threats (FTC, CSA, Thorn), and recipient prompts raise reporting (Tinder +46%).
2. **Romance scams are a first-class category.** There is a `romance_scam` report category, `financial_request` detection and first-date financial education (spec §8–§9) — exactly the West Africa risk the INTERPOL and CSA data show.
3. **Double-blind interest is enforced at the data layer** (Fable C3 fixed). Introductions are few and curated, with no browsing, admirer queue or counts.
4. **Orientation is protected.** Preferences are never in payloads; `gender_visible` defaults to false; nothing is inferred (spec §4.1, §6.1).
5. **No GPS and no distance** — structurally safer than the six trilateration-exposed apps.
6. **Photo pipeline:**
   - private bucket, opaque keys, signed URLs, EXIF stripping;
   - Vision SafeSearch before display;
   - camera-only verification selfie;
   - **the selfie is deleted in the same call and no embedding or score is stored**;
   - no "verified" badge (no over-trust).

   This is the exact failure of Tea and M.A.D Mobile, avoided.
7. **Former-partner exclusion** by keyed phone-HMAC, which survives re-registration. The residual is documented (Fable C4).
8. **The age gate is server-authoritative**, with a service-role-only writer (Fable C2). Feature flags are hidden from clients (H1). Error and timing behaviour is uniform (H2).
9. **Quick exit, PIN, a neutral cover screen, content-free pushes**, and a neutral app name.

#### What is missing for a worldwide launch

| # | Gap | Evidence |
|---|---|---|
| G1 | No **country risk model**: no tiers, no traveller handling, no LGBTQ legal notes, no per-country kill switch. | §2.1 |
| G2 | `city_region_code` is **free text** (1–80 characters). It cannot drive risk tiers or same-country defaults, and it can leak a neighbourhood. | `20260705210000:460` |
| G3 | **Every same-gender introduction discloses preference.** No photo-on-mutual mode, no caps for new accounts, no dragnet detection. | §2.1.8 |
| G4 | **No real age assurance at Dating entry.** Liveness is deferred to v2; there is no facial age estimation or ID path; Apple/Google age signals are not consumed. | §2.2 |
| G5 | **Dating chat media policy** is undecided (spec §5.4, the "largest known gap"). The UK priority offence now makes this a compliance issue. | §2.5 |
| G6 | **No early-chat contact masking or mutual contact swap.** | §2.4 |
| G7 | **No CSAM hash-matching** on profile photos or any chat media; no published CSAE standards page or named child-safety contact (Google Play). | §2.2.2, §2.6 |
| G8 | **No moderation console, runbook, SLAs or escalation contacts.** Report copy promises "We will review it" (Fable L5). | §2.6 |
| G9 | **Support resources** are a static list of 3 countries. F10 (country-routed, verified, with an `lgbtq_legal` category) is not built. There is no CSA 292 and no sextortion entry. | `safety_resources_screen.dart`; 06-synthesis F10 |
| G10 | **Quick exit does not wipe dating caches** (introductions, matches, photos, future chat). There is no discreet icon and no separate Dating lock. | `quick_exit_service.dart` |
| G11 | **Reporting after unmatch or block** is not guaranteed, and evidence is not snapshotted at report time. | §2.5 |
| G12 | **Compliance artefacts:**<br>• Ghana DPC registration;<br>• DPIA;<br>• EU/UK representatives;<br>• BIPA-style biometric consent and a retention schedule for US users;<br>• a law-enforcement request policy;<br>• a transparency report;<br>• OSA illegal-content and children's access assessments. | §2.2–§2.3 |
| G13 | **Ban evasion** by a new SIM is unaddressed, beyond phone-HMAC for former partners only. | §2.3 |
| G14 | `age_verification_invalid` **preserves matches** (Fable H5 accepted trade-off). An underage discovery should close them. | Fable §5 |
| G15 | **Cultural review is Ghana-only**, and there is no LGBTQ-safety reviewer anywhere in the review packets. | `DATING_MODE_CULTURAL_REVIEW_PACKET.md` |

#### What conflicts with the new owner decisions (worldwide; no Healing gate for new singles)

| # | Conflict | Where | Resolution needed |
|---|---|---|---|
| C1 | Eligibility is still Healing score >70, all stages, and path time gates for **everyone**. §2.1 "gate-erosion pre-commitment" says removing Healing stages needs "fresh recorded clinical sign-off". | `DATING_MODE_SPEC.md` §2, §2.1, §3.1; `dating_candidate_is_current` includes the Healing gates (Fable H4a) | Amend the spec with a recorded owner and clinical note. Keep the 8-week wait only where `breakup_at_source = relationship`. Remove the Healing predicates from `dating_candidate_is_current` for everyone else. |
| C2 | The readiness path's 4-week observed journey was also **incidental anti-scam friction**: a scammer had to sit through a month. Removing it removes that cost. | §3.1 | Replace with explicit trust friction: liveness, an account-age cool-off and introduction caps (Implication 19). |
| C3 | **Date of birth for everyone at sign-up** (self-declared) collides with Fable C2's rule that age is "never a client-editable integer" and that the gate must not fall back to self-attestation. | Fable C2; `verify_dating_age` | Two layers: the sign-up DOB is a declared screen and is never written to `dating_age_verifications`. Dating activation requires an assurance result written by the service role (Implication 9). |
| C4 | **Worldwide vs Ghana-only artefacts.** Ghana-only cultural review, Ghanaian city defaults, a 3-country resource list, and a launch gate of "2,000 active couples, sufficient local pool". | Spec §2, cultural packet | Per-country enablement checklist (Implication 31). |
| C5 | **Dating chat spec §4.1** says a trigger "does not block the message, delay it, mark it, or alter what the sender sees", with "no client-side detection". Contact masking (Implication 21) and nudity blur (Implication 25) alter rendering. | `DATING_CHAT_SAFETY_SPEC.md` §1.2, §4.1 | Amend the spec: render-time masking and blurring are explicit, rule-based, server-decided presentation rules, distinct from phrase triggers. Delivery stays fail-open. |
| C6 | **Dating chat spec §5.1**: restriction follows human review only. A solo operator cannot review P0 reports at 3 a.m. | §5.1 | Allow report-driven interim holds for P0 categories; phrase triggers still never restrict (Implication 30). |

---

## 3. Implications for Attune

Each item says what to build, change, avoid or measure, and why.

**LGBTQ and country safety**

1. **Build a versioned server-side country risk table** (Tier 1/2/3, `source_url`, `reviewed_at`, quarterly review) from §2.1.6.
   - Effective tier = the highest of: phone-number country, chosen dating country, and the session's IP country (processed transiently, never stored).
   - *Why:* Grindr's tiering is built on ILGA data; five countries changed their law in 2025–26; travel changes risk (Tinder Traveler Alert).
2. **Replace free-text `city_region_code` with structured `country_code` plus `region_code`** from a fixed list.
   - *Why:* tiering, same-country defaults and cross-border controls need structure; free text can leak a neighbourhood (§2.1.5).
3. **Same-gender protections in Tier 1/2**, all server-enforced:
   - (a) a private, plain country note before the preference is saved, covering trans and non-binary users too;
   - (b) **photos withheld until mutual interest** for same-gender introductions; the card shows first name, age, region and alignment band;
   - (c) liveness required;
   - (d) a weekly cap on same-gender introductions for accounts under 30 days old;
   - (e) dragnet detection (Interested to nearly every introduction, rarely messaging) routed to moderation;
   - (f) auto-hide while in a higher tier than home, with opt-in visibility.

   *Why:* each introduction discloses preference (§2.1.8); entrapment works through fake profiles (Egypt, Nigeria, Ghana, Russia).
4. **Never** add an orientation label, an "LGBTQ" badge, a same-gender filter visible to others, or analytics on preference values. Keep `gender_visible` defaulting to false. *Why:* the Grindr Norway special-category ruling; outing risk.
5. **Harden the device against seizure:**
   - quick exit also wipes dating introductions, matches, photos and chat caches;
   - an optional separate Dating PIN;
   - dating media never saved to the gallery; Android `FLAG_SECURE` on dating screens;
   - a short local chat cache, plus an option for disappearing messages;
   - an optional **discreet icon** (iOS alternate icon, Android activity-alias).

   *Why:* phones searched at checkpoints and arrests are the main source of evidence (HRW 2023; Rigot 2022; the Grindr Beirut case).
6. **Per-country kill switches** for (a) same-gender matching and (b) Dating as a whole, plus a legal watchlist: Ghana's bill, Kenya's FPB, Senegal's assent, Türkiye's reform. *Why:* laws flip fast, and Ghana's bill reportedly makes platform owners liable as "promoters".
7. **Add LGBTQ legal and support resources** for Tier 1/2 countries to the F10 resource model (the `lgbtq_legal` category already exists in the roadmap), each with `verified_at`. Ship a short, localised safety guide in the spirit of Grindr's Holistic Security Guide: English, French, Arabic, Pidgin, and Twi if a reviewer is available. *Why:* Ghana survivors often don't know help exists (Guardian 2025).
8. **Minimise what can be compelled or breached:**
   - hard-delete preferences, gender and dating messages on exit (not just schedule it);
   - delete dating chat at match close plus a short evidence window;
   - keep no preference history;
   - publish a law-enforcement request policy (valid legal process only; notify the user unless prohibited; nothing beyond what exists).

   *Why:* the server-side set of same-gender seekers in criminalising countries is a target list.

**Age**

9. **Two-layer age model:**
   - **Sign-up:** a neutral DOB screen for everyone (no cut-off hint; blocked retry), stored in the protected account domain.
   - **Dating activation:** an assurance step in the existing camera-only selfie — **liveness plus facial age estimation with a challenge age** (e.g., 25), falling back to ID.
   - **Mandatory** for UK users; recommended for everyone.
   - The sign-up DOB must never write `dating_age_verifications`.

   *Why:* Ofcom HEAA; more than 1 in 10 15–17s on major dating apps; Fable C2.
10. **Consume Apple Declared Age Range** (and Google's equivalent, [BK]). An under-18 signal blocks the app's 18+ surfaces. *Why:* Texas, Utah and Louisiana app-store laws.
11. **Store compliance, cheap but blocking:**
    - rate the app 18+;
    - publish a CSAE standards web page;
    - name a child-safety contact in Play Console;
    - meet Apple 1.2 (filter, report with timely response, block, published contact).
12. **Underage path:** an `underage_risk` report triggers an interim `age_review` hold and **closes active matches**. Add `age_verification_invalid` to the match-closing reasons (fixes G14).

**Data protection**

13. **Treat gender identity plus "interested in" as special-category data worldwide:**
    - a separate explicit-consent screen at dating opt-in (purpose, who sees what, how to withdraw);
    - application-level encryption of the preference and gender columns with a server-held key;
    - no client reads of other users' values (already true);
    - excluded from logs, analytics, support tools and admin views by default;
    - a **DPIA** before launch.

    *Why:* GDPR Art. 9 and CJEU C-184/20; Ghana, Nigeria and Kenya law; US opt-in states.
14. **Collect no HIV/STI status, ethnicity or tribe fields in Dating v1.** If faith is added (a cultural-research question), it is filter-only, explicit-consent and never displayed without choice. *Why:* the Grindr HIV-data cases; Art. 9.
15. **Biometric consent:** add a BIPA/CUBI-style written consent checkbox and a published retention and destruction schedule to the verification flow before US users are enabled. Name Art. 9 explicit consent for EU/UK users. *Why:* face geometry is biometric even when transient.
16. **Registrations and representatives:**
    - Ghana DPC registration now (mandatory);
    - EU Art. 27 and UK representatives before enabling those countries;
    - Nigeria NDPC and Kenya ODPC registration when thresholds apply.
17. **Breach-proofing gates before any flag flip:**
    - secret scanning in CI (M.A.D Mobile);
    - storage-bucket policy test (Tea);
    - a dating RLS/RPC canary in CI, not a one-off test (Raw; in-repo `analysis_sessions` history);
    - no ad or analytics SDKs on dating surfaces (Grindr);
    - one external penetration test.
18. **Phone numbers never appear in any dating payload, push or admin list view.** Make the sign-in OTP response identical for new and existing numbers. Require re-verification of Dating on a new device. *Why:* reverse lookup, enumeration, SIM swap.

**Fraud and abuse**

19. **Replace the Healing gate's incidental friction with explicit trust friction:**
    - liveness plus photo consistency are **required** for Dating (not v2);
    - a cool-off between activation and first introduction (e.g., 72 hours — a proposal to measure);
    - keep introduction caps.

    *Why:* removing the 4-week journey removes a scammer cost (C2).
20. **Same-country introductions by default.** Cross-border (diaspora) introductions are opt-in, both people verified, with cross-border scam education ("soldier abroad", "oil rig", "crypto mentor"). *Why:* FTC scam scripts; INTERPOL/West Africa and SE Asia compound data. Worldwide availability is not the same as cross-border matching.
21. **Early-chat contact masking with a mutual "Swap contacts" action:**
    - server-side presentation rules mask phone numbers (including mobile-money numbers), URLs, emails and @handles for the first 72 hours, or until both tap "Swap contacts";
    - an inline note explains why;
    - links are never auto-clickable.

    *Why:* FTC, CSA and Thorn all show the move off-platform comes first. Requires a spec amendment (C5).
22. **Add deterministic, non-LLM scam signals to the dating config:**
    - Ghana variants: MoMo, "mobile money", "send me small", "transport fare", "data bundle";
    - duplicate opening-message hashes across matches;
    - IP-country mismatch;
    - several accounts per device.

    All route to moderation and never auto-ban. *Why:* local playbooks (Guardian, CSA); spec §5.1.
23. **Sextortion card.** When chat patterns indicate intimate-image or video-call pressure, the recipient sees: "Don't pay. Keep the messages. Report here and to [CSA 292 / local line]." Use the same deterministic tier-2 routing. *Why:* the CSA alert; NCMEC growth; Thorn's 47% West-Africa tie.
24. **CSAM hash-matching on every image upload** (profile photos now; chat media if ever enabled), plus an NCMEC/IWF/CSA escalation runbook. Consider StopNCII integration. *Why:* the Google CSAE policy; legal reporting duties; near-zero false positives.

**Harassment and dates**

25. **Dating chat v1 is text-only:** no images, voice, video or clickable links.
    - If media is added later: blur by default with a server-side nudity classifier (Vision SafeSearch is already in the stack; Bumble's Private Detector is open source), tap to view, one-tap report.
    - *Why:* Pew 38%/56%; the UK priority offence since 8 Jan 2026; spec §5.4.
26. **Keep recipient-side support on harassment and sexual-pressure triggers** (spec tier 1), styled like "Does this bother you?". Do **not** add a sender-side "Are you sure?" in v1: it needs a pre-send check, which conflicts with fail-open, no-delay delivery. State this explicitly. *Why:* Tinder's evidence is +46% reports from recipient prompts versus a modest 10% from sender nudges.
27. **Reporting survives unmatch and block** for a window (e.g., 30 days) from match history, and the server snapshots the last N messages as evidence at report time. *Why:* the unmatch-erases-evidence problem.
28. **"Share my plan"** sends time, place and an optional check-in time to a trusted contact **without the match's photo or name by default**; in Tier 1/2 same-gender matches it never includes them.
    - An optional "check on me" local reminder offers "I'm OK" or "Get help".
    - "Get help" shows local emergency numbers behind a confirmation; it never auto-dials (F10).
    - *Why:* Tinder Share My Date shares the match's photo, which outs people in Tier 1.
29. **Deterministic, reviewed meeting-safety content** in the guided-date guide:
    - video call first;
    - meet in public;
    - arrange your own transport;
    - tell someone;
    - never send money;
    - keep chat on Attune.

    Add an LGBTQ-specific block (never a private address first; beware urgency to meet; see the country note) and Ghana lines (CSA 292, police). *Why:* advocate guidance; Ghana and Nigeria lure patterns.

**Moderation and launch**

30. **Write the runbook:**
    - P0–P3 tiers and SLAs (§2.6);
    - report-driven interim holds for P0;
    - owner plus one trained Ghana-based moderator;
    - a minimal admin console covering `needs_review` photos and verifications, reports, restrictions and appeals;
    - escalation contacts;
    - a quarterly transparency summary.

    *Why:* Apple's timely-response rule, OSA, DSA Art. 16–17, the Australian code norm, and honest report copy (Fable L5).
31. **Enable Dating country by country.** A country turns on only when it has:
    - (a) a tier row;
    - (b) verified resources;
    - (c) a legal checklist (age assurance, registrations, representatives);
    - (d) moderator language coverage.

    Start with Ghana plus a few diaspora countries. *Why:* "worldwide" multiplies legal regimes; a solo team can't comply everywhere on day one.
32. **Measure from day one**, with aggregates only and no individual attribution:
    - time to triage, by category;
    - reports per 1,000 matches;
    - scam and sextortion reports;
    - false-positive rate of `financial_request` and the masking rules (sampled review);
    - verification pass and fallback rates;
    - same-gender cap hits and dragnet flags.

    Get skin-tone and region error data from the age-estimation vendor rather than collecting skin tone. *Why:* no public benchmark exists; NIST and Yoti both show demographic variance.

---

## 4. Open questions for the owner

| # | Question | Recommendation |
|---|---|---|
| Q1 | **Offer same-gender matching in Tier 1 countries, including Ghana?** | **Yes, with the Tier 1 protections** (Implications 3, 5, 6, 8). Get a **Ghanaian legal opinion before launch** on owner and staff exposure under s.104 and the bill's platform-"promotion" clause. Pre-build the per-country kill switch, and turn same-gender off in Ghana if the bill is enacted with platform liability. Removing it everywhere (the WhosHere approach) pushes users to riskier channels; offering it unprotected makes Attune a list. |
| Q2 | **What level of age assurance?** | One flow for everyone at Dating activation: **Rekognition Face Liveness** (already in AWS) plus facial age estimation with a challenge age and ID fallback. Make it **mandatory before enabling the UK**, using an HEAA-recognised estimation vendor (Yoti or similar). Ask vendors for skin-tone and West-Africa error data and Ghana Card support (Smile ID as the African ID fallback). |
| Q3 | **Launch geography: literally worldwide on day one?** | **Worldwide-capable, country-enabled.** Ghana plus selected diaspora countries first (UK only once Q2 is done); Dating geo-off elsewhere until the Implication 31 checklist passes. |
| Q4 | **Cross-border introductions (diaspora ↔ Ghana)?** | **Off by default.** An opt-in "open to people in [country]" for verified users, with cross-border scam education. |
| Q5 | **Media in dating chat?** | **Text-only in v1.** Revisit with blur-by-default and hash-matching once moderation capacity is measured. |
| Q6 | **Mask contact details in early chat?** | **Yes.** Mask for 72 hours or until a mutual "Swap contacts", and amend dating chat spec §4.1 to allow rule-based presentation changes (C5). |
| Q7 | **Interim automatic holds on P0 reports before human review?** | **Yes**, report-driven only. Phrase triggers still never restrict (amend spec §5.1, C6). |
| Q8 | **Store face templates to stop ban evasion, as Tinder Face Check does?** | **Not in v1.** Biometric retention is a breach and legal liability (BIPA, Art. 9); use phone, device and IP signals. Revisit at scale with legal review. |
| Q9 | **Who moderates, and from where?** | The owner plus one contracted, trained moderator who reads Twi, Ga and Pidgin. Get legal advice on whether Ghana-based moderators handling same-gender cases face exposure if the bill passes; restrict their view to the minimum needed. |
| Q10 | **Replace the Healing gate's friction for new singles?** | **Yes:** required liveness, a short cool-off before the first introduction, and introduction caps. Record the spec §2.1 amendment with a clinical note, so the "gate-erosion" clause is honoured rather than silently bypassed. |
| Q11 | **Offer a discreet app icon to everyone?** | **Yes, everyone**, with a prompt to use it in Tier 1/2. It is cheap, and Grindr found global availability better than geo-targeting. |
| Q12 | **Publish a law-enforcement request policy and transparency summary?** | **Yes, before launch.** Draft both with counsel. Minimal retention is the real protection: Attune can only hand over what it keeps. |

---

### Source key (short forms used in tables)

- **HDT:** [Human Dignity Trust, Map of Countries that Criminalise LGBT People (2026)](https://www.humandignitytrust.org/lgbt-the-law/map-of-criminalisation/) [M]
- **ILGA 2026:** [ILGA World, Pride Month 2026 data update, 1 Jun 2026](https://ilga.org/news/pride-month-2026-lgbti-maps-data/) [M]
- **HRW 2023:** [Human Rights Watch, "All This Terror Because of a Photo", 21 Feb 2023](https://www.hrw.org/report/2023/02/21/all-terror-because-photo/digital-targeting-and-its-offline-consequences-lgbt) [M]
- **Grindr blog:** [Assessing and Mitigating Risk for the Global Grindr Community (updated 18 Oct 2026)](https://grindr.com/blog/mitigating-risk-for-the-global-grindr-community) [W]
- **Guardian 2025:** Dotto & Krobea Asante, "Torture, blackmail, extortion: the dangers of queer online dating in Ghana", *The Guardian*, 10 Oct 2025, [republished by 76crimes](https://76crimes.com/2026/01/29/torture-blackmail-extortion-the-dangers-of-queer-online-dating-in-ghana/) [W]
- **Rigot 2022:** [Afsaneh Rigot, "Digital Crime Scenes", Belfer Center, 2022](https://www.belfercenter.org/publication/digital-crime-scenes-role-digital-evidence-persecution-lgbtq-people-egypt-lebanon-and) [M]
- In-repo: `DATING_MODE_SPEC.md`, `DATING_CHAT_SAFETY_SPEC.md`, `docs/reviews/DATING_REVIEW_FABLE.md`, `docs/superpowers/specs/2026-08-02-dating-photo-verification-design.md`, `lib/features/safety/**`, `supabase/migrations/*dating*`

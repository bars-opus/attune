# 02 — Dating and matchmaking apps: what real users love, hate and ask for

*Research date: 2026-10-24. Researcher 02 of the flow + dating programme (see `BRIEF.md`). Scope: the user's voice, from reviews at scale, with surveys, regulators, NGOs and academic work as a cross-check. This builds on, and does not repeat, `2026-10-16-couples-research/01-market-reviews.md`.*

---

## 1. How this was researched

### 1.1 Primary evidence: an 11,502-review App Store corpus across 51 apps and 10 storefronts

| | |
|---|---|
| **Apps** | 51, in seven groups. **Mainstream:** Tinder, Bumble, Hinge, OkCupid, Match, eharmony, Badoo, happn, Boo, Plenty of Fish, Hily, tantan. **Intentional/curated:** Coffee Meets Bagel, The League, Raya, Thursday, Timeleft, Known, Breeze. **Faith:** Muzz, Salams, Christian Mingle, Upward, Ark, SALT, Lox Club. **South Asian culture:** Dil Mil, Shaadi.com, Jeevansathi, Aisle. **African/diaspora:** BLK, AfroIntroductions, Trueflutter, Bumpy, Olosho, African Abroad, Heyama, Jebena, Konjo, TrulyAfrican. **LGBTQ+:** Grindr, HER, Taimi, SCRUFF, Feeld. **AI matchmakers:** iris, Amata, Sitch, RARE, SciMatch, Teleport. App IDs came from the iTunes Search API; per-country availability and rating counts from the iTunes Lookup API (`country=`), both on 2026-10-24. |
| **Storefronts** | us, gb, ng, gh, ke, za, in, ae, ca, au. **Ghana is available**, and Ghana-store reviews exist. |
| **Source A: Apple's public review RSS feed** | `itunes.apple.com/{cc}/rss/customerreviews/page={n}/id={id}/sortby={mostrecent\|mosthelpful}/json`. 276 pages fetched, up to 50 reviews each. 9,887 reviews came this way. |
| **Source B: the public App Store page** | `apps.apple.com/{cc}/app/id{id}?see-all=reviews`. I parsed the embedded page data for up to 10 featured reviews per app per storefront, across 367 app×storefront pages. This added 1,615 reviews not in Source A. Review IDs are shared across both sources, so the corpus is deduplicated by ID. |
| **Totals** | **11,502 unique reviews: 7,698 rated 1–3★ (67%), 3,804 rated 4–5★.** Dates run from 2012-06-19 to 2026-10-22, and 71% (8,166) are from 2024 or later. Raw JSON is kept only in the session scratchpad. |

**Per-storefront counts** (the brief asked for these):

| Storefront | Reviews | 1–3★ | Apps with ≥1 review | Median words per 1–3★ review | 1–3★ reviews of ≤15 words |
|---|---|---|---|---|---|
| us | 3,468 | 2,570 | 51 | 66 | 14% |
| gb | 2,370 | 1,798 | 44 | 72 | 13% |
| **ng** | **1,310** | 689 | 23 | 27 | 30% |
| **gh** | **661** | 311 | 18 | **18** | **43%** |
| **ke** | **436** | 216 | 14 | 21 | 39% |
| **za** | **1,279** | 678 | 32 | 40 | 14% |
| in | 747 | 518 | 31 | 31 | 33% |
| ae | 454 | 287 | 28 | 50 | 20% |
| ca | 441 | 386 | 46 | 39 | 17% |
| au | 336 | 245 | 38 | 131 | 7% |

**Per-app corpus** (US store rating from the Lookup API, 2026-10-24):

| App | Group | Reviews | % 1–3★ | Avg ★ of sample | US store ★ (ratings) |
|---|---|---|---|---|---|
| Tinder | Mainstream | 2,909 | 72% | 2.30 | 4.20 (1.76M) |
| Badoo | Mainstream | 451 | 29% | 3.90 | 4.58 (150K) |
| Bumble | Mainstream | 360 | 73% | 2.33 | 4.32 (1.77M) |
| OkCupid | Mainstream | 352 | 61% | 2.76 | 4.32 (289K) |
| Boo | Mainstream | 296 | 32% | 3.85 | 4.17 (212K) |
| Hinge | Mainstream | 273 | 54% | 3.08 | 4.41 (1.13M) |
| happn | Mainstream | 227 | 78% | 2.04 | 4.35 (49K) |
| eharmony | Mainstream | 213 | 91% | 1.50 | 4.06 (49K) |
| Plenty of Fish | Mainstream | 212 | 80% | 1.97 | 4.29 (1.81M) |
| Hily | Mainstream | 182 | 78% | 2.07 | 4.40 (384K) |
| tantan | Mainstream | 134 | 89% | 1.54 | 4.61 (4K) |
| Match | Mainstream | 100 | 91% | 1.55 | 3.87 (243K) |
| Raya | Intentional | 239 | 89% | 1.74 | 4.04 (16K) |
| The League | Intentional | 237 | 91% | 1.53 | 4.21 (56K) |
| Timeleft | Intentional (group dinners) | 218 | 56% | 2.98 | 4.62 (9K) |
| Breeze (no chat, just dates) | Intentional | 161 | 60% | 2.83 | 4.34 (608) |
| Known (swipeless, AI onboarding) | Intentional | 86 | 43% | 3.42 | 4.56 (1.9K) |
| Thursday (events) | Intentional | 57 | 67% | 2.54 | 4.54 (413) |
| Coffee Meets Bagel | Intentional | 20 | 95% | 1.30 | 4.34 (22K) |
| Muzz | Faith | 325 | 60% | 2.76 | 4.53 (55K) |
| SALT | Faith (Christian) | 245 | 44% | 3.40 | 4.32 (2K) |
| Salams | Faith (Muslim) | 177 | 80% | 1.98 | 4.43 (49K) |
| Ark | Faith (Christian) | 165 | 41% | 3.54 | 4.57 (10K) |
| Upward | Faith (Christian) | 99 | 84% | 1.88 | 4.34 (163K) |
| Christian Mingle | Faith | 66 | 91% | 1.59 | 3.54 (563) |
| Lox Club | Faith (Jewish) | 62 | 89% | 1.68 | 4.26 (4.5K) |
| Shaadi.com | South Asian | 228 | 80% | 1.84 | 4.30 (22K) |
| Dil Mil | South Asian | 148 | 74% | 2.17 | 3.99 (21K) |
| Aisle | South Asian | 135 | 79% | 1.99 | 4.47 (11K) |
| Jeevansathi | South Asian | 115 | 97% | 1.22 | 4.49 (3K) |
| Bumpy (international) | African/diaspora-used | 358 | 48% | 3.23 | 4.54 (43K) |
| AfroIntroductions | African/diaspora | 271 | 46% | 3.29 | 4.51 (13K) |
| Heyama | African/diaspora | 190 | 11% | 4.51 | 4.40 (1K) |
| Olosho (Nigeria) | African | 147 | 73% | 2.21 | 4.42 (5.7K; 12.4K in ng) |
| BLK | Black singles (US) | 146 | 86% | 1.90 | 4.57 (556K) |
| TrulyAfrican | African | 140 | 81% | 1.99 | 3.19 (208) |
| Trueflutter | African | 132 | 48% | 3.31 | 4.84 (2.9K; 9.1K in ng) |
| Jebena / Konjo | Habesha diaspora | 82 / 35 | 67% / 80% | 2.50 / 2.09 | 4.31 / 4.33 |
| African Abroad | African diaspora | 7 | — | — | 4.54 (112) |
| Grindr | LGBTQ+ | 343 | 74% | 2.21 | 4.45 (389K) |
| Feeld | LGBTQ+ / open | 174 | 85% | 1.90 | 4.30 (102K) |
| HER | LGBTQ+ (women, queer) | 172 | 47% | 3.36 | 4.42 (66K) |
| SCRUFF | LGBTQ+ | 163 | 64% | 2.73 | 4.36 (30K) |
| Taimi | LGBTQ+ | 155 | 85% | 1.90 | 4.42 (215K) |
| RARE | AI dating assistant | 122 | 84% | 1.67 | 4.49 (1.9K) |
| Amata | AI matchmaking club | 104 | 73% | 2.28 | 4.34 (2.5K) |
| Sitch | AI matchmaker | 96 | 94% | 1.46 | 3.91 (2.6K) |
| iris | AI matching | 88 | 58% | 2.86 | 4.53 (5.8K) |
| Teleport | AI matchmaker | 47 | 72% | 2.21 | 3.59 (139) |
| SciMatch | AI matching | 38 | 61% | 2.61 | 4.28 (282) |

**As in the couples market, store averages hide the pain.** Most apps sit at 4.2–4.6★ in the store, but their most-helpful and most-recent reviews are mostly 1–3★. **Do not benchmark Attune against store ratings.** Heyama is an outlier (11% low, median review length of 4 words, 128 of 190 rated 5★). That pattern looks like prompted or low-effort reviewing, so its "loves" carry little weight.

### 1.2 How the counts work

I tagged each review against keyword themes. That gives 8 love themes and 30 pain themes, plus derived tags such as "ban with no reason given" and "banned after being reported". I then hand-checked random samples (§1.4) and tightened any theme that scored badly. Read the numbers as **frequency signals, not prevalence**:
- **Pains** use the 7,698 reviews rated 1–3★ as the base. **Loves** use the 3,804 rated 4–5★. Love counts are low partly because positive reviews are short: median 17 words, and 39% are 10 words or fewer.
- **Tinder is 25% of the corpus.** Every theme therefore also carries a **macro %**: the average of per-app rates across the 40 apps with at least 30 low reviews. The macro figure stops one app from driving the ranking.
- Keyword matching misses paraphrase. Counts for subtle themes (ghosting, burnout, gender imbalance) are floors. West African reviews are much shorter (Ghana median 18 words; only 47% of Ghana's low reviews hit *any* pain theme, against 76% in the US). **Rates for ng/gh/ke are therefore floors too.** Their *ranking* is more reliable than their size.

### 1.3 Limits, stated plainly

1. **Collection was rate-limited.** Apple's RSS feed returned empty pages for about 80% of requests. After an early burst of parallel requests it also returned HTTP 403 for about 30 minutes. I recovered with a single slow crawler and cache-busting. As a result, depth is uneven: the US, Nigeria, South Africa and Ghana got deeper pulls, while ca/au/in/ae are mostly the 10 featured reviews per app plus Tinder. Some big apps (OkCupid, Coffee Meets Bagel, Badoo) never returned their US RSS pages and are under-represented.
2. **Featured reviews (Source B) lean towards "most helpful"**: longer, older and more often negative.
3. **Reddit is not reachable.** WebFetch refuses reddit.com, as it did on 2026-10-16. Nairaland (Nigeria's largest forum) returned 403.
4. **Web search was unavailable.** The programme's shared WebSearch budget was exhausted before this researcher's first query. Every non-review source below was fetched from a known URL or verified through the Crossref DOI API. pewresearch.org, ofcom.org.uk, Singles in America, Forbes Health, PNAS, Science and PMC all returned 403, a captcha or a timeout. Pew figures are therefore read second-hand (flagged in §2.8).
5. **Google Play was not attempted.** Android dominates in Ghana and Nigeria, so Android-only voices are missing, and they are probably the majority there. iPhone users in Ghana skew urban and higher-income.
6. **Selection bias.** People who quietly leave, or quietly succeed, rarely review. Banned users review a lot.

### 1.4 Hand-checked precision

Random samples were drawn from the final corpus after tightening. "Before" shows themes that needed fixing.

| Theme | Checked | Correct | Notes |
|---|---|---|---|
| Paywall (strict complaint) | 20 | 20 | A separate "mentions a paid tier" tag is broader and reported only as context |
| Fake profiles and bots | 20 | 18 | Misses: "fake app", a support bot |
| Bans and suspensions | 20 | 20 | Before excluding "shadow ban" it was 12/15 |
| Ban with no reason given (derived) | 12 | 12 | |
| Romance fraud and scams | 12 | 12 | Before: 9/15 ("Tinder scammed me" meant the paywall) |
| Algorithm and visibility | 15 | 13 | |
| Location and distance | 15 | 14 | |
| Support unreachable | 12 | 12 | |
| Billing, refunds and renewals | 12 | 11 | |
| Bugs | 10 | 8 | |
| Waste of time | 10 | 10 | |
| Harassment | 15 | 10 | Noisy: "creepy" support, "abuse of power" |
| Safety incidents | 15 | 11 | Before: 2/15 ("set up", "predatory pricing") |
| Privacy and data | 12 | 9 | |
| Ghosting | 12 | 7 | Many say support "ghosted" them |
| Burnout and mental health | 12 | 10 | |
| Race and ethnicity | 12 | 12 race-related | About 7 describe racism or exclusion; 5 want or reject ethnicity filters |
| Gender imbalance | 12 | 12 | Only 17 hits in total, so the theme is tiny |
| Met partner / married | 12 | 11 | |
| Quality over quantity | 12 | 10 | |
| Community / faith fit | 12 | 11 | |
| Verification and "real people" (love) | 12 | 12 | Before: 3/12. The bare word "verify" mostly appears in complaints |
| Prompts and icebreakers | 10 | 8 | |
| Slow, curated, matchmaker feel | 10 | 8 | |

---

## 2. Findings

### 2.0 The headlines

1. **What makes people love a dating app is a result, not a feature.** "I met my husband here" is the strongest love theme. It is three to five times more common on faith and South Asian apps than on mainstream ones (§2.1).
2. **The market's #1 pain is still money standing between two interested people.** Paywalls on replying, on seeing likes and on being seen account for 14% of low reviews (macro 15%). A quarter of low reviews mention a paid tier (§2.2).
3. **In Ghana, Nigeria and Kenya, the #1 named pain is being banned, usually with no reason given** (15.7–17.4% of low reviews, against 7.3% in the US). A cross-app pattern drives part of it: **people who refuse sexual or meeting demands get reported and auto-banned** (§2.2 P4, §2.3).
4. **Fakes and scams are the trust tax of the whole category.** Fakes and bots appear in 14% of low reviews. India has the highest rate (26%), and South Asian apps are at 22%. Foreign reviewers stereotype West African profiles as scammers, which matters because Attune's first users are Ghanaian (§2.2, §2.3).
5. **Curated and AI matchmakers, closest to Attune's "few introductions a day", fail in predictable ways.** They ignore stated dealbreakers, pad a thin local pool with far-away or mismatched people, charge per date before value, and gate entry behind invites and waitlists (§2.4).
6. **West African users hit access walls before they ever meet anyone**: OTP codes that never arrive, selfie-review queues lasting a week, verification puzzles, Facebook-only verification, and cards that don't work where mobile money is the norm (§2.5, §2.6).
7. **Safety features are rarely praised but their absence is resented.** Paying for safety, auto-bans, early video calls that turn into sextortion, and entrapment risk for LGBTQ+ users stand out (§2.2, §2.3).

### 2.1 What users LOVE

Base: 3,804 reviews rated 4–5★. "All" counts include the theme in any rating.

| # | What users love | Corpus (4–5★) | Strongest in | Evidence grade |
|---|---|---|---|---|
| L1 | **It worked: met a partner, engaged, married** | 127 (3.3%; macro 5.0%); 145 at any rating | **South Asian 12.9%** and **faith 8.9%** of 4–5★, against mainstream 2.7%. Hinge 7.7%, Dil Mil 8.8%, Muzz 4.0% | Anecdote, consistent across 13 apps |
| L2 | **Quality over quantity, intentional people, "not just swiping"** | 117 (3.1%); 294 at any rating | AI apps 8.5%, intentional 7.9%, faith 6.3%. Boo 8.4%, Known 9.3%, SALT 4.9% | Anecdote |
| L3 | **Community and faith fit: "same faith", halal, like-minded, built for us** | 67 (1.8%) | **Faith 8.6%**. SALT 7.8%, Muzz 3.7%, Jebena (Habesha) | Anecdote |
| L4 | **Prompts, icebreakers and personality depth that start real conversations** | 55 (1.4%) | Boo 4.1%, Hinge 3.7%, SALT 3.7% | Anecdote |
| L5 | **Verification that means "real people"** | 36 (0.9%) | AI apps 3.4%. Boo, Badoo, iris | Anecdote |
| L6 | **Safety features** (nude blur, women first, block and report) | 31 (0.8%) | LGBTQ+ 2.8% | Anecdote; rarely praised in its own right |
| L7 | **Video and voice** | 28 (0.7%) | Mostly *requests* inside positive reviews (§2.7) | Anecdote |
| L8 | **Slow, curated, "a matchmaker behind the scenes"** | 20 (0.5%) | Known 5.8%; intentional and AI groups about 3% | Anecdote |

**L1, it worked.** These stories credit *fit* more than mechanics. "I come from a very traditional Indian family so it was important for me to find a girl that not only I would like, but so would my family" (Dil Mil, US, 5★, 2019). "I met my soulmate on muzmatch and we met in person in the presence of my mother… after much istikhara we are getting engaged tomorrow" (Muzz, US, 5★, 2017). They also appear in African storefronts: "Met my husband through this app… Married for 3 years now" (Tinder, ZA, 5★, 2023); "I met my husband here. I posted a short story on TikTok" (OkCupid, KE, 5★, 2023); "Found my soulmate… the app made me delete the app after a few days 🤍 thanks bumpy for connecting me to the person I couldn't find in my country" (Bumpy, ZA, 5★, 2025). The last one is a diaspora and cross-border success. Nigerian success stories often come with ban anxiety: "pls dont ban my account once we get engaged i will personally promote tinder" (Tinder, NG, 5★, 2026).

**L2, quality over quantity.** This is the love that matches Attune's model most closely, and it is conditional. "No, you will not see hundreds of matches, but you will see quality matches… I will see 3-5 people at a time" (The League, US, 5★, 2018, 337 helpful votes). "I'd rather have fewer intentional matches over the dozens of shallow matches" (Known, US, 5★, 2026). "There's no endless swiping, no dopamine spiral, no sense that you're just another profile being shuffled through an algorithm designed to keep you addicted" (Known, US, 5★, 2026). The same apps' 1★ reviews show what happens when "few" becomes "none" or "wrong" (§2.4).

**L3, community fit.** "My favourite thing about SALT is that I'm able to connect with people who hold the same faith as me" (SALT, AU, 4★). "Us habesh ppl have been underrated for timeeee‼️" (Jebena, AU, 5★). "One of the best things to happen for the EthiEri/Habesha community, especially for those of us who are in different part of the world" (Jebena, US, 5★). These apps are diaspora-first, not local-first.

**L4, prompts and effort.** "Requiring a minimum of 6 photos and 3 prompts, it forces users to put actual effort into creating their profile… users of the app are a bit more invested or serious about dating" (Hinge, US, 3★, 2022, 61 votes). "The prompts are amazing conversation starters that eased me into chats that were more in-depth and skipped the awkward small talk. I matched with my current boyfriend on my first or second day" (Hinge, US, 5★). Boo's personality test is praised as onboarding that *pays off*: "The personality tests and deep questions bring out things you'd want in a long-term partner" (Boo, AE, 5★).

**L5–L6, trust and safety as loves.** These are small but telling. "Verified Profiles Make a Big Difference… more quality users, thanks to verification features that make the platform feel safer" (Tinder, IN, 5★, 2025). "Love that they verify all profile photos so you don't just have a bunch of 'can't show face for work reasons'" (Boo, AU, 5★). On faith apps a privacy control is loved: "blur your photo if you don't want someone to see it then give the option for them to see it when you're ready" (Muzz, US, 5★, female perspective, 44 votes). Salams has a similar "blurring of my image option which is a nice plus for females".

**Not loved:** streaks, boosts, super likes, and gamified mechanics generally. Positive mentions of paid features are almost always hedged with price complaints.

### 2.2 What users HATE

Base: 7,698 reviews rated 1–3★. "Macro" is the average per-app rate across 40 apps (§1.2). Ranking combines frequency, breadth and intensity.

| # | Pain | Corpus (1–3★) | Macro | Top apps (share of that app's low reviews) | Grade |
|---|---|---|---|---|---|
| P1 | **Paywalls on the core loop:** pay to reply, to see likes, to be seen; "money grab" | **1,089 (14.1%)**. Any paid-tier mention: 1,907 (24.8%). See-likes paywall 175; pay-to-be-seen 170 | 15.2% | Hily 37%, eharmony 33%, League 26%; LGBTQ+ group 20%, faith 18% | Anecdote, 44 apps |
| P2 | **Fake profiles, bots, catfish, escorts, "promote my Instagram/OnlyFans"** | **1,069 (13.9%)** | 13.6% | tantan 55%, happn 30%, Hily 30%; South Asian 22.5%; India storefront 25.9% | Anecdote, 44 apps; matches Pew (52% say scam accounts are common) |
| P3 | **Bugs, crashes, lost messages** | 857 (11.1%) | 10.7% | Feeld 40%, OkCupid 27%, Grindr 17% | Anecdote |
| P4 | **Bans and suspensions, often with no reason given** | **846 (11.0%)**; **43% of those say no reason or explanation** (364); ≥44 say they were banned after someone reported them | 7.2% | Hinge 32%, Tinder 21%, Grindr 17%; **ng 17.4%, gh 16.1%, ke 15.7%** vs us 7.3% | Anecdote, 31 apps; Trustpilot repeats it for Tinder, Hinge, Bumble and Muzz |
| P5 | **Waste of time / no results** | 845 (11.0%) | 11.9% | AI 16.7%, intentional 15.4%, South Asian 14.3% | Anecdote |
| P6 | **Location and distance:** shown people far away or abroad, radius limits, wrong city | 652 (8.5%) | 10.0% | happn 20%, Hily 20%, Raya 13%; intentional 12.7%, faith 11.1% | Anecdote |
| P7 | **Support unreachable or automated** | 587 (7.6%) | 8.1% | Salams 19%, Shaadi 18%, eharmony 17% | Anecdote |
| P8 | **Billing traps:** auto-renew, refusing refunds, "free trial" charges | 577 (7.5%) | 9.1% | **eharmony 50%**, Amata 26%, Timeleft 21%; **AI group 16.2%** | Anecdote |
| P9 | **Algorithm unfairness and low visibility:** shadow bans, same profiles recycled, "no one sees me" | 524 (6.8%) | 5.9% | Hinge 27%, Raya 13%, Bumble 11% | Anecdote |
| P10 | **Romance fraud and scams:** money, crypto, "airtime", sextortion, bar-bill scams | 211 (2.7%) | 3.0% | tantan 15%, Aisle 10%, happn 7%; South Asian 6.3%, African 3.9% | Anecdote; FTC/IC3 data agree (§2.8) |
| P11 | **Harassment:** creeps, unsolicited nudes, stalking, "won't take no" | 193 (2.5%) | 2.6% | SCRUFF 11%, Taimi 9%; LGBTQ+ 6.1% | Anecdote; Pew (N3) shows reviews under-count it |
| P12 | **Race and ethnicity:** exclusion of Black women; ethnicity filters demanded or rejected; caste | 124 (1.6%) | 1.5% | Raya 4.7%, Shaadi 4.4%, League 3.7% | Anecdote; academic (N19) |
| P13 | **Ageism and age-range problems** | 120 (1.6%) | 1.7% | SALT 6.4%, League 5.6%, Taimi 5.3% | Anecdote |
| P14 | **Ghosting / no replies** | 110 (1.4%) | 1.6% | Muzz 4.1%, League 3.2% | Anecdote (floor); academic (N14) |
| P15 | **Long distance, abroad, visas, diaspora** | 110 (1.4%) | 1.6% | Raya, eharmony, Muzz; faith and South Asian 2.4% | Anecdote |
| P16 | **Thin or inactive pool** | 98 (1.3%) | 1.4% | eharmony, League, Raya; faith 2.8% | Anecdote |
| P17 | **Invasive data asks** (ID, income, "why do you need this") | 97 (1.3%) | 1.6% | Shaadi, Grindr, PoF | Anecdote |
| P18 | **Burnout, self-esteem, "designed to keep you scrolling"** | 87 (1.1%) | 1.1% | Hinge 5.4%, Muzz 5.1% | Anecdote (floor); academic (N9–N11) |
| P19 | **Verification failures and loops** | 81 (1.1%) | 0.9% | TrulyAfrican 7.1%, Trueflutter 6.2%; **ng 2.9%** (highest storefront) | Anecdote |
| P20 | **Safety incidents:** blackmail after a video call, robbery or kidnap set-ups, stalking | 71 (0.9%) | 1.0% | Aisle 6.6%, Grindr 2.7%; South Asian 2.0% | Anecdote |
| P21 | **Privacy:** data selling, can't delete, exposure | 65 (0.8%) | 0.9% | League, SALT, eharmony | Anecdote |
| P22 | **LGBTQ+ hostility:** chasers, cis men and couples intruding, trans users reported | 52 (0.7%) | 0.8% | **HER 13.8%, Taimi 9.8%** | Anecdote; HRW (N6) |
| P23 | **Religious mismatch:** "not practising", sect judgement | 44 (0.6%) | 0.8% | **Muzz 8.2%, Salams 7.1%**; faith 5.3% | Anecdote |
| P24 | **Married users / polygamy** | 32 (0.4%) | 0.4% | Muzz, Shaadi, Salams | Anecdote |
| P25 | **Onboarding too long** | 50 (0.6%) | 1.1% | Known 10.8%, eharmony 4.7% | Anecdote (§2.6) |
| P26 | **Gender imbalance** stated outright | 17 (0.2%) | 0.3% | Thursday events ("4x more men than women"), PoF "4:1 male:female" | Anecdote (floor); academic (N12) |

**P1, money between two people.** The most-voted complaint in the corpus is about it: "unless you pay for Tinder gold, the premium service…. Or at least you'd think it was premium! Wrong, for gold you still only get limited benefits" (Tinder, GB, 1★, 2022, 314 votes). The worst form, for Attune's purposes, is the **pay-to-reply** wall, because it makes the *other* person look like a ghost: "I realized I need a subscription to be able to respond; and I feel like I'm ghosting the guy even though I quite literally just can't talk to him" (Christian Mingle, US, 2★, 2026). Gendered paywalls are resented too: "As a man, I cannot blur my photos, but women can? I cannot see who liked me without paying, but women can for free?" (Muzz, GB, 1★). In African storefronts the paywall shows up as an *affordability and rails* problem rather than greed (§2.5): "Let women I[n] Africa not have to pay to see their likes" (Tinder, ZA, 1★); "it's a Muslim app but wants everyone to be a gold member as Muslim they should know not everyone can afford" (Muzz, KE, 5★).

**P2/P10, fakes and fraud.** "Subscription fees recently went up by 208%. So has bots – literally 7 to 9 out of 10 accounts are bots. I count it every time" (Tinder, ZA, 1★). Common fraud scripts:
- crypto pivots: "after a few days of chatting with some beautiful women, they bring up cryptos. None will send a video" (tantan, US, 1★);
- "Malaysian profiles" asking for crypto enrolment and documents (Jeevansathi, US, 1★);
- the Indian bar-bill scam: "asks to go washroom and she left and you will have to pay 25000 for a fake bill… bouncers will stop you" (Tinder, IN, 1★);
- the West African small ask: "please I need airtime help me with a gift… if you say no they start with threats" (AfroIntroductions, GB, 1★). TrulyAfrican reviewers report similar asks for "airtime or food for their family".

**P4, bans.** These are the most emotionally intense reviews in the corpus. Many reviewers had *paid* just before the ban: "banned my account immediately after subscribing to their 1 year Gold" (Tinder, ZA, 1★). "I was banned without a reason. No communication, nothing. Not even a chance to defend, why?" (Tinder, GH, 1★). Across apps and countries, the ban is a **weapon used against people who said no**:
- "People report me most times cus I refuse to send nudes and the moment they report me, bumble tends to block me without finding out why" (Bumble, NG, 3★, 2023);
- "This creepy guy was talking to me and he reported me when I didn't give him what he wanted. It got me permanently banned. On this app, it's a matter of who gets to the report b[utton first]" (Taimi, US, 1★, 49 votes);
- "sometimes when you don't agree to their offer then they report you" (Tinder, GH, 5★, 2021);
- "All it takes is one person to report you – for any reason or no reason at all – and Feeld immediately blocks you. The human review comes AFTER" (Feeld, US, 1★, 23 votes);
- "I was kicked off 5 times for people believing I was a cis gender male and not a trans male" (HER, US, 5★, 248 votes);
- "A lady can report ills done to her yet the guy isn't questioned… The lady account will be blocked" (Muzz, KE, 1★).

**P6, location.** "The smallest radius you can put is 500 miles. That makes me think that the creators are more about caste than about safety" (Dil Mil, US, 3★, 69 votes). "Most of them are out of state or the country. I have to pay money in order to filter by location" (SALT, US, 2★). Travellers and visitors pollute local pools: "offer an option to suppress profiles of people temporarily within the distance limit who don't live locally" (Bumble, US).

**P9, the algorithm.** "I do not see myself as an unattractive male but this app almost tries to make me believe this when I am not getting any matches" (Tinder, GB, 3★, 119 votes). "Because of Hinge's algorithms, only unattractive and creepy people see me" (Hinge, US, 1★, 44 votes). Users read opacity as manipulation.

**P11/P20, harassment and incidents.** The sextortion script on South Asian apps is consistent: "asked if you could talk on video call… And now that person… has been harassing me and blackmailing me to send money and threatening me that he/she would use my face with some obscene videos" (Aisle, US, 1★, 2023). "They ask for your contact info and FaceTime & later blackmail you" (Aisle, US, 1★). In Nigeria: "you'll have a nice chat with someone and probably fix a date, on the date you'll be robbed or kidnapped" (Olosho, NG, 2★, 2026). Safety behind a paywall is its own pain: "Users must PAY for SAFETY FEATURES… Why can I not delete an address I accidentally sent? What if that person actually comes to my house or stalks me? It happened" (Grindr, US, 1★, 81 votes).

**P14/P18, ghosting and burnout.** These are under-counted by keywords but vivid. "The insistence of the messages and ma[tches] gives women a constant hit of dopamine through constant validation" (Hinge, US, 2★). "This app has made me mentally ill, giving my issues about myself, my personality, my self-esteem" (Hinge, AU, 1★). "Honestly dating apps are dead in 2026 – endless swiping matches unresponsive to messages" (Tinder, GB, 1★). The academic and survey work in §2.8 suggests these are much bigger than reviews show.

### 2.3 Differences by region, culture, faith and identity

**West Africa (ng, gh, ke; 2,407 reviews, of which 1,216 are 1–3★):**

| Theme (% of 1–3★) | us | gb | ng | gh | ke | za |
|---|---|---|---|---|---|---|
| Bans | 7.3 | 10.5 | **17.4** | **16.1** | **15.7** | 14.3 |
| Ban, no reason given | 2.6 | 5.1 | 7.1 | 6.8 | 5.1 | 6.5 |
| Bugs | 10.8 | 11.1 | 14.5 | 3.5 | 15.7 | 12.8 |
| Verification failures | 0.8 | 0.9 | **2.9** | 0.6 | 0.5 | 1.2 |
| Paywall | 17.1 | 19.7 | 3.2 | 3.9 | 1.9 | 14.7 |
| Fakes and bots | 17.0 | 15.4 | 2.5 | 1.0 | 2.3 | 8.4 |
| Location | 11.4 | 11.9 | 3.2 | 1.6 | 1.9 | 4.0 |

Short reviews depress every rate for ng/gh/ke (§1.2). Even so, **bans are the #1 named pain in all three**, and Kenya ties it with bugs. Three things stand out:
1. **Access before matching.** Several walls come before anyone can meet anyone.
   - **OTP:** "Ghana appears to be effectively blocked from using this service. When you try to sign up with a Ghanaian phone number, the verification process fails, no OTP is received, even after requesting a resend or a call… it would be better to clearly state that the service isn't available in Ghana" (Bumble, GH, 1★, 2026). Of 22 "code never arrives" reviews, 12 are Nigerian.
   - **Verification queues:** "My account has been on selfie review for a week" (Tinder, NG, 1★, 2025). "My account has been under review for 2 months now" (Tinder, NG).
   - **Puzzles:** "unable to log into my Bumble account for months because of their verification puzzle" (Bumble, NG, 1★, 2026).
   - **Facebook:** "Even after you verify your account with a camera photo & ID, it still needs you to verify with your phone number & facebook. So what happens if you don't have facebook?" (TrulyAfrican, KE, 1★).
2. **Scam stigma runs both ways.** Foreign users on AfroIntroductions' Trustpilot write "All fake profile majority from Ghana and Nigeria", and Shaadi reviewers mention "people from Nigeria who ask for money". Meanwhile Ghanaian and Nigerian users are banned in volume, plausibly by anti-fraud systems tuned on that stigma. Attune's honest Ghanaian users will meet the same suspicion from diaspora matches.
3. **Faith and seriousness complaints are local.** "The Ghanaian men are all not serious they are here for games… They want sex before marriage and ask if you are virgin or not" (Muzz, GH, 2★, 2026). Faith expression is part of the positive voice too: "You will get your man here with hope and Blood of Jesus" (Bumble, GH, 5★).

**South Africa** sits between the two profiles. It has US-like paywall and fake rates and African-like ban rates. It also has the clearest race-filter debate in the corpus, in both directions: "I can't help that I'm attracted to people of my ethnic group" (Tinder, ZA) versus white users demanding to exclude Black profiles.

**Faith communities (711 low and 428 high reviews, 7 apps).** Faith apps have the second-highest *met my spouse* rate (8.9% of 4–5★, after South Asian apps' 12.9%) and the most *community fit* love (8.6%). Their low reviews carry the distinctive pains:
- **religious mismatch** (5.3%): "I get judged based on my Islamic sect even when the guys have their chosen Islam flavor as 'any muslim'… I got called 'a fake religious sunni'" (Salams, US, 2★);
- **missing denomination filters**: "if someone says they'd prefer someone Church of Christ or Baptist… let there be a way they can swipe through profiles ONLY of their preferred religious group" (Upward, US, 4★);
- **modesty versus photo rules**: lewd photos on Muslim apps; "won't let you use the app… unless you have a photo with direct eye contact" (Ark, AU, 1★); a covered-face (half-niqab) main photo not allowed (Salams, GB, 1★); on Trustpilot, a Muzz account "banned within 14 hours of creation" over a niqab photo;
- **polygamy, from both sides**: "a matrimonial app branding itself as 'Muslim' effectively bans or penalizes men who openly state they are already married and seeking a second wife… it unintentionally encourages dishonesty" (Muzz, KE, 2★, 2026), against complaints about deceptive married men (Muzz, Aisle, Shaadi);
- **family**: present in successes (Muzz, Dil Mil) and in breakups ("Her parents basically tore us apart by forcing her to break up", Ark, US, 4★).

**South Asian matrimony and dating (510 low reviews).** This group has the highest fake rate (22.5%) and fraud rate (6.3%), and the most "met my spouse" love (12.9%). Matrimony apps are judged on *seriousness*: "Don't even think about this app if you are serious about marriage… One nearly fooled me by sending fake IDs n fake video call as well!" (Jeevansathi, IN, 1★). Invasive or physical data asks are resented: "why does it ask for ur height & bmi??? …this isn't a doctor's clinic" (Aisle, IN, 1★). "There should be an option to hide profiles with the same gotra" (Jeevansathi): caste and clan filters are both requested and criticised.

**LGBTQ+ (719 low reviews, 5 apps).** This group has the highest paywall rate (20%), the highest harassment rate (6.1%) and the most bugs (18.9%).
- **Hostile jurisdictions:** "Why is impossible to sign up in Africa Ghana?… Please enable back registering in Ghana" (Grindr, GH, 1★, 2025). "I use an iPhone… still says unauthorized registration" (Grindr, GH, 2★, 2023). Grindr appears to restrict new registrations from Ghana. I could not confirm the policy itself.
- **Intrusion:** "too many couples looking for a threesome, and too many cishet men… There are legitimate safety concerns for queer women… we're leaving up identifying details" (HER, US, 1★). Chasers: "I wish there was a way to report people for being a chaser" (Taimi, US, 4★, 116 votes).
- **Being outed by a bug:** "I pay $40 a month for Unlimited so I am able to use the 'Incognito' mode and not be seen. Two days ago the app stopped letting me use any of the Unlimited functions so everyone was able to see my profile" (Grindr, US, 1★, 30 votes, a closeted user in a small city).

**Race, age and gender.**
- **Race:** "Racist and discriminatory selection process against black women" (Raya, US, 1★). "I have multiple black female friends with noteworthy accomplishments… who weren't accepted on Raya" (57 votes). "White men are extremely biased against black women" (League, US, 1★). "Very racist app… towards black women" (tantan, GH, 1★, 2026). Ethnicity filters are both demanded and attacked. Academic work (Curington et al. 2021) finds the same hierarchy (N19).
- **Age:** SALT and League users complain of age ranges not honoured, and of being out of place over 35 ("it was for people under 35, and I'm 39", Thursday). "At 61, I'm not moving to India! I have grandkids I live near" (iris, US, 3★).
- **Gender:** explicit imbalance complaints are rare in text (17). They are concentrated in events ("4x more men than women", Thursday) and in men's "as a guy you will absolutely not get many likes" (Bumble, GB). Bruch & Newman's large dataset shows the asymmetry is structural (N12).

**Diaspora and long distance (110 low reviews mention abroad, visas or long distance).** Cross-border is wanted by some and resented by many. "I get invites from men in India" (Aisle, US). "I selected a worldwide option… I get to view Mexico, Peru, Chile and Argentina as my only options. I want to meet everyone everywhere from Africa…" (Bumpy, KE, 4★). Visa-seeking is a named fear on Muzz ("a person looking for a visa"). The diaspora-first apps (Jebena, Bumpy) earn their love by *connecting across borders on purpose*.

### 2.4 Intentional, curated and AI matchmakers: lessons for "a few introductions a day"

These 13 apps (1,117 low reviews) are the nearest analogues to Attune Dating Mode. Their loves are Attune's thesis: intentional, calm, "a matchmaker behind the scenes". The quality-over-quantity love rate is 7.9–8.5%, against 2.2% for mainstream apps. Their pains are specific and avoidable:

| Failure mode | Evidence | What it means for Attune |
|---|---|---|
| **Hard preferences ignored** | "It can't remember my most basic search criteria: that I don't want kids" (Sitch). "Sometimes it says I want kids other times it doesn't… Ive clearly stated I dont want anything casual and it presents me with people that want a casual relationship" (Amata). "I set the location to Manhattan and Hobo[ken]… continues to show me people that do not fit my criteria" (Amata, 2026). "I described my ideal partner as someone who values human rights… Moderate felt like a clear mismatch" (Known). | Dealbreakers must be enforced filters, not soft signals |
| **Padding a thin pool** | "Contacted support and was told it's because they still don't have many users in my area. So they… present whatever they have instead of focusing on what you WANT. So that's quantity over quality" (Amata, 1★, 2026). "95% of ppl it recommends are across the country and even world" (iris). Breeze: "just getting 1-3 profiles a day… they blamed my preferences". | Spec §6.4's "never lower filters to fill an empty state" is right; add honest copy |
| **Opacity about the pool** | "I hate that I can't see a large number of people who are on the app… Are there more than 2 people on here at once? You can't tell" (Sitch). | Some coarse honesty is needed even without counts |
| **Pay per date or setup before any value** | "$80 upfront for 3 setups… only one match" (Sitch). "It costs $16 just to confirm the date. You don't get to talk to the guy, hear their voice" (Amata). "Pay $15 up front… If your date doesnt show up… you only get a credit" (Known). | Don't monetise introductions |
| **Invite gates and waitlists** | "You have to send 3 invites to be considered" (Known). "Spam your friends to 'move up the priority list'" (Teleport). "Claiming you're #7,304 on the wait list, but the numbers don't mean anything" (League, 100 votes). "Waitlisted for 5 years" (Raya). | No growth gates on entry |
| **Long onboarding that loses work or leads nowhere** | "Tried the onboarding call multiple times and it repeatedly fails to save… upwards of an hour" (Known). "Wasted half an hour filling out their endless questionnaire… profile is STILL 'under review'" six days later (Teleport). Yet: "From the personalized phone call onboard… Known reminds us that finding love is all about patience and sincerity" (5★). | Depth is fine if it saves, is fast to approve, and pays off |
| **No-shows and penalties** | "They never commit to a date, or the couple times they do, they cancel" (Breeze). "I was penalized" for being out of town (Amata). "They also shadowban your account for a week if you agree to meet someone twice and then change your mind" (Amata). | Accountability without punishment |
| **The explanation is the product** | "The AI explained why we might be a good fit, which made me way more open-minded. I ended up meeting someone I probably would've overlooked" (SciMatch, 5★, 2025). Against that: "The app tried to describe my personality based on my photo, but it was way, way off. I hit the 'not accurate' button and it still proceeded" (SciMatch, 1★). | Supports the Alignment preview, *if* grounded in user-stated data (spec §6.1); never infer from photos (spec §4.3) |

**Grade:** Anecdote, but consistent across six AI and seven curated apps. AI matchmakers have the worst billing rate (16.2%) and waste-of-time rate (16.7%) of any group.

### 2.5 Payments and access in West Africa

**At least 19 reviews** ask for, or praise, local payment rails (mobile money, airtime, SIM billing, bank transfer), or report local cards failing. 17 come from Ghana and Nigeria. The other two are Jebena ("Ethiopians and Eritreans can't pay by credit or debit card") and Heyama (praising "le payement par mobile money rapide et simple"). One Nigerian review says money was taken through Paystack but premium was never activated (Olosho, NG, 1★). Quotes:
- "Am not staying in a country that used Credit card we used Mobile money here" (Tinder, GH, 2★, 2022);
- "I'm from Ghana 🇬🇭. I can't use Mobile Money to subscribe to an iPhone" (Tinder, GH, 4★, 2025);
- "I wish I can pay… with my SIM card instead of account details" (Badoo, GH, 5★);
- "add bank transfer in your payment options, stop stressing Nigerians" (Tinder, NG, 3★, 2026);
- "Not accepting my Nigerian master debit card" (Bumpy, NG, 2★);
- "most of the times the card doesn't usually work" (Muzz, NG);
- "When we had to use airtime to buy coins was far more better" (Badoo, NG, 5★).

This is a small count but strongly concentrated: none come from in/ae/ca/au/gb. Two more reviews mention airtime only as a *scam* ask (§2.2 P10). **Constraint to check:** on iOS, digital subscriptions normally go through Apple's in-app purchase. Whether Apple offers mobile-money or carrier billing in Ghana today, and what external-payment rules apply there, is **unknown from this research** and needs verifying before any pricing design.

### 2.6 Onboarding-specific feedback

1,477 reviews mention sign-up, verification, questionnaires, waitlists, photos, codes or date of birth, and 1,213 of them are 1–3★. The sub-theme counts below are coarse (about 60–70% precision for "approval/waitlist", because "approved" and "rejected" also appear in payment complaints).

| Topic | Reviews (low) | Where | What users say |
|---|---|---|---|
| **Verification steps** | 629 (526) | Tinder 203, TrulyAfrican 36, Bumble 35, Badoo 31; **ng 110** | Loved when it keeps out fakes (§2.1 L5). Hated as queues ("selfie review for a week"), loops and puzzles, repeated re-verification ("having to send in video selfie reviews to ensure I'm human on 10+ occasions", Tinder US), rejections for glasses (Salams), and stacked steps (TrulyAfrican). "I don't understand why I have to go through such a long verification process just to log into my own account… other apps like Badoo or Tinder let you get started almost immediately" (Bumble, GH, 1★, 2026). |
| **Waitlists, applications, approval** | 380 (295) | Raya 62, League 49, Known, Teleport | "Why the waitlist? Is it supposed to make you feel important? Not me that makes me feel unimportant" (League). "The waitlist is a scam, they just wait to see if you will pay" (League). An exception: "frustrating being waitlisted for 4-5 days… but it was worth it" (Raya). |
| **Phone, SMS code, login** | 167 (149) | Tinder 41; ng 23 | Codes not arriving (§2.3). Logging out then being unable to get back in ("You guys log me out and am trying to log in… dont send code and on email too", Tinder NG). Changing SIM while travelling locks you out (Tinder ZA). |
| **Questionnaires and personality tests** | 37 (21) | Boo 15 (mostly positive), eharmony 10 | Praise when it shapes matches ("a Myers-Briggs test… from experience is usually on the money", Boo). Hate when it feels like admin: "cookie cutter multiple choice questions that you'd see on a job application… more of a data collection app" (eharmony). Even a user who "didn't mind the process" notes "spending an hour answering questions", and then could not see anyone's pictures (eharmony, 2★). One request *for more*: "If you want to be considered a serious Muslim marriage app I suggest you incorporate a lengthy questionnaire on sign up" (Muzz, GB). |
| **Paywall before value at sign-up** | 34 (33) | eharmony, Tinder, Badoo, Timeleft, Sitch | "UX suggested I had to sign up for a paid subscription to use" (eharmony). "You can't even select age or country without paying" (SALT). |
| **Sign-up stuck or bugs** | 34 (32) | OkCupid 12; ng 14 | "I can't create account" (Tinder NG). "Stuck on add photos option" for 24 hours (Bumpy GH). |
| **Photo rules** | 10+ | Ark, TrulyAfrican, Feeld, Muzz | Eye-contact rules, repeated rejections ("you keep rejecting even following your rules", TrulyAfrican KE), "bizarre and ambiguous photo restrictions" (Feeld). Faith users want modest photos *and* blur controls. |
| **Date of birth** | 5 | Tinder, Upward, Grindr, Muzz | Rare but severe: "The app bugged out and put the wrong birthday for me… now I have to wait 2000 days to use the app" (Tinder ZA). "Got my birthday wrong (and yes I typed it out right)… WOULDN'T LET ME EDIT" (Upward). "The app changes your age… my age had been changed for me to be four years younger" (Grindr). Someone else changing your DOB (Muzz). |

**Effort as a filter.** Users accept effort that signals seriousness: Hinge's "minimum of 6 photos and 3 prompts… users… more invested" (61 votes); "I love that Salt HAS you fill out certain amount of information!" (SALT, 5★). What they reject is effort that is *lost* (Known), *unexplained* (eharmony "job application"), *held in a queue* (Teleport, Tinder NG) or *gated by payment or invites*.

### 2.7 What users ask for

There are 372 explicit request sentences ("please add", "I wish", "you should", "bring back") across 44 apps. The topic grouping is coarse, so the examples are hand-picked:

| Request | Snippets / apps | Examples |
|---|---|---|
| **Better filters**: religion and denomination, intent, kids, height, ethnicity, caste/gotra | 42 / 23 | Upward denomination; Tinder ZA "only people who are looking for a short term relationship"; Jebena "receive people of the same religion"; Jeevansathi "hide profiles with the same gotra" |
| **Verification and anti-fake measures** | 42 / 22 | "make profile verification mandatory during account creation" (happn IN); "make profile verification compulsory, so as to reduce… Catfish accounts" (OkCupid NG); "why are you not able to do a reverse image search FOR ME" (iris) |
| **Free see-likes, cheaper, monthly, local payment** | 41 / 23 | "add mobile payment" (Tinder GH); "a deal for the one month subscription" (Taimi); "they should have a free trial" (RARE) |
| **Location control** (country choice, travel or roaming mode, accurate city) | 20 / 13 | "specify which countries exactly I need to search from rather than distance" (OkCupid GB); "a setting… allowing for roaming when traveling or not" (Upward) |
| **Conversation tools and anti-ghosting** | 19 / 10 | "A new report option of 'NO RESPONSE'" (Tinder ZA); "more prompts to choose from" (Tinder GB) |
| **Voice and video** | 16 / 11 | "Please add a calling feature so I can call a person directly and verify if they are real or a scammer" (Tinder US); "add a voice note to messaging" (OkCupid NG); Hily praised for in-app "FaceTime and call people… instead of giving someone your number, which helps a lot with verifying" |
| **Safety and reporting** | 13 / 11 | "a way to report people for being a chaser" (Taimi); "if a user keeps getting reported by different people for not being serious (for example, five genuine reports)… temporarily suspended, with an option to appeal" (Muzz NG) |
| **More people, fewer limits** | 12 / 11 | "I wish there were more people" (SALT); "limit swipes up to 10 people per day as there are not enough users yet" (Jebena: a request *for* limits in a small community) |
| **Undo or second look** | 7 / 5 | Accidental pass recovery (Feeld, BLK) |
| **Other** | small | Google Sign-in (Trueflutter NG); translation (Tinder NG); search in messages (Tinder GH); change gender identity without deleting (happn) |

### 2.8 Non-review voices: surveys, regulators, NGOs, academic work, Trustpilot

| # | Source | What it says (relevant here) | Grade |
|---|---|---|---|
| N1 | Pew Research Center, *From Looking for Love to Swiping the Field* (survey July 2022, n=6,034 US adults; published 2023-02-02), https://www.pewresearch.org/internet/2023/02/02/from-looking-for-love-to-swiping-the-field-online-dating-in-the-u-s/ | 53% of users rate their experience positive, 46% negative. 52% say scam accounts are common. 49% say apps are not too or not at all safe. 54% say apps made no difference or made finding a partner harder. | Moderate (large probability survey). **Read via Wikipedia's citation of it**, because pewresearch.org returned 403 to this session. |
| N2 | Pew, *The Virtues and Downsides of Online Dating* (Oct 2019, n=4,860), https://www.pewresearch.org/internet/2020/02/06/the-virtues-and-downsides-of-online-dating/ | 57% positive / 42% negative; 50% say scam accounts are common; 46% say not safe. | Moderate; same access caveat |
| N3 | Pew 2023 (N1), harassment of women under 50 who have dated online | Widely reported figures: 56% received sexually explicit messages or images they didn't ask for; 43% were contacted after saying they were not interested; 38% were called an offensive name; 11% were threatened with physical harm. **Not re-verified this session (403); confirm before quoting externally.** Harassment is only 2.5% of low *reviews*, so reviews under-count it badly. | Moderate if confirmed |
| N4 | FTC Data Spotlight, "Romance scammers' favorite lies exposed" (2023-02-09), https://www.ftc.gov/news-events/data-visualizations/data-spotlight/2023/02/romance-scammers-favorite-lies-exposed | $1.3B in reported losses in 2022, from about 70,000 people; median loss $4,400. 40% of people who lost money said contact began on social media, 19% on a dating site or app. Lies: military abroad, oil rig, sick or jailed, crypto "teaching", parcel customs. Romance-linked sextortion reports are up more than 8× since 2019, and 18–29s are over 6× as likely to report it. Crypto plus wires make up over 60% of losses. | Moderate (official complaint data; under-reported) |
| N5 | FBI IC3 Annual Report 2025, via Wikipedia "Romance scam" | Confidence/romance fraud: 23,159 complaints, $929.3M in losses. The same article cites UK Finance via the *New Statesman*: romance scams were the UK's fastest-growing cybercrime in 2023. | Moderate; second-hand (PDF not text-extractable here) |
| N6 | Human Rights Watch, *"All This Terror Because of a Photo"* (2023-02-21), 120 interviews, https://www.hrw.org/report/2023/02/21/all-terror-because-photo/digital-targeting-and-its-offline-consequences-lgbt | Documents 20 entrapment cases through Grindr and Facebook by security forces (Egypt, Iraq, Jordan) and 17 extortion cases; 16 of those entrapped were arrested. Six people who reported extortion were themselves arrested. Police created fake profiles and planted Grindr chats. Asks: regional moderation transparency, rapid-response channels with local LGBT groups. | Moderate (systematic NGO documentation; MENA, not West Africa) |
| N7 | Grindr's privacy record, via Wikipedia "Grindr" (citing SINTEF, the Norwegian DPA, *WSJ*, Hoang et al.) | HIV status shared with third parties (2018). Norway's DPA fined Grindr about €10M (2021). Distance trilateration attacks (2014, 2016), including with distance hidden. Distance auto-hidden in at-risk countries since 2019. | Moderate (regulator) / Weak (press) |
| N8 | Trustpilot company pages, read 2026-10-24 | Tinder 1.1★ (5,132 reviews, 89% 1★). Hinge 1.2★ (1,225, 92% 1★). Bumble 1.2★ (2,634, 87% 1★). Muzz 1.2★ (167, 96% 1★: "accused me of polygamy and banned my account"; "banned within 14 hours of creation" over a niqab photo). eharmony 2.9★ (4,450; 53% 1★, 42% 4–5★; praise for "deeper personality questions" and vetting). AfroIntroductions 2.4★ (803; "All fake profile majority from Ghana and Nigeria"). None of these companies invite reviews, so the pages skew to complaints. The themes match the corpus. | Anecdote |
| N9 | Pronk & Denissen, "A Rejection Mind-Set: Choice Overload in Online Dating", *Social Psychological and Personality Science* 11(3), 2020, doi:10.1177/1948550619866189 | Across three studies, the chance of accepting a partner fell by about 27% from the first option to the last as people viewed more profiles. | Moderate (experiments) |
| N10 | Thomas, Binder & Matthes, "The agony of partner choice", *Computers in Human Behavior* 126, 2022, doi:10.1016/j.chb.2021.106977 | Excessive partner availability is linked to fear of being single and partner-choice overload (title-verified; abstract not retrieved). | Moderate |
| N11 | Holtzhausen et al., "Swipe-based dating applications use and its association with mental health outcomes", *BMC Psychology* 8, 2020, doi:10.1186/s40359-020-0373-1 (n=437, Australia) | Users had higher distress (OR 2.51) and depression (OR 1.91). More frequent and longer use was linked to more distress. Yet 39.1% had entered a serious relationship with someone met on an app, and more reported a positive than a negative effect on self-esteem (40.4% vs 28.7%). | Weak to Moderate (cross-sectional, convenience sample) |
| N12 | Bruch & Newman, "Aspirational pursuit of mates in online dating markets", *Science Advances* 4(8), 2018, doi:10.1126/sciadv.aap9815 | Large message-log study in four US cities. Users contact people on average about 25% more desirable than themselves; women's desirability peaks at 18 and men's at 50 (headline figures as reported by *The Atlantic* and *NYT*). | Strong (large behavioural dataset) |
| N13 | Rosenfeld, Thomas & Hausen, "Disintermediating your friends", *PNAS* 116(36), 2019, doi:10.1073/pnas.1908630116 | Since about 2013, meeting online has been the most common way US heterosexual couples meet. It displaces introductions by friends and family. | Strong (nationally representative) |
| N14 | Koessler, Kohut & Campbell, "When Your Boo Becomes a Ghost", *Collabra: Psychology* 5(1), 2019, doi:10.1525/collabra.230; LeFebvre et al., *Imagination, Cognition and Personality* 38(4), 2019, doi:10.1177/0276236618820519 (N=99) | People who are ghosted report more distress than after direct break-ups. Most emerging adults have both ghosted and been ghosted. | Moderate / Weak |
| N15 | Thompson, "'I can be your Tinder nightmare'", *Feminism & Psychology* 28(1), 2018, doi:10.1177/0959353517720226 (526 posts); Gillett, "Intimate intrusions online", *Women's Studies International Forum* 69, 2018, doi:10.1016/j.wsif.2018.04.005 | Harassment clusters around *rejection*: a "not hot enough" discourse and a missing discourse of consent. Abuse is normalised as part of using dating apps. This matches the "refused, then reported" ban pattern (§2.2 P4). | Moderate (qualitative) |
| N16 | Rochadiat, Tong & Novak, "Online dating and courtship among Muslim American women", *New Media & Society* 20(4), 2018, doi:10.1177/1461444817702396 (n=16) | Users value agency, control over interaction and confidentiality. Challenges: social stigma, fear of misrepresentation, keeping religious courtship practices. | Weak (small qualitative); directly relevant to faith users |
| N17 | McWilliams & Barrett, "Online Dating in Middle and Later Life", *Journal of Family Issues* 35(3), 2014, doi:10.1177/0192513X12468437 (n=18, aged 53–74) | Women face competition from younger women. Both genders screen for "youthful" traits. | Weak |
| N18 | Albury & Byron, "Safe on My Phone?", *Social Media + Society*, 2016, doi:10.1177/2056305116672887; Brubaker, Ananny & Crawford, "Departing glances", *New Media & Society* 18(3), 2016, doi:10.1177/1461444814542311 | Same-sex-attracted young people manage risk through selfie exchange and visibility choices. Leaving an app is a process (delete, return, hide), not one moment. | Weak (qualitative) |
| N19 | Hutson, Taft, Barocas & Levy, "Debiasing Desire", *PACM HCI* 2 (CSCW), 2018, doi:10.1145/3274342; Curington, Lundquist & Lin, *The Dating Divide* (University of California Press, 2021) | Platform design (race filters, sorting, prompts) can worsen or reduce bias without removing user autonomy. US data show a racial hierarchy in replies, with Black women and Asian men the most excluded. | Moderate |
| N20 | Whitty, "Do You Love Me?", *Cyberpsychology, Behavior, and Social Networking* 21(2), 2018, doi:10.1089/cyber.2016.0729; Whitty & Buchanan 2012, doi:10.1089/cyber.2011.0352 | Romance scams are advance-fee fraud run by international groups. Victims tend to be middle-aged, well-educated women who score high on trust and impulsivity. | Moderate |
| N21 | Hancock, Toma & Ellison, "The truth about lying in online dating profiles", CHI 2007, doi:10.1145/1240624.1240697 | Small, frequent deceptions (height, weight, age) are common; large lies are rare. | Moderate |
| N22 | Bumble and Hinge, via Wikipedia "Bumble (app)" and "Hinge (app)" | Bumble: Private Detector nude-blur (2019, open-sourced 2022); Deception Detector (2024) claims to block up to 95% of spam and scam accounts; women-first rule loosened from 2024, with the reply window extended to 72h (2026). Hinge markets itself as "designed to be deleted"; "Most Compatible" recommends one person a day. | Weak (vendor claims and press) |
| N23 | **Not reachable this session** | Reddit (refused by WebFetch); Nairaland (403); Ofcom (403); Singles in America (403); Forbes Health dating-fatigue survey (403); pewresearch.org (403); PMC (captcha); PNAS, Science (403); eSafety Australia (timeout). No peer-reviewed study of dating-app user experience *in Ghana* was found or reachable. **The Ghana evidence here is the review corpus only.** | — |

### 2.9 How this compares with the couples market (01-market-reviews, 2026-10-16)

The top pain is the same: paywalls on the core loop. The second pain differs: couples apps fail on sync bugs, while dating apps fail on **fakes and enforcement**. Both markets reward low-pressure rituals and punish retroactive paywalls. Dating adds three pains with no couples equivalent: **being banned**, **being defrauded**, and **being shown the wrong people**. All three are trust failures. Fixing them is what makes "quality over quantity" believable.

---

## 3. Implications for Attune

Each item says what to build, change, avoid or measure, and the evidence behind it. "Spec" means `lib/architecture/DATING_MODE_SPEC.md`.

**Money and the core loop**
1. **Never charge to reply, to see that you matched, to be introduced, or to be seen.** This is the #1 pain (§2.2 P1: 14% of low reviews; 25% mention a paid tier). Paywalled replies create *perceived ghosting* that blames the other person (Christian Mingle). Spec §7 already forbids monetised revelation; extend it to message replies and introduction visibility.
2. **No per-introduction or per-date fees, and no payment before a first value moment.** Upfront setup and confirmation fees (Known $15, Amata $16–20, Sitch $80) are why the curated and AI apps have the worst billing (16%) and waste-of-time (17%) rates (§2.4). If Dating is ever monetised, keep the free path complete.
3. **If and when there is pricing, design for local rails, and check the iOS constraint first.** Ghana and Nigeria reviewers ask for mobile money, SIM or airtime billing and bank transfer, and report cards failing (§2.5: 17 of at least 19 rail reviews). Paystack fits Android and web. On iOS, digital subscriptions normally need Apple IAP, and local availability is unverified.

**Trust, enforcement and safety**
4. **Make enforcement explainable, graduated and appealable, and never auto-ban on a single report.** Bans are the #1 named pain in ng/gh/ke (15.7–17.4% vs 7.3% US). 43% of ban reviews say no reason was given. Across Bumble NG, Taimi, Tinder GH, Feeld, HER and Muzz KE, people were banned after refusing sexual or meeting demands (§2.2 P4).
   - **Build:** reason categories shown to the account holder (never the reporter's identity or words); a step before suspension (reduced reach, or re-verify); one human-reviewed appeal with a stated time limit; report-credibility weighting (repeat reports from people the reported user declined count less); a clear "you were reported after declining a request" safeguard.
   - **Measure:** overturned-ban rate by country.
   - Spec §8's "never reveal suspension… cause" conflicts with this (Q3).
5. **Treat fraud as a design constraint without profiling Ghanaian users.** Foreign users stereotype Ghana and Nigeria profiles as scams (N8, §2.3), and Attune's first users are exactly those users. Keep spec §8–9's money-request detection, scam category and education. Add West African scripts to the education: **airtime and data top-ups, "a small gift", mobile-money requests** (AfroIntroductions, TrulyAfrican), alongside the FTC's military, oil-rig and crypto scripts (N4). Never use country, network or name as a risk signal.
6. **Keep the first contact inside Attune; voice before video, and no number exchange required.** Sextortion follows early video calls and number swaps (Aisle, Jeevansathi, Grindr; FTC sextortion up 8×). Users want in-app calls precisely so they can check someone is real without giving a number (Hily praise; Tinder US and OkCupid NG requests). Show a one-time safety card before the first call or image share. Blur images by default, with view-or-report (Bumble Private Detector precedent, N22).
7. **Safety controls are never paid and work instantly.** "Users must PAY for SAFETY FEATURES" (Grindr, 81 votes). A paid incognito failing outed a closeted user (Grindr). HER users want a true pause. Block, report, pause, hide and delete stay free and immediate. Spec §2's frictionless exit already says this; extend it to pause and hide.
8. **Offer photo blur until mutual interest, as a choice.** Muslim women praise "blur your photo… give the option for them to see it when you're ready" (Muzz, 44 votes; Salams). It fits spec §4.2's psychology-first, photos-secondary design. Offer it to everyone. Muzz's women-only version drew resentment from men.

**Sign-in, verification, onboarding**
9. **Prove phone-code sign-in on Ghanaian and Nigerian carriers, and fail honestly.** "Ghana appears to be effectively blocked… no OTP is received, even after requesting a resend or a call" (Bumble GH, 2026); 12 of 22 "code never arrives" reviews are Nigerian. This validates `AUTH_ONBOARDING_ENGINE.md`'s Ghana-direct SMS and voice fallback. Add: a clear "we can't reach this number yet" state with next steps, no silent dead-ends after a long sign-up, and per-carrier OTP success as a launch metric. When Apple/Google sign-in comes, it is a resilience path for exactly this failure.
10. **Verification: one liveness selfie, a visible status with a time limit, a human fallback, and no lock-outs for existing users.** Verification is loved for "real people" (§2.1 L5). It is hated as week-long queues (Tinder NG), puzzles (Bumble NG), stacked steps and Facebook requirements (TrulyAfrican KE), repeated re-checks (Tinder US, "10+ occasions") and eye-contact rules (Ark). Don't require Facebook. Keep ID optional.
11. **Date of birth: show the derived age back before saving, and provide a protected correction path.** DOB errors are rare but lock people out ("wait 2000 days", Tinder ZA; "got my birthday wrong… WOULDN'T LET ME EDIT", Upward; "the app changes your age", Grindr). The owner's DOB-for-everyone rule makes this flow critical for *every* user. Show "You'll appear as 29" and require a confirm. Spec §4.1 already describes a protected correction flow.
12. **Onboarding depth is welcome when it saves, is explained, and visibly drives introductions.** Praise: Boo's personality test, Hinge's 6 photos and 3 prompts ("users… more invested"), SALT ("HAS you fill out certain amount of information"). Rage: Known "fails to save… upwards of an hour"; Teleport "endless questionnaire" then days "under review"; eharmony "job application". Build: save per step, a short required core, optional depth with "why we ask", and no review queue without a stated time.
13. **No invite-gates and no open-ended waitlists.** These are resented across League (100 votes), Raya ("5 years"), Known and Teleport, as Agapé's recruiting gate was in the couples market (01 §3.2 #17). If supply is thin in a city, say so (item 15).

**Matching**
14. **Hard preferences stay hard, and the explanation cites them.** The main AI-matchmaker failure is ignoring stated dealbreakers on kids, intent, location, ethnicity and religion (§2.4). Make dealbreakers explicit fields enforced server-side. The Alignment preview (spec §4.2) must never present someone who violates them. When it explains a fit, ground it in what the user said; "the AI explained why" is SciMatch's best review.
15. **When the pool is thin, say so; never pad.** Amata "present[s] whatever they have", and iris shows a 61-year-old in Michigan people in India. Spec §6.4 "never lower filters to fill an empty state" is correct. Pair it with calm, coarse honesty: "Attune is still small in Kumasi. We'll introduce you when there's a good fit." That answers Sitch's "are there more than 2 people on here?" without revealing counts (spec §1).
16. **Location: city or region, home versus visiting, and an explicit private cross-border choice.** Location is 8.5% of low reviews (macro 10%), and 12.7% for intentional apps. Users want to choose countries rather than a radius (OkCupid GB, Bumpy KE), hide travellers (Bumble US), and not be shown strangers abroad by default (iris, SALT, Ark). For Ghana plus the diaspora: "Open to meeting people in: Ghana / UK / US / …", private, off by default (Q6).

**Culture, faith and identity**
17. **Offer optional, self-declared faith fields with importance and visibility controls, never inferred.** Faith and South Asian apps produce the most "met my spouse" reviews (8.9% and 12.9% of 4–5★). Faith apps also lead on community-fit love (8.6%). Their pains are mismatch (5.3%), sect judgement (Salams) and missing denomination filters (Upward) (§2.3). Spec §4.1 bars collecting religion without review, so this needs the cultural reviewer (Q4).
18. **Decide the polygamy and married-user policy explicitly, before launch.** Muzz is attacked from both sides: a ban "encourages dishonesty" (KE), while "married men" deceive others (Muzz, Aisle, Shaadi). Trustpilot: "They accused me of polygamy and banned my account". A silent policy produces both complaints (Q5).
19. **LGBTQ+ safety in hostile jurisdictions is a launch gate.** Grindr sign-up appears blocked from Ghana. HRW documents police entrapment through fake profiles (N6). HER and Taimi users report intrusion and chasers. A trans man was "kicked off 5 times" after being reported as cis. The owner's rule ("who you want to meet" never shown, mutual only, country safety notes) matches the evidence. Add: no distance ever, verified-only introductions for same-gender seekers in high-risk countries, a "suspected fake or entrapment profile" report path, and enforcement that cannot be weaponised by reporting someone's gender identity (Q10).
20. **Design against race and colourism bias, and audit it.** Black women report exclusion (Raya, League, tantan GH), and ethnicity filters are demanded and attacked (§2.3). Spec §4.3 already forbids photo, skin-tone and attractiveness-derived ranking; keep it. Run the §6.5 cohort audit of exposure and mutual interest (N19).

**What to measure**
21. **Measure graduations, not engagement.** The strongest love is "it worked" (§2.1 L1), and happy reviewers delete the app (Bumpy ZA "made me delete the app"; Hinge "designed to be deleted", N22). Choice overload and distress are documented (N9–N11).
    - **Primary:** mutual interest per introduction, first message within 48h of a match, private self-reported "we met", and Dating → Relationship Mode links.
    - **Guardrails:** report rate, overturned-ban rate by country, OTP success by carrier, verification time to decision, money-request flags per 1,000 messages, and "no good fit this week" rate by city (the thin-pool signal).

---

## 4. Open questions for the owner

| # | Question | Recommendation and why |
|---|---|---|
| Q1 | Will Dating Mode ever be paid, and for what? | **Free at launch with a complete free path. Never charge to reply, to see a match or to be introduced.** Paywalls are the #1 pain outside West Africa, and per-date fees sink curated and AI apps (§2.2 P1, §2.4). Decide on optional extras after a pilot, and check iOS payment rules for Ghana first (§2.5). |
| Q2 | How many introductions a day, and what happens on days with nobody suitable? | **1–3 a day, and an honest "no good fit yet" state on thin days, with no padding.** League's "3–5 people at a time" is praised (337 votes). Breeze's "1–3 profiles a day… they blamed my preferences" and Amata's padding are punished (§2.4; spec §6.4). |
| Q3 | Should a suspended user be told why? Spec §8 says never reveal suspension cause. | **Yes: show the category (spam, harassment, scam, underage risk, impersonation) and one human appeal. Never reveal who reported or what they wrote.** No-reason bans are the top West African complaint, and retaliatory reporting is documented across six apps (§2.2 P4). Revise spec §8 accordingly. |
| Q4 | Collect faith, and how deep? | **Optional self-declared religion plus "how important is this to you", visible only if chosen. Optional Christian denomination. Defer Muslim sect.** Sect judgement is a named harm (Salams). Needs the cultural reviewer's sign-off under spec §4.1 (§2.3). |
| Q5 | Polygamy and already-married users? | **Not permitted in Dating Mode v1, stated plainly in the rules. "Hiding that you're married" becomes a report category.** The Muzz evidence cuts both ways; a silent policy is the worst option. Revisit with faith advisers (§2.3). |
| Q6 | Cross-border matching for the diaspora: default on or off? | **Off by default, with an explicit private "open to meeting people in [countries]" choice one tap away.** Unwanted far-away suggestions are a top location pain (iris, Ark, SALT). Diaspora-first apps win when cross-border is deliberate (Jebena, Bumpy) (§2.3, P6). |
| Q7 | In-app voice or video in dating chat? | **In-app voice early (v1 or v1.1), behind mutual consent and a one-time safety card. Defer video.** Users want to check "real or a scammer" without giving numbers. Early video is the sextortion vector (§2.2 P20, N4). |
| Q8 | How strict is verification before introductions? | **Liveness selfie required for everyone. ID optional for a badge. A target decision time of under 24 hours, shown in the app, with a human fallback.** Loved when it removes fakes; hated when it queues or loops, especially in Nigeria (§2.6). |
| Q9 | Any role for family (wali, chaperone)? | **Not in v1 beyond spec §9's "share your date plan with a trusted person". Put it to the Ghanaian cultural review.** Family appears in success stories (Muzz, Dil Mil) and in break-ups (Ark). The evidence is thin, but family is culturally central in Ghana (§2.3). |
| Q10 | What does a same-gender seeker in Ghana see? | **Mutual, verified introductions only. A country safety note before opt-in. No distance and no orientation anywhere on the profile. A dedicated report path for suspected entrapment. Reports about someone's gender identity never trigger automatic action.** Grindr sign-up appears blocked from Ghana; HRW documents entrapment; trans users on HER were repeatedly reported off (§2.3, N6). Needs an LGBTQ+ safety reviewer with West African context. |
| Q11 | How much profile effort should Dating Mode require before introductions start? | **A modest required core (1+ photo, 2–3 prompts or values answers), optional depth, and progress saved at every step.** Effort read as seriousness is praised (Hinge, SALT). Effort that is lost or gated is the most enraging onboarding experience (Known, Teleport) (§2.6). |

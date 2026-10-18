# 01 — Couples / Relationship App Market: What Users Love, Hate and Ask For

*Research date: 2026-10-16. Scope: the market as seen by users, not vendors. Feeds the "best relationship app ever" synthesis.*

---

## 0. How this was researched (read first)

**Primary evidence: a 15,746-review App Store corpus I pulled myself.** For 44 couples apps I downloaded US App Store customer reviews through Apple's public review feed (`itunes.apple.com/us/rss/customerreviews/.../sortby={mostrecent|mosthelpful}/json`). That is up to 500 most-recent plus 500 most-helpful reviews per app, deduplicated. Every review has a star rating, date, title and full text. 4,561 of them are rated 1–3 stars. Date range: 2012 to 2026-10-14. Store-wide rating counts (for example Paired's 209K ratings) come from the iTunes Search API on 2026-10-16.

**How the counts work.** I tagged each review against keyword themes ("paywall", "sync/bug", "repetitive", "streak", "ex/breakup" and so on) and counted matches. I hand-checked random samples. Precision is about 85–90% for paywall and bug themes. It was poor for "repetitive" and "closer" until I tightened those patterns. The tightened figures are the ones used below. Read the counts as **frequency signals, not exact prevalence**:
- **"N reviews / M apps"** means N reviews matched the theme across M apps. For loves, the base is all 15,746 reviews. For pains, the base is the 4,561 reviews rated 1–3 unless stated otherwise.
- Keyword matching misses paraphrases, so counts for subtle themes (partner disengagement, notification awkwardness) are floors, not estimates.

**Secondary evidence:**
- App Store review pages read directly.
- Trustpilot (Bond Touch, Lovebox, OurRitual).
- Press: Refinery29, Android Police, Autostraddle, TechCrunch, The Markup, ABC (AU), The Conversation, Vice.
- Academic and government work: the eSafety Commissioner (AU), Griffith University, Chatterjee et al. IEEE S&P 2018, Freed et al. CHI 2018, the Open University/Paired evaluation (JMIR mHealth 2025), a 2025 scoping review of relationship apps, Pew.
- Vendor and help-centre pages, only where they state policy (Paired, Between, Lasting, Bond Touch).
- Third-party review aggregators (JustUseApp, Unstar) are used only for verbatim review quotes. Their sentiment and "safety" scores are machine-generated and often contradict themselves, so I ignore them.

**Limits, stated plainly:**
1. **Reddit was not reachable.** Both WebFetch and WebSearch refuse reddit.com, so this document has no Reddit threads. Mumsnet stands in for forum voice on location tracking.
2. **Google Play review text was not retrievable.** Play pages truncate, so Android-specific complaints are under-represented.
3. **US App Store only.** Non-US couples (for example Korea, where Between is from) are under-represented.
4. **Selection bias.** People who quietly churn, such as couples where one partner stopped engaging, rarely write reviews. Expert sources flag this pain more often than reviews do.
5. Some apps named in the brief could not be identified or have no user evidence. See §2.9.

---

## 1. Corpus overview

| App (category) | Reviews pulled | % rated 1–3 | Avg ★ of pulled sample | Store rating (count) |
|---|---|---|---|---|
| Paired (daily Qs) | 890 | 39% | 3.67 | 4.72 (209K) |
| Agapé (daily Qs) | 531 | 22% | 4.21 | 4.80 (26K) |
| Lovewick (Q cards) | 113 | 27% | 3.92 | 4.77 (1.9K) |
| Evergreen (Qs/quizzes, streaks) | 438 | 26% | 4.05 | 4.82 (55K) |
| Flamme (Qs, AI coach) | 45 | 13% | 4.47 | 4.72 (417) |
| Couply (quizzes, AI coach) | 91 | 14% | 4.44 | — |
| Couple Joy (LDR quizzes/widgets) | 719 | 16% | 4.43 | 4.86 (39K) |
| Candle (2025, "Duolingo for relationships") | 334 | 33% | 3.79 | 4.76 (11.6K) |
| Cozy Couples (pet/house + Qs) | 857 | 19% | 4.18 | 4.84 (46K) |
| CoupleGrow | 116 | 82% | 2.03 | 4.66 (6.4K) |
| Love8 (widgets/location/pet) | 431 | 30% | 3.90 | 4.61 (7.2K) |
| Couple Game: Relationship Quiz | 377 | 49% | 3.22 | 4.49 (5.7K) |
| Gottman Card Decks | 103 | 10% | 4.59 | 4.83 (1.7K) |
| LoveTrack | 25 | 8% | 4.72 | 4.8 (343) |
| Together: Rekindle & Rebuild (John Delony) | 80 | 9% | 4.71 | 4.91 (1.6K) |
| Connected (2026, AI + Gottman/EFT) | 9 | — | 4.11 | 4.87 (101) |
| Lasting (Gottman-based program) | 330 | 49% | 3.15 | 4.68 (25K) |
| Love Nudge (5 Love Languages) | 407 | 55% | 3.08 | 4.58 (18K) |
| Marriage 365 | 299 | 3% | 4.87 | 4.88 (499) |
| Maia (AI couples support) | 44 | 23% | 4.18 | 4.79 (379) |
| Ember (AI couples) | 46 | 54% | 2.93 | 4.57 (710) |
| OurRitual (couples therapy) | 32 | 78% | 1.88 | 4.56 (310) |
| ReGain (couples therapy) | 902 | 15% | 4.37 | 4.80 (13K) |
| Blueheart (sex therapy) | 18 | 50% | 3.06 | 4.54 (200) |
| Coral (intimacy) | 234 | 56% | 2.97 | 4.56 (3.5K) |
| Spicer (sex-idea matching) | 614 | 21% | 4.19 | 4.60 (3.9K) |
| Desire (dares) | 383 | 23% | 4.06 | 4.31 (779) |
| Couples Games & Challenges | 487 | 31% | 3.82 | 4.89 (23K) |
| LoveSync (desire signalling) | 57 | 77% | 2.25 | 3.86 (180) |
| Between (private chat/memories) | 876 | 12% | 4.52 | 4.80 (21K) |
| Just Between Us (private chat) | 160 | 31% | 3.91 | 4.76 (2K) |
| Widgetable (widgets/pets) | 979 | 27% | 4.05 | 4.92 (387K) |
| Locket Widget (photo widget) | 991 | 11% | 4.46 | 4.76 (579K) |
| Loveit (LDR drawing widget) | 412 | 36% | 3.70 | 4.47 (3.9K) |
| Couple Tree | 47 | 30% | 3.89 | 4.83 (1.9K) |
| Bond Touch (touch bracelet app) | 656 | 57% | 2.93 | 4.65 (18K) |
| Lovebox (hardware messenger app) | 606 | 23% | 4.17 | 4.74 (3.9K) |
| Cupla (shared calendar) | 227 | 30% | 3.86 | 4.69 (2.3K) |
| Raft (shared calendar) | 82 | 49% | 3.32 | — |
| Honeydue (couples finance) | 657 | 67% | 2.69 | 4.49 (10K) |
| Life360 (location; couples use filtered) | 1,000 | 21% | 4.21 | 4.79 (3.1M) |
| Covenant (Christian marriage) | 15 | 27% | 4.07 | 4.2 (49) |
| Pookie (2026 widgets/games) | 23 | 52% | 2.91 | 4.63 (1.4K) |
| Amora (2026) | 3 | — | — | 4.63 (166) |

**The headline number is the gap between columns.** Store ratings sit at 4.5–4.9 almost everywhere. The *helpful* and *recent* reviews tell a harsher story: 39% of Paired's sampled reviews, 49% of Lasting's, 55% of Love Nudge's and 67% of Honeydue's are 1–3★. High store averages are inflated by in-app rating prompts. Several reviewers complain about those prompts directly. Covenant users report being asked "at least 10 times in 48 hours", and a Lasting user was asked "before we ever started". **Do not benchmark against store averages.**

---

## 2. App-by-app profiles

Each profile covers core features, loves, complaints, requests, pricing, and safety/breakup notes. "Corpus" means my App Store pull. Reviewer handle and date are given for traceability.

### 2.1 Daily-question / conversation apps (the market's centre of gravity)

#### Paired — the category leader
- **Core:** a daily question answered privately, then revealed to both partners. Also quizzes, "Journeys" (expert courses), games, timeline and special dates. Claims 8M downloads ([App Store](https://apps.apple.com/app/id1469609343)). The Open University/Brighton evaluation (n>4,400 over 3 months) reported a 36% rise in relationship quality. The study's principal investigator later became Paired's Chief Relationships Officer, there was no control group, and the report was preliminary ([OU](https://university.open.ac.uk/research-projects/enduring-love/paired)). The peer-reviewed follow-up (JMIR mHealth 2025, n=440 longitudinal, 745 survey, 20 interviews) found quality rose with use. Interviewees said the app's neutral framing made hard topics easier to raise. Participants were self-selected ([JMIR record](https://mhealth.jmir.org/2025/1/e55433)).
- **Pricing:** the official FAQ says one subscription covers both partners: $79.99 per couple per year, with a 7-day trial and a free tier of one daily question ([Paired FAQ](https://www.paired.com/frequently-asked-questions)). A $14.99/month tier is also listed. Reviewers cite $60–70 a year in 2022 ([App Store](https://apps.apple.com/us/app/paired-couples-relationship/id1469609343?see-all=reviews)).
- **Loves:**
  - Conversations "we haven't thought" of. LDR intimacy: the top-voted review (98 votes) is a long-distance couple.
  - The habit: "something we do every morning as part of our routine" (eembezzle, 2023).
  - Gaps revealed by comparing answers. DeafiniteAlle (2024): "Every time we found gaps, we actually sat down —no electronics".
  - A private channel: "No risk of accidentally typing in a different group" (MoeVel, 2021).
  - Inclusive representation, praised by queer couples. "we've never felt like we were navigating a hetero-based app as a same[-sex couple]" (Mmaaddeenn, 2025). Trans couple @selfmadekayd (2022): "LOVE this app".
- **Complaints (corpus, 345 reviews rated 1–3):**
  - **Paywall and pricing (139 reviews):** "pretty much the only thing available without the 'premium account' is a daily question". One review says "Why is a relationship app this greedy" ([Unstar](https://unstar.app/blog/paired-lasting-love-nudge-evergreen-cupla-couples-apps-ranked-2026)).
  - **Billing:** trial converting to annual, and double charges. Kerri (2023): "They double charge and make it near impossible to reach customer service" ([JustUseApp](https://justuseapp.com/en/app/1469609343/paired-relationship-couples/reviews)).
  - **Bugs and sync (73):** partner answers don't appear, the "read" state doesn't register. CrankyAndTheFox (2021): "He can see the results instantly", while she is still "waiting for answers".
  - **Notifications (54):** reminders arrive after the question is already answered. Notifications always deep-link to the home screen. They can't be filtered to "only when my boyfriend answers", so "It's like getting ads for an app we already pay for" (Jjongzzz, 2022). After a 2024 update a couple had "200+ unread notifications with no simple way to clear it" (Mr T Hodges).
  - **Streaks (52):** lost to bugs. "It's frustrating to constantly lose my streak when it's the app that won't let me answer" (Oj78guy23, 2024). Lost to time zones: a 60-day streak showed 2 for a couple 9 hours apart (bteats1, 2022). One reviewer *likes* the lock-screen countdown "before you loose your streak" (Jillianmay3, 2026).
  - **Removed features (44):** in 2024 Paired removed the in-app chat (14 reviews) and the store with streak freezes and "send my partner a hug or kiss" (16 reviews). "I will be canceling our subscription" (rosey.Nerd., 2024).
  - **Sexual content (50 mentions; 23 in reviews rated 1–3):** an asexual user asked for an opt-out (eembezzle, 2023, 6 votes; the developer replied that personalisation was "in progress"). "Way too much content about sex and kink" (RelicAdventures, 2026). Some see hints of non-monogamy. Others love the sex-life topics.
  - **Representation tension (18 reviews):** LGBTQ+ couples praise the inclusive imagery. Conservative or religious couples ask to hide same-sex illustrations: "contacted support, and they confirmed there was no option to customize/remove any illustrations" (Craine0318, 2026). Christians ask for a faith category (12 reviews). **Both sides ask for the same thing: content and imagery that reflect *their* relationship.**
  - **Generic or irrelevant content (14):** questions about birth families for a long-married couple, LGBTQ quizzes for straight couples, and the reverse.
  - **Repetition:** 25 corpus reviews. Unstar puts "questions repeat" at 22% of 1–3★ reviews across five apps. My keyword method found far fewer, which suggests the true share sits between the two.
- **Requests:** monthly pricing, a "mark all read" button, per-question chat, filters for relevance (married, kids, orientation), editable answers, an option for "don't agree" answers to not be labelled a "growth area", and a religion category.
- **Notification-awkwardness check:** the brief says Paired's sensitive push notifications are visible to others. **I found no review in 890 Paired reviews, or anywhere else, describing a third party seeing an embarrassing Paired notification.** The closest evidence:
  - Paired puts streak countdowns on the lock screen (Jillianmay3).
  - A generic couples-app guide advises turning off previews "so prompts don't appear on a lock screen at work" ([Cohesa](https://cohesa.io/blog/best-apps-couples-intimacy)).
  - Treat this as a plausible risk, not an evidenced complaint.
- **Breakup — critical:** a user deleted their account, later re-joined with a new partner, and "ALL of the quizzes that I had answered before popped up… That's an absolute slap in the face". The deletion screen had promised data was gone (ChiBlackhawks fan, 2023). Separately, a 2026 user objects that there is "no way to opt-out of the use of AI… It feeds ALL of your responses to an AI" (aEDS-er). Unpairing hides the ex's answers: "Once unpaired, you will not be able to see your previous partner's answers" ([Paired support](https://support.paired.com/en/articles/164637-how-do-i-unpair-my-account-from-my-partner-s)). The page says nothing about deletion or notifying the other person.

#### Agapé
- **Core:** a daily question with blind reveal and unlimited answer length. Also wellness checks and a photo scrapbook. A pilot of 405 couples reported high engagement ([Auburn/Military REACH summary](https://aub.ie/MilitaryREACH-Rogge2023)).
- **Pricing:** about $29.99/yr or a $199.99 lifetime option per couple (vendor blogs). Reviewers cite "$50 a year" or "$200". In 2024 Agapé gated the free tier behind **3 connections**: you must recruit two more people (25 corpus reviews). "none of your friends want to join a couples app with you because that's insanely weird" (Pete15115, 2024). "You need to have 4 people… Deleted it immediately" (Stegs, 2024).
- **Loves:** the blind reveal and serious-conversation space. "a place for some more serious conversations" (Henry_5678) ([JustUseApp](https://justuseapp.com/en/app/1507907556/agapé-relationship-wellness/reviews)). Refinery29's tester reconsidered her own reply after an argument because of the side-by-side answers ([Refinery29](https://refinery29.com/en-gb/relationship-wellness-app-agape-review)). It works for partners who aren't verbal: "isn't the type to express himself through writing" but enjoys it.
- **Complaints:**
  - A 2022 change from a single "Daily Question" with a timer to "Chosen for you" broke a ritual. "It felt more special because it was only one" (Cata33$, 2022).
  - "Failed to prepare account" crash loops.
  - A mandatory data-collection questionnaire: "It is not optional" (2024).
  - Notifications that never clear.
  - Premium bought by one partner didn't unlock for the other.
  - US-only availability at one point.
- **Requests:** drafts, comment indicators, more than one question a day, personal memories in the scrapbook.

#### Lovewick
- **Core:** question cards, date and gesture ideas, important dates, milestones, wishlists.
- **Pricing:** Plus is $9.99/mo, $14.99/qtr or $29.99/yr for both partners. The free tier went from 10 random questions a day to 1 in July 2024 (14 corpus reviews).
- **Loves:** "Some of the best conversations I've had with my partner were sparked by the questions" (2024). Used across life stages: "from dating, to engaged, to married" (Lizzi3009). Helped an interracial, inter-religious couple discuss their future (2024).
- **Complaints:** the **retroactive paywall**. "Subscriptions Ruined This App" (J93901). "$10 a month to access previously free features? … I'd be less mad about ads" (Funny1o1o). The developer's line that "everything is free if you're patient" was called "rude". An earlier move from Goals to community date ideas was disliked (2022).
- **Requests:** add our own questions (a long-distance user), and control over question intensity.
- Source: [App Store](https://apps.apple.com/us/app/lovewick-relationship-tracker/id1516199115?see-all=reviews).

#### Evergreen
- **Core:** daily questions, quizzes, expert lessons, points, streaks and a "forest". 55K ratings.
- **Pricing:** about $50/yr (reviewer), and "most quizzes locked".
- **Loves:** "really questions your values and intentions". A couple got "hooked on doing the quizzes together".
- **Complaints:**
  - Repetition (15). "How many times can we say we don't have arguments before the app figures it out?" (mitch1795, 2024).
  - Paying couples finished all quizzes in 3 weeks.
  - **The topic filter was ignored:** "we specifically did not choose anything concerning sex… yet we are still getting those" (TheologyNerd316, 2025).
  - "Weekly" check-ins never refresh.
  - Trial charged immediately.
  - Points have no purpose.
- **Requests:** a "remind your partner to answer" button, a shared message board, team achievements, **seeing growth over time and exporting data** ("We're on day 300 and there's no ability to see how our relationship has grown").

#### Flamme
- **Core:** daily questions, AI coach, bucket list, streaks, widgets.
- **Loves:** "something to look forward to daily". A couple's bucket list for planning the next long-distance meetup.
- **Complaints:** "This app thinks every couple has issues!" Onboarding asked whether to work on communication, money or family (A.Kinng, 2023) ([App Store](https://apps.apple.com/us/app/flamme-cozy-couples-app/id1583601044?see-all=reviews)). Flamme's own blog concedes its AI "isn't tailored to a specific relationship".
- Note: three 5★ reviews were posted on 2025-11-18 with similar developer replies. Treat its rating cautiously.

#### Couple Joy (long-distance focus)
- **Core:** quizzes, daily questions, distance and countdown widgets, scrapbook timeline.
- **Pricing:** $29.99/yr premium. One reviewer cites "almost $13 a month" for premium when "I literally just wanted the widget" (2025).
- **Loves:** long distance. A couple met a week before one partner shipped out to Korea: it "takes away the awkwardness of maybe asking a risky question" (zozohunt, 2023). "It doesn't ask you to always open it and be on your phone" (2026).
- **Complaints:**
  - Paywall (83 mentions).
  - "the subscription doesnt work for the both of us".
  - Distance widget updates "every couple of days".
  - Messages "disappear into the abyss".
  - The streak resets though both answered.
  - The 18+ filter was turned off but risqué questions still came (tigergirl0117, 2025).
  - A "Blue Monday" prompt on MLK Day.
- A third-party summary claims an ex's photos persisted after unpairing. **I could not verify this in any primary review.**

#### Candle (2025 newcomer, YC "Duolingo for relationships")
- **Core:** swipeable prompts, photo prompts, thumb kisses, local date ideas, widgets, streaks ([YC launch](https://www.ycombinator.com/launches/OFK-candle-the-duolingo-for-relationships)).
- **Loves:** "the first one that actually felt fun and real" (47-day streak, 2025). Playful streak nudges ("do you even like [partner] anymore?") were "highly endearing". Developers are responsive on Reddit and TikTok.
- **Complaints:**
  - Price: "more expensive than most of my other subscriptions".
  - No polyamory support: "no option to add more than one person to a partnership" (2025).
  - Data asks: access to photos and location, birth date, "shady privacy policy".
  - A request for a "family friendly setting" from a couple waiting for marriage.

#### Cozy Couples (pet/house gamified, 46K ratings)
- **Loves:** long-distance daily ritual. Mood sharing: "inform each other easily about our moods". "So much better than those many couple apps with ads".
- **Complaints:**
  - A paid **monthly streak repair**. "if I'm sick for 2-4 days … all of the work we've done is gone" (NaeSlay33, 2025).
  - "lost our 450 days" streak.
  - **A Dec 2025 change put old notes behind premium "after the fact"** (Baerett) — 63 reviews mentioning pay or premium since Oct 2025.
  - "NOTHING IN THIS IS FREE".
  - The streak breaks across time zones.
  - Infantile UI.

#### CoupleGrow
- 82% of sampled reviews rated 1–3★.
- "you can't see half of each other's answers without paying".
- **Trial cancellation required BOTH accounts to unsubscribe**, and the couple was charged (leon s kennedy22, 2023).
- Support doesn't respond.

#### Love8 (widgets + location + pet)
- "everything is blocked and the only thing you can see is your partners location. You gotta buy premium for everything else. even the battery percentage" (Ferkety, 2025). 43 reviews mention location or battery.
- Distrust of IP and location collection.
- "sends me to the 'upgrade to premium' every time I open the app".

#### Couple Game: Relationship Quiz
- 49% rated 1–3. Top complaints: ads (43) and paywall (43).

#### Gottman Card Decks — the "honest free tool"
- **Core:** 14 decks and 1,000+ cards. Free.
- **Loves:** research-based and free. "The original, free, helpful tool… cutting through the BS and assumptions". Recommended by counsellors and used by therapists to reinforce sessions. Helps introverts start talking ([App Store](https://apps.apple.com/us/app/gottman-card-decks/id1292398843?see-all=reviews)).
- **Complaints:**
  - Shuffle is still requested in 2026 ("really wish there was a way to shuffle them").
  - **Large text cuts off questions** (two Oct 2026 reviews, one calling it "useless for me"). This is an accessibility failure that hits older users.
  - Sex questions duplicated across "male" and "female" decks.
  - Crashes in 2018–19.
- **No partner sync.** It is a single-phone deck.

#### LoveTrack (user-provided summary verified)
- **Core:** 500+ planned dates with steps, supplies, playlists and recipes. 5,000+ couples questions. Milestones and reminders. **Free with no ads or subscriptions** ("it's all free without any adds or subscriptions!"). Developed with the National Alliance for Relationship & Marriage Foundation and listed by the US ACF ([App Store](https://apps.apple.com/us/app/-/id6608982670), [ACF](https://peerta.acf.hhs.gov/content/lovetrack-app)).
- **Loves:** date search by mood, organisation, important-date reminders. Found at a bridal expo.
- **Gaps:**
  - **No partner pairing until at least mid-2025.** The developer promised it "very soon… end of July" (June 2025).
  - Users ask for long-distance features and custom special dates.
  - A privacy question was answered with "your data will never be sold".
- Small sample (25 reviews), so evidence is thin.

#### Together: Rekindle & Rebuild (Dr John Delony / Ramsey)
- Small daily challenges, plus a travel mode for partners who travel for work (praised).
- Complaints: no preview, a pay screen first, "$5.99/month paywall on basic daily prompts" ("Ramsey-style cash grab"), no Android.
- **Not the same as the "Together" app at together-app.co** (founder Dominik), whose blog argues against streaks.

#### Connected (2026)
- AI interpretation of validated assessments plus Gottman-based conflict tools. A therapist reviewer ranks it first, while disclosing that she knows the builders ([South Denver Therapy](https://www.southdenvertherapy.com/blog/do-relationship-apps-work-therapist-review)).
- Early App Store reviews: "AI generated slop… can't even shut off the notifications", tasks randomly deleted, the same daily question for days. One couples therapist gives it "to all my clients".

### 2.2 Structured programs, coaching and therapy companions

#### Lasting (Gottman-based; now part of Talkspace)
- **Core:** a personalised plan from an assessment, short sessions, workshops, retreats.
- **Pricing:** "$12 for both you and your partner, not per person" (2018). Choosing Therapy lists $29.99/mo, $59.99/3 mo, $89.99/6 mo; no insurance or HSA ([ChoosingTherapy](https://www.choosingtherapy.com/lasting-app-review/)).
- **Loves:** "breaks down decades of research" into short sessions. "Great for our unstable relationship" but not a replacement for counselling ([App Store](https://apps.apple.com/us/app/lasting-marriage-couples/id1225049619?see-all=reviews)).
- **Complaints (49% of sample rated 1–3):**
  - Cancellation and billing (28): "NIGHTMARE to cancel"; "charged $80 after a week"; "Won't let me stop".
  - Bugs: partner can't see conversations, workshops don't load. A Google Play bug **reveals the partner's answer early**.
  - Generic content: "very standardized, generic one size fits all package (despite filling out a very lengthy quiz)".
  - iOS-only at launch: "Worthless if you and your partner don't have the same type phone" (2017).
  - "Designed to purposely cause conflict, so the app can sell a solution".
- **Breakup and safety — critical:**
  - "when I linked my partner, it shows all the sessions he completed with his previous relationship… a failed marriage" (Paddleout4725, 2022, 7 votes). Old relationship data surfaced to a new partner.
  - A user whose partner refused to participate wanted to stop: "Unsubscribe | refusal of partner to participate" (2019).
  - A user broke up before the partner joined and was still charged (2020).

#### Love Nudge (5 Love Languages) — user-provided summary verified
- **Core:** love-language quiz, "love tank" percentage, goals, nudges. Free.
- **Loves:** "finding out your partners love languages is PRICELESS!" "Thanks for keeping LoveNudge FREE!" Action suggestions tied to love language ([JustUseApp](https://justuseapp.com/en/app/495326842/love-nudge/reviews)).
- **Complaints (55% of sample rated 1–3):**
  - **Goals don't sync:** "I created a test goal - my partner can't see it at all."
  - Goals can't be marked complete or deleted. Partner linking loops ("you already have a partner").
  - Love tank can't be updated unless the percentage changes ("There is no weight to the percentages").
  - Reminders can't be turned off for mastered goals. 40-character goal limit. Crashes and "check internet connection" errors.
  - **Poor instructions:** "not intuitive… We expected our goals to be able to be shared"; "Limited info/directions/best uses".
- **Conceptual critiques — important:**
  - "Nudging or 'nagging' your partner on how they can fill your love tank is the opposite of what this program should be doing" (Redwench, 2019).
  - "When you hear the ding reminding your partner to come give you a hug because he or she cannot care enough… you realize how silly this app is" (2019).
- **Coercion and inclusivity:** "if I tell my partner OF 30 years that I hate this app, they will get upset with me… some of us (spectrum, trauma, abusive past) do NOT want to [be nudged]" (PurpleEm633, 2022). "Doesn't work well if one partner is disabled". "Transphobic: Only two genders and uses he/her" (2023).
- **Requests:** goals for long-distance couples, goals for kids, editable notes.

#### Gottman Connect
- This is the platform behind Gottman's online "Love Lab". Partners complete questionnaires, record conversations and rate them with an on-screen dial ([Gottman](https://www.gottman.com/love-lab/)). **No user reviews were found.**

#### Relish (relationship coaching)
- Reported as $100/yr for two, with a weekly custom plan and texting with a coach ([Scottish Financial News](https://www.scottishfinancialnews.com/articles/forfar-born-entrepreneur-launches-new-app-in-the-usa)). The founder positions it as early intervention and a companion to therapy. **No independent user reviews were found.**

#### OurRitual (couples therapy + app)
- Trustpilot is 4.6/5 from 259 reviews; the App Store sample is 78% rated 1–3.
- **Loves:** bilingual matching, individual sessions when one partner drops out ("for both individual therapy and couples therapy"), a journaling AI "for getting thoughts out" ([Trustpilot](https://nz.trustpilot.com/review/www.ourritual.com)).
- **Complaints:**
  - "260 dollar per month… no cancellation option" (2025).
  - Refunds refused within the 14-day window.
  - 20-minute sessions.
  - "you have to pay $310 to know who you'll get as a counselor".
  - The app blocked homework.

#### ReGain (BetterHelp couples)
- Complaints: counsellor fit and responsiveness ("generic worksheets"), and denial of service to under-18 couples.

#### Maia, Ember (AI couples apps)
- **Maia:** a 2025–26 run of "crashes every time I open it". Its argument analyser "failed and not all features were available yet".
- **Ember:**
  - "Kept talking in circles… constantly remind it to stop giving me the entire 'how to have a relationship' Wiki page".
  - "feels so like ai generated slop".
  - A 24-hour reply window punishes a partner who doesn't open the app: "It's for anxious attachment styles" (DJ Mykell B, 2025).
  - Both partners charged "$50 each before our free trial ended".

#### Marriage 365
- 97% of sample rated 4–5★. Loves: husband-and-wife perspective, step-by-step instructions, open-ended follow-ups.
- Notable: used *solo* by a spouse whose partner isn't on board ("Not everyone believes it's needed", 2022). A faith-centred user complained of "No mention of scripture".

#### Blueheart (sex/relationship therapy, audio, no live therapist)
- Boots claims 50K couples and that users "feel 70% more connected within two weeks" ([Boots](https://www.boots-uk.com/newsroom/news/boots-expands-online-health-services-offering-with-sex-and-relationship-therapy-app-blueheart)). Those are vendor figures.
- Reviews: login and verification failures, a support email that bounced, a trial that charged a 6-month plan after 3 days.
- **Partner asymmetry:** "my wife was only going to engage with the daily questions". "no way to tell how far along your partner is progressing".

### 2.3 Sex and intimacy apps

#### Coral
- **Core:** guided intimacy exercises, lessons, community, chat. The yearly fee is about $42 per a review.
- **Loves:** "saved my marriage". It normalised low desire: "I, like many others, have felt guilt for not having desire" (105 votes). Weekly date night built on exercises.
- **Complaints (56% of sample rated 1–3):**
  - **Gender options excluded non-binary people (40-vote and 26-vote reviews, 2020).** "I would have to lie to create an account". Content "forces misgendering".
  - Suggesting porn alienated users with porn-addiction histories.
  - "The Privacy Policy is INSANE" for sex data.
  - Misleading framing on a sexual-abuse statistics question.
  - **Partner disengagement:** "I really liked it, but my husband kept ignoring it" (2023). "Pay, then pay some more" when the partner never used it.
  - 2023: "staff left… events stopped" (the developer admitted limited staffing).
  - Exercises open in a browser and don't sync to calendars ([App Store](https://apps.apple.com/us/app/coral-couples-relationship/id1448861466?see-all=reviews)).

#### Spicer (private desire-matching)
- **Core:** both partners swipe yes/no/maybe on ideas; only matches are revealed.
- **Loves:** "Your partner only sees the desires they match with you on". It "takes away the hard part of communicating desires".
- **Complaints:**
  - **The match privacy leaked:** "If you go into 'Change Answers' you can see all of your partners answers regardless of if they match" (2019). This breaks the app's core promise.
  - Terms reportedly allow staff to "access your private account" (2019 reviewer reading).
  - Packs must be bought on both phones.
  - Content skews to non-monogamy or voyeurism: "Almost every question is about sex that in some way involves other people" (2023). "I'm open but not open for infidelity" (2024).
  - Trauma triggers: a question about assault and rape "appalling and triggering" for a survivor (2023).
  - Catholic and conservative couples tired of answering "no" repeatedly. They want categories they can exclude.
  - Questions ambiguous about who does the act.
  - Removed from Google Play in 2020; Android users must sideload.

#### Desire (dares)
- In 2019 it removed community dares: 38 corpus reviews, "Update killed the app", "nerfed… money grab". Reviewers loved asking for more of what they like via dares, and the diary.

#### Kindu
- AlternativeTo marks Kindu as discontinued, with the website and apps gone ([AlternativeTo](https://alternativeto.net/software/kindu/about)). Earlier reports describe crashes and partners needing the same device. The private yes/no matching concept lives on in Spicer.

#### LoveSync (desire signalling)
- Fixed timing windows (15 min, 1 h, 2.5 h, 8 h). Notifications don't fire: "It will lead to confusion and resentment" (2023). In 2025 it moved to 3 free syncs a month, then $7/mo.

### 2.4 Private messaging and memory apps

#### Between (VCNC, Korea)
- **Core:** private chat, stickers, shared calendar, albums, anniversaries. Plus is $2.99/mo to $26.99 lifetime.
- **Loves:** stickers, the shared calendar, and **"I can't accidentally text someone else"**. "peace of mind that we were only sending messages to each other" ([App Store](https://apps.apple.com/us/app/between-the-app-couples-love/id458035189?see-all=reviews)).
- **Complaints:**
  - **Mass photo loss, Sept 2025 to June 2026 (12 reviews).**
    - "Between informed users that all non-paying users had their photos and videos deleted by accident and the data is not recoverable" (D'orazia, 2025-09-25).
    - "deleted 38,000 PHOTOS!! YEARS WORTH!! My wedding photos included" (2026-02).
    - Old files show as grey boxes; Plus users could only download about 300 of 1,900+.
    - I found **no press coverage** confirming the incident, so it rests on consistent independent user reports.
  - Pornographic or violent pop-up ads inside an intimate chat (2018).
  - Privacy-policy changes and no end-to-end encryption: "this app is not END to END".
  - Undelivered messages on one partner's phone.
  - Lifetime buyers still get upsell red dots.
- **Breakup handling:**
  - Disconnecting notifies the partner by notification and email. Data is recoverable for 30–31 days (90 for Plus) if both reconnect, then deleted ([Between help, via search](https://help.between.us/hc/en-us/articles/115006148087)).
  - Users have found the breakup email brutal: "you receive a dry email… 'relationship has been CANCELED and we will hold on to your data for 30 days.' It hits you hard" (TomasuHandera, 2018).

#### Couple (formerly Pair) and Avocado — the graveyard
- **Pair → Couple:** launched 2012 and passed 100K users in a week. Acquired by Life360 in 2016. **Defunct since 22 April 2019** ([Wikipedia](https://en.wikipedia.org/wiki/Couple_(app)); [Life360 PR](https://www.life360.com/press/love-is-in-the-air-life360-acquires-couple-the-app-for-two)).
- **Autostraddle's queer group review of Couple:**
  - Loved: Thumbkiss (two thumbs touching vibrates), stickers, long distance.
  - Disliked: it "felt co-dependent in a way we really aren't" and was "totally creeped out at first".
  - An unreciprocated thumbkiss felt like a bad first kiss.
  - "not very poly-friendly": partners had to unpair from exes.
  - Unclear data storage.
  - **Unpairing after a breakup erased shared messages**, which hurts either person ([Autostraddle](https://www.autostraddle.com/couple-me-app-is-co-dependent-also-wonderful-the-giant-group-review-213632/)).
- **Avocado** closed on 28 Feb 2017 for "lack of funding". It offered a data export and pointed users to Couple ([Android Police](https://www.androidpolice.com/2017/01/20/avocado-messaging-app-couples-closing-doors/)). A Between reviewer was "eager to find Between after the demise of Couple and the various other similar apps" (2020).

#### Just Between Us
- Messages arrive 7 hours late. Photos can't be deleted without paying, "and once you pay, the photos still will not delete" (2021). Spam after signup suggests data sharing.

### 2.5 Presence, widgets and touch (mostly long distance)

#### Widgetable (387K ratings)
- **Loves:** cute widgets, a "miss you" button, steps, the **distance between you two**, co-parented pets.
- **Complaints:**
  - Ads (122 low reviews): "100 second long ad for ONE piece of food"; ads that are "always sexual"; "the entire game became the add itself".
  - Pets "leave you" when neglected.
  - Widgets go black.
  - "It is constantly tracking my location" (2023; 30 location mentions).
  - Pay-to-win premium widgets.
  - Co-parent doesn't help with pet care ([App Store](https://apps.apple.com/us/app/widgetable-besties-couples/id1641107226?see-all=reviews)).

#### Locket Widget (579K ratings)
- Live photos on the partner's home screen: "seeing his random pictures pop up on my home screen has made me very happy" (long distance, 2022).
- **Deleting a sent photo only removes it on your side**: "it only deletes the pic on your side" (TaeTaeBear, 2023; also [Deseret](https://www.deseret.com/2022/1/27/22902015/how-the-locket-app-works-family)). Users want separate widgets per person.

#### Loveit (drawing widget)
- Free tier capped at 4 people. Ads (60 low reviews). "taking away the ability to write a note". Widget doesn't update. No Android.

#### Bond Touch (bracelets + app; Apple Watch "Lite" subscription)
- **Loves:** LDR, deployments, and couples who live together but work 12-hour days use taps to check in.
- **Complaints (57% of sample rated 1–3):**
  - Pairing and sync failures; Android and iPhone mismatches.
  - Touch delays "even when right next to each other".
  - Phone must be within about 10 m.
  - Battery drain.
  - Clasps open and bracelets get lost ([Trustpilot 3.8/1,293](https://www.trustpilot.com/review/bond-touch.com)).
  - Support delays.
  - An Apple Watch "Lite" subscription on top of the hardware.

#### Lovebox (hardware love-note box)
- **Loves:** for parents, partners and long distance.
- **Complaints:**
  - **Subscription on top of $130–200 hardware (42 reviews):** "now they want me to pay $50 a year for the templates!?" Colour is software-locked to monochrome.
  - Messages deleted after 30 days without a subscription ([LON.tv](https://blog.lon.tv/2024/03/04/the-lovebox-review/)).
  - Wi-Fi setup loops; "13 rounds of back and forth emails" ([Trustpilot 3.8/27](https://ca.trustpilot.com/review/lovebox.love)).

#### Filimin / friendship lamps
- An app review analysis reports frustration with a subscription that buyers expected to be a one-off hardware purchase ([Filimin support](https://support.filimin.com/hc/en-us/articles/53718641641363)).

### 2.6 Logistics: calendars, money

#### Cupla (shared calendar)
- **Loves:** "Google Calendar stinks"; simplicity for a partner who gets "overwhelmed"; a weekly planning ritual.
- **Complaints:** **the couple feature itself is paywalled.** "you have to pay to see more than 7 days of your partners calendar… kinda defeats the purpose" (2026). "To get my partner be on this app with me, we have to pay". Also crashes and wrong dates.

#### Raft (social calendar)
- Free and feed-style, but "overwhelming if you just want a simple view" ([Cupla blog](https://cupla.app/blog/the-5-best-shared-calendar-apps-for-couples/)). Corpus: crashes and "no partner sharing even tho we both connected".

#### Honeydue (couples finance, free)
- **Loves:** reactions and comments on individual transactions. Choose what to share: privacy settings "as little or as much transparency" (mogli3). "this transparency between my husband and I".
- **Complaints (67% of sample rated 1–3):**
  - Bank sync fails "every few days" (234 sync and connect mentions).
  - Balances wrong; support unresponsive.
  - **"The app starts fights because of miscommunicated information"** from lagging data (2019).
  - Features removed, and reviewers fear a shutdown ([App Store](https://apps.apple.com/us/app/honeydue-couples-finance/id1157633945?see-all=reviews)).
- **Graveyard:** Honeyfi "no longer exists" ([Financial Planning](https://financial-planning.com/news/families-couples-ex-couples-fintechs-delve-into-shared-finance)). Zeta's couples product reportedly ended in May 2025, per a competitor's blog (unverified).

### 2.7 Location sharing between partners (Life360, Find My, Snap Map)

- **Prevalence:**
  - Life360's own survey (n=1,000) claims 95% of people in relationships use some location sharing and check about 7 times a day. This is industry-sponsored ([Vice](https://www.vice.com/en/article/is-sharing-your-location-with-a-partner-actually-healthy-heres-what-a-psychologist-says/)).
  - A Life360 figure reported via the WSJ says about 21% see refusing to share as a dealbreaker.
- **Couples' positive use (corpus):**
  - Safety: "not to spy on my boyfriend, but to make sure he's driving home safe" (tingxdos).
  - Logistics: an alert "when my husband reaches a certain point on his commute… so I know when to start dinner" (BoskoBella).
  - Health: "My wife has MS… My wife can opt out at any time".
- **Backlash and coercive control:**
  - **eSafety Commissioner (AU), n=2,000:** about 1 in 5 young adults think partner tracking is normal. Over 13% think monitoring via Life360 or Find My is reasonable. About 25% think a partner's passwords are "necessary". eSafety links location apps to tech-based coercive control and calls for safety-by-design ([ABC](https://www.abc.net.au/news/2025-05-15/location-sharing-apps-esafety-commission-coercive-control/105289994)).
  - **Griffith University (n>1,000, plus 28 in focus groups, ages 16–25):** tracking is read as care and trust. Stopping sharing is read as distrust. Parental tracking normalises it. Anger when a partner stops sharing is a red flag, and the article cites the Lilie James case ([The Conversation](https://theconversation.com/location-sharing-apps-are-enabling-domestic-violence-but-young-people-arent-aware-of-the-danger-253932)).
  - **Mumsnet thread:** a wife tracked for years by her husband fears that turning it off "would cause an explosion". Most replies call it abuse, while some say "The problem isn't the find my friends type app, its your relationship" ([Mumsnet](https://www.mumsnet.com/talk/relationships/4752805-life-360-tracking-controlling-behaviour)).
  - **Snapchat:** studies link Snap Map use to jealousy and mate-guarding ([Boise State](https://experts.boisestate.edu/en/publications/relationships-between-jealousy-in-intimate-partnerships-and-the-u-2/)).
  - **After breakups:** 25% of US adults admitted logging into an ex's account to see real-time location (ExpressVPN, n=1,506, 2021) ([Fox](https://www.foxnews.com/lifestyle/1-of-4-americans-tracking-exs-real-time-location)). Pew (2020): about 1 in 3 partnered Americans have looked through a partner's phone without them knowing.
  - **Data monetisation:** Life360 sold precise location data to about a dozen data brokers until The Markup's 2021 exposé ([The Markup](https://themarkup.org/privacy/2021/12/06/the-popular-family-safety-app-life360-is-selling-precise-location-data-on-its-tens-of-millions-of-user)).
- **IPV research:**
  - Most partner-surveillance apps are "dual-use" (child safety, anti-theft). Antivirus tools fail to flag them ([Chatterjee et al. 2018](https://www.cs.cornell.edu/~rahul/papers/IPV_Spyware.pdf)).
  - Most abuse is by a "UI-bound adversary": an authenticated partner using normal features, often through shared accounts or family plans ([Freed et al. CHI 2018](https://www.classes.cs.uchicago.edu/archive/2020/winter/20370-1/readings/Stalkers.pdf)).
  - Apple's Safety Check exists to cut sharing at once. Guides warn that changing settings can alert an abusive partner ([Intego](https://www.intego.com/mac-security-blog/bad-breakup-how-to-stop-sharing-data-with-your-ex-on-iphone-and-ipad/)).
- **Couples-app location features:** Love8 makes partner location and battery its free headline feature. Widgetable is "constantly tracking my location". Both show location turned into an engagement hook.

### 2.8 Faith-based couple apps

- **Christian:**
  - Covenant: 4.2★ from 49 ratings. Loves: "keep God and my husband a priority". Complaints: glitchy reminders, shared articles don't send, constant review nags, "Wish it wouldn't ask for money" ([App Store](https://apps.apple.com/us/app/covenant-christian-marriage/id6744675778?see-all=reviews)).
  - TwoAsOne: one topic held for several days felt repetitive (the developer says that is deliberate, for reflection).
  - FamilyLife's Toucan Together devotional is on YouVersion. The Love Dare is a 40-day free devotional.
- **Demand inside secular apps:** 12 Paired reviews ask for Christian or faith content. Marriage 365 was criticised for lacking scripture. Spicer was abandoned by "a devout Catholic couple". Candle users want a "family friendly setting" while "waiting for marriage".
- **Muslim:** the market is dominated by matrimonial apps for singles (Muzz and others). The only married-couple app found is a lightly reviewed "Islamic Couples & Relationship" app on intimacy ethics ([App Store](https://apps.apple.com/us/app/-/id6477761051)). **This is a gap.**
- **Jewish:** no shalom bayit app for married couples was found; only dating apps (JSwipe, JWed). **This is a gap.**
- **Academic confirmation:** a 2025 scoping review of 38 relationship apps found religion addressed by **1 of 38**, the least-covered factor. Finance and decision-making were also underserved ([SCIRP 2025](https://www.scirp.org/journal/paperinformation?paperid=141110)).

### 2.9 Requested apps not found or without user evidence
- **Dabble:** the App Store "Dabble" is a sports pick'em app. "Doubble" is a double-dating app. No couples app named Dabble was found.
- **Ours:** two 2025–26 listings ("Ours: Couple Diary", "Ours: Couple Widget & Art") have no ratings.
- **Love Is (Widget):** not identifiable. The nearest are "Couple Widget: Love Countdown" (3.7K ratings) and "Love Widget – Couple Countdown".
- **OurPath:** not found. The nearest is OurRelationship, a $79–249 one-time online program ([ChoosingTherapy](https://www.choosingtherapy.com/our-relationship-review/)).
- **Kindu:** discontinued (see §2.3).
- **Couple (Pair):** defunct 2019 (see §2.4).
- **Duolingo-style couple apps:** Candle markets itself this way. Duolingo's own Friend Streak (both must practise daily, resets to zero) shows the mechanic: Duolingo claims learners with a shared streak are 22% more likely to finish daily ([Duolingo blog](https://blog.duolingo.com/friend-streak/)). Couple language apps "Fluent Duo" ("no streaks shaming you in red") and "Coupling" (no streak gamification) explicitly reject guilt mechanics.

---
## 3. Cross-market synthesis

**How to read the evidence column.** "Corpus N / M apps" is the number of keyword-matched reviews in my 15,746-review App Store corpus, and the number of apps where the theme appears in at least 3 reviews. Love counts use all reviews. Pain counts use the 4,561 reviews rated 1–3 unless marked "(all)". Where keyword counting can't capture a theme, the evidence is listed qualitatively with named sources. **Rank combines frequency, breadth across apps, and intensity** (vote counts, 1★ share, churn language such as "deleted", "cancelled" or "ruined").

### 3.1 Top 25 things users LOVE

| # | What users love | Evidence | Example apps |
|---|---|---|---|
| 1 | **Prompts that start conversations you'd never have had otherwise.** "Some of the best conversations I've had with my partner" | Corpus 1,889 / 38 apps (12% of all reviews) | Paired, Agapé, Lovewick, Gottman Cards, Spicer |
| 2 | **Feeling closer and connected, especially when apart** | Corpus 713 / 32 apps | Paired, Couple Joy, Cozy Couples, Locket |
| 3 | **Learning new things about a partner even after years.** "after 13 years together, are learning new things" | Corpus 305 / 18 apps; "never knew / different answers" 96 / 27 | Paired, Spicer, Evergreen |
| 4 | **Warm, cute, non-clinical design** (stickers, illustrations, pets) | Corpus 1,887 / 33 apps | Between, Paired, Cozy Couples, Widgetable, Locket |
| 5 | **Play: quizzes, games, dares** | Corpus 3,530 / 37 apps (a broad keyword, so this overcounts) | Evergreen, Couple Joy, Candle, Desire |
| 6 | **A small daily ritual** ("every morning as part of our routine"; "something to look forward to daily") | Corpus 1,041 / 30 apps | Paired, Agapé, Candle, Flamme |
| 7 | **A lifeline for long-distance couples.** LDR mentions skew strongly positive: only 99 of 880 are in reviews rated 1–3 | Corpus 880 (all) / 24 apps | Couple Joy, Paired, Locket, Bond Touch, Cozy Couples |
| 8 | **Low effort: minutes a day, simple UI**, "doesn't ask you to always open it" | "Easy/simple" 1,166 / 34; "few minutes/quick" 389 / 32 | Couple Joy, Cupla, Paired |
| 9 | **Seeing the partner's answer only after giving your own** (blind reveal), and seeing only mutual "yes"es in intimacy apps | Corpus 98 / 17 apps; Refinery29 (Agapé); Paired DeafiniteAlle; Spicer "Your partner only sees the desires they match" | Agapé, Paired, Spicer |
| 10 | **Neutral framing that makes risky topics safe.** "takes away the awkwardness of… a risky question"; "without embarrassing yourself" | JMIR 2025 Paired interviews; Spicer (9 "embarrass" praise reviews); Couple Joy | Paired, Spicer, Couple Joy |
| 11 | **Shared memories: timeline, anniversaries, countdowns, albums** | Corpus 940 / 26 apps | Between, Couple Joy, LoveTrack, Desire (diary) |
| 12 | **Home-screen and lock-screen presence:** a partner's photo, mood, distance or countdown | Corpus 604 / 15 apps; mood/status 364 / 25 | Locket, Widgetable, Cozy Couples, Couple Joy |
| 13 | **A private channel just for the two of us.** "I can't accidentally text someone else"; nothing appears on the lock screen | Corpus 63 / 12 apps (56 rated 4–5) | Between, Just Between Us, Paired (old chat) |
| 14 | **Genuinely free, or honestly priced** ("Thanks for keeping LoveNudge FREE!"; "all free without any adds or subscriptions") | "free" in 670 reviews rated 4–5 / 39 apps | Love Nudge, Gottman Cards, LoveTrack, Agapé (old free tier) |
| 15 | **Touch and presence gestures:** thumbkiss, haptic taps, "miss you" button, hug/kiss | Corpus 670 / 25 apps (broad); Autostraddle (Couple) | Couple/Pair, Bond Touch, Candle, Widgetable |
| 16 | **Mood or "how I'm feeling" sharing for when you can't say it out loud** ("tell him my mood when i feel embarrassed or too emotional to talk about it") | Mood/status 364 / 25; many Cozy Couples requests for more moods | Cozy Couples, Widgetable |
| 17 | **Expert or research credibility** (Gottman, therapists) | Corpus 102 / 11; counsellors recommend Gottman Cards | Gottman Cards, Lasting, Couply, Connected |
| 18 | **Shared calendar and lists that reduce logistics friction** ("Google Calendar stinks") | Corpus 563 / 21 | Cupla, Between, Raft |
| 19 | **Seeing gaps, then talking offline** ("no electronics, no distractions") | Paired top reviews; "different answers" 96 / 27 | Paired, Agapé |
| 20 | **Talking about the future and big decisions** (engaged, inter-faith, moving in) | "future/engaged/premarital" 236 / 33 | Lovewick, Lasting, Paired |
| 21 | **Works for introverts and less verbal partners** ("isn't the type to express himself through writing") | Corpus 45 / 15 | Agapé, Gottman Cards, Lasting |
| 22 | **Responsive, human developers** (Reddit/TikTok founders, fast support) | Corpus 109 / 23 | Candle, Cupla, Couply, Flamme |
| 23 | **Normalising sexual struggles** ("felt guilt for not having desire…" 105 votes) | Coral, Spicer praise | Coral, Spicer, Desire |
| 24 | **Ready-to-run date plans** (steps, supplies, playlists) | Corpus 107 / 12; LoveTrack reviews | LoveTrack, Lovewick, Candle |
| 25 | **Money transparency with choice** (comment and react on transactions; "choose what you want to share") | Honeydue praise (mogli3, Mandykate) | Honeydue |

### 3.2 Top 25 things users HATE (pain points)

| # | Pain | Evidence | Example apps |
|---|---|---|---|
| 1 | **Paywalls that lock the core loop:** one question a day, then pay; pay to see the partner's answers; pay to see the partner's calendar | 783 low reviews (17%) / 32 apps; Unstar: 28% of 1–3★ across 5 apps | Paired, Cozy Couples, Couple Joy, CoupleGrow, Cupla, Love8 |
| 2 | **Bugs and partner sync failures:** answers don't appear, "read" state stuck, linking loops | 827 low reviews (18%) / 37 apps; Unstar: sync 16% | Paired, Love Nudge, Honeydue, Bond Touch, Lasting |
| 3 | **Retroactive paywalls and removed features** (free → paid; chat, community or store removed) | 141 low reviews / 14 apps; Lovewick 10→1 (14), Paired chat (14) + store (16), Desire community (38), Cozy Couples (63 since Oct 2025), Agapé 3-connection gate (25) | Lovewick, Paired, Desire, Cozy Couples, Agapé, Lovebox |
| 4 | **Trials that turn into annual charges; cancellation hell;** both accounts must cancel | 194 low reviews / 17 apps; Unstar: 19% | Lasting, Paired, Evergreen, CoupleGrow, Ember, OurRitual |
| 5 | **Intrusive or inappropriate ads** (100-second ads per pet food; sexual or porn ads inside intimate chat) | 339 low reviews (7%) / 25 apps; 10 cite sexual or porn ads | Widgetable, Loveit, Couple Game, Between |
| 6 | **Unresponsive support** | 296 low reviews (6.5%) / 22 apps | Honeydue, Lasting, Between, CoupleGrow, Lovebox |
| 7 | **Broken or dumb notifications:** missing, late, nagging after completion, no per-type control, deep links to home | 265 low reviews / 31 apps | Paired, Love Nudge, Coral, LoveSync, Just Between Us |
| 8 | **Repetitive or thin content** ("How many times can we say we don't have arguments…") | 77 low (tight keyword) / 12 apps; Unstar: 22% | Evergreen, Paired, Agapé, Cozy Couples, Connected |
| 9 | **Content that doesn't fit our relationship:** married vs dating, kids, orientation, monogamy, faith; filters ignored | "generic" 42 / 13; sexual content 111 low / 19 apps; Evergreen and Couple Joy filters ignored | Paired, Evergreen, Spicer, Lasting |
| 10 | **Unwanted sexual content, or content that implies non-monogamy** ("too much content about sex and kink") | 111 low / 19 apps | Paired, Spicer, Coral, Couple Joy |
| 11 | **Old-relationship data resurfacing with a new partner** | Paired (deleted account restored on re-pair, 2023); Lasting (partner's sessions with ex-wife shown, 2022); Couple ("unpairing erases messages") | Paired, Lasting, Couple |
| 12 | **Losing years of memories** (data deletion and outages) | Between: 12 reviews Sept 2025–Jun 2026 ("38,000 photos"); Couple/Avocado shutdowns | Between, Couple, Avocado |
| 13 | **Streak loss from bugs, time zones, illness, or paywalled repair** | Streak 205 (all) / 8 apps; time zone 31 / 5 | Paired, Cozy Couples, Couple Joy, Candle |
| 14 | **Privacy distrust:** sex-data policies, no E2EE, staff access, data-collection gates, AI processing with no opt-out | 108 low / 19 apps | Coral, Between, Spicer, Agapé, Paired (AI) |
| 15 | **Location and battery tracking as a feature or bait** ("the only thing you can see is your partners location… even the battery") | Location 186 low (a large share is Life360 family use); Love8 43; Widgetable 30 | Love8, Widgetable, Life360 |
| 16 | **Exclusion: binary gender, no non-binary, no poly, heteronormative, ableist** | 57 low / 12 apps; Coral top reviews (40 and 26 votes) | Coral, Love Nudge, Lasting, Candle, Couple |
| 17 | **Being made to recruit friends or family to unlock the free tier** | Agapé 25 reviews | Agapé |
| 18 | **One partner pays or uses, the other ignores it**, or the subscription won't share | Floors: ~21 explicit mentions; Coral, Lasting, Blueheart, Marriage 365; CoupleBee and a therapist flag it | Coral, Lasting, Blueheart, Couple Joy |
| 19 | **The "nudge" feels like nagging or guilt-tripping** | Love Nudge (Redwench; "ding reminding your partner to come give you a hug"); Ember 24-hour window "for anxious attachment styles" | Love Nudge, Ember, Cozy Couples |
| 20 | **Cross-platform gaps** (iOS-only, Android missing, bracelets won't pair across OSes) | 47 low / 14 apps | Lasting (2017), Together, Bond Touch, Loveit |
| 21 | **Hardware plus subscription** ("$200… you want another $50 a year?") | Lovebox 42; Bond Touch Lite; Filimin | Lovebox, Bond Touch, Filimin |
| 22 | **Trauma-blind content** (sexual-assault prompts, porn suggestions) | 26 low / 6 apps | Spicer, Coral, Love Nudge |
| 23 | **Accessibility failures** (large text cuts off questions) | 47 low / 15 apps | Gottman Cards (Oct 2026) |
| 24 | **Review nagging and pay screens before any value** | 15 low / 3 apps; "Initial screen upon opening the app is a pay screen" | Covenant, Lasting, Together, Love8 |
| 25 | **Data that drifts or is wrong and starts fights** ("The app starts fights because of miscommunicated information") | Honeydue sync 234 mentions | Honeydue, Cupla (wrong dates) |

### 3.3 Top 25 unmet needs and feature requests

| # | Unmet need | Evidence | Who asks |
|---|---|---|---|
| 1 | **A fair free tier, monthly or one-time pricing, and one price for the couple** | Request cluster "free/cheaper/monthly" 109 snippets / 21 apps; "monthly/lifetime/one-time" 144 / 15 | Paired, Agapé, Coral, Couple Joy |
| 2 | **Conversation inside the app around each answer:** reply, comment, react; bring back chat | Chat/comment requests 93 snippets / 17 apps; Paired chat-removal backlash | Paired, Evergreen, Agapé, Between |
| 3 | **Content personalised to our relationship type** (married or dating, kids, LGBTQ+ or straight, monogamous, faith) and **filters that actually work** | Paired (PennyGirl87, cforabba, Venom77xx, Craine0318), Evergreen, Couple Joy, Spicer | Married, religious, queer and ace users alike |
| 4 | **Write our own questions and prompts** | 66 snippets / 15 apps ("allowing to add our own questions") | Lovewick, Candle, Desire |
| 5 | **More and fresher content that doesn't repeat** | 52 snippets / 13 apps | Evergreen, Spicer, Couple Joy |
| 6 | **A gentle "remind my partner" that isn't nagging, and per-type notification control** | 48 snippets / 14 apps (Evergreen "button to remind your partner"; Paired filters) | Evergreen, Paired, Between |
| 7 | **Shared calendar, lists and to-dos inside the relationship app** | 65 snippets / 16 apps | Between, Cupla |
| 8 | **Richer memories:** video, voice, journal, scrapbook, bulk photo actions | 70 snippets / 14 apps | Between, Agapé, Couple Joy |
| 9 | **Video and voice calling in the couple space** | 48 snippets / 13 apps | Between (repeatedly), Widgetable |
| 10 | **Customisation and theming** (dark mode, colours, own photos, custom moods) | 82 snippets / 14 apps; Cozy Couples custom-mood requests | Between, Cozy Couples |
| 11 | **Seeing how we've grown:** history, progress, insights, export | 21+ snippets / 11 apps; Evergreen ("day 300… no ability to see how our relationship has grown"); Blueheart (partner progress) | Evergreen, Love Nudge, Blueheart |
| 12 | **Neutral answer options** ("neither", "both", "doesn't apply") so a disagreement isn't labelled a "growth area" | 31 snippets / 15 apps; Paired (Jillianmay3) | Paired, Couple Joy |
| 13 | **Forgiving streaks:** free freezes, time-zone-aware days, no reset when one partner is sick | Paired, Cozy Couples, Couple Joy streak reviews | LDR couples |
| 14 | **Edit or delete answers and messages; deletion that is real on both sides** | 16 snippets / 11 apps; Locket "only deletes the pic on your side"; Just Between Us | Paired, Locket, Just Between Us |
| 15 | **Clean breakup handling:** no old data on a new partner, compassionate unpair, export, deletion | Paired 2023, Lasting 2022, Between "CANCELED" email, Couple unpair | Anyone re-partnering |
| 16 | **Discretion:** no lock-screen previews, neutral icon, CarPlay-safe, kid-safe | Between "wouldn't pop up on the lock screen"; Just Between Us (CarPlay, kids); Lovewick icon "looks like a dating app" | Parents, professionals |
| 17 | **Multi-person, poly and family modes** | 36 snippets / 12 apps; Candle, Couple, Spicer polycule | Poly users; families (Agapé 3-connection backlash shows non-couples are a misfit) |
| 18 | **Android, iPad and web parity** | 15 snippets / 10 apps + cross-platform pains | Mixed-OS couples |
| 19 | **Long-distance specifics:** time zones, distance widget refresh, meetup countdown, visit planning | LoveTrack, Love Nudge, Couple Joy requests; Flamme bucket-list praise | LDR couples |
| 20 | **Conflict help in the moment, not just prompts** | Therapist review: conflict support is "the biggest gap in most apps"; Maia argument analyser failed; CoupleBee "surface-level by design" | Couples in conflict |
| 21 | **Private space for one partner to process before sharing** | CoupleBee "No private space to be fully honest"; dvoe positioning (private + shared layer) | Couples in conflict |
| 22 | **Faith-integrated content** (Christian, Muslim, Jewish) | Paired 12 faith requests; Marriage 365 scripture complaint; scoping review: religion 1/38 apps | Faith couples |
| 23 | **Trauma-informed, consent-aware intimacy content** with opt-outs and content warnings | Spicer survivor review; Coral porn/abuse framing; Love Nudge "trauma, abusive past" | Survivors, recovering couples |
| 24 | **Transparent, human-quality AI with opt-out** ("no way to opt-out of the use of AI"; AI questions feel "detached"; "Lose the AI please") | Paired (aEDS-er 2026), Candle (2 reviews), Ember, Connected ("AI generated slop") | Privacy-minded and quality-minded users |
| 25 | **Accessibility** (Dynamic Type, disability-aware suggestions) | Gottman Cards large text; Love Nudge "doesn't work well if one partner is disabled" | Older and disabled users |

---

## 4. Patterns by couple type

**Long-distance (LDR)** — the most enthusiastic segment (880 mentions, overwhelmingly positive).
- Wants ambient presence: home-screen photos (Locket), distance and countdown widgets (Couple Joy, Widgetable), touch (Bond Touch, thumbkiss), mood, and daily questions that substitute for dinner-table talk.
- Specific pains:
  - Time-zone-blind streaks and "days". Paired 60→2 streak at a 9-hour gap. Cozy Couples "streak ends randomly".
  - Widgets that refresh slowly.
  - Hardware that fails across OSes.
  - Requests for meetup planning and countdowns (Flamme bucket list, Couple Joy countdown).
- Military and deployment couples appear repeatedly (Couple Joy Korea deployment; Lovewick "dual military relationship").

**Cohabiting / busy couples** — value coordination and micro-check-ins more than deep content.
- Cupla for weekly planning. Honeydue for money. Life360 commute alerts ("start dinner"). Bond Touch taps during 12-hour shifts.
- Pain: data drift starting fights (Honeydue). Together (Delony) users describe "living more like coworkers… This helps us".

**Newly dating** — use questions to get to know each other fast ("getting to know eachother better and fast").
- Most sensitive to price ("tapped out"). Most likely to churn when the free tier shrinks (Lovewick, Candle).
- Teens and young adults are heavy users of widget and pet apps (Cozy Couples mood requests "because teenagers use this a lot").

**Engaged / newlyweds** — want future-planning conversations (money, kids, faith, families).
- LoveTrack found at a bridal expo. Lovewick used "from dating, to engaged, to married". Lasting is used as pre-counselling.
- Honeydue is praised for joint finance transparency, encouraged by premarital counsellors (Mandykate).

**Parents** — are time-poor (389 "few minutes/quick" mentions) and want discretion from kids ("our kids grabbing our phones" — Just Between Us).
- Content mismatch: "Are we married? … kids?" requests in Paired.
- Love Nudge users ask for goals for kids. Co-parents after separation are served by separate apps (Onward, SupportPay).

**Faith-based couples** — are underserved and split two ways.
- Some want explicit faith content: Covenant, Christian categories in Paired (12), scripture (Marriage 365).
- Others want secular apps that respect their boundaries: hide same-sex imagery, no porn suggestions, monogamy-only, "family friendly setting" for couples waiting for marriage.
- No Muslim or Jewish married-couple app with real traction was found. The scoping review ranks religion as the least-addressed factor (1/38).

**LGBTQ+ couples** — reward explicit inclusion and punish exclusion fast.
- Paired is praised by trans and same-sex couples. Coral and Love Nudge are condemned for binary gender fields ("I would have to lie to create an account").
- Polyamorous users can't add a third person (Candle, Couple, Spicer requests).
- Asexual users want sex topics off (Paired).
- **Key tension:** the inclusive imagery that queer couples love is what some conservative couples ask to hide. **Per-couple personalisation resolves both.**

**Couples in conflict / therapy** — want structure and live help.
- Lasting "great for our unstable relationship". OurRitual and ReGain for live sessions. Marriage 365 used solo.
- Pains:
  - Apps that "cause conflict to sell a solution" (Lasting).
  - Prompts that trigger fights (Refinery29's psychologist).
  - Expensive, rigid therapy logistics (OurRitual $260–310, refusals of refunds).
  - Counsellor mismatch (ReGain).
  - The partner who won't engage (Coral, Lasting, Blueheart).
- Therapist view: apps are "vitamins, therapy is medicine". Conflict tools are the biggest gap ([South Denver Therapy](https://www.southdenvertherapy.com/blog/do-relationship-apps-work-therapist-review)).
- **Coercion signal:** one Love Nudge user feels unable to tell a partner of 30 years that she hates the app.

**Older / long-married couples** — evidence is thin (no age field in reviews).
- Signals:
  - Long-married reviewers dismiss nudge apps ("Who needs an app to learn how to love each other… 25 years").
  - Large-text failures (Gottman Cards).
  - Content assuming early-stage relationships ("Why all the questions about my birth family…").
  - Positive: "boyfriend of nearly 20 years… it is fun for us" (Cozy Couples). Lovebox used to connect with parents.

---

## 5. Notable failure modes

1. **Shut down and took the memories with it.**
   - Avocado: closed Feb 2017 for "lack of funding". It at least offered an export.
   - Couple/Pair: bought by Life360 in 2016, defunct April 2019.
   - Kindu: discontinued.
   - Honeyfi: gone. Zeta couples: reportedly ended 2025.
   - Users carry this distrust forward: "eager to find Between after the demise of Couple and the various other similar apps".
   - Honeydue reviewers predict its shutdown from removed features and silent support.
2. **Lost the memories without shutting down.** Between, Sept 2025 to June 2026: users report that free users' photos were "deleted by accident", that the data is not recoverable, and "38,000 photos" including wedding photos. A couples app's memory vault is the highest-trust asset in the category, and losing it produces the angriest reviews in the corpus.
3. **Took away what was free.**
   - Lovewick's 10→1 questions (July 2024) produced a wave of 1★ "greed" reviews.
   - Desire removed community dares (2019): 38 reviews, "Update killed the app".
   - Paired removed chat and the store (2024).
   - Cozy Couples paywalled old notes after the fact (Dec 2025).
   - LoveSync went from free to 3 syncs a month.
   - Lovebox put colour and templates behind a subscription after hardware purchase.
   - **Users tolerate a paywall they meet on day one far better than one added later.**
4. **Leaked the old relationship.** Paired restored a deleted account's quiz answers when the user paired with a new partner ("a slap in the face"). Lasting showed a new partner's sessions with his ex-wife. Both are trust-destroying moments that standard account-model design causes by default.
5. **Broke its own privacy promise.** Spicer's "only matches are revealed" could be bypassed through "Change Answers" (2019). Between changed its data policy without E2EE, and lifetime buyers revolted.
6. **Mistook engagement for value.**
   - Agapé forced users to recruit 3 connections.
   - Cozy Couples charges monthly for streak repair.
   - Paired's streak timers sit on the lock screen.
   - Love8 makes the partner's location and battery the free hook.
   - A therapist: "If the primary feature is earning badges or protecting streaks, the app is designed for engagement, not growth".
7. **Excluded users at the front door.** Coral's binary gender fields (2020) and Love Nudge's he/her-only text lost users before they saw any content.
8. **Sold surveillance as safety.** Life360 sold precise location data to brokers until 2021. Partner tracking is normalised among young people, and research links it to coercive control (eSafety; Griffith). Couples apps that copy location features inherit this risk.
9. **Built for engagement, shipped broken.** Bond Touch: 57% of the sample rated 1–3, mostly pairing failures. Maia and Connected crash or are called "AI slop" within months. Love Nudge goals never synced. Coral lost staff and stopped events.

---

## 6. Monetisation lessons: what users accept vs resent

**Accepted (or praised):**
- **One subscription that covers both partners.** Users notice it and praise it: "$12 for both you and your partner, not per person" (Lasting); "One membership works for two people, so the value is incredible" (Paired).
- **A generous free core plus optional depth.** Agapé's old free tier ("100% get value out of the free app"). Spicer's free version "more than enough tools". Gottman Cards and Love Nudge fully free. LoveTrack free with no ads.
- **Monthly options and small prices.** "I'd be happy to pay $5 a month… but paying so much up front or $10 a month is too high" (Paired). Many reviewers name $2–5 a month as fair (Couple Joy: "$10 a year maybe 15$").
- **Lifetime purchases**, for Between, Agapé and Desire users who want to "pay once".
- Paying for **therapist-designed structure** (Lasting, Coral) when it works. Paying for live therapy, if refund and cancellation terms are honest.

**Resented:**
- **Paying to see your partner's side:** answers (CoupleGrow), calendar beyond 7 days (Cupla), notes you already wrote (Cozy Couples). The couple feature *is* the product.
- **Retroactive paywalls and removed features** (§5.3).
- **Annual-only billing presented as a monthly price** ("they spin it off as 'oh it's only $2.08 per month'… Then why can't I just pay $2.08 a month?" — Agapé).
- **Trials that silently convert to annual.** Charges after the partner never joined or after a breakup (Lasting). Both accounts having to cancel (CoupleGrow). Double charges across web and App Store (Paired). Partner purchases that don't unlock for the other (Agapé, Couple Joy, Spicer "packs have to be purchased on both phones").
- **Ads in an intimate space**, especially sexual ads in chat (Between, Widgetable), and ad-gated basics (Widgetable pet food, Loveit).
- **Paid streak repair or freezes** that turn the relationship into a loss-aversion tax (Cozy Couples monthly repair; Hint of Us sells streak freezes).
- **Subscriptions on top of hardware** (Lovebox, Bond Touch Lite, Filimin).
- **Pay screen before any value; review prompts before use** (Together, Lasting, Covenant).
- **Upsell clutter after a lifetime purchase** (Between red dots).
- **Mandatory data collection or friend recruitment as the price of "free"** (Agapé).

**Net lesson:** users accept paying for *depth* (courses, extra packs, live experts) and *permanence* (backup, lifetime). They resent paying for *access to each other*, being *surprised* by charges, or *losing* something they already had.

---

## 7. Safety, privacy, coercive control and breakups (consolidated)

1. **Partner surveillance is normalised, and dangerous at the margin.**
   - Location sharing is read as commitment, and stopping it as distrust (Griffith).
   - About 13% of Australian adults find partner monitoring reasonable (eSafety).
   - 25% of US adults admit checking an ex's real-time location (ExpressVPN).
   - Abusers mostly use legitimate features through shared accounts (Freed CHI 2018; Chatterjee S&P 2018).
   - **Any couples app with location, battery, "last seen" or read receipts is a potential coercive-control tool** unless designed against it: symmetric visibility, easy and quiet stop, no punishment for pausing, no dealbreaker framing.
2. **Some people cannot say no to the app.** Mumsnet's OP fears an "explosion" if she turns tracking off. A Love Nudge user can't tell her partner she hates it. Ember's 24-hour windows punish non-response. Exit has to be safe and face-saving.
3. **Sensitive content needs discretion by default.**
   - Users praise apps that keep intimate content off lock screens and CarPlay and away from kids (Just Between Us).
   - They ask Between for no lock-screen pop-ups and are embarrassed by a "dating app"-looking icon (Lovewick).
   - **No review in the corpus documents a third party seeing a sensitive Paired notification.** The risk is real but un-evidenced for Paired specifically.
4. **Sexual data demands top-tier privacy.** Coral's privacy policy alarmed users ("Hope you don't mind THE WORLD knowing about your sex life!"). Spicer's terms reportedly allow staff to view content. Spicer's match-only reveal leaked through a UI path.
5. **Breakups are mishandled across the board.**
   - Data from an old relationship resurfaces with a new partner (Paired 2023, Lasting 2022).
   - Unpairing destroys shared memories (Couple), or keeps them only for 30–90 days with a cold legalistic email (Between).
   - Users are charged after breaking up (Lasting).
   - An ex's photos may persist (an unverified Couple Joy claim).
   - Deleting on one side doesn't delete on the other (Locket, Just Between Us).
   - The CHI 2024 study "Delete it and Move On" shows shared intimate content is scattered across platforms after breakups.
   - **No app in the corpus offers a designed, compassionate, safe breakup flow.**
6. **AI raises a new consent question.** "no way to opt-out of the use of AI in the app. It feeds ALL of your responses to an AI" (Paired, 2026). Users notice and dislike AI-written prompts and AI review replies.

---
## 8. Implications for the synthesis (evidence-backed, not prescriptions)

These are the patterns a "best relationship app" would have to answer, stated as user evidence:

- **The core loop users love is cheap to deliver:** a daily prompt, a blind reveal, then talking offline. Charging for that loop is the top source of anger.
- **A memory vault is the stickiest feature and the most dangerous to get wrong** (Between). Durability, export and a breakup policy are part of the product.
- **Personalisation to the specific couple** (stage, kids, orientation, monogamy, faith, sex-topic opt-in) is requested from every direction and resolves the representation tension.
- **Streaks motivate many couples but must be forgiving** (time zones, illness, no paid repair). Bug-caused streak loss is a reliable 1★ trigger.
- **The "both partners" problem is structural:** one partner engages, the other doesn't, and reviews under-report it. Solo-useful value and gentle, non-nagging invitations matter.
- **Safety-by-design is a regulator ask** (eSafety): location and presence features need anti-coercion design, discreet notifications, and safe exits.
- **Breakup and re-partnering are a blank space:** no competitor handles them well, and failures are visceral.
- **Conflict support and a private space to process** are the clearest functional gaps identified by therapists and reviewers.

---

## 9. Sources

### Primary corpus (App Store, US)
- Apple customer-review RSS feeds, pattern `https://itunes.apple.com/us/rss/customerreviews/page={1..10}/id={APP_ID}/sortby={mostrecent|mosthelpful}/json`, pulled 2026-10-16. App IDs:
  - Paired 1469609343, Lovewick 1516199115, Between 458035189, Agapé 1507907556, Flamme 1583601044
  - Lasting 1225049619, Love Nudge 495326842, Gottman Card Decks 1292398843, LoveTrack 6608982670, Evergreen 1573360122
  - Honeydue 1157633945, Cupla 1557764033, Coral 1448861466, Spicer 1335558932, Desire 923073855
  - Widgetable 1641107226, Locket 1600525061, Couply 1484241314, Couple Joy 1624758651, Raft 949819247
  - Candle 6743355635, Bond Touch 1291952832, Lovebox 1154499750, Life360 384830320, Covenant 6744675778
  - Connected 6758622511, OurRitual 1671770240, Blueheart 1473815579, Maia 6462700876, Amora 6756627554
  - Pookie 6756569878, Ember 6744977130, Cozy Couples 6463766369, CoupleGrow 6443615953, Love8 6448163027
  - Together (Delony) 6742922524, ReGain 1206964049, Marriage 365 1628739510, Loveit 1609366842, Couple Tree 1550789824
  - Just Between Us 1498275568, Couple Game 1391022038, LoveSync 1483221951, Couples Games & Challenges 933524873
- iTunes Search API for store-wide rating counts: `https://itunes.apple.com/search?term=…&entity=software&country=us`.
- App Store review pages read directly:
  - [Paired](https://apps.apple.com/us/app/paired-couples-relationship/id1469609343?see-all=reviews)
  - [Lovewick](https://apps.apple.com/us/app/lovewick-relationship-tracker/id1516199115?see-all=reviews)
  - [Between](https://apps.apple.com/us/app/between-the-app-couples-love/id458035189?see-all=reviews)
  - [Flamme](https://apps.apple.com/us/app/flamme-cozy-couples-app/id1583601044?see-all=reviews)
  - [Lasting](https://apps.apple.com/us/app/lasting-marriage-couples/id1225049619?see-all=reviews)
  - [Gottman Card Decks](https://apps.apple.com/us/app/gottman-card-decks/id1292398843?see-all=reviews)
  - [LoveTrack](https://apps.apple.com/us/app/-/id6608982670?see-all=reviews)
  - [Honeydue](https://apps.apple.com/us/app/honeydue-couples-finance/id1157633945?see-all=reviews&platform=iphone)
  - [Evergreen](https://apps.apple.com/us/app/evergreen-relationship-growth/id1573360122?see-all=reviews)
  - [Coral](https://apps.apple.com/us/app/coral-couples-relationship/id1448861466?see-all=reviews)
  - [Widgetable](https://apps.apple.com/us/app/widgetable-besties-couples/id1641107226?see-all=reviews)
  - [Locket](https://apps.apple.com/us/app/1600525061?see-all=reviews)
  - [Covenant](https://apps.apple.com/us/app/covenant-christian-marriage/id6744675778?see-all=reviews)
  - [Islamic Couples & Relationship](https://apps.apple.com/us/app/-/id6477761051)

### Review aggregators (verbatim quotes only)
- [JustUseApp — Paired](https://justuseapp.com/en/app/1469609343/paired-relationship-couples/reviews)
- [JustUseApp — Love Nudge](https://justuseapp.com/en/app/495326842/love-nudge/reviews)
- [JustUseApp — Agapé](https://justuseapp.com/en/app/1507907556/agapé-relationship-wellness/reviews)
- [JustUseApp — Spicer](https://justuseapp.com/en/app/1335558932/spicer-sex-ideas-for-couples/reviews)
- [JustUseApp — Couple Joy](https://justuseapp.com/en/app/1624758651/couple-joy-relationship-app/reviews)
- [JustUseApp — Couply](https://justuseapp.com/en/app/1484241314/couply-couples-relationship/reviews)
- [Unstar — 1–3★ analysis of Paired/Lasting/Love Nudge/Evergreen/Cupla](https://unstar.app/blog/paired-lasting-love-nudge-evergreen-cupla-couples-apps-ranked-2026). A vendor analysis; sample size not disclosed.

### Trustpilot
- [Bond Touch](https://www.trustpilot.com/review/bond-touch.com)
- [Lovebox](https://ca.trustpilot.com/review/lovebox.love)
- [OurRitual](https://nz.trustpilot.com/review/www.ourritual.com)

### Vendor, help centre and policy pages
- [Paired FAQ (pricing; one subscription for both)](https://www.paired.com/frequently-asked-questions)
- [Paired — unpairing](https://support.paired.com/en/articles/164637-how-do-i-unpair-my-account-from-my-partner-s)
- [Between help — disconnect and recovery window](https://help.between.us/hc/en-us/articles/115006148087) (content via search snippets; direct fetch blocked)
- [Gottman Love Lab / Gottman Connect](https://www.gottman.com/love-lab/)
- [Honeydue](https://www.honeydue.com/)
- [Filimin support](https://support.filimin.com/hc/en-us/articles/53718641641363)
- [Bond Touch Lite](https://bond-touch.com/collections/bond-touch-lite)
- [Candle YC launch](https://www.ycombinator.com/launches/OFK-candle-the-duolingo-for-relationships)
- [Duolingo Friend Streak](https://blog.duolingo.com/friend-streak/)
- [Together (together-app.co) — "Why no streaks"](https://together-app.co/blog-why-no-streaks) (vendor opinion)
- [LoveTrack — ACF listing](https://peerta.acf.hhs.gov/content/lovetrack-app)

### Press and reviews
- [Refinery29 — Agapé review](https://refinery29.com/en-gb/relationship-wellness-app-agape-review)
- [Autostraddle — Couple.me group review](https://www.autostraddle.com/couple-me-app-is-co-dependent-also-wonderful-the-giant-group-review-213632/)
- [Android Police — Avocado closing](https://www.androidpolice.com/2017/01/20/avocado-messaging-app-couples-closing-doors/)
- [Wikipedia — Couple (app)](https://en.wikipedia.org/wiki/Couple_(app))
- [Life360 — acquires Couple](https://www.life360.com/press/love-is-in-the-air-life360-acquires-couple-the-app-for-two)
- [TechCrunch — Paired funding](https://techcrunch.com/2021/05/27/paired-pulls-in-3-6m-to-encourage-more-couples-to-get-cosy-with-app-based-relationship-care)
- [ChoosingTherapy — Lasting](https://www.choosingtherapy.com/lasting-app-review/)
- [ChoosingTherapy — OurRelationship](https://www.choosingtherapy.com/our-relationship-review/)
- [South Denver Therapy — therapist review of relationship apps](https://www.southdenvertherapy.com/blog/do-relationship-apps-work-therapist-review)
- [CoupleBee — Paired reviews](https://couplebee.com/blog/paired-app-reviews) (competitor)
- [Cupla blog — shared calendars](https://cupla.app/blog/the-5-best-shared-calendar-apps-for-couples/) (competitor)
- [LON.tv — Lovebox review](https://blog.lon.tv/2024/03/04/the-lovebox-review/)
- [Deseret — how Locket works](https://www.deseret.com/2022/1/27/22902015/how-the-locket-app-works-family)
- [Boots — Blueheart](https://www.boots-uk.com/newsroom/news/boots-expands-online-health-services-offering-with-sex-and-relationship-therapy-app-blueheart)
- [Scottish Financial News — Relish](https://www.scottishfinancialnews.com/articles/forfar-born-entrepreneur-launches-new-app-in-the-usa)
- [Financial Planning — couples fintech](https://financial-planning.com/news/families-couples-ex-couples-fintechs-delve-into-shared-finance)
- [AlternativeTo — Kindu (discontinued)](https://alternativeto.net/software/kindu/about)
- [Cohesa — intimacy apps guide (lock-screen advice)](https://cohesa.io/blog/best-apps-couples-intimacy)

### Location, surveillance and coercive control
- [ABC News — eSafety Commissioner research on location apps and coercive control (2025)](https://www.abc.net.au/news/2025-05-15/location-sharing-apps-esafety-commission-coercive-control/105289994)
- [The Conversation — Griffith University study on location sharing and young people](https://theconversation.com/location-sharing-apps-are-enabling-domestic-violence-but-young-people-arent-aware-of-the-danger-253932)
- [Vice — psychologists on partner location sharing](https://www.vice.com/en/article/is-sharing-your-location-with-a-partner-actually-healthy-heres-what-a-psychologist-says/)
- [Mumsnet — "Life 360 tracking - controlling behaviour?"](https://www.mumsnet.com/talk/relationships/4752805-life-360-tracking-controlling-behaviour)
- [The Markup — Life360 selling location data (2021)](https://themarkup.org/privacy/2021/12/06/the-popular-family-safety-app-life360-is-selling-precise-location-data-on-its-tens-of-millions-of-user)
- [Fox News / ExpressVPN survey — tracking an ex's location](https://www.foxnews.com/lifestyle/1-of-4-americans-tracking-exs-real-time-location)
- [Boise State — Snapchat and jealousy](https://experts.boisestate.edu/en/publications/relationships-between-jealousy-in-intimate-partnerships-and-the-u-2/)
- [Chatterjee et al., "The Spyware Used in Intimate Partner Violence", IEEE S&P 2018](https://www.cs.cornell.edu/~rahul/papers/IPV_Spyware.pdf)
- [Freed et al., "A Stalker's Paradise", CHI 2018](https://www.classes.cs.uchicago.edu/archive/2020/winter/20370-1/readings/Stalkers.pdf)
- [Intego — stopping sharing with an ex on iPhone (Safety Check)](https://www.intego.com/mac-security-blog/bad-breakup-how-to-stop-sharing-data-with-your-ex-on-iphone-and-ipad/)
- [Pew — couples and technology (2014)](https://www.pewresearch.org/internet/2014/02/11/couples-the-internet-and-social-media/). Pew 2020 phone-snooping figure via [Statista](https://statista.com/statistics/1124855/adults-united-states-partner-cellphone-looked-through).
- ["Delete it and Move On": Digital Management of Shared Sexual Content after a Breakup, CHI 2024](https://dl.acm.org/doi/10.1145/3613904.3642722) (abstract via search; full text blocked)

### Academic evaluations of couples apps
- [Aicken, Gabb et al., "Exploring the Potential of a Digital Intervention to Enhance Couple Relationships (the Paired App)", JMIR mHealth 2025](https://mhealth.jmir.org/2025/1/e55433)
- [Open University — Paired evaluation summary](https://university.open.ac.uk/research-projects/enduring-love/paired)
- [Mobile Apps for Relationship Improvement: A Scoping Review (2025)](https://www.scirp.org/journal/paperinformation?paperid=141110)
- [Military REACH — Agapé pilot (Rogge 2023)](https://aub.ie/MilitaryREACH-Rogge2023)

### Not accessible during this research
- reddit.com (blocked for both fetch and search).
- Google Play review text (pages truncated).
- PMC full texts (bot check).
- Medium (403).

# 07 — Opinions as Attune's only community surface (after Forums)

Researcher 07 · 2026-10-24 · Read-only research. No code, specs or other files were changed.

**Question.** Once Forums are removed, Opinions is the only community surface. It is meant to be a place where people "break free and write their thoughts without judgment". What makes anonymous writing spaces like this good or harmful? What should Opinions keep, soften, add or remove?

**Short answer.**

- The current anonymity *plumbing* is sound: `user_id` is never returned, and author handles are HMAC values.
- The *social layer* on top was built as a Twitter clone. It has public likes and dislikes, engagement-ranked Discover, follower counts, reposts, quotes, and a per-author profile that anyone can read, guests included.
- Those features work against "without judgment", and they work against the relationship promise "your partner doesn't know it's you".
- Separately, three things exist on paper but not in code:
  1. The pre-post content filter. It is promised in the specs and required by Apple guideline 1.2, but there is none.
  2. A self-harm or crisis path for authors. There is none.
  3. Any notice, reason or appeal for moderation decisions. There are none.

---

## 1. How this was researched

**Codebase (read-only):**
- `lib/features/opinions/**`, `lib/core/polls/**`, `lib/core/widgets/tag_picker.dart` and `tag_chip_row.dart`;
- `lib/home/home_screen.dart`;
- `lib/architecture/FORUM.md` (all 2,140 lines);
- `ATTUNE_MASTER_SPEC.md` §8.11;
- `ATTUNE_SOUL.md` §2, §8 and §9;
- `ATTUNE_THESIS.md` §3.6;
- `SAFETY_SYSTEM_SPEC.md` §1–3;
- `lib/app/documentations/user_manual/data/opinions_docs.dart`;
- the 2026-10-16 couples research (`03`, `04`, `05`, `06`).

**Migrations read in full or in their relevant functions:**

| Migration | What it covers |
|---|---|
| `20260716120000` | Launch |
| `20260716140000` | Anonymity hardening |
| `20260722120000` | Bans |
| `20260726120000` | Polls |
| `20260727120000` | Notifications |
| `20260730120000` | Edit window |
| `20260730130000` | Mute/hide |
| `20260802120000` | Report dedup |
| `20260807120000` | 5,000-character limit; latest `create_opinion` |
| `20260818120000` / `20260822120000` / `20260824120000` | Guest reads |
| `20260825120000` | Tag follows |
| `20260826120000` | Realtime counts |

**External sources:**
- peer-reviewed papers and meta-analyses;
- official platform policies (Apple App Review 1.2, Instagram 2021, Mastodon 2025);
- the Santa Clara Principles 2.0;
- press coverage of Yik Yak, Secret, Whisper, 7 Cups and Nairaland;
- Mumsnet threads.

**Limits. Please read these.**
- **The shared web-search budget ran out partway through this researcher's work.** After that, sources were checked only by fetching known primary URLs directly.
- Each external claim is marked:
  - **[V]** means verified this session, from the source page or a search abstract.
  - **[M]** means it comes from prior knowledge of a well-known paper and was *not re-verified this session*. The citation details (authors, year, venue, DOI) are given so the synthesis step can spot-check them.
  - Treat **[M]** numbers as approximate.
- **Reddit itself was not reachable**, as in the 2026-10-16 programme. Reddit evidence comes from peer-reviewed studies of Reddit.
- **No Ghana-specific or West African study** of anonymous relationship forums was found.
  - Nairaland evidence is thin (Wikipedia and press).
  - West African points are therefore marked as reasoning or unknown, not as findings.
- **Lemon8 and Threads:** I could not verify any anonymous-posting feature on either. The only transferable feature is Meta's per-viewer "hide like counts" control, which Threads inherited from Instagram **[M]**.
- **Evidence grades follow the brief:**
  - **Strong:** meta-analysis, large RCT or large dataset.
  - **Moderate:** peer-reviewed study, large survey or official policy.
  - **Weak:** small study, press or vendor claim.
  - **Anecdote:** reviews and forum posts.

---

## 2. Findings

### 2.1 What Opinions does today (code audit)

**Shell and navigation**

| Area | Today | Where |
|---|---|---|
| Place in the app | Two-tab shell: **Opinions** and **Chat**. Opinions is the default for single and personal users; Chat is the default for active couples. | `lib/home/home_screen.dart:372-381` |
| Inside the tab | An outer tab bar: **Opinions** and **Forums** (`IndexedStack` with `ForumsSection`). Opinions has inner tabs **Following** and **Discover**; guests start on Discover. | `opinions_tab.dart` |

**Posting and reading**

| Area | Today | Where |
|---|---|---|
| Compose | 10–5,000 characters, text only. Optional: up to 3 tags from a fixed list of **21** (FORUM.md says "20" but lists 21), and a 2–4 option poll. | `opinion_compose_screen.dart`, `create_opinion` in `20260807120000` |
| Compose: no confirmation | There is no "Post this?" confirmation. The spec requires one and the user manual promises one. | `opinion_providers.dart:469`, `opinions_docs.dart:103` |
| Compose: no drafts | The draft is lost when the sheet closes. | `opinion_compose_screen.dart` |
| Compose: copy | Two info cards. One says "Others see only your handle… Keep details that could identify you or your partner out of it." | `opinion_compose_screen.dart` |
| Feeds | **Following:** authors you follow plus tags you follow, newest first. **Discover:** posts with the same relationship status first, then `((likes − dislikes) + comments×2) × 1/(hours+1)`, with a tag filter. | `20260716140000`, `20260806120000`, `20260825120000` |
| Card | Shows the status glyph and label, the time, and the full text. | `opinion_card.dart` |
| Card: actions and counts | Public counts on **like (heart)**, **dislike**, repost, quote and comment. Saving has no count. A **Follow** button sits on others' posts. Counts tick live for every viewer through Realtime Broadcast. | `opinion_card.dart`, `20260826120000` |
| Comments | Flat. A reply carries a quote prefix. Comments can be liked and disliked. Comments are 5,000 characters, cannot be edited, and can be deleted. | FORUM.md §4.4 |
| Reposts and quotes | Repost is a one-tap reshare. Quote is your own opinion embedding another. Each has a public count and an "engagement" screen listing the quotes and the reposting handles. | `opinion_engagement_screen.dart`, `20260728120000`, `20260729120000` |
| Anonymous profile | Opened by tapping any card. Shows the status, the **follower count**, **every opinion** by that author and **every repost**. Your own avatar opens your own profile. | `anonymous_profile_screen.dart`, `get_author_*` RPCs |
| Polls | Results stay hidden until you vote. Aggregate counts only. You can change or retract your vote. | `20260726120000`, MASTER_SPEC §8.11 |
| Tags | Fixed vocabulary. Browse, search (from the list only) and follow. Tag filters can never be combined with an author filter. **No tag mute.** | FORUM.md §7, `tag_*_screen.dart` |
| Edit and delete | Edit within 15 minutes; shows "(edited)" with no history. Delete any time (soft delete). | `20260730120000` |

**Privacy, limits and moderation**

| Area | Today | Where |
|---|---|---|
| Hide and mute | Hide one post. Mute an author by handle, which also hides their past posts and stays silent. There is no Block, because the client never has a `user_id`. | `20260730130000`, `opinion_more_data.dart` |
| Anonymity | `author_handle = HMAC-SHA256(user_id, server secret)`. It is **stable forever and deliberately never rotated** ("rotating it would break follow relationships"). The same handle is on posts **and comments**. `user_id` is never in any RPC result. | `20260716140000:36-64, 270` |
| Guests | Can read Discover, comment threads, tags, tag browse, **author profiles including reposts**, quoted opinions and statuses. Cannot write anything. | `20260818120000`, `20260822120000`, `20260824120000` |
| Limits | 5 opinions per 24 hours with a 60-second cooldown; 20 comments per 24 hours; a ban gate. | `private.assert_can_post` |
| Reporting | Six reasons, one report per reporter per item. Content auto-hides at **10** reports. Priority is set only for "Identifies a real person", "Harmful or dangerous content" and "Hate speech". **Self-harm is not a reason.** Confirmation text: "We will review this within 24 hours." | `20260716140000`, `20260802120000`, `opinion_more_data.dart` |
| Removal and bans | `admin_confirm_content_removal` is service-role only (SQL editor; there is **no admin UI**). Three confirmed removals bring a 7-day ban. | `20260722120000` |
| Notifications | Likes (grouped), comments and replies, with a **60-character preview of the comment text in the push body**. Also reposts, quotes, "Post removed" (no reason given) and "Posting paused". Follows and dislikes are silent. | `20260727120000:238-335` |

**Mismatches and gaps found.** Each is a fact in the code or the docs.

1. **No pre-post content filter exists.**
   - FORUM.md §7–§9 and MASTER_SPEC §8.11 say opinions, quotes, edits and poll options all pass a "Layer 1 keyword filter".
   - In the code, `create_opinion` checks only length and `assert_can_post`, which is rate limits plus the ban gate.
   - No migration defines a keyword, contact-information or slur filter.
   - The content rules ban "contact information" and "real names", and nothing enforces either.
2. **There is no crisis path for authors.**
   - `SAFETY_SYSTEM_SPEC.md` §1.4 explicitly excludes "anonymous forum posts or comments" and "sender-authored self-harm or suicide statements", "pending a separate self-harm protocol".
   - So a person writing "I don't want to be here any more" in Opinions gets nothing, unless someone reports it. Self-harm is not a report reason, and it is not a priority reason.
3. **The privacy promise is overclaimed.**
   - The manual answers "Is there any way someone could figure out who I am from my posts?" with "Your posts show only your relationship status and post time — nothing else" (`opinions_docs.dart:166-168`).
   - In fact, every post *and comment* by one person is linked under one permanent handle. Anyone, guests included, can open that person's whole history from any single post.
4. **The specs disagree with the code on handles.**
   - THESIS §3.6 says "no handles, no avatars".
   - The compose copy tells users "Others see only your handle". It is not visibly shown, but it is a stable key.
   - The original MASTER_SPEC changelog (line ~3457) specified a **"daily-rotating hash"**.
   - The 2026-10-16 scenario doc says "anonymity is HMAC-rotated" (`04-scenarios-everyday.md:620`). That is not true of the code.
5. **Lock-screen leak.** Comment and reply text appears in push previews. This matters on shared or checked phones (see §2.7).
6. **No moderation notice, reason or appeal.**
   - "One of your posts was removed for violating guidelines" names no rule and offers no route to appeal.
   - There is no community-guidelines page anywhere in the Opinions UI.
7. **Status labels will drift.** The labels are Single, Taken, Figuring it out and Open. They predate the three new paths, and "Open" is ambiguous: it could be read as "open relationship".

### 2.2 Expressive writing: what the science actually supports

| Finding | Evidence | Grade |
|---|---|---|
| Writing about emotional experiences has a **small** average benefit across outcomes. Early estimates were larger because they used fixed-effects models. | Smyth 1998, *J Consult Clin Psychol* 66(1):174–184 (13 studies; d ≈ .47, reported second-hand) **[V]**. Frattaroli 2006, *Psychol Bull* 132(6):823–865, random effects over 146 studies, **r = .075** **[V]**. | Strong |
| For **depression specifically**, the benefit is close to zero. | Reinhold, Bürkner & Holling 2018, *Clin Psychol Sci Pract* 25(1), 39 studies, no benefit on self-reported depression **[V via abstract summary]**. Mogk et al. 2006, *GMS Psycho-Social-Medicine*, 30 studies with ≥4-week follow-up, no effect **[V]**. A 2023 meta-analysis of 31 RCTs (N = 4,012) found g = −0.12, with effects appearing after a delay **[V via summary; authorship believed to be Guo 2023, *Br J Clin Psychol* — M]**. | Strong (mixed) |
| The *instructions* matter more than the act. In 833 students, classic expressive writing did not beat a control. "Emotion-acceptance" instructions helped the most engaged writers. | Rude et al. 2023, *Front Psychol* 14:1192595 **[V]** | Moderate |
| Writing raises distress **immediately**, and the benefit (if any) comes later. | Smyth 1998 **[V]** | Strong |
| **About breakups:** writing about the *positive* aspects of a breakup raised positive emotion without raising negative emotion. Expressive writing about a breakup cut short-term physical symptoms. | Lewandowski 2009, *J Positive Psychol* 4(1) **[V]**. Lepore & Greenberg 2002, *Psychol Health* **[V existence / M detail]** | Moderate / Weak |
| **About separation, the key caution:** in 90 recently separated adults, both expressive-writing variants left **high ruminators** worse off about 8–9 months later than plain daily-activity writing. Low ruminators were unaffected. The author's advice: "get out of [their] head" and re-engage. | Sbarra et al. 2013, *Clin Psychol Sci* 1(2):120–134; APS release **[V]** | Moderate |
| Benefit tracks moving toward **meaning-making** (more insight and causal words across sessions), not repeated replay. | Pennebaker, Mayne & Francis 1997, *J Pers Soc Psychol* 72(4):863–871 **[M]** | Moderate |
| Benefits come from writing that **no one reads**. Most trials used private writing, sometimes destroyed afterwards. An audience is not the active ingredient. | Pennebaker & Beall 1986, *J Abnorm Psychol* 95(3):274–281 **[M]**. Frattaroli 2006 moderators **[M: I could not re-check the full moderator table]** | Moderate |
| **Sharing has a different payoff:** talking to others brings socio-affective benefits (closeness, feeling understood). It does *not* by itself produce emotional recovery unless the talk includes reappraisal. | Rimé 2009, *Emotion Review* 1(1):60–85 **[M]**. Zech & Rimé 2005, *Clin Psychol Psychother* 12(4) **[M]** | Moderate |
| Among adolescents with social-emotional difficulties, blogging about the difficulty **with comments open** beat private diaries and closed blogs. The comments were overwhelmingly supportive. | Boniel-Nissim & Barak 2013, *Psychol Serv* 10(3):333–341 **[M]** | Moderate (one RCT, teens) |

**What this means for Opinions:**
- "Write your thoughts without judgment" is a reasonable promise for *feeling heard*.
- It is a weak promise for *getting better*.
- It is a potential harm for people who ruminate after a breakup. They are exactly the users that the "Just for me" and Healing paths attract.
- The design should therefore:
  - offer a **private** route (the Reflection Journal) as a first-class alternative to posting;
  - frame prompts toward meaning and one's own side rather than replay;
  - avoid pulling recently separated users back into a feed of other people's relationship pain by default.

### 2.3 Venting, co-rumination and support

| Finding | Evidence | Grade |
|---|---|---|
| **Co-rumination** means revisiting problems again and again, speculating, and dwelling on negative feelings. It predicts closer friendships *and* more anxiety and depression. The distress comes from its overlap with rumination; the closeness comes from its overlap with self-disclosure. | Rose 2002, *Child Dev* 73(6):1830–1843; reanalysis by Calmes & Roberts **[V]** | Moderate (adolescents) |
| Online support-seeking was linked to *higher* depression and anxiety in adolescent girls. Support from friends was linked to lower levels. Digital co-rumination findings are mixed. | Mackenzie et al., *Front Psychiatry* 2023 (10.3389/fpsyt.2023.1040636) **[V]**. Van Zalk & Tillfors 2017 **[V]**. Battaglini et al. 2024, *J Adolesc* **[V]** | Moderate (cross-sectional, mixed) |
| **Rant sites:** reading and writing rants was followed by more anger and less happiness. Frequent ranters had higher trait anger. | Martin et al. 2013, *Cyberpsychol Behav Soc Netw* 16(2):119–122 **[M]** | Weak–Moderate |
| "Catharsis" venting raises anger and aggression; it does not drain them. | Bushman 2002, *Pers Soc Psychol Bull* 28(6):724–731 **[M]** | Moderate |
| **Composed comments** from close ties were linked to better well-being over time. **One-click feedback** (likes) and broadcasting were not. | Burke & Kraut 2016, *J Comput-Mediat Comm* 21(4):265–281 (about 1,900 users; logs plus surveys) **[M]** | Strong |
| On Reddit, anonymous (throwaway) mental-health posts drew more involved, emotionally engaged responses. | De Choudhury & De 2014, ICWSM (10.1609/icwsm.v8i1.14526) **[V]** | Moderate–Strong |
| Peer supporters on mental-health platforms show low empathy that **does not improve with time** unless they get feedback or training. | Sharma et al. 2020, EMNLP (235k interactions) **[V]** | Moderate |
| Structured, crowd-sourced *reappraisal* responses (Koko/Panoply) reduced depression in an RCT, compared with expressive writing alone. | Morris, Schueller & Picard 2015, *JMIR* 17(3):e72 **[M]** | Moderate |

**What this means for Opinions:**
- Support helps when it is *composed*, *warm* and *reframing*.
- Engagement metrics and pile-ons do not help.
- A feed that rewards comment volume (Discover gives `comments×2`) is optimising for the wrong thing.
- The highest-value change is to make sure posts that disclose something hard get *at least one* kind reply, rather than to make popular posts more popular.

### 2.4 Anonymous and pseudonymous platforms: what went right and wrong

| Platform | What made it supportive | What made it toxic or fail | Grade |
|---|---|---|---|
| **Reddit throwaways** (r/relationship_advice, parenting subs) | Throwaways were used for the most stigmatised disclosures and **drew more replies, longer replies and higher karma** (Ammari et al. 2019, *PACM HCI* 3(CSCW), 1,460 throwaways and 10,632 comments over 10 years **[V via U-Michigan release]**). Survivors used throwaways more to disclose abuse and seek support (Andalibi et al. 2016, CHI, 10.1145/2858036.2858096 **[M]**). | The identity is *per disclosure*, chosen by the user. A main account's history is never attached to the hard post. I could not reach Reddit itself. | Moderate–Strong |
| **Mumsnet** | The Talk Guidelines ask posters to think about whether details could identify them, and to make "judicious use of the name-change facility". "Outing" a poster is banned (2014 suspension of an MP for linking users' identities **[V]**). | Users describe **"jigsaw identification"**: scattered details across posts "totally outed" someone to people who knew them (Mumsnet thread 4108116 **[V, Anecdote]**). The site was court-ordered to unmask posters in defamation cases **[V, Weak]**. | Weak / Anecdote |
| **Yik Yak**, first era (2013–17) | The largest content study (19 universities, spring 2016) found **prosocial messages outnumbered bullying 5.23 to 1** (JMIR 2020;22(5):e17224 **[V via summary]**). | Bullying clustered *with* emotional help-seeking posts: vulnerable posts attract cruelty. Bomb and shooting threats. Shut down in May 2017 amid falling use and criticism **[V]**. NYU researchers located posts to within 300 ft and identified dorms with 100% accuracy **[V]**. | Moderate |
| **Yik Yak**, second era (2021–23) | Relaunched in 2021 with a "one strike and you're out" onboarding rule **[V]**. | Bullying accusations continued. A 2022 flaw exposed users' precise locations (10–15 ft) **[V, Weak]**. Sold to Sidechat in 2023. | Weak |
| **Secret** (2014–15) | — | Used for rumours about *identifiable people*. The founder shut it down saying it no longer matched his vision; press tied the closure to rumour-spreading and cyberbullying **[V, Weak]**. | Weak |
| **Whisper** | Confessional format. | The Guardian (Oct 2014) reported location tracking of "anonymous" users, including ones who had opted out. Whisper disputed it and admitted using IP addresses to get rough location **[V, Weak]**. *Lesson: an anonymity promise is only as good as the metadata policy.* | Weak |
| **7 Cups** | Free peer listening. | A Mashable investigation (2024) found unqualified listeners manipulating vulnerable youth, and trolling **[V, Weak]**. Mozilla rated its privacy "very concerning" (2023) **[V]**. *Lesson: one-to-one anonymous contact between strangers is the dangerous part.* | Weak |
| **NGL / Sendit-style apps** | — | Anonymous messages *aimed at a named recipient* produce harassment. The FTC acted against NGL in 2024 over fake messages and false claims that AI moderation stopped bullying. It barred the app from minors and imposed about $5M **[M; FTC page not reachable]**. | Moderate (regulator) |
| **Tumblr** | Pseudonymity, several accounts per person and separation from offline networks made it a haven for trans and queer users (Haimson et al. 2021, *Feminist Media Studies* **[M]**; Cavalcante 2019, *J Homosexuality* 66(12) **[M]**). | Reblog-with-commentary pile-ons, described as "vortexes" of negativity (Cavalcante 2019 **[M]**). | Moderate |
| **Nairaland** (Nigeria, West Africa's largest forum) | Pseudonymous. Reading needs no account; posting needs registration (Wikipedia **[V]**). | Criticised for ethnic bigotry and tribalism. Its host took the site offline in Dec 2023 after an overlooked abuse report. The owner then pledged to "focus on content moderation" (TechCabal 2023 **[V, Weak]**). *A guest-readable West African forum without staffed moderation drifts toward bigotry and host or legal risk.* | Weak |
| **Mastodon** (contrast) | For years it declined to build quote posts. The 2025 release says quoting "can be misused". It ships with author controls: opt out of being quoted, limit who can quote, and **remove your post from someone else's quote** (Mastodon blog, 11 Sep 2025 **[V]**). | — | Moderate (vendor policy) |

**Common pattern across platforms:**
- **Benign anonymity** is a person disclosing about *themselves*, with no persistent identity attached to the hard post.
- **Toxic anonymity** is anonymous speech *about or toward identifiable others*.
- Persistent anonymous identities, plus metadata, plus small communities, make people re-identifiable.

### 2.5 Anonymity and disinhibition: the research

- **Suler 2004.** The online disinhibition effect has a **benign** form (opening up, disclosure) and a **toxic** form (flaming, cruelty), driven by dissociative anonymity, invisibility, asynchronicity and the absence of authority (*CyberPsychol Behav* 7(3):321–326 **[V]**). — Moderate (theory, widely replicated)
- **Norms matter more than anonymity itself.** In a lab experiment, people wrote more aggressive comments when existing comments were aggressive. Anonymity had *no direct effect* but tended to strengthen conformity to the visible norm (Rösner & Krämer 2016, *Social Media + Society* 2(3) **[V]**). — Moderate
- **In the field,** 53.3% of anonymous newspaper comments were uncivil, against 28.7% of non-anonymous ones (Santana 2014, *Journalism Practice* 8(1) **[V via summaries]**). That was on adversarial topics (immigration). — Moderate (correlational)
- **Showing the rules works.** Posting community rules at the top of threads raised newcomers' rule-compliance by about 8 percentage points and increased newcomer participation (Matias 2019, *PNAS* 116(20):9785–9789, 2,190 r/science discussions **[M]**). — Strong (field experiment)
- **Negative feedback breeds worse behaviour.** Users who get down-votes then post *more*, post *worse*, and down-vote others more, so negativity spreads (Cheng, Danescu-Niculescu-Mizil & Leskovec 2014, ICWSM, arXiv:1405.1429 **[V]**). — Strong (four large communities)
- **Banning toxic communities works.** Reddit's 2015 bans cut hate-speech use by remaining accounts by about 80% or more (Chandrasekharan et al. 2017, *PACM HCI* 1(CSCW) **[M]**). — Strong

**Implication for Opinions.** Anonymity is not the problem. Visible norms, the content's subject (self versus others), the feedback design and moderation decide whether Opinions is benign or toxic. Opinions currently has the *dislike* button, which is exactly the feedback design that Cheng shows degrades a community. It also has no visible norms at compose time.

### 2.6 "Without judgment" design patterns

#### (a) Public like counts

- **Herding.** One random up-vote at the start raised the eventual rating of a comment by about 25%. Negative manipulation was corrected by the crowd. Visible scores herd judgement (Muchnik, Aral & Taylor 2013, *Science* 341:647–651, about 100k comments randomised **[M]**). — Strong
- **Conformity in teens.** Adolescents "liked" photos with many likes more often, and reward circuitry responded to receiving likes (Sherman et al. 2016, *Psychol Sci* 27(7) **[M]**). — Weak–Moderate (small fMRI)
- **Instagram's test.** Instagram tested hiding likes. It reported that "not seeing like counts was beneficial for some, and annoying to others", and in May 2021 shipped a *choice* to hide counts on others' posts and on your own (about.instagram.com, 26 May 2021 **[V]**). Instagram never published the effect sizes **[V]**. — Moderate (policy) / Weak (outcome)
- **Attune's own rules.** SOUL §9 Forum: "Community belonging without competition. The forum is connection, not comparison", and "Never creates visible status hierarchies." Public like counts, follower counts and engagement ranking are comparison mechanics. — Binding product rule

#### (b) Reactions that support rather than rank

- Burke & Kraut (above) found that **one-click feedback adds little well-being**. Its value is a cheap signal of "you're not alone", which matters most for posts that would otherwise get nothing.
  - The Yik Yak data show the vulnerable posts are the ones that draw cruelty.
  - Reddit data show anonymous disclosures draw *engaged* support.
  - So the design goal is that every hard post receives warmth, and no post receives a score.
- **Dislike has no supportive form.** "Not for me" is already served by **Hide**, which is silent and private.
- A small set of reactions that cannot be read as a verdict fits the promise. Candidates: "I relate", "Sending strength", "This helped me".
  - Their counts should be visible **to the author only**, or not shown at all.
  - They should **never** be used for ranking.
- This is design reasoning built on the cited evidence. No study of "hug" buttons was found this session.

#### (c) Comments: help or hurt?

- **For:** Boniel-Nissim & Barak (open comments beat private diaries); De Choudhury and Ammari (anonymous posts drew richer replies).
- **Against:** Sharma (peer empathy is low and does not improve); Yik Yak (bullying clusters on help-seeking posts); Rose and Mackenzie (co-rumination).
- **Gentle-comment patterns with evidence behind them:**
  - **Pre-send reconsider prompts.** In a Twitter RCT, prompting users on potentially offensive replies led to **6% fewer offensive tweets**, an effect that persisted later, plus fewer offensive replies to those tweets (Katsaros, Yang & Fratamico 2022, ICWSM, arXiv:2112.00773 **[V]**). — Strong
  - **Show norms at the point of writing** (Matias 2019 **[M]**). — Strong
  - **Author controls over their own thread.** Mastodon's opt-out and remove-from-quote controls (2025 **[V]**) are the model.
  - **Response structure.** Koko's reappraisal format (Morris 2015 **[M]**) shows that *prompted* responses ("What might help them see this differently?") beat free-for-all advice.

#### (d) Content warnings

- A meta-analysis found trigger warnings **do not reduce** negative emotional responses to the material. They **increase anticipatory anxiety** and do not meaningfully increase avoidance (Bridgland, Jones & Bellet 2023, *Clin Psychol Sci*, 10.1177/21677026231186625 **[M; publisher page blocked]**). — Strong (if confirmed)
- Choice-based filtering, letting people decide what they never see, is a different mechanism. It is the trauma-informed "choice" principle the 2026-10-16 research already adopted: per-user tag mute (06 B13) and topic exclusions (06 §5).
- Implication: prefer **tag mute** and private opt-outs over warning labels.

#### (e) Writing for yourself versus posting

- §2.2 shows that the benefits of expressive writing do not need an audience, while the risks of an audience (recognition, judgment, co-rumination) are real.
- Attune already has a private **Reflection Journal** (`lib/features/reflection_journal`).
- A "Keep this private" choice at compose, which saves to the journal, removes the audience for people who only need to get the words out.

#### (f) Drafts and delayed posting

- **Regret.** People regret posts made while highly emotional, and relationships are among the most-regretted topics (Wang et al. 2011, SOUPS, "I regretted the minute I pressed share" **[M]**). — Moderate
- **Self-censorship is common.** 71% of 3.9 million Facebook users self-censored at least one post or comment over 17 days (Das & Kramer 2013, ICWSM **[M]**). — Strong (dataset)
- **Delay nudges.** A short **delay with a cancel option** and an audience reminder reduced unintended posts in a 6-week field trial. Some users found the timer annoying (Wang et al. 2014, CHI, 10.1145/2556288.2557413 **[M]**). — Weak–Moderate (small)
- **Implications:**
  - Keep drafts.
  - Offer "Post later" ("sleep on it"), especially late at night.
  - Use a short undo window rather than a blocking confirmation dialog.

#### (g) Edit and delete windows

- Deleting at any time protects the author: it is the escape hatch from regret and from recognition.
- The 15-minute edit window stops "bait-and-switch" edits after replies arrive. Mastodon and Twitter use similar windows; no outcome studies were found.
- Keep both.

#### (h) Safety for people writing about abuse or self-harm

- **The gap.** There is no route today (§2.1, items 1–2).
- **Attune's binding rules:**
  - the safety system is never LLM-dependent;
  - safety notifications go to the at-risk user only;
  - no accusation, no punishment (SAFETY §1.2).
- **The routing logic fits.** In Opinions, the at-risk person is the **author**. "Recipient-only" becomes "author-only". This is why SAFETY §1.4 excluded it: chat routing would send help to the wrong person.
- **A separate, clinically reviewed spec is required (SAFETY §1.4).**
- **Lexicon limits.** When Instagram banned pro-eating-disorder hashtags, communities moved to lexical variants with *more* toxic content (Chancellor et al. 2016, CSCW **[M]**). A deterministic lexicon will miss things and cannot be framed as complete detection. SAFETY §3.5 already says so.
- **Peer-triggered "send help" reports can be weaponised.** Reddit's "Get them help" feature is widely reported as used for harassment **[Anecdote, not verified this session]**. Any "worried about this person" report should go to a human, not straight to the author.

#### (i) Preventing a partner from being identified, and preventing doxxing

- **Uniqueness and stylometry.**
  - ZIP code, gender and birth date alone identify about 87% of Americans (Sweeney 2000 **[M]**).
  - Writing style alone identified the author among 100,000 blogs about 20% of the time at top-1 (Narayanan et al. 2012, IEEE S&P **[M]**).
  - A *linked history* of posts multiplies both effects. That is the jigsaw problem Mumsnet users describe.
- **Apple App Review guideline 1.2 (verified)** requires that apps with user-generated content include:
  - "A method for filtering objectionable material from being posted to the app";
  - a reporting mechanism "and timely responses";
  - "the ability to block abusive users";
  - "Published contact information".
  - It also says apps used for "random or anonymous chat… bullying" "do not belong on the App Store". — Official policy
- **Opinions today:**
  - It has **no pre-post filter**.
  - Mute is the closest thing to blocking, and is arguably adequate.
  - Contact information is not verified.
  - It has no one-to-one anonymous chat, which is good; keep it that way.

### 2.7 Relationship-specific risks

| Risk | How it happens in Opinions today | Evidence | What helps |
|---|---|---|---|
| **The partner recognises the author** | The partner sees one post they recognise (an event, a phrase, the time), taps it, and reads the author's **entire history of posts, comments and reposts** under one permanent handle. Guests can do this with no account. MASTER_SPEC §8.11 promises "Your partner doesn't know it's you — even if they're… in the same thread." | Jigsaw identification (Mumsnet **[V, Anecdote]**); stylometry (Narayanan **[M]**); Reddit throwaways exist for exactly this (Ammari **[V]**) | **Unlinkable posts by default** (a new handle per post); no author profile pages; coarse timestamps; honest compose copy |
| **Phone access by the partner** | Comment text in push previews on the lock screen. Your own avatar on the Opinions tab opens your own post history. | Abusers exploit physical device and account access (Freed et al. 2018, CHI, "A Stalker's Paradise" **[M]**). Phone checking is common among Ghanaian couples (2026-10-16 research, 01 §2.7 and B12). | Neutral push text ("Someone replied to you"); quick exit and app PIN covering Opinions; no "my posts" shortcut on the tab bar (keep it in a menu) |
| **The partner is recognised** (a post about *them*) | A detailed story about "my husband, the pastor in Kumasi…" identifies the partner to people who know them, without consent. | Secret's failure (rumours about identifiable people **[V, Weak]**); Mumsnet outing rules **[V]** | Self-focused compose prompts; a deterministic contact-information filter; report reason "Identifies a real person" with fast hide-pending-review |
| **Posts used as evidence or weapons** | Screenshots of a partner's anonymous post as "proof", or a partner posting to build a public case. Quotes and reposts amplify such posts. | SOUL §8: "Never generating content that could be used as evidence against a partner" (binds Attune's own outputs). Quote pile-ons (Mastodon 2025 **[V]**). | Remove quotes and reposts; offer "Copy text" only on your own posts; never show "how many people agreed" with a post about a partner |
| **Posting about the partner instead of yourself** | Opinions invites opinions. A post about the partner invites strangers' verdicts ("leave him"), which is the *judge* role SOUL forbids Attune itself from playing. | SOUL §2 "Not a judge" and §8 "Never: attributing negative behaviour to a named or implied partner" (these bind *Attune's* content, AI and prompts). Co-rumination research (Rose **[V]**). Network disapproval of a partner predicts breakup (Sprecher & Felmlee 1992 **[M]**). | Attune's prompts and copy never ask "what did your partner do?". Compose hint: "Write about your side: what happened, how you felt, what you need." Optional "Just listening, no advice" mode on posts |

**Rule check.** The "never attribute negative behaviour to a named or implied partner" constraint applies to Attune's *own* outputs: AI, prompts, copy, notifications and summaries. It does not ban users from writing about their lives. It does mean:

1. No Attune-written prompt may invite partner-blame.
2. No AI may summarise, tag or rewrite posts about a partner. THESIS §3.6 already firewalls forum content from the AI pipeline; keep that absolute.
3. Ranking and counts must never turn a post about a partner into an aggregated verdict ("847 people think he's wrong"). Public like and dislike counts on such posts are exactly that verdict.

### 2.8 Moderation for a small team

| Practice | Evidence | Fit for Attune at launch |
|---|---|---|
| **Visible norms at compose and in threads** | Matias 2019 **[M]**, Strong | Cheap; do it |
| **Deterministic pre-post filter**: contact information (phone formats including +233 and 0XX XXX XXXX, emails, URLs, @handles), a reviewed slur list including Twi, Ga, Ewe, Hausa and Pidgin terms, and explicit-sexual terms. **Block with a specific reason.** | Apple 1.2 **[V]**; explanations reduce future removals (Jhaver, Bruckman & Gilbert 2019, *PACM HCI* 3(CSCW), 10.1145/3359252 **[M]**) | Required for store review; needs a cultural reviewer for the local-language list |
| **Reconsider prompt on harsh comments** (deterministic list; non-blocking) | Katsaros 2022 **[V]**, Strong | Do it |
| **Report thresholds.** At 10 distinct reports the threshold will almost never fire in a small community. Dedup already stops a single account from hiding a post on its own. | Design reasoning (no study found this session) | Lower to **3 distinct reporters**, or **2 for "Identifies a real person" or "Someone may be at risk"**, to hide pending review |
| **Priority queue with an honest SLA** | FORUM.md promises "within 24 hours" and a 2-hour priority SLA; there is no admin UI | Build a minimal review screen (or a saved Supabase view plus a push to the moderator). Change the copy to "We review reports as quickly as we can" unless the SLA is staffed. |
| **Notice with reason and a human appeal** | Santa Clara Principles 2.0: notice must name the rule; appeals need "human review by a person… not involved in the initial decision" **[V]**. Jhaver 2019 **[M]**. EU DSA Art. 17 (statement of reasons) applies to hosting services **[M; legal check]**. | Add a reason to "Post removed", a one-tap appeal, and re-review by someone else (or the owner after 24 hours if solo) |
| **Ban ladder** (3 confirmed → 7 days, existing) | — | Keep. Add an escalation (for example permanent after a second ban) and phone-number reuse protection. |
| **Never AI for safety decisions** | Attune constraint | Keep. Any AI anywhere in Opinions is out of scope for v1 (THESIS §3.6 firewall). |
| **Track harm and health metrics (counts only)** | 06 §3 harm signals | Reports per 100 posts; removal rate; appeal overturn rate; % of posts with no reply after 24 hours; deletes within 24 hours (regret proxy); crisis-resource displays (count only, SAFETY §9) |

### 2.9 Migration from Forums

**What Forums users lose:**
- FOR/AGAINST debate rooms;
- topic submission and topic voting (activation at more than 50% of viewers);
- forum insight stats;
- activity and "going quiet" pushes;
- browse-only mode.

There are no real users, so the human cost is close to zero.

**What should fold into Opinions:**
- **Polls already exist on opinions.** They are the "what do people think?" mechanic, without sides.
- **Tags absorb the old forum categories.**
- **Add one Attune-authored prompt a week** ("Attune asks…", self-focused and clinician-reviewed). It replaces the "topic" structure that Forums gave people. Prompts are also how expressive writing is delivered in every trial (§2.2).

**What should not fold in:**
- **Sides.** Adversarial framing amplifies conformity to the visible norm (Rösner & Krämer **[V]**).
- **Majority-voted topics.** Content with moral-emotional and out-group language spreads further: about 20% per moral-emotional word (Brady et al. 2017, *PNAS* **[M]**), and out-group words greatly raised share odds (Rathje, Van Bavel & van der Linden 2021, *PNAS* **[M]**). Voted topics will select for provocation.
- **Insight counters.** These are comparison mechanics.

**Couplings found in code.** These are the regression risk for the removal spec.
- `forum_reports` holds **all opinion and comment reports**. Do not drop it with the forum tables; rename it later.
- `post_polls.topic_id` and `forum_topic_tags` share polls and tags with forum topics.
- `private.assert_can_post` has a `'topic'` kind.
- `CreateContentChooser` and `CreateContentFab` offer "Submit a topic" (`onTopicSubmitted`).
- `opinions_tab.dart` imports `ForumsSection` and `votingTopicsProvider`.
- `TagBrowseScreen` pairs Opinions and Forums tabs.
- Other places:
  - `notification_config.dart`;
  - the edge functions `activate-topics` and `forum-quiet-check`;
  - `forum_docs.dart` and its `manual_documentation_registry.dart` entry;
  - `count_broadcast_channel.dart`;
  - the `against` theme colour.

**How to tell users:** a release note plus updates to the manual (`opinions_docs.dart`; retire `forum_docs.dart`). If Forums ever had users, add a one-time card: "Debates are now polls in Opinions."

### 2.10 Regional and cultural notes

These are mostly reasoning; regional evidence is thin.

- **Ghana and West Africa.**
  - Norms against airing marital problems publicly ("don't wash dirty linen in public") make anonymity *more* valuable for help-seeking.
  - Small city and diaspora networks make jigsaw re-identification *easier*: fewer people fit "nurse, Kumasi, married 2 years, in-laws in Cape Coast".
  - Unlinkable posts matter more here than on Reddit. **No regional study found; reasoning.**
- **Faith communities.** Posts naming a church, pastor or role are highly identifying. The fixed tags lack West African staples: **family and in-laws, money, faith, marriage pressure**. A tag-follow list is special-category-adjacent data. It is already private (`20260825120000` header), and must stay private.
- **LGBTQ+ safety.**
  - Ghana's anti-LGBTQ bill passed parliament in February 2024 and was reintroduced in 2025. As reported by HRW, it criminalises content "promoting" prohibited activity and *failing to report* LGBT people (HRW, 5 Mar 2024 **[V]**; Jurist, Mar 2025 **[V]**).
  - Guest-readable author histories are a reconnaissance tool for outing or entrapment.
  - Mitigations:
    - unlinkable posts;
    - no author profiles for guests;
    - a country-aware compose note, mirroring the dating path's safety notes;
    - **legal review** of Attune's own exposure as host.
- **Diaspora (UK and EU).** UK and EU users bring Online Safety Act and DSA duties: statement of reasons and complaint handling. Some duties are lighter for small services. **[M; legal check needed]**

---

## 3. Implications for Attune

Each implication is tied to the evidence above. "Opinions after Forums" is summarised in the table after the list.

### Build, change or remove

1. **Make posts unlinkable by default.**
   - **Change:** give each opinion and each comment its own handle, for example `HMAC(user_id || content_id)`.
   - **Remove:** author profile pages and the follower count.
   - **Remove:** following authors. Keep following tags.
   - **Keep:** `is_mine`, mute and own-post management, all server-side.
   - **Why:** it restores the MASTER_SPEC §8.11 promise ("your partner doesn't know it's you"). It matches how people choose anonymity for hard disclosures: throwaways get *more* support (Ammari **[V]**, De Choudhury **[V]**). It removes the jigsaw and stylometry surface (Narayanan **[M]**, Mumsnet **[V]**) and SOUL's "visible status hierarchy".
   - **Trade-off:** muting works per post rather than per author. Keep a server-side "mute the author of this post" action that resolves through the post id. It can stay silent and needs no linkable handle.
   - **Fallback:** if the owner wants followable voices, make linking an explicit per-post opt-in ("Add to my profile"). It must never be the default.
2. **Remove dislike** on posts and comments.
   - **Why:** negative feedback degrades later behaviour and spreads (Cheng 2014 **[V]**, Strong). Dislike also contradicts "without judgment". Hide already covers "not for me".
3. **Replace public like counts with supportive reactions.**
   - Two or three reactions: "I relate", "Sending strength", "This helped".
   - Counts are visible **only to the author**, or not at all, and are **never used for ranking**.
   - **Why:** herding (Muchnik **[M]**); the Instagram result was mixed and led to a choice (**[V]**); one-click feedback adds little well-being (Burke & Kraut **[M]**); SOUL "connection, not comparison".
4. **Re-rank Discover.**
   - **Drop** `(likes − dislikes) + comments×2`. It rewards controversy (Brady **[M]**, Rathje **[M]**) and buries disliked honest posts.
   - **Use** recency, plus a boost for posts with **no reply yet**, plus tag diversity. Keep the same-status boost, but drop it if status labels change (implication 15).
   - **Measure:** the % of posts with a reply within 24 hours.
5. **Remove reposts and quotes**, along with the engagement screen and the live count broadcasts.
   - **Why:** they spread a vulnerable post to more readers (more chances for the partner to see it) and enable dunking and evidence-building (Mastodon's 2025 caution and author controls **[V]**; Tumblr "vortexes" **[M]**). They add nothing to "write without judgment".
6. **Keep comments, made gentle.**
   - Show norms above the comment box (Matias **[M]**).
   - Add a deterministic **reconsider prompt** on harsh words (Katsaros **[V]**).
   - Remove comment likes and dislikes.
   - **Author controls:** turn comments off; "Just listening: no advice, please" (reactions plus warm replies only, shown as a banner); remove any comment on your own post.
   - **Why:** comments help when supportive (Boniel-Nissim **[M]**) and hurt when cruel or co-ruminative (Yik Yak **[V]**, Rose **[V]**).
7. **Add a deterministic pre-post filter.**
   - Block contact information, slurs and explicit content, with a clear reason, on posts, comments, poll options and edits.
   - **Why:** it is required by Apple 1.2 (**[V]**), already promised in FORUM.md and MASTER_SPEC, and absent in code (§2.1, item 1). It also enforces "no contact info / no identifying a person".
   - Needs a Ghanaian-language reviewer for the slur list.
8. **Add an author-only crisis path.**
   - **Detection:** deterministic and versioned, never an LLM. Run it on the author's own post. **Never block posting.**
   - **Response:** after posting, show the author privately: "Thank you for writing this. If you're not safe or not okay, support is here", with a link to the existing Safety Resources screen (SAFETY §6).
   - **Always available:** a permanent "Need support now?" link in compose, regardless of what anyone types.
   - **Reports:** add a "Someone may be at risk" reason that goes to the **human** priority queue. Do not auto-message the author (Reddit-Cares weaponisation **[Anecdote]**).
   - **Governance:** needs the separate, clinically reviewed spec that SAFETY §1.4 demands.
   - **Why:** "write without judgment" will attract abuse and self-harm disclosures. Today there is no route at all.
9. **Add a private route and slower posting.**
   - **"Keep this private (save to my journal)"** in compose.
   - **Drafts that persist.**
   - **"Post later"** with a short "sending…" undo window, offered by default between 23:00 and 05:00 local time.
   - **Why:**
     - expressive-writing benefits need no audience (§2.2);
     - delay nudges reduce regret (Wang 2011, 2014 **[M]**);
     - a randomised delay also breaks *timing correlation* by a partner who knows when you were on your phone (design reasoning).
   - **Also:** the missing "Post this?" dialog should be replaced by this undo window, and the manual corrected.
10. **Make compose prompts self-focused.**
    - Placeholder: "What's on your mind?" becomes "What happened, and how did it feel for you?"
    - Hint: "Write about your side. Leave out names, places and details someone could recognise."
    - Plus the weekly "Attune asks…" prompt.
    - **Why:** meaning-making predicts benefit (Pennebaker 1997 **[M]**); rumination harms (Sbarra **[V]**); SOUL's never-attribute rule binds Attune's prompts.
11. **Make the privacy copy honest.**
    - Fix `opinions_docs.dart:166-168` and the compose card "Others see only your handle".
    - New wording: "Others see your status and a rough time. Your partner or people you know could still recognise your story. Leave out names and details."
    - **Why:** the current claim is false given linkable history (§2.1, items 3–4). Overclaiming safety breaks SOUL §8 ("Never: safety features positioned as guarantees of safety").
12. **Remove text from push previews and coarsen timestamps.**
    - Push body: "Someone replied to your post". Respect the engine's quiet hours (06 F6).
    - Public timestamps: "today" or "this week" rather than "2h ago".
    - **Why:** lock-screen exposure on checked phones (Freed **[M]**); timing correlation.
13. **Moderation for a small team.**
    - Lower auto-hide to 3 distinct reporters (2 for identifying a person or someone at risk).
    - Add self-harm as a report reason.
    - Build a minimal review queue.
    - Removal notices name the rule, and offer an appeal with human re-review (Santa Clara 2.0 **[V]**).
    - Publish a contact email (Apple 1.2 **[V]**).
    - Soften the "within 24 hours" copy unless it is staffed.
14. **Guests can read, not profile.**
    - Guests can read Discover, threads and tags.
    - Guests cannot see author histories (moot if implication 1 lands), react, vote or see poll results.
    - Add a one-time self-declared **18+** gate before reading; Attune is 18+ and guests have given no date of birth.
    - Keep quick exit on every Opinions screen and sheet.
    - **Why:** guest histories are a reconnaissance and outing tool (§2.10); Apple 1.2 age expectations.
15. **Update status labels for the new paths.**
    - Map to "In a relationship / Single / Not saying".
    - Retire "Open" (ambiguous) and "Figuring it out", or keep the latter if the owner wants it.
    - Add "Don't show my status on this post".
    - **Why:** the label is a quasi-identifier and today is the only identity signal (THESIS §3.6).
16. **Add tag mute** (06 B13) and West African tags: family and in-laws, money, faith. Keep tag follows private.
17. **Delete Forums cleanly.** Follow the coupling list in §2.9. Keep `forum_reports`, `post_polls`, `tags` and `opinion_tags`.
18. **Measure (counts only):**
    - % of posts with a supportive reply or reaction within 24 hours (target: rising);
    - reports per 100 posts;
    - removals and appeal overturns;
    - self-deletes within 24 hours;
    - private-journal saves against posts;
    - crisis-resource displays (count only).

### "Opinions after Forums": the feature-by-feature verdict

| Feature today | Verdict | Change | Evidence |
|---|---|---|---|
| Text only, 5,000 characters | **Keep** | — | THESIS §3.6; MASTER §8.11 (reduces abuse vectors) |
| HMAC handle, `user_id` never exposed | **Keep the plumbing; change the scope** | A handle per post and per comment, not per person | §2.7; Ammari; Narayanan; Mumsnet |
| Anonymous profile (all posts, reposts, follower count) | **Remove** (or make it an opt-in per post) | — | SOUL §9 (no status hierarchy); jigsaw ID; guest reconnaissance |
| Follow author / Following feed | **Remove author follow; keep tag follow** | The Following feed becomes "Topics I follow" | As above |
| Like (public count) | **Soften** | Supportive reactions; counts for the author only; no ranking | Muchnik; Burke & Kraut; Instagram 2021 |
| Dislike (posts and comments) | **Remove** | Hide stays as the private "not for me" | Cheng 2014; "without judgment" |
| Comments | **Keep, soften** | Norms shown; reconsider prompt; author can turn off or remove comments; "just listening" mode; no comment likes or dislikes | Boniel-Nissim; Katsaros; Matias; Yik Yak |
| Reposts | **Remove** | — | Spreads exposure; no supportive function |
| Quotes and the engagement screen | **Remove** | — | Mastodon 2025; dunking and evidence risk |
| Saves (private) | **Keep** | — | Private; no count |
| Polls (results hidden until vote) | **Keep** | They become the successor to Forums debates | MASTER §8.11; no sides |
| Fixed tags (21) | **Keep, extend** | Add tag mute plus family and in-laws, money, faith | 06 B13; §2.10 |
| Hide post / mute author | **Keep** | Mute resolves through the post id once handles are per post | Apple 1.2 (blocking) |
| 15-minute edit, delete any time | **Keep** | — | Author escape hatch |
| Engagement-ranked Discover | **Change** | Recency plus a boost for unanswered posts plus tag diversity | Brady; Rathje; §2.3 |
| Live count broadcasts | **Remove** | Not needed without public counts | — |
| Push previews of comment text | **Change** | Neutral text; quiet hours | Freed; 06 F6 |
| Pre-post filter | **Add** (missing) | Contact information, slurs, explicit content; block with a reason | Apple 1.2; FORUM.md promise |
| Crisis path | **Add** | Author-only, deterministic, never blocks, clinically reviewed | SAFETY §1.2, §1.4 |
| Private journal route, drafts, "Post later" | **Add** | — | §2.2; Wang 2011/2014 |
| Self-focused prompts and "Attune asks" | **Add** | — | Pennebaker 1997; Sbarra; SOUL §8 |
| Moderation: threshold 10, no notice or appeal | **Change** | 3 (or 2) distinct reporters; notice with rule; human appeal; contact email | Santa Clara 2.0; Jhaver; Apple 1.2 |
| Status labels | **Change** | Align with the paths; per-post "hide my status" | §2.1, item 7 |
| Forums tab, topics, debate rooms, insights | **Remove** (owner decision) | Mind the couplings in §2.9 | — |

### Where Opinions sits in navigation

| Who | Where Opinions sits | Default landing | Notes |
|---|---|---|---|
| **Guest** (not signed in) | The first screen | Opinions, Discover (read-only) | 18+ self-declare once; read posts, threads and tags; no author pages, reactions, votes or poll results; a "Sign in to write" call to action; quick exit visible |
| **Just for me** | A top-level peer tab next to the user's own space (Journal, quizzes, Healing) | **Their own space**, with an "Attune asks" card linking into Opinions | Recently separated, ruminating users should not land in other people's relationship pain by default (Sbarra **[V]**). This revises THESIS's "default home for singles": owner question 1. |
| **Single and open to dating** | A top-level peer tab next to Introductions and the dating chat | Introductions | Compose note: "People you match with may read Opinions too." Never link an Opinions post to a dating profile (no shared handle, no "posted by your match"). |
| **In a relationship** | A top-level peer tab next to Chat | Chat (as today) | Compose note: "Your partner may read Opinions too. Posts aren't linked to each other or to you." Never any couple-level signal: no "your partner posted", no shared counts. |

---

## 4. Open questions for the owner

Each has a recommendation.

1. **Should "Just for me" users still land on Opinions by default?** (THESIS calls the commons "the default home for single users".)
   - **Recommendation:** no. Land them on their own space, with Opinions one tap away and an "Attune asks" card. Keep Opinions as the guest landing.
   - Reason: rumination risk after separation (Sbarra), and SOUL's "not a social media platform".
2. **Unlinkable posts by default, with no author profiles and no author following?**
   - **Recommendation:** yes for v1. It is the only way to keep "your partner doesn't know it's you".
   - If followable voices matter, allow a per-post "Add to my profile" opt-in later.
3. **Supportive reactions: counts for the author only, or no counts at all?**
   - **Recommendation:** the author sees a gentle total ("12 people related to this"). Nobody else sees counts. Never rank by them.
4. **Remove reposts and quotes entirely?**
   - **Recommendation:** yes. Their only job is reach, and reach is the risk.
5. **Must the crisis path ship before Opinions is promoted as "write without judgment"?**
   - **Recommendation:** yes.
   - Minimum for launch: a static "Need support now?" link in compose and on every post menu, plus a self-harm report reason routed to the human queue.
   - The deterministic author-only detector follows its own clinical spec (SAFETY §1.4).
6. **Report threshold:** 10 distinct reporters (today), or 3 (2 for identifying a person or someone at risk)?
   - **Recommendation:** 3 and 2, with dedup kept, plus a review queue the owner actually checks daily.
7. **Moderation staffing.** Who reviews reports and appeals, and how fast?
   - **Recommendation:** name a person and a daily review slot.
   - Change "within 24 hours" to "as quickly as we can" until that is staffed.
   - Publish a contact email (Apple 1.2).
8. **Legal review for Ghana before launch.** This covers the LGBTQ+ "promotion" provisions and defamation from posts about identifiable people.
   - **Recommendation:** yes. Add a country-aware compose note on the same model as Dating Mode's safety notes.
9. **Guest scope.**
   - **Recommendation:** read-only Discover, threads and tags behind a one-time 18+ self-declaration. No author histories (moot if question 2 is accepted).
10. **Status labels after the new paths.**
    - **Recommendation:** "In a relationship / Single / Not saying", plus per-post "hide my status". Retire "Open".
11. **New tags.**
    - **Recommendation:** add "family and in-laws", "money" and "faith" after a cultural reviewer signs off. Keep tag-follow lists private.
12. **Should comments be on by default?**
    - **Recommendation:** yes, with three author controls: turn off; "just listening"; remove a comment. Add norms above the box and a reconsider prompt.

---

### Source list (URLs)

**Verified this session [V]**

*Expressive writing and rumination*
- Frattaroli 2006: <https://pubmed.ncbi.nlm.nih.gov/17073523/>
- Smyth 1998: <https://pubmed.ncbi.nlm.nih.gov/9489272/>
- Mogk et al. 2006: <https://www.egms.de/static/en/journals/psm/2006-3/psm000026.shtml>
- Rude et al. 2023: <https://frontiersin.org/journals/psychology/articles/10.3389/fpsyg.2023.1192595/full>
- Sbarra et al. 2013: <https://www.psychologicalscience.org/news/releases/post-divorce-journaling-may-hinder-healing-for-some.html>
- Lewandowski 2009 (APA summary): <https://www.apa.org/topics/marriage/relationship-breakups>
- Rose 2002: <https://pubmed.ncbi.nlm.nih.gov/12487497/>
- Van Zalk & Tillfors 2017: <https://capmh.biomedcentral.com/articles/10.1186/s13034-017-0179-y>
- Mackenzie et al.: <https://frontiersin.org/journals/psychiatry/articles/10.3389/fpsyt.2023.1040636/text>

*Anonymity, feedback and peer support*
- Suler 2004: <https://en.wikipedia.org/wiki/Online_disinhibition_effect>
- Rösner & Krämer 2016: <https://doaj.org/article/379d5dc31a744d2c93167086858da93a>
- Santana 2014: <https://campustechnology.com/articles/2014/01/23/u-houston-research-anonymous-commenting-less-civil.aspx>
- De Choudhury & De 2014: <https://ojs.aaai.org/index.php/ICWSM/article/view/14526>
- Ammari et al. 2019: <https://si.umich.edu/about-umsi/news/throwaway-social-profiles-may-have-place-some-platforms-some-topics>
- Cheng et al. 2014: <https://arxiv.org/abs/1405.1429>
- Katsaros et al. 2022: <https://arxiv.org/abs/2112.00773>
- Sharma et al. 2020: <https://arxiv.org/abs/2009.08441>

*Platforms*
- Instagram 2021: <https://about.instagram.com/blog/announcements/giving-people-more-control>
- Mastodon 2025: <https://blog.joinmastodon.org/2025/09/introducing-quote-posts/>
- Yik Yak JMIR 2020: <https://www.jmir.org/2020/5/e17224>
- NYU Yik Yak: <https://engineering.nyu.edu/news/hold-yak-nyu-researchers-discover-clues-identifying-yik-yak-users-college-campuses>
- Yik Yak relaunch: <https://techcrunch.com/2021/08/16/yik-yak-is-back/>
- Yik Yak history: <https://en.wikipedia.org/wiki/Yik_Yak>
- Secret: <https://www.technologyreview.com/2015/04/30/168303/anonymity-app-secret-says-goodbye/>
- Whisper/Guardian: <https://betanews.com/2014/10/16/investigation-finds-anonymous-whisper-app-secretly-tracks-user-location/>
- 7 Cups (Mashable): <https://healthjournalism.org/blog/2024/06/how-a-mashable-senior-reporter-exposed-hidden-dangers-of-online-teen-peer-support-forums/>
- 7 Cups (Mozilla): <https://www.mozillafoundation.org/de/privacynotincluded/7-cups/>
- Mumsnet outing thread: <https://www.mumsnet.com/talk/am_i_being_unreasonable/4108116-AIBU-to-wonder-if-anyone-has-been-outed>
- Mumsnet / Hemming: <https://expressandstar.com/editors-picks/2014/01/02/mp-john-hemming-banned-from-mumsnet-after-revealing-the-identity-of-users>
- Nairaland: <https://en.wikipedia.org/wiki/Nairaland>
- Nairaland outage: <https://techcabal.com/2023/12/21/nairaland-is-back-online-after-brief-cloudfare-blackout/>

*Policy and law*
- Apple App Review Guidelines 1.2: <https://developer.apple.com/app-store/review/guidelines/>
- Santa Clara Principles 2.0: <https://santaclaraprinciples.org/>
- HRW Ghana 2024: <https://www.hrw.org/news/2024/03/05/ghana-president-should-veto-anti-lgbt-bill>
- Jurist 2025: <https://www.jurist.org/news/2025/03/ghana-lawmakers-reintroduce-anti-lgbtq-bill-imposing-harsh-restrictions/>

**From prior knowledge, not re-verified this session [M]** (spot-check before the decision document)

*Expressive writing and venting*
- Pennebaker & Beall 1986, *J Abnorm Psychol* 95(3):274–281
- Pennebaker, Mayne & Francis 1997, *JPSP* 72(4):863–871
- Reinhold et al. 2018, *Clin Psychol Sci Pract* 25(1):e12224
- Guo 2023, *Br J Clin Psychol* (31 RCTs)
- Rimé 2009, *Emotion Review* 1(1):60–85
- Zech & Rimé 2005, *Clin Psychol Psychother* 12(4)
- Bushman 2002, *PSPB* 28(6):724–731
- Martin et al. 2013, *Cyberpsychol Behav Soc Netw* 16(2):119–122
- Boniel-Nissim & Barak 2013, *Psychol Serv* 10(3):333–341

*Feedback, norms and moderation*
- Burke & Kraut 2016, *JCMC* 21(4):265–281
- Muchnik et al. 2013, *Science* 341:647–651
- Sherman et al. 2016, *Psychol Sci* 27(7)
- Brady et al. 2017, *PNAS* 114(28)
- Rathje et al. 2021, *PNAS* 118(26)
- Matias 2019, *PNAS* 116(20):9785–9789
- Jhaver et al. 2019, *PACM HCI* 3(CSCW) 10.1145/3359252
- Chandrasekharan et al. 2017, *PACM HCI* 1(CSCW)
- Chancellor et al. 2016, CSCW
- Morris et al. 2015, *JMIR* 17(3):e72

*Disclosure, regret and warnings*
- Andalibi et al. 2016, CHI
- Bridgland et al. 2023, *Clin Psychol Sci* 10.1177/21677026231186625
- Wang et al. 2011, SOUPS
- Wang et al. 2014, CHI
- Das & Kramer 2013, ICWSM

*Identification and surveillance*
- Sweeney 2000
- Narayanan et al. 2012, IEEE S&P
- Freed et al. 2018, CHI

*Other*
- Haimson et al. 2021, *Feminist Media Studies*
- Cavalcante 2019, *J Homosexuality* 66(12)
- Sprecher & Felmlee 1992, *J Marriage Fam*
- FTC v. NGL Labs (July 2024)
- EU DSA Art. 17/19/20
- UK Online Safety Act

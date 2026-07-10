# ATTUNE — THE THESIS

**Version:** 1.1 (evidence corrections from the July 2026 research pass — Between/Paired precedent framing softened to match public evidence; dating-mode outcome language tightened; see `ATTUNE_RISK_SOLUTIONS.md` v2.0 Appendix A for the full corrections ledger)
**Written:** July 2026
**Status:** Living document — update as the product learns
**What this is:** The non-technical companion to the architecture specs. The specs say *how*; this document says *why*, *for whom*, *against what*, and *what could go wrong*. It is written for the founder, future collaborators, advisors, reviewers, and investors. Nothing in it overrides the governing documents (`ATTUNE_SOUL.md`, `ATTUNE_CLINICAL.md`, `ATTUNE_MASTER_SPEC.md`); it synthesizes them.

**Reading order:** this document first, then `ATTUNE_RISK_SOLUTIONS.md` (the mechanism-level treatment of Section 9's ranked risks), then `attune/ATTUNE_MASTER_SPEC.md` for implementation. The master spec's own opening now points back here — if you arrived at this document from there, you're on the right track.

---

## 1. The Thesis in One Page

Most people repeat the same relationship mistakes for years — not because they are broken, but because they are flying blind. Nobody gets objective data about their own relationship. Memory is biased toward the worst moments. Advice is generic. Therapy is expensive, scarce, and — in much of the world, including Ghana — stigmatized. So people cycle: same fights, same silences, same endings, different partners.

**Attune's bet is that the raw material for relationship self-knowledge already exists — it's the couple's own conversation — and that modern AI finally makes it possible to turn that conversation into honest, specific, non-judgmental insight at consumer prices.**

The product is deceptively simple: a beautiful, private chat built for exactly two people in love. One chat per couple. When the relationship ends, the chat seals forever. Inside that chat, an AI reads quietly — never interrupting, never judging, never taking sides — and over weeks it surfaces what no friend, pastor, or quiz could: *your own patterns, from your own words.* Around that core sit tools (a conflict translator, connection games, self-knowledge quizzes), a weekly relationship pulse, a monthly sourced summary, and — invisibly, until the moment it matters — a safety net for people whose relationship has become dangerous.

And because relationships end, Attune doesn't end with them. A private healing journey helps a person make meaning of the ending. And when they are genuinely ready — gated by time and reflection, never by loneliness — a dating mode introduces them to people matched on *who they actually are in relationships*, not on photos. No swiping. No games. No one ever learns they were passed over.

Three things make this defensible:

1. **The chat is the data source.** Every competitor is a quiz app or a prompt app; none has the substrate. And nobody can copy the dating product without first building the couples product.
2. **Ethics is the architecture, not the marketing.** The rules that make Attune trustworthy — no couple scorecards, no partner-blaming, safety alerts to the at-risk person only, the translator invisible to the recipient — are enforced at the database level. They cannot be quietly walked back by a growth team, because they are structurally impossible to violate.
3. **Honesty is the brand.** Attune tells users what it doesn't know. It grades its own psychological instruments in public. It refuses the entire dark-pattern playbook. In a category defined by manipulation, the anti-product is the differentiator.

The one-sentence soul, from the governing documents: *"Attune is designed to be worth returning to — not designed to make leaving feel painful."*

---

## 2. The Problem

### 2.1 Pattern blindness

Couples don't fail from a lack of love; they fail from a lack of *sight*. The pursue-withdraw cycle, the fight that is always secretly about fairness, the repair attempt that never lands — these patterns are invisible from inside. Human memory makes it worse: we remember the peak of the fight and the sting of the ending, not the four times we resolved the same argument cleanly. People leave relationships with pain but without transferable learning, then reproduce the same dynamic with someone new.

### 2.2 The advice industry is generic; the data is personal

Books, podcasts, quizzes, and couple apps all sell the same thing: population-level generalizations. "Men withdraw; women pursue." "Speak their love language." Even when the frameworks are sound, the delivery is horoscope-shaped — nothing in it is *about you*. The only entity that has ever seen a couple's actual communication is the couple themselves, and they are the least objective observers alive.

### 2.3 Help is scarce exactly where the need is largest

In Ghana and most of West Africa, couples therapy is functionally unavailable to ordinary people: few practitioners, high cost, and a documented cultural stigma around anything framed as mental-health treatment. The clinical literature itself is part of the problem — less than 1% of psychology research samples African populations. The result is a continent-sized gap between need and supply. An app is not therapy and must never claim to be; but where the alternative is *nothing*, honest, culturally reviewed pattern insight is a meaningful intervention.

### 2.4 The dating market optimizes for the wrong outcome

Swipe apps monetize engagement, not outcomes: the longer you stay single and swiping, the better their business does. Their mechanics (variable rewards, match counts, admirer queues) are imported casino design. People increasingly know this and hate it. Nobody has built the alternative — matching on demonstrated relational behavior — because nobody else has the behavioral data. Attune will. One honesty note the research demands: the strongest published science (Finkel et al. 2012) finds *no* evidence that any matching algorithm, however sophisticated, predicts relationship outcomes — so Attune's dating differentiation is a more honest and richer *experience* (real signals, modest claims, better first conversations), never a promised outcome. The dating spec already enforces exactly this humility in its copy rules; the strategy claims no more than the spec does.

### 2.5 And when a relationship is dangerous, silence is the default

Domestic violence support in the region is under-resourced, and the moments when an at-risk partner most needs resources are precisely the moments they can't search for them openly. A private chat app with a quiet, deniable safety layer can reach someone at the exact moment a controlling message arrives — something no hotline poster can do.

---

## 3. What Attune Is

### 3.1 The lovers' chat — the heart

Attune is not trying to replace WhatsApp for everyone. It is **the chat for this one relationship** — a dedicated space that exists because the relationship exists. One chat per couple, ever. When the relationship ends, the chat goes read-only (both people can revisit the history), and the moment either person moves on, it seals permanently. Every love gets one chat, and when it ends, it becomes an artifact — not a weapon, not a haunting, not a data source for anyone else.

This positioning matters. Asking couples to *replace* their messenger is one of the hardest behavior changes in software. Asking them to give their relationship *a home* has real precedent — Between built exactly this dedicated-couple-space model to 10M+ downloads across Asia. The honest version of that precedent: Between proved the *demand* (millions of couples wanted a dedicated space), but not the standalone *business* — its parent company pivoted away in 2018 and the app was sold twice more as an asset, with no public evidence it ever monetized strongly. The demand is proven; the durable business model is Attune's to prove, and the intelligence layer — which Between never had — is the bet on how. Attune's difference is everything that lives inside the space.

### 3.2 The intelligence layer — the reason it exists

While the couple simply lives their relationship in chat, the AI builds understanding in layers: every message is read for tone and communication signals; conversations are grouped into sessions and analyzed for escalation, repair, and resolution; long-term patterns accumulate in a memory that spans months. From this the couple receives:

- **Pulse** — a weekly relationship-health snapshot across five dimensions (communication, connection, conflict health, alignment, emotional safety), always shown with an honest confidence indicator. No streaks, no guilt mechanics, no penalty for a missed week — ever.
- **Insights** — specific, sourced observations. Crucially, they are *asymmetric by design*: the pattern is shared ("a reach-and-distance cycle appears in your conflicts"), but each person's role in it is shown only to that person. "Your partner withdraws" is a sentence the system is architecturally incapable of producing. The pattern is shared; the role is private. This single rule is what keeps insight from becoming ammunition.
- **The monthly Verdict** — a sourced summary of what the data shows: what's working, what deserves attention, one thing to try. Every claim cites its evidence. It never judges the relationship, never says "healthy" or "unhealthy," and never, under any circumstance, tells anyone whether to stay or leave. The design brief in the soul document: it should read like *"a wise, attentive friend sharing what they noticed"* — never like a judge.

### 3.3 The toolkit — how the hard conversations arrive

- **The Conflict Translator ("Help me say this")** — mid-argument, a user can privately ask the AI to help them say the hard thing without the blame. They see their original and the rewrite side by side, with equal weight, and choose freely. The recipient never knows — no label, no indicator, permanently. It is a private thinking tool, not a persuasion layer. Strategically, it is also the feature most likely to pull real conflict into Attune, because it is only useful mid-conflict and exists nowhere else.
- **Games** — the launch canon is three: *This or That* (playful preference matching that refuses to let couples "lose"), *Truth or Dare* (with a silent, judgment-free skip that the partner never learns about), and *36 Questions* (the Aron intimacy protocol in three mutually-consented chapters, with AI reflections that only appear when there's enough evidence to say something true). Games are the fun that doubles as data — and the answers stay hidden until both have committed, defeating people-pleasing.
- **Quizzes** — four self-knowledge instruments (attachment, love languages, communication style, conflict style), each honestly graded by its own evidence quality. Attachment is the anchor (a real, validated instrument); love languages is explicitly the weakest tier and is *banned* from ever being used to score compatibility — because the peer-reviewed evidence says the matching idea doesn't hold. Attune is likely the only relationship app that publicly grades its own psychometrics.

### 3.4 The guardian — the feature that must never fail

A hard-coded, non-AI safety system watches for explicit threats and coercive-control language. When it fires, *only the at-risk person* is quietly notified — a deliberately generic push ("Some resources are available"), never naming safety or a partner on a lock screen. The sender never knows. The message is never blocked. Nothing is ever escalated to authorities automatically. A triple-tap quick-exit hides the app behind a neutral screen for someone whose phone may be watched. Crisis resources are localized (Ghana's DOVVSU line verified and corrected during spec review), never paywalled, and reviewed quarterly. The system is deterministic *by principle*: an AI model can hallucinate, drift, or go down; the safety net cannot be any of those things. And the specs are unusually candid that keyword matching cannot catch everything — the product must never claim comprehensive detection.

### 3.5 The lifecycle — because relationships end

- **Personal mode** — for singles, waiting partners, and anyone between relationships: private reflection journaling with AI analysis, all four quizzes, personal patterns. Explicitly *not* a consolation prize — it is the product for a huge population and the pipeline for everything else.
- **Healing mode** — a private, self-paced post-breakup journey in five stages: reflection, an evidence-grounded look back at the relationship, pattern awareness, a personal pattern portrait, and a readiness check-in. It never blames, never diagnoses the ex, never advises reconciliation or leaving. The former partner never learns any of it exists.
- **Dating mode** — the culmination. Eligibility is earned (healing completed, readiness score, a real waiting period), enrollment is a separate explicit choice, and matching uses only a person's *own* data, never an ex-partner's. Introductions are small, curated, and psychology-first: the alignment explanation comes before the photo. Interest is double-blind — no one ever learns of one-sided interest or rejection. There is no swiping, no browsing, no match counts, no urgency. The words the spec bans tell the story: no "you are 84% compatible," no "this pairing will last." Just modest, sourced common ground, and a guided first date.

### 3.6 The commons — Opinions and Forums

An anonymous community surface (the default home for single users): short-form relationship opinions and structured FOR/AGAINST debate rooms whose topics are elected by community vote rather than by an editor. Anonymity is real — no handles, no avatars; the only identity signal is relationship status. It is deliberately firewalled from the private product: forum personas can never be linked to real profiles, and forum posts are never fed to the AI pipeline. Its jobs: give singles a reason to be in the app, let people learn from strangers' honesty, and create a content funnel that markets the product without touching anyone's private data.

### 3.7 What Attune refuses to be

The soul document is explicit, and it reads as a list of the industry's sins: no streaks or badges or leaderboards; no engagement-optimized notifications; no couple scorecards; no coin pricing or cancellation friction; no degraded free tier; no swipe mechanics; no "they liked you" queues; no A/B testing on safety or verdict copy; no ads; no selling or training on user data; no telling anyone what to decide about their own relationship. Two named anti-products anchor the philosophy — the manipulative coin-economy of short-drama apps and the engagement casino of swipe dating — and Attune defines itself as the visible opposite.

---

## 4. Why This Can Win

**The substrate moat.** Quiz apps know what you *say* about yourself. Attune knows how you actually communicate, fight, repair, and reconnect — because the relationship happens inside it. This data cannot be bought, scraped, or shortcut. A competitor wanting Attune's dating product must first build and win with Attune's couples product. That is a multi-year moat made of trust, not code.

**Compounding value, ethically.** Most apps decay — novelty wears off. Attune appreciates: every week of use makes the insight more specific and the product harder to leave *for the right reason* (it genuinely knows you), never through lock-in. The soul document even corrected itself on this point during drafting — reframing the moat from "non-exportable" to "non-transferable," removing any pride in trapping users. Your data is yours; your understanding just can't be faked elsewhere.

**Ethics enforced below the feature level.** Every promise above is backed by a permanent constraint enforced in the database schema and reviewed against a checklist before every merge. This isn't compliance theater; it's the product's deepest bet: *in the most intimate software category that exists, trust is the only durable brand,* and trust survives only if the ethical rules cannot be violated by a future feature, a growth experiment, or a tired founder at 2am.

**Honesty as positioning.** Attune shows confidence levels on its own scores. It tells a new couple "we can't see your patterns yet." It publicly refuses to use a beloved-but-unsupported framework (love languages) for matching. In a category full of confident nonsense, calibrated honesty is both the ethical and the commercial play: it converts skeptics, and skeptics are exactly who this product needs to convert.

**Category precedent, unclaimed intersection.** Dedicated couple spaces have demonstrated demand at scale (Between, 10M+ downloads). Paid couples apps have demonstrated real-but-modest traction and successful exits (Paired at meaningful monthly revenue; Lasting acquired by Talkspace) — precedent for traction, not yet for large standalone success; the category's cautionary tale is Relish, which couldn't sustain its cost structure and decayed into a quiz app. AI-relationship spend is exploding in the adjacent companion category. Nobody sits at the intersection: *the couple's own space, with real intelligence, with clinical humility, with a lifecycle.* The intersection is empty because it is hard — technically, ethically, and emotionally. The specs are the evidence that the hard part has been taken seriously; the beta is the test of whether the intersection pays.

---

## 5. Why Now, and Why Ghana First

**Why now:** Two years ago, per-message AI understanding at consumer prices was impossible; today frontier-model quality at commodity cost makes a silent reading layer economically plausible, and costs continue to fall in Attune's favor. Simultaneously, dating-app fatigue has gone mainstream — the cultural moment is actively hostile to swipe mechanics and hungry for the alternative.

**Why Ghana first:** Not as a compromise — as a strategy.

- **The need is sharpest.** Counseling scarcity plus stigma means the realistic alternative for most couples is nothing.
- **The market is mobile-first and chat-native.** Communication already lives in messaging apps; the behavior Attune needs is universal there.
- **Community distribution is real.** Ghanaian relationship life runs through churches, families, and tight social networks — word-of-mouth channels that reward a trustworthy product and punish a manipulative one. Attune's ethics are a *distribution advantage* here.
- **A defensible beachhead.** Global players ignore West Africa; local credibility, local crisis resources, local cultural review, and local language sensitivity create a home-field advantage that scales outward (Nigeria and anglophone West Africa next, then the diaspora, who send remittances and app recommendations home in both directions).
- **The honesty caveat, stated plainly:** the psychological instruments Attune uses were built and validated on Western populations. The clinical document confronts this — Africa is under 1% of the research base — and the product carries real mitigations: hedged language tiers, Ghanaian cultural review as a blocking release gate on the risky features, a proposed "communal obligation" needs category, and Ubuntu explicitly held up as a counter-framework to Western attachment individualism. Launching without a Ghana-specific validation study is an acknowledged, disclosed risk. Turning that gap into a contribution is part of the long game (Section 10).

---

## 6. The Problems We Will Face — and the Plans

This section is deliberately unsparing. Every product this ambitious has a list like this; most teams keep it in their heads. Ours is written down.

### 6.1 Adoption: the second-messenger ask

**The problem.** Even as a "lovers' space," Attune asks couples to move *some* daily communication out of WhatsApp. Habit is the strongest force in consumer software.
**The plan.** Position as the relationship's home, not a messenger replacement (this is now locked in the master spec). Lean on the emotional resonance of the sealed chat — "every love gets one chat" is a story people retell. Make day one magical (the compatibility preview lands within minutes of both partners joining). Measure the switch honestly (Section 9).

### 6.2 Ceremonial drift: getting the sweet nothings but not the fights

**The problem.** Dedicated couple apps historically become the *ritual* channel — good-morning texts and anniversaries — while the load-bearing arguments stay in the general messenger. For Attune this is existential: the intelligence layer feeds on exactly the conversations least likely to migrate. A couple can be daily-active and still starve the product of everything it needs to say something true.
**The plan.** This risk is now named in the master spec with three countermeasures: the Conflict Translator as the pull (the one feature only useful mid-conflict, existing only here); honest data-confidence displays as the nudge ("we can't see your patterns yet" is an invitation, not an apology); and — most importantly — **conflict capture is a launch gate**: the app does not scale until a meaningful share of beta couples demonstrably have real disagreements inside it. Activity metrics alone are forbidden from masquerading as product-market fit.

A fourth lever exists but is deliberately narrow: **historical chat import** (a couple may, if both independently consent, bring a prior WhatsApp conversation history into Attune — `CHAT_SYSTEM_SPEC.md` Section 11). This can shorten the cold start dramatically for couples with months of existing history, but it is not a growth hack — it is gated behind the same dual-consent architecture as everything else, because a single partner uploading the *other* partner's past words without consent would recreate exactly the surveillance-weapon failure mode the permanent constraints exist to prevent. Historical messages run through the same Safety and analysis pipeline as new ones, and evidence drawn from imported history carries a deliberately lower confidence tier than native evidence. Treat it as a slow-burn option for engaged couples, not a day-one growth lever.

### 6.3 The trust paradox: an AI that reads your most private words

**The problem.** Attune's value requires server-side reading of messages — end-to-end encryption is architecturally impossible for this product, and the couples who most need pattern insight are often the most privacy-anxious. One breach, one scandal, one dark-pattern headline, and the brand is unrecoverable.
**The plan.** Radical disclosure over quiet fine print: users are told plainly at signup that the intelligence requires reading, what is stored (derived scores, not quotable logs), what never happens (no ads, no training on their data, no selling, no combined couple reports), and what they control (deletion, export). Message content is banned from logs and analytics at the spec level. The soul document is, in effect, a public trust contract — publishing its commitments outright is a marketing asset most companies could never risk. And the deepest answer is architectural: the most damaging failures (partner data leakage, couple scorecards) are structurally impossible, not just policy-forbidden.

### 6.4 Dyadic friction: two people must say yes

**The problem.** Every couples product suffers double onboarding friction; the motivated partner joins and the reluctant one stalls. Hard gates here churn the most motivated users.
**The plan.** Already designed in depth: a 48-hour solo-reflection fallback (the waiting partner starts building their own value immediately), exactly one gentle nudge to the reluctant partner, and a dignified day-7 pivot (keep waiting / switch to Personal mode / invite someone else). Personal mode is a real product, not a waiting room — and it may prove to be the primary wedge, with couples mode as the upgrade.

### 6.5 Cultural miscalibration: the WEIRD problem in production

**The problem.** If the AI reads high-context, indirect Ghanaian communication through a Western lens — scoring respectful silence as stonewalling, or direct-communication coaching as disrespect — users won't feel seen; they'll feel *misjudged*. In this category, feeling misjudged is fatal churn.
**The plan.** Layered: framework-confidence tiers force hedged language wherever evidence is thin (contempt detection and stonewalling are explicitly flagged as culturally risky); Ghanaian cultural review is a *blocking* release gate on every psychometric and matching feature; referral copy avoids therapy framing per documented stigma; a communal-obligation needs category is under clinical consideration; and post-launch, dismissal signals ("this doesn't feel right" exists as a first-class button in healing mode) become the calibration dataset. The residual gap is disclosed, not hidden.

### 6.6 Unit economics: the AI bill

**The problem.** Per-message analysis for every couple, forever, is the single largest variable cost, and monetization is deliberately still open. A free tier that must be "genuinely valuable" (soul rule) plus real AI costs is a squeeze.
**The plan.** Levers exist and are sequenced: launch measures true cost per active couple before optimizing (a locked decision — "you can't optimize what you haven't measured"); then model-tiering (small cheap models for the per-message layer, frontier models only for the monthly verdict and reflections), batching, caching, and a schema-level `analysis_skipped` hook for sampling strategies — all without touching product promises. On revenue: a single couples subscription (one payment covers both partners) is the natural shape; premium buys *depth* (richer verdicts, full pattern history, more games), never basics, never safety. Pricing in real currency, cancellable without friction — the ethics constrain the how, not the whether.

### 6.7 Clinical and legal exposure

**The problem.** A product that interprets psychology, detects abuse signals, and introduces singles carries liability across three domains at once — and its data is discoverable in divorce proceedings.
**The plan.** Already among the most developed parts of the spec: licensed clinical advisor sign-off gates every interpretive feature; a DV-experienced lawyer (not a generic startup lawyer) reviews the safety system and terms; "not a crisis service" and "best-effort detection" stated repeatedly; discoverability disclosed at signup; safety events retained in anonymized form for legal protection. The remaining exposure is operational discipline — the gates only protect if they're actually honored (see 6.9).

### 6.8 The safety system's honest limits

**The problem.** Keyword matching cannot catch sarcasm, coded language, or slow-burn coercion that never uses a trigger phrase. And the spec itself flags a real gap: sender-authored self-harm statements are excluded (recipient-only routing would send help to the wrong person), with no protocol yet.
**The plan.** Never overclaim (spec-mandated); pattern-based third-tier triggers catch some slow-burn cases; quarterly lexicon review with DV professionals; and a separate, clinically designed self-harm routing protocol as a named future work item rather than a silent omission. The discreet exit and always-free resources don't depend on detection at all — the manual path works even when the automatic one misses.

### 6.9 The solo-founder bottleneck

**The problem.** One person is currently the engineering team, the moderation team, and the gate-keeper of a review process designed for an organization. The two failure modes are opposite: gates rubber-stamped under deadline pressure, or gates so honored the product never ships.
**The plan.** Automate the moderation floor (machine pre-screens, human confirms, published SLAs); batch the external reviews (one clinical engagement covering couples + healing + dating; one cultural reviewer across all packets; one legal engagement for the full stack) and start recruiting reviewers *before* the features need them — the outreach templates already exist; keep kill switches and feature flags on everything AI-generated; and treat the hard gates (safety, privacy, clinical) as truly hard while consciously right-sizing the operational ones (load testing margins, observability polish) to launch scale. Also, honestly: plan for hiring help at the moderation and support layer as an early use of revenue, not a someday luxury.

### 6.10 Local infrastructure realities

**The problem.** The auth review surfaced it plainly: the entire product sits behind SMS OTP, and SMS delivery reliability across Ghanaian carriers is exactly where West African launches break. Data costs and low-end devices shape everything downstream.
**The plan.** Real-device, real-carrier OTP testing as a launch gate; a fallback verification channel evaluated before public launch; performance budgets measured on representative Ghanaian networks and hardware (already written into the chat spec's acceptance criteria); and aggressive payload thrift (image compression, minimal sync) as a permanent discipline rather than an optimization pass.

### 6.11 Process drift: the specs outrunning the code

**The problem.** Attune's spec discipline is its superpower and its overhead. The moment implementation quietly diverges and nobody reconciles, the documents flip from source-of-truth to source-of-confusion. Small drift already exists (the master spec's original five-game list versus the games module's shipped three-game canon).
**The plan.** The update-doc-in-the-same-pass rule is already law; the missing piece is a periodic reconciliation sweep (monthly, tied to the milestone review that the master spec already schedules) that hunts for exactly this kind of drift. Cheap insurance for the asset the whole methodology depends on.

---

## 7. How Attune Scales

### 7.1 The sequence

1. **Beta (now → soft launch):** ~200 waitlisted couples. The beta's real job is to answer one question: *do the hard conversations arrive?* Conflict capture, dyadic onboarding completion, and day-14 messaging share are the gates — not vanity retention.
2. **Ghana public launch:** only after all three launch gates pass. Couples mode and Personal mode together; community surfaces seeded.
3. **Personal + Healing as standalone funnels (the underrated move):** "Process your breakup properly" is a searchable, shareable, *single-player* value proposition with zero dyadic friction — and every healing completion is future dating-pool supply. Marketing healing mode on its own is simultaneously acquisition, mission, and dating-mode infrastructure.
4. **Dating mode, region by region:** enabled only where the eligible pool crosses density thresholds (measured, not guessed). Thin-pool pressure has a pre-committed answer: grow supply, never weaken gates.
5. **Regional expansion:** Nigeria and anglophone West Africa (cultural review per market — the Ghana playbook generalizes as a *process*, not as content), then the diaspora corridors (UK/US Ghanaian and Nigerian communities), which double as hard-currency revenue.

### 7.2 The growth engines (all consent-based, none dark)

- **The anniversary report** — the planned "Spotify Wrapped for your relationship." Specific, warm, sourced, and inherently shareable *as a story* rather than a score. The single most plausible breakout artifact.
- **The day-one compatibility preview** — tweet-length, warm, screenshot-ready. Quality of this one prompt disproportionately drives early word-of-mouth.
- **The "it sees us" moment** — the insight that stops a couple cold and gets shown across the dinner table. Unmanufacturable, slow, and the deepest engine: it converts users into evangelists in their own social graph, which in Ghana's community-dense culture is worth more than any ad budget.
- **The commons as a front door** — anonymous, honest relationship debate is natively shareable content and searchable surface area; browsable without an account by design.
- **Community-institution partnerships** — Ghanaian churches run premarital counseling at scale; counselors and pastors are trusted relationship authorities constantly asked for help they can't scale. A respectful, non-clinical partnership motion ("a tool your couples can use between sessions") turns the strongest local institution into a channel. This must be approached with the same cultural care as everything else — but it is the most Ghana-native distribution idea available.
- **What Attune will never do:** referral bribes, streak-shares, invite-gates, engagement-bait notifications. Growth compounds slower and sturdier.

### 7.3 The money (recommendation, since the spec leaves it open)

One **couples subscription** (single payment covers both partners — pricing the *relationship*, not the individuals), with a genuinely useful free tier; premium unlocks depth: full pattern history, richer verdicts, expanded games, healing extras. Personal-mode subscription as a second, cheaper tier. Later, a B2B2C lane (counselor/church cohort licenses). Never ads, never data sales, never paywalled safety — these are already permanent constraints, and they are also the marketing copy.

### 7.4 What scaling must never change

The permanent constraints travel unchanged into every market, tier, and partnership. Scale pressure will test each of them — thin dating pools will argue for weaker gates, engagement dips will argue for streaks, revenue pressure will argue for a couple report. The pre-commitments now written into the specs exist precisely for those moments. The moat *is* the restraint.

---

## 8. The Dating Work: What We've Fixed, What Could Still Challenge Us

Dating mode is the most scrutinized surface in the entire architecture — governance-first to a degree that is itself a signal (its review packets existed before its UI). The design already resolved the classic sins: no swiping or browsing; double-blind interest (one-sided interest and rejection are unknowable, even through timing behavior); psychology before photos; modest "alignment bands" instead of fake percentages; love languages banned from matching on evidence grounds; an ex's data never used; readiness earned through healing rather than claimed through a checkbox.

### 8.1 Gaps identified and closed (v1.2, July 2026)

- **Gate-erosion pre-commitment.** The thin-pool temptation now has a written answer: growth levers are enumerated, and eligibility gates move only with fresh clinical sign-off. The founder pre-committed against future-founder pressure.
- **The solo-path clock.** A self-reported breakup date could previously have satisfied the eight-week waiting gate on day one. Now solo journeys require a minimum observed journey duration regardless of the reported date — closing the speed-run without punishing honest users.
- **Ex re-registration.** A former partner re-registering under a new number could have been *introduced to their ex* — a stalking vector in DV histories. A privacy-reviewed exclusion mechanism (keyed, non-reversible, deletion-surviving) is now specified, with the residual risk documented rather than silent.
- **Romance scams as a first-class threat.** West Africa hosts real scam operations, and a trust-branded matching app is an attractive hunting ground. Financial-request detection, a dedicated scam report category, and "never send money" education in the first-date guide are now in scope — because one publicized scam through Attune damages the couples product too.
- **Dating chat safety decision made.** Dating chat will get its own safety specification rather than silently inheriting the couples system — the threat models (stranger harassment and grooming vs. intimate-partner coercion) barely overlap.

### 8.2 What could still challenge us

- **Pool density — the honest number-one.** The eligibility funnel is long by design; from thousands of users it yields dozens of matchable people per city and preference segment. The mitigations are sequencing (healing-mode acquisition as supply-building, regional enablement by measured density) and patience. If dating disappoints early, it will be because of this, not the algorithm.
- **Age verification.** Adults-only enforcement beyond self-attestation is an unresolved, expensive, non-optional decision (a minor on a dating product is existential legal risk). Vendor selection and cost-per-verification must be settled before the pilot, not before scale.
- **Moderation is headcount.** Photo/bio review before display, report triage, scam response — these are human operations with SLAs, and moderation latency is activation latency. The automation-plus-human plan (6.9) is necessary but must be resourced.
- **The calibration chicken-and-egg.** Alignment weights require clinical sign-off, but no outcome data exists to tune them. Posture: treat v1 weights as clinically plausible priors, keep the presentation humble (bands, not scores), and let mutual-interest and conversation-start rates calibrate empirically. The product's promise is *better first conversations*, never predicted love — the copy rules enforce exactly this.
- **The communal-context question.** The cultural review packet itself asks whether an individual-only values model fits a culture where family weighs heavily in partner choice. Deferred to a future reviewed layer — the right call, but it means v1 matching is knowingly incomplete for its own market.
- **Emotional adjacency.** People will be dating inside the app that holds the sealed chat of the relationship they're healing from. The architecture separates these worlds completely; the *experience* must too — tone, navigation, and notification discipline around anyone in healing mode deserve specific design attention.

---

## 9. What Could Kill It — Ranked, with Tripwires

1. **Ceremonial usage.** The product works but the fights never arrive; the AI has nothing true to say; churn follows the first shallow verdict. *Tripwire:* conflict-capture rate in beta (now a launch gate). *Response:* translator prominence, expectations reset, and if unfixable — reposition around the surfaces that don't need conflict (games, quizzes, healing).
2. **Dyadic funnel collapse.** Motivated halves join; partners don't. *Tripwire:* invite-acceptance and both-onboarded rates. *Response:* make Personal mode the primary product and couples linking the upgrade — the architecture already supports the inversion.
3. **Unit-economics squeeze.** Cost per active couple exceeds willingness to pay. *Tripwires:* measured AI cost per couple vs. subscription price sensitivity in beta. *Response:* model-tiering and sampling levers first; pricing second; never product-promise erosion.
4. **Cultural misread at scale.** Insights feel foreign; the market concludes "this app isn't for us." *Tripwires:* insight-dismissal rates, "doesn't feel right" signals, qualitative beta interviews. *Response:* the hedging machinery, cultural review gates, and rapid lexicon/prompt iteration under the existing versioned-prompt discipline.
5. **A trust catastrophe.** A breach, a partner-data leak, a safety failure with a news cycle. Likelihood is designed down (structural impossibilities, audits, pen-test gates); severity is total. *Response readiness:* incident process, honest disclosure posture, and the fact that the most damaging leaks are architecturally prevented rather than policy-prevented.
6. **Founder capacity.** Gate backlog, moderation overload, burnout — the quiet killer of solo ventures with organizational-grade ambitions. *Tripwires:* gate-completion velocity, moderation SLA breaches, and the honest state of the founder. *Response:* batch external reviews, automate the floor, hire moderation help early, and protect the spec discipline that lets AI collaborators carry more of the load safely.

**A full mechanism-level treatment of all six risks — concrete solutions, falsifiable tests, and pre-committed fallbacks for each — lives in `ATTUNE_RISK_SOLUTIONS.md`.** That companion document also surfaces a cross-cutting pattern worth stating here: five of the six risks trace back to just two root causes — friction and value being misaligned in time (Risks 1–3), and one-time reviews decaying silently instead of being continuously re-verified (Risks 4–6). The single highest-leverage fix across the whole list is a small number of cheap, always-on verification loops (a dismissal-queue calibration router, production RLS canary tests, a dated gate-status dashboard) that turn good decisions made once into guarantees that stay true.

---

## 10. The Long View

If the near-term product succeeds, Attune's endgame is bigger than an app:

**A lifelong relationship companion.** People don't have one relationship; they have a relational life. Attune's lifecycle design — together, apart, healing, beginning again — means the product's horizon is decades, and its value compounds across relationships, not just within one. Nobody has ever built software with that shape, because nobody has ever earned the right to it. The right is earned one honest insight at a time.

**The first large-scale African relationship dataset — as a contribution, not an extraction.** The clinical document's sharpest complaint is that the science Attune must rely on barely sampled the continent it launches on. At scale, ethically consented and properly partnered with researchers, Attune could help *fix the gap it currently suffers from* — cross-cultural validation of the field's core frameworks, from Ghanaian data, on Ghanaian terms. That is a legacy-grade contribution and, incidentally, an unassailable moat: the competitor would need not just the product but the years of consented trust.

**Proof that the anti-product wins.** Every permanent constraint in these specs is a bet that the dark-pattern era of intimate software is ending — that in the one category where people can least afford to be manipulated, the company that refuses to manipulate takes the market. If Attune works, it won't just be a successful app. It will be the existence proof.

The soul document says it in one line, and it belongs at the end of this one too:

> *"Attune is designed to be worth returning to — not designed to make leaving feel painful."*

---

## Appendix A — Sources

This thesis synthesizes, and defers to, the following documents (all under `lib/architecture/`): `attune/ATTUNE_MASTER_SPEC.md` (v2.19), `attune/ATTUNE_SOUL.md`, `attune/ATTUNE_CLINICAL.md`, `attune/ATTUNE_PRINCIPLES_CHECKLIST.md`, `algorithms/algorithm_quality_review_checklist.md`, `CHAT_SYSTEM_SPEC.md` (v1.3), `SAFETY_SYSTEM_SPEC.md`, `CONFLICT_TRANSLATOR.md`, `VERDICT_SYSTEM_SPEC.md`, `PULSE.md`, `AUTH_ONBOARDING_ENGINE.md`, `NOTIFICATION_ENGINE.md`, `HEALING_MODE_SPEC.md` (v1.2), `DATING_MODE_SPEC.md` (v1.2) and its four review/gates companions, `GAMES.md`, `36_QUESTIONS.md`, `THIS_OR_THAT.md`, `TRUTH_OR_DARE.md`, the four quiz specifications, `FORUM.md`, and `COMMUNITY_QUESTIONS.md`.

## Appendix B — Known Document Drift (for the next reconciliation pass)

- Master spec §8.4 describes an original five-game canon (36 Questions, Mirror, Sliding Scale, Scenario, Love Map); the games module's shipped v1 canon is three (This or That, Truth or Dare, 36 Questions) with the others deferred. The master should be reconciled to match.
- The attachment quiz spec (v1.0) retains raw quiz answers server-side "for audit"; the communication and conflict quiz specs (v1.1) explicitly reversed this to aggregate-only storage. The attachment spec should adopt the later, stricter standard.
- Pulse spec Section 10 carries unresolved `[OPEN]/[NEEDS DECISION]` items (score sharing semantics, partner check-in visibility, recompute limits) that predate decisions made elsewhere; worth a sweep.

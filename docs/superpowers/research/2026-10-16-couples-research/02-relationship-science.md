# Relationship Science for Attune: An Evidence-Graded Review

**What builds healthy, growing romantic bonds, how couples handle conflict best (in-person and long-distance), and what a relationship app can ethically operationalize**

Prepared: 2026-10-16 · Scope: peer-reviewed research, meta-analyses, RCTs, clinical manuals, therapist resources, reputable summaries · Audience: Attune product, design, AI-pipeline and safety owners

---

## 0. How to read this document

### 0.1 Evidence grades (used throughout)

| Tag | Meaning |
|---|---|
| **[MA]** | Meta-analysis or systematic review with pooled estimates |
| **[RCT]** | Randomized controlled trial (note the comparator: a waitlist is weaker than an active control) |
| **[LONG]** | Prospective longitudinal / daily-diary / observational cohort |
| **[XS]** | Cross-sectional survey or correlational |
| **[QUAL]** | Qualitative / interview / HCI field study |
| **[CC]** | Clinical consensus, therapy manual, practitioner framework |
| **[POP]** | Popular-only: trade book, institute marketing, press, not peer-reviewed |

**Confidence** (for the operational claim, not the study): **High** = several converging designs including RCT/MA; **Moderate** = consistent longitudinal/XS plus some experimental support; **Low** = single studies, small samples, advocacy sources, or contested.

### 0.2 Citation honesty

Every citation below was located during this review (search results, abstracts, PubMed/PMC, publisher or author pages). Where I could confirm a paper's bibliographic details but only saw secondary summaries of its findings, I say so with **(findings via secondary source)**. Where a commonly repeated number could not be traced to a peer-reviewed primary source, I flag it as **[POP]** or **unverified**. I did not invent effect sizes; where none is given, none was found.

### 0.3 The five meta-findings that should shape Attune

1. **Perceived responsiveness is the hub.** Across 43 longitudinal datasets and 11,000+ couples, the strongest relationship-specific predictors of relationship quality were *perceived partner commitment, appreciation, sexual satisfaction, perceived partner satisfaction, and conflict* (Joel et al., 2020) [MA-like pooled ML analysis]. Note that these are mostly *perceptions of the partner*. An app's job is to make real care visible and easy to give, not to measure it.
2. **Positives are as important as conflict management.** Low positive affect predicts later divorce, while high negative affect predicts early divorce (Gottman & Levenson, 2000) [LONG]. How partners respond to *good* news predicts breakups better than how they respond to bad news (Gable et al., 2006, via secondary source) [LONG].
3. **Skills training is not the only active ingredient.** Programs that just raise awareness did as well as PREP-style skills training over three years (Rogge et al., 2013) [RCT]. Speaker-listener "active listening" is rare in real conflict, and in one cohort it did not predict outcomes (Gottman et al., 1998) [LONG]. Apps should not over-invest in scripted communication drills.
4. **Gains fade without boosters.** IBCT's advantage over traditional therapy disappeared by five years (Christensen et al., 2010) [RCT]. Behavioral couple therapy gains were near zero at 12 months in one meta-analysis (Rathgeber et al., 2019) [MA]. Hold Me Tight program gains slid back at follow-up (Kennedy, 2017) [LONG]. Light, periodic check-ins such as the Marriage Checkup (Córdova et al., 2014) [RCT] are the best-evidenced answer, and they fit what an app can deliver.
5. **The same feature can be care or control.** Location sharing, read receipts, shared calendars and "check-ins" are the very tools abusers misuse with authenticated, ordinary access (Freed et al., 2018) [QUAL]. Safety has to be an architectural property, not a settings page.

---

## 1. Gottman: Sound Relationship House and the conflict research

### 1.1 Key findings

**The Sound Relationship House (SRH)** [CC/POP]. Gottman's clinical model stacks seven "floors": love maps, fondness and admiration, turning toward, positive perspective, managing conflict, making life dreams come true, and creating shared meaning. Trust and commitment are the walls. The model is a clinical synthesis. It has not been validated as a structural model in peer-reviewed tests. I could confirm only fragments of the floor list from secondary sources, so treat the exact architecture as a teaching device.

**Predicting divorce from interaction** [LONG].
- Gottman & Levenson (1992): 73 couples assessed in 1983 and 1987. "Nonregulated" couples (more negative than positive in a cascade of behaviors) were at greater risk of dissolution and showed physiological differences (*JPSP*, 63, 221).
- Gottman & Levenson (2000): 79 couples followed for 14 years, 28% divorced. **Negative affect during conflict predicted *early* divorce. *Absence of positive affect* in both conflict and events-of-the-day talks predicted *later* divorce.** The model was 93% accurate, but that accuracy was in-sample.
- Gottman, Coan, Carrère & Swanson (1998): 130 newlyweds, 6 years. Active listening was rare during conflict and did not predict success. Positive affect, gentler start-up (mostly by wives in their heterosexual sample) and husbands' accepting influence did predict it.
- First three minutes: 6-year outcomes could be predicted from the first three minutes of a conflict conversation (UW summary of Carrère & Gottman, 1999).

**Turning toward bids** [LONG, findings via Gottman Institute]. In a six-year newlywed follow-up, couples still married had turned toward each other's bids 86% of the time in the lab, against 33% for couples who later divorced (Gottman Institute blog). I could not retrieve the underlying peer-reviewed paper, usually cited as Driver & Gottman (2004, *Family Process*), so treat the exact percentages as Institute-reported.

**The 5:1 ratio** [LONG + POP]. The claim is that stable couples show about five positive interactions for every negative one *during conflict*. It is usually traced to Gottman (1993, *JCCP*, 61, 6–15, "five types of couples": validating, volatile, avoidant, hostile, hostile-detached). I could confirm the citation but not the ratio's derivation from the primary text. Popular use often drops "during conflict". It is also frequently confused with Losada's "critical positivity ratio" (2.9:1), which was **partly withdrawn** after Brown, Sokal & Friedman (2013) showed the math was invalid (APA Monitor, 2013). **Use 5:1 as a heuristic about conflict tone, never as a target to score.**

**Four Horsemen and antidotes** [LONG + CC]. Criticism → gentle start-up. Contempt → build a culture of appreciation. Defensiveness → take responsibility. Stonewalling → physiological self-soothing (Gottman Institute). Contempt and the cascade are the best-supported predictors. The antidotes are clinical inferences that have not been tested one by one.

**Repair attempts** [LONG + CC]. Happier couples enter negative affect less and *exit* it more easily (secondary summary of Gottman's sequential analyses). Repair success depends on the relationship's positive baseline, not on the repair phrase itself.

**Flooding and 20-minute breaks** [CC, partly LONG]. Diffuse physiological arousal impairs listening. Gottman Institute guidance is that a flooded partner needs **at least about 20 minutes away** for stress hormones to clear. The break should be truly distracting (no rehearsing grievances), and the partner should name when they will return. The popular "100 bpm" threshold and the 20-minute figure are not stated in the 1992 abstract. They come from Gottman's books and Institute materials. The rationale is plausible physiology, and the exact numbers are a heuristic.

**Perpetual vs solvable problems** [POP/CC]. "69% of problems are perpetual" comes from Gottman's *Seven Principles* book and Institute materials. I could not find a peer-reviewed derivation, so treat the number as unverified. The clinical idea that some conflicts rest on enduring differences and need *dialogue, not resolution* converges with IBCT's acceptance work (Section 3), which **is** RCT-supported.

**Dreams within conflict, rituals of connection, shared meaning** [CC]. These are clinical constructs with face validity, and none has stand-alone RCT support. They overlap with better-evidenced constructs: Michelangelo phenomenon and goal support (Section 14), self-expansion (Section 6), and sanctification for religious couples (Section 11).

**Bringing Baby Home (BBH)** [RCT]. Shapiro & Gottman (2005, *Journal of Family Communication*, 5(1), 1–24) evaluated the psycho-communicative-educational workshop one year after the intervention. A later randomized trial with 136 couples found fathers reported more parenting involvement, more satisfaction with the division of parenting labor, and feeling more appreciated (Shapiro, Gottman & Fink, via PMC8136247). An Australian partial replication is registered (ACTRN12623000102673). I did not find published results.

**Gottman Method Couples Therapy** [RCT, thin]. Independent RCTs of the full therapy protocol are few and small, and many were run in Iran (e.g., PMC6037577). Most positive Gottman evidence is for workshops and psychoeducation, not the therapy.

### 1.2 Critiques (important)

- **Prediction overfitting.** Heyman & Slep (2001, *Journal of Marriage and Family*, "The hazards of predicting divorce without crossvalidation") showed that 90%-accurate discriminant functions collapse in holdout samples, and positive predictive value falls sharply. Gottman's 93–94% figures were derived after the fact, within the same sample.
- **Causal overreach from correlational data.** Stanley, Bradbury & Markman (2000, *JMF*) critiqued the 1998 newlywed paper. They pointed to non-random sampling, missing controls, unclear tests, and premature prescriptions such as "active listening doesn't work" (critique content via ProQuest abstract; authorship confirmed by later citing papers).
- **Samples** were predominantly White, middle-class, heterosexual US couples.
- **Commercialization.** Much Gottman evidence reaches the public through Institute materials that mix research with marketing.

### 1.3 What an app can ethically operationalize

- **Love maps:** a light, *opt-in* question deck ("What's stressing you most this week?", "What's a small dream for this year?"), where each partner chooses whether to share an answer. Frame it as curiosity, not a test. **No "score" for knowing your partner.**
- **Bids:** teach the concept once. Make small bids cheap: a "thinking of you" tap, sending a photo, "look at this". Never show "bids missed" counts.
- **Soft start-up helper:** when a user drafts a complaint, offer an optional private rewrite: "I feel… about… I need…". The user stays in control, and the app makes no automatic edits to messages.
- **Flooding break:** a "Pause" button in the conflict flow sends a neutral, pre-agreed message ("I'm flooded; back in 30 minutes, I care about this"). It starts a 20–30 minute timer with a self-soothing exercise, then prompts the user to return. Both partners agree to the protocol in advance.
- **Repair library:** low-stakes phrases ("Can we start over?", "I see my part") available in-thread.
- **Perpetual-problem dialogue:** a guided "dreams behind the gridlock" conversation (what the position means to me, the story behind it). Present it as a way to understand each other, not a resolution engine.
- **Rituals:** let couples define their *own* rituals (Sunday walk, nightly check-in, weekly date) with gentle, skippable reminders.

### 1.4 What to avoid

- **Ratio dashboards** ("Your positivity ratio this week: 3.2:1") turn affection into performance and invite scorekeeping. Contested numbers also invite false precision.
- Calling the user's partner "contemptuous" or diagnosing horsemen from message text. That is iatrogenic, can be weaponized ("the app says you're contemptuous"), and AI classification is error-prone.
- Divorce prediction of any kind.

**Confidence:** High that positive affect, contempt, and repair matter. Moderate for turning toward bids. Low for specific numbers (5:1, 86/33, 69%, 20 minutes as an exact threshold).

---

## 2. Emotionally Focused Therapy (Sue Johnson)

### 2.1 Key findings

**Model** [CC]. Couple distress is understood as an *attachment* problem: partners are trying to answer "Are you there for me?" Negative cycles, most commonly **pursue–withdraw** ("demon dialogues" in *Hold Me Tight*), are protests against disconnection. The target is **A.R.E.: Accessibility** (can I reach you?), **Responsiveness** (will you respond to my feelings?), and **Engagement** (will you value me and stay close?), per Johnson's *Hold Me Tight* (2008), via secondary summaries. Therapy de-escalates the cycle, then restructures bonds through "softening" and withdrawer re-engagement events. Online A.R.E. quizzes are **not validated instruments**.

**Pursue–withdraw is harmful and very common** [MA]. Schrodt, Witt & Shimkowski (2014, *Communication Monographs*, 81(1), 28–58): a meta-analysis of 74 studies and more than 14,000 participants. Demand/withdraw is reliably associated with worse individual, relational and communication outcomes, and the link is stronger in distressed couples. This independent evidence supports EFT's central target.

**Outcomes:**
- Johnson, Hunsley, Greenberg & Schindler (1999, *Clinical Psychology: Science and Practice*, 6(1), 67–79): a meta-analysis of the four most rigorous early EFT studies. The ES of **1.3** comes from the authors and is promoted by ICEEFT, so it may be inflated by small samples [MA, early].
- **Rathgeber, Bürkner, Schiller & Holling (2019, *JMFT*, 45(3), 447–463):** 33 RCTs, 2,730 participants. Post-test g = 0.60 overall, **EFCT g = 0.73**, BCT g = 0.53. At 6 months, EFCT g = 0.66 and BCT g = 0.35. At 12 months, BCT g = 0.06. EFCT and BCT did not differ significantly, and there is possible publication bias [MA].
- Wiebe et al. (2017, *JMFT*, 43(2), 227–244): two-year follow-up in which satisfaction gains were maintained and attachment trajectories improved [LONG, uncontrolled follow-up].
- 2024 meta-analysis (*Couple and Family Psychology*, cfp0000233): pre-post d = 0.93 across 20 studies including non-RCTs [MA, weaker designs].
- **Hold Me Tight** program (group psychoeducation): Kennedy's (2017) uOttawa thesis followed 95 couples in 16 groups. Satisfaction, trust and avoidance improved, then **drifted back toward baseline at follow-up**, and the author suggests boosters [LONG, uncontrolled]. A Dutch study (Conradi; UvA 2017 press release) reported medium-to-large effects [non-RCT].

### 2.2 App operationalization

- **Name the cycle, not the person.** A psychoeducational "our cycle" map: "When I feel ___, I tend to ___; then you feel ___ and ___". Each partner fills in their own side privately, then chooses whether to share. This is IBCT's "unified detachment" and EFT's "the cycle is the enemy" in practice.
- **A.R.E. reflection prompts:** "When did you feel your partner was reachable this week?" Use these as appreciation prompts, not ratings.
- **Hold Me Tight–style guided conversations** (e.g., "revisiting a rocky moment") as optional, paced modules, with pause points and an exit at any time.
- **Pursuer and withdrawer tips:** for pursuers, softer bids. For withdrawers, "I'm stepping back to calm down, not away from you", which ties to the flooding break.

### 2.3 Avoid

- **Forced vulnerability.** EFT's deep "enactments" are therapist-held. An app must not push people to disclose attachment fears, especially without safety screening. EFT is also **not designed for couples with ongoing violence or coercive control**: softening a victim toward an abuser is dangerous (see Section 13).
- Labeling users with attachment styles ("you're anxiously attached"). This is reductive, can be used as an accusation, and is not a diagnosis.

**Confidence:** High that couple therapy, including EFT, helps distressed couples. Moderate that EFT specifically outperforms. High that demand–withdraw is a valid target. Low for app-delivered EFT.

---

## 3. Integrative Behavioral Couple Therapy (Christensen & Jacobson)

### 3.1 Key findings

- **Acceptance plus change** [CC]. Traditional behavioral couple therapy (TBCT) teaches behavior exchange, communication and problem solving. IBCT adds **acceptance**: **empathic joining** (expressing the soft, vulnerable emotions under hard ones to evoke compassion), **unified detachment** (describing the pattern together, as observers), and **tolerance building**. It also adds a *DEEP* formulation: Differences, Emotional sensitivities, External stressors, Patterns (Christensen, Doss & Jacobson, 2020, *Integrative Behavioral Couple Therapy*, 2nd ed., Norton).
- **Christensen, Atkins, Baucom & Yi (2010, *JCCP*, 78, 225–235)** [RCT]: 134 seriously distressed couples randomized to IBCT or TBCT and followed for 5 years. Both improved similarly by the end of treatment. **IBCT showed better maintenance over the first 2 years**, and the conditions converged by 5 years. About half of couples in both conditions showed clinically significant improvement at 5 years (per secondary summaries; exact percentages not verified). There were no boosters.
- **OurRelationship (online IBCT)** [RCT]: Doss et al. (2016, *JCCP*, 84(4), 285–296, doi:10.1037/ccp0000063). 300 couples, about 8 hours online plus brief coach calls, against a waitlist. Satisfaction d ≈ 0.69, relationship confidence d ≈ 0.47, negative relationship quality d ≈ 0.57, with gains in depression and anxiety (effect sizes via secondary summary). Replicated with low-income couples (Doss et al., 2020). Breakups were not reduced at 6 months.
- **Couple therapy in general** [MA]: Shadish & Baldwin (2003, *JMFT*, 29(4)) d ≈ 0.84 across meta-analyses. Their 2005 publication-bias-adjusted estimate for BCT is d ≈ 0.585. Roddy, Walsh, Rothman, Hatch & Doss (2020, *JCCP*, 88(7), 583–596): 58 studies, 2,092 couples, pre-post satisfaction g = 1.12 against a waitlist g = 0.12. Communication and intimacy improved, gains were generally maintained, and **more distressed couples gained more**. All samples were opposite-sex couples.

### 3.2 App operationalization

**IBCT is the most "app-ready" evidence-based model.** OurRelationship already shows that an online, mostly self-guided version works.
- A **DEEP formulation wizard**: each partner privately names one recurring issue, their soft emotions, external stressors, and the pattern. The app produces a shared *non-blaming* narrative only with both partners' consent.
- **Empathic joining prompt:** "Under my frustration about the dishes is feeling ___ (unappreciated, alone, scared that ___)."
- **Unified detachment:** give the pattern a playful shared name ("the Tuesday Spiral") that both can call out with humor.
- **Acceptance framing for perpetual differences:** "Some differences are features of two people, not problems to fix."
- **Booster check-ins** at 1, 3, 6 and 12 months. This is the single most evidence-justified retention feature.

### 3.3 Avoid

- Promising change by "fixing" the partner. IBCT's insight is that pressure to change *blocks* change.
- Positioning the app as therapy for severely distressed couples without routing them to a clinician. OurRelationship included coach contact and exclusion criteria, including IPV screening.

**Confidence:** High.

---

## 4. PREP, speaker–listener, and communication-skills training

### 4.1 Key findings

- **PREP** (Markman, Stanley et al.) teaches the speaker–listener technique (floor card, paraphrase before rebuttal), problem solving, time-outs, commitment, and fun and friendship time [CC].
- **Marriage and relationship education (MRE) meta-analysis:** Hawkins, Blanchard, Baldwin & Fawcett (2008, *JCCP*): 86 reports, 117 studies, 500+ effect sizes. In experimental studies, **relationship quality d = .30–.36 and communication skills d = .43–.45**. Moderate dose beat low dose, and there was no gender difference [MA]. Blanchard et al. (2009, *JFP*): observed outcomes showed larger effects than self-report, and effects persisted longer for more distressed couples [MA]. Fawcett et al. (2010): **premarital** education **did not improve relationship quality when unpublished studies were included**, but did improve communication [MA].
- **Army RCT:** Stanley et al. (2014, *Family Relations*): 662 Army couples. PREP plus deployment content **reduced divorce at the higher-risk site** (3.8% vs 15.7% among ethnic minority couples), with **no lasting effects on relationship quality**. Couples under economic strain benefited more [RCT].
- **Low-income federal programs:** Johnson (2012, *American Psychologist*, 67(4), 296–308) argued that results from the two multisite federal trials were disappointing for poor couples and couples of color, and that programs needed overhaul. Hawkins, Stanley, Cowan, Fincham et al. (2013) published a more optimistic rebuttal [debate].
- **Is skills training necessary?** Rogge, Cobb, Lawrence, Johnson & Bradbury (2013, *JCCP*, 81(6), 949–961): 174 engaged or newlywed couples were randomized to PREP, CARE (acceptance, support, empathy), or **PAIR, a relationship-awareness program using films**, against no treatment. **All three reduced 3-year dissolution about equally.** The authors questioned the unique value of skills, and raised the possibility that skills training can sensitize couples to deficits [RCT].
- **Active listening in the wild:** rare during conflict and not predictive in Gottman et al. (1998) [LONG, contested by Stanley et al., 2000].

### 4.2 App operationalization

- Offer **structured turn-taking** as an *optional* tool for hot topics (a "floor" token in a guided conversation, paraphrase-then-respond), with a time-out integrated.
- **Relationship-awareness content** (PAIR-style: watch or read a scene, then discuss "Are we like that?") is cheap, engaging, and as effective as heavy skills drills.
- "Sliding vs deciding" nudges at transitions (moving in, having kids, relocating). Stanley, Rhoades & Markman (2006, *Family Relations*, 55(4), 499–509) [LONG].

### 4.3 Avoid

- Making every conversation a scripted exercise. It feels robotic, and it can increase deficit-focus.
- Grading communication ("Your paraphrase score").

**Confidence:** Moderate. MRE helps communication and modestly helps quality; effects are smaller for premarital and low-income samples.

---

## 5. Imago Relationship Therapy

### 5.1 Key findings

- **Model** [CC]. Hendrix and Hunt's Imago dialogue: *mirroring → validation → empathy*, grounded in a theory that we choose partners resembling early caregivers ("imago"). **The partner-selection theory lacks empirical support.** The dialogue structure resembles generic reflective listening.
- **Evidence:**
  - Gehlert, Schmidt, Giegerich & Luquet (2017, *Journal of Couple & Relationship Therapy*, 16(3), 188–209): RCT of 12 sessions. Statistically significant gains in satisfaction **but not clinically significant**, and only one couple reached dyad-level recovery [RCT, small].
  - Schmidt, Luquet & Gehlert (2016, *JCRT*, 15(1), 1–18): weekend workshop. Women's satisfaction rose and men's did not. **Satisfaction declined from post-test to 3 months** [uncontrolled].
  - Muro, Holliman & Luquet (2016, *JCRT*, 15(3)): empathic accuracy improved [small].

### 5.2 App guidance

The mirror–validate–empathize *sequence* is a reasonable generic listening scaffold, the same as speaker–listener. Don't market it as "Imago". Don't use the childhood-imago partner-selection theory.

**Confidence:** Low for Imago-specific efficacy.

---

## 6. Core relationship-maintenance processes

### 6.1 Perceived partner responsiveness (Reis)

- Reis, Clark & Holmes (2004), in Mashek & Aron (Eds.), *Handbook of Closeness and Intimacy*, 201–225: responsiveness, meaning feeling **understood, validated and cared for**, is the organizing construct linking disclosure, support, trust and intimacy (interpersonal process model of intimacy) [CC/theory, extensive LONG support].
- Joel et al. (2020, *PNAS*, 117(32), 19061–19071): the top predictors listed in 0.3 [pooled ML across 43 studies].
- Autistic and non-autistic partners alike: partner responsiveness predicted satisfaction (Yew, Hooley & Stokes, 2023, *Autism*) [XS].
- **App:** every feature should ask "does this help someone feel understood, validated, cared for?" Prompt *responding*, not just sharing: after a partner shares, offer response scaffolds ("Ask one follow-up question", "Reflect what you heard").
- **Confidence:** High.

### 6.2 Capitalization and active-constructive responding (Gable)

- Gable, Reis, Impett & Asher (2004, *JPSP*, 87(2), 228–245): sharing positive events boosts positive affect and life satisfaction beyond the event itself. **Active-constructive** responses (enthusiastic, asking questions, helping the sharer savor) predicted trust, intimacy, satisfaction and commitment. Passive-constructive ("nice"), active-destructive ("but now you'll work more") and passive-destructive (ignoring) responses did not [XS + diary].
- Gable et al. (2006, *JPSP*): in about 80 couples, responses to *good* news predicted relationship well-being and breakups two months later better than responses to bad news (findings via secondary source) [LONG].
- **App:** a "Share a win" flow. When a partner posts good news, the other gets a gentle, optional cue: "Ask them about it, what was the best part?" Offer celebratory reactions beyond a like (a "tell me more" button that opens a reply).
- **Avoid:** auto-replies or AI-generated enthusiasm sent in the user's name. Responsiveness that isn't really the partner's is inauthentic and corrodes trust if discovered.
- **Confidence:** Moderate–High.

### 6.3 Gratitude: find, remind, bind (Algoe)

- Algoe (2012, *Social and Personality Psychology Compass*, 6(6), 455–469): gratitude helps people **find** good partners, **remind** them of the partner's value, and **bind** them closer [theory + LONG].
- Algoe, Gable & Maisel (2010, *Personal Relationships*): daily gratitude for partner's thoughtful acts predicted next-day connection and satisfaction [diary].
- Gordon, Impett, Kogan, Oveis & Keltner (2012, *JPSP*, 103(2), 257–274): feeling appreciated promotes appreciating, which predicts responsiveness, commitment, and staying together over time. Outside observers rated appreciative partners more responsive [XS, diary, observational, LONG].
- Appreciation **buffers perceived unfairness** in housework: during COVID-19 (N = 2,193 incl. 476 couples), the negative effect of unfair housework on satisfaction disappeared when people felt appreciated (*Psychological Science*, 2022, doi 10.1177/09567976221081872) [XS/LONG].
- **App:** a low-friction "I noticed…" gratitude note tied to *specific* acts (the evidence favors specific, other-praising thanks). Partners can save notes to a private "appreciation jar" to revisit in hard times.
- **Avoid:** gratitude quotas, streaks, or "you haven't thanked your partner in 6 days" guilt pings. Gratitude must be voluntary to be credible.
- **Confidence:** High.

### 6.4 Self-expansion and novel shared activities (Aron)

- Aron, Norman, Aron, McKenna & Heyman (2000, *JPSP*, 78, 273–283): surveys linked shared exciting activities to satisfaction, with boredom partly explaining the link. In lab experiments, a short **novel-arousing** joint task raised relationship quality more than a mundane task [XS + experiment].
- **App:** a date and activity generator weighted toward *novel* and mildly challenging ideas, filtered by budget, distance and accessibility, with LDR-friendly versions (co-watching, online games, cooking the same recipe over video).
- **Confidence:** Moderate. The lab effects are short-term, but the field correlations are consistent.

### 6.5 The 36 questions and closeness generation (Aron et al., 1997)

- Aron, Melinat, Aron, Vallone & Bator (1997, *PSPB*, 23(4), 363–377): 45 minutes of escalating reciprocal self-disclosure produced more closeness than small talk between strangers. Matching attitudes, expecting mutual liking, and explicit closeness goals had no effect [experiment].
- **It was never shown to make people fall in love.** The popular "36 questions to fall in love" framing is a press distortion. Evidence in established couples is limited (small studies and dissertations).
- **App:** escalating, reciprocal question decks are fine as *fun conversation starters*, with turn-taking and a skip button.
- **Avoid:** making the deep end mandatory, or giving long-term couples the impression something is wrong if questions feel awkward.
- **Confidence:** High for short-term closeness between strangers. Low for long-term couples.

### 6.6 Sacrifice and communal strength (Impett, Muise)

- Impett, Gable & Peplau (2005, *JPSP*, 89, 327–344): **approach-motivated** sacrifice ("to make my partner happy") was linked to better well-being and relationship quality. **Avoidance-motivated** sacrifice ("to avoid conflict or guilt") was linked to worse outcomes and to breakups over time (2-week diary, dating students) [diary/LONG].
- Communal strength (motivation to meet the partner's needs without expecting tit-for-tat) predicts satisfaction. In sexuality, see Section 8.
- **App:** frame giving in approach terms ("a way to make their day") rather than duty or avoidance. Never frame sacrifices as debts.
- **Avoid:** favor ledgers or "you owe" counters. These are the opposite of communal orientation.
- **Confidence:** Moderate–High.

### 6.7 Dyadic coping and stress spillover (Bodenmann; Neff & Karney)

- **Dyadic coping:** Falconier, Jackson, Hilpert & Bodenmann (2015, *Clinical Psychology Review*, 42, 28–46): meta-analysis showing dyadic coping (stress communication, supportive, common and delegated coping) is robustly associated with satisfaction, consistently across gender and nation in mostly Western samples (pooled estimates not retrieved). A 35-nation study (N = 7,973) found associations vary somewhat by nation [MA + XS].
- **CCET (Couples Coping Enhancement Training)** RCTs: e.g., Zemp et al., 159 couples randomized to standard, compact or DVD-blended CCET against a waitlist (outcomes not retrieved). Zemp et al. (2017) linked CCET-driven dyadic coping changes to reduced coparenting conflict [RCT].
- **Stress spillover:** Neff & Karney (2004, *PSPB*, 30, 134–148): external stress is associated with more negative perceptions of the relationship. Neff & Karney (2009): reactivity to daily relationship experiences is stronger on high-stress days. A 2017 review: stress diverts time and attention from intimacy [LONG]. Karney & Bradbury's (1995, *Psychological Bulletin*, 118, 3–34) **Vulnerability–Stress–Adaptation** model, built from 115 longitudinal studies and 45,000+ marriages, frames this [MA/review].
- **App:** a "my stress today" signal, private by default and shared if chosen ("heavy day, I may be short"). It helps partners attribute irritability to *context, not character*. Add support-request templates ("I need to vent, not solutions" / "I need help deciding").
- **Avoid:** turning stress logs into evidence ("you were stressed 5 days this week"). Keep entries ephemeral by default.
- **Confidence:** High.

### 6.8 Forgiveness and apology

- Fincham, Beach & Davila (2004, *JFP*, 18, 72–81): **benevolence** predicted better conflict resolution, while **retaliation and avoidance** predicted worse, independent of satisfaction. For wives, benevolence predicted husbands' later reports of better resolution over 12 months [XS + LONG].
- **Doormat effect:** Luchies, Finkel, McNulty & Kumashiro (2010, *JPSP*, 98, 734–749): forgiving boosts self-respect *only when the offender signals safety and value* (amends, agreeableness). Otherwise it **erodes self-respect and self-concept clarity** [experiment + LONG]. This is the key safety caveat for forgiveness features.
- **Apology components:** Lewicki, Polin & Lount (2016, *Negotiation and Conflict Management Research*, 9(2), 177–196): 755 participants. More components were better, the most important being **acknowledging responsibility**, then **offer of repair**. The *request for forgiveness* was least important [experiment, non-couple vignettes].
- **App:** an apology helper that guides users through acknowledging their part, naming the impact, offering repair, and committing to change. It **never pressures the hurt partner to forgive** and never shows "forgiveness status".
- **Avoid:** "forgive and forget" messaging, especially where there is repeated harm or abuse.
- **Confidence:** Moderate–High.

### 6.9 Accommodation

- Rusbult, Verette, Whitney, Slovik & Lipkus (1991, *JPSP*, 60(1), 53–78): **accommodation** means inhibiting the impulse to retaliate when a partner behaves badly and responding constructively instead. It is stronger with commitment, satisfaction and investment, commitment mediates it, and it predicts couple functioning [XS + experiment].
- **App:** in-the-moment "pause before you reply" nudges in heated threads (optional, user-enabled).
- **Avoid:** implying the user should accommodate *everything*. Pair this with doormat-effect awareness and IPV safety.

### 6.10 Positive illusions

- Murray, Holmes & Griffin (1996a, *JPSP*, 70(1), 79–98, "The benefits of positive illusions"; 1996b, *JPSP*, 71(6), 1155–1180, "The self-fulfilling nature of positive illusions"): seeing one's partner more positively than they see themselves predicts satisfaction and buffers conflict, and partners grow toward the idealized image. The pattern holds in same-sex couples (Conley et al., 2009) [LONG].
- **Limits:** extreme idealization in long-distance couples predicts *instability on reunion* (Stafford & Merolla, 2007; Section 9).
- **App:** generous attribution prompts ("What's a charitable explanation?") and appreciation features support healthy positive illusions.
- **Avoid:** encouraging users to "see the best" in harmful behavior.

### 6.11 Relationship check-ups (Córdova)

- Córdova et al. (2014, *JCCP*, 82, 592–604): **Marriage Checkup RCT**, 215 married couples, two annual assessment-and-feedback visits against a waitlist, 9 measurement waves over 2 years. **Intimacy, acceptance and satisfaction improved and persisted for 2+ years**, and the most distressed couples improved most [RCT].
- **App:** this is the **highest-fit evidence-based model for Attune.** A quarterly or semi-annual "Relationship Check-up" covers strengths first (the Marriage Checkup emphasizes strengths), then 1–2 areas to grow, with motivational-interviewing style reflection. Each partner completes it privately, sees a joint summary only with both consenting, and the app suggests resources, with a clinician referral when distress is high.
- **Avoid:** turning the check-up into a scorecard with trends that partners compare or weaponize. Show qualitative strengths and growth themes, not numbers.
- **Confidence:** High.

---

## 7. Love languages: Chapman vs the evidence

### 7.1 Key findings

- **Chapman's claims** [POP]: everyone has one primary language among five (words of affirmation, quality time, gifts, acts of service, physical touch), and couples whose languages "match" or who speak each other's are happier.
- **Impett, Park & Muise (2024, *Current Directions in Psychological Science*, doi 10.1177/09637214231217663)** reviewed the roughly 10 existing studies. The three core premises largely fail. (1) Most people value **all five** highly, and forced-choice quizzes manufacture a "primary" language. (2) Factor analyses do **not** consistently recover five factors. (3) Matching does **not** reliably predict satisfaction. They propose a "**balanced diet**" metaphor instead [review].
- **Bunt & Hazelwood (2017, *Personal Relationships*)**: 67 heterosexual couples. Love-language alignment gave **limited support** for satisfaction, and **self-regulation** explained more variance [XS].
- **Mostova, Stolarski & Matthews (2022, *PLoS ONE*, 17(6), e0269429)**: 100 heterosexual couples. **Partners who expressed love in the way the other preferred** had higher relationship and sexual satisfaction [XS, small, self-selected].
- A 2025 study (Flicker & Sancier-Barbosa, via secondary report) suggested that expressing love in *any* of the five forms enhances satisfaction. I did not verify it in the primary text.

### 7.2 What holds up and what doesn't

| Holds up | Doesn't |
|---|---|
| Knowing and responding to your partner's **specific, current preferences** (an instance of responsiveness) | That each person has **one** fixed primary language |
| A **variety** of affectionate behaviors | That there are exactly **five** categories |
| Effort and self-regulation in giving care | That "matching" languages predicts success |
| Using it as a **conversation starter** | Using it as an **excuse** ("my language isn't acts of service, so I won't help") |

### 7.3 App operationalization

- Replace "your love language" with "**What feels loving to me right now**": multi-select, rated, changeable, context-specific (e.g., "when I'm stressed, help with chores; when I'm sad, a hug").
- Let partners see each other's current preferences and get gentle idea suggestions.
- If love-language vocabulary is kept for familiarity, label it as a popular framework, not science.
- **Avoid:** typing quizzes, compatibility scores based on languages, and "mismatch" warnings.

**Confidence:** High that the strong claims are unsupported. Moderate that preference-tailored responsiveness helps.

---

## 8. Sexuality

### 8.1 Key findings

- **Frequency vs satisfaction.** Muise, Schimmack & Impett (2016, *Social Psychological and Personality Science*, online 2015): 30,000+ participants. Sexual frequency's association with well-being is **curvilinear, with no further gain beyond about once a week** for people in relationships. Relationship satisfaction mediates the link, and the direction is unclear [XS, large].
- **More sex is not causal:** Loewenstein, Krishnamurti, Kopsic & McDonald (2015, *Journal of Economic Behavior & Organization*, 116, 206–218): couples instructed to **double** frequency over about 3 months had more sex but became **slightly less** happy, with reduced wanting and enjoyment. Sex framed as an *assignment* undermined intrinsic motivation [RCT, n = 128 individuals].
- **Sexual communication:** Mallory, Stanton & Handy (2019, *Journal of Sex Research*, 56(7)): 48 studies, 12,145 participants. Sexual communication correlates with overall sexual function (r = .35), orgasm (r = .23) and desire (r = .16), with stronger effects for women and married samples [MA, correlational].
- **What satisfied long-term couples do:** Frederick, Lever, Gillespie & Garcia (2017, *Journal of Sex Research*): about 39,000 married or cohabiting adults. Satisfied people more often **set a mood, communicate sexually (including affectionate texts during the day), add variety, and act on the ideas they read** [XS, large].
- **Responsive desire:** Basson's (2000) circular model holds that, especially in long relationships, desire often **follows** arousal and intimacy-motivated willingness rather than preceding it (via secondary sources; DSM-5 FSIAD criteria include responsive desire, per Brotto & Graham's 2021 commentary) [CC/theory, influential].
- **Sexual communal strength:** being motivated to meet a partner's sexual needs is linked to higher desire and satisfaction for *both* partners over time. Meeting the partner's needs while **neglecting one's own** harms both (Muise and colleagues; In-Mind and SPSP summaries; primary 2013 paper not retrieved) [LONG].
- **Desire discrepancy:** Day, Muise, Joel & Impett (2015, *PSPB*): discrepancies are common (about 80% reported one in the past month). Communally motivated partners navigate them better [diary]. Kim et al. (2020): with 366 couples and proper response-surface analysis, **matched desire per se did not predict satisfaction**; overall couple desire and large absolute gaps mattered [XS].
- **Aging and health:** Lindau et al. (2007, *NEJM*, 357(8), 762–774): 3,005 US adults aged 57–85. Sexual activity was 73% at 57–64, 53% at 65–74, and 26% at 75–85. Frequency among those still active was comparable to younger adults. Ill health and lack of a partner were the main barriers, and **most had never discussed sex with a physician** [XS, national probability sample].
- **Coercion:** reproductive coercion (pregnancy coercion, birth-control sabotage) is common in clinical samples. Miller et al. (2010, *Contraception*): among 1,278 clinic attendees aged 16–29, 19% reported pregnancy coercion and 15% birth-control sabotage, and 35% of those reporting IPV also reported reproductive control [XS].

### 8.2 App operationalization

- **Desire education:** normalize spontaneous vs responsive desire, and normalize desire discrepancy as common and navigable.
- **Private "yes / no / maybe" lists** (fantasies, activities, boundaries) that reveal **only mutual yeses**. Each partner's "no" stays invisible. Explicitly label it as consent-first, revocable at any time.
- **Mood-setting and anticipation:** affectionate or teasing messages during the day, and planning intimate time if the couple *wants* that. Scheduling can work well for busy or LDR couples when it's chosen. It backfires when it feels like an assignment.
- **Communication starters** about sex (what I like, what's changed, what I'm curious about) with low-stakes framing.
- **Health-aware content** for aging, illness, postpartum, disability and medications, with prompts to talk to a clinician.

### 8.3 Avoid

- **Sex frequency trackers, targets, streaks, or "once a week" goals.** Experimental evidence shows assigned frequency backfires, and trackers create pressure and comparison.
- Any feature that could be used to **pressure** a partner ("you haven't…in 2 weeks"), or that frames sex as owed. Communal motivation must never become obligation.
- Gendered stereotypes about desire.
- Treating "no" as something to overcome. All intimacy features must be **mutual-opt-in, private-by-default, and revocable**.

**Confidence:** High for communication, responsiveness and the backfire of assigned frequency. Moderate for communal strength. Moderate–High for consent principles (clinical consensus plus IPV evidence).

---

## 9. Long-distance relationships (LDRs)

### 9.1 Key findings

- **Intimacy through mediated communication:** Jiang & Hancock (2013, *Journal of Communication*, 63, 556–577): one-week diary of 63 dating couples. LDR partners had **fewer** interactions but used more mediated channels, and felt **more intimate**, driven by **more self-disclosure** and **idealizing the partner's behavior** (the hyperpersonal effect). Effects varied with medium richness, synchronicity and mobility [diary].
- **Stability and the reunion paradox:** Stafford & Merolla (2007, *Journal of Social and Personal Relationships*, 24(1), 37–54): LDR dating couples were **more stable while apart**, idealized more, and were more satisfied with communication. But **after moving to the same place, many broke up**, and longer gaps between visits and *extreme* idealization predicted instability on reunion [LONG]. The "twice as likely" reunion breakup figure is secondary and unverified.
- **Quality comparisons:** Kelmer, Rhoades, Stanley & Markman (2013, *Family Process*, 52, 257–270): about 870 participants. LDR partners reported equal or higher quality (love, fun, adjustment, conversation, less negative communication) and lower feelings of constraint (via secondary summary) [XS/LONG]. Dargie, Blair, Goldfinger & Pukall (2015, *Journal of Sex and Marital Therapy*, 41(2), 181–202): about 1,140 participants found no quality difference between LDRs and geographically close relationships. Better LDR outcomes went with **lower distress, positive LDR attitudes, and relationship certainty**. LDR couples were better at *talking* about sex, while close couples *had* more sex [XS].
- **End-date certainty:** a *Communication Quarterly* study (2007, 55(4), "Will it ever end?") found that partners **uncertain whether they'd ever live in the same city** were more distressed, less satisfied, and found coping strategies less helpful. The effect weakened when people held positive future evaluations [XS]. *Practical reading: a shared plan or review date matters even when the exact end date is unknown.*
- **Maintenance behaviors:** Stafford & Canary (1991, *JSPR*, 8, 217–242) identified **positivity, openness, assurances, social networks, sharing tasks**. Positivity and **assurances** predict satisfaction most consistently, and openness predicts least, with mixed results [XS, many replications].
- **Video "co-presence":** Neustaedter & Greenberg (2012, CHI): LDR couples leave video links open for hours to "hang out" and share everyday life. This gave intimacy and *reduced idealization*. Challenges included **time zones**, technical quality, and lack of physicality [QUAL].
- **Military deployments:** Knobloch & Theiss (2012, *JSPR*): 259 reunited partners reported both challenges (relational uncertainty, partner interference in routines) and opportunities, with women, at-home partners and reservists hit hardest. Theiss & Knobloch (2013, 2014): turbulence predicts less openness, more aggressiveness, and distress. Knobloch, Basinger & Theiss (2018): turbulence reduces perceived partner support [XS]. The Army PREP RCT included deployment and reunion content (Stanley et al., 2014) [RCT]. Anticipatory **relational savoring** buffered distress for civilian partners during deployment (Froidevaux, Borelli et al., 2023) [LONG].
- **Commuter marriages:** commuters report more satisfaction with work and time alone but less with family life (Bunker et al., 1992, via secondary citation) [XS]. Lindemann's interview study of 97 commuter spouses (*Commuter Spouses*, 2019) [QUAL]. Findings are mixed across cultures.
- **Time zones:** I found no dedicated outcome studies. Neustaedter & Greenberg (2012) note time zones as a practical barrier. **Evidence gap.**

### 9.2 App operationalization (LDR is a core Attune use case)

- **Dual-clock and "good time to call" overlap finder** across time zones and work schedules. **Opt-in, coarse availability** ("free evening" / "busy"), never precise location.
- **Countdown to next visit** (assurance plus anticipation) and a **"Our plan" card**: next visit, review date for the distance arrangement, shared goals. Keep it non-judgmental if no end date exists.
- **Co-presence rituals:** synchronous watch-together, cook-the-same-recipe, "open line" video nights, shared music, play-together games. These cut idealization by sharing mundane life.
- **Assurance prompts** ("Tell them one thing you're looking forward to together"), plus attention to social networks (meeting each other's friends virtually).
- **Reunion transition module:** before moving together or a long visit, prompts on routines, alone time, space, chores and finances, normalizing that reunions can be bumpy. It draws on Stafford & Merolla and the relational turbulence work.
- **Asynchronous media** (voice notes, photo journals) for mismatched time zones.

### 9.3 Avoid

- **Constant-contact pressure:** "online now", last-seen, read receipts and response-time indicators fuel anxiety and surveillance in LDRs. Default them **off** and make them mutual.
- **Location tracking as a "trust" feature.** Monitoring is associated with insecurity (Fox & Warber, 2014). Location sharing is a primary coercive-control vector (Section 13).
- Encouraging extreme idealization. Balance it with "share the boring stuff".
- Assuming all LDRs end in cohabitation. Respect commuter, military and LAT (living-apart-together) couples.

**Confidence:** Moderate. Mostly XS and small diary samples of young dating couples, so extrapolation to married or older LDR couples is uncertain.

---

## 10. Technology and couples

### 10.1 Key findings

- **Technoference:** McDaniel & Coyne (2016, *Psychology of Popular Media Culture*, 5, 85–98): 143 married or cohabiting women. Technoference was associated with more technology conflict, lower relationship and life satisfaction, and more depressive symptoms. The data are correlational and likely bidirectional [XS].
- **Partner phubbing:** Roberts & David (2016, *Computers in Human Behavior*, 54, 134–141): two surveys (N ≈ 453) linked phubbing to conflict, lower relationship and life satisfaction, and depression [XS].
- **Texting:** Schade et al. (2013, *Journal of Couple & Relationship Therapy*, 12, 314–338): 276 emerging adults. **Affectionate texting** went with higher attachment. **Hurtful texting** (for men) went with lower attachment, satisfaction and stability. Conflict via text is a poor fit for the medium [XS, exploratory].
- **Partner surveillance:** Fox & Warber (2014, *Cyberpsychology, Behavior, and Social Networking*, 17, 3–7): N = 328. Anxious (preoccupied or fearful) attachment predicted Facebook partner surveillance [XS]. A 2025 location-sharing study (N = 434, *Frontiers in Human Dynamics*) found perceived intrusion lowered satisfaction, mutual acceptance reduced intrusion, and broader scope raised it [XS].
- **Tech-facilitated abuse:** Freed et al. (2018, CHI, "A Stalker's Paradise"; Best Paper): abusers mostly use **unsophisticated, authenticated access** through **ordinary UIs** and shared accounts, gained through intimacy or coercion. They also use "dual-use" apps such as family trackers [QUAL, n = 89]. Freed et al. (2017, CSCW): multi-stakeholder analysis [QUAL]. Chatterjee et al. (2018, IEEE S&P): hundreds of dual-use spyware apps [measurement]. PenzeyMoog (2021, *Design for Safety*, A Book Apart): a practitioner framework for designing against interpersonal harm [CC].
- **Mental load and fair division:** Daminger (2019, *American Sociological Review*, 84(4), 609–633): 35 couples. Cognitive labor (**anticipate, identify options, decide, monitor**) is invisible and taxing. Women did more anticipating and monitoring, while decision-making was roughly equal. It is a frequent source of conflict [QUAL]. Gillespie, Peterson & Lever (2019, *PLoS ONE*): 10,236 respondents. **Unfairness to oneself** predicts relationship quality more than unfairness to the partner, and **fairness over shared expenses** predicted quality more strongly than housework equity [XS].
- **Digital couple interventions:** a 2025 *BMC Psychology* systematic review and meta-analysis (doi 10.1186/s40359-025-03444-y) of 15 studies found mostly positive effects on satisfaction, a moderate pooled effect across 6 studies with high heterogeneity, OurRelationship d ≈ 0.53 and ePREP d ≈ 0.42 (via abstract and secondary summary) [MA]. App-specific evidence is thin: pilot studies such as the iCognito chatbot program (Troitskaya et al., 2022, *Family Process*) and the Paired app mixed-methods evaluation (PMC12001865) [pilot]. Disengagement is a general mHealth problem.

### 10.2 App operationalization

- **Shared logistics that reduce mental load:** shared lists and calendars that show *who is holding which task* (including the "noticing" and "monitoring" parts). Make it easy to hand off a whole task (anticipate → decide → do → follow up), not just the doing.
- **Fairness conversations, not ledgers:** a periodic, private "How fair does our split feel to *you*?" reflection that leads to a conversation. Don't count chores.
- **Phone-free rituals:** an optional "together time" mode that silences the app itself, and gentle encouragement to put phones away on dates. The app should practice what it preaches.
- **Digital rituals:** morning and night check-ins, shared journals, photo-of-the-day. All skippable, with no streak penalties.

### 10.3 Avoid

- **Chore scoreboards and point systems.** These create the scorekeeping that predicts dissatisfaction, and they invite weaponization.
- **Read receipts, typing indicators, last-active and location as defaults.**
- **Any feature letting one partner see the other's private entries, app activity, or settings changes.**
- Engagement-maximizing dark patterns (infinite feeds, guilt notifications) that themselves become technoference.

**Confidence:** Moderate for technoference and phubbing (correlational). High for IPV tech-abuse patterns (consistent qualitative and measurement work). Moderate for mental-load findings.

---

## 11. Religion and spirituality

### 11.1 Key findings

- **Religion and marriage meta-analysis:** Mahoney, Pargament, Tarakeshwar & Swank (2001, *Journal of Family Psychology*, 15, 559–596): 94 studies. Religious attendance has a **small** association with lower divorce (r ≈ .125), and the affiliation–divorce link largely disappears with demographic controls [MA].
- **Sanctification of marriage:** Mahoney, Pargament, Murray-Swank & Murray-Swank (2003, *Review of Religious Research*, 44, 220–236). Perceiving marriage as having divine character predicts marital quality. A 2015 meta-analysis (Pomerleau, Wong & Mahoney) reported zr ≈ .32 with satisfaction (via BGSU summary). Sanctity predicted quality beyond forgiveness and sacrifice in 342 couples (2013) [MA + XS].
- **Praying for the partner (Fincham's experiments):**
  - Fincham, Lambert & Beach (2010, *JPSP*): daily partner-focused prayer for 4 weeks **reduced extradyadic romantic behavior** compared with positive thoughts or neutral activity (N = 83), mediated by perceived sacredness. Observers rated pray-ers as more committed [RCT-like experiments, student samples].
  - Lambert, Fincham, Stillman, Graham & Beach (2010, *Psychological Science*): prayer for partner or friend **increased forgiveness**, mediated by selfless concern [experiments, N = 52 and 67].
  - Lambert et al. (2013, *Personal Relationships*): partner-focused prayer led coders to rate participants as less vengeful [experiment].
- **Interfaith and homogamy:** Lehrer & Chiswick (1993, *Demography*, 30(3), 385–404): religious intermarriage is associated with higher instability. A later IZA analysis notes the direct effect can become non-significant with controls, and that indirect paths such as child-rearing decisions matter [LONG/demographic]. Interfaith couples face couple-level minority stress where stigmatized (LeBlanc, Frost & Wight, 2015) [theory].
- **Shared meaning without religion:** the mechanisms (shared values, rituals, sacredness, transcendence) overlap with secular constructs: shared meaning, Michelangelo, self-expansion.

### 11.2 App operationalization

- **Faith as an opt-in layer, not a default.** Onboarding asks *each partner separately* whether they'd like spiritual content and which tradition, if any, with "none" and "prefer not to say" as first-class options.
- For couples who opt in: prompts to pray for the partner (Fincham), sacred-values conversations, and tradition-appropriate rituals and holidays in the shared calendar.
- **Secular equivalents** for everyone: "hold your partner in mind" intention-setting, gratitude for the partner, values conversations, meaning-making rituals.
- **Interfaith couples:** conversation guides about traditions, children's upbringing, holidays and extended family. Respect asymmetric opt-in (one partner religious, one not).

### 11.3 Avoid

- Assuming a faith, or nudging toward or away from religion.
- Religious content shown to a partner who didn't opt in.
- Using religious framing to discourage leaving abuse ("covenant", "submission", "forgive seventy times seven"). IPV safety overrides.
- Gender-role prescriptions.

**Confidence:** Moderate. The effects are real but modest and largely from US Christian samples. Prayer studies are small and student-based.

---

## 12. Life-context challenges

### 12.1 Money, chores, fairness, mental load

- See Section 10.1: Daminger (2019) on cognitive labor, Gillespie et al. (2019) on shared-expense fairness, and appreciation as a buffer (Psych Science 2022).
- **App:** shared budgeting and goal tools with *transparency by mutual consent*. "Money dates": a periodic guided conversation about values, goals and fears. Never force financial disclosure, because financial control is a recognized abuse tactic.
- **Confidence:** Moderate.

### 12.2 Transition to parenthood

- Doss, Rhoades, Stanley & Markman (2009, *JPSP*, 96(3), 601–619): 218 couples over 8 years. A **sudden post-birth decline** in relationship functioning (small to medium) that persisted, similar for mothers and fathers. Childless couples showed gradual decline without the drop. Pre-birth negative communication predicted worse change [LONG].
- **Prevention works:** Bringing Baby Home (Section 1). Family Foundations (Feinberg et al., 2010, 169 couples; 2016, 399 couples, *Prevention Science*): improved coparenting, parent mental health, parenting and child adjustment, and **reduced family violence**, with effects maintained to child ages 7 and 10 (via Blueprints and clearinghouse summaries) [RCT; Blueprints "model program"].
- **App:** a pregnancy and newborn track covering expectations, the division of new labor, coparenting teamwork, sleep-deprivation conflict tips, and protected couple time. Screen for perinatal depression and route to care, since pregnancy and postpartum are elevated IPV-risk periods (USPSTF evidence came mostly from perinatal populations).
- **Confidence:** High.

### 12.3 In-laws and family

- Orbuch et al. (2013, *Family Relations*): early closeness to in-laws predicted lower divorce for husbands and *higher* for wives in some groups, varying by race and gender (16-year analysis; press reports of 20% differences come from the broader 26-year project) [LONG].
- **Collectivist contexts:** Bejanyan, Marshall & Ferenczi (2015, *PLoS ONE*): **accepting parental influence** over mate choice reduced commitment and passion, while **family allocentrism** (close family ties) *increased* commitment [XS]. *Family involvement is not inherently negative. Unwanted control is the problem.*
- **App:** "family and boundaries" conversation guides. Cultural adaptations for extended-family obligations, remittances, and family events (relevant for West African, South Asian, Latin American and other collectivist users). A shared family calendar with *per-event visibility*.
- **Confidence:** Moderate–Low (few studies, mixed findings).

### 12.4 Health, illness and caregiving

- Dyadic coping predicts satisfaction (Falconier et al., 2015). In dementia, relationship quality is linked to lower caregiver stress. One couple-based dementia RCT (108 couples) did not improve quality of life overall, except in couples with poor relationship quality (PMC7317469). Reviews note gaps in couple support as dementia progresses [RCT/review].
- **App:** caregiver-burden check-ins, task sharing with family helpers, respite reminders, "we-coping" framing ("our challenge"), and redefining intimacy and roles. Route to caregiver support resources.
- **Confidence:** Moderate–Low.

### 12.5 Grief

- Büyükcan-Tetik et al. (2017, *JFP*): 229 bereaved Dutch couples. **Perceiving one's partner's grief as different** predicted lower satisfaction. Perceived similarity mattered more than actual congruence [LONG].
- **App:** psychoeducation that partners often grieve differently (pace, style, gender patterns) and that this is not a lack of love. Anniversary sensitivity: no cheerful "memories" resurfacing a deceased child, pet or parent without consent. Route to grief support.
- **Confidence:** Low–Moderate.

### 12.6 Infertility

- Peterson, Newton, Rosen and colleagues (2006, *Family Relations*: 420 couples; 2008, *Human Reproduction*): **congruent perceptions** of infertility stress predicted better marital adjustment, and a **partner's active-avoidance coping** increased the other's distress [XS/LONG].
- **App:** private, opt-in fertility-journey support. Separate each partner's emotional check-ins. Avoid baby-centric marketing, pregnancy announcements in feeds, and "family planning" nudges. Treatment logistics in the calendar only if chosen.
- **Confidence:** Low–Moderate.

### 12.7 Neurodivergence (ADHD, autism)

- Adult ADHD is associated with more relationship conflict and instability (Wymbs, Canu, Sacchetti et al., 2021, *JMFT*, 47(3), 664–681, review; findings via Duke summary) [review].
- Autistic adults: **partner responsiveness** predicts satisfaction for both autistic and non-autistic partners (Yew et al., 2023, *Autism*). Satisfaction is similar regardless of partner neurotype (2024, *Autism in Adulthood*, doi 10.1089/aut.2024.0124) [XS].
- **App:** explicit, literal communication options (no reliance on hinting). Reminders and executive-function supports *the user sets for themselves*. Sensory-friendly date ideas. Content that frames differences as **access needs, not character flaws**. Avoid "neurotypical as normal" scripts.
- **Avoid:** using one partner's diagnosis as a framing for blame. Reminder systems controlled by the *other* partner can become monitoring.
- **Confidence:** Low–Moderate.

### 12.8 Trauma-informed approaches

- CBCT for PTSD (Monson et al., 2012, *JAMA*, 308(7), 700–709): 40 couples, conjoint therapy improved PTSD and patient relationship satisfaction against a waitlist [RCT].
- **SAMHSA (2014) trauma-informed principles:** safety; trustworthiness and transparency; peer support; collaboration and mutuality; empowerment, voice and choice; cultural, historical and gender issues. Plus the "4 Rs": realize, recognize, respond, resist re-traumatization [CC].
- **App:** apply the SAMHSA principles as **design principles**. Predictable flows, content warnings, user-paced disclosure, exits everywhere, no surprise resurfacing of painful content, and choice over what is shared.
- **Confidence:** High as design guidance (consensus). Moderate for CBCT.

### 12.9 Culturally diverse couples

- Dyadic coping–satisfaction links vary across 35 nations. Sexual-communication associations were larger outside the US (Mallory et al., 2019). Collectivism has opposing effects through parental influence vs family ties (Bejanyan et al., 2015). MRE evidence is thin for low-income and minority couples (Hawkins et al., 2008; Johnson, 2012).
- **App:** localize content (examples, family structures, holidays, gender norms) with community input. Never assume Western individualist defaults such as "set boundaries with your parents" as universal truth. Offer *options* ("Some couples… others…").
- **Confidence:** Moderate that adaptation matters. Specific adaptations are under-researched.

### 12.10 LGBTQ+ couples

- **Couple-level minority stress:** LeBlanc, Frost & Wight (2015, *JMF*, 77(1), 40–59). Stigma targets the *relationship itself*, and feeling in a "second-class" relationship is linked to poorer mental health [theory + XS].
- Rostosky & Riggle (2017): an ecological review of minority stress in same-sex relationships, plus a review of **strengths**: respect for differences, positive interactions, communication and negotiation, intimacy, commitment, **egalitarian ideals**, outness (*Psychology of Sexual Orientation and Gender Diversity*, 4) [review].
- Positive illusions hold across gay, lesbian and heterosexual couples (Conley et al., 2009).
- **App:** inclusive defaults (no gendered roles in chore, sex or parenting content; partner pronouns; chosen family). **Outness controls**: an app that reveals relationship status to contacts, calendars or notifications could out someone. Notification previews should be generic by default.
- **Confidence:** Moderate.

### 12.11 Older couples

- Levenson, Carstensen & Gottman (1993, *Psychology and Aging*, 8): older long-married couples showed **less conflict potential and more shared pleasure**. Carstensen, Gottman & Levenson (1995): older couples resolved conflict with **more affection, less negativity**, and lower physiological arousal [XS/observational].
- Sexuality continues into later life, with health the main barrier (Lindau et al., 2007).
- **App:** accessibility (type size, voice, simple flows). Content on retirement transitions, health, caregiving, grandparenting and later-life sexuality. Avoid youth-centric date ideas.
- **Confidence:** Moderate.

---

## 13. Intimate partner violence (IPV) and coercive control

### 13.1 Key findings

- **Coercive control:** Stark (2007, *Coercive Control: How Men Entrap Women in Personal Life*). Abuse is often a *pattern* of domination (isolation, monitoring, micro-regulation of daily life, degradation, financial control), not discrete incidents [CC/theory].
- **Johnson's typology** (2008): **intimate terrorism** (violence embedded in coercive control), **situational couple violence** (escalated conflicts without a general control pattern), and violent resistance. Coercive controlling violence is associated with more severe and frequent violence, injury, and post-separation harassment [theory + XS]. It is debated: Walby & Towers (2018) critique it.
- **Lethality risk factors:** Campbell's **Danger Assessment** (NIJ Journal, 2003) found weapon threats associated with about 20× homicide risk. **Non-fatal strangulation** raised the odds of attempted homicide (OR 6.70) and homicide (OR 7.48) (Glass et al., 2008, PMC2573025) [case-control]. Separation and escalation are recognized danger periods [CC].
- **Screening:** USPSTF (2018, **Grade B**; superseded by a 2025 update) recommends screening women of reproductive age and referring positives to support. Validated brief tools include **HARK, HITS, E-HITS, PVS, WAST**. There is adequate evidence that *support services* reduce harm, and inadequate direct evidence that screening alone does [CC/systematic review].
- **Couple therapy and IPV:** conjoint therapy is generally **contraindicated with coercive control or fear of the partner**. Victims may be endangered by disclosures in joint sessions, and "the cycle" framing can imply shared blame. Bograd & Mederos (1999, *JMFT*) called for universal, **separate** screening before any couple work [CC]. Very few therapists routinely screen (MSU dissertation reports about 4%). Narrow exception: Domestic Violence Focused Couples Treatment (Stith, McCollum, Rosen et al.) for carefully screened *situational* violence, where both want to stay and there is no coercive control. In the multi-couple format it reduced recidivism compared with controls (via program description) [RCT, specialized].
- **Tech abuse:** see Section 10 (Freed et al., 2017, 2018; Chatterjee et al., 2018). Location sharing, shared accounts, cloud backups, smart-home devices and "family safety" apps are the main vectors. Leitão (2019, DIS) covers smart homes. The main design text is PenzeyMoog (2021).
- **Reproductive and sexual coercion:** Miller et al. (2010) (Section 8).

### 13.2 Warning signs an app should recognize (in content, never as a "diagnosis")

Fear of the partner; checking or monitoring the phone or location; isolation from friends and family; controlling money; threats (to self, partner, children, pets); strangulation or choking; weapon access; forced or pressured sex; jealousy framed as love; humiliation; escalation after separation or pregnancy.

### 13.3 Safe design principles for Attune (non-negotiable)

1. **Individual safety screening in private.** Each partner gets a brief, validated-style check (adapted from HITS or HARK, with clinician input), *never* shown to the other partner, with results stored separately. Positive screens **gate conjoint conflict features** and route the user to safety resources.
2. **No partner surveillance primitives.** No precise location tracking. No read receipts or last-seen by default. No view of the partner's private journal, mood logs, screening answers, or app usage. Any shared visibility must be **symmetric, opt-in, granular, and revocable by either partner unilaterally, without notifying the other in a way that could provoke retaliation** (e.g., stop sharing silently).
3. **Unilateral exit and data separation.** Either partner can leave the couple space, delete their own data, and download it, *without the other's consent*. Shared content created by both needs a fair split policy.
4. **Quick exit and discretion.** A quick-exit gesture, a neutral app icon option, generic notification text ("You have a new message"), and no sensitive content in previews.
5. **Account security for the IPV threat model.** Assume the adversary knows the passcode or holds the phone. Re-authenticate for sensitive areas, show active sessions and devices, alert *the account owner* (not the partner) to new logins, and never allow password resets through a partner's email or phone.
6. **AI handling.** If the AI detects disclosure of abuse, fear, strangulation, sexual coercion or threats, it stops relationship-skill coaching and does **not** suggest "communicating better" or "both sides". It responds supportively, offers hotline and advocate resources, and offers safety-planning information. **Never** notify or summarize to the partner.
7. **No conflict features that require both partners to disclose vulnerabilities simultaneously** when a safety flag is present.
8. **Safety planning resources** (hotlines, text lines, local advocates, "how to check your phone for stalkerware", how to secure accounts), localized by country.
9. **Shared couple features must not become evidence logs.** No exportable "history of what you did wrong", and no timestamped receipts of who did chores or apologized.

**Confidence:** High (strong consensus, consistent HCI and security evidence).

---

## 14. Shared goals, meaning, celebration, savoring, nostalgia

### 14.1 Key findings

- **Michelangelo phenomenon:** Drigotas, Rusbult, Wieselquist & Whitton (1999, *JPSP*): partners who **affirm** each other's *ideal selves* help each other move toward those ideals, and this predicts personal growth and couple well-being (findings via later reviews). Rusbult, Kumashiro, Kubacka & Finkel (2009, *JPSP*, 96, 61–82) and Rusbult et al. (2009, *Current Directions*) [LONG + experiments].
- **Secure-base goal support:** Feeney (2004, *JPSP*, 87, 631–648): partners who are **available, encouraging, and non-interfering** foster goal striving and exploration. *Intrusive* help undermines it [observational + LONG].
- **Celebration and capitalization:** Section 6.2.
- **Relational savoring:** anticipatory savoring buffered deployment distress (Froidevaux, Borelli et al., 2023) [LONG]. Borelli's clinical model is a brief, guided recollection of a moment of connection [CC + small experiments].
- **Shared meaning** (Gottman) [CC]. **Nostalgia** in couples is under-studied. Mostly theory, with little couple-specific evidence found in this review.

### 14.2 App operationalization

- **Dreams and goals board:** each partner adds personal aspirations, and the other can "cheer" or offer support *in the way they want* ("Cheer me on" vs "Help me plan" vs "Just know about it"). This is a direct secure-base implementation.
- **Shared goals and bucket list** with *joint* ownership (trips, home, savings, faith or values goals).
- **Savoring prompts:** "Relive one moment this week when you felt close" (relational savoring), anticipatory savoring before visits (LDR), and an anniversary or memory lane with **consent and sensitivity controls** (snooze, hide, grief-safe).
- **Celebration rituals:** milestones the couple defines, not app-imposed streak milestones.

### 14.3 Avoid

- Goal tracking that lets one partner pressure the other ("You said you'd go to the gym"). Feeney shows intrusive support backfires.
- Forced nostalgia (resurfacing memories after a breakup or bereavement).

**Confidence:** Moderate.

---

## 15. Breakups, dissolution, healing and co-parenting

### 15.1 Key findings

- **Emotional course:** Sbarra & Emery (2005, *Personal Relationships*, 12(2), 213–232): 58 young adults on 28-day beeper diaries. Love declined linearly, while sadness, anger and relief followed curvilinear paths. **Contact with the ex slowed recovery** of love and sadness, and attachment security and acceptance aided recovery (2006 follow-ups) [diary/LONG].
- **Structured reflection helps:** Larson & Sbarra (2015, *Social Psychological and Personality Science*): 210 recently separated adults. Repeated reflective assessments improved **self-concept clarity**, which reduced emotional intrusion and loneliness [RCT-like assignment].
- **Co-parenting:** Family Foundations shows coparenting quality is modifiable, and it reduced family violence (Feinberg et al.) [RCT]. Children are harmed most by **ongoing interparental conflict**, so low-conflict, structured communication is key [CC].

### 15.2 App operationalization

- **Graceful decoupling:** a clear "end the shared space" flow with each person's data separated and an option to archive or delete memories. **Turn off memory resurfacing and partner content immediately.**
- **Post-breakup self-care track** (opt-in, individual): self-concept rebuilding ("Who am I outside this relationship?"), structured reflection, social reconnection, and "no-contact" support tools such as muting.
- **Co-parenting mode** (separate product surface if built): child-focused, businesslike communication, a shared child calendar, and neutral templates. **Not** a channel for monitoring the ex. Note that post-separation is a high-risk period for IPV.

### 15.3 Avoid

- Keeping exes connected through features or reminders by default.
- Gamifying "getting over it", or using breakup data for engagement.
- Encouraging contact that research associates with slower recovery.

**Confidence:** Moderate.

---

## (a) The 30 highest-leverage, evidence-backed mechanisms an app could support (ranked)

Ranking weights evidence strength, effect magnitude or robustness, breadth across couple types including LDR, and how feasibly an app can deliver it safely.

| # | Mechanism | Core evidence | Grade | App form |
|---|---|---|---|---|
| 1 | **Perceived partner responsiveness** (understood, validated, cared for) | Reis et al. 2004; Joel et al. 2020; Yew et al. 2023 | LONG + pooled ML | Response scaffolds after every share; "ask one question" cues |
| 2 | **Periodic relationship check-ups** (strengths-first, feedback, boosters) | Córdova et al. 2014; Christensen 2010 and Kennedy 2017 fade without boosters | RCT | Quarterly private check-up → consented joint summary → resources/referral |
| 3 | **Appreciation and gratitude for specific acts** | Algoe 2012; Gordon 2012; Algoe 2010; Psych Sci 2022 buffer | LONG + diary | "I noticed…" notes; appreciation jar |
| 4 | **Acceptance of perpetual differences, unified detachment, empathic joining** | Christensen 2010; Doss 2016 OurRelationship; Roddy 2020 | RCT + MA | DEEP wizard; name the pattern together |
| 5 | **Interrupting demand–withdraw** (soft bids for pursuers, "stepping back, not away" for withdrawers) | Schrodt 2014 (74 studies); EFT RCTs (Rathgeber 2019) | MA | Cycle map; pursuer and withdrawer tips |
| 6 | **Active-constructive responding to good news** | Gable 2004; Gable 2006 | XS + LONG | "Share a win" + "tell me more" |
| 7 | **Physiological self-soothing breaks during flooding** (≥20 min, agreed return) | Gottman & Levenson 1992; Gottman clinical | LONG + CC | Pause button, pre-agreed message, timer, return prompt |
| 8 | **Keeping positive affect high in everyday life** (low positivity predicts later divorce) | Gottman & Levenson 2000 | LONG | Small bids, rituals, fun prompts (no ratios) |
| 9 | **Dyadic coping and support matching** ("vent vs solve") | Falconier 2015; CCET RCTs | MA + RCT | Stress signal + support-request templates |
| 10 | **Contextualizing stress** (spillover awareness, charitable attributions) | Neff & Karney 2004/2009; Karney & Bradbury 1995 | LONG | "Heavy day" status; generosity prompts |
| 11 | **Gentle start-up and taking responsibility** | Gottman 1998; Lewicki 2016 (apology) | LONG + experiment | Optional private rewrite helper; apology helper |
| 12 | **Repair attempts and de-escalation** | Gottman sequential analyses; Rusbult 1991 accommodation | LONG | In-thread repair phrases; "pause before reply" |
| 13 | **Novel, shared, self-expanding activities** | Aron 2000 | XS + experiment | Novelty-weighted date generator incl. LDR versions |
| 14 | **Approach-motivated giving and communal strength** | Impett 2005; Muise (sexual communal strength) | diary/LONG | Approach framing; no ledgers |
| 15 | **Sexual communication and mutual-opt-in desire exploration** | Mallory 2019; Frederick 2017 | MA + XS | Yes/no/maybe mutual-match; talk starters |
| 16 | **Responsive-desire education and anticipation-building** (not frequency targets) | Basson; Loewenstein 2015 (backfire) | CC + RCT | Psychoeducation; affectionate daytime messages |
| 17 | **Transition-to-parenthood prevention** (coparenting teamwork) | Doss 2009; Family Foundations RCTs; BBH | LONG + RCT | Pregnancy and newborn track + perinatal screening routing |
| 18 | **Assurances and positivity in maintenance** | Stafford & Canary 1991 + replications | XS | Assurance prompts; future-together talk |
| 19 | **Shared plan and end-date certainty for LDRs** | CQ 2007 "Will it ever end?"; Dargie 2015 certainty | XS | "Our plan" card + review date + visit countdown |
| 20 | **Co-presence and shared mundane life at a distance** | Neustaedter & Greenberg 2012; Jiang & Hancock 2013 | QUAL + diary | Watch-together, open-line video nights, voice notes, time-zone overlap |
| 21 | **Reunion and transition preparation** | Stafford & Merolla 2007; Knobloch & Theiss | LONG + XS | Reunion module: routines, space, roles |
| 22 | **Secure-base goal support (Michelangelo)** | Feeney 2004; Drigotas 1999; Rusbult 2009 | LONG + experiment | Dreams board with "how to support me" |
| 23 | **Making cognitive labor visible and shareable; felt fairness** | Daminger 2019; Gillespie 2019 | QUAL + XS | Task ownership incl. noticing and monitoring; fairness reflection |
| 24 | **Benevolent forgiveness, conditional on amends** | Fincham 2004; Luchies 2010 | LONG + experiment | Apology-first flows; no forgiveness pressure |
| 25 | **Relationship awareness via media or reflection** (no skill drills needed) | Rogge 2013 (PAIR = PREP = CARE) | RCT | Film or story discussion prompts |
| 26 | **Optional structured turn-taking for hot topics** | Hawkins 2008 MRE; Stanley 2014 | MA + RCT | Floor token, paraphrase, time-out |
| 27 | **Phone-free connection time** | McDaniel & Coyne 2016; Roberts & David 2016 | XS | Together mode; app silences itself |
| 28 | **Savoring (relational and anticipatory)** | Froidevaux & Borelli 2023; Borelli model | LONG + CC | Relive-a-moment prompts; pre-visit savoring |
| 29 | **Faith-congruent practices for opted-in couples** (partner prayer, sanctification) and secular equivalents | Fincham 2010; Lambert 2010; Mahoney 2001/2003 | experiments + MA | Opt-in spiritual layer; intention-setting |
| 30 | **Minority-stress-aware, culturally adapted content** | LeBlanc 2015; Rostosky & Riggle 2017; Bejanyan 2015 | theory + XS | Inclusive defaults, outness controls, localized family content |

*Not ranked, because they are the precondition for all of the above: IPV-safe architecture and individual safety screening (Section 13).*

---

## (b) Popular ideas the evidence does NOT support (or that are contested or misused)

| Popular idea | Status | What the evidence actually says |
|---|---|---|
| **Everyone has one primary "love language"; matching predicts success** | Largely unsupported | Impett, Park & Muise 2024: people value all five; five factors aren't consistently found; matching doesn't reliably predict satisfaction. Responsiveness to *specific current preferences* is the defensible core (Mostova 2022, small) |
| **"Gottman can predict divorce with 90%+ accuracy"** | Misleading | In-sample, after-the-fact accuracy; collapses on cross-validation (Heyman & Slep 2001) |
| **The magic 5:1 ratio as a daily target** | Over-extended | Derived from conflict interactions. Not a validated threshold for everyday life. Often conflated with Losada's withdrawn 2.9:1 positivity ratio (Brown, Sokal & Friedman 2013) |
| **"69% of problems are unsolvable"** | Unverified number | Book and Institute figure without a traceable peer-reviewed derivation. The *concept* of perpetual problems is clinically useful and fits IBCT acceptance |
| **The 36 questions make people fall in love** | Misreported | Aron 1997 produced temporary closeness between strangers, not love |
| **Active listening / speaker–listener is the key to marriage** | Contested | Rare in natural conflict, and in one cohort not predictive (Gottman 1998). Awareness-only programs matched skills programs (Rogge 2013). Skills training has modest effects (Hawkins 2008) |
| **More sex = happier couple; aim for X times a week** | Unsupported causally | Curvilinear, flat beyond about once a week (Muise 2016). Doubling frequency on instruction slightly *lowered* happiness (Loewenstein 2015) |
| **Matched libido is necessary** | Unsupported | Discrepancy is near-universal. Matched desire per se didn't predict satisfaction (Kim 2020). Communal responsiveness matters (Day 2015) |
| **"Never go to bed angry" / resolve every fight immediately** | Not supported as a rule | Flooded partners need breaks. Many problems are perpetual and need ongoing dialogue, not immediate resolution |
| **Venting anger always helps / anger itself is toxic** | Oversimplified | Gottman 1998 found anger per se was not the predictor. Contempt, defensiveness and stonewalling cascades were. How anger is expressed matters |
| **Imago: we choose partners who resemble our parents, so healing childhood wounds via dialogue cures the marriage** | Unsupported theory; weak efficacy | RCT gains not clinically significant (Gehlert 2017). Workshop gains faded (Schmidt 2016) |
| **Long-distance relationships are doomed** | Unsupported | LDR quality equals or exceeds geographically close relationships in several samples (Kelmer 2013; Dargie 2015). The risk is the *reunion transition* and uncertainty, not distance per se |
| **Monitoring your partner's location or phone builds trust** | Contrary to evidence | Surveillance tracks insecurity (Fox & Warber 2014), perceived intrusion lowers satisfaction (Frontiers 2025), and it is a core coercive-control vector (Freed 2018) |
| **Forgiveness is always good for you** | Conditional | Without amends or partner agreeableness, forgiving erodes self-respect: the doormat effect (Luchies 2010) |
| **Religious couples never divorce / interfaith marriages fail** | Overstated | Small attendance–divorce association that shrinks with controls (Mahoney 2001). Interfaith risk is partly indirect (Lehrer & Chiswick 1993) |
| **Couples counseling is right for every troubled couple** | False with coercive control | Contraindicated where there is fear, coercive control or intimate terrorism. Requires separate screening (Bograd & Mederos 1999) |
| **Attachment-style labels explain your partner** | Misuse of science | Attachment is dimensional and relationship-specific. Pop labels become accusations |
| **Relationship "scores" or compatibility percentages** | No validated basis for app use | Self-report quality predicts *something* (Joel 2020) but individual-level prediction is weak, and scoring invites comparison and weaponization |

---

## (c) Clinical and ethical guardrails for a relationship app

### C1. Crisis routing

- **Detect and route, don't treat.** If a user discloses suicidal ideation, self-harm, abuse, fear of the partner, strangulation, sexual assault, threats to children or pets, or a homicide risk, the AI **halts coaching** and gives a warm, non-judgmental response. It shows **localized crisis resources** (e.g., 988 in the US, national DV hotlines and text lines, local emergency numbers, country-specific advocates) and offers safety-planning information. It never sends partner notifications, summaries or alerts to the other partner.
- **Human-reviewed protocols** for risk language, built with clinicians and DV advocates. Log minimal data, and store risk flags separately from couple-shared data.
- **No automated risk scores shown to users.** Use risk detection only to route.

### C2. Not replacing therapy

- State clearly, at onboarding and in context, that Attune is **education and connection support, not therapy or diagnosis**.
- **Escalation ladder:** high distress on check-ups, repeated unresolved gridlock, infidelity crises, perinatal depression, substance misuse or trauma symptoms trigger suggestions of couple or individual therapy, with directories and what to look for (evidence-based models: IBCT, EFT, BCT, CBCT). **Never suggest conjoint therapy when a safety flag exists.** Suggest individual support and advocates instead.
- AI must not role-play as a therapist, must not interpret a partner's psychology ("your partner is a narcissist"), and must not adjudicate who is right.

### C3. IPV safety by design

All of Section 13.3. Every new feature passes an **"abuser-in-the-loop" threat review**: how could a controlling partner use this to monitor, isolate, pressure, humiliate, or gather evidence against the other? Ship only if mitigated.

### C4. Consent

- **Granular, symmetric, revocable** consent for every shared surface (moods, journals, location, calendars, intimacy lists, AI summaries).
- **No covert features.** Nothing one partner can enable about the other without the other's knowledge and agreement.
- **Mutual-match only** for sexual preferences. "No" is never revealed.
- AI summaries of the couple or of conversations require **both** partners' opt-in, with each able to withdraw.
- Never require simultaneous vulnerable disclosure. Disclosure is always individually paced (**no forced vulnerability**).

### C5. Privacy and data

- **Private by default** for every individual entry (journals, check-in answers, screening, mood), even inside the couple space.
- **Data minimization.** No precise location, contacts scraping or message content mining for engagement or ads.
- **Unilateral leave-and-delete.** Either partner can exit, export and delete their data without the other's permission. Shared artifacts follow a published split policy.
- **Discretion features:** generic notifications, an optional neutral icon, quick-exit, re-authentication for sensitive areas, session and device visibility for the account owner.
- **Outness and sensitive-attribute protection** (sexual orientation, religion, health, fertility, neurodivergence). Never inferred, never surfaced outside the user's control.
- Regulatory alignment (e.g., GDPR special-category data for health, sex life, religion, orientation) and clear retention limits.

### C6. Anti-iatrogenic product rules

1. **No scorekeeping.** No chore points, favor ledgers, apology counts, bid-miss counts or positivity ratios.
2. **No comparison.** No "couples like you", percentile ranks or leaderboards.
3. **No streak guilt.** Rituals and check-ins are skippable without penalty. Prefer "welcome back" over "you broke your streak".
4. **No surveillance defaults.** Read receipts, last-seen, typing indicators and location are off unless mutually enabled.
5. **No sex targets or frequency tracking.**
6. **No diagnosis or labels** of partners (horsemen, attachment styles, personality disorders).
7. **No pressure to forgive, reconcile or stay.** The app's goal is *healthy* relationships, which sometimes means ending one safely.
8. **Authenticity.** AI-drafted messages are suggestions the user edits and sends. Never auto-send affection in a user's name, and be transparent about AI involvement.
9. **Engagement ethics.** Optimize for relationship outcomes and *time together offline*, not time in the app.
10. **Inclusive by default:** LGBTQ+, faith and no-faith, neurodivergent, disabled, older, LDR, military, commuter, collectivist and multigenerational families.

### C7. Evaluation

- Measure **outcomes, not engagement**: validated brief satisfaction measures, perceived responsiveness, and user-reported helpfulness, with an *option* for couples to participate. Run A/B tests ethically, with no harmful arms.
- Monitor **harm signals**: increased conflict after features, safety-flag rates, and reports of misuse.
- Consider an **external clinical and DV advisory board** to review features, AI prompts and crisis flows.

---

## Evidence gaps (where Attune should be humble)

- **App-delivered relationship interventions:** only a handful of RCTs (OurRelationship, ePREP), with high heterogeneity and small samples for apps specifically.
- **Long-distance relationships:** mostly young dating samples, cross-sectional, with little on married, older or international couples, and **no dedicated time-zone research found**.
- **Non-Western, low-income, LGBTQ+, neurodivergent couples:** under-represented across nearly all foundational studies.
- **Gottman Method therapy, Imago and Hold Me Tight:** thin independent RCT evidence.
- **Nostalgia, rituals of connection, shared meaning:** largely clinical constructs with limited direct testing.
- **Love languages:** about 10 studies, mostly small and cross-sectional.

---

## Reference list

*Grouped by section. URLs/DOIs are those located during this review. "(secondary)" = bibliographic details confirmed, findings read via abstract or secondary summary.*

### Gottman and conflict research
- Carrère, S., & Gottman, J. M. (1999). Predicting divorce among newlyweds from the first three minutes of a marital conflict discussion. *Family Process*. (UW summary: https://washington.edu/news/1999/09/27/first-three-minutes-of-discussion-about-on-going-area-of-marital-conflict-are-predictive-of-divorce-for-newlyweds) (secondary)
- Gottman, J. M. (1993). The roles of conflict engagement, escalation, and avoidance in marital interaction: A longitudinal view of five types of couples. *Journal of Consulting and Clinical Psychology, 61*, 6–15. (secondary)
- Gottman, J. M., Coan, J., Carrère, S., & Swanson, C. (1998). Predicting marital happiness and stability from newlywed interactions. *Journal of Marriage and the Family, 60*. UW summary https://www.washington.edu/news/1998/02/20/husbands-willingness-to-be-influenced-by-wife-share-power-are-key-predictors-of-newlywed-happiness-stability-uw-study-shows/ (secondary)
- Gottman, J. M., & Levenson, R. W. (1992). Marital processes predictive of later dissolution: Behavior, physiology, and health. *Journal of Personality and Social Psychology, 63*(2), 221. https://pubmed.ncbi.nlm.nih.gov/1403613/ doi:10.1037/0022-3514.63.2.221
- Gottman, J. M., & Levenson, R. W. (2000). The timing of divorce: Predicting when a couple will divorce over a 14-year period. *Journal of Marriage and Family, 62*. https://bpl.studentorg.berkeley.edu/docs/61-Timing%20of%20Divorce00.pdf
- Gottman Institute. An introduction to emotional bids and trust (86%/33% figures). https://www.gottman.com/blog/an-introduction-to-emotional-bids-and-trust/ [POP/institute]
- Gottman Institute. The Four Horsemen: The antidotes. https://www.gottman.com/blog/the-four-horsemen-the-antidote/ [CC]
- Gottman Institute. How stress can cause relationship dissatisfaction (flooding, 20-minute break). https://www.gottman.com/blog/how-stress-can-cause-relationship-dissatisfaction/ [CC]
- Gottman Institute. Research FAQ (response on prediction accuracy). https://www.gottman.com/about/research/faq/ [institute]
- Heyman, R. E., & Slep, A. M. S. (2001). The hazards of predicting divorce without crossvalidation. *Journal of Marriage and Family, 63*. Summary: https://scienceblog.com/?p=596422 (secondary)
- Shapiro, A. F., & Gottman, J. M. (2005). Effects on marriage of a psycho-communicative-educational intervention with couples undergoing the transition to parenthood, evaluation at 1-year post intervention. *Journal of Family Communication, 5*(1), 1–24. doi:10.1207/s15327698jfc0501_1 (secondary)
- Shapiro, A. F., Gottman, J. M., & Fink, B. C. Father involvement RCT of Bringing Baby Home (136 couples). https://pmc.ncbi.nlm.nih.gov/articles/PMC8136247 (secondary)
- Bringing Baby Home Down Under trial registration. ANZCTR ACTRN12623000102673. https://anzctr.org.au/ACTRN12623000102673.aspx
- Stanley, S. M., Bradbury, T. N., & Markman, H. J. (2000). Structural flaws in the bridge from basic research on marriage to interventions for couples. *Journal of Marriage and the Family, 62*. ProQuest abstract: https://www.proquest.com/docview/219750581 (secondary; authorship confirmed via citing paper PMC1828692)
- Example small Gottman therapy trial: Examining the effectiveness of Gottman couple therapy on improving marital adjustment and couples' intimacy. https://www.ncbi.nlm.nih.gov/pmc/articles/PMC6037577/
- APA Monitor (2013). On the critical positivity ratio critique and partial withdrawal. https://www.apa.org/monitor/2013/12/model-emotions

### EFT
- Beasley, C. C., & Ager, R. (2019). Emotionally focused couples therapy: A systematic review of its effectiveness over the past 19 years. *Journal of Evidence-Based Social Work, 16*(2). doi:10.1080/23761407.2018.1563013 (secondary)
- Johnson, S. M. (2008). *Hold Me Tight: Seven Conversations for a Lifetime of Love*. Little, Brown. (A.R.E. via secondary summaries) [CC]
- Johnson, S. M., Hunsley, J., Greenberg, L., & Schindler, D. (1999). Emotionally focused couples therapy: Status and challenges. *Clinical Psychology: Science and Practice, 6*(1), 67–79. https://iceeft.com/research-articles/johnson-s-hunsley-j-greenberg-l-schindler-d-1999-emotionally-focused/ (secondary)
- Kennedy, N. (2017). *Conversations for Connection: An Outcome Assessment of the Hold Me Tight Relationship Education Program for Couples* (Doctoral thesis, University of Ottawa). https://ruor.uottawa.ca/handle/10393/36059
- Rathgeber, M., Bürkner, P.-C., Schiller, E.-M., & Holling, H. (2019). The efficacy of emotionally focused couples therapy and behavioral couples therapy: A meta-analysis. *Journal of Marital and Family Therapy, 45*(3), 447–463. doi:10.1111/jmft.12336 https://pubmed.ncbi.nlm.nih.gov/29781200/
- Schrodt, P., Witt, P. L., & Shimkowski, J. R. (2014). A meta-analytical review of the demand/withdraw pattern of interaction and its associations with individual, relational, and communicative outcomes. *Communication Monographs, 81*(1), 28–58. doi:10.1080/03637751.2013.813632 (secondary)
- University of Amsterdam (2017). 'Hold me tight' relationship course shows promise for mild attachment problems. https://www.uva.nl/shared-content/uva/en/news/press-releases/2017/09/%E2%80%98hold-me-tight%E2%80%99-relationship-course-shows-promise-for-mild-attachment-problems.html
- Wiebe, S. A., Johnson, S. M., Burgess Moser, M., Dalgleish, T. L., Lafontaine, M.-F., & Tasca, G. A. (2017). Two-year follow-up outcomes in emotionally focused couple therapy. *Journal of Marital and Family Therapy, 43*(2), 227–244. doi:10.1111/jmft.12206
- 2024 meta-analysis of EFT (pre-post d = .93). *Couple and Family Psychology*. Abstract listing: https://ifp.nyu.edu/2024/meta-analyses-systematic-reviews/cfp0000233/ (secondary; authors not verified)

### IBCT and couple therapy outcomes
- Christensen, A., Atkins, D. C., Baucom, B., & Yi, J. (2010). Marital status and satisfaction five years following a randomized clinical trial comparing traditional versus integrative behavioral couple therapy. *Journal of Consulting and Clinical Psychology, 78*, 225–235. https://pmc.ncbi.nlm.nih.gov/articles/PMC4324126 (secondary)
- Christensen, A., Doss, B. D., & Jacobson, N. S. (2020). *Integrative Behavioral Couple Therapy: A Therapist's Guide to Creating Acceptance and Change* (2nd ed.). W. W. Norton. Review: https://tpcjournal.nbcc.org/book-review-integrative-behavioral-couple-therapy-a-therapists-guide-to-creating-acceptance-and-change-second-edition/
- Doss, B. D., Cicila, L. N., Salivar, E. G., Roddy, M. K., Nowlan, K. M., Benson, L. A., & Christensen, A. (2016). A randomized controlled trial of the web-based OurRelationship program. *Journal of Consulting and Clinical Psychology, 84*(4), 285–296. doi:10.1037/ccp0000063 (secondary)
- Doss, B. D., et al. (2020). OurRelationship in low-income couples. https://people.miami.edu/_assets-profiles/acad-as/pdf/psychology/brian-doss-et-al-2020-or-in-low-income-couples.pdf
- Roddy, M. K., Walsh, L. M., Rothman, K., Hatch, S. G., & Doss, B. D. (2020). Meta-analysis of couple therapy: Effects across outcomes, designs, timeframes, and other moderators. *Journal of Consulting and Clinical Psychology, 88*(7), 583–596. doi:10.1037/ccp0000514 https://pubmed.ncbi.nlm.nih.gov/32551734/
- Shadish, W. R., & Baldwin, S. A. (2003). Meta-analysis of MFT interventions. *Journal of Marital and Family Therapy, 29*(4). (secondary)

### PREP / MRE / skills
- Blanchard, V. L., Hawkins, A. J., Baldwin, S. A., & Fawcett, E. B. (2009). Investigating the effects of marriage and relationship education on couples' communication skills: A meta-analytic study. *Journal of Family Psychology*. (secondary)
- Fawcett, E. B., Hawkins, A. J., Blanchard, V. L., & Carroll, J. S. (2010). Do premarital education programs really work? A meta-analytic study. *Family Relations*. https://scholarsarchive.byu.edu/facpub/4230
- Hawkins, A. J., Blanchard, V. L., Baldwin, S. A., & Fawcett, E. B. (2008). Does marriage and relationship education work? A meta-analytic study. *Journal of Consulting and Clinical Psychology, 76*. https://pubmed.ncbi.nlm.nih.gov/18837590/
- Hawkins, A. J., Stanley, S. M., Cowan, P. A., Fincham, F. D., et al. (2013). A more optimistic perspective on government-supported marriage and relationship education programs for lower income couples. *American Psychologist*. (secondary)
- Johnson, M. D. (2012). Healthy marriage initiatives: On the need for empiricism in policy implementation. *American Psychologist, 67*(4), 296–308. https://researchconnect.suny.edu/en/publications/healthy-marriage-initiativeson-the-need-for-empiricism-in-policy-/
- Rogge, R. D., Cobb, R. J., Lawrence, E., Johnson, M. D., & Bradbury, T. N. (2013). Is skills training necessary for the primary prevention of marital distress and dissolution? A 3-year experimental study of three interventions. *Journal of Consulting and Clinical Psychology, 81*(6), 949–961. https://pubmed.ncbi.nlm.nih.gov/24060193/
- Stanley, S. M., Rhoades, G. K., & Markman, H. J. (2006). Sliding versus deciding: Inertia and the premarital cohabitation effect. *Family Relations, 55*(4), 499–509. doi:10.1111/j.1741-3729.2006.00418.x
- Stanley, S. M., Rhoades, G. K., Loew, B. A., Allen, E. S., Carter, S., Osborne, L. J., Prentice, D., & Markman, H. J. (2014). A randomized controlled trial of relationship education in the U.S. Army: 2-year outcomes. *Family Relations*. https://pmc.ncbi.nlm.nih.gov/articles/PMC4237282

### Imago
- Gehlert, N. C., Schmidt, C. D., Giegerich, V., & Luquet, W. (2017). Randomized controlled trial of Imago relationship therapy: Exploring statistical and clinical significance. *Journal of Couple & Relationship Therapy, 16*(3), 188–209. doi:10.1080/15332691.2016.1253518 https://collected.jcu.edu/couns-facpub/1
- Muro, L., Holliman, R., & Luquet, W. (2016). *Journal of Couple & Relationship Therapy, 15*(3), 232–246. (secondary)
- Schmidt, C. D., Luquet, W., & Gehlert, N. C. (2016). Evaluating the impact of the "Getting the Love You Want" couples workshop. *Journal of Couple & Relationship Therapy, 15*(1), 1–18. (secondary)

### Maintenance processes
- Algoe, S. B. (2012). Find, remind, and bind: The functions of gratitude in everyday relationships. *Social and Personality Psychology Compass, 6*(6), 455–469. (secondary)
- Algoe, S. B., Gable, S. L., & Maisel, N. C. (2010). It's the little things: Everyday gratitude as a booster shot for romantic relationships. *Personal Relationships*. (secondary)
- Aron, A., Melinat, E., Aron, E. N., Vallone, R. D., & Bator, R. J. (1997). The experimental generation of interpersonal closeness. *Personality and Social Psychology Bulletin, 23*(4), 363–377. doi:10.1177/0146167297234003
- Aron, A., Norman, C. C., Aron, E. N., McKenna, C., & Heyman, R. E. (2000). Couples' shared participation in novel and arousing activities and experienced relationship quality. *Journal of Personality and Social Psychology, 78*, 273–283.
- Conley, T. D., et al. (2009). Positive illusions across gay, lesbian and heterosexual couples. https://peplau.psych.ucla.edu/wp-content/uploads/sites/141/2017/07/Conley-et-al-2009.pdf
- Córdova, J. V., et al. (2014). The Marriage Checkup: A randomized controlled trial of annual relationship health checkups. *Journal of Consulting and Clinical Psychology, 82*, 592–604. doi:10.1037/a0037097 https://pmc.ncbi.nlm.nih.gov/articles/PMC4115001/
- Falconier, M. K., Jackson, J. B., Hilpert, P., & Bodenmann, G. (2015). Dyadic coping and relationship satisfaction: A meta-analysis. *Clinical Psychology Review, 42*, 28–46. doi:10.1016/j.cpr.2015.07.002
- Fincham, F. D., Beach, S. R. H., & Davila, J. (2004). Forgiveness and conflict resolution in marriage. *Journal of Family Psychology, 18*, 72–81. https://www.ffri.hr/~ibrdar/komunikacija/seminari/Fincham,%202004%20-%20Conflict%20resolution%20in%20marriage%20and%20forgiven.pdf
- Gable, S. L., Reis, H. T., Impett, E. A., & Asher, E. R. (2004). What do you do when things go right? The intrapersonal and interpersonal benefits of sharing positive events. *Journal of Personality and Social Psychology, 87*(2), 228–245. (secondary)
- Gable, S. L., et al. (2006). Responses to positive vs negative events in ~80 couples, predicting well-being and breakups two months later. *Journal of Personality and Social Psychology*. (secondary; co-authors and title not verified)
- Gordon, A. M., Impett, E. A., Kogan, A., Oveis, C., & Keltner, D. (2012). To have and to hold: Gratitude promotes relationship maintenance in intimate bonds. *Journal of Personality and Social Psychology, 103*(2), 257–274. doi:10.1037/a0028723 https://pubmed.ncbi.nlm.nih.gov/22642482
- The associations of dyadic coping and relationship satisfaction vary between and within nations: A 35-nation study (N = 7,973). *Frontiers in Psychology*. https://pmc.ncbi.nlm.nih.gov/articles/PMC4976670 (authors not verified)
- Impett, E. A., Gable, S. L., & Peplau, L. A. (2005). Giving up and giving in: The costs and benefits of daily sacrifice in intimate relationships. *Journal of Personality and Social Psychology, 89*, 327–344. doi:10.1037/0022-3514.89.3.327
- Joel, S., Eastwick, P. W., et al. (2020). Machine learning uncovers the most robust self-report predictors of relationship quality across 43 longitudinal couples studies. *PNAS, 117*(32), 19061–19071. doi:10.1073/pnas.1917036117
- Karney, B. R., & Bradbury, T. N. (1995). The longitudinal course of marital quality and stability: A review of theory, method, and research. *Psychological Bulletin, 118*, 3–34.
- Lewicki, R. J., Polin, B., & Lount, R. B., Jr. (2016). An exploration of the structure of effective apologies. *Negotiation and Conflict Management Research, 9*(2), 177–196. https://news.osu.edu/the-6-elements-of-an-effective-apology-according-to-science/
- Luchies, L. B., Finkel, E. J., McNulty, J. K., & Kumashiro, M. (2010). The doormat effect: When forgiving erodes self-respect and self-concept clarity. *Journal of Personality and Social Psychology, 98*, 734–749. https://eprints-gro.gold.ac.uk/5360/1/Luchies%20doormat%20effect%20JPSP%202010.pdf
- Murray, S. L., Holmes, J. G., & Griffin, D. W. (1996a). The benefits of positive illusions: Idealization and the construction of satisfaction in close relationships. *Journal of Personality and Social Psychology, 70*(1), 79–98.
- Murray, S. L., Holmes, J. G., & Griffin, D. W. (1996b). The self-fulfilling nature of positive illusions in romantic relationships. *Journal of Personality and Social Psychology, 71*(6), 1155–1180.
- Neff, L. A., & Karney, B. R. (2004). How does context affect intimate relationships? Linking external stress and cognitive processes within marriage. *Personality and Social Psychology Bulletin, 30*, 134–148.
- Neff, L. A., & Karney, B. R. (2009). Stress and reactivity to daily relationship experiences. https://sites.lifesci.ucla.edu/psych-marriagelab/wp-content/uploads/sites/213/2020/05/Neff__Karney_2009.220154529.pdf
- Reis, H. T., Clark, M. S., & Holmes, J. G. (2004). Perceived partner responsiveness as an organizing construct in the study of intimacy and closeness. In D. J. Mashek & A. Aron (Eds.), *Handbook of Closeness and Intimacy* (pp. 201–225). Erlbaum.
- Rusbult, C. E., Verette, J., Whitney, G. A., Slovik, L. F., & Lipkus, I. (1991). Accommodation processes in close relationships: Theory and preliminary empirical evidence. *Journal of Personality and Social Psychology, 60*(1), 53–78. doi:10.1037/0022-3514.60.1.53
- Zemp, M., et al. RCT of Couples Coping Enhancement Training formats. https://kops.uni-konstanz.de/handle/123456789/43742 (secondary)

### Love languages
- Bunt, S., & Hazelwood, Z. J. (2017). Walking the walk, talking the talk: Love languages, self-regulation, and relationship satisfaction. *Personal Relationships*. https://ifp.nyu.edu/2017/journal-article-abstracts/walking-walk-talking-talk-love-languages-self-regulation-relationship-satisfaction/
- Impett, E. A., Park, H. G., & Muise, A. (2024). Popular psychology through a scientific lens: Evaluating love languages from a relationship science perspective. *Current Directions in Psychological Science*. doi:10.1177/09637214231217663 https://www.utoronto.ca/news/little-evidence-linking-five-love-languages-healthy-relationships-researchers-say
- Mostova, O., Stolarski, M., & Matthews, G. (2022). I love the way you love me: Responding to partner's love language preferences boosts satisfaction in romantic heterosexual couples. *PLoS ONE, 17*(6), e0269429. https://pmc.ncbi.nlm.nih.gov/articles/PMC9216579/

### Sexuality
- Basson, R. (2000). Circular model of female sexual response (responsive desire). (Primary paper not retrieved; via secondary sources, e.g., https://ir.lib.uth.gr/xmlui/handle/11615/27088)
- Brotto, L. A., & Graham, C. A. (2021). Commentary on female sexual response models / DSM-5. https://eprints.soton.ac.uk/448412/
- Day, L. C., Muise, A., Joel, S., & Impett, E. A. (2015). To do it or not to do it? How communally motivated people navigate sexual interdependence dilemmas. *Personality and Social Psychology Bulletin*. https://www.utm.utoronto.ca/node/4673 (secondary)
- Frederick, D. A., Lever, J., Gillespie, B. J., & Garcia, J. R. (2017). What keeps passion alive? Sexual satisfaction is associated with sexual communication, mood setting, sexual variety, oral sex, orgasm, and sex frequency in a national U.S. study. *Journal of Sex Research*. doi:10.1080/00224499.2015.1137854
- Kim, J. J., Muise, A., Barranti, M., Mark, K. P., Rosen, N. O., Harasymchuk, C., & Impett, E. A. (2020). Are couples more satisfied when they match in sexual desire? https://experts.umn.edu/en/publications/are-couples-more-satisfied-when-they-match-in-sexual-desire-new-i/
- Lindau, S. T., et al. (2007). A study of sexuality and health among older adults in the United States. *New England Journal of Medicine, 357*(8), 762–774. doi:10.1056/NEJMoa067423 https://pubmed.ncbi.nlm.nih.gov/17715410/
- Loewenstein, G., Krishnamurti, T., Kopsic, J., & McDonald, D. (2015). Does increased sexual frequency enhance happiness? *Journal of Economic Behavior & Organization, 116*, 206–218. https://www.cmu.edu/dietrich/sds/docs/loewenstein/IncreasedSexualFrequency.pdf
- Mallory, A. B., Stanton, A. M., & Handy, A. B. (2019). Couples' sexual communication and dimensions of sexual function: A meta-analysis. *Journal of Sex Research, 56*(7). https://pmc.ncbi.nlm.nih.gov/articles/PMC6699928/
- Miller, E., et al. (2010). Reproductive coercion and IPV among family-planning clinic attendees (N = 1,278). *Contraception*. Summary: https://www.ucdavis.edu/news/%E2%80%98reproductive-coercion%E2%80%99-often-accompanied-physical-or-sexual-violence-study-finds (secondary)
- Muise, A., Schimmack, U., & Impett, E. A. (2016). Sexual frequency predicts greater well-being, but more is not always better. *Social Psychological and Personality Science*. https://journals.sagepub.com/doi/abs/10.1177/1948550615616462
- Muise, A., & colleagues. Sexual communal strength summaries: In-Mind, "Keeping the spark alive: The role of sexual communal motivation." https://in-mind.org/article/keeping-the-spark-alive-the-role-of-sexual-communal-motivation ; SPSP https://spsp.org/news-center/character-context-blog/fan-flame-maintain-spark (secondary)

### Long-distance
- Dargie, E., Blair, K. L., Goldfinger, C., & Pukall, C. F. (2015). Go long! Predictors of positive relationship outcomes in long-distance dating relationships. *Journal of Sex & Marital Therapy, 41*(2), 181–202. doi:10.1080/0092623X.2013.864367
- Froidevaux, N. M., Borelli, J. L., et al. (2023). Anticipatory relational savoring during deployment. https://aub.ie/MilitaryREACH-Froidevaux2023 (secondary)
- Jiang, L. C., & Hancock, J. T. (2013). Absence makes the communication grow fonder: Geographic separation, interpersonal media, and intimacy in dating relationships. *Journal of Communication, 63*, 556–577. https://sml.stanford.edu/publications/2013/absence-makes-communication-grow-fonder-geographic-separation-interpersonal-media
- Kelmer, G., Rhoades, G. K., Stanley, S., & Markman, H. J. (2013). Relationship quality, commitment, and stability in long-distance relationships. *Family Process, 52*, 257–270. (secondary)
- Knobloch, L. K., & Theiss, J. A. (2012). Experiences of U.S. military couples during the post-deployment transition: Applying the relational turbulence model. *Journal of Social and Personal Relationships*. https://reachfamilies.umn.edu/node/4885
- Knobloch, L. K., Basinger, E. D., & Theiss, J. A. (2018). Relational turbulence and perceptions of partner support during reintegration after military deployment. *Journal of Applied Communication Research*. https://aub.ie/MilitaryREACH-Knobloch18TRIP
- Lindemann, D. J. (2019). *Commuter Spouses: New Families in a Changing World*. Cornell University Press. https://paw.princeton.edu/podcasts/pawcast-sociologist-danielle-lindemann-02-commuter-spouses
- Neustaedter, C., & Greenberg, S. (2012). Intimacy in long-distance relationships over video chat. *Proceedings of CHI 2012*. https://grouplab.cpsc.ucalgary.ca/grouplab/uploads/Publications/Publications/2012-IntimacyInLDR.CHI.pdf
- Stafford, L., & Canary, D. J. (1991). Maintenance strategies and romantic relationship type, gender and relational characteristics. *Journal of Social and Personal Relationships, 8*, 217–242. doi:10.1177/0265407591082004
- Stafford, L., & Merolla, A. J. (2007). Idealization, reunions, and stability in long-distance dating relationships. *Journal of Social and Personal Relationships, 24*(1), 37–54. (secondary)
- Theiss, J. A., & Knobloch, L. K. (2013, *Journal of Communication*; 2014, *Communication Research*). Relational turbulence and the post-deployment transition. https://reachfamilies.umn.edu/sites/default/files/rdoc/Theiss_2013.pdf ; https://reachfamilies.umn.edu/sites/default/files/rdoc/Theiss_2014.pdf
- "Will it ever end?": A (re)examination of uncertainty in college student long-distance dating relationships. (2007). *Communication Quarterly, 55*(4). https://www.tandfonline.com/doi/full/10.1080/01463370701658002 (author not verified in this review)
- Dual-career commuter couples / Bunker et al. (1992) via secondary: https://www.frontiersin.org/journals/psychology/articles/10.3389/fpsyg.2022.860717/pdf

### Technology
- Chatterjee, R., Doerfler, P., Orgad, H., Havron, S., Palmer, J., Freed, D., Levy, K., Dell, N., McCoy, D., & Ristenpart, T. (2018). The spyware used in intimate partner violence. *IEEE Symposium on Security and Privacy*, 441–458. https://www.cs.cornell.edu/~rahul/papers/IPV_Spyware.pdf
- Daminger, A. (2019). The cognitive dimension of household labor. *American Sociological Review, 84*(4), 609–633. doi:10.1177/0003122419859007 https://inequality.hks.harvard.edu/publications/cognitive-dimension-household-labor
- Effectiveness of digital interventions on relationship satisfaction among couples: A systematic review and meta-analysis. (2025). *BMC Psychology*. doi:10.1186/s40359-025-03444-y (secondary; authors not verified)
- Fox, J., & Warber, K. M. (2014). Social networking sites in romantic relationships: Attachment, uncertainty, and partner surveillance on Facebook. *Cyberpsychology, Behavior, and Social Networking, 17*, 3–7.
- Freed, D., Palmer, J., Minchala, D., Levy, K., Ristenpart, T., & Dell, N. (2017). Digital technologies and intimate partner violence: A qualitative analysis with multiple stakeholders. *PACM HCI (CSCW)*. https://dfreed.me/publications/
- Freed, D., Palmer, J., Minchala, D., Levy, K., Ristenpart, T., & Dell, N. (2018). "A Stalker's Paradise": How intimate partner abusers exploit technology. *Proceedings of CHI 2018*. doi:10.1145/3173574.3174241 https://www.classes.cs.uchicago.edu/archive/2020/winter/20370-1/readings/Stalkers.pdf
- Gillespie, B. J., Peterson, G., & Lever, J. (2019). Gendered perceptions of fairness in housework and shared expenses: Implications for relationship satisfaction and sex frequency. *PLoS ONE*. https://www.ncbi.nlm.nih.gov/pmc/articles/PMC6426245/
- Leitão, R. (2019). Anticipating smart home security and privacy threats with survivors of intimate partner abuse. *Proceedings of DIS 2019*. doi:10.1145/3322276.3322366
- Location-sharing apps and perceived intrusion (2025). *Frontiers in Human Dynamics*. https://www.frontiersin.org/journals/human-dynamics/articles/10.3389/fhumd.2025.1553619/full (authors not verified)
- McDaniel, B. T., & Coyne, S. M. (2016). "Technoference": The interference of technology in couple relationships and implications for women's personal and relational well-being. *Psychology of Popular Media Culture, 5*, 85–98.
- Paired app mixed-methods evaluation. https://pmc.ncbi.nlm.nih.gov/articles/PMC12001865/
- PenzeyMoog, E. (2021). *Design for Safety*. A Book Apart. https://abookapart.com/products/design-for-safety
- Psychological Science (2022). Housework unfairness, appreciation, and relationship satisfaction during COVID-19. doi:10.1177/09567976221081872 https://www.psychologicalscience.org/journals/psychological-science/09567976221081872/ (secondary)
- Roberts, J. A., & David, M. E. (2016). My life has become a major distraction from my cell phone: Partner phubbing and relationship satisfaction among romantic partners. *Computers in Human Behavior, 54*, 134–141.
- Schade, L. C., Sandberg, J., Bean, R., Busby, D., & Coyne, S. (2013). Using technology to connect in romantic relationships: Effects on attachment, relationship satisfaction, and stability in emerging adults. *Journal of Couple & Relationship Therapy, 12*, 314–338. https://scholarsarchive.byu.edu/facpub/2343
- Troitskaya, O., et al. (2022). Mobile application for couple relationships: Results of a pilot effectiveness study. *Family Process*. doi:10.1111/famp.12733

### Religion
- Fincham, F. D., Lambert, N. M., & Beach, S. R. H. (2010). Faith and unfaithfulness: Can praying for your partner reduce infidelity? *Journal of Personality and Social Psychology*. (secondary)
- Lambert, N. M., Fincham, F. D., Stillman, T. F., Graham, S. M., & Beach, S. R. H. (2010). Motivating change in relationships: Can prayer increase forgiveness? *Psychological Science*. doi:10.1177/0956797609355634
- Lambert, N. M., et al. (2013). Shifting toward cooperative tendencies and forgiveness: How partner-focused prayer transforms motivation. *Personal Relationships*. https://scholars.uky.edu/en/publications/shifting-toward-cooperative-tendencies-and-forgiveness-how-partne/
- Lehrer, E. L., & Chiswick, C. U. (1993). Religion as a determinant of marital stability. *Demography, 30*(3), 385–404. doi:10.2307/2061647
- Mahoney, A., Pargament, K. I., Tarakeshwar, N., & Swank, A. B. (2001). Religion in the home in the 1980s and 1990s: A meta-analytic review and conceptual analysis of links between religion, marriage, and parenting. *Journal of Family Psychology, 15*, 559–596. doi:10.1037/0893-3200.15.4.559
- Mahoney, A., Pargament, K. I., Murray-Swank, A., & Murray-Swank, N. (2003). Religion and the sanctification of family relationships. *Review of Religious Research, 44*, 220–236.
- BGSU Psychology of Spirituality and Family: sanctification findings (incl. Pomerleau, Wong & Mahoney 2015 meta-analysis). https://www.bgsu.edu/arts-and-sciences/psychology/graduate-program/clinical/the-psychology-of-spirituality-and-family/research-findings/marriage-couples/sanctification.html

### Life-context challenges
- Bejanyan, K., Marshall, T. C., & Ferenczi, N. (2015). Associations of collectivism with relationship commitment, passion, and mate preferences: Opposing roles of parental influence and family allocentrism. *PLoS ONE, 10*(2), e0117374. doi:10.1371/journal.pone.0117374
- Büyükcan-Tetik, A., et al. (2017). Perceived grief similarity in bereaved couples. *Journal of Family Psychology*. (via search summary)
- Carstensen, L. L., Gottman, J. M., & Levenson, R. W. (1995). Emotional behavior in long-term marriage. *Psychology and Aging*. https://bpl.studentorg.berkeley.edu/docs/47-Emotional%20Behavior95.pdf
- Dementia couple-based intervention RCT (108 couples). https://pmc.ncbi.nlm.nih.gov/articles/PMC7317469
- Doss, B. D., Rhoades, G. K., Stanley, S. M., & Markman, H. J. (2009). The effect of the transition to parenthood on relationship quality: An 8-year prospective study. *Journal of Personality and Social Psychology, 96*(3), 601–619. doi:10.1037/a0013969
- Feinberg, M. E., et al. (2016). Couple-focused prevention at the transition to parenthood, a randomized trial. *Prevention Science*. doi:10.1007/s11121-016-0674-z ; Blueprints: https://blueprintsprograms.org/programs/441999999/family-foundations
- LeBlanc, A. J., Frost, D. M., & Wight, R. G. (2015). Minority stress and stress proliferation among same-sex and other marginalized couples. *Journal of Marriage and Family, 77*(1), 40–59. doi:10.1111/jomf.12160 https://pmc.ncbi.nlm.nih.gov/articles/PMC4316376
- Levenson, R. W., Carstensen, L. L., & Gottman, J. M. (1993). Long-term marriage: Age, gender, and satisfaction. *Psychology and Aging, 8*. https://bpl.studentorg.berkeley.edu/docs/43-Long-Term%20Marriage93.pdf
- Monson, C. M., Fredman, S. J., Macdonald, A., Pukay-Martin, N. D., Resick, P. A., & Schnurr, P. P. (2012). Effect of cognitive-behavioral couple therapy for PTSD: A randomized controlled trial. *JAMA, 308*(7), 700–709. doi:10.1001/jama.2012.9307
- Orbuch, T. L., Bauermeister, J. A., Brown, E., & McKinley, B.-D. (2013). Early family ties and marital stability over 16 years. *Family Relations*. (secondary; press coverage via https://www.bostonglobe.com/ideas/2013/11/17/the-weird-science-laws/oxS966evzs9ymeZrWKDlEP/story.html)
- Peterson, B. D., Newton, C. R., Rosen, K. H., et al. (2006). Coping processes of couples experiencing infertility (420 couples). *Family Relations*; Peterson et al. (2008), partner coping, *Human Reproduction*. Review: https://www.ncbi.nlm.nih.gov/pmc/articles/PMC4877237/ (secondary)
- Rostosky, S. S., & Riggle, E. D. B. (2017). Same-sex relationships and minority stress. https://scholars.uky.edu/en/publications/same-sex-relationships-and-minority-stress/ ; Same-sex couple relationship strengths: A review and synthesis. *Psychology of Sexual Orientation and Gender Diversity, 4*. https://scholars.uky.edu/en/publications/same-sex-couple-relationship-strengths-a-review-and-synthesis-of-/
- SAMHSA (2014). *SAMHSA's Concept of Trauma and Guidance for a Trauma-Informed Approach* (HHS Publication No. SMA 14-4884). https://youth.gov/feature-article/samhsas-concept-trauma-and-guidance-trauma-informed-approach
- Wymbs, B. T., Canu, W. H., Sacchetti, G. M., et al. (2021). Adult ADHD and romantic relationships: What we know and what we can do to help. *Journal of Marital and Family Therapy, 47*(3), 664–681. doi:10.1111/jmft.12475 (secondary)
- Yew, R. Y., Hooley, M., & Stokes, M. A. (2023). Relationship satisfaction in autistic and non-autistic partners in long-term relationships (title approximate). *Autism*. https://journals.sagepub.com/doi/xml/10.1177/13623613231160244
- Autistic adults' relationship satisfaction by partner neurotype (2024). *Autism in Adulthood*. doi:10.1089/aut.2024.0124 (authors not verified)

### IPV and coercive control
- Bograd, M., & Mederos, F. (1999). Battering and couples therapy: Universal screening and selection of treatment modality. *Journal of Marital and Family Therapy*. https://anrows.intersearch.com.au/anrowsjspui/handle/1/13600 (secondary)
- Campbell, J. C., et al. (2003). Danger Assessment / risk factors for intimate partner homicide. *NIJ Journal* (title paraphrased). https://www.ojp.gov/pdffiles1/jr000250e.pdf
- Glass, N., et al. (2008). Case-control study of non-fatal strangulation as a risk factor for (attempted) homicide (title paraphrased). https://pmc.ncbi.nlm.nih.gov/articles/PMC2573025/
- Johnson, M. P. (2008). *A Typology of Domestic Violence: Intimate Terrorism, Violent Resistance, and Situational Couple Violence*. Northeastern University Press. https://ojp.gov/ncjrs/virtual-library/abstracts/typology-domestic-violence-intimate-terrorism-violent-resistance
- Stark, E. (2007). *Coercive Control: How Men Entrap Women in Personal Life*. Oxford University Press.
- Stith, S. M., McCollum, E. E., & Rosen, K. H. Domestic Violence Focused Couples Treatment (program description and outcomes). https://www.continuum.militaryfamilies.psu.edu/program/Couples%20Therapy%20for%20Domestic%20Violence%3A%20Finding%20Safe%20Solutions ; *Couples Therapy for Domestic Violence: Finding Safe Solutions* (APA, 2011) https://www.apa.org/pubs/books/4317268 (secondary)
- US Preventive Services Task Force (2018). Intimate partner violence, elder abuse, and abuse of vulnerable adults: Screening (superseded by 2025 update). https://www.uspreventiveservicestaskforce.org/uspstf/recommendation/intimate-partner-violence-and-abuse-of-elderly-and-vulnerable-adults-screening-october-2018
- Walby, S., & Towers, J. (2018). Untangling the concept of coercive control: Theorizing domestic violent crime. https://researchonline.ljmu.ac.uk/id/eprint/9449/

### Goals, meaning, savoring
- Drigotas, S. M., Rusbult, C. E., Wieselquist, J., & Whitton, S. W. (1999). Close partner as sculptor of the ideal self: Behavioral affirmation and the Michelangelo phenomenon. *Journal of Personality and Social Psychology*. (via secondary reviews)
- Feeney, B. C. (2004). A secure base: Responsive support of goal strivings and exploration in adult intimate relationships. *Journal of Personality and Social Psychology, 87*, 631–648.
- Rusbult, C. E., Finkel, E. J., & Kumashiro, M. (2009). The Michelangelo phenomenon. *Current Directions in Psychological Science*. https://eprints-gro.gold.ac.uk/5363/1/Michelangelo%20Phenomenon%20Rusbult%20et%20al%202009%20Current%20Directions.pdf
- Rusbult, C. E., Kumashiro, M., Kubacka, K. E., & Finkel, E. J. (2009). "The part of me that you bring out": Ideal similarity and the Michelangelo phenomenon. *Journal of Personality and Social Psychology, 96*, 61–82. https://eprints-gro.gold.ac.uk/5364/1/Rusbult%20et%20al%202009%20ideal%20similarity.pdf

### Breakups
- Larson, G. M., & Sbarra, D. A. (2015). Participating in research on romantic breakups promotes emotional recovery via changes in self-concept clarity. *Social Psychological and Personality Science*. doi:10.1177/1948550614563085
- Sbarra, D. A., & Emery, R. E. (2005). The emotional sequelae of nonmarital relationship dissolution: Analysis of change and intraindividual variability over time. *Personal Relationships, 12*(2), 213–232. https://experts.arizona.edu/en/publications/the-emotional-sequelae-of-nonmarital-relationship-dissolution-ana/
- Sbarra, D. A. (2006). Survival analysis of sadness and anger recovery after nonmarital dissolution (title paraphrased). *Personality and Social Psychology Bulletin*. doi:10.1177/0146167205280913

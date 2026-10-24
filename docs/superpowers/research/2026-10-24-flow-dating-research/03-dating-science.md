# 03 — Dating science: what predicts a good match and a lasting bond, and what helps or harms people while dating

Prepared 2026-10-24 by researcher 03 for the Flow + Dating programme (see `BRIEF.md`). Audience: owner, Dating Mode spec authors, safety and clinical reviewers.

This document builds on the 2026-10-16 couples research and does not repeat it. `02` means `docs/superpowers/research/2026-10-16-couples-research/02-relationship-science.md`; `06` means `06-synthesis-roadmap.md` in the same folder. `SPEC` means `lib/architecture/DATING_MODE_SPEC.md`.

---

## 0. The short version

1. **Nobody can predict, from profiles, which two strangers will click.** Machine learning on 100+ self-report measures predicted how much a person likes people in general and how liked they are in general, but not who likes whom (Joel, Eastwick & Finkel 2017). A seven-month follow-up found the same (Eastwick et al. 2023). What predicts a lasting bond is how partners come to perceive each other after meeting: commitment, appreciation, responsiveness and satisfaction (Joel et al. 2020, 43 datasets). **So a curated-introductions product earns its keep by filtering for feasibility and safety, then helping two people meet soon and respond well to each other. Claiming to predict fit is not where its value lies.**
2. **Similarity matters for values and life plans, not for personality.** Partners resemble each other strongly on political and religious attitudes, education, substance use and age, but barely on personality (extraversion r = .08; Horwitz et al. 2023). Personality similarity adds almost nothing to satisfaction (Dyrenforth et al. 2010). The current SPEC §6.1 ranks pairs by attachment, communication and conflict-style "distance", which this evidence does not support.
3. **Fewer options make for better choices.** Large choice sets push people towards quick, surface judgements (Lenton & Francesconi 2010). They also lower satisfaction with whoever is chosen (D'Angelo & Toma 2017) and build a "rejection mind-set" within a single session (Pronk & Denissen 2020). Compulsive swiping is the pathway that links app use to harm (Thomas et al. 2023). A few introductions a day is defensible; an endless feed is not.
4. **Dating apps are associated with worse body image and more compulsive use, and the link with mood is weaker.** Three syntheses from 2025–26 agree on this (Bowman et al. 2025; Cela & Wood 2026; Sharabi et al. 2026). Almost all the underlying studies are cross-sectional. The mood association appeared only in WEIRD samples, so evidence for Ghana is essentially absent.
5. **Safety risk concentrates at the first in-person meeting and when contact moves off the platform.** Dating-app-facilitated sexual assaults cluster at the first meeting, often at the perpetrator's home and while the victim is impaired (Rowse et al. 2020). They are more violent than other acquaintance assaults (Valentine et al. 2022). Chatting across several platforms raises risk (AIC 2024). Romance fraud moves victims to WhatsApp or Telegram (FTC 2023). In Ghana, LGBTQ people have been lured through dating sites and social media and then beaten or blackmailed (HRW 2018). Parliament passed a new anti-LGBTQ+ bill in May 2026; at last report it was awaiting the President's assent.

---

## 1. How this was researched

**Sources.**
- Peer-reviewed papers, located through web search and checked against abstracts, publisher pages, PMC, institutional repositories, and Crossref metadata (`api.crossref.org/works/<doi>`).
- Official data: Pew Research Center, the US FTC, and the Australian Institute of Criminology (AIC).
- NGO documentation: Human Rights Watch.
- The 2026-10-16 couples research, wherever it already covers a topic.

**Verification tags** (used in the text and the reference list):

| Tag | Meaning |
|---|---|
| **[V]** | Findings checked this session against an abstract, publisher or repository page, or an official page |
| **[V-cite]** | Bibliographic record confirmed this session through Crossref; findings stated from prior knowledge of the paper, not re-read |
| **[K]** | Prior knowledge, not re-verified this session; treat as provisional until checked |
| **[02]** / **[06]** | Taken from the 2026-10-16 research, which verified it then |
| **(secondary)** | Only a press or secondary summary was reachable |

**Evidence grades** follow the brief:
- **Strong:** meta-analysis, large RCT or large dataset.
- **Moderate:** peer-reviewed study, large survey or official policy.
- **Weak:** single small study, press or vendor claim.
- **Anecdote.**

A grade describes the evidence behind the operational claim, not the prestige of the venue.

**Limits (please read).**
- **Search budget.** The web-search budget, shared across all parallel researchers, ran out about two-thirds of the way through. The rest was verified through direct fetches of known primary pages and Crossref records. Claims that could not be re-verified are tagged [K].
- **Full texts.** Most papers were read at abstract level. Effect sizes are quoted only where a primary or repository source gave them.
- **Ghana-specific research.** Peer-reviewed work on Ghanaian dating, courtship and dating apps could not be located this session. It is the largest evidence gap here. Statements about Ghanaian marriage norms rest on law and secondary sources, graded Weak or Moderate.
- **Where the evidence comes from.** Almost all dating-app research comes from US, European and Australian samples, mostly heterosexual and under 35.
- **Mental-health studies** are overwhelmingly cross-sectional, so they show association, not causation.

---

## 2. Findings

### 2.1 Can compatibility be predicted before two people meet?

| Claim | Evidence | Grade |
|---|---|---|
| Matching-site algorithms rely on information that is easy to collect (personality and attitude similarity), not on what predicts relationship wellbeing. Profiles are a "feeble substitute" for meeting when it comes to judging chemistry, and browsing many profiles encourages a shopping mind-set. | Finkel, Eastwick, Karney, Reis & Sprecher 2012, *Psychological Science in the Public Interest* 13(1):3–66 [V] | Strong (expert critical review) |
| Random forests over 100+ pre-date self-report traits and preferences, in two speed-dating samples with 4-minute dates, predicted **actor** variance (how much a person desires others in general, 4–18%) and **partner** variance (how desired they are in general, 7–27%). They could **not** predict the relationship-specific part, meaning who desires whom. | Joel, Eastwick & Finkel 2017, *Psychological Science* 28(10):1478–1489 [V] | Moderate (two samples, about 350 people; strong method) |
| A preregistered study of 208 singles rating 1,065 real potential partners (7,179 data points over seven months) found main effects: sociosexuality, sex drive, perceived attractiveness and excitement, attachment-related proximity seeking, and **perceived interest from the other person**. Support for perceiver-by-target "compatibility" was only modest, and there was **no support for ideal-partner-preference matching**. | Eastwick, Joel, Carswell, Molden, Finkel & Blozis 2023, *European Journal of Personality* 37(3):276–312 [V] | Moderate |
| Across 43 dyadic longitudinal datasets from 29 labs (11,000+ couples), the strongest predictors of relationship quality were **relationship-specific perceptions**: perceived partner commitment, appreciation, sexual satisfaction, perceived partner satisfaction, and conflict. Relationship-specific variables explained up to 45% of variance at baseline. **Individual differences and partner reports added nothing beyond a person's own relationship perceptions. Change over time was largely unpredictable.** The top individual-difference predictors (life satisfaction, negative affect, depression, attachment avoidance and anxiety) predict a person's *own* relationship quality, not fit. | Joel et al. 2020, *PNAS* 117(32):19061–19071 [V]; 02 §0.3 #1 | Strong |
| Partners correlate most on **attitudes, education and substance use**: political values r = .58 (meta-analytic mean); religious attitudes, education and drinking or smoking are also high. They correlate least on **psychological traits**: extraversion r = .08. In UK Biobank (up to 79,074 couples), birth year r = .87. Only about 3% of traits showed any tendency towards opposites. | Horwitz, Balbona, Paulich & Keller 2023, *Nature Human Behaviour* 7:1568–1583 [V] | Strong |
| In three national samples of married couples (Australia 5,278; UK 6,554; Germany 11,418), a person's **own** personality explained about 6% of their relationship satisfaction. **Couple similarity added no consistent prediction.** | Dyrenforth, Kashy, Donnellan & Lucas 2010, *JPSP* 99(4):690–702 [V] | Strong |
| A meta-analysis of 313 studies (460 effects) found that both actual similarity (r = .47) and perceived similarity (r = .39) relate to attraction. Secondary summaries add that actual similarity's effect fades in existing relationships while perceived similarity holds, but I could not confirm that moderator claim in the primary source this session. | Montoya, Horton & Kirchner 2008, *Journal of Social and Personal Relationships* 25(6):889–922 [V; moderator (secondary)] | Strong (main effect) |
| In live speed dating, **perceived** similarity predicted romantic liking and **actual** similarity did not. | Tidwell, Eastwick & Finkel 2013, *Personal Relationships* 20(2):199–215 [V] | Moderate |
| Stated ideal-partner preferences did **not** predict whom people were drawn to after meeting. The textbook sex differences (men value looks, women value earning prospects) appeared in stated ideals but not in actual interest, and this was replicated. | Eastwick & Finkel 2008, *JPSP* 94(2):245–264 [V]; Selterman, Chagnon & MacKinnon 2015, *SAGE Open* [V] | Moderate |
| Ideal preferences predict satisfaction modestly *within established* relationships. A 43-country registered report (N = 10,358) found significant preference-matching effects, but the trait-level effects were tiny (average β ≈ .04). | Eastwick, Luchies, Finkel & Hunt 2014, *Psychological Bulletin* 140:623–665 [V (secondary for findings)]; Psychological Science Accelerator registered report [V (secondary); venue not confirmed] | Strong / Moderate |
| Agreement on who is attractive or desirable is high at first meeting and falls towards zero as people get to know each other. Couples who were acquainted longer before dating are less matched on attractiveness. | Eastwick & Hunt 2014, *JPSP* 106(5):728–751 [V (secondary)]; Hunt, Eastwick & Finkel 2015, *Psychological Science* 26(7) [V (APS release)] | Moderate |
| **Complementarity** ("opposites attract", "secure fits anxious") has no robust support. Assortment is positive for most traits (Horwitz 2023), and attachment effects in dating couples are mostly the person's *own* anxiety predicting their own later relationship quality. | Horwitz et al. 2023 [V]; Holland, Fraley & Roisman 2012, *Personal Relationships* 19(2):234–246 [V] | Strong (against complementarity) |
| **Matching hypothesis.** People pursue partners about 25% more desirable than themselves, and the reply rate falls sharply as the desirability gap grows. A desirability hierarchy emerges by itself on open platforms. | Bruch & Newman 2018, *Science Advances* 4(8) [V] | Strong (large dataset) |
| Drawing attention to shared interests increased willingness to date across racial lines. | Fisman, Iyengar, Kamenica & Simonson, "Racial preferences in dating" (working paper / *Review of Economic Studies* 2008) [V (secondary)] | Moderate |

**What it means for a curated-introductions product.**
- **Fit cannot be predicted before meeting, and saying otherwise is false precision.** SPEC §6.3 already forbids percentages, which is right. But SPEC §6.1–6.2 still scores "symmetric component distances" on attachment, communication-style and conflict-style dimensions. The evidence above says that distance has no demonstrated predictive value: personality and attachment similarity add roughly nothing (Dyrenforth 2010; Joel 2017; Eastwick 2023).
- **Profile data is useful for three things:**
  - **Feasibility filters:** age, location, intention, children, faith importance.
  - **Value overlaps** on dimensions where real couples assort strongly (Horwitz 2023).
  - **Honest "you both said…" overlaps,** which raise *perceived* similarity. Perceived similarity, not actual similarity, predicts liking at a first meeting (Tidwell 2013).
- **Attachment, communication and conflict-style results belong in self-facing growth** (Joel 2020: they predict a person's own relationship quality). They should not be used to rank strangers.

### 2.2 Speed dating, first meetings and what increases mutual liking

| Claim | Evidence | Grade |
|---|---|---|
| In a randomised speed-dating experiment, women were more selective than men as the number of partners grew; men's selectivity did not change with group size. Women weighted intelligence and race more, men weighted attractiveness more. Press coverage notes a stated-versus-revealed gap. | Fisman, Iyengar, Kamenica & Simonson 2006, *Quarterly Journal of Economics* 121(2):673–697 [V] | Moderate |
| People who asked more questions, especially **follow-up** questions, were better liked. In speed dating (110 people, 2,000+ dates), follow-up question rate predicted getting a second date. Responsiveness explained the effect, and people did **not** expect questions to increase liking. | Huang, Yeomans, Brooks, Minson & Gino 2017, *JPSP* 113(3):430–452 [V] | Moderate–Strong |
| Forty-five minutes of escalating, reciprocal self-disclosure (Fast Friends / "36 questions") produced more closeness between strangers than small talk. Matching on attitudes, expecting to be liked, or setting an explicit closeness goal made no difference. It was never shown to make people fall in love. | Aron, Melinat, Aron, Vallone & Bator 1997, *PSPB* 23(4):363–377 [V]; 02 §6.5 | Strong for short-term closeness |
| **Taking turns** at disclosure produced more liking than one person disclosing while the other listened. | Sprecher, Treger, Wondra, Hilaire & Wallpe 2013, *Journal of Experimental Social Psychology* 49:860–866 [V (secondary for findings)] | Moderate |
| First interactions by **text** produced less liking than audio, video or face-to-face. **Video added little over audio.** | Sprecher 2014, *Computers in Human Behavior* 31:190–197 [V (listing and thesis summary); volume from prior knowledge] | Moderate |
| Feeling chosen *specifically* is reciprocated, while indiscriminate interest is not. Speed daters who liked everyone were liked less. | Eastwick, Finkel, Mochon & Ariely 2007, *Psychological Science* 18(4):317–319 [K] | Moderate |
| In a national sample (n = 433), the amount of online contact before meeting had an **inverted-U** relation with intimacy, relational outcomes and forecasts for the relationship. The authors put the turning point at about **17–23 days** by visual inspection. | Ramirez, Sumner, Fleuriet & Cole 2015, *Journal of Computer-Mediated Communication* 20(1):99–114 [V] | Moderate |
| First-date success could be predicted from features of online impressions and relational dynamics (n = 186 before, 94 after). Perceiving the *other* person as deceptive lowered first-date success. | Sharabi & Caughlin 2017, *Personal Relationships* 24(2):370–391 [V]; Sharabi & Caughlin 2019, *New Media & Society* [V (secondary)] | Moderate |
| People who believed the matching process worked had better first dates. Outcomes were best when the match was also genuinely good. | Sharabi 2021, *Communication Research* 48(7):931–952 [V (author summary)] | Moderate |
| People overestimate how readily they would reject an unsuitable partner face to face, because they overlook their concern for the other person's feelings. | Joel, Teper & MacDonald 2014, *Psychological Science* 25(12):2233–2240 [K] | Moderate |

**What it means.**
- What happens between "match" and "first date" is the part of the process the evidence says can be shaped:
  - reciprocal, gradually deepening disclosure;
  - follow-up questions;
  - a move to voice early;
  - meeting within about three weeks.
- Sharabi 2021 is a double-edged result. Belief in the algorithm helps first dates, so an *honest* "why you were introduced" can help. But inflating that belief with fake precision would be manipulation, and the effect should not be used to oversell.
- A double opt-in with few introductions also makes interest *selective*, which is the kind that gets reciprocated (Eastwick et al. 2007 [K]).

### 2.3 Choice overload, the "rejection mind-set", swipe fatigue

| Claim | Evidence | Grade |
|---|---|---|
| Across three studies, the probability of accepting a profile fell by about **27%** from the first profile shown to the last. The cause was falling satisfaction with pictures and with one's perceived dating success. The effect was stronger for women, and for women it reduced actual matches. | Pronk & Denissen 2020, *Social Psychological and Personality Science* 11(3):388–396 [V] | Moderate |
| People choosing from **24** profiles were less satisfied a week later than people choosing from **6**, and more likely to switch. The least satisfied of all chose from the large set with the option to reverse. | D'Angelo & Toma 2017, *Media Psychology* [V (university release); n ≈ 100–152 undergraduates] | Weak–Moderate |
| Larger pools (30, 60 or 90 profiles) led to more searching, more time on poor options, and lower odds of choosing the best-fitting partner. | Wu & Chiou 2009, *CyberPsychology & Behavior* 12(3):315–318 [V (secondary for findings)] | Weak |
| In 84 real speed-dating events (3,738 people), larger events (24 or more partners) shifted choice towards attributes that can be judged quickly (height, weight) and away from slower ones (education, occupation). | Lenton & Francesconi 2010, *Psychological Science* [V] | Strong (field data) |
| General choice overload is *not* universal: across 50 experiments (N = 5,036) the mean effect was about zero, with wide variance. It reliably appears when the choice set is complex, the task is hard, **preferences are uncertain**, or the goal is to pick the single best option, all of which describe dating. | Scheibehenne, Greifeneder & Todd 2010, *Journal of Consumer Research* 37(3):409–425 [V]; Chernev, Böckenholt & Goodman 2015, *Journal of Consumer Psychology* [V (secondary)] | Strong |
| Among 464 users aged 16–25, dating app use related to upward social comparison, fear of being single and partner-choice overload **only through compulsive swiping**. How carefully people swiped did not change this. | Thomas, Binder, Stevic & Matthes 2023, *Telematics and Informatics* 78:101949 [V] | Moderate |
| Communication overload predicted ghosting romantic partners. | Forrai, Koban & Matthes 2023, *Telematics and Informatics* [V (abstract snippet only)] | Moderate |

**What it means.**
- No study has tested 1 versus 3 versus 10 introductions a day, so any exact number is a judgement.
- But every experimental and field result points the same way:
  - single-digit options per decision session;
  - low reversibility;
  - no endless feed;
  - a cap on how many conversations a person is juggling at once (communication overload predicts ghosting).
- Dating meets every condition under which choice overload *does* appear (Chernev 2015).

### 2.4 Mental-health effects: self-esteem, body image, mood, rejection, ghosting, burnout

| Claim | Evidence | Grade |
|---|---|---|
| A systematic review of 45 studies (2016–2023): **over 85% of body-image studies** found a significant negative association with dating app use, against **48.6%** of mental-health and wellbeing studies. The authors call for design changes. | Bowman, Drummond, Church, Kay & Petersen 2025, *Computers in Human Behavior* 165:108515 [V] | Strong (synthesis of mostly cross-sectional work) |
| Meta-analysis of 27 studies (N = 21,263) on swipe-based apps:<br>• overall adverse mental health g = 0.28;<br>• **behavioural dysregulation (compulsive use, loss of control) g = 0.44**;<br>• body pathology and disordered eating g = 0.32;<br>• appearance evaluation 0.28;<br>• interpersonal sensitivity 0.28;<br>• emotional distress 0.25;<br>• general wellbeing 0.10 (not significant).<br>Women and sexual-minority men were most affected. The authors say the results do not imply "uniform or generalized psychological harm". | Cela & Wood 2026, *Communications Psychology* [V (News-Medical summary of the paper)] | Strong (association) |
| Meta-analysis of 23 studies (N > 26,000): users scored worse than non-users on depression, loneliness, anxiety and distress. The effect appeared for **apps but not websites**, for **single** users but not partnered ones, and in **WEIRD nations but not elsewhere**. The direction of causation is unclear. | Sharabi, Ou, Von Feldt & Parsons 2026, *Computers in Human Behavior* 177:108879 [V (Psychology Today summary)] | Strong (association) |
| Australian adults (n = 437): current users were about **2.5×** as likely to report psychological distress and **2×** as likely to report probable depression. Heavier use went with more distress. About 40% of users said apps helped their self-esteem. | Holtzhausen et al. 2020, *BMC Psychology* 8:22 [V] | Weak–Moderate (cross-sectional) |
| Tinder users (out of 1,317 students) reported less satisfaction with their bodies and looks. Only male users reported lower self-esteem. | Strübel & Petrie 2017, *Body Image* [V (press); title variants exist] | Moderate (cross-sectional) |
| People higher in **anxious attachment** are more likely to use dating apps, and people higher in avoidant attachment less likely. | Chin, Edelstein & Vernon 2019, *Mobile Media & Communication* 7(1):41–59 [V] | Weak–Moderate |
| **Ghosting:**<br>• Ghosting breakups involve more avoidance and withdrawal and less open confrontation than direct breakups.<br>• Most young adults have either ghosted or been ghosted.<br>• People with strong destiny beliefs ghost more.<br>• **Breadcrumbing**, alone or with ghosting, was linked to lower life satisfaction and more helplessness and loneliness; ghosting alone was not significant (n = 626).<br>• A small RCT (n = 112) found **no measurable effect of ghosting on sleep** compared with a courteous ending (all \|d\| < .20).<br>• An earlier experiment found short-term rises in heart rate and blood pressure.<br>• Qualitative work reports confusion, mistrust over time, and for some, eventual reflection. | Koessler, Kohut & Campbell 2019, *Collabra* [V]; LeFebvre et al. 2019, *Imagination, Cognition and Personality* 39(2):125–150 [V (secondary)]; Freedman, Powell, Le & Williams 2019, *JSPR* [V (secondary)]; Navarro et al. 2020, *IJERPH* 17(3):1116 [V]; Langlais et al. 2026, *Frontiers in Psychology* 16:1742356 [V]; Langlais et al. 2024, *Sexuality & Culture* 28 [V (secondary)] | Moderate that ghosting is common and unpleasant; Weak on lasting harm |
| **"Dating app burnout"** as a named construct has thin peer-reviewed support. The best-measured mechanism is compulsive swiping plus choice overload (Thomas 2023). Popular burnout prevalence figures come from vendor and press surveys, which I could not verify. | Thomas et al. 2023 [V]; NPR 2019 coverage [V (press)] | Weak (as a construct) |

**What it means.**
- **Strongest harm signals:** body image, and compulsive or dysregulated use. Both are design-sensitive: they depend on appearance-first browsing and swipe mechanics.
- **Mood:** the association is real but small, its causal direction is unknown, and it was missing outside WEIRD samples. Ghana is effectively unstudied.
- **Ghosting** is common. The evidence that it does lasting harm is weak, but ambiguity and breadcrumbing look worse than a clean ending. A cheap "close kindly" path addresses the real cost (Joel 2014 [K]: people avoid explicit rejection).

### 2.5 Online versus offline: relationship outcomes

| Claim | Evidence | Grade |
|---|---|---|
| Meeting online became the most common way US heterosexual couples met: **39% in 2017** (22% in 2009). About 65% of same-sex couples met online. Meeting through friends fell from 36.4% to 28.6%. | Rosenfeld, Thomas & Hausen 2019, *PNAS* 116(36):17753–17758 [V] | Strong |
| Couples who met online and offline **break up at similar rates**, and couples who met through dating websites marry faster. No causal claim is made. | Rosenfeld 2017, *Sociological Science* 4:490–510 [V] | Strong |
| Among 19,131 people married 2005–2012, about a third met online. Online-met couples had slightly fewer breakups (5.96% vs 7.67%) and slightly higher satisfaction (5.64 vs 5.48). **eHarmony commissioned the survey and the lead author advised eHarmony.** | Cacioppo et al. 2013, *PNAS* 110(25):10135–10140 [V] | Moderate (large but conflicted, retrospective) |
| In Switzerland (3,245 partnered people, only 104 couples who met on an app), app-met couples had **stronger cohabitation intentions** and no difference in marriage intentions or satisfaction. Women who met on an app had stronger intentions to have a child within three years. App couples were more educationally mixed and lived farther apart. | Potarca 2020, *PLOS ONE* 15(12):e0243733 [V] | Moderate |
| Online-met couples are more likely to be interracial, interreligious and of different college-degree status, more similar in age, and no different in crossing political lines. | Thomas 2020, *Social Forces* 98(3):1257–1286 [V] | Strong |
| US users split almost evenly: 53% call their experience positive, 46% negative. Men report more positive experiences than women. | Pew Research Center 2023, "Key findings about online dating in the US" (survey of 6,034 adults, July 2022) [V] | Strong (survey) |
| Couples who met through weak ties or "anomic" settings (bars, online) perceived less network support, and some used cover stories about how they met. | Sassler & Miller 2015, *JSPR* 32(2):141–160 [V] | Weak–Moderate (62 couples, qualitative) |

**What it means.**
- Meeting online does not doom or improve relationships; venue explains little.
- **Stigma and secrecy around meeting online are real.** That matters where respectability counts (Sassler & Miller 2015) and supports discreet-by-default design.

### 2.6 Arranged, assisted and matchmaker marriages; family and faith; Ghana

| Claim | Evidence | Grade |
|---|---|---|
| Among Indian Americans (n = 58), arranged and love-based marriages did **not differ** in love, satisfaction or commitment. | Regan, Lakhanpal & Anguiano 2012, *Psychological Reports* 110(3):915–924 [V] | Weak (small) |
| Arranged marriages in India, arranged marriages among Indians in the US, and US marriages of choice (n = 229 / 185 / 173) differed in satisfaction. My recollection, not re-read, is that Indians in arranged marriages living in the US scored highest. | Madathil & Benshoff 2008, *The Family Journal* 16(3):222–230 [V-cite; direction K] | Moderate |
| No difference in marriage satisfaction between arranged marriages in India and marriages of choice in the US (preliminary). | Myers, Madathil & Tingle 2005, *Journal of Counseling & Development* 83(2):183–190 [V-cite; finding K] | Weak |
| In Nepal, taking part in choosing one's spouse was associated with higher marital quality. | Allendorf & Ghimire 2013, *Social Science Research* 42(1):59–70 [V-cite; finding K] | Moderate |
| In Chengdu, China, wives in love matches were more satisfied than wives in arranged marriages. | Xiaohe & Whyte 1990, *Journal of Marriage and the Family* 52(3):709–722 [K] | Moderate |
| **Network approval matters.** Higher perceived interference or lower approval from friends and family predicted poorer relationship quality on every outcome (n = 396). The "Romeo and Juliet effect" did not replicate, and a meta-analysis showed the same pattern. | Sinclair, Hood & Wright 2014, *Social Psychology* 45(3):170–178 [V]; Sprecher & Felmlee 1992, *JMF* 54(4) [V-cite]; Felmlee 2001, *Social Forces* [K] | Moderate–Strong |
| In collectivist contexts, **accepting parental influence** on mate choice lowered commitment and passion, while close family ties raised commitment. Family involvement is not the problem; unwanted control is. | Bejanyan, Marshall & Ferenczi 2015, *PLOS ONE* [02 §12.3] | Moderate–Low |
| Muslim American women using online dating valued control over how relationships start, privacy, and keeping their religious and cultural courtship traditions. They also faced stigma and feared misrepresentation. | Rochadiat, Tong & Novak 2018, *New Media & Society* 20(4):1618–1639 [V] | Weak (16 interviews) |
| Religious homogamy: attendance has a small association with lower divorce (r ≈ .125). Interfaith marriage is associated with more instability, partly through indirect paths. | Mahoney et al. 2001 [02 §11.1]; Lehrer & Chiswick 1993 [02 §11.1] | Moderate |
| **Ghana, marriage forms.**<br>• Customary marriage is a union of two families: kin traditionally arranged it and family consent was central.<br>• The "knocking" (*kɔkɔɔkɔ*) is the groom's family formally approaching the bride's family, usually with drinks, before head rites or bride price.<br>• Customary marriage may be polygynous and can be registered under the Customary Marriage and Divorce (Registration) Law, 1985 (PNDCL 112). Ordinance marriage (Marriages Act, Cap. 127) is monogamous.<br>• Polygyny: 23.9% of rural and 12.4% of urban married women.<br>• Urban marriage is described as more self-chosen. | Wikipedia, "Marriage in Ghana" [V; Weak]; legal framework [K]; scenario context in 04-scenarios-everyday ("traditional engagement (knocking, bride-price list) then a church wedding") | Weak–Moderate |
| **Peer-reviewed research on how Ghanaians date or court through apps today could not be located this session.** | — | Unknown |

**What it means.**
- The arranged-marriage literature is small and mixed. It does *not* show that autonomy-free matching produces worse or better marriages. What does hold up: **having a say in the choice** (Allendorf 2013 [K]) and **network approval** (Sinclair 2014) both predict better outcomes.
- For Ghana and the diaspora, that supports two things:
  - letting family enter the story **at the user's chosen moment**: conversation guides on "how and when would we involve our families", and eventually the knocking;
  - never giving families control of, or visibility into, a profile.
- Faith importance and family-involvement expectations are value dimensions where couples assort, so they are legitimate "shared ground". They are not success predictors.

### 2.7 Early bonding and commitment

| Claim | Evidence | Grade |
|---|---|---|
| **Investment model:** across 52 studies (11,582 people), satisfaction, quality of alternatives and investments together explain about two-thirds of the variance in commitment, and commitment predicts breakup. | Le & Agnew 2003, *Personal Relationships* 10(1):37–57 [V]; Rusbult 1980/1983 [K] | Strong |
| The strongest predictors of non-marital breakup are relationship-level: commitment, love, inclusion of the other in the self, and dependence. Individual traits predict weakly. | Le, Dove, Agnew, Korn & Mutso 2010, *Personal Relationships* 17(3):377–390 [V-cite; findings K] | Strong |
| **Self-expansion:** falling in love broadens the self-concept. Novel shared activities raise relationship quality. | Aron, Paris & Aron 1995, *JPSP* 69(6):1102–1112 [V-cite; findings K]; Aron et al. 2000 [02 §6.4] | Moderate |
| **Sliding versus deciding:** relationships that *slide* into transitions such as cohabitation, through inertia, fare worse than those that *decide*. Deciding is associated with higher dedication and lower infidelity. | Stanley, Rhoades & Markman 2006, *Family Relations* 55(4):499–509 [V]; Owen, Rhoades & Stanley 2013, *Journal of Couple & Relationship Therapy* 12(2):135–149 [V-cite; findings K] | Moderate |
| A "progression bias": once relationships start, people tend to move them forward rather than reject them. | Joel & MacDonald 2021, *Personality and Social Psychology Review* [K] | Moderate |
| **Passionate to companionate:** romantic love *without obsession* goes with satisfaction in both short and long relationships (meta-analysis of 25 studies), while obsession is negative in long relationships. Early disillusionment, meaning loss of affection and responsiveness in the first two years, predicted divorce better than early intensity did. | Acevedo & Aron 2009, *Review of General Psychology* 13(1):59–65 [V]; Huston, Caughlin, Houts, Smith & George 2001, *JPSP* 80(2):237–252 [V-cite; findings K] | Strong / Moderate |
| Attachment anxiety at the start of dating relationships predicted lower later relationship quality and less positive observed interaction (actor effect). | Holland, Fraley & Roisman 2012 [V] | Moderate |

**What it means.**
- **Defining the relationship** is a "deciding" moment, and Attune can make it one:
  - a private "where am I with this?" reflection;
  - a shared, optional "talk about what we are" prompt;
  - linking into Relationship Mode as an explicit joint act with a short "what are we agreeing to" step.
- **The investment model is also a warning.** App-made "investments" (streaks, points, accumulated history) can trap people in relationships through sunk cost rather than satisfaction. Attune should not manufacture them.
- **Self-expansion** supports novel first and early date ideas (02 §6.4).

### 2.8 Re-entering dating after a breakup

| Claim | Evidence | Grade |
|---|---|---|
| Starting a new relationship soon after a breakup was associated with *higher* wellbeing, self-esteem and confidence in one's desirability, and was not associated with a worse new relationship. | Brumbaugh & Fraley 2015, "Too fast, too soon? An empirical investigation into rebound relationships", *JSPR* 32(1):99–118 [K; not re-verified] | Moderate |
| Focusing on a new partner, or believing one could easily find one, reduced anxiously attached people's longing for their ex (one correlational study, two experiments). | Spielmann, MacDonald & Wilson 2009, *PSPB* 35(10):1382–1394 [V] | Moderate |
| Anxiously attached people rebound more, and part of their post-breakup growth runs *through* rebounding (two samples, n ≈ 411 and 465). Avoidant people report less distress and less growth. | Marshall, Bejanyan & Ferenczi 2013, *PLOS ONE* 8(9):e75161 [V] | Moderate (cross-sectional) |
| Rebound sex for coping or revenge is more common soon after a breakup and among the more distressed, and declines over time. | Barber & Cooper 2014, *Archives of Sexual Behavior* 43(2):251–265 [K] | Moderate |
| **Contact with the ex slowed recovery** of love and sadness. Attachment security and acceptance helped. | Sbarra & Emery 2005 [02 §15.1] | Moderate |
| Structured reflection after separation improved self-concept clarity, which reduced emotional intrusion and loneliness. | Larson & Sbarra 2015 [02 §15.1] | Moderate |
| Separation is a recognised danger period for intimate partner violence. | Campbell 2003; Glass et al. 2008 [02 §13.1] | Strong (case-control) |
| **No study I found tests an imposed waiting period before dating again.** Claims that recovery takes a fixed number of weeks are popular-press figures and could not be traced to primary sources. | — | Unknown |

**What it means for the "gentle wait only after an Attune breakup" decision.**
- The evidence does **not** support a mandatory cooldown. Rebounding is not reliably harmful and can help anxiously attached people let go (Spielmann 2009; Marshall 2013; Brumbaugh & Fraley 2015 [K]).
- It **does** support three things:
  - **making contact with, or visibility of, the ex impossible:** SPEC §5.1 exclusion, and no signal to the ex that someone has rejoined;
  - **offering structured reflection:** Healing (Larson & Sbarra 2015);
  - **remembering the safety risk of separation** (02 §13.1).
- The owner's "offered, not forced" framing fits the evidence. A hard timer would add friction without evidence of benefit.

### 2.9 Safety and harm

| Claim | Evidence | Grade |
|---|---|---|
| In a national survey of 9,987 Australian dating app and site users:<br>• **72.3%** had experienced online dating-app-facilitated sexual violence, and about **a third** in-person;<br>• sexual harassment was the most common form (69%);<br>• LGBTIQ men and women had higher rates of in-person sexual violence (36% and 42%) than heterosexual men and women (21% and 28%). | Wolbers, Boxall, Long & Gunnoo 2022, AIC Research Report 25 [V] | Strong |
| **Risk factors:**<br>• frequent use;<br>• sharing more personal information;<br>• **chatting with matches across different platforms**;<br>• paying for a service. | Wolbers & Dowling 2024, AIC Trends & Issues 704 [V] | Strong (correlational) |
| 88% of users with disability reported online dating-app-facilitated sexual violence. | AIC Trends & Issues 695 (2024) [V] | Strong |
| **12.4%** of users reported requests to facilitate sexual exploitation of their own children or children they could access. | Napier, Boxall, Brown & Teunissen 2022, AIC Trends & Issues 658 [V] | Strong |
| App users face more sexual and violent victimisation than non-users, and most apps place the burden of protection on users. | Pooley & Boxall 2020, AIC Trends & Issues 612 [V] | Moderate (review) |
| In a forensic caseload, **14% (11 of 76)** of sexual assaults followed a dating-app meeting:<br>• all complainants were female, mostly under 30;<br>• **more than half were impaired**;<br>• the assault happened at the **first in-person meeting**, and **more than half at the perpetrator's home**;<br>• injuries were common. | Rowse, Bolt & Gaya 2020, *Forensic Science, Medicine and Pathology* 16:71–77 [V] | Weak (small audit), consistent with the next row |
| Across 3,413 forensic exam charts, dating-app-facilitated assaults made up 8.0% of all cases and 13.9% of acquaintance assaults. They were more violent: **strangulation in about a third**, and more injuries. | Valentine, Miles, Hamblin & Gibbons 2022, *Journal of Interpersonal Violence* [V] | Moderate |
| Young women users (under 35):<br>• 60% said someone kept contacting them after they said no (men 27%);<br>• 44% were called an offensive name (men 23%);<br>• 19% were threatened with physical harm (men 9%). | Pew Research Center 2020 [V] | Strong (survey) |
| **Romance fraud (US, 2022):**<br>• about 70,000 reports, **$1.3 billion** lost, median loss $4,400;<br>• the most common lies were being on a military base or an oil rig, crypto "tutoring", and fake parcels;<br>• crypto and wires carried more than 60% of losses;<br>• 40% of contacts began on social media and 19% on dating sites or apps;<br>• victims were moved to WhatsApp or Telegram. | FTC Data Spotlight, Feb 2023 [V] | Strong (official complaints; underreported) |
| Romance scams follow a staged grooming model. **Romantic idealisation** is a victim risk marker; psychological traits otherwise explain little. Victims suffer a "double hit" (money and relationship), with heavy emotional harm even without money lost. Romance fraud mirrors coercive-control dynamics. | Whitty 2013, *British Journal of Criminology* 53(4):665–684 [V-cite]; Buchanan & Whitty 2013, *Psychology, Crime & Law* [V (project summary)]; Whitty & Buchanan 2016, *Criminology & Criminal Justice* [V (secondary)]; Cross, Dragiewicz & Richards 2018, *BJC* 58(6):1303–1322 [V-cite] | Moderate |
| **Coercive-control early signs** in content (never a "diagnosis"):<br>• jealousy framed as love;<br>• monitoring or checking;<br>• isolation from friends;<br>• pressure and rushing;<br>• threats;<br>• strangulation. | Stark 2007; Johnson 2008; Campbell 2003 [02 §13.1–13.2] | Strong (consensus) |
| **LGBTQ entrapment:**<br>• **Ghana:** HRW interviewed 114 LGBT Ghanaians. Cases include a man met through a dating site who led the victim to six men who beat, stripped and robbed him; lures through social media; blackmail with intimate photos; extortion by police; mob and family violence.<br>• **MENA:** HRW documented 20 cases of security forces entrapping people on Grindr and Facebook (Egypt, Iraq, Jordan), 16 of them arrested. | HRW 2018, "No Choice but to Deny Who I Am" [V]; HRW 2023, "All This Terror Because of a Photo" [V] | Moderate (documentation) |
| **Ghana law:**<br>• Criminal Offences Act 1960 s.104 criminalises "unnatural carnal knowledge" (a misdemeanour).<br>• In **May 2026 Parliament passed a new anti-LGBTQ+ bill** (BBC 30 May; France 24 and DW 29 May): up to 3 years for identifying as LGBTQ or same-sex relations, and 3–5 years for "promoting, sponsoring or supporting" LGBTQ activities. At last report it was **awaiting presidential assent**, and the President had said he would sign.<br>• Status after May 2026 is unknown to me. | Wikipedia, "LGBTQ rights in Ghana", citing BBC, France 24 and DW [V; Weak, secondary] | Weak (needs counsel) |
| **Safe first-date practices** (public place, own transport, tell someone, stay sober, keep chat on-platform) are expert consensus. **No trial shows that safety tips reduce assault.** The data above support the logic: first meetings, private homes, impairment, and moving across platforms. | Pooley & Boxall 2020 [V]; Rowse 2020 [V]; AIC 2024 [V]; Couch, Liamputtong & Pitts 2012, *Health, Risk & Society* [K] | Moderate (risk factors) / Unknown (tip efficacy) |

**What it means.**
- The *structure* of the product must reduce risk, rather than leaving it to tips. Four features carry the evidence:
  - in-app chat and calls, so numbers are not swapped early;
  - a first-meeting plan shared with a trusted person;
  - deterministic money and off-platform nudges;
  - immediate block and report.
- **Same-gender matching in Ghana is now a legal question,** possibly for the company as well as for users. It is not only a copy question.
- **Single parents:** child-exploitation requests are common enough (12.4%) that children's details and photos must never appear on dating profiles.

### 2.10 Age and life stage

| Life stage | What the evidence says | Grade |
|---|---|---|
| **18–25** | • Highest app use (US: about half of under-30s have used one [K: Pew 2023]).<br>• Most research samples are this age, and it carries the strongest body-image and compulsive-use signals (Cela & Wood 2026 sample mean age 23 [V]; Thomas 2023, ages 16–25 [V]).<br>• Motives mix love, casual sex, self-worth validation and thrill-seeking (Sumter, Vandenbosch & Ligtenberg 2017, *Telematics and Informatics* [K]); self-worth validation motives are the risky ones [K].<br>• Most forensic complainants were under 30 (Rowse 2020 [V]).<br>• Among Swiss 18–29s, app couples were more often age-hypergamous, with the man 3+ years older (Potarca 2020 [V]). | Moderate |
| **30s** | • Intentions shift towards long-term partnership and children.<br>• Women who met on an app had stronger near-term fertility intentions (Potarca 2020 [V]).<br>• Clarity about intentions and children early saves time; this follows from the dealbreaker literature (Jonason et al. 2015, *PSPB* [K]) more than from direct trials. | Moderate–Weak |
| **50+ and after divorce** | • Online daters' age preferences diverge with age: men seek increasingly younger partners, while women seek older partners until later life (Alterovitz & Mendelsohn 2009, *Psychology and Aging* 24(2):513–517 [V-cite; findings K]).<br>• Many older women prefer living apart together over remarriage (Benson & Coleman 2016, *JMF* [K]).<br>• Older adults lose larger sums to fraud (FTC data [K]).<br>• Divorce carries health risks and most people are resilient (Sbarra, Law & Portley 2011, *Perspectives on Psychological Science* [K]). | Moderate–Weak |
| **Single parents** | • Child-exploitation requests reach 12.4% of users (AIC TI 658 [V]).<br>• Children constrain time and pace.<br>• Co-parenting with an ex brings unavoidable contact (02 §15). | Strong (risk) / Weak (needs) |
| **Older adults generally** | • Accessibility, simpler flows and a different intention vocabulary ("companionship", "not looking to live together").<br>• Some evidence that later-life couples have less conflict and more shared pleasure (02 §12.11). | Moderate |
| **Ghana and the diaspora** | No peer-reviewed age-stage data on Ghanaian app dating was located. Respectability, family involvement and marriage-mindedness are likely more salient. Diaspora users meet across borders, which overlaps with long-distance needs (02 §9) and with romance-fraud scripts ("abroad", "can't meet yet", FTC 2023 [V]). | Unknown |

---

## 3. Direct answers

### (a) Which profile data predicts, and which is just preference filtering?

| Data | Predictive value for a good match or lasting bond | Correct use |
|---|---|---|
| Age, location, willingness to relocate, "who you want to meet" | Feasibility, not prediction. Age assortment is very strong (r = .87, Horwitz 2023). | Symmetric hard filters (SPEC §5). Never displayed except age. |
| Relationship intention (marriage-minded / long-term / unsure / companionship) | Mismatched intention is a dealbreaker; sociosexuality predicts who someone is interested in (Eastwick 2023). | Hard filter plus shared ground. |
| Wants children / has children | Dealbreaker-class. Children's details carry a safety risk (AIC TI 658). | Filter; yes/no only. No children's details or photos. |
| Faith and its importance, political or social values, substance use (smoking, drinking) | Strongest assortment of any measured traits (r up to .58); a small link with stability (Mahoney 2001; Lehrer & Chiswick 1993 [02]). | User-chosen filters, plus "you both said…" shared ground. Never a success claim. |
| Education, occupation, income | Strong assortment, but filtering on them entrenches inequality and desirability hierarchies (Bruch & Newman 2018). | Optional display at most. Never a ranking feature. |
| Family-involvement expectations (Ghana and diaspora) | Network approval predicts quality (Sinclair 2014). Expectations are a values match. | Optional value question; shared ground. |
| Explicit answers to prompts ("A perfect Sunday…") | No direct predictive value. They create *perceived* similarity and conversation material (Tidwell 2013; Fisman racial-preferences paper). | Display and first-conversation fuel. |
| Personality, attachment, communication style, conflict style | **No pair-predictive value** (Dyrenforth 2010; Joel 2017; Eastwick 2023). They predict the person's *own* relationship quality (Joel 2020; Holland 2012). | Self-facing growth only. **Remove from ranking (SPEC §6.1).** |
| Love languages | Unsupported as a typology or a match (02 §7). | Do not use (SPEC already forbids). |
| Stated ideal-partner preferences (traits wanted) | Do not predict initial attraction (Eastwick & Finkel 2008; Eastwick 2023); tiny effects later (β ≈ .04). | Let users set a few filters; do not weight them. |
| Photos and attractiveness | Drive initial interest equally for men and women (Eastwick & Finkel 2008). Consensus fades with acquaintance (Eastwick & Hunt 2014). Appearance focus links to body-image harm (Bowman 2025). | Show photos (people need them), after prompts and shared ground. Never rank by appearance. No body-type or weight fields. |
| Behavioural popularity (likes received, reply speed) | Predicts being *generally* desired (Joel 2017 partner variance), which is a hierarchy, not fit. | Never use (SPEC §6.1 already forbids). |
| Relationship-specific perceptions (responsiveness, appreciation, commitment) | **The strongest predictors** (Joel 2020), and they **only exist after meeting.** | Help them form and measure them (opt-in) after the match. See (c) and (e). |

### (b) How many introductions a day is defensible?

**Recommendation:**
- **at most 3 new introductions a day**, delivered once at a time the user chooses;
- **at most about 6 waiting** to be reviewed;
- **new introductions pause** while the user has **3 open pre-date conversations**.

Show nothing rather than lowering filters (SPEC §6.4). Pilot 2 versus 3 a day.

Why:
- options per session stay in single digits (D'Angelo & Toma 2017, 6 vs 24; Lenton & Francesconi 2010, the shift at 24 or more; Wu & Chiou 2009);
- the rejection mind-set builds within a session (Pronk & Denissen 2020);
- dating meets the conditions under which choice overload appears (Chernev 2015);
- compulsive swiping is the harm pathway (Thomas 2023), and communication overload predicts ghosting (Forrai et al. 2023);
- selective interest is reciprocated (Eastwick et al. 2007 [K]).

**Honest limit:** no study compares 1, 3 and 10 a day. This is a bounded judgement, not a measured optimum.

### (c) What should happen between "match" and "first date"?

1. **A guided first conversation:**
   - a few **reciprocal** question pairs, where each answer is revealed only after both people have answered (Sprecher 2013, taking turns);
   - questions deepen gently, from light to moderate, never the deepest Fast Friends set (Aron 1997);
   - every question can be skipped;
   - a quiet tip to ask a follow-up question (Huang 2017).
   - Reviewed, deterministic templates only (SPEC §9; nothing written by AI in the user's name, 02 C6).
2. **"Why you two were introduced":**
   - two or three explicit overlaps ("You both said faith matters a lot", "Both of you want children");
   - the line "Attune can't predict chemistry; meeting is how you find out."
   - This is honest and builds perceived similarity (Tidwell 2013; Sharabi 2021), without false precision (Finkel 2012).
3. **An early, optional voice call inside the app,** with video optional: text produces the least liking, and video adds little over audio (Sprecher 2014). It also keeps phone numbers private, avoiding cross-platform risk (AIC TI 704; FTC 2023). Both people must opt in, and it is never required.
4. **A gentle timebox, with no countdowns:**
   - around day 7–10: "Would you like to plan a first meet?";
   - around day 21 with no plan: "Keep chatting, or close kindly?"
   - The inverted U peaks at about 17–23 days (Ramirez 2015). No expiry timers or urgency (Thomas 2023; SOUL).
5. **A first-meeting plan:**
   - a public place, getting there and back independently, and a "share my plan" link to a trusted person;
   - a deterministic check-in prompt afterwards that only the user sees.
   - This targets first meetings at private homes and impairment (Rowse 2020; Valentine 2022).
6. **"Close kindly":** one tap sends a reviewed, final message ("Thank you for chatting. I don't think we're a match, and I wish you well.") and archives the chat. Silent unmatching stays available for safety. This lowers the cost of explicit rejection (Joel 2014 [K]) and avoids ambiguity and breadcrumbing (Navarro 2020).
7. **Private post-date reflection** (SPEC §10, keep as is), plus the opt-in panel items in (e).

### (d) Features that harm wellbeing and should not be built

| Do not build | Why (evidence) |
|---|---|
| Swipe decks, infinite feeds, browse or search of the pool | Rejection mind-set (Pronk & Denissen 2020); compulsive swiping (Thomas 2023; Cela & Wood 2026, behavioural dysregulation g = .44); worse choices (Wu & Chiou 2009) |
| Unlimited reversal ("rewind", re-open past passes) | Large sets plus reversibility gave the least satisfaction (D'Angelo & Toma 2017). Allow only a few seconds' undo. |
| "Likes you" queues, admirer counts, profile-view lists, "who viewed you" | Builds a desirability hierarchy (Bruch & Newman 2018); comparison and rejection-sensitivity loops (Thomas 2023); undermines double opt-in |
| Paid boosts, super-likes, paid visibility | A desirability market; paying for a service correlates with dating-app sexual violence (AIC TI 704); SOUL "no paywall between two people" [06 §1.5] |
| Popularity, Elo or attractiveness ranking; photo-derived features | Hierarchy, not fit (Joel 2017); body-image harm (Bowman 2025); SPEC §4.3 already forbids |
| Compatibility percentages or trait-distance "alignment" scores | No predictive validity (Finkel 2012; Joel 2017; Dyrenforth 2010); expectancy effects can mislead (Sharabi 2021) |
| Body-type or weight fields and filters | Body pathology and appearance associations (Cela & Wood 2026; Bowman 2025; Strübel & Petrie 2017) |
| Read receipts, typing indicators, "online now", last active | Ghosting anxiety and monitoring vectors (02 §13.3 #2; 06 §9) |
| Streaks, match counters, "you have 12 matches", celebratory gamification | Compulsivity (Thomas 2023); manufactured investments that cause sliding (Le & Agnew 2003; Stanley 2006) |
| "Someone new liked you" pushes, many re-engagement notifications | Compulsive checking (Cela & Wood 2026); at most one daily digest |
| Telling someone they were declined; "rejection reasons" | Rejection sensitivity; double opt-in exists to prevent this (SPEC §7) |
| Urgency timers (24-hour "message or lose them") | Pressure and compulsivity (Thomas 2023); conflicts with the deciding, not sliding, principle (Stanley 2006) |
| Requiring or nudging users to move to WhatsApp or phone numbers early | Cross-platform chat raises risk (AIC TI 704); scammers move victims off-platform (FTC 2023) |
| Children's photos, names or ages on dating profiles | Child-exploitation requests at 12.4% (AIC TI 658) |
| Any public or discoverable sign of "who you want to meet", or of being on Dating at all | LGBTQ entrapment and violence (HRW 2018; HRW 2023); online-meeting stigma (Sassler & Miller 2015) |
| A mandatory waiting period for everyone | No evidence of benefit; rebounding can help (Spielmann 2009; Marshall 2013) |
| LLM-based safety detection or AI-written messages | Permanent constraint (safety never depends on an LLM); inauthentic responsiveness (02 C6) |

### (e) What to measure as success: not swipes

**Theory of change for Dating Mode, mirroring 06 §1.4.** Attune helps single people meet a few well-filtered, safe people. It helps them reach a timely first meeting in which both feel responded to, and it helps them *decide*, rather than slide, into whatever comes next. The aim is never to keep them browsing. (Grounded in Joel 2020; Huang 2017; Ramirez 2015; Stanley 2006; 06 §1.4.)

| Metric | Definition | Why |
|---|---|---|
| **Meeting conversion** | Share of mutual matches that reach a first meeting, self-reported by either person through a boolean "we met", with no content | Meeting is where chemistry is decided (Finkel 2012; Joel 2017) |
| **Time to meet** | Median days from match to first meeting; target 7–21 | Inverted U (Ramirez 2015) |
| **Perceived responsiveness** | Opt-in panel, 3 items after the first conversation and after the first date ("I felt they were interested in what I said / understood me / cared"), aggregated only above n = 50, never shown to the other person | The theory of change (Reis; Joel 2020; 06 §4.0) |
| **Wellbeing does not worsen** | Opt-in brief items at enrolment and monthly (single-item self-esteem, loneliness, "Is dating here making you feel better, the same, worse?") | Association with distress and body image (Holtzhausen 2020; Bowman 2025; Sharabi 2026) |
| **Kind endings** | Share of conversations ended with "close kindly" rather than silence (an aggregate harm metric, never per user) | Ghosting and breadcrumbing (Navarro 2020; Koessler 2019) |
| **Safety** | Reports and blocks per 1,000 matches; money and off-platform nudge rate; report-to-action time; repeat-offender rate | DAFSV and romance fraud (AIC 2022; FTC 2023) |
| **Healthy exits** | Share of pauses or departures with the reason "I met someone"; number of matched pairs that link into Relationship Mode | Success is leaving (06 §1.5: not a slot machine) |
| **Commitment, later (opt-in)** | At 3 and 6 months after linking, a brief commitment and satisfaction measure (investment-model short form) | Commitment predicts staying together (Le & Agnew 2003) |
| **Fairness** | Distribution of exposure (who gets introduced) and mutual-interest rates by audited cohort | Desirability hierarchies (Bruch & Newman 2018); SPEC §6.5 |
| **Anti-metrics** (watched, never optimised) | Sessions a day, time in the app, introductions viewed | Compulsive use is the strongest harm signal (Cela & Wood 2026) |

Keep SPEC §10 and §13.3: product analytics record reflection *completion* only. All outcome measures above go through the opt-in panel.

---

## 4. Implications for Attune

1. **Re-scope the "Alignment preview" into "Why you two were introduced".** List only explicit, user-supplied overlaps: intention, children, faith importance, values, family-involvement expectations. Always add "Attune can't predict chemistry".
   - **Change SPEC §6.1:** remove attachment, communication-style and conflict-style dimensions from scoring and keep them self-facing.
   - *Why:* personality and attachment similarity adds no prediction (Dyrenforth 2010; Joel 2017; Eastwick 2023); perceived similarity drives first-meeting liking (Tidwell 2013); values are where couples truly assort (Horwitz 2023).
2. **Rank by feasibility and fairness, not "fit".**
   - Order: mutual hard filters, then feasibility (intention, children, location or relocation), then the count of explicit shared-value overlaps, then exposure balancing with bounded randomisation (SPEC §6.4).
   - *Why:* profiles cannot predict pair-specific attraction (Joel 2017). Popularity signals create hierarchy (Bruch & Newman 2018).
3. **Cadence:**
   - at most 3 new introductions a day, at a user-chosen time;
   - at most about 6 waiting;
   - new introductions pause while 3 pre-date conversations are open;
   - no refresh, and no stacking of missed days.
   - This replaces SPEC §6.4's weekly batch with a daily trickle *inside* the same caps. *Why:* see (b).
4. **Low-reversibility decisions:** "Interested" or "Not for me" with a five-second undo, and no rewind. *Why:* D'Angelo & Toma 2017.
5. **Person before photo, photo still present:**
   - keep SPEC §4.2's order (shared ground and prompts first);
   - photos remain optional;
   - no body-type, weight or attractiveness data anywhere.
   - *Why:* attraction matters for both sexes (Eastwick & Finkel 2008), and appearance focus links to body-image harm (Bowman 2025; Cela & Wood 2026).
6. **Build the guided first conversation:** reciprocal reveal-after-both-answer pairs, gentle deepening, skips, and a follow-up-question tip, from reviewed templates. *Why:* Sprecher 2013; Aron 1997; Huang 2017. Measure: panel responsiveness after the first conversation.
7. **Offer an in-app voice call, with video optional,** after mutual opt-in.
   - *Why:* text is the weakest first modality (Sprecher 2014); number privacy avoids cross-platform risk (AIC TI 704).
   - *Tension:* 06 §9 rejected in-app video for couples because of the media-stack and moderation burden. Dating's safety rationale differs (see open question 5).
8. **Gentle meeting timebox:** a "plan a meet?" card around day 7–10 and a "keep chatting or close kindly?" card around day 21. No countdowns. *Why:* Ramirez 2015; Thomas 2023.
9. **"Close kindly":** a one-tap reviewed closing message that archives the chat, with a silent unmatch kept for safety. Measure the aggregate share of kind endings. *Why:* ghosting and breadcrumbing (Koessler 2019; Navarro 2020); reluctance to reject (Joel 2014 [K]).
10. **A structural first-meeting safety kit:**
    - public-venue guidance;
    - "share my plan" with a trusted person, by link and with no location tracking by default;
    - an after-date check-in that only the user sees;
    - safety copy reviewed by an expert.
    - *Why:* risk concentrates at the first meeting, in private homes and with impairment (Rowse 2020; Valentine 2022). Tips alone are not proven (Pooley & Boxall 2020), so structure carries the weight.
11. **Deterministic money and off-platform nudges, shown to the at-risk user only.** Triggers: keyword and pattern rules for money, mobile money, crypto, gift cards, "customs fees", "I'm on a base or rig abroad", and requests to move to WhatsApp or Telegram. There is no LLM involvement (a permanent constraint). The nudge links to the scam report category (SPEC §9). *Why:* FTC 2023; Whitty 2013; Buchanan & Whitty 2013 (emotional harm without money lost).
12. **Mental-health guardrails:**
    - at most one notification a day (a digest);
    - no interest counts;
    - "Pause" hides the user immediately and silently;
    - an optional private monthly check-in ("better / same / worse") that suggests a pause or Healing when the answer is "worse".
    - *Why:* Cela & Wood 2026; Sharabi 2026; Holtzhausen 2020.
13. **After an Attune breakup: an offer, never a timer.**
    - Show one private "before you begin" readiness reflection with Healing offered, and let the user set their own start date if they wish.
    - Keep SPEC §5.1 ex-exclusion mandatory and never signal anything to the ex.
    - Apply no wait to anyone else.
    - *Why:* Spielmann 2009; Marshall 2013; Brumbaugh & Fraley 2015 [K]; Sbarra & Emery 2005; Larson & Sbarra 2015.
14. **Make "becoming a couple" a decision, not a slide:**
    - linking into Relationship Mode needs both partners to confirm, after a short private "what are we agreeing to?" step;
    - offer an optional "talk about what we are" prompt pack after a few weeks of active chatting;
    - no streaks or accumulated "investment" mechanics.
    - *Why:* Stanley 2006; Owen 2013; Le & Agnew 2003.
15. **Family at the user's pace:** an optional "how involved do you want family to be?" value question used as shared ground; later-stage guides ("introducing each other to family", "the knocking"); a trusted-person feature for safety. No family or guardian accounts at launch. *Why:* network approval helps (Sinclair 2014); unwanted parental control hurts (Bejanyan 2015); family violence against LGBTQ Ghanaians (HRW 2018).
16. **Faith as importance, not just a label:** ask "How important is faith in your partner?" (not important / somewhat / very / same faith required), optionally with the tradition, used as filter and shared ground. *Why:* strong assortment (Horwitz 2023); faith users value tradition alongside control (Rochadiat 2018).
17. **Life-stage vocabulary and protections:**
    - intention options include "marriage-minded" and "companionship";
    - "not looking to live together" is a valid answer;
    - "has children" is yes or no only, and child photos are banned in moderation;
    - older-adult fraud nudges stay switched on.
    - *Why:* Alterovitz & Mendelsohn 2009 [K]; Benson & Coleman 2016 [K]; AIC TI 658; FTC 2023.
18. **Discreet by default:**
    - no discoverability by contacts or search;
    - neutral notification text;
    - "who you want to meet" is never shown or exposed through any API (already SPEC §4.1);
    - Dating data is purged on exit under the retention schedule.
    - *Why:* HRW 2018 and 2023; Sassler & Miller 2015.
19. **Treat Ghana same-gender matching as a legal-gate item before launch** (see open question 3). *Why:* the May 2026 bill (Weak, secondary) may criminalise "supporting" LGBTQ activities; HRW-documented entrapment.
20. **Measure with the opt-in panel and the metrics in (e).** Report harm signals and anti-metrics alongside success, and never optimise sessions or time in the app. *Why:* 06 §4.0; Joel 2020.

---

## 5. Open questions for the owner

1. **Drop trait-distance from the alignment algorithm?**
   - The evidence says attachment, communication and conflict-style similarity cannot predict pair fit.
   - **Recommendation: yes.** Rank on feasibility and explicit shared values, and rename the preview "Why you two were introduced". Quizzes stay self-facing.
2. **Exact cadence numbers.**
   - **Recommendation:** 3 new a day, about 6 waiting, a pause at 3 open pre-date conversations. Pilot 2 versus 3, and set the numbers as server configuration, not constants.
3. **Same-gender matching for accounts located in Ghana.**
   - Parliament passed a new anti-LGBTQ+ bill in May 2026 (awaiting assent at last report). It may criminalise "promoting or supporting".
   - **Recommendation:**
     - get Ghanaian legal counsel and consult Ghanaian LGBTQ rights groups before Dating launches;
     - until both clear it, do not offer same-gender introductions to accounts located in Ghana; explain why honestly and point to safety resources;
     - keep same-gender matching for diaspora and other jurisdictions, with country-aware notes;
     - in every country, store "who you want to meet" minimally and purge it on exit.
   - This is a hard trade-off, because LGBTQ Ghanaians are the most underserved. But entrapment and prosecution risk falls on the user.
4. **Family or guardian involvement** (for example, an Islamic *wali* or a parent as introducer).
   - **Recommendation:** not at launch. Ship family-pace guides and a trusted person for date safety. Revisit guardian modes after the cultural review (DATING_MODE_CULTURAL_REVIEW_PACKET).
5. **In-app voice or video before the first date.**
   - **Recommendation:** in-app voice first, with video optional, because it protects numbers and uses the stronger modality.
   - Accept that this reverses 06 §9's "no in-app video" for this surface only.
   - Check whether the existing Sendbird contract covers calls before choosing anything else.
6. **An age-gap guardrail for 18–20-year-olds.**
   - Evidence is weak: risk concentrates in young women (Rowse 2020), and young app couples skew age-hypergamous (Potarca 2020).
   - **Recommendation:** default the age range to at most about +7 years for 18–20-year-olds, and let them widen it deliberately with one plain-language note.
7. **Should "casual" be an intention option?**
   - **Recommendation:** not at launch. Attune is relationship-focused (SOUL), and intention mismatch is a dealbreaker. Offer "marriage-minded / long-term / open to seeing where it goes / companionship".
8. **A hard wait after an Attune breakup?**
   - **Recommendation:** no. Show one readiness reflection with Healing offered and an optional self-set start date; ex-exclusion stays mandatory.
9. **An opt-in outcome panel for Dating, including 3- and 6-month follow-ups.**
   - **Recommendation:** yes, mirroring 06 §4.0, aggregated above n = 50, deletable, never a ranking input.
10. **"Don't introduce me to my contacts."**
    - **Recommendation:** offer it as opt-in, with on-device hashing of contacts. Discretion matters (Sassler & Miller 2015; Rochadiat 2018; HRW 2018). Privacy review is needed because contact data is sensitive.
11. **Commission Ghana-specific research.**
    - No peer-reviewed data on Ghanaian app dating was found.
    - **Recommendation:** a small qualitative study (12–20 interviews in Accra and Kumasi, plus diaspora) before launch, folded into the cultural review packet.

---

## 6. References

Tags: [V] findings verified this session; [V-cite] citation verified, findings from prior knowledge; [K] not re-verified; (secondary) press or summary only.

**Prediction, similarity, preferences**
- Finkel, E. J., Eastwick, P. W., Karney, B. R., Reis, H. T., & Sprecher, S. (2012). Online dating: A critical analysis from the perspective of psychological science. *Psychological Science in the Public Interest*, 13(1), 3–66. doi:10.1177/1529100612436522 [V]
- Joel, S., Eastwick, P. W., & Finkel, E. J. (2017). Is romantic desire predictable? Machine learning applied to initial romantic attraction. *Psychological Science*, 28(10), 1478–1489. doi:10.1177/0956797617714580 [V]
- Joel, S., et al. (2020). Machine learning uncovers the most robust self-report predictors of relationship quality across 43 longitudinal couples studies. *PNAS*, 117(32), 19061–19071 [V]
- Eastwick, P. W., Joel, S., Carswell, K. L., Molden, D. C., Finkel, E. J., & Blozis, S. A. (2023). Predicting romantic interest during early relationship development: A preregistered investigation using machine learning. *European Journal of Personality*, 37(3), 276–312. doi:10.1177/08902070221085877 [V]
- Horwitz, T. B., Balbona, J. V., Paulich, K. N., & Keller, M. C. (2023). Evidence of correlations between human partners based on systematic reviews and meta-analyses of 22 traits and UK Biobank analysis of 133 traits. *Nature Human Behaviour*, 7, 1568–1583 [V]
- Dyrenforth, P. S., Kashy, D. A., Donnellan, M. B., & Lucas, R. E. (2010). Predicting relationship and life satisfaction from personality in nationally representative samples from three countries. *JPSP*, 99(4), 690–702 [V]
- Montoya, R. M., Horton, R. S., & Kirchner, J. (2008). Is actual similarity necessary for attraction? *JSPR*, 25(6), 889–922 [V]
- Tidwell, N. D., Eastwick, P. W., & Finkel, E. J. (2013). Perceived, not actual, similarity predicts initial attraction in a live romantic context. *Personal Relationships*, 20(2), 199–215 [V]
- Eastwick, P. W., & Finkel, E. J. (2008). Sex differences in mate preferences revisited. *JPSP*, 94(2), 245–264 [V]; Selterman, D., Chagnon, E., & MacKinnon, S. (2015). *SAGE Open* (replication) [V]
- Eastwick, P. W., Luchies, L. B., Finkel, E. J., & Hunt, L. L. (2014). The predictive validity of ideal partner preferences. *Psychological Bulletin*, 140, 623–665 [V (secondary for findings)]
- Psychological Science Accelerator. A worldwide test of the predictive validity of ideal partner preference matching (registered report, N = 10,358, 43 countries) [V (secondary); venue not confirmed]
- Eastwick, P. W., & Hunt, L. L. (2014). Relational mate value. *JPSP*, 106(5), 728–751 [V (secondary)]; Hunt, L. L., Eastwick, P. W., & Finkel, E. J. (2015). Leveling the playing field. *Psychological Science*, 26(7) [V (APS release)]
- Holland, A. S., Fraley, R. C., & Roisman, G. I. (2012). Attachment styles in dating couples. *Personal Relationships*, 19(2), 234–246 [V]
- Bruch, E. E., & Newman, M. E. J. (2018). Aspirational pursuit of mates in online dating markets. *Science Advances*, 4(8) [V]
- Fisman, R., Iyengar, S. S., Kamenica, E., & Simonson, I. (2006). Gender differences in mate selection. *QJE*, 121(2), 673–697 [V]; Racial preferences in dating (2008, *Review of Economic Studies*) [V (secondary)]
- Jonason, P. K., et al. (2015). Relationship dealbreakers. *PSPB*, 41(12) [K]

**First meetings and liking**
- Huang, K., Yeomans, M., Brooks, A. W., Minson, J., & Gino, F. (2017). It doesn't hurt to ask: Question-asking increases liking. *JPSP*, 113(3), 430–452 [V]
- Aron, A., Melinat, E., Aron, E. N., Vallone, R. D., & Bator, R. J. (1997). The experimental generation of interpersonal closeness. *PSPB*, 23(4), 363–377 [V]
- Sprecher, S., Treger, S., Wondra, J. D., Hilaire, N., & Wallpe, K. (2013). Taking turns. *JESP*, 49, 860–866 [V (secondary for findings)]
- Sprecher, S. (2014). Initial interactions online-text, online-audio, online-video, or face-to-face. *Computers in Human Behavior*, 31, 190–197 [V (listing); volume K]
- Eastwick, P. W., Finkel, E. J., Mochon, D., & Ariely, D. (2007). Selective versus unselective romantic desire. *Psychological Science*, 18(4) [K]
- Ramirez, A., Sumner, E. M., Fleuriet, C., & Cole, M. (2015). When online dating partners meet offline. *JCMC*, 20(1), 99–114. doi:10.1111/jcc4.12101 [V]
- Sharabi, L. L., & Caughlin, J. P. (2017). What predicts first date success? *Personal Relationships*, 24(2), 370–391 [V]; (2019) deception and first dates, *New Media & Society* [V (secondary)]
- Sharabi, L. L. (2021). Exploring how beliefs about algorithms shape (offline) success in online dating. *Communication Research*, 48(7), 931–952 [V (author summary)]
- Joel, S., Teper, R., & MacDonald, G. (2014). People overestimate their willingness to reject potential romantic partners. *Psychological Science*, 25(12) [K]

**Choice overload**
- Pronk, T. M., & Denissen, J. J. A. (2020). A rejection mind-set: Choice overload in online dating. *SPPS*, 11(3), 388–396 [V]
- D'Angelo, J. D., & Toma, C. L. (2017). There are plenty of fish in the sea. *Media Psychology* [V (university release)]
- Wu, P.-L., & Chiou, W.-B. (2009). More options lead to more searching and worse choices in finding partners for romantic relationships online. *CyberPsychology & Behavior*, 12(3), 315–318 [V (secondary for findings)]
- Lenton, A. P., & Francesconi, M. (2010). How humans cognitively manage an abundance of mate options. *Psychological Science*, 21 [V]
- Scheibehenne, B., Greifeneder, R., & Todd, P. M. (2010). Can there ever be too many options? *Journal of Consumer Research*, 37(3), 409–425 [V]; Chernev, A., Böckenholt, U., & Goodman, J. (2015). Choice overload: A conceptual review and meta-analysis. *Journal of Consumer Psychology* [V (secondary)]
- Thomas, M. F., Binder, A., Stevic, A., & Matthes, J. (2023). 99+ matches but a spark ain't one. *Telematics and Informatics*, 78, 101949 [V]
- Forrai, M., Koban, K., & Matthes, J. (2023). Ghosting and communication overload. *Telematics and Informatics* [V (snippet only)]

**Mental health and ghosting**
- Bowman, Z., Drummond, M., Church, J., Kay, J., & Petersen, J. M. (2025). Dating apps and their relationship with body image, mental health and wellbeing: A systematic review. *Computers in Human Behavior*, 165, 108515 [V]
- Cela, H., & Wood, G. (2026). Mental health and well-being outcomes of swiping-based dating app use: Systematic review and meta-analysis. *Communications Psychology* [V (News-Medical summary)]
- Sharabi, L. L., Ou, L., Von Feldt, P. A., & Parsons, T. D. (2026). Dating app use, psychological health, and psychological well-being. *Computers in Human Behavior*, 177, 108879 [V (Psychology Today summary)]
- Holtzhausen, N., Fitzgerald, K., Thakur, I., Ashley, J., Rolfe, M., & Pit, S. W. (2020). Swipe-based dating applications use and its association with mental health outcomes. *BMC Psychology*, 8, 22 [V]
- Strübel, J., & Petrie, T. A. (2017). Love me Tinder. *Body Image* [V (press)]
- Chin, K., Edelstein, R. S., & Vernon, P. A. (2019). Attached to dating apps. *Mobile Media & Communication*, 7(1), 41–59 [V]
- Koessler, R. B., Kohut, T., & Campbell, L. (2019). When your boo becomes a ghost. *Collabra: Psychology* [V]
- LeFebvre, L. E., et al. (2019). Ghosting in emerging adults' romantic relationships. *Imagination, Cognition and Personality*, 39(2), 125–150 [V (secondary)]
- Freedman, G., Powell, D. N., Le, B., & Williams, K. D. (2019). Ghosting and destiny. *JSPR* [V (secondary)]
- Navarro, R., Larrañaga, E., Yubero, S., & Víllora, B. (2020). Psychological correlates of ghosting and breadcrumbing experiences. *IJERPH*, 17(3), 1116 [V]
- Langlais, M. R., et al. (2026). Resilience to ghosting? An RCT on sleep. *Frontiers in Psychology*, 16, 1742356 [V]

**Online vs offline**
- Rosenfeld, M. J., Thomas, R. J., & Hausen, S. (2019). Disintermediating your friends. *PNAS*, 116(36), 17753–17758 [V]
- Rosenfeld, M. J. (2017). Marriage, choice, and couplehood in the age of the internet. *Sociological Science*, 4, 490–510 [V]
- Cacioppo, J. T., Cacioppo, S., Gonzaga, G. C., Ogburn, E. L., & VanderWeele, T. J. (2013). Marital satisfaction and break-ups differ across on-line and off-line meeting venues. *PNAS*, 110(25), 10135–10140 [V]
- Potarca, G. (2020). The demography of swiping right. *PLOS ONE*, 15(12), e0243733 [V]
- Thomas, R. J. (2020). Online exogamy reconsidered. *Social Forces*, 98(3), 1257–1286 [V]
- Pew Research Center (2023). Key findings about online dating in the U.S. [V]; Pew Research Center (2020). Young women often face sexual harassment online, including on dating sites and apps [V]
- Sassler, S., & Miller, A. J. (2015). The ecology of relationships: Meeting locations and cohabitors' relationship perceptions. *JSPR*, 32(2), 141–160 [V]

**Arranged, family, faith, Ghana**
- Regan, P. C., Lakhanpal, S., & Anguiano, C. (2012). Relationship outcomes in Indian-American love-based and arranged marriages. *Psychological Reports*, 110(3), 915–924 [V]
- Madathil, J., & Benshoff, J. M. (2008). Importance of marital characteristics and marital satisfaction. *The Family Journal*, 16(3), 222–230 [V-cite]
- Myers, J. E., Madathil, J., & Tingle, L. R. (2005). Marriage satisfaction and wellness in India and the United States. *Journal of Counseling & Development*, 83(2), 183–190 [V-cite]
- Allendorf, K., & Ghimire, D. J. (2013). Determinants of marital quality in an arranged marriage society. *Social Science Research*, 42(1), 59–70 [V-cite]
- Xiaohe, X., & Whyte, M. K. (1990). Love matches and arranged marriages: A Chinese replication. *JMF*, 52(3), 709–722 [K]
- Sinclair, H. C., Hood, K. B., & Wright, B. L. (2014). Revisiting the Romeo and Juliet effect. *Social Psychology*, 45(3), 170–178 [V]; Sprecher, S., & Felmlee, D. (1992). *JMF*, 54(4), 888ff. [V-cite]
- Rochadiat, A. M. P., Tong, S. T., & Novak, J. M. (2018). Online dating and courtship among Muslim American women. *New Media & Society*, 20(4), 1618–1639 [V]
- Human Rights Watch (2018). "No Choice but to Deny Who I Am": Violence and discrimination against LGBT people in Ghana [V]
- Human Rights Watch (2023). "All This Terror Because of a Photo": Digital targeting and its offline consequences for LGBT people in MENA [V]
- Wikipedia, "LGBTQ rights in Ghana" (accessed 2026-10-24; cites BBC 30 May 2026, France 24 and DW 29 May 2026) [V; Weak]; Wikipedia, "Marriage in Ghana" [V; Weak]

**Commitment and bonding**
- Le, B., & Agnew, C. R. (2003). Commitment and its theorized determinants: A meta-analysis of the Investment Model. *Personal Relationships*, 10(1), 37–57 [V]
- Le, B., Dove, N. L., Agnew, C. R., Korn, M. S., & Mutso, A. A. (2010). Predicting nonmarital romantic relationship dissolution: A meta-analytic synthesis. *Personal Relationships*, 17(3), 377–390 [V-cite]
- Aron, A., Paris, M., & Aron, E. N. (1995). Falling in love: Prospective studies of self-concept change. *JPSP*, 69(6), 1102–1112 [V-cite]
- Stanley, S. M., Rhoades, G. K., & Markman, H. J. (2006). Sliding versus deciding. *Family Relations*, 55(4), 499–509 [V]
- Owen, J., Rhoades, G. K., & Stanley, S. M. (2013). Sliding versus deciding in relationships. *Journal of Couple & Relationship Therapy*, 12(2), 135–149 [V-cite]
- Acevedo, B. P., & Aron, A. (2009). Does a long-term relationship kill romantic love? *Review of General Psychology*, 13(1), 59–65 [V]
- Huston, T. L., Caughlin, J. P., Houts, R. M., Smith, S. E., & George, L. J. (2001). The connubial crucible. *JPSP*, 80(2), 237–252 [V-cite]
- Joel, S., & MacDonald, G. (2021). We're not that choosy: Progression bias. *PSPR* [K]

**Breakups and rebound**
- Brumbaugh, C. C., & Fraley, R. C. (2015). Too fast, too soon? An empirical investigation into rebound relationships. *JSPR*, 32(1), 99–118 [K]
- Spielmann, S. S., MacDonald, G., & Wilson, A. E. (2009). On the rebound. *PSPB*, 35(10), 1382–1394 [V]
- Marshall, T. C., Bejanyan, K., & Ferenczi, N. (2013). Attachment styles and personal growth following romantic breakups. *PLOS ONE*, 8(9), e75161 [V]
- Barber, L. L., & Cooper, M. L. (2014). Rebound sex. *Archives of Sexual Behavior*, 43(2), 251–265 [K]
- Sbarra & Emery (2005); Larson & Sbarra (2015) [02 §15.1]

**Safety**
- Wolbers, H., Boxall, H., Long, C., & Gunnoo, A. (2022). Sexual harassment, aggression and violence victimisation among mobile dating app and website users in Australia. AIC Research Report 25. doi:10.52922/rr78740 [V]
- Wolbers, H., & Dowling, C. (2024). Routine online activities and vulnerability to dating app facilitated sexual violence. AIC Trends & Issues 704 [V]
- AIC (2024). Online DAFSV victimisation among people with disability. Trends & Issues 695 [V]
- Napier, S., Boxall, H., Brown, R., & Teunissen, C. (2022). The sexual exploitation of Australian children on dating apps and websites. AIC Trends & Issues 658 [V]
- Pooley, K., & Boxall, H. (2020). Mobile dating applications and sexual and violent offending. AIC Trends & Issues 612 [V]
- Rowse, J., Bolt, C., & Gaya, S. (2020). Swipe right: The emergence of dating-app facilitated sexual assault. *Forensic Science, Medicine and Pathology*, 16, 71–77 [V]
- Valentine, J. L., Miles, L. W., Hamblin, K., & Gibbons, A. W. (2022). Dating app facilitated sexual assault. *Journal of Interpersonal Violence*. doi:10.1177/08862605221130390 [V]
- US Federal Trade Commission (2023, February). Data Spotlight: Romance scammers' favorite lies exposed [V]
- Whitty, M. T. (2013). The scammers persuasive techniques model. *British Journal of Criminology*, 53(4), 665–684 [V-cite]
- Buchanan, T., & Whitty, M. T. (2013). The online dating romance scam: Causes and consequences of victimhood. *Psychology, Crime & Law* [V (project summary)]; Whitty, M. T., & Buchanan, T. (2016). *Criminology & Criminal Justice* [V (secondary)]
- Cross, C., Dragiewicz, M., & Richards, K. (2018). Understanding romance fraud: Insights from domestic violence research. *British Journal of Criminology*, 58(6), 1303–1322 [V-cite]
- Couch, D., Liamputtong, P., & Pitts, M. (2012). What are the real and perceived risks and dangers of online dating? *Health, Risk & Society* [K]
- IPV and coercive-control sources (Stark 2007; Johnson 2008; Campbell 2003; Glass et al. 2008) [02 §13]

**Age and life stage**
- Alterovitz, S. S.-R., & Mendelsohn, G. A. (2009). Partner preferences across the life span: Online dating by older adults. *Psychology and Aging*, 24(2), 513–517 [V-cite]
- Benson, J. J., & Coleman, M. (2016). Older adults developing a preference for living apart together. *JMF* [K]
- Sumter, S. R., Vandenbosch, L., & Ligtenberg, L. (2017). Love me Tinder: Untangling emerging adults' motivations. *Telematics and Informatics* [K]
- Sbarra, D. A., Law, R. W., & Portley, R. M. (2011). Divorce and death. *Perspectives on Psychological Science* [K]

# ATTUNE — CLINICAL VALIDATION DOCUMENT
### The evidence base for every psychological framework used in the product
**Version:** 1.0
**Created:** June 2026
**Status:** Draft — requires review by licensed clinical advisor before launch
**Primary audience:** Clinical advisor, legal counsel, regulatory review
**Secondary audience:** Engineering team (for implementation constraints)
**Related documents:** ATTUNE_SOUL.md · ATTUNE_MASTER_SPEC.md · ATTUNE_PRINCIPLES_CHECKLIST.md

---

> **CRITICAL NOTE — READ FIRST**
>
> This document is a working draft compiled from published research.
> It is not a substitute for clinical review by a licensed professional.
> Before Attune launches, every psychologically interpretive section
> of this document must be reviewed and signed off by a licensed
> clinical advisor with expertise in couples therapy and cross-cultural
> psychology.
>
> Where this document identifies gaps, limitations, or open questions,
> those items must be resolved before the relevant psychologically
> interpretive feature is deployed.
> An unresolved gap is not a reason to delay documentation —
> it is a reason to delay deployment of that specific psychologically
> interpretive feature.
>
> All citations in this document require independent verification
> of author names, journal titles, publication years, and DOI links
> before the document is used in any external, investor-facing,
> or regulatory context.

---

## TABLE OF CONTENTS

1. [Purpose and Scope](#1-purpose-and-scope)
2. [The WEIRD Population Problem](#2-the-weird-population-problem)
3. [Framework 1 — Attachment Theory and the ECR-R](#3-framework-1--attachment-theory-and-the-ecr-r)
4. [Framework 2 — Gottman's Four Horsemen](#4-framework-2--gottmans-four-horsemen)
5. [Framework 3 — Love Languages](#5-framework-3--love-languages)
6. [Framework 4 — Nonviolent Communication](#6-framework-4--nonviolent-communication)
7. [Framework 5 — Pursue-Withdraw Pattern](#7-framework-5--pursue-withdraw-pattern)
8. [Framework 6 — The Needs Taxonomy](#8-framework-6--the-needs-taxonomy)
9. [Cultural Calibration — Ghana and West Africa](#9-cultural-calibration--ghana-and-west-africa)
10. [Framework Confidence Levels](#10-framework-confidence-levels)
11. [Clinical Advisor Review Checklist](#11-clinical-advisor-review-checklist)
12. [Open Questions Before Launch](#12-open-questions-before-launch)
13. [Research References](#13-research-references)
14. [Update Log](#14-update-log)

---

## 1. PURPOSE AND SCOPE

### What this document is

This is the evidence base that validates every psychological framework
Attune uses to generate quiz results, detect communication patterns,
surface insights, and produce relationship verdicts.

For each framework it answers four questions:
1. What is the source and research basis?
2. What validated instrument exists, and are we using it?
3. What are the known limitations the research itself acknowledges?
4. What is the AI allowed and not allowed to conclude from it?

### What this document is not

This document does not diagnose users. It does not prescribe treatment.
It does not replace clinical judgment. It is an evidence framework for
a pattern detection and self-awareness product.

Every statement the product makes to users must be traceable to a
section of this document. If an AI output makes a claim that cannot
be traced here, that output is outside the product's evidential basis
and should not ship.

### The clinical advisor's role

Before launch, a licensed clinical advisor — preferably with both
couples therapy expertise and cross-cultural psychology experience —
must review this document in full and provide written sign-off on:

- The choice of instrument for each framework
- The specific question wording for all quizzes
- The AI output constraints for each framework
- The cultural calibration section's adequacy for the target market
- The safety system classification tiers

The credential line in all Attune marketing and the product itself
("Psychological frameworks reviewed by [name, credentials]") is
contingent on this review being completed and documented.

---

## 2. THE WEIRD POPULATION PROBLEM

### What WEIRD means

WEIRD stands for Western, Educated, Industrialised, Rich, and Democratic.
The term was introduced by Henrich, Heine, and Norenzayan (2010) to
describe the narrow population on which the vast majority of psychological
research has been conducted.

Studies published between 2014 and 2017 found that 95% of psychology
research samples were drawn from WEIRD populations. Africa, representing
17% of the global population, contributed less than 1% of research samples
during the same period.

### Why this matters specifically for Attune

Every framework Attune uses — the ECR-R attachment instrument, Gottman's
four horsemen, love languages, NVC, the pursue-withdraw pattern — was
developed on and primarily validated against WEIRD populations. Attune is
being built in Ghana for an initial user base that includes West African
couples. The population mismatch is significant and must be acknowledged
explicitly in three places: this document, the soul document, and any
external communications about the product's psychological basis.

### What the research says about cross-cultural validity

The WEIRD bias does not mean these frameworks are wrong or inapplicable
in non-Western contexts. It means their direct transference requires
caution, explicit acknowledgment of limitations, and active calibration
work. The research distinguishes between:

**Structural universality** — the basic architecture of a framework
(e.g. the two dimensions of attachment anxiety and avoidance) may hold
across cultures even when the specific expression and distribution of
those dimensions varies.

**Normative variation** — what counts as a healthy or normative level
of a measured dimension may differ significantly between cultures. A
score that indicates avoidant attachment in a US sample may represent
culturally normative emotional restraint in a Ghanaian sample.

**Instrument validity** — the specific questions used to measure a
construct may carry cultural assumptions that make them less valid
in non-Western contexts even when the underlying construct is universal.

All three of these distinctions are addressed for each framework in
Sections 3 through 8. The cross-cutting cultural calibration section
covering Ghana and West Africa is in Section 9.

### The honest position Attune takes

Attune uses the best available validated instruments while explicitly
acknowledging their WEIRD origin. The product does not claim cultural
validation it does not have. The clinical advisor review is specifically
intended to address the most significant cultural mismatches before
deployment. Post-launch data collection from the actual user base
should be used to refine framework calibration over time.

This honest position must be reflected in the product's clinical
credential statement: "Psychological frameworks reviewed and calibrated
for cross-cultural use by [name, credentials]. These frameworks are
based on peer-reviewed research and have been adapted where evidence
supports cultural variation."

---

## 3. FRAMEWORK 1 — ATTACHMENT THEORY AND THE ECR-R

### 3.1 Source and research basis

**Founder:** John Bowlby (1907–1990)
**Core work:** Attachment and Loss trilogy (1969, 1973, 1980); A Secure Base (1988)

Bowlby proposed that humans have an innate need for close emotional bonds
and that early caregiving experiences create internal working models —
mental representations of the self, others, and relationships — that
persist into adult relational behaviour. These models operate largely
outside conscious awareness and guide how people seek or avoid closeness,
how they respond to perceived abandonment, and how they regulate emotion
in intimate relationships.

The extension to adult romantic attachment was made by Hazan and Shaver
(1987), who demonstrated that the three attachment patterns identified in
infants — secure, anxious-ambivalent, and avoidant — had measurable
parallels in adult romantic relationships.

### 3.2 The validated instrument — ECR-R

**Instrument:** Experiences in Close Relationships — Revised (ECR-R)
**Authors:** Fraley, Waller, and Brennan (2000)
**University of Illinois at Urbana-Champaign**

The ECR-R is the gold standard self-report measure of adult attachment
in romantic relationships. It measures two continuous dimensions:

- **Attachment anxiety:** the degree to which a person fears rejection,
  abandonment, and partner unavailability. High anxiety = preoccupied
  with partner's availability and responsiveness.
- **Attachment avoidance:** the degree to which a person is uncomfortable
  with closeness and depending on others. High avoidance = suppresses
  attachment needs, values independence defensively.

**Format:** 36 items on a 7-point Likert scale (1 = strongly disagree,
7 = strongly agree)

**Psychometric properties:**
- Internal consistency: Cronbach's alpha 0.88 (avoidance) and 0.86 (anxiety)
- Good test-retest reliability over short periods
- Predictive validity for conflict resolution styles and emotional support
  behaviours
- Developed using Item Response Theory (IRT) methods, giving it superior
  psychometric properties compared to earlier measures

**The four attachment types as quadrants, not categories:**
The four commonly named attachment types (secure, anxious-preoccupied,
dismissive-avoidant, fearful-avoidant) are quadrants in the two-dimensional
anxiety × avoidance space, not discrete categories. Every person has
scores on both dimensions. The product must display results as spectrums,
not as fixed type labels.

```
HIGH AVOIDANCE
        |
Dismissive- |  Fearful-
avoidant    |  avoidant
            |
LOW --------+-------- HIGH
ANXIETY     |          ANXIETY
            |
Secure      |  Anxious-
            |  preoccupied
LOW AVOIDANCE
```

### 3.3 How Attune uses this instrument

**What the quiz measures:**
The Attune attachment quiz measures the same two dimensions as the ECR-R
using conversationally rewritten questions. Each question is mapped to
its underlying construct (anxiety or avoidance dimension) and reviewed
by the clinical advisor for construct validity after rewriting.

**Instrument length decision — unresolved:**
The original ECR-R is a 36-item validated instrument. The current master
spec references a 25-question Attune attachment quiz. These two facts
cannot coexist without an explicit instrument decision. Attune must choose
one of three paths before launch:

1. Use all 36 ECR-R items, conversationally rewritten and advisor-reviewed.
2. Use a published shortened instrument such as the ECR-RS, with its own
   validation basis documented.
3. Use a 25-item ECR-R-inspired adaptation, explicitly acknowledging that
   it is not the ECR-R and requires clinical advisor sign-off on the
   validation gap.

This is tracked as an open launch question in Section 12.

**What the AI is allowed to conclude:**
- Where the user sits on the anxiety and avoidance dimensions (as a spectrum)
- How this position tends to manifest in communication behaviour
  (as a description, not a diagnosis)
- How this position may interact with a partner's position to create
  specific relational dynamics
- How observed chat patterns validate or contextualise the quiz scores

**What the AI is never allowed to conclude:**
- That the user has an attachment disorder
- That the user's attachment style is permanent or unchangeable
- That a specific attachment combination is incompatible or doomed
- That one attachment style is superior to another
- Anything diagnostic about the partner based on the user's quiz results

### 3.4 Known limitations

**Self-report bias:** The ECR-R is self-report. People's awareness of
their own attachment behaviour may be limited, particularly for avoidant
individuals who may underreport closeness needs. The AI's observation
of actual communication patterns over time provides a behavioural
counterpoint that self-report cannot.

**State vs trait:** Attachment orientations are relatively stable but
not fixed. Life events, therapy, new relationships, and personal growth
all shift attachment patterns. The quiz should be retakeable and the
result explicitly framed as a current snapshot, not a permanent identity.

**Social desirability:** People may answer questions to present as
more secure than they are. This bias is reduced but not eliminated
by the ECR-R's indirect item phrasing.

**Cultural limitations (critical for Attune's user base):**
The ECR-R was developed and primarily validated on Western university
student samples. Its cross-cultural validity has been studied in East
Asian, Middle Eastern, and some African contexts but not specifically
in Ghana. The primary cultural risk is the avoidance dimension: in
collectivist, high-context cultures where emotional restraint is
normative and valued, high avoidance scores may reflect cultural
communication norms rather than defensive psychological independence.

**Specific calibration required by clinical advisor:**
- Review of question wording for cultural appropriateness in Ghanaian context
- Assessment of whether the avoidance dimension threshold scores require
  cultural adjustment for West African users
- Review of whether the normative distribution of the Ghanaian user base
  differs significantly from the Western validation samples

---

## 4. FRAMEWORK 2 — GOTTMAN'S FOUR HORSEMEN

### 4.1 Source and research basis

**Researcher:** John Gottman, University of Washington Love Lab
**Core period:** 1970s–2000s, ongoing
**Sample:** 3,000+ couples observed over four decades

John Gottman and his colleagues conducted longitudinal observational
studies of couples in conflict, tracking their communication patterns
and following up on relationship outcomes over six to fourteen years.
His research identified four communication patterns that predict
relationship dissolution with approximately 93-94% accuracy.

**Priority verification required:** this figure is widely cited but
often simplified in secondary sources. Before external use, verify
the exact study design, sample, outcome definition, and statistical
basis in the original Gottman/Levenson publications.

**The Four Horsemen:**
1. **Criticism** — attacking a partner's character rather than a
   specific behaviour. Distinguishable from complaints, which address
   specific behaviours without character attribution.
2. **Contempt** — communicating superiority through eye-rolling,
   mockery, dismissiveness, and sarcasm used as a weapon.
   Contempt is the single strongest predictor of relationship failure.
3. **Defensiveness** — responding to a perceived attack by
   counter-attacking or claiming victimhood, which escalates conflict.
4. **Stonewalling** — withdrawing from interaction, shutting down,
   ceasing to respond. Usually a response to flooding
   (physiological overwhelm during conflict).

**Additional validated concepts:**
- **Bids for connection:** micro-moments of reaching for emotional
  contact. Partners either turn toward (acknowledge), turn away
  (ignore), or turn against (respond negatively).
- **The 5:1 ratio:** stable relationships show a minimum 5:1 ratio
  of positive to negative interactions during conflict.
- **Repair attempts:** actions taken to de-escalate during conflict.
  Whether repair attempts land is a strong predictor of relationship health.
- **Physiological flooding:** heart rate above approximately 100 bpm
  during conflict, at which point effective communication becomes
  physiologically impossible. Stonewalling is often a flooding response.

### 4.2 How Attune uses this framework

**What the AI is allowed to conclude:**
- The presence or absence of specific four horsemen signals in text
  (flagged as patterns over sessions, never per individual message)
- Whether bid-for-connection moments are being met with turning toward,
  away, or against responses
- Whether repair attempts are being made and whether they appear to land
- Escalation trajectory within a session
- The 5:1 ratio approximation across a relationship period

**What the AI is never allowed to conclude:**
- That a single message constitutes contempt, criticism, or any horseman
  (patterns across sessions required)
- That the presence of a horseman means the relationship is failing
- Anything diagnostic about either person's psychology from communication
  patterns alone
- That stonewalling is a character flaw rather than a physiological response

### 4.3 The critical gap — observed behaviour vs text analysis

**This is the most important limitation in the entire clinical document.**

Gottman's research was conducted through observation of couples in a
controlled setting with video recording, coding by trained observers,
and physiological monitoring. The four horsemen were identified and
validated as patterns in observed, embodied, real-time behaviour.

Attune detects these patterns in text messages. This is a fundamentally
different signal source. Text communication:
- Lacks tone of voice, facial expression, and body language
- Lacks physiological data (heart rate, skin conductance)
- Is asynchronous and edited, unlike spoken conflict
- May represent one moment in a longer emotional exchange

**The clinical implication:** Attune's text-based detection of four
horsemen signals is a reasonable analogy to Gottman's observational
coding but it is not equivalent to it. The product must never claim
Gottman-equivalent predictive accuracy from text analysis alone.

**The implementation rule this creates:**
Text-based horsemen detection is flagged as a signal, not a finding.
Individual sessions generate signals. Patterns across multiple sessions
generate insights. The AI output level is calibrated accordingly:

- Single session with horsemen signals → session flag only, not surfaced
- 3+ sessions with same horsemen pattern → insight surfaced, medium confidence
- 6+ sessions with pattern → watch area in verdict, cited as pattern
- Contempt detected even once → immediate flag given its predictive weight

### 4.4 Known limitations

**Observer coding vs AI text analysis:** See Section 4.3. This is the
primary limitation and must be disclosed to the clinical advisor for
explicit sign-off on whether text-based detection meets the minimum
standard for responsible deployment.

**Cultural expression of conflict:** Gottman's research was conducted
primarily on American couples. Conflict expression styles, what
constitutes direct criticism vs culturally normative directness,
and the meaning of silence (stonewalling vs respectful restraint)
vary across cultures. In Ghana specifically, indirect communication
in conflict is normative and may read as avoidance where it is
actually culturally appropriate restraint.

**Specific calibration required by clinical advisor:**
- Review of whether text-based detection is a responsible application
  of Gottman's observational framework
- Assessment of culturally normative conflict communication in Ghana
  and whether the four horsemen definitions require cultural adjustment
- Sign-off on the per-session vs cross-session thresholds before any
  horsemen detection is surfaced to users

---

## 5. FRAMEWORK 3 — LOVE LANGUAGES

### 5.1 Source and the scientific critique

**Author:** Gary Chapman, Baptist minister and marriage counsellor
**Core work:** The Five Love Languages: The Secret to Love That Lasts (1992)

Chapman proposed five categories through which people prefer to give
and receive love: words of affirmation, quality time, acts of service,
physical touch, and receiving gifts. His claim: relationship satisfaction
improves when partners learn to speak each other's primary love language.

### 5.2 The 2024 peer-reviewed critique — mandatory reading

**Authors:** Impett, E.A., Park, G., and Muise, A.
**Journal:** Current Directions in Psychological Science (2024)
**DOI:** 10.1177/09637214231217663

This review is the most important research development affecting Attune's
use of love languages. The researchers reviewed ten studies on love
languages and found that **none of them supported Chapman's core claims.**

Specific findings that directly affect the product:

**Finding 1: The matching hypothesis fails.**
Chapman's central claim is that couples whose love languages match
are more satisfied. Three studies, including one using Chapman's own
quiz, found that couples with matching love languages were no more
satisfied than couples with mismatched love languages.

**Finding 2: All love languages are associated with satisfaction.**
Expressions of all five love languages were positively associated with
relationship satisfaction regardless of a person's stated preference.
The specific love language expressed matters less than the fact of
expression itself.

**Finding 3: The forced-choice quiz produces artefacts.**
Chapman's quiz forces respondents to choose between love language
options, which may create a false sense of having one primary language
rather than reflecting genuine preference complexity.

**Finding 4: The framework lacks peer-reviewed development.**
Chapman developed his framework from pastoral counselling observations,
not systematic research. The love languages have popular validity —
they resonate with many people and provide a useful vocabulary — but
they lack the empirical foundation of attachment theory or Gottman's
observational research.

### 5.3 How Attune uses this framework given the critique

The 2024 critique does not mean love languages should be removed from
Attune. It means the product must be honest about what the quiz does
and does not establish, and the AI must not make claims the research
does not support.

**What the love language quiz IS in Attune:**
A self-awareness tool that gives users vocabulary for articulating
how they prefer to give and receive affection. Useful as a conversation
starter. Useful for personalising weekly intimacy challenges and
first-date guide suggestions. Useful for helping users reflect on
their own relational preferences.

**What the love language quiz IS NOT in Attune:**
A compatibility scoring input. The AI must never generate compatibility
insights based on love language match or mismatch, because the research
does not support that matching predicts relationship satisfaction.

**Specific output rules:**
The AI can say: "You tend to feel most appreciated through quality time.
Here are ways your partner might express that."

The AI cannot say: "Your love languages don't match Jordan's, which
may be causing disconnection" — because the research does not support
love language mismatch as a predictor of disconnection.

### 5.4 Known limitations

All of the above. Additionally:

**Cultural limitation:** Chapman's framework was developed from pastoral
counselling of predominantly American Christian couples. The five
categories reflect Western, individualist assumptions about how affection
is expressed. In collectivist African contexts, affection may be expressed
primarily through communal participation, extended family involvement,
and obligation fulfilment — none of which map cleanly to Chapman's five
categories. This requires specific review.

**FRAMEWORK_CONFIDENCE: LOWER**
This is the only framework in Attune rated at lower confidence.
The quiz remains in the product because users find it useful and it
enables personalisation. But the AI output from love language data
must be explicitly modest and never predictive of compatibility.

---

## 6. FRAMEWORK 4 — NONVIOLENT COMMUNICATION

### 6.1 Source and research basis

**Developer:** Marshall Rosenberg, PhD (1934–2015), clinical psychologist
**Core work:** Nonviolent Communication: A Language of Life (2003)
**Development period:** 1960s–1970s

Rosenberg developed NVC from a background in humanistic psychology,
influenced by Carl Rogers' client-centred therapy and Gandhian principles
of nonviolence. The framework has four components applied in sequence:

1. **Observation:** describing what happened without evaluation or judgment
   ("When you arrived 30 minutes late" not "when you were inconsiderate")
2. **Feeling:** expressing the emotional response without blame
   ("I felt anxious" not "you made me feel anxious")
3. **Need:** identifying the underlying need the feeling points to
   ("because I need to feel that our time matters")
4. **Request:** making a specific, actionable, non-coercive request
   ("Would you be willing to let me know when you'll be late?")

NVC has been applied in conflict mediation in 60+ countries, healthcare
settings, educational institutions, and couples therapy.

### 6.2 Evidence base — honest assessment

NVC has a different evidentiary basis than attachment theory or Gottman's
research. It was developed from practitioner observation and clinical
experience, not from systematic research with control groups and
outcome measurement.

**What exists:**
- Outcome evaluation studies showing improvements in interpersonal
  relationships after NVC training in healthcare settings
- Practitioner literature reporting decades of application across
  diverse conflict contexts
- Theoretical alignment with Carl Rogers' client-centred therapy,
  which has strong empirical support
- Widespread adoption by couples therapists as a practical communication tool

**What is limited:**
- Few randomised controlled trials testing NVC specifically
- Limited peer-reviewed validation compared to attachment theory
  (which has decades of RCT-backed research)
- Rosenberg himself did not connect NVC to broader psychology research,
  which one critic noted situates it "more in the self-help camp than
  the serious psychology camp"

### 6.3 How Attune uses this framework

NVC provides the four-component structure that the conflict translator
implicitly follows when rewriting charged messages. The translator
moves messages from observation-mixed-with-evaluation toward cleaner
observation, from blame toward feeling expression, from demand toward
request.

**What the translator is allowed to do:**
- Rewrite accusation-heavy messages toward need expression
- Identify the underlying need in a charged message
- Offer one alternative phrasing the user can choose or reject

**What the translator is never allowed to do:**
- Tell the user their original message was wrong
- Appear automatically without user request
- Produce a rewrite that adds false warmth or false apology
- Produce a rewrite so sanitised it no longer represents the user's
  actual feeling or concern

**The private framing note:**
After a translator rewrite, a private note is shown to the sender only:
"underlying need: to feel heard." This is the NVC insight made visible.
The note is never shown to the recipient.

### 6.4 Known limitations

**Limited RCT evidence:** NVC's evidence base is practitioner-strong
but research-thin. The product must not claim clinical validation for
NVC-based features at the same level it claims for ECR-R-based features.

**Cultural fit in Ghana:**
NVC's explicit, direct verbal expression of feelings and needs ("I feel X
because I need Y") is a low-context communication model. Ghana is a
high-context culture where indirect speech, implied meaning, and emotional
restraint are normative. NVC phrasing may feel foreign, overly vulnerable,
or even disrespectful in some Ghanaian communication contexts.

This is a significant calibration challenge for the translator. Rewrites
need to be reviewed for whether they sound like natural, culturally
appropriate Ghanaian relationship communication or like a foreign
communication style being imposed.

**FRAMEWORK_CONFIDENCE: MEDIUM**
Solid practitioner basis, clinically useful, limited peer-reviewed
validation. AI output using NVC signals should be appropriately hedged.

---

## 7. FRAMEWORK 5 — PURSUE-WITHDRAW PATTERN

### 7.1 Source and research basis

**Primary researcher:** Sue Johnson, EdD (1947–2024)
**Framework:** Emotionally Focused Therapy (EFT)
**Evidence base:** 35+ years of peer-reviewed clinical research
**Efficacy:** 70-75% of couples moved from distress to recovery
in randomised controlled trials, maintained at 2-year follow-up

The pursue-withdraw pattern is the most commonly observed negative
interaction cycle in distressed couples. Johnson's research, grounded
in Bowlby's attachment theory, explains the dynamic as an attachment
system response:

**The pursuer** (typically higher attachment anxiety) escalates
attempts at emotional contact when sensing distance or disconnection.
They send more messages, raise their voice, push for resolution,
and become more intense because their attachment system is alarmed.

**The withdrawer** (typically higher attachment avoidance) reduces
responsiveness when sensing pressure or emotional flooding. They go
quiet, give shorter responses, need space, and may physically or
digitally disengage. This is not indifference — it is a nervous system
attempting to regulate overwhelming emotional input.

The cruel irony: the pursuer's escalation triggers more withdrawal.
The withdrawer's silence triggers more pursuit. Neither person is wrong.
Both are responding to the same underlying fear — that the attachment
bond is threatened — with opposite nervous system responses.

### 7.2 How Attune uses this framework

**What the AI is allowed to conclude:**
- That a pursue-withdraw dynamic appears to be present in session data
  (based on message volume patterns, response latency, and session
  resolution rates across multiple sessions)
- The general role each person tends to play in this dynamic
  (shown privately to each user only — never shown to the other)
- That this is a dynamic, not a character flaw in either person

**What the AI is never allowed to conclude:**
- That one person is "the pursuer" as a fixed identity
- That the other person is "withdrawing from you" — framed as a
  description of the partner rather than the dynamic
- That this pattern predicts relationship failure
- Anything about the partner's internal emotional state

**The asymmetric data rule applies here without exception:**
"Pursue-withdraw detected" is shared with both users.
"You tend to pursue" is shown privately to that user.
"Jordan tends to withdraw" is never generated or stored.

### 7.3 Known limitations

**Text vs observed behaviour:** The same gap identified for Gottman
applies here. Johnson's research used video observation and coded
behavioural sequences in therapy settings. Attune detects analogous
patterns in text messages. Message volume and response latency are
reasonable proxies for pursuit and withdrawal behaviours in digital
communication, but they are proxies, not the original signal.

**Cultural expression:** The pursue-withdraw pattern may express
differently in high-context cultures where silence is not always
withdrawal and where emotional restraint is normative. The threshold
for what constitutes withdrawal in a Ghanaian communication context
may be different from a Western context.

**FRAMEWORK_CONFIDENCE: MEDIUM**
Strong research basis in EFT literature, well-validated construct,
reasonable text-based proxy detection. Threshold calibration requires
cultural review.

---

## 8. FRAMEWORK 6 — THE NEEDS TAXONOMY

### 8.1 Source and research basis

**Primary source:** Abraham Maslow (1908–1970)
**Core work:** A Theory of Human Motivation (1943);
Motivation and Personality (1954)

**Secondary sources:** Marshall Rosenberg's universal human needs
framework (NVC); Sue Johnson's attachment needs framework (EFT)

Attune's AI identifies six root need categories when analysing what
a conflict is fundamentally about beneath its surface content:

```
respect     — the need to be treated as a person of worth
fairness    — the need for equitable treatment and reciprocity
affection   — the need to feel loved, appreciated, and desired
security    — the need to feel safe, stable, and not at risk
             of abandonment
autonomy    — the need to feel one's choices and independence
             are respected
rest        — the need for recovery, space, and freedom from
             demands
```

These six categories are a distillation of:
- Maslow's love/belonging and esteem needs (the two tiers most
  relevant to intimate relationship conflict)
- Rosenberg's universal human needs list (filtered to the six most
  commonly underlying relationship conflict)
- Johnson's attachment needs framework (specifically security and
  affection as attachment-core needs)

### 8.2 How Attune uses this taxonomy

When the Layer 2 session analysis identifies an insight-worthy conflict,
the AI attempts to identify which of the six root needs is most likely
underlying the surface content of the conflict.

**Example application:**
Surface content: repeated argument about who does household chores
Root need most likely: fairness (equitable treatment), possibly
rest (depletion and need for recovery)
Not the root need: affection (the fight is about fairness, not
about feeling unloved — though both may be present)

**What the AI is allowed to say:**
"The conflict in this session appears to be connected to a need for
fairness — specifically, a sense that contributions are not being
recognised equally."

**What the AI is never allowed to say:**
"Jordan doesn't appreciate what you do." — partner attribution.
"You have a fairness issue in this relationship." — pathologising.
"This need is causing problems." — the need is legitimate, not a problem.

### 8.3 Known limitations

**Taxonomy is derived, not directly validated:**
The six-category needs taxonomy is a practitioner synthesis, not a
validated psychological instrument. It is grounded in respected sources
(Maslow, Rosenberg, Johnson) but the specific combination and weighting
has not been independently validated. The clinical advisor must review
whether these six categories are appropriate, sufficient, and mutually
distinct enough for accurate classification.

**Cultural needs variation:**
In Ghanaian and West African contexts, communal obligation and
extended family wellbeing function as significant relational drivers
that are not captured by any of the six current categories. A couple
experiencing conflict because of family pressure around marriage timing,
bride price expectations, or extended family obligations may be
experiencing something that maps poorly onto the current taxonomy.

**A seventh category — communal obligation — is recommended for review:**
```
communal obligation — the need to fulfil responsibilities to
                      extended family and community, which in
                      collectivist cultures is inseparable from
                      the intimate relationship itself
```

This category requires clinical advisor input on whether to add it
to the taxonomy and, if so, how to define it precisely enough for
AI classification.

---

## 9. CULTURAL CALIBRATION — GHANA AND WEST AFRICA

The following characterisation of Ghanaian relational norms is compiled
from published research and practitioner literature. It is directionally
useful for identifying calibration questions, but it should not be treated
as authoritative without review by someone with deep expertise in Ghanaian
relationship psychology and cultural practice. The clinical advisor review
in Section 11 includes specific items requiring this expertise.

### 9.1 The WEIRD bias applied to Attune's specific user base

All frameworks in this document were developed primarily on Western,
educated, individualised populations. Attune is being built in Ghana,
a country characterised by:

- **High collectivism:** Sub-Saharan Africa ranks among the highest
  regions globally for collectivist cultural orientation. Individual
  identity is deeply embedded in community, family, and relational
  obligation.
- **High-context communication:** Ghana is a high-context culture
  where non-verbal cues, indirect speech, implied meanings, and
  silence carry significant communicative weight. Direct verbal
  expression of feelings and needs — the model underlying NVC —
  is not the default.
- **Extended family involvement in romantic relationships:** Family
  approval, traditional marriage rites, bride price, lineage
  considerations, and extended family obligations are active
  participants in the romantic relationship, not external to it.
- **Hierarchy and respect norms:** Respect for elders, deference
  to family authority figures, and avoidance of direct confrontation
  with senior figures are normative. These norms extend into
  romantic relationships and affect how conflict is expressed and
  resolved.
- **Mental health stigma:** Research confirms significant mental
  health stigma in Ghana, including self-stigma that reduces
  willingness to seek professional psychological help. This affects
  how professional referrals in the product should be worded.

### 9.2 Ubuntu — the African philosophical framework

Ubuntu (from Bantu languages: "umuntu ngumuntu ngabantu" — a person
is a person through other people) is the foundational African
philosophical framework for understanding identity, relationships,
and wellbeing.

Ubuntu contrasts with Western attachment theory in a specific way:
Western attachment theory asks "how does this individual regulate
their need for closeness and independence?" Ubuntu asks "how does
this person fulfil their role in a web of relationships?" These
are different questions with different implications for what
a healthy relationship looks like.

**Key Ubuntu principles relevant to Attune:**
- Identity is relational, not individual. A person's sense of self
  is constituted through relationships, not independent of them.
- The wellbeing of the individual and the community are inseparable.
  A relationship's health cannot be assessed in isolation from its
  community context.
- Conflict resolution is communal, not purely dyadic. Traditional
  African conflict resolution involves community members, elders,
  and family in ways that Western dyadic couples therapy does not.
- Interconnectedness is a source of strength, not a sign of dependence.
  High relatedness scores on Western instruments may reflect Ubuntu
  values rather than anxious attachment.

**The research supports this:**
A Frontiers in Psychology study (Wissing et al., 2020) found that
in Ghanaian and South African contexts, relationships function as
primary sources of meaning in ways that individualist Western theories
do not fully capture. The study emphasised the importance of developing
contextually relevant wellbeing frameworks rather than transferring
Western models uncritically.

### 9.3 Specific calibration requirements by framework

**Attachment quiz (ECR-R):**
Avoidance dimension questions require review for cultural appropriateness.
Questions about independence, not sharing feelings, and preferring not
to depend on partners may capture Ubuntu-consistent relational norms
rather than defensive avoidance. The clinical advisor should review
whether avoidance dimension thresholds require cultural adjustment.

Recommended question types to flag for review:
- "I prefer not to share my feelings with my partner"
  (may reflect respectful restraint, not avoidance)
- "I find it difficult to depend on others"
  (Ubuntu relational identity may not map onto this)
- "I don't feel comfortable opening up to romantic partners"
  (high-context communication norms may produce culturally
  normative responses that read as avoidant)

**Four horsemen detection:**
Stonewalling detection in text requires cultural calibration. Silence
and reduced responsiveness in Ghanaian communication may represent
culturally normative respectful restraint or space-giving, not the
physiological flooding-induced withdrawal that Gottman identifies.

The contempt detection framework was validated on American samples
where certain sarcasm and eye-rolling indicators are unambiguous.
In high-context cultures where sarcasm operates differently, the
detection thresholds need review.

**NVC conflict translator:**
The four-component NVC structure requires review for whether it
produces culturally authentic communication or imposes a Western
direct-expression model that will feel alien to Ghanaian users.

The translator may need culturally sensitive alternatives that
achieve the same underlying goal — moving from accusation to need
expression — through indirect, face-saving, high-context language
patterns that are normative in Ghanaian communication.

**Needs taxonomy:**
The communal obligation category addition should be evaluated by the
clinical advisor specifically for the West African context. The current
six categories do not account for the relationship strain that arises
from extended family obligations, traditional practices, and community
expectations — which are primary sources of couple conflict in
Ghanaian relationships.

**Professional referral language:**
Given documented mental health stigma in Ghana, the product's language
when suggesting professional support should avoid clinical framing.

Instead of: "Consider speaking with a therapist"
Consider: "Talking with someone you trust outside the relationship"
or: "Getting a trained outside perspective"

The clinical advisor should review all safety resource and professional
referral copy for appropriateness in the Ghanaian context.

### 9.4 The honest position on cultural calibration

Attune will launch without a Ghana-specific validation study for any
of its frameworks. This is an unavoidable reality of the build timeline.

The honest position the product takes:
1. Acknowledge the WEIRD origin of all frameworks
2. Have clinical advisor review for the most significant cultural
   mismatches before launch
3. Collect data from the actual user base post-launch and use it
   to refine calibration
4. Flag in the product's credential statement that frameworks have
   been reviewed for cross-cultural use, not that they have been
   independently validated for the Ghanaian context

This is honest. It is better than pretending the gap does not exist.
And it creates a concrete research agenda for post-launch improvement.

---

## 10. FRAMEWORK CONFIDENCE LEVELS

These confidence levels govern how strongly the AI is permitted to
state observations derived from each framework. They apply to every
insight card, verdict section, and pattern detection output.

```
FRAMEWORK               CONFIDENCE    RATIONALE
──────────────────────────────────────────────────────────────────
ECR-R attachment quiz   HIGH          Strong psychometric validation,
                                      36-item instrument, IRT-developed,
                                      good cross-cultural structural validity
                                      NOTE: avoidance dimension requires
                                      cultural calibration for Ghana

Gottman bids for        HIGH          Decades of observational research,
connection                            well-validated construct, text-based
                                      detection is reasonable proxy

Repair attempt          HIGH          Well-validated in EFT and Gottman
detection                             research, clear behavioural markers

Response latency        HIGH          Objective measurement, not construct-
patterns                              dependent, culturally robust

Pursue-withdraw         MEDIUM        Strong EFT research basis, text-based
pattern detection                     detection is proxy, cultural expression
                                      variation requires calibration

NVC violation           MEDIUM        Solid practitioner basis, limited RCT
detection                             evidence, high-context culture fit
                                      requires review

Session escalation      MEDIUM        Reasonable text proxies, validated
trajectory                            direction of construct, threshold
                                      calibration required

Attachment quiz         MEDIUM        Self-report limitations, state vs trait
interpretation                        ambiguity, avoidance dimension cultural
                                      calibration required

Love language quiz      LOWER         2024 peer-reviewed critique confirms
interpretation                        matching hypothesis does not hold,
                                      Chapman's framework lacks systematic
                                      validation, Western cultural assumptions

Contempt detection      LOWER         Highly context-dependent, cultural
                                      variation in sarcasm and dismissiveness,
                                      text-based detection misses non-verbal
                                      indicators that define contempt
```

### AI output language by confidence level

```
HIGH confidence — state directly:
"Your repair attempt rate has increased significantly over three months."

MEDIUM confidence — qualify appropriately:
"Some patterns in these sessions suggest a pursue-withdraw dynamic
may be present."
"Based on your quiz results, you tend toward higher attachment anxiety,
which often shows up as..."

LOWER confidence — explicit hedge, user decides:
"This is one possible interpretation — it may or may not apply to you."
"Your love language quiz results suggest you tend to feel most
appreciated through quality time. This is a starting point for
reflection, not a definitive profile."
```

---

## 11. CLINICAL ADVISOR REVIEW CHECKLIST

This checklist is for the clinical advisor engaged in Month 1.
Every item must receive explicit written sign-off before the
relevant psychologically interpretive feature is deployed.

### Safety tier cross-reference

The full safety system definition lives in ATTUNE_MASTER_SPEC.md
Section 8.7. This document does not duplicate it to avoid drift.
For clinical review, the three tiers are:

```
Tier 1: Explicit threats
  Immediate notification, prominent resources

Tier 2: Isolation/control language
  Quiet notification, softer framing

Tier 3: Pattern-based safety concern
  Fires only after 3+ occurrences in pattern memory
```

Clinical review should evaluate whether these tier categories, trigger
families, and user-facing actions are appropriate. The source of truth
for implementation details remains ATTUNE_MASTER_SPEC.md Section 8.7.

### Attachment framework review

```
□ Review ECR-R instrument choice — is this the right instrument for
  this product, this user base, and this cultural context?

□ Resolve the attachment item-count decision: full 36-item ECR-R,
  published shortened instrument such as ECR-RS, or explicit
  25-item ECR-R-inspired adaptation with documented validation gap

□ Review all selected attachment quiz questions for construct
  validity after conversational rewriting — does each question
  still measure its intended construct?

□ Flag any questions that may carry Western cultural assumptions
  problematic for Ghanaian users, particularly on the
  avoidance dimension

□ Advise on whether avoidance dimension thresholds require
  cultural adjustment for West African users

□ Review the four-type presentation (quadrant model, not discrete
  categories) and confirm it is clinically appropriate

□ Advise on whether the self-report limitation requires any
  specific disclosure to users
```

### Gottman framework review

```
□ Review and sign off on whether text-based detection of four
  horsemen signals is a responsible application of Gottman's
  observational framework

□ Verify whether the 93-94% relationship dissolution accuracy claim
  is accurately represented given the original study design,
  sample, outcome definition, and statistical basis

□ Review the contempt detection approach specifically —
  highest-weight signal, highest cultural variation risk

□ Review cultural calibration of stonewalling detection
  for high-context Ghanaian communication norms

□ Advise on per-session vs cross-session threshold settings
  before any horsemen-based insight is surfaced to users

□ Review the bids-for-connection detection approach and confirm
  it is well-founded for text-based detection
```

### Love languages review

```
□ Confirm that the quiz is appropriately positioned as a
  self-awareness tool, not a compatibility scoring input

□ Review all quiz questions for Western cultural assumptions
  that may not translate to Ghanaian relationship expression

□ Advise on whether to add or substitute culturally relevant
  love expression categories for the West African context

□ Confirm that no AI output makes love language matching claims
  inconsistent with the 2024 Impett et al. critique
```

### NVC framework review

```
□ Review the conflict translator rewrite approach for clinical
  appropriateness

□ Assess whether the four-component NVC structure produces
  culturally authentic rewrites for Ghanaian users or imposes
  a foreign communication model

□ Advise on culturally appropriate alternatives if the standard
  NVC phrasing is not appropriate for the target market

□ Review the private framing note (shown to sender only) for
  clinical appropriateness and potential unintended effects
```

### Needs taxonomy review

```
□ Review the six root need categories for clinical accuracy
  and mutual exclusivity

□ Advise on whether to add a seventh category for communal
  obligation specifically for the Ghanaian/West African context

□ Review sample AI outputs using the needs taxonomy for
  clinical appropriateness
```

### Cultural calibration review

```
□ Confirm the document's characterisation of Ghanaian
  communication styles and relational norms is accurate

□ Advise on Ubuntu framework integration — is it appropriately
  described and are its implications for the product correctly
  identified?

□ Review professional referral language for appropriateness
  in the Ghanaian mental health stigma context

□ Advise on any additional cultural considerations not
  covered in Section 9

□ Confirm whether the WEIRD limitation disclosures are
  appropriately scoped
```

### Safety system review

```
□ Review the three-tier safety trigger classification
  for clinical appropriateness

□ Advise on whether the trigger word lists are appropriate
  given the product's cultural context

□ Review the safety resources screen content and language
  for appropriateness and accuracy of hotline information

□ Confirm the crisis resource referral language is appropriate
  for the Ghanaian mental health stigma context

□ Sign off on the explicit statement that the safety system
  does not constitute a clinical safety assessment
```

---

## 12. OPEN QUESTIONS BEFORE LAUNCH

Items that require resolution before the relevant psychologically
interpretive feature deploys.
Each item has an owner and a target resolution date.

```
[OPEN] ECR-R cultural calibration for Ghana
  Question: Does the avoidance dimension require threshold
            adjustment for West African users?
  Owner: Clinical advisor
  Required before: Attachment quiz launch (Month 1)

[OPEN] Attachment instrument length decision
  Question: Should Attune use the full 36-item ECR-R, a published
            shortened instrument such as ECR-RS, or a 25-item
            ECR-R-inspired adaptation with an acknowledged
            validation gap?
  Owner: Product + clinical advisor
  Required before: Attachment quiz launch (Month 1)

[OPEN] Text-based four horsemen detection — responsible application?
  Question: Does text-based detection meet the clinical standard
            for responsible application of Gottman's framework?
  Owner: Clinical advisor
  Required before: Session analysis layer goes live (Month 2)

[OPEN] NVC translator cultural fit
  Question: Do standard NVC rewrites sound natural and culturally
            appropriate to Ghanaian users?
  Owner: Clinical advisor + user testing with Ghanaian users
  Required before: Conflict translator launch (Month 2)

[OPEN] Communal obligation needs category
  Question: Should a seventh root need category covering communal
            obligation be added to the taxonomy?
  Owner: Clinical advisor
  Required before: Session analysis root need detection (Month 2)

[OPEN] Safety trigger list — cultural review
  Question: Are the tier-1 and tier-2 trigger categories appropriate
            for Ghanaian relationship communication norms?
  Owner: Clinical advisor + DV professional review
  Required before: Safety system launch (Month 3)

[OPEN] Professional referral language
  Question: Is the language used when recommending professional
            support appropriate given mental health stigma in Ghana?
  Owner: Clinical advisor
  Required before: Any professional referral content goes live

[OPEN] Love language quiz — cultural additions
  Question: Are there culturally relevant love expression categories
            for West African users that should supplement or replace
            any of Chapman's five categories?
  Owner: Clinical advisor
  Required before: Love language quiz launch (Month 2)

[RESOLVED — noted for record]
Love language compatibility scoring removed from product.
The 2024 Impett et al. critique confirmed the matching hypothesis
does not hold. Love languages are a self-awareness and
personalisation tool only, not a compatibility input.
```

---

## 13. RESEARCH REFERENCES

> All citations require independent verification before external use.

### Attachment theory

**Bowlby, J.** Attachment and Loss Vol. 1: Attachment. Basic Books, 1969.
**Bowlby, J.** A Secure Base. Basic Books, 1988.
**Hazan, C. and Shaver, P.** Romantic love conceptualised as an
  attachment process. Journal of Personality and Social Psychology, 1987.
**Fraley, R.C., Waller, N.G., and Brennan, K.A.** An item-response
  theory analysis of self-report measures of adult attachment.
  Journal of Personality and Social Psychology, 78(2), 350-365, 2000.

### Cross-cultural attachment

**Van Ijzendoorn, M.H. and Kroonenberg, P.M.** Cross-cultural patterns
  of attachment: A meta-analysis of the strange situation.
  Child Development, 59, 147-156, 1988.
**Agishtein, P. and Brumbaugh, C.** Cultural variation in adult
  attachment: The impact of ethnicity, collectivism, and country of
  origin. Journal of Social, Evolutionary, and Cultural Psychology,
  7(4), 384–405, 2013.
**Sakman, E. and Sümer, N.** Cultural correlates of adult attachment
  dimensions: Comparing the US and Turkey. Journal of Cross-Cultural
  Psychology, 2024.

### Gottman research

**Gottman, J.M.** What Predicts Divorce. Erlbaum, 1994.
**Gottman, J.M. and Levenson, R.W.** Marital processes predictive of
  later dissolution. Journal of Personality and Social Psychology,
  63(2), 221–233, 1992.
**Gottman, J.M. and Silver, N.** The Seven Principles for Making
  Marriage Work. Crown, 1999.

### Love languages critique

**Impett, E.A., Park, G., and Muise, A.** Popular psychology through
  a scientific lens: Evaluating love languages from a relationship
  science perspective. Current Directions in Psychological Science,
  2024. DOI: 10.1177/09637214231217663

### EFT and pursue-withdraw

**Johnson, S.M.** The Practice of Emotionally Focused Couple Therapy.
  3rd ed. Routledge, 2020.
**Johnson, S.M.** Hold Me Tight. Little, Brown, 2008.
**Wiebe, S.A. and Johnson, S.M.** A review of the research in
  emotionally focused therapy for couples. Family Process, 2016.

### NVC

**Rosenberg, M.B.** Nonviolent Communication: A Language of Life.
  PuddleDancer Press, 2003.

### Maslow

**Maslow, A.** A theory of human motivation. Psychological Review,
  50(4), 370-396, 1943.

### WEIRD bias

**Henrich, J., Heine, S.J., and Norenzayan, A.** The weirdest people
  in the world. Behavioral and Brain Sciences, 33(2-3), 61-83, 2010.
**The Decision Lab.** Behavioral Science is WEIRD and This Should
  Concern Us. 2024. (Non-peer-reviewed explainer, verify primary sources)

### Ghana and West Africa

**Wissing, M.P. et al.** Motivations for relationships as sources of
  meaning: Ghanaian and South African experiences. Frontiers in
  Psychology, 11, 2019, 2020. DOI: 10.3389/fpsyg.2020.02019
**Frontiers in Psychology.** Editorial: African cultural models in
  psychology. 2022. DOI: 10.3389/fpsyg.2022.844872
**Human Arenas.** Exploring the effects of social media on marriages
  in Northern Ghana. Springer, 2023.

### Mental health stigma in Ghana

**Gyamfi et al.** Impact of the stigma of mental illness: A descriptive
  exploratory study of outpatients in a public mental health hospital
  in Ghana. Journal of Community Psychology, 2024/2025.
  DOI: 10.1002/jcop.23164
**University of Ghana study.** Does stigma influence intentions to seek
  mental health care? A study among adults attending university in Ghana.
  PMC, 2021-22. DREC/009/21-22.

### Ubuntu

**Tutu, D.** No Future Without Forgiveness. Doubleday, 1999.
**Metz, T.** Ubuntu as a moral theory and human rights in South Africa.
  African Human Rights Law Journal, 2011.

---

## 14. UPDATE LOG

```
[June 2026 — v1.0 — Initial creation]
Clinical document created from research phase covering:
- All six psychological frameworks used in Attune
- WEIRD population bias and its specific implications
- Ghana and West Africa cultural calibration
- Ubuntu philosophical framework
- Mental health stigma context in Ghana
- Framework confidence levels
- Complete clinical advisor review checklist
- Open questions with owners and deadlines

Key findings that changed product decisions:
1. Love language compatibility scoring removed — Impett et al. 2024
   confirms matching hypothesis does not hold
2. Avoidance dimension cultural calibration flagged as critical
   open question for Ghanaian users
3. Communal obligation proposed as seventh root need category
4. NVC translator cultural fit flagged for user testing
5. Professional referral language requires stigma-aware rewrite

Status: Awaiting clinical advisor review before any psychologically
interpretive feature deployment.

[Future updates — clinical advisor sign-offs logged here]
```

---

*This document must be reviewed by a licensed clinical advisor*
*before any psychologically interpretive feature described in it*
*is deployed to users.*
*Clinical advisor sign-off is a launch prerequisite, not a formality.*
*Last reviewed: June 2026*

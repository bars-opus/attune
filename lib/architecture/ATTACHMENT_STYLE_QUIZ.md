# ATTUNE — ATTACHMENT STYLE QUIZ SPECIFICATION
### Complete implementation spec for the attachment style quiz
**Version:** 1.0
**Created:** June 2026
**Status:** Ready for DeepSeek implementation
**Part of:** Psychological Profiling Module (Quiz 1 of 4)
**Related documents:** ATTUNE_MASTER_SPEC.md · ATTUNE_CLINICAL.md · ATTUNE_SOUL.md

---

> **HOW TO USE THIS DOCUMENT**
>
> This spec defines the attachment style quiz end to end.
> Build in the exact order defined in Section 8.
> The quiz is Quiz 1 of 4 in the profiling module.
> Quizzes 2, 3, and 4 follow the same architecture —
> build this one cleanly and the others slot in identically.
> If something is unclear, ask before building it.

---

## TABLE OF CONTENTS

1. [What This Feature Is](#1-what-this-feature-is)
2. [Quiz Structure and Questions](#2-quiz-structure-and-questions)
3. [Scoring Algorithm](#3-scoring-algorithm)
4. [Quiz Interaction Design](#4-quiz-interaction-design)
5. [Result Screen](#5-result-screen)
6. [Sharing System](#6-sharing-system)
7. [Profile Integration](#7-profile-integration)
8. [Database Schema](#8-database-schema)
9. [Build Order](#9-build-order)
10. [Open Questions](#10-open-questions)

---

## 1. WHAT THIS FEATURE IS

The attachment style quiz is the first and most important quiz
in Attune's psychological profiling module. It is the data
foundation that unlocks the compatibility preview — the
day-one payoff that determines whether a new couple stays
past day three.

### Clinical basis

Based on the ECR-R (Experiences in Close Relationships —
Revised) instrument by Fraley, Waller, and Brennan (2000).
The ECR-R measures two continuous dimensions:

```
ANXIETY dimension:
How much a person fears rejection, abandonment, and
partner unavailability. High anxiety = preoccupied with
partner's availability.

AVOIDANCE dimension:
How uncomfortable a person is with closeness and depending
on others. High avoidance = suppresses attachment needs,
values independence defensively.
```

Full clinical basis: see ATTUNE_CLINICAL.md Section 3.

### What it produces

```
Two dimension scores (0-100 each):
- Anxiety score
- Avoidance score

One named result type (derived from quadrant):
- Secure          (low anxiety, low avoidance)
- Anxious         (high anxiety, low avoidance)
- Avoidant        (low anxiety, high avoidance)
- Fearful         (high anxiety, high avoidance)

One combined label where relevant:
- Anxious-secure  (moderate anxiety, low avoidance)
- Secure-avoidant (low anxiety, moderate avoidance)
etc.

One poetic type name (warm, non-clinical):
See Section 5 for the full name mapping.
```

### Important clinical rules

```
RESULTS ARE SPECTRUMS, NOT FIXED LABELS:
Never present the result as a permanent identity.
Always frame as: "how you tend to show up right now"
not "you are an anxious person."

NEVER USE THESE WORDS IN RESULT COPY:
disorder / broken / damaged / toxic / narcissist

RESULTS ARE PRIVATE BY DEFAULT:
Partner never sees result unless user explicitly shares.
See Section 6.

RETAKING IS ALLOWED:
User can retake the quiz any time.
New result replaces old in psych_profiles.
Historical results stored for growth tracking.
```

---

## 2. QUIZ STRUCTURE AND QUESTIONS

> **Implementation note — two distinct attachment quizzes exist.** This spec
> governs the **standalone** profiling quiz in `lib/features/quiz/` (25
> questions, 7-point scale, A/V/R dimension tags, scored by
> `AttachmentScoringService`). That implementation matches this spec.
>
> Separately, the **onboarding reflection quiz**
> (`lib/features/onboarding/domain/onboarding_models.dart`) ships an interim
> **26-question, 5-point yes/no set with no dimension tags**. Its answers are
> stored raw in `onboarding_profiles.attachment_answers` and are never run
> through the 7-point scorer, so the two do not conflict at runtime. Whether
> onboarding should adopt this spec's canonical instrument (count, 7-point
> scale, tags) is an **open launch decision blocked on clinical-advisor
> sign-off** — see §10 and `ATTUNE_CLINICAL.md` §12. Until then the onboarding
> set is deliberately kept lightweight.

### Format

```
25 questions total
5 questions per screen = 5 screens
7-point Likert scale per question:
  1 = Strongly disagree
  2 = Disagree
  3 = Slightly disagree
  4 = Neutral
  5 = Slightly agree
  6 = Agree
  7 = Strongly agree

Each question maps to one dimension:
  A = Anxiety dimension
  V = Avoidance dimension
  R = Reverse scored (noted where applicable)
```

### The 25 questions

These are conversationally rewritten from the ECR-R instrument.
Each preserves the original construct being measured.
Clinical advisor must review question wording before deployment.
See ATTUNE_CLINICAL.md Section 11 for advisor checklist.

**Screen 1 — Questions 1 to 5**

```
Q1 [A] I worry about whether my partner really cares about me.
Q2 [V] I prefer not to rely on my partner too much.
Q3 [A] I often wonder if my partner truly wants to be with me.
Q4 [V] I find it hard to let myself depend on someone I am with.
Q5 [A-R] I feel comfortable sharing my feelings with my partner.
         (Reverse scored: 7=strongly disagree on anxiety)
```

**Screen 2 — Questions 6 to 10**

```
Q6  [V] I get uncomfortable when a partner wants to be very close.
Q7  [A] I need a lot of reassurance that my partner loves me.
Q8  [V-R] I find it easy to be emotionally open with my partner.
          (Reverse scored)
Q9  [A] I worry a lot that my partner will not want to stay with me.
Q10 [V] I keep my guard up even in relationships I really care about.
```

**Screen 3 — Questions 11 to 15**

```
Q11 [A] When my partner is away I find myself worrying about them.
Q12 [V] I feel suffocated when someone gets too close too fast.
Q13 [A-R] I feel secure knowing my partner is there for me.
          (Reverse scored)
Q14 [V] I find it difficult to trust a partner completely.
Q15 [A] Small things my partner does can make me feel unloved.
```

**Screen 4 — Questions 16 to 20**

```
Q16 [V-R] Being emotionally intimate with someone feels natural to me.
          (Reverse scored)
Q17 [A] I often feel like my partner does not want to be as close
        as I do.
Q18 [V] I tend to keep my romantic partner at a certain distance.
Q19 [A-R] I do not often worry about being abandoned by the person
          I am with.
          (Reverse scored)
Q20 [V] Opening up fully to a partner makes me feel exposed.
```

**Screen 5 — Questions 21 to 25**

```
Q21 [A] I sometimes feel my partner does not value me as much
        as I value them.
Q22 [V-R] I am comfortable with my partner knowing most things
          about me.
          (Reverse scored)
Q23 [A] I get anxious when my partner does not respond quickly.
Q24 [V] I value my independence more than closeness in
        a relationship.
Q25 [A-R] I feel relaxed and confident in my relationship most
          of the time.
          (Reverse scored)
```

---

## 3. SCORING ALGORITHM

### Step 1 — Reverse scoring

For all questions marked [R], reverse the score before calculating:
```
Reversed score = 8 - raw_score
Example: raw score of 2 → reversed score of 6
Example: raw score of 6 → reversed score of 2
```

Reverse-scored questions: Q5, Q8, Q13, Q16, Q19, Q22, Q25

### Step 2 — Separate by dimension

```
Anxiety questions (A):
Q1, Q3, Q5(R), Q7, Q9, Q11, Q13(R), Q15, Q17, Q19(R), Q21, Q23, Q25(R)
Count: 13 questions

Avoidance questions (V):
Q2, Q4, Q6, Q8(R), Q10, Q12, Q14, Q16(R), Q18, Q20, Q22(R), Q24
Count: 12 questions
```

### Step 3 — Calculate raw dimension scores

```
anxiety_raw = sum of all anxiety question scores (after reverse scoring)
              / number of anxiety questions
              = value between 1.0 and 7.0

avoidance_raw = sum of all avoidance question scores (after reverse scoring)
                / number of avoidance questions
                = value between 1.0 and 7.0
```

### Step 4 — Normalise to 0-100

```
anxiety_score = round(((anxiety_raw - 1) / 6) * 100)
avoidance_score = round(((avoidance_raw - 1) / 6) * 100)

Example:
anxiety_raw = 4.2
anxiety_score = round(((4.2 - 1) / 6) * 100) = round(53.3) = 53
```

### Step 5 — Determine attachment type

```
Using thresholds on the 0-100 normalised scores:

LOW threshold:  score < 40
MID threshold:  score 40-60
HIGH threshold: score > 60

Quadrant mapping:
┌──────────────────────────────────────────────┐
│              AVOIDANCE                        │
│         LOW      MID       HIGH              │
│ A  LOW  Secure   Secure-   Avoidant          │
│ N       (pure)   avoidant  (pure)            │
│ X  MID  Anxious- Fearful-  Avoidant-         │
│ I       secure   secure    anxious           │
│ E HIGH  Anxious  Anxious-  Fearful           │
│ T       (pure)   avoidant  (pure)            │
└──────────────────────────────────────────────┘

Primary type assignment:
if anxiety < 40 AND avoidance < 40  → 'secure'
if anxiety > 60 AND avoidance < 40  → 'anxious'
if anxiety < 40 AND avoidance > 60  → 'avoidant'
if anxiety > 60 AND avoidance > 60  → 'fearful'
if anxiety 40-60 AND avoidance < 40 → 'anxious_secure'
if anxiety < 40 AND avoidance 40-60 → 'secure_avoidant'
if anxiety > 60 AND avoidance 40-60 → 'anxious_avoidant'
if anxiety 40-60 AND avoidance > 60 → 'avoidant_anxious'
if anxiety 40-60 AND avoidance 40-60→ 'fearful_secure'
```

### Step 6 — Derive percentage breakdown for display

```
The display shows four percentages (secure/anxious/avoidant/fearful)
that sum to 100. Derived from the two dimension scores:

secure_pct  = round(((100 - anxiety_score) + (100 - avoidance_score)) / 4)
anxious_pct = round((anxiety_score * (100 - avoidance_score)) / 5000)
avoidant_pct= round((avoidance_score * (100 - anxiety_score)) / 5000)
fearful_pct = round((anxiety_score * avoidance_score) / 5000)

Normalise to ensure they sum to exactly 100:
remainder = 100 - (secure + anxious + avoidant + fearful)
Add remainder to the largest value.

Note: These percentages are for display only.
The canonical scores stored in the database are
anxiety_score and avoidance_score (the two dimensions).
The percentages are computed at display time, not stored.
```

### Scoring example

```
User answers:
Q1=6, Q2=5, Q3=5, Q4=4, Q5=3(R→5), Q6=4, Q7=6, Q8=2(R→6),
Q9=5, Q10=4, Q11=5, Q12=3, Q13=2(R→6), Q14=5, Q15=4,
Q16=3(R→5), Q17=5, Q18=4, Q19=5(R→3), Q20=4,
Q21=5, Q22=5(R→3), Q23=6, Q24=3, Q25=2(R→6)

Anxiety questions: Q1(6)+Q3(5)+Q5(5)+Q7(6)+Q9(5)+Q11(5)+
                   Q13(6)+Q15(4)+Q17(5)+Q19(3)+Q21(5)+Q23(6)+Q25(6)
Sum = 67, Count = 13
anxiety_raw = 67/13 = 5.15
anxiety_score = round(((5.15-1)/6)*100) = round(69.2) = 69

Avoidance questions: Q2(5)+Q4(4)+Q6(4)+Q8(6)+Q10(4)+Q12(3)+
                     Q14(5)+Q16(5)+Q18(4)+Q20(4)+Q22(3)+Q24(3)
Sum = 50, Count = 12
avoidance_raw = 50/12 = 4.17
avoidance_score = round(((4.17-1)/6)*100) = round(52.8) = 53

Type: anxiety=69 (HIGH), avoidance=53 (MID)
→ 'anxious_avoidant'

Display percentages:
secure  = round(((100-69)+(100-53))/4) = round((31+47)/4) = round(19.5) = 20
anxious = round((69*(100-53))/5000)    = round(3243/5000) = round(64.9) = 65
avoidant= round((53*(100-69))/5000)    = round(1643/5000) = round(32.9) = 10
fearful = round((69*53)/5000)          = round(3657/5000) = round(73.1) = 5
Sum = 100 ✓
```

---

## 4. QUIZ INTERACTION DESIGN

### Entry point

```
Where the quiz is accessed:
- Profile tab → "Know yourself" section → [Attachment style quiz]
- Onboarding flow (required before compatibility preview unlocks)
- Notification prompt after signup if not yet completed

Quiz entry screen:
┌─────────────────────────────────────┐
│  ← Back                             │
│                                     │
│  Attachment style                   │
│                                     │
│  25 questions · about 5 minutes     │
│                                     │
│  This quiz helps you understand     │
│  how you tend to show up in         │
│  relationships — and why.           │
│                                     │
│  Your result is private. You        │
│  choose whether to share it.        │
│                                     │
│  There are no right or wrong        │
│  answers. Answer how you            │
│  actually feel, not how you         │
│  think you should feel.             │
│                                     │
│                     [Start quiz →]  │
└─────────────────────────────────────┘
```

### Quiz screen layout (5 questions per screen)

```
┌─────────────────────────────────────┐
│  ← Back                             │
│  ████████████░░░░░░░  Screen 2 of 5 │  ← progress bar
├─────────────────────────────────────┤
│                                     │
│  Q6                                 │
│  I get uncomfortable when a         │
│  partner wants to be very close.    │
│                                     │
│  ○ ○ ○ ○ ○ ○ ○                     │
│  1  2  3  4  5  6  7               │
│  Strongly           Strongly        │
│  disagree           agree           │
│                                     │
│  ─────────────────────────────────  │
│                                     │
│  Q7                                 │
│  I need a lot of reassurance        │
│  that my partner loves me.          │
│                                     │
│  ○ ○ ○ ○ ○ ○ ○                     │
│  1  2  3  4  5  6  7               │
│                                     │
│  ─────────────────────────────────  │
│                                     │
│  Q8                                 │
│  I find it easy to be emotionally   │
│  open with my partner.              │
│                                     │
│  ○ ○ ○ ○ ○ ○ ○                     │
│  1  2  3  4  5  6  7               │
│                                     │
│  ─────────────────────────────────  │
│                                     │
│  Q9                                 │
│  I worry a lot that my partner      │
│  will not want to stay with me.     │
│                                     │
│  ○ ○ ○ ○ ○ ○ ○                     │
│  1  2  3  4  5  6  7               │
│                                     │
│  ─────────────────────────────────  │
│                                     │
│  Q10                                │
│  I keep my guard up even in         │
│  relationships I really care about. │
│                                     │
│  ○ ○ ○ ○ ○ ○ ○                     │
│  1  2  3  4  5  6  7               │
│                                     │
├─────────────────────────────────────┤
│  [← Previous]           [Next →]   │
│  Next button disabled until all     │
│  5 questions on this screen answered│
└─────────────────────────────────────┘

Rules:
- Progress bar fills as screens are completed
  Screen 1 = 20%, Screen 2 = 40%, etc.
- [Next] button disabled until all 5 questions answered
- [← Previous] goes back to previous screen
  Previously selected answers are preserved
- Selected answer is visually highlighted (filled circle +
  Attune green colour)
- Unselected answers are empty circles
- Question text is readable at normal font size
  Do not truncate or shrink text to fit
- Scroll is allowed within the screen if needed on small devices
```

### Transition between screens

```
On [Next] tap:
- Current screen slides out left
- Next screen slides in from right
- Animation duration: 250ms
- No loading state between screens
  (all questions are local, no network call needed)

On [← Previous] tap:
- Current screen slides out right
- Previous screen slides in from left
- Same animation, opposite direction
```

### Loading screen (after Screen 5 [Next] is tapped)

```
Full screen loading state:

┌─────────────────────────────────────┐
│                                     │
│                                     │
│                                     │
│          [Attune green pulse        │
│           animation — subtle,       │
│           not a spinner]            │
│                                     │
│     Analysing your answers...       │
│                                     │
│                                     │
│                                     │
└─────────────────────────────────────┘

Duration: 2.5 seconds minimum
  (even if computation is instant — the pause is intentional)
  (this is the anticipation stage from the gift/receipt framework)
What happens during this time:
  - Scoring algorithm runs (client-side, no network needed)
  - Results stored to database (one API call)
  - Loading screen waits the full 2.5 seconds
    regardless of how fast the above completes

Animation:
  - A soft pulsing green circle — not a loading spinner
  - Slow pulse: expand slightly, contract, repeat
  - Conveys: something meaningful is being computed
  - Does NOT convey: waiting for a slow network
```

---

## 5. RESULT SCREEN

### Stage 1 — Type name reveal (ceremonial, appears alone first)

```
┌─────────────────────────────────────┐
│                                     │
│                                     │
│                                     │
│                                     │
│         Anxious-secure              │  ← fades in, large text
│                                     │     takes 1 second to appear
│                                     │     stays alone for 1.5 seconds
│                                     │
│                                     │
│                                     │
└─────────────────────────────────────┘

Then the rest of the screen fades in below it.
The type name stays at the top — it does not move.
The detail appears beneath it.
Total transition: 0.8 seconds fade in for detail section.
```

### Stage 2 — Full result screen (after reveal)

```
┌─────────────────────────────────────┐
│  Your attachment style              │
│                                     │
│         Anxious-secure              │  ← large, Attune green
│                                     │
│  ─────────────────────────────────  │
│                                     │
│  How you tend to show up            │
│                                     │
│  You bring warmth and depth to      │
│  your relationships. You care       │
│  deeply and feel things fully —     │
│  which is a gift. In moments of     │
│  stress or distance you may reach   │
│  for reassurance more than others   │
│  do. That is not a flaw. It is      │
│  your nervous system asking for     │
│  safety.                            │
│                                     │
│  ─────────────────────────────────  │
│                                     │
│  Your spectrum                      │
│                                     │
│  Secure      ████████████░░  65%   │
│  Anxious     ████░░░░░░░░░░  28%   │
│  Avoidant    █░░░░░░░░░░░░░   5%   │
│  Fearful     █░░░░░░░░░░░░░   2%   │
│                                     │
│  ─────────────────────────────────  │
│                                     │
│  What this means in practice        │
│                                     │
│  [3 bullet points — see below]      │
│                                     │
│  ─────────────────────────────────  │
│                                     │
│  This is a snapshot, not a label.   │
│  Attachment styles shift with       │
│  growth, therapy, and experience.   │
│                                     │
│  [Share with partner]               │
│                                     │
│  [Retake quiz]    [Back to profile] │
└─────────────────────────────────────┘
```

### Result type names and poetic descriptions

```
TYPE: secure
DISPLAY NAME: "Secure"
POETIC DESCRIPTION:
"You approach relationships from a place of groundedness. You
can be close without losing yourself, and give space without
fear. You trust that people who care about you will stay —
and that trust makes you easy to love."

TYPE: anxious
DISPLAY NAME: "Anxious"
POETIC DESCRIPTION:
"You feel everything deeply in relationships — the warmth,
the connection, and the uncertainty. Your sensitivity is
real and it makes you attentive and caring. In moments of
distance, your mind can race toward the worst. That is your
nervous system, not the truth of the situation."

TYPE: avoidant
DISPLAY NAME: "Avoidant"
POETIC DESCRIPTION:
"You value your independence and you have learned to rely
on yourself. Closeness can feel complicated — not because
you do not care, but because you care in ways that are
hard to show. Your self-sufficiency is a strength, and
so is learning when to let someone in."

TYPE: fearful
DISPLAY NAME: "Fearful-avoidant"
POETIC DESCRIPTION:
"You want closeness and find it frightening at the same time.
This is one of the most human experiences there is — wanting
connection while also protecting yourself from it. You are
not broken. You are someone who has learned caution, and
who can learn trust."

TYPE: anxious_secure
DISPLAY NAME: "Anxious-secure"
POETIC DESCRIPTION:
"You are mostly grounded in your relationships but you feel
things more intensely than others in moments of uncertainty.
Your warmth and attentiveness are genuine strengths. When
stress rises, reassurance helps you return to your steady self."

TYPE: secure_avoidant
DISPLAY NAME: "Secure-avoidant"
POETIC DESCRIPTION:
"You are mostly comfortable in relationships but you guard
your independence carefully. You can connect deeply when
you choose to and you need space to feel like yourself.
Your self-awareness about what you need is one of your
greatest relational assets."

TYPE: anxious_avoidant
DISPLAY NAME: "Anxious-avoidant"
POETIC DESCRIPTION:
"You experience both the pull toward connection and the
discomfort of closeness. This creates a push-pull dynamic
in your relationships that can be exhausting for you.
Understanding this pattern is the first step toward
something more settled."

TYPE: avoidant_anxious
DISPLAY NAME: "Avoidant-anxious"
POETIC DESCRIPTION:
"You tend to keep distance in relationships but when
something threatens the bond you do care about, anxiety
surfaces quickly. Your independence is real and so is
your capacity for connection — they just need the right
conditions to coexist."

TYPE: fearful_secure
DISPLAY NAME: "Cautiously secure"
POETIC DESCRIPTION:
"You sit in the middle of the attachment landscape —
neither strongly secure nor strongly insecure. You can
connect and you have some uncertainty about it. This
balance means you are open to growth in either direction."
```

### "What this means in practice" — 3 bullets per type

```
TYPE: secure
• You can ask for what you need without excessive worry
  about the response
• You give your partner space without reading it as rejection
• You repair conflict relatively well because you trust
  the relationship can survive disagreement

TYPE: anxious
• You may check in more than you intend to when things
  feel uncertain
• Small signals from your partner can carry a lot of weight
  for you emotionally
• Explicit reassurance helps you — asking for it directly
  is more effective than hoping it appears

TYPE: avoidant
• Deep conversations or emotional intensity can feel
  draining rather than connecting
• You may withdraw when a partner needs more closeness
  than feels comfortable
• The best relationships for you have clear space and
  do not require constant emotional availability

TYPE: fearful
• You may find yourself wanting closeness and then
  pulling away when it arrives
• Trust builds very slowly for you and that is valid —
  it needs to be earned over time
• Therapy or structured self-reflection tends to produce
  the most meaningful shifts for this style

TYPE: anxious_secure
• You are mostly settled but benefit from occasional
  check-ins where your partner explicitly affirms the connection
• You notice distance more quickly than your partner
  probably realises
• Your instinct to reach out in uncertainty is healthy —
  watch that it does not tip into over-reassurance-seeking

TYPE: secure_avoidant
• You thrive when relationships have clear boundaries
  around time and space
• You express care more through actions than words —
  make sure your partner knows how to read that
• You are more emotionally available than you seem —
  letting people see that occasionally goes a long way

TYPE: anxious_avoidant
• You may find yourself frustrated by wanting more
  while also feeling overwhelmed when you get it
• Naming this dynamic out loud to a partner can
  reduce a lot of confusion between you
• Self-compassion is more useful here than self-analysis —
  this pattern usually has deep roots

TYPE: avoidant_anxious
• You tend to be fine until something specific triggers
  concern — then anxiety comes quickly
• Understanding your specific triggers is more useful
  than addressing avoidance or anxiety in general
• Partners who respect your need for space while being
  consistent tend to work well for you

TYPE: fearful_secure
• You have flexibility in how you relate — use it
• You are not locked into one pattern which means
  you can move toward security with intentional practice
• Notice what conditions bring out your more secure
  versus less secure side
```

---

## 6. SHARING SYSTEM

### Default state

Result is completely private. Partner sees nothing.
No automatic sharing. No notification to partner on completion.

### Share button

Visible on the result screen after the full result loads.

```
Button label: [Share with partner]
Only shown if:
- User is in Couples mode with a linked partner
- User has not already shared this quiz result
  (once shared it changes to "Shared with Jordan ✓")

If user is in Personal mode or Single mode:
- Button not shown
- No sharing option exists
```

### Confirmation dialog

```
Tapping [Share with partner] shows:

┌─────────────────────────────────────┐
│  Share your result?                 │
│                                     │
│  Jordan will be able to see your    │
│  attachment style result. This      │
│  cannot be undone.                  │
│                                     │
│  [Cancel]          [Yes, share it]  │
└─────────────────────────────────────┘

[Cancel] → dialog closes, nothing shared
[Yes, share it] → result shared, partner notified
```

### After sharing

```
User's result screen:
- [Share with partner] button replaced with
  "Shared with Jordan ✓" (non-tappable, confirmation state)

Partner notification (push + in-app):
Title: "[Name] shared their attachment style"
Body: "See how your styles compare in your profile."
Tap destination: Profile tab → compatibility section

What the partner sees:
- User's named type (e.g. "Anxious-secure")
- User's poetic description
- User's spectrum percentages
- The "What this means in practice" bullets
- A compatibility note if both have shared
  (see Section 7 — Profile Integration)

What the partner NEVER sees:
- Individual question answers
- Raw dimension scores (anxiety_score, avoidance_score)
  These are private — only the named result is shared
```

### Revoking a share

```
Not possible. Once shared, it is permanent.
This was the stated design decision.
Do not add a revoke option.
```

---

## 7. PROFILE INTEGRATION

### Where results appear

```
Profile tab → "Know yourself" section:

┌─────────────────────────────────────┐
│  Know yourself                      │
│                                     │
│  Attachment style      ✓ Complete   │
│  Anxious-secure                     │
│  [View result]  [Retake]            │
│                                     │
│  Love languages        ○ Not started│
│  [Start quiz →]                     │
│                                     │
│  Communication style   ○ Not started│
│  [Start quiz →]                     │
│                                     │
│  Conflict style        ○ Not started│
│  [Start quiz →]                     │
└─────────────────────────────────────┘
```

### Compatibility section (couples only, after both share)

```
Shown only when:
- Both partners have completed the attachment quiz AND
- Both partners have shared their result

┌─────────────────────────────────────┐
│  Your attachment pairing            │
│                                     │
│  You              Jordan            │
│  Anxious-secure   Secure            │
│                                     │
│  [Pairing type name]                │
│  e.g. "The anchor and the tide"     │
│                                     │
│  [One sentence about this pairing]  │
│                                     │
│  [View full compatibility →]        │
└─────────────────────────────────────┘

Pairing type names and descriptions:
Generated by Claude API call using both attachment types.
Prompt: see Section 7.1 below.
Cached after first generation — not regenerated on every view.
```

### 7.1 Compatibility preview Claude API call

```javascript
// Called once when both partners have shared results
// Result cached in psych_profiles or a compatibility cache table
// Never regenerated unless one partner retakes and reshares

const generateCompatibilityNote = async (typeA, typeB) => {
  const prompt = `
    Generate a short attachment compatibility note for two people.

    Person A attachment type: ${typeA}
    Person B attachment type: ${typeB}

    Return ONLY valid JSON:
    {
      "pairing_name": string (3-5 words, poetic, warm — not clinical),
      "pairing_description": string (max 30 words, specific to
                             this combination),
      "natural_strength": string (max 20 words),
      "watch_area": string (max 20 words, about the dynamic
                   not about either person individually)
    }

    Rules:
    - pairing_name must feel like a name for this dynamic
      not a clinical description
    - Never use: anxious, avoidant, fearful, disorder, broken
    - watch_area describes the dynamic — never blames either person
    - Return ONLY the JSON object
  `
  return callClaude(prompt)
}
```

### psych_profiles table integration

```
Quiz result is stored in psych_profiles table
(already defined in ATTUNE_MASTER_SPEC.md Section 4)

Fields updated on quiz completion:
psych_profiles.attachment_style = {
  type: 'anxious_secure',
  anxiety_score: 69,
  avoidance_score: 53,
  completed_at: timestamp,
  version: 1  ← increments on retake
}
psych_profiles.completed_quizzes = array_append('attachment')
psych_profiles.last_updated = now()

On retake:
- New result overwrites current in psych_profiles
- Previous result stored in psych_profile_history table
  (for growth tracking — shows how style shifts over time)
- If result was shared with partner:
  partner sees the new result automatically
  (no new notification — partner sees "Updated" label)
```

---

## 8. DATABASE SCHEMA

```sql
-- Quiz responses (stores individual answers for audit and retake)
CREATE TABLE quiz_responses (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES auth.users NOT NULL,
  quiz_type text CHECK (quiz_type IN (
    'attachment', 'love_language', 'communication', 'conflict'
  )) NOT NULL,
  responses jsonb NOT NULL,
  -- Example: {"Q1": 6, "Q2": 5, "Q3": 5, ...}
  anxiety_score int,        -- 0-100, attachment quiz only
  avoidance_score int,      -- 0-100, attachment quiz only
  result_type text,         -- e.g. 'anxious_secure'
  completed_at timestamptz DEFAULT now(),
  version int DEFAULT 1     -- increments on retake
);

-- Quiz result sharing (tracks what has been shared with partner)
CREATE TABLE quiz_shares (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  sharer_user_id uuid REFERENCES auth.users NOT NULL,
  recipient_user_id uuid REFERENCES auth.users NOT NULL,
  quiz_type text NOT NULL,
  quiz_response_id uuid REFERENCES quiz_responses NOT NULL,
  shared_at timestamptz DEFAULT now(),
  UNIQUE (sharer_user_id, recipient_user_id, quiz_type)
  -- one share per quiz per couple — new share overwrites on retake
);

-- Profile history (tracks how results change over time)
CREATE TABLE psych_profile_history (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES auth.users NOT NULL,
  quiz_type text NOT NULL,
  result_type text NOT NULL,
  anxiety_score int,
  avoidance_score int,
  recorded_at timestamptz DEFAULT now(),
  version int NOT NULL
);

-- Compatibility cache (stores generated pairing notes)
CREATE TABLE attachment_compatibility_cache (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  relationship_id uuid REFERENCES relationships NOT NULL,
  type_a text NOT NULL,
  type_b text NOT NULL,
  pairing_name text NOT NULL,
  pairing_description text NOT NULL,
  natural_strength text NOT NULL,
  watch_area text NOT NULL,
  generated_at timestamptz DEFAULT now(),
  UNIQUE (relationship_id)
  -- one cached result per relationship
  -- regenerated if either partner retakes and reshares
);
```

### RLS Policies

```sql
-- Quiz responses: private to owner
CREATE POLICY "quiz_responses_private"
ON quiz_responses FOR ALL
USING (auth.uid() = user_id);

-- Quiz shares: readable by both sharer and recipient
CREATE POLICY "quiz_shares_both_parties"
ON quiz_shares FOR SELECT
USING (
  auth.uid() = sharer_user_id OR
  auth.uid() = recipient_user_id
);

-- Quiz shares: insertable by sharer only
CREATE POLICY "quiz_shares_sharer_insert"
ON quiz_shares FOR INSERT
WITH CHECK (auth.uid() = sharer_user_id);

-- Profile history: private to owner
CREATE POLICY "psych_history_private"
ON psych_profile_history FOR ALL
USING (auth.uid() = user_id);

-- Compatibility cache: readable by both relationship members
CREATE POLICY "compatibility_cache_relationship"
ON attachment_compatibility_cache FOR SELECT
USING (
  relationship_id IN (
    SELECT id FROM relationships
    WHERE user_a = auth.uid() OR user_b = auth.uid()
  )
);
```

---

## 9. BUILD ORDER

```
PHASE 1 — DATA LAYER
Step 1:  Run migrations from Section 8
         quiz_responses, quiz_shares, psych_profile_history,
         attachment_compatibility_cache tables + RLS
Step 2:  Verify psych_profiles table exists
         (from ATTUNE_MASTER_SPEC.md) — add attachment_style
         jsonb column if not already present

PHASE 2 — QUIZ FLOW
Step 3:  Quiz entry screen
         Description, time estimate, privacy note, Start button
Step 4:  Question screen component (reusable)
         5 questions, 7-point scale, progress bar
         Next button disabled until all 5 answered
         Previous navigation with answer preservation
Step 5:  Screen transition animations (slide left/right, 250ms)
Step 6:  Answer state management
         Store all 25 answers locally during quiz
         Do not save to database until quiz is completed

PHASE 3 — SCORING AND LOADING
Step 7:  Scoring algorithm (client-side)
         Reverse scoring, dimension averages, normalisation,
         type assignment, display percentage computation
Step 8:  Loading screen (2.5 second minimum)
         Pulsing green animation, "Analysing your answers..."
         Score computation runs during this screen
         Database save runs during this screen

PHASE 4 — RESULT SCREEN
Step 9:  Stage 1 — type name reveal
         Fade in alone, 1 second appear, 1.5 second hold
Step 10: Stage 2 — full result screen fade in
         Named type, poetic description, spectrum bars,
         practice bullets, snapshot disclaimer
Step 11: Spectrum bar animation
         Bars fill from 0 to final percentage on reveal
         Animation duration: 800ms, ease-out

PHASE 5 — SHARING SYSTEM
Step 12: [Share with partner] button (couples mode only)
Step 13: Confirmation dialog
Step 14: Share write to quiz_shares table
Step 15: Partner push notification via OneSignal
Step 16: Partner result view (what partner sees after share)
Step 17: "Shared with [name] ✓" state after sharing

PHASE 6 — PROFILE INTEGRATION
Step 18: "Know yourself" section in Profile tab
         Shows all 4 quizzes, complete/incomplete state
         [View result] and [Retake] for completed quizzes
Step 19: Compatibility section (couples, both shared)
         Pairing name + description
Step 20: Claude API call for compatibility note generation
         Cache result in attachment_compatibility_cache
Step 21: Retake flow
         New response overwrites psych_profiles
         History stored in psych_profile_history
         Share updated automatically if previously shared

PHASE 7 — EDGE CASES
Step 22: Handle quiz abandonment
         If user exits mid-quiz: save progress locally
         Resume from where they left off on next open
         Do not save partial results to database
Step 23: Handle no partner (Personal/Single mode)
         Hide sharing button entirely
         Show result screen without sharing option
Step 24: Handle both partners sharing
         Trigger compatibility note generation
         Show compatibility section in Profile tab
```

---

## 10. OPEN QUESTIONS

```
[NEEDS CLINICAL REVIEW — before deployment]
All 25 question wordings must be reviewed by the clinical
advisor confirmed in ATTUNE_CLINICAL.md Section 11.
Specifically: review avoidance dimension questions for
cultural appropriateness for Ghanaian users.
Do not deploy the quiz to real users before this review.

[OPEN] Retake notification to partner
  If a user retakes the quiz and has previously shared,
  the partner sees the new result automatically.
  Should the partner receive a push notification that
  the result has been updated?
  Suggested: yes, a single quiet notification:
  "[Name] updated their attachment style result."
  Decide before Step 21.

[OPEN] Quiz abandonment — local storage
  Step 22 saves progress locally if user exits.
  What local storage mechanism is available in the
  existing codebase? Use the same mechanism already
  in use rather than introducing a new one.

[OPEN] Compatibility note — when both partners retake
  If both partners retake and reshare, the compatibility
  cache should regenerate. The UNIQUE constraint on
  relationship_id means the old cache row needs updating,
  not inserting. Handle this with an UPSERT.
  Confirm the Claude API call regenerates correctly
  when attachment types change.
```

---

*This spec is complete and ready for DeepSeek implementation.*
*Build in the order defined in Section 9.*
*Do not deploy to real users before clinical advisor*
*reviews the question wording (see Open Questions).*
*Review against ATTUNE_SOUL.md before shipping.*
*Last reviewed: June 2026*
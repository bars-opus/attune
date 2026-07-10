# ATTUNE — LOVE LANGUAGE QUIZ SPECIFICATION

**Version:** 1.1  
**Created:** July 2026  
**Status:** Ready for implementation  
**Part of:** Psychological Profiling Module — Quiz 2 of 4  
**Related documents:**  
- `ATTUNE_MASTER_SPEC.md`  
- `ATTUNE_SOUL.md`  
- `ATTUNE_PRINCIPLES_CHECKLIST.md`  
- `ATTUNE_CLINICAL.md`  
- `ATTUNE_GAMES_MODULE_SPEC.md`  
- `../algorithms/algorithm_quality_review_checklist.md`

---

## HOW TO USE THIS DOCUMENT

This spec defines the **Love Language Quiz** — Quiz 2 of 4 in the Psychological Profiling Module.  
It follows the same architecture as the Attachment Quiz.  
Build in the exact order defined in **Section 9 — Build Order**.  
If something is unclear, ask before building it.

---

## TABLE OF CONTENTS

1. Feature Overview
2. Quiz Structure and Questions
3. Scoring Algorithm
4. Quiz Interaction Design
5. Result Screen
6. Sharing System
7. Profile Integration
8. Database Schema
9. Build Order
10. Algorithm Quality Checklist (Acceptance Criteria)
11. Soul Document Compliance
12. Open Questions

---

## 1. FEATURE OVERVIEW

### 1.1 What it is

The Love Language Quiz helps users understand how they most naturally give and receive affection. Based on Chapman's five love languages framework, it is positioned as a **self-awareness tool only** — not a compatibility scorer (per the 2024 Impett et al. critique).

### 1.2 Clinical positioning (critical)

| Aspect | Status |
|--------|--------|
| **Framework** | Chapman's Five Love Languages (Words of Affirmation, Quality Time, Receiving Gifts, Acts of Service, Physical Touch) |
| **Evidence base** | Limited peer-reviewed validation; 2024 Impett et al. critique found no evidence for the matching hypothesis |
| **Positioning in product** | **Self-awareness tool only** — never used for compatibility scoring |
| **FRAMEWORK_CONFIDENCE** | **LOWER** — the only framework at this level |
| **Allowed AI output** | "You tend to feel most appreciated through quality time." |
| **Forbidden AI output** | "Your love languages don't match your partner's, which may be causing disconnection." |

### 1.3 Core characteristics

| Characteristic | Value |
|----------------|-------|
| Questions | 15 |
| Duration | ~3 minutes |
| Format | 7-point Likert scale (1 = Strongly disagree, 7 = Strongly agree) |
| Output | Spectrum percentages for all five languages |
| Primary/Secondary | Primary and secondary love language identified |
| Sharing | Private by default; opt-in share with partner |
| Retaking | Allowed anytime; new result replaces old in `psych_profiles`, with prior result stored in `psych_profile_history` |

---

## 2. QUIZ STRUCTURE AND QUESTIONS

### 2.1 Format

```
15 questions total
5 questions per screen = 3 screens
7-point Likert scale per question:
  1 = Strongly disagree
  2 = Disagree
  3 = Slightly disagree
  4 = Neutral
  5 = Slightly agree
  6 = Agree
  7 = Strongly agree
```

### 2.2 The 15 questions (conversationally rewritten)

**Screen 1 — Questions 1 to 5**

```
Q1 [Words] I feel most loved when my partner tells me they appreciate me.
Q2 [Quality Time] I value undivided attention from my partner more than gifts.
Q3 [Gifts] A thoughtful gift makes me feel truly seen and cared for.
Q4 [Acts] I feel loved when my partner does something helpful for me.
Q5 [Touch] Physical affection is one of the most important ways I feel connected.
```

**Screen 2 — Questions 6 to 10**

```
Q6 [Words] Hearing "I love you" matters more to me than almost anything else.
Q7 [Quality Time] Spending quality time together is my favourite way to connect.
Q8 [Gifts] Receiving a meaningful gift makes me feel valued and appreciated.
Q9 [Acts] I feel cared for when my partner takes care of something for me.
Q10 [Touch] A hug or a touch can make me feel instantly closer to my partner.
```

**Screen 3 — Questions 11 to 15**

```
Q11 [Words] Words of encouragement from my partner mean a lot to me.
Q12 [Quality Time] I feel closest to my partner when we are doing something together.
Q13 [Gifts] The thought behind a gift matters more to me than the gift itself.
Q14 [Acts] When my partner helps me with something, I feel supported and loved.
Q15 [Touch] Feeling my partner's touch makes me feel safe and loved.
```

### 2.3 Question mapping

| Language | Questions | Count |
|----------|-----------|-------|
| Words of Affirmation | Q1, Q6, Q11 | 3 |
| Quality Time | Q2, Q7, Q12 | 3 |
| Receiving Gifts | Q3, Q8, Q13 | 3 |
| Acts of Service | Q4, Q9, Q14 | 3 |
| Physical Touch | Q5, Q10, Q15 | 3 |

---

## 3. SCORING ALGORITHM

### 3.1 Step 1 — Calculate raw dimension scores

```
words_score = sum(Q1, Q6, Q11) / 3          // Value between 1.0 and 7.0
quality_time_score = sum(Q2, Q7, Q12) / 3
gifts_score = sum(Q3, Q8, Q13) / 3
acts_score = sum(Q4, Q9, Q14) / 3
touch_score = sum(Q5, Q10, Q15) / 3
```

### 3.2 Step 2 — Normalise to percentages

```
total = words_score + quality_time_score + gifts_score + acts_score + touch_score

words_pct = round((words_score / total) * 100)
quality_time_pct = round((quality_time_score / total) * 100)
gifts_pct = round((gifts_score / total) * 100)
acts_pct = round((acts_score / total) * 100)
touch_pct = round((touch_score / total) * 100)

// Normalise to ensure sum is exactly 100
remainder = 100 - (words_pct + quality_time_pct + gifts_pct + acts_pct + touch_pct)
Add remainder to the largest percentage.
```

### 3.3 Step 3 — Determine primary and secondary

```
primary = language with highest percentage
secondary = language with second-highest percentage
```

### 3.4 Scoring example

```
User answers:
Q1=6, Q2=5, Q3=3, Q4=4, Q5=7,
Q6=7, Q7=6, Q8=4, Q9=5, Q10=7,
Q11=6, Q12=7, Q13=5, Q14=6, Q15=7

words_score = (6+7+6)/3 = 6.33
quality_time_score = (5+6+7)/3 = 6.00
gifts_score = (3+4+5)/3 = 4.00
acts_score = (4+5+6)/3 = 5.00
touch_score = (7+7+7)/3 = 7.00

total = 6.33 + 6.00 + 4.00 + 5.00 + 7.00 = 28.33

words_pct = round((6.33/28.33)*100) = 22%
quality_time_pct = round((6.00/28.33)*100) = 21%
gifts_pct = round((4.00/28.33)*100) = 14%
acts_pct = round((5.00/28.33)*100) = 18%
touch_pct = round((7.00/28.33)*100) = 25%

Normalised (remainder = 0):
touch: 25%, words: 22%, quality_time: 21%, acts: 18%, gifts: 14%

Primary: Physical Touch (25%)
Secondary: Words of Affirmation (22%)
```

---

## 4. QUIZ INTERACTION DESIGN

### 4.1 Entry point

```
Profile tab → "Know yourself" section → [Love languages quiz]

Quiz entry screen:
┌─────────────────────────────────────┐
│  ← Back                             │
│                                     │
│  Love languages                     │
│                                     │
│  15 questions · about 3 minutes     │
│                                     │
│  This quiz helps you understand     │
│  how you most naturally give and    │
│  receive affection.                 │
│                                     │
│  Your result is private. You        │
│  choose whether to share it.        │
│                                     │
│  There are no right or wrong        │
│  answers. Answer how you            │
│  actually feel.                     │
│                                     │
│                     [Start quiz →]  │
└─────────────────────────────────────┘
```

### 4.2 Quiz screen layout (5 questions per screen)

```
┌─────────────────────────────────────┐
│  ← Back                             │
│  ████████████░░░░░░░  Screen 2 of 3 │  ← progress bar
├─────────────────────────────────────┤
│                                     │
│  Q6                                 │
│  Hearing "I love you" matters       │
│  more to me than almost anything    │
│  else.                              │
│                                     │
│  ○ ○ ○ ○ ○ ○ ○                     │
│  1  2  3  4  5  6  7               │
│  Strongly           Strongly        │
│  disagree           agree           │
│                                     │
│  ─────────────────────────────────  │
│                                     │
│  Q7                                 │
│  Spending quality time together     │
│  is my favourite way to connect.    │
│                                     │
│  ○ ○ ○ ○ ○ ○ ○                     │
│  1  2  3  4  5  6  7               │
│                                     │
│  ─────────────────────────────────  │
│                                     │
│  Q8                                 │
│  Receiving a meaningful gift makes  │
│  me feel valued and appreciated.    │
│                                     │
│  ○ ○ ○ ○ ○ ○ ○                     │
│  1  2  3  4  5  6  7               │
│                                     │
│  ─────────────────────────────────  │
│                                     │
│  Q9                                 │
│  I feel cared for when my partner   │
│  takes care of something for me.    │
│                                     │
│  ○ ○ ○ ○ ○ ○ ○                     │
│  1  2  3  4  5  6  7               │
│                                     │
│  ─────────────────────────────────  │
│                                     │
│  Q10                                │
│  A hug or a touch can make me feel  │
│  instantly closer to my partner.    │
│                                     │
│  ○ ○ ○ ○ ○ ○ ○                     │
│  1  2  3  4  5  6  7               │
│                                     │
├─────────────────────────────────────┤
│  [← Previous]           [Next →]   │
└─────────────────────────────────────┘
```

### 4.3 Loading screen

```
┌─────────────────────────────────────┐
│          [Attune green pulse        │
│           animation]                │
│                                     │
│     Analysing your answers...       │
└─────────────────────────────────────┘

Duration: 2.0 seconds minimum (gift/receipt framework)
```

---

## 5. RESULT SCREEN

### 5.1 Full result screen

```
┌─────────────────────────────────────┐
│  Your love languages                │
│                                     │
│  Primary: Physical Touch            │
│  Secondary: Words of Affirmation    │
│                                     │
│  ─────────────────────────────────  │
│                                     │
│  Physical Touch  ████████████  25%  │  ← primary highlighted
│  Words           ██████████   22%  │
│  Quality Time    █████████   21%   │
│  Acts of Service ████████    18%   │
│  Gifts           ██████     14%   │
│                                     │
│  ─────────────────────────────────  │
│                                     │
│  What this means                    │
│                                     │
│  "You tend to feel most loved through│
│   physical affection and touch.     │
│   A hug, a hand on your shoulder,   │
│   or just sitting close can say     │
│   more to you than words."          │
│                                     │
│  ─────────────────────────────────  │
│                                     │
│  This is a snapshot, not a label.   │
│                                     │
│  [Share with partner]               │
│  [Retake quiz]    [Back to profile] │
└─────────────────────────────────────┘
```

### 5.2 Language descriptions

| Language | Description |
|----------|-------------|
| **Words of Affirmation** | "You tend to feel most loved through words — hearing appreciation, encouragement, and 'I love you.'" |
| **Quality Time** | "You tend to feel most loved through undivided attention — being truly present with your partner." |
| **Receiving Gifts** | "You tend to feel most loved through thoughtful gifts — the effort and thought behind them matters most." |
| **Acts of Service** | "You tend to feel most loved through actions — when your partner does something helpful or supportive." |
| **Physical Touch** | "You tend to feel most loved through physical affection — touch, hugs, and closeness." |

---

## 6. SHARING SYSTEM

### 6.1 Sharing rules

```
Default: completely private. Partner sees nothing.
Share: opt-in only, with confirmation dialog.
Once shared: partner sees primary and secondary love languages + percentages.
Partner NEVER sees individual question answers.
```

### 6.2 Compatibility note

**Important per clinical document:** The love language quiz is **not** used for compatibility scoring. The 2024 Impett et al. critique found no evidence that matching love languages predicts relationship satisfaction. Do not generate compatibility notes based on love language match/mismatch.

---

## 7. PROFILE INTEGRATION

### 7.1 Profile display

```
Profile tab → "Know yourself" section:

┌─────────────────────────────────────┐
│  Know yourself                      │
│                                     │
│  Attachment style      ✓ Complete   │
│  Anxious-secure                     │
│  [View result]  [Retake]            │
│                                     │
│  Love languages        ✓ Complete   │  ← now complete
│  Words of Affirmation               │
│  [View result]  [Retake]            │
│                                     │
│  Communication style   ○ Not started│
│  [Start quiz →]                     │
│                                     │
│  Conflict style        ○ Not started│
│  [Start quiz →]                     │
└─────────────────────────────────────┘
```

### 7.2 Database storage

```sql
-- Stored in `psych_profiles.love_languages`; prior results are appended to `psych_profile_history` on retake
{
  "words": 22,
  "quality_time": 21,
  "gifts": 14,
  "acts": 18,
  "touch": 25,
  "primary": "touch",
  "secondary": "words",
  "completed_at": "2026-07-02T10:00:00Z"
}
```

---

## 8. DATABASE SCHEMA

### 8.1 Existing columns (already in psych_profiles)

```sql
-- psych_profiles already has love_languages column
ALTER TABLE psych_profiles
ADD COLUMN IF NOT EXISTS love_languages jsonb;  -- already exists from master spec
```

### 8.2 Quiz responses (shared with other quizzes)

```sql
-- Uses existing quiz_responses table
-- quiz_type = 'love_language'
-- responses: {"Q1": 6, "Q2": 5, ...}
```

### 8.3 Quiz shares (shared with other quizzes)

```sql
-- Uses existing quiz_shares table
-- quiz_type = 'love_language'
```

---

## 9. BUILD ORDER

### Phase 1 — Data Layer (already exists)
Step 1: Verify `psych_profiles.love_languages` column exists  
Step 2: Verify `quiz_responses` and `quiz_shares` tables exist  

### Phase 2 — Quiz Flow
Step 3: Quiz entry screen (description, time estimate, Start button)  
Step 4: Question screen component (5 questions, 7-point scale, progress bar)  
Step 5: Screen transition animations (slide left/right, 250ms)  
Step 6: Answer state management (store 15 answers locally)  

### Phase 3 — Scoring and Loading
Step 7: Scoring algorithm (calculate dimension averages, normalise percentages)  
Step 8: Loading screen (2.0 second minimum, pulse animation)  

### Phase 4 — Result Screen
Step 9: Full result screen (primary/secondary, spectrum bars, descriptions)  
Step 10: Spectrum bar animation (bars fill from 0 to final percentage)  

### Phase 5 — Sharing System
Step 11: [Share with partner] button (couples mode only)  
Step 12: Confirmation dialog  
Step 13: Share write to `quiz_shares` table  
Step 14: Partner result view  

### Phase 6 — Profile Integration
Step 15: "Know yourself" section update (show love language completion)  
Step 16: [View result] and [Retake] for love languages  

### Phase 7 — Edge Cases
Step 17: Quiz abandonment (save progress locally, resume)  
Step 18: Retake flow (new response overwrites `psych_profiles.love_languages`; prior result stored in `psych_profile_history`)  

---

## 10. ALGORITHM QUALITY CHECKLIST (ACCEPTANCE CRITERIA)

| # | Criterion | Verification Method |
|---|-----------|---------------------|
| 1.1 | Idempotent mutations | Test: submit same quiz twice → no duplicate effects |
| 1.5 | Authentication verified | Test: unauthenticated request → rejected |
| 2.1 | Input sanitised | Test: Likert scale values validated (1-7) |
| 2.4 | Error messages don't leak | Test: errors show generic message, no stack trace |
| 2.10 | Resources released | Test: screen exit → subscriptions disposed |
| 4.1 | Structured logs | Test: log entry is valid JSON with request_id, user_id |
| 4.4 | PII excluded from logs | Test: logs contain no quiz answers |
| 5.1 | Actionable error responses | Test: all failure states show user-friendly next step |
| 6.1 | Edge cases covered | Test: quiz abandonment, retake flow produce defined behaviour |
| 6.7 | Branch coverage ≥90% | Unit test report shows ≥90% branch coverage for scoring algorithm |

---

## 11. SOUL DOCUMENT COMPLIANCE

| Principle | Status | Evidence |
|-----------|--------|----------|
| No streaks | ✅ | No streak tracking |
| No leaderboards | ✅ | No comparison between couples |
| Gift/receipt framework | ✅ | 2.0s minimum loading, result reveal |
| User autonomy | ✅ | Sharing is opt-in, private by default |
| No diagnostic language | ✅ | Results framed as "how you tend to show up" |
| No anxiety by design | ✅ | No scoring, no pressure |

**Key clinical constraint:** Love language quiz results are **never used for compatibility scoring** per the 2024 Impett et al. critique. FRAMEWORK_CONFIDENCE = LOWER.

---

## 12. OPEN QUESTIONS

All resolved.

| Status | Item |
|--------|------|
| ✅ | Love language quiz = self-awareness tool only |
| ✅ | Not used for compatibility scoring |
| ✅ | FRAMEWORK_CONFIDENCE = LOWER |
| ✅ | Private by default, opt-in share |
| ✅ | 15 questions, 3 screens |
| ✅ | Primary + secondary love languages identified |

---

*This spec is ready for review.*  
*Build in the exact order defined in Section 9.*  
*Review against ATTUNE_SOUL.md before shipping.*  
*Run algorithm quality checklist before merge.*  
*Last reviewed: July 2026*

## ATTUNE — 36 QUESTIONS JOURNEY SPECIFICATION v2.4 (FINAL)

**Version:** 2.4 (final cleanup)  
**Created:** June 2026  
**Last updated:** June 2026  
**Status:** **Ready for implementation**  
**Part of:** Games Module — Game 3 of 3  
**Related documents:**  
- `ATTUNE_MASTER_SPEC.md`  
- `ATTUNE_SOUL.md`  
- `ATTUNE_PRINCIPLES_CHECKLIST.md`  
- `ATTUNE_CLINICAL.md`  
- `ATTUNE_GAMES_MODULE_SPEC.md`  
- `ATTUNE_ALGORITHM_QUALITY_REVIEW_CHECKLIST.md`

---

## HOW TO USE THIS DOCUMENT

This spec defines the **36 Questions Journey** — a 3-chapter, 36-question intimacy experience.  
It is Game 3 of 3 in the Games Module.

Build in the exact order defined in **Section 12 — Build Order**.  
The game uses the shared session architecture from the Games Module.

**Status:** This spec is ready for implementation. Build according to the defined phases.

---

## TABLE OF CONTENTS

1. Feature Overview
2. Journey Flow
3. Screen Designs
4. Question Bank
5. Selection Algorithm
6. AI Observation System
7. Database Schema
8. Edge Cases
9. Notifications
10. Analytics Events
11. Privacy & Retention Rules
12. Build Order
13. Algorithm Quality Checklist (Acceptance Criteria)
14. Soul Document Compliance
15. Open Questions

---

## 1. FEATURE OVERVIEW

### 1.1 What it is

The 36 Questions Journey is Attune's adaptation of Arthur Aron's 1997 intimacy study. It is structured as **3 chapters of 12 questions each**, building progressively from warm-up to deep vulnerability. Couples complete one chapter per play session, with each chapter requiring fresh mutual opt-in.

### 1.2 Core characteristics

| Characteristic | Value |
|----------------|-------|
| Total questions | 36 (3 chapters × 12 questions) |
| Per session | 12 questions (~20 minutes) |
| Players | 2 (asynchronous on separate devices) |
| Chapters | Chapter 1: Warm Up, Chapter 2: Deeper, Chapter 3: Vulnerable |
| Tone | Connecting only (per the Aron study) |
| Answer type | Free text (soft minimum 20 chars, hard max 400 chars) |
| Replayability | Large bank (120+ questions) + seen tracking |
| AI Observations | Chapter reflection (optional, evidence-gated) + Final Journey Reflection |
| Question Bank | Supabase with canonical questions + localized translations |

### 1.3 Chapter definitions

| Chapter | Content | Vulnerability |
|---------|---------|---------------|
| **1 — Warm Up** | Light self-disclosure, preferences, memories, curiosity, ordinary closeness | Low |
| **2 — Deeper** | Values, family patterns, emotional needs, repair, feeling seen, hopes, regrets | Medium |
| **3 — Vulnerable** | Fear, loss, healing, future, intimacy, trust, being known | High |

### 1.4 Hard exclusions (all chapters)

```
- No "tell your partner your deepest trauma"
- No "what abuse have you experienced?"
- No "have you ever wanted to hurt yourself?"
- No "what do you hate about your partner?"
- No "what would make you leave?"
- No prompts that force confession, accusation, or commitment decisions
```

---

## 2. JOURNEY FLOW

### 2.1 Complete flow diagram

```
Partner A initiates Chapter 1
    │
    ▼
Creates journey (status: in_progress) + chapter session (status: invited)
    │
    ▼
Partner B accepts
    │
    ▼
Chapter 1 starts (12 questions, Warm Up)
    │
    ├── Both answer independently
    ├── Reveal after both answer (side by side)
    └── Chapter 1 completion ceremony
    │
    ▼
Chapter 1 complete → both see "Chapter 2 is ready when you both are"
    │
    ├── Either partner taps "Invite to continue Chapter 2"
    ├── Partner receives **one push notification** (explicit invite only)
    ├── Both must accept before Chapter 2 starts
    └── If no response in 48h: invite expires (abandoned with reason: 'invite_expired')
    │
    ▼
Chapter 2 starts (12 questions, Deeper)
    │
    ├── Same flow as Chapter 1
    └── Chapter 2 completion ceremony
    │
    ▼
Same flow for Chapter 3 (Vulnerable)
    │
    ▼
All 3 chapters completed
    │
    ▼
Final Journey Reflection generated (if enough usable content)
    │
    ▼
Journey complete end screen
```

### 2.2 Journey status

| Status | Meaning |
|--------|---------|
| `in_progress` | Journey has been started (Chapter 1 invited or active). Remains `in_progress` until all 3 chapters are completed or the journey is explicitly abandoned. |
| `completed` | All 3 chapters completed. |
| `abandoned` | User explicitly ended the journey. |

### 2.3 Chapter status (`game_sessions.status` with `abandon_reason`)

| Status | Meaning |
|--------|---------|
| `invited` | Partner A invited, B hasn't responded |
| `active` | Both accepted, game in progress |
| `completed` | All 12 questions finished |
| `abandoned` | Ended (with `abandon_reason` column) |

**`abandon_reason` values:**
- `inactivity` → 7 days no activity
- `invite_expired` → 48 hours no response to invitation
- `user_initiated` → User explicitly ended the chapter

### 2.4 Mutual opt-in per chapter

After each chapter completes, the app shows:

> "Chapter 2 goes deeper. Continue now, or leave it for another day."

**Both partners must tap "Continue" before the next chapter starts.** This is a fresh mutual opt-in, not an automatic progression.

### 2.5 Chapter Order & Active Journey Rule

**Chapter order enforcement (v2.4):**
- Chapter 2 cannot be invited until Chapter 1 is `completed`.
- Chapter 3 cannot be invited until Chapter 2 is `completed`.
- This ensures the emotional progression (Warm Up → Deeper → Vulnerable) is preserved.
- If a chapter is abandoned, the couple must restart that chapter before proceeding to the next.

**One active journey per relationship (v2.4):**
- A relationship can have only one `in_progress` 36 Questions Journey at a time.
- If a user attempts to start a new journey while one is `in_progress`, the app prompts: "You already have an active journey — resume it or end it first."
- This is enforced by a partial unique index on the database (see Section 7.1).

---

## 3. SCREEN DESIGNS

### 3.1 Games Hub entry

```
┌─────────────────────────────────────┐
│  💬 36 Questions Journey            │
│  Deep connection · 3 chapters of 12 │
│  ~20 min per chapter                │
│                                     │
│  ┌─────────────────────────────┐   │
│  │  Chapter 1: Warm Up   ○    │   │
│  │  Chapter 2: Deeper    ○    │   │
│  │  Chapter 3: Vulnerable ○   │   │
│  └─────────────────────────────┘   │
│                                     │
│  If journey in progress:            │
│  [Resume journey →]                 │
│                                     │
│  If no journey active:              │
│  [Start journey →]                  │
└─────────────────────────────────────┘
```

### 3.2 Chapter introduction screen

```
┌─────────────────────────────────────┐
│  Chapter 1 — Warm Up                │
│                                     │
│  The conversation starts here.      │
│  Let's get comfortable together.    │
│                                     │
│  12 questions · ~20 minutes         │
│                                     │
│       [Begin →]                     │
└─────────────────────────────────────┘
```

### 3.3 Question screen

```
┌─────────────────────────────────────┐
│  ← Back   Chapter 1    Q3 of 12     │
├─────────────────────────────────────┤
│                                     │
│  If you could have dinner with      │
│  anyone in the world, who would     │
│  it be?                             │
│                                     │
│  ┌─────────────────────────────┐   │
│  │ Your answer...              │   │
│  │                             │   │
│  └─────────────────────────────┘   │
│  Max 400 characters                 │
│  A sentence or two is enough.       │
│                                     │
│  Jordan will see your answer after  │
│  you both submit.                   │
│                                     │
├─────────────────────────────────────┤
│  Jordan: ● answered / ○ waiting     │
│                                     │
│  [Skip question]  [Submit answer]   │
└─────────────────────────────────────┘
```

### 3.4 Reveal screen

```
┌─────────────────────────────────────┐
│  Q3 of 12 · Chapter 1               │
├─────────────────────────────────────┤
│  If you could have dinner with      │
│  anyone in the world?               │
├─────────────────────────────────────┤
│                                     │
│  Your answer:                       │
│  "My grandmother. She passed away   │
│   before I could really know her    │
│   as an adult."                     │
│                                     │
│  Jordan's answer:                   │
│  "My favourite author. I have so    │
│   many questions I'd want to ask."  │
│                                     │
├─────────────────────────────────────┤
│  ┌─────────┐         ┌─────────┐   │
│  │ Previous│         │  Next → │   │
│  └─────────┘         └─────────┘   │
└─────────────────────────────────────┘
```

### 3.5 Chapter completion ceremony

```
┌─────────────────────────────────────┐
│  ✨ Chapter 1 complete               │
│                                     │
│  You both showed up for the         │
│  conversation.                      │
│                                     │
│  ─────────────────────────────────  │
│                                     │
│  One thread in your answers:        │
│  "You both described feeling close  │
│   in ordinary, everyday moments."   │
│                                     │
│  ─────────────────────────────────  │
│                                     │
│  Chapter 2 goes deeper.             │
│  Continue now, or leave it for      │
│  another day.                       │
│                                     │
│  [Continue to Chapter 2 →]          │
│  [Maybe later]                      │
└─────────────────────────────────────┘
```

### 3.6 Chapter 2 invitation

```
Partner A sees:
┌─────────────────────────────────────┐
│  Invitation sent to Jordan          │
│                                     │
│  Waiting for Jordan to accept       │
│  Chapter 2.                         │
│                                     │
│  This invitation expires in 48h.    │
│                                     │
│  [Cancel invitation]                │
└─────────────────────────────────────┘

Partner B sees:
┌─────────────────────────────────────┐
│  [Name] invited you to continue     │
│  the 36 Questions Journey           │
│                                     │
│  Chapter 2: Deeper                  │
│                                     │
│  ~20 minutes                        │
│                                     │
│  [Maybe later]    [Continue →]      │
└─────────────────────────────────────┘
```

### 3.7 Final Journey Reflection

```
┌─────────────────────────────────────┐
│  ✨ Journey complete                 │
│                                     │
│  36 questions. 3 chapters.          │
│  You both showed up for all of it.  │
│                                     │
│  ─────────────────────────────────  │
│                                     │
│  Your journey reflection:           │
│  "Across your answers, you both     │
│   returned again and again to the   │
│   idea of being heard. You each     │
│   described safety in different     │
│   ways, but both of you named it.   │
│   That might be something worth     │
│   continuing to talk about."        │
│                                     │
│  ─────────────────────────────────  │
│                                     │
│  [Play again]   [Back to games]     │
└─────────────────────────────────────┘
```

---

## 4. QUESTION BANK

### 4.1 Canonical + translation table structure

Questions are stored in Supabase with a canonical ID and separate translations:

```sql
-- Canonical question identity
CREATE TABLE thirty_six_questions_canonical (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  chapter int NOT NULL CHECK (chapter IN (1, 2, 3)),
  intensity_order int NOT NULL,
  requires_review boolean DEFAULT false,
  active boolean DEFAULT true,
  created_at timestamptz DEFAULT now()
);

-- Localized translations
CREATE TABLE thirty_six_questions_translations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  canonical_id uuid REFERENCES thirty_six_questions_canonical NOT NULL,
  locale text NOT NULL,
  question_text text NOT NULL,
  is_reviewed boolean DEFAULT false,
  created_at timestamptz DEFAULT now(),
  UNIQUE(canonical_id, locale)
);
```

### 4.2 Minimum question counts before launch

| Chapter | Minimum canonical questions |
|---------|----------------------------|
| Chapter 1 — Warm Up | 40 |
| Chapter 2 — Deeper | 40 |
| Chapter 3 — Vulnerable | 40 |
| **Total** | **120** |

### 4.3 Localization rules

- English is the canonical source bank.
- Each locale has translated/adapted question text.
- Translations preserve intent, not exact wording.
- Chapter 3 translations require `is_reviewed = true` before they can be served.
- If a locale is incomplete, fallback to English.
- Never machine-translate vulnerable questions at runtime.

---

## 5. SELECTION ALGORITHM

### 5.1 Question selection for a chapter

```dart
Future<List<SelectedQuestion>> selectChapterQuestions({
  required String relationshipId,
  required int chapter,
  required String locale,
  required List<CanonicalQuestion> allCanonical,
  required List<QuestionTranslation> allTranslations,
}) async {
  // 1. Get active canonical questions for this chapter
  final activeCanonical = allCanonical
      .where((q) => q.chapter == chapter && q.active)
      .toList();

  // 2. For Chapter 3, only include reviewed translations
  final translationFilter = (QuestionTranslation t) {
    if (chapter == 3 && !t.isReviewed) return false;
    return true;
  };

  // 3. Get seen IDs and seen_at timestamps for this couple
  final seenMap = await getSeenMap(relationshipId); // Map<canonicalId, seenAt>

  // 4. Build question objects with the best available translation
  final questions = activeCanonical.map((canonical) {
    // Find translation for requested locale
    var translation = allTranslations.firstWhere(
      (t) => t.canonicalId == canonical.id && t.locale == locale && translationFilter(t),
      orElse: () => null,
    );

    // Fallback to English if requested locale not available
    if (translation == null) {
      translation = allTranslations.firstWhere(
        (t) => t.canonicalId == canonical.id && t.locale == 'en' && translationFilter(t),
        orElse: () => null,
      );
    }

    // If no translation exists, skip this question
    if (translation == null) return null;

    return {
      'canonicalId': canonical.id,
      'chapter': canonical.chapter,
      'intensityOrder': canonical.intensityOrder,
      'text': translation.questionText,
      'locale': translation.locale,
      'isSeen': seenMap.containsKey(canonical.id),
      'seenAt': seenMap[canonical.id],
    };
  }).where((q) => q != null).toList();

  // 5. Split into unseen and seen
  final unseen = questions.where((q) => !q['isSeen']).toList();
  final seen = questions.where((q) => q['isSeen']).toList();

  // 6. Sort unseen by intensity_order
  unseen.sort((a, b) => a['intensityOrder'].compareTo(b['intensityOrder']));

  // 7. Select 12 from unseen
  var selected = unseen.take(12).toList();

  // 8. If not enough unseen, fill from seen (oldest seen_at first)
  if (selected.length < 12) {
    seen.sort((a, b) => a['seenAt'].compareTo(b['seenAt']));
    selected.addAll(seen.take(12 - selected.length));
  }

  // 9. Snapshot question text into the round so history is preserved
  return selected.map((q) => ({
    'canonicalId': q['canonicalId'],
    'questionText': q['text'], // snapshot preserved at time of session
    'chapter': q['chapter'],
    'intensityOrder': q['intensityOrder'],
  })).toList();
}
```

### 5.2 Seen tracking

- Questions are marked seen **only after a chapter is completed** (all 12 questions answered by both partners).
- `seen_at` timestamp is recorded when marked seen.
- Abandoned chapters do NOT mark questions seen.
- Fallback: use oldest seen questions (by `seen_at`) if unseen pool is exhausted.

### 5.3 Skip replacement mechanics (v2.4)

When a partner uses a skip:
1. The **skipped question is not marked as seen**. It remains available for future sessions.
2. The app selects a **replacement question** using the same selection algorithm (unseen, appropriate locale, same chapter).
3. The replacement question becomes the canonical question for the current round:
   - `canonical_question_id` is updated to the replacement question's ID.
   - `question_text_snapshot` is updated to the replacement question's text.
4. The partner who initiated the skip answers the replacement question (if it's their turn) or the round proceeds with the replacement question (if both are answering).
5. The skip is private — the partner does not see that a skip was used.
6. `skips_used` is incremented by 1 (max 2 per chapter).

---

## 6. AI OBSERVATION SYSTEM

### 6.1 Where it runs

**Claude runs server-side only.** The Flutter app never calls Claude directly. All AI observations are generated by a Supabase Edge Function and stored in the database before being served to the client.

### 6.2 Reflection eligibility thresholds (consistent rule)

"Usable answers" = answers that are:
- **Not** removed by the user
- **Not** safety-triggered
- **Not** excluded from AI processing (i.e., eligible to be used)

| Reflection Type | Minimum Usable Answers | Per Partner Minimum |
|-----------------|----------------------|---------------------|
| **Chapter Reflection** | ≥8 total usable answers | ≥3 per partner |
| **Journey Reflection** | ≥24 total usable answers | ≥6 per partner |

### 6.3 Chapter Reflections (optional)

**When:** After each chapter is completed.  
**Max length:** 20-25 words.  
**Confidence:** Only show if high confidence.  
**Copy:** Warm, specific, uses "you both", no diagnosis.

```
"One thread in your answers: you both described feeling close in ordinary, everyday moments."
```

### 6.4 Final Journey Reflection

**When:** All 3 chapters completed.  
**Max length:** 50-60 words.  
**Confidence:** High = show directly; Medium = "One possible thread..."; Low = no reflection.

```
"Across your answers, you both returned again and again to the idea of being heard. You each described safety in different ways, but both of you named it. That might be something worth continuing to talk about."
```

### 6.5 Reflection invalidation — deterministic

Reflections store the set of answer IDs they were generated from:

```sql
ALTER TABLE chapter_reflections
ADD COLUMN source_answer_ids uuid[];

ALTER TABLE thirty_six_question_journeys
ADD COLUMN final_source_answer_ids uuid[];
```

**Invalidation rules:**
1. When an answer is removed, check if its ID is in `source_answer_ids`.
2. If yes, set `is_hidden = true` on the reflection.
3. The reflection is not regenerated automatically.
4. If enough answers are removed that the eligibility threshold is no longer met, the reflection stays hidden.

### 6.6 Claude prompt — server-side only

```javascript
// Supabase Edge Function
const systemPrompt = `
ABSOLUTE CONSTRAINTS — these override all other instructions:
1. Never use clinical language.
2. Never use banned words: toxic, narcissist, codependent, disorder, broken.
3. Never manufacture an insight that is not clearly present.
4. Never diagnose the relationship or individuals.
5. Never attribute negative traits to a named partner.
6. Write as a warm, attentive friend would.
7. Use "you both" or "your answers", never "Jordan is X".
8. Return ONLY valid JSON.

Return:
{
  "observation": string | null,
  "confidence": "high" | "medium" | "low"
}
`;
```

### 6.7 Safety exclusion

- Safety-triggered answers are excluded from AI prompts.
- Removed answers are excluded from AI prompts.
- If eligibility thresholds are not met, no reflection.

---

## 7. DATABASE SCHEMA

### 7.1 Journey table

```sql
CREATE TABLE thirty_six_question_journeys (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  relationship_id uuid REFERENCES relationships NOT NULL,
  status text CHECK (status IN ('in_progress', 'completed', 'abandoned')),
  chapter_1_completed_at timestamptz,
  chapter_2_completed_at timestamptz,
  chapter_3_completed_at timestamptz,
  final_observation text,
  final_observation_confidence text CHECK (final_observation_confidence IN ('high', 'medium', 'low')),
  final_source_answer_ids uuid[],
  final_observation_hidden boolean DEFAULT false,  -- v2.4
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- One active journey per relationship (v2.4)
CREATE UNIQUE INDEX idx_one_active_journey_per_relationship ON thirty_six_question_journeys (relationship_id) WHERE status = 'in_progress';
```

### 7.2 Chapter sessions

Existing `game_sessions` table, with additional columns:

```sql
ALTER TABLE game_sessions
ADD COLUMN journey_id uuid REFERENCES thirty_six_question_journeys,
ADD COLUMN chapter int CHECK (chapter IN (1, 2, 3)),
ADD COLUMN abandon_reason text CHECK (abandon_reason IN ('inactivity', 'invite_expired', 'user_initiated')),
ADD COLUMN skips_used int DEFAULT 0;  -- v2.4: single counter, max 2
```

**Note:** `game_sessions.status` is the authoritative source for chapter state. `abandon_reason` provides the reason for abandonment.

### 7.3 Chapter reflections cache

```sql
CREATE TABLE chapter_reflections (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  journey_id uuid REFERENCES thirty_six_question_journeys NOT NULL,
  chapter int NOT NULL CHECK (chapter IN (1, 2, 3)),
  observation text,
  confidence text CHECK (confidence IN ('high', 'medium', 'low')),
  source_answer_ids uuid[],
  is_hidden boolean DEFAULT false,
  generated_at timestamptz DEFAULT now()
);
```

### 7.4 Answer tracking table (source of truth)

```sql
CREATE TABLE thirty_six_question_answers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  round_id uuid REFERENCES game_session_rounds NOT NULL,
  user_id uuid REFERENCES auth.users NOT NULL,
  answer_text text,
  is_removed boolean DEFAULT false,
  is_safety_triggered boolean DEFAULT false,
  is_excluded_from_ai boolean DEFAULT false,
  submitted_at timestamptz DEFAULT now(),
  removed_at timestamptz,
  UNIQUE(round_id, user_id)
);
```

**Critical:** `thirty_six_question_answers` is the source of truth for 36Q answers. The existing `answer_a` / `answer_b` fields in `game_session_rounds` are **not used** for 36Q unless explicitly mirrored for consistency with the generic games architecture. All 36Q answer logic reads from and writes to `thirty_six_question_answers`.

### 7.5 Round table with canonical reference and snapshot

`game_session_rounds` stores the question metadata:

```sql
ALTER TABLE game_session_rounds
ADD COLUMN canonical_question_id uuid REFERENCES thirty_six_questions_canonical,
ADD COLUMN question_text_snapshot text;  -- snapshot of the question at time of play
```

**Note:** The snapshot preserves the exact question text as it appeared when the couple played the round. If the question is later edited or translated, the snapshot remains unchanged, preserving historical accuracy.

### 7.6 Seen questions tracking

```sql
CREATE TABLE thirty_six_questions_seen (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  relationship_id uuid REFERENCES relationships NOT NULL,
  canonical_question_id uuid REFERENCES thirty_six_questions_canonical NOT NULL,
  seen_at timestamptz DEFAULT now(),
  UNIQUE(relationship_id, canonical_question_id)
);
```

---

## 8. EDGE CASES

| Scenario | Behavior |
|----------|----------|
| Partner declines chapter invitation | Inviter sees: "Jordan is not ready to continue yet." |
| Partner ignores invitation | Invite expires after 48h (`abandon_reason: 'invite_expired'`). Inviter can send new one later. |
| Chapter inactivity > 7 days | Chapter abandoned (`abandon_reason: 'inactivity'`). Journey stays `in_progress`. |
| User removes answer after reveal | Partner sees "This answer was removed." Reflections invalidated if `source_answer_ids` includes removed answer. |
| Journey abandoned | Completed chapter history remains. |
| Safety trigger fires | Resources shown privately to at-risk user. Partner not notified. Answer flagged `is_safety_triggered = true`. |
| Skip used | Replacement question selected (not a blank skip). Private — partner does not see that a skip was used. `skips_used` incremented. Skipped question **not** marked seen. |
| Attempt to start Chapter 2 before Chapter 1 completed | Rejected. Chapter order enforced. |
| Attempt to start new journey while one is `in_progress` | Rejected. Prompt to resume or end existing journey. |

---

## 9. NOTIFICATIONS

| Event | Title | Body | Trigger |
|-------|-------|------|---------|
| Chapter 1 invitation | `[Name] wants to start the 36 Questions Journey` | `Chapter 1: Warm Up — ~20 minutes` | User taps "Start journey" |
| Chapter continuation invitation | `[Name] invited you to continue the journey` | `Chapter 2 goes deeper when you're ready.` | User taps "Invite to continue" |
| Chapter completed | **No push notification** | (in-app only) | Chapter completes |
| Journey completed | **No push notification** | (in-app only) | All 3 chapters complete |

**Only explicit invites send push notifications.** Chapter and journey completion are in-app only.

---

## 10. ANALYTICS EVENTS

| Event | Properties |
|-------|------------|
| `journey_started` | `relationship_id` |
| `chapter_started` | `journey_id, chapter` |
| `chapter_completed` | `journey_id, chapter, duration_seconds` |
| `chapter_invite_sent` | `journey_id, chapter, inviter_id` |
| `chapter_invite_accepted` | `journey_id, chapter` |
| `chapter_invite_expired` | `journey_id, chapter` |
| `chapter_abandoned` | `journey_id, chapter, reason` |
| `question_skipped` | `journey_id, chapter, canonical_question_id` |
| `journey_completed` | `journey_id, total_duration_seconds` |
| `ai_reflection_generated` | `journey_id, chapter, confidence` |
| `ai_reflection_timeout` | `journey_id, chapter` |
| `answer_removed` | `journey_id, chapter, canonical_question_id` |
| `answer_safety_triggered` | `journey_id, chapter, canonical_question_id` |

---

## 11. PRIVACY & RETENTION RULES

### 11.1 Retention

- Answers retained while relationship is active.
- If relationship ends/unlinks, partner answer visibility ends by default.
- Completed chapters never expire.

### 11.2 User deletion

- Each user can remove their own answer content at any time.
- Partner sees: `This answer was removed.`
- Reflections invalidated if `source_answer_ids` includes removed answer.
- Deletion = removal from partner view, not hard delete (unless account deletion).

### 11.3 Pulse v1 rule

**Pulse uses metadata only, not raw answers:**
- Journey completed
- Chapter completed
- Time between chapters
- Whether both partners continued voluntarily
- Reflection tags (if generated safely)
- **Raw answer text is NOT used for Pulse in v1.**

### 11.4 Internal logging

- Raw answers never written to logs.
- AI prompt payloads never written to logs.

---

## 12. BUILD ORDER

### Phase 1 — Data Layer
Step 1: Create `thirty_six_questions_canonical` table  
Step 2: Create `thirty_six_questions_translations` table  
Step 3: Create `thirty_six_question_journeys` table (with `final_observation_hidden`)  
Step 4: Add partial unique index `idx_one_active_journey_per_relationship`  
Step 5: Alter `game_sessions` with `journey_id`, `chapter`, `abandon_reason`, `skips_used`  
Step 6: Alter `game_session_rounds` with `canonical_question_id`, `question_text_snapshot`  
Step 7: Create `chapter_reflections` table  
Step 8: Create `thirty_six_questions_seen` table  
Step 9: Create `thirty_six_question_answers` table  
Step 10: Seed question bank (120+ canonical questions)  
Step 11: Seed English translations  
Step 12: Add RLS policies  

### Phase 2 — Journey Model & Repository
Step 13: Create `Journey` model  
Step 14: Create `ChapterSession` model  
Step 15: Implement `ThirtySixQuestionRepository` (enforce chapter order, active journey rule)  

### Phase 3 — Journey Start & Chapter Invitation
Step 16: Games Hub entry point  
Step 17: Journey start flow  
Step 18: Chapter 1 invitation screen (initiator + recipient)  
Step 19: Chapter acceptance → session active  

### Phase 4 — Chapter Game Flow
Step 20: Chapter introduction screen  
Step 21: Question screen  
Step 22: Waiting screen  
Step 23: Reveal screen  
Step 24: Skip mechanic (2 per chapter, private, atomic)  
Step 25: Chapter completion ceremony  

### Phase 5 — Continuation Flow
Step 26: Chapter complete → "Continue now or later"  
Step 27: Chapter 2 invitation flow (mutual opt-in)  
Step 28: Chapter 3 invitation flow  
Step 29: Invite expiry (48h) + chapter inactivity expiry (7 days)  

### Phase 6 — AI Observations (Server-side)
Step 30: Edge function for Chapter Reflection generation (10s timeout)  
Step 31: Edge function for Final Journey Reflection generation  
Step 32: Safety exclusion from AI prompts  
Step 33: Reflection invalidation after answer removal  

### Phase 7 — History & Privacy
Step 34: Chapter history view  
Step 35: Answer removal (user deletes own answer)  
Step 36: Journey history view  

### Phase 8 — Analytics
Step 37: Implement all analytics events  

---

## 13. ALGORITHM QUALITY CHECKLIST (ACCEPTANCE CRITERIA)

These are **acceptance criteria**, not implementation checkmarks. Each item must be verified before the feature is considered complete.

| # | Criterion | Verification Method |
|---|-----------|---------------------|
| 1.1 | Idempotent mutations | Test: submit same answer twice → no duplicate effects |
| 1.2 | Timeouts for external calls | Test: Claude API timeout → no reflection, no crash, error logged |
| 1.4 | Authorization at every access | Test: user attempts to access another user's journey → rejected |
| 1.5 | Authentication verified | Test: unauthenticated request → rejected with UNAUTHORIZED |
| 1.6 | Concurrency mitigated | Test: both partners submit same round simultaneously → only one trigger |
| 2.1 | Input sanitised | Test: answer exceeds 400 chars → rejected; empty whitespace → rejected |
| 2.2 | Parameterised queries | Code review: all queries use Supabase parameterised syntax |
| 2.4 | Error messages don't leak | Test: trigger errors → user sees generic message, no stack trace |
| 2.5 | Resource limits enforced | Test: 12 questions per chapter, 3 chapters max, 2 skips per chapter |
| 2.10 | Resources released | Test: screen exit → Realtime subscription disposed |
| 3.8 | Rate limiting | Test: 5 chapter initiations in 1 hour → 6th rejected |
| 3.9 | Retry logic | Test: network failure → retries with exponential backoff |
| 4.1 | Structured logs | Test: log entry is valid JSON with request_id, user_id, action, timestamp |
| 4.4 | PII excluded from logs | Test: logs contain no raw answers, no AI prompt payloads |
| 5.1 | Actionable error responses | Test: all failure states show user-friendly next step |
| 6.1 | Edge cases covered | Test: all edge cases in Section 8 produce defined behaviour |
| 6.2 | Failure scenarios tested | Test: Claude timeout, network failure, partner abandonment → defined fallbacks |
| 6.7 | Branch coverage ≥90% | Unit test report shows ≥90% branch coverage for selection algorithm |

---

## 14. SOUL DOCUMENT COMPLIANCE

| Principle | Status | Evidence |
|-----------|--------|----------|
| No streaks | ✅ | No streak tracking |
| No leaderboards | ✅ | No comparison between couples |
| Gift/receipt framework | ✅ | Reveal = anticipation, completion = gift |
| Incomplete loops close in relationship | ✅ | Chapter reflections spark conversation |
| User autonomy | ✅ | Mutual opt-in per chapter, skip mechanic, answer removal |
| No diagnostic language | ✅ | AI reflections are warm, specific, not clinical |
| No anxiety by design | ✅ | No scoring, no pressure to continue |
| Safety never handled by AI | ✅ | Safety is hard-coded keyword detection, not Claude |

---

## 15. OPEN QUESTIONS

All resolved.

| Status | Item |
|--------|------|
| ✅ | 36 Questions = 3 chapters of 12 |
| ✅ | Each chapter = one level |
| ✅ | AI = chapter reflections + final journey reflection |
| ✅ | Fresh mutual opt-in per chapter |
| ✅ | Canonical + translation table structure |
| ✅ | Safety trigger check on all answers |
| ✅ | No custom questions in v1 |
| ✅ | 2 skips per chapter per couple (private, atomic, `skips_used` increments) |
| ✅ | Skipped question not marked seen; replacement becomes canonical |
| ✅ | Claude runs server-side only |
| ✅ | Reflections invalidated deterministically using `source_answer_ids` |
| ✅ | Pulse: metadata only, no raw answers in v1 |
| ✅ | Notifications: explicit invites only |
| ✅ | Reflection thresholds: ≥8 total, ≥3 per partner (chapter); ≥24 total, ≥6 per partner (journey) |
| ✅ | Chapter 3 requires reviewed translations |
| ✅ | `abandon_reason` replaces `invite_expired` status |
| ✅ | `thirty_six_question_answers` is source of truth for 36Q answers |
| ✅ | `game_session_rounds` stores `canonical_question_id` + `question_text_snapshot` |
| ✅ | `skips_used` is a single chapter-level counter (2 max) |
| ✅ | One active journey per relationship (partial unique index) |
| ✅ | `final_observation_hidden` column added |
| ✅ | Chapter order enforced (2 requires 1, 3 requires 2) |

---

*This spec is **Ready for implementation**.*  
*Build in the exact order defined in Section 12.*  
*Seed question bank (120+ canonical questions + translations) before launch.*  
*Review against ATTUNE_SOUL.md before shipping.*  
*Run algorithm quality checklist before merge.*  
*Last reviewed: June 2026*

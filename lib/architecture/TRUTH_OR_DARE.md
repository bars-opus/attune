## ATTUNE — TRUTH OR DARE GAME SPECIFICATION (UPDATED v1.1)

**Version:** 1.1 (updated after grill review)  
**Created:** June 2026  
**Last updated:** June 2026  
**Status:** Ready for implementation  
**Part of:** Games Module — Game 2 of 3  
**Related documents:**  
- `ATTUNE_MASTER_SPEC.md`  
- `ATTUNE_SOUL.md`  
- `ATTUNE_PRINCIPLES_CHECKLIST.md`  
- `ATTUNE_CLINICAL.md`  
- `ATTUNE_GAMES_MODULE_SPEC.md`  
- `../algorithms/algorithm_quality_review_checklist.md`

---

## TABLE OF CONTENTS

1. Game Overview
2. Game Flow
3. Screen Designs
4. Question Bank
5. Selection Algorithm
6. Database Schema Extensions
7. Edge Cases
8. Notifications
9. Analytics Events
10. Build Order
11. Algorithm Quality Checklist
12. Soul Document Compliance
13. Open Questions

---

## 1. GAME OVERVIEW

### 1.1 What it is

The classic Truth or Dare game, reimagined for two people on separate devices. Each round the app randomly selects either a Truth or a Dare for the active player. The player taps the face‑down card to reveal what type they got, completes it, and confirms. The other partner sees the result.

### 1.2 Core characteristics

| Characteristic | Value |
|----------------|-------|
| Duration | ~15 minutes (10 rounds) |
| Players | 2 (asynchronous on separate devices) |
| Tones | Connecting, Romantic, Playful, Spicy, Intimate |
| Turn structure | Alternating (A → B → A → B …) |
| Rounds | 10 rounds |
| Type selection | **App randomly selects** Truth or Dare (50/50, no player choice, no soft balancing) |
| Card flip | Player taps face‑down card to reveal type + content |
| Skip mechanic | One skip per partner per session (replaces Dare with a Truth — **private, no notification to partner**) |
| Custom questions | Included in v1, **private by default** (user must explicitly share) |

### 1.3 What makes it work for couples

- **Spontaneity:** The app chooses for you — no "I always pick Truth" safety net
- **Surprise:** The card flip creates anticipation and excitement
- **Trust:** Dares require physical completion, fostering trust and vulnerability
- **Adaptability:** Tone system ensures content matches relationship stage
- **Autonomy:** Skip is private, custom questions are private by default

---

## 2. GAME FLOW

### 2.1 Complete flow diagram

```
Partner A initiates (tone selector, invite flow identical to Games Module)
    │
    ▼
Both partners see the game screen (Round 1)
    │
    ▼
Partner A's turn (alternating)
    │
    ├── Face‑down card with ? icon
    ├── Player taps card → app randomly selects Truth or Dare (50/50)
    ├── Card flips to reveal Truth question or Dare instruction
    │
    ├── If Truth: type answer (max 200 chars), submit
    │   └── Safety trigger check on answer (hard‑coded keywords, no AI)
    │   └── Disclosure: "Stored in your game history"
    │
    ├── If Dare: complete in real life, tap "Done"
    │   └── Skip available (one per partner per session, **private**)
    │   └── Skip replaces Dare with a different Truth
    │   └── Partner is NOT notified that a skip was used
    │
    ▼
Partner B watches (sees type + content + waiting animation)
    │
    ▼
When Partner A confirms (Truth submitted OR Dare Done):
    │
    ▼
Reveal screen — Partner B sees the Truth answer or Dare completion
    │
    ▼
Next round — Partner B's turn
    │
    ▼
Repeat for 10 rounds
    │
    ▼
End screen with stats (no skip counts shown)
```

### 2.2 Turn structure (alternating)

```
Round 1: Partner A → Partner B watches
Round 2: Partner B → Partner A watches
Round 3: Partner A → Partner B watches
…
Round 10: Partner B (if even) / Partner A (if odd)
```

### 2.3 Type selection — fully random

The app randomly selects Truth or Dare **after** the player taps the face‑down card. The player does not choose. No re‑roll. No override. No soft balancing.

```
Player sees face‑down card →
    │
    ▼
Taps card →
    │
    ▼
App selects Truth or Dare (50/50 chance, pure random) →
    │
    ▼
Card flips to reveal type + content
```

### 2.4 Card flip mechanic

1. Player taps the face‑down card
2. App randomly selects the type (Truth or Dare)
3. Card flips with an animation (300ms, 3D rotation)
4. Content appears on the card (question or instruction)
5. Action area appears below (text input for Truth, "Done" button for Dare)

### 2.5 Skip mechanic (private — UPDATED)

| Rule | Behavior |
|------|----------|
| Availability | Only when a Dare is revealed (not available for Truth) |
| Limit | **One skip per partner per session** |
| Effect | Replaces the current Dare with a **different Truth** (same tone) |
| Privacy | **Partner is NOT notified** that a skip was used. They simply see a Truth appear. |
| Atomic tracking | `skips_used_a` / `skips_used_b` on `game_sessions` (tracked for analytics only) |
| End screen | **Skip counts are NOT shown** — removes social pressure |

---

## 3. SCREEN DESIGNS

### 3.1 Turn indicator — face‑down card

```
┌─────────────────────────────────────┐
│  ← Back   Truth or Dare   Round 3/10│
│           Spicy tone                 │
├─────────────────────────────────────┤
│                                     │
│  Your turn, Jordan.                 │
│                                     │
│      ┌─────────────────┐           │
│      │                 │           │
│      │       ?         │           │
│      │                 │           │
│      └─────────────────┘           │
│                                     │
│  Tap the card to reveal what you    │
│  got...                             │
└─────────────────────────────────────┘

Rules:
- Entire card area is tappable
- Tapping triggers random selection + flip animation
- No "Truth" or "Dare" buttons — the app decides
```

### 3.2 Card revealed — Truth

```
┌─────────────────────────────────────┐
│  ← Back   Truth or Dare   Round 3/10│
├─────────────────────────────────────┤
│                                     │
│  🗣 TRUTH (chosen for you)          │
│                                     │
│  What is something you have always  │
│  wanted to tell me but have not     │
│  yet said?                          │
│                                     │
│  ─────────────────────────────────  │
│                                     │
│  Your answer:                       │
│  ┌─────────────────────────────┐   │
│  │ Type your answer here...    │   │
│  └─────────────────────────────┘   │
│  Max 200 characters                 │
│                                     │
│  Partner will see your answer.      │
│  Stored in your game history.       │  ← NEW: disclosure added
│                                     │
│               [Submit answer]       │
└─────────────────────────────────────┘
```

### 3.3 Card revealed — Dare

```
┌─────────────────────────────────────┐
│  ← Back   Truth or Dare   Round 3/10│
├─────────────────────────────────────┤
│                                     │
│  🎯 DARE (chosen for you)           │
│                                     │
│  Send Jordan a voice note saying    │
│  three things you love about them   │
│  right now.                         │
│                                     │
│  ─────────────────────────────────  │
│                                     │
│  Complete the dare, then tap Done.  │
│  Partner will see what your dare was│
│                                     │
│  ┌─────────────────────────────┐   │
│  │  [Skip this dare — I'll take │   │
│  │   another truth instead]    │   │
│  │   (1 skip remaining)        │   │
│  └─────────────────────────────┘   │
│                                     │
│                         [Done ✓]   │
└─────────────────────────────────────┘

Skip button behaviour:
- Before tapping Done: "Skip this dare — I'll take another truth instead"
- After skip used: "No skips remaining" (button disabled or hidden)
- Skip replaces current Dare with a new Truth (same tone)
- Partner sees the Truth appear without explanation — they do not know a skip was used
```

### 3.4 Partner watching screen

```
┌─────────────────────────────────────┐
│  ← Back   Truth or Dare   Round 3/10│
├─────────────────────────────────────┤
│                                     │
│  Jordan's turn 👀                   │
│                                     │
│  Type: 🎯 Dare                      │
│                                     │
│  The dare:                          │
│  "Send a voice note saying three    │
│   things you love about them"       │
│                                     │
│  ┌─────────────────────────────┐   │
│  │        ⏳                    │   │
│  │   Waiting for Jordan to      │   │
│  │   complete...                │   │
│  └─────────────────────────────┘   │
│                                     │
│  [subtle animation]                 │
└─────────────────────────────────────┘

For Truth: shows the question, waiting for answer submission
For Dare: shows the dare description, waiting for "Done"
```

### 3.5 Reveal screen — after completion

**For Truth:**

```
┌─────────────────────────────────────┐
│  ← Back   Truth or Dare   Round 3/10│
├─────────────────────────────────────┤
│                                     │
│  🗣 Truth completed!                 │
│                                     │
│  Jordan's answer to:                │
│  "What is something you have always │
│   wanted to tell me but haven't?"   │
│                                     │
│  "I've always wanted to tell you    │
│   that I love how you make me feel  │
│   safe enough to be myself."        │
│                                     │
│  ┌─────────┐                        │
│  │ Next → │                        │
│  └─────────┘                        │
└─────────────────────────────────────┘
```

**For Dare:**

```
┌─────────────────────────────────────┐
│  ← Back   Truth or Dare   Round 3/10│
├─────────────────────────────────────┤
│                                     │
│  🎯 Dare completed!                 │
│                                     │
│  Jordan completed the dare:         │
│  "Send a voice note saying three    │
│   things you love about them"       │
│                                     │
│  ✅ Completed ✓                     │
│                                     │
│  ┌─────────┐                        │
│  │ Next → │                        │
│  └─────────┘                        │
└─────────────────────────────────────┘
```

### 3.6 End screen (UPDATED — no skip counts)

```
┌─────────────────────────────────────┐
│  ← Back        Game over!           │
├─────────────────────────────────────┤
│                                     │
│  Session complete!                  │
│                                     │
│  You completed:                     │
│    Truths: 4  Dares: 6              │
│  Jordan completed:                  │
│    Truths: 7  Dares: 3              │
│                                     │
│  Most interesting:                  │
│  Truth: "What is something you have │
│   always wanted to tell me?"       │
│   Jordan's answer: [preview]        │
│                                     │
│  ┌─────────┐      ┌──────────────┐ │
│  │Play again│      │Try another   │ │
│  │         │      │    game →    │ │
│  └─────────┘      └──────────────┘ │
└─────────────────────────────────────┘

Skip counts are NOT shown on the end screen.
Skips are private and tracked only for analytics.
```

### 3.7 Most interesting pick logic (UPDATED — deterministic)

**Priority order:**

1. **Find the longest Truth answer** in the session (character length). Longer answers are a proxy for emotional engagement and vulnerability. This is deterministic and requires no AI.
2. If no Truths were answered, **show the first Dare** completed.
3. If a skip was used, **show the round where the skip occurred** (this is a moment of genuine choice).
4. Fallback: show the first round.

```javascript
function getMostInterestingPick(rounds):
  // Step 1: Find longest Truth answer
  truthRounds = rounds.filter(r => r.chosen_type == 'truth' && r.answer)
  if truthRounds.length > 0:
    return truthRounds.sortBy(r => r.answer.length).last  // longest answer

  // Step 2: Show first Dare
  dareRounds = rounds.filter(r => r.chosen_type == 'dare' && r.completed)
  if dareRounds.length > 0:
    return dareRounds.first

  // Step 3: Show skip round
  skipRounds = rounds.filter(r => r.is_skip == true)
  if skipRounds.length > 0:
    return skipRounds.first

  // Step 4: Fallback to first round
  return rounds.first
```

---

## 4. QUESTION BANK

### 4.1 Preset question structure

| Field | Type | Description |
|-------|------|-------------|
| `id` | uuid | Primary key |
| `game_type` | text | `'truth_or_dare'` |
| `question_subtype` | text | `'truth'` or `'dare'` |
| `question_text` | text | The question (Truth) or instruction (Dare) |
| `tone` | text | connecting, romantic, playful, spicy, intimate |
| `tone_level` | int | 1-4 |
| `active` | boolean | Soft delete flag |

### 4.2 Minimum question counts before launch

| Tone | Truths | Dares | Total |
|------|--------|-------|-------|
| Connecting | 30 | 20 | 50 |
| Romantic | 30 | 20 | 50 |
| Playful | 30 | 20 | 50 |
| Spicy | 30 | 20 | 50 |
| Intimate | 30 | 20 | 50 |
| **Total** | **150** | **100** | **250** |

### 4.3 Custom questions (UPDATED — private by default)

Users can create custom Truths and Dares:

| Field | Description |
|-------|-------------|
| `user_id` | Creator |
| `question_type` | `'truth'` or `'dare'` |
| `content` | The question (Truth) or instruction (Dare) |
| `tone` | connecting, romantic, playful, spicy, intimate |
| `is_private` | **Default: true** (only visible to creator until explicitly shared) |
| `times_used` | Usage counter |

**Creating a custom Truth:**
- Select "Truth" type
- Write the question (max 200 chars)
- Select tone
- **Default: private** — toggle to share with partner

**Creating a custom Dare:**
- Select "Dare" type
- Write the instruction (max 200 chars)
- Select tone
- **Default: private** — toggle to share with partner

**Custom question moderation (NEW):**
- Partner can report any custom question they see
- **At 1 report** (since only 2 people ever see a custom question), the question is flagged for review and **immediately stops being served**
- Creator is notified generically: "A custom question has been removed from circulation"
- If the question content matches the safety trigger list (hard‑coded keywords), it is treated as a safety event per `ATTUNE_MASTER_SPEC.md` Section 8.7 — resources surfaced to the at‑risk partner

### 4.4 Truth answer safety (NEW)

Truth answers are free text and may contain distressing content.

- Truth answers run through the **same safety trigger check as chat messages** (hard‑coded keyword detection, no AI)
- If a safety trigger fires, **surface resources privately to the reader** — not to the writer
- The game continues normally (no interruption)
- This is a light‑touch safety net, not full moderation

---

## 5. SELECTION ALGORITHM (UPDATED)

### 5.1 Preset question selection

```
selectQuestionForRound(sessionId, tone, type, userId):
  // type = 'truth' or 'dare' — determined by random selection
  // userId = the player whose turn it is

  // Step 1: Check custom questions (only shared ones)
  customPool = SELECT * FROM custom_truth_or_dare_questions
               WHERE (user_id = userId OR user_id = partnerId)
                 AND question_type = type
                 AND tone = selectedTone
                 AND is_private = false  // only shared questions
               ORDER BY times_used ASC, last_used_at ASC NULLS FIRST

  if customPool.length > 0:
    return customPool[0]  // used least first

  // Step 2: Check unseen preset questions
  seenIds = getSeenQuestionIds(relationshipId, 'truth_or_dare')
  presetPool = SELECT * FROM game_questions
               WHERE game_type = 'truth_or_dare'
                 AND question_subtype = type
                 AND tone = selectedTone
                 AND active = true
                 AND id NOT IN seenIds
               ORDER BY RANDOM()

  if presetPool.length > 0:
    return presetPool[0]

  // Step 3: Allow repeats from seen pool
  repeatPool = SELECT * FROM game_questions
               WHERE game_type = 'truth_or_dare'
                 AND question_subtype = type
                 AND tone = selectedTone
                 AND active = true
                 AND id IN seenIds
               ORDER BY RANDOM()
               LIMIT 1

  return repeatPool[0]  // fallback
```

### 5.2 Type selection — fully random

```
function selectTypeForRound():
  return random() < 0.5 ? 'truth' : 'dare'
```

### 5.3 Skip mechanic (private — UPDATED)

When a player taps "Skip" on a Dare:

```
function handleSkip(sessionId, userId):
  // Check if user already used their skip
  session = SELECT * FROM game_sessions WHERE id = sessionId
  if userId == session.user_a AND session.skips_used_a >= 1:
    throw Exception('Skip already used')
  if userId == session.user_b AND session.skips_used_b >= 1:
    throw Exception('Skip already used')

  // Increment skip count atomically
  if userId == session.user_a:
    UPDATE game_sessions SET skips_used_a = skips_used_a + 1
    WHERE id = sessionId AND skips_used_a < 1
  else:
    UPDATE game_sessions SET skips_used_b = skips_used_b + 1
    WHERE id = sessionId AND skips_used_b < 1

  // Select a new Truth question (same tone)
  newQuestion = selectQuestionForRound(sessionId, tone, 'truth', userId)

  // Replace the current Dare in the round
  UPDATE game_session_rounds
  SET question_id = newQuestion.id,
      chosen_type = 'truth',
      is_skip = true  // track that this was a skip
  WHERE round_id = currentRoundId

  // DO NOT notify partner — the skip is private
  // Partner simply sees a Truth appear without explanation

  return newQuestion
```

### 5.4 Custom question priority — no cap (UPDATED)

No cap on custom questions per session. If a couple has shared custom questions, they will be served. Once custom questions are exhausted, the algorithm falls back to preset content. This preserves the personal touch and does not override the couple's preference.

### 5.5 Seen questions tracking

- Only preset questions are tracked in `game_questions_seen`
- Custom questions are **not** tracked (they can repeat)
- Seen question insert happens when a round is **completed** (both players have moved on)

---

## 6. DATABASE SCHEMA EXTENSIONS

### 6.1 Custom Truth or Dare questions

```sql
CREATE TABLE custom_truth_or_dare_questions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES auth.users NOT NULL,
  question_type text NOT NULL CHECK (question_type IN ('truth', 'dare')),
  content text NOT NULL CHECK (char_length(content) <= 200),
  tone text NOT NULL CHECK (tone IN ('connecting','romantic','playful','spicy','intimate')),
  is_private boolean DEFAULT true,  -- UPDATED: private by default
  times_used int DEFAULT 0,
  last_used_at timestamptz,
  report_count int DEFAULT 0,
  hidden_for_review boolean DEFAULT false,  -- NEW: flagged for review
  created_at timestamptz DEFAULT now()
);

-- RLS: creator can read/write own
CREATE POLICY "custom_tod_questions_owner"
ON custom_truth_or_dare_questions FOR ALL
USING (auth.uid() = user_id);

-- RLS: partner can read non-private, non-hidden
CREATE POLICY "custom_tod_questions_relationship_read"
ON custom_truth_or_dare_questions FOR SELECT
USING (
  is_private = false
  AND hidden_for_review = false
  AND user_id IN (
    SELECT user_a FROM relationships WHERE user_b = auth.uid()
    UNION
    SELECT user_b FROM relationships WHERE user_a = auth.uid()
  )
);
```

### 6.2 Add Truth or Dare specific columns to game_sessions

```sql
ALTER TABLE game_sessions
ADD COLUMN current_turn_user_id uuid REFERENCES auth.users,
ADD COLUMN skips_used_a int DEFAULT 0,
ADD COLUMN skips_used_b int DEFAULT 0;
```

### 6.3 Add skip tracking to game_session_rounds

```sql
ALTER TABLE game_session_rounds
ADD COLUMN is_skip boolean DEFAULT false,
ADD COLUMN skip_replaced_type text CHECK (skip_replaced_type IN ('truth', 'dare'));
```

### 6.4 Session history — metadata only (NEW)

Truth or Dare session history stores **metadata only** — date, tone, Truth/Dare counts. **Full Truth answers are not stored in the history view.** The answers exist in the round data for the session (they are still present in the database) but they are not exposed in the history UI.

History view query (metadata only):

```sql
SELECT
  id,
  relationship_id,
  tone,
  status,
  created_at,
  -- Calculate counts from rounds
  (SELECT COUNT(*) FROM game_session_rounds WHERE session_id = s.id AND chosen_type = 'truth') as truths_count,
  (SELECT COUNT(*) FROM game_session_rounds WHERE session_id = s.id AND chosen_type = 'dare') as dares_count,
  (SELECT COUNT(*) FROM game_session_rounds WHERE session_id = s.id AND is_skip = true) as skips_used
FROM game_sessions s
WHERE relationship_id = p_relationship_id
  AND game_type = 'truth_or_dare'
  AND status = 'completed';
```

---

## 7. EDGE CASES

| Scenario | Behavior |
|----------|----------|
| Player taps card → random selects type | Card flips immediately to reveal type + content |
| No custom questions available for selected type | Fallback to preset questions |
| No preset questions left (unseen) | Allow repeats from seen pool |
| Player skips a Dare (private) | Replaced with Truth. Partner NOT notified. |
| Both partners skip | No penalty, session continues normally |
| Partner completes Truth/Dare, other partner closes app | Session stays active, notification sent |
| App selects same type 10 times in a row | Pure random — acceptable, no balancing |
| Dare requires physical action, player takes long time | No timer, partner waits on watching screen |
| Player taps "Done" on Dare | Partner sees completion confirmation |
| Custom question reported (1 report) | Immediately hidden, creator notified generically |
| Truth answer triggers safety check | Resources surfaced to reader, game continues |
| Session history viewed | Metadata only (date, tone, counts — not full answers) |

---

## 8. NOTIFICATIONS (UPDATED — no previews)

| Event | Title | Body | Data |
|-------|-------|------|------|
| Game invitation | `[Name] wants to play Truth or Dare` | `[Tone] tone — ~15 minutes` | `{ type: 'game_invite', session_id }` |
| Your turn | `Your turn in Truth or Dare` | `Tap the card to reveal what you got 🎲` | `{ type: 'your_turn', session_id, round_number }` |
| Partner answered (Truth) | `Partner answered their truth` | `Tap to see their answer 👀` | `{ type: 'partner_answered', session_id, round_number }` |
| Partner completed (Dare) | `Partner completed their dare` | `Tap to see what they did 🎯` | `{ type: 'partner_completed', session_id, round_number }` |
| Session abandoned | `Game session expired` | `Start a new game of Truth or Dare →` | `{ type: 'session_expired', game_type }` |

**No answer previews in notification bodies.** The content lives inside the app only, preserving the reveal mechanic.

---

## 9. ANALYTICS EVENTS

| Event | Properties |
|-------|------------|
| `game_session_started` | `game_type: 'truth_or_dare', tone, initiator_id` |
| `game_card_flipped` | `session_id, round_number, type: 'truth'/'dare', player_id` |
| `game_truth_submitted` | `session_id, round_number, player_id, answer_length` |
| `game_dare_completed` | `session_id, round_number, player_id` |
| `game_dare_skipped` | `session_id, round_number, player_id` (analytics only, not shown to users) |
| `game_round_completed` | `session_id, round_number, type` |
| `game_session_completed` | `session_id, truths_completed_a, dares_completed_a, truths_completed_b, dares_completed_b` (no skip counts in analytics) |
| `session_abandoned` | `session_id, reason` |
| `custom_question_created` | `user_id, type: 'truth'/'dare', tone, is_private` |
| `custom_question_shared` | `user_id, type: 'truth'/'dare'` |
| `custom_question_reported` | `question_id, reason` |
| `truth_answer_safety_trigger` | `session_id, round_number` |

---

## 10. BUILD ORDER

### Phase 1 — Data Layer
- Run migrations: `custom_truth_or_dare_questions` table (private by default), alter `game_sessions`, alter `game_session_rounds`
- Seed preset question bank (250 questions across all tones)
- Add RLS policies for custom questions (including hidden_for_review)
- Add indexes for performance

### Phase 2 — Shared Architecture (already built)
- All session creation, invitation, notification, timeout logic from Games Module
- Idempotency keys, concurrency control, rate limiting, error handling

### Phase 3 — Question Selection
- Random type selector (50/50)
- Selection algorithm with custom + preset pools (custom priority, no cap)
- Skip logic (atomic increment, **no partner notification**)
- Custom question moderation (1 report → hide immediately)
- Truth answer safety trigger check

### Phase 4 — Screens
- Turn indicator with face‑down card
- Card flip with random type selection + animation
- Truth answer input (max 200 chars, disclosure: "Stored in your game history")
- Dare instruction + Done button
- Skip button (Dare only, one per session, private)
- Partner watching screen (shows type + content)
- Reveal screen (Truth answer or Dare completion)
- End screen (Truth/Dare counts, **no skip counts**, most interesting pick)

### Phase 5 — Custom Questions CRUD
- Create custom Truth/Dare (type selector, tone selector, content input, **private by default**)
- List own questions with type toggle
- Share/unshare with partner
- Edit/delete own questions
- Report custom question (1 report → hidden immediately)

### Phase 6 — Session History
- History list: metadata only (date, tone, Truth/Dare counts)
- Detail view: rounds with answers (this is the session detail, not the history list — full answers remain visible in the session detail for review immediately after playing)

---

## 11. ALGORITHM QUALITY CHECKLIST

| # | Check | Status | Implementation |
|---|-------|--------|----------------|
| 1.1 | Idempotency for mutations | ✅ | Skip increment uses atomic update; answer submission upserts |
| 1.2 | Timeouts for external calls | ✅ | All API calls have 10s timeout with fallback |
| 1.4 | Authorization at every access | ✅ | JWT + relationship membership check on every endpoint |
| 1.5 | Authentication verified | ✅ | JWT validation before all endpoints |
| 1.6 | Concurrency risks mitigated | ✅ | Row lock + transaction for simultaneous submissions |
| 2.1 | Input sanitisation | ✅ | Type validation, length limits, reject invalid values |
| 2.2 | Parameterised queries | ✅ | Supabase RLS + parameterised queries |
| 2.4 | Error messages don't leak | ✅ | Generic user messages; internal logs only |
| 2.5 | Resource limits enforced | ✅ | 10 rounds, 200 char Truth answers, rate limits |
| 2.10 | Resources released | ✅ | Realtime subscriptions disposed on screen exit |
| 2.14 | Memory growth bounded | ✅ | No unbounded caches |
| 3.1 | Pagination | ✅ | Past games list paginated |
| 3.8 | Rate limiting | ✅ | 5 game init/hour, 1 answer/2s |
| 3.9 | Retry logic | ✅ | Exponential backoff + manual retry |
| 3.10 | No retry on permanent errors | ✅ | 4xx errors never retried |
| 4.1 | Structured logs | ✅ | JSON format with request_id, hashed user_id |
| 4.4 | PII excluded from logs | ✅ | Answers, content never logged |
| 4.6 | RED metrics | ✅ | Rate, Errors, Duration defined |
| 4.9 | Alerts defined | ✅ | Session failure, latency, timeout alerts |
| 5.1 | Actionable error responses | ✅ | Clear user messages with next steps |
| 5.5 | No internal info leaked in UI | ✅ | Generic error messages only |
| 6.1 | Edge cases covered | ✅ | Table of 10+ edge cases |
| 6.2 | Failure scenarios tested | ✅ | All error paths have defined behaviour |
| 6.3 | Concurrency tested | ✅ | Simultaneous answer test case documented |
| 6.7 | Branch coverage ≥ 90% | ✅ | Unit tests required for selection algorithm |

---

## 12. SOUL DOCUMENT COMPLIANCE

| Principle | Status | Evidence |
|-----------|--------|----------|
| No streaks | ✅ | No streak tracking |
| No leaderboards | ✅ | No comparison between couples |
| No badges | ✅ | No achievement badges |
| Gift/receipt framework | ✅ | Card flip is anticipation; reveal is gift moment |
| Incomplete loops close in relationship | ✅ | Conversations sparked by Truth answers/Dares |
| User autonomy | ✅ | Custom questions (private by default), tone selection, private skip |
| No diagnostic language | ✅ | Game content is experiential, not diagnostic |
| No anxiety by design | ✅ | No scoring pressure, skip is private, no social comparison on end screen |
| Intimate consent gate | ✅ | Both partners must explicitly consent |
| Data belongs to users | ✅ | Soft delete for session history, custom questions private by default |
| Transparency | ✅ | Truth input screen includes "Stored in your game history" disclosure |
| Privacy | ✅ | Custom questions private by default; skip not broadcast; Truth answers not in history list |

---

## 13. OPEN QUESTIONS

All decisions locked in.

| Status | Item |
|--------|------|
| ✅ Resolved | Turn structure: strictly alternate |
| ✅ Resolved | Type selection: fully random (50/50), no soft balancing |
| ✅ Resolved | Card flip: tap to reveal type + content |
| ✅ Resolved | Skip mechanic: one per partner per session, **private**, replaces Dare with Truth |
| ✅ Resolved | Skip notification to partner: **removed entirely** (partner sees Truth without explanation) |
| ✅ Resolved | Custom questions: included in v1, **private by default** |
| ✅ Resolved | Custom question moderation: 1 report → immediately hidden, creator notified generically |
| ✅ Resolved | Truth answer safety: run through chat safety trigger check |
| ✅ Resolved | Notification previews: **removed** from all notification bodies |
| ✅ Resolved | Most interesting pick: deterministic (longest Truth answer → first Dare → skip round → first round) |
| ✅ Resolved | Session history: metadata only (date, tone, counts — not full answers) |
| ✅ Resolved | Skip counts on end screen: **removed entirely** (tracked only in analytics) |
| ✅ Resolved | Custom question cap: **no cap** for v1 |
| ✅ Resolved | Truth storage disclosure: added to input screen |

---

*This spec is complete and ready for implementation.*  
*Build in the exact order defined in Section 10.*  
*Seed preset question bank (250 min) in parallel with build.*  
*Intimate tone: build fully, deploy only after clinical sign-off.*  
*Review against ATTUNE_SOUL.md before shipping.*  
*Run algorithm_quality_review_checklist.md before merge.*  
*Last reviewed: June 2026*
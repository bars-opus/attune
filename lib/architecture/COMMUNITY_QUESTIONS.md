# ATTUNE — COMMUNITY QUESTIONS SPECIFICATION (UPDATED v1.1)

**Version:** 1.1  
**Created:** June 2026  
**Last updated:** June 2026  
**Status:** Ready for implementation (post-launch — Month 3-4)  
**Part of:** Games Module — Community Feature  
**Related documents:**  
- `ATTUNE_MASTER_SPEC.md`  
- `ATTUNE_SOUL.md`  
- `ATTUNE_PRINCIPLES_CHECKLIST.md`  
- `ATTUNE_GAMES_MODULE_SPEC.md`  
- `../algorithms/algorithm_quality_review_checklist.md`

---

## 1. WHAT CHANGED FROM V1

| Change | Reason |
|--------|--------|
| Added `custom_this_or_that_questions` table creation | The table was not created in v1 — this spec now includes the migration |
| Added community feed seeding with 20-30 preset questions | Ensures the feed is never empty at feature launch |
| Updated empty state copy | "No community questions yet" + "Browse our featured collection" instead of "Be the first to share" |

---

## 2. DATABASE SCHEMA (UPDATED)

### 2.1 Create `custom_this_or_that_questions` table (if not exists)

```sql
-- This table should have been created in v1. If not, run this migration.
CREATE TABLE IF NOT EXISTS custom_this_or_that_questions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES auth.users NOT NULL,
  question_text text NOT NULL CHECK (char_length(question_text) <= 100),
  option_a text NOT NULL CHECK (char_length(option_a) <= 50),
  option_b text NOT NULL CHECK (char_length(option_b) <= 50),
  emoji_a text,
  emoji_b text,
  tone text NOT NULL CHECK (tone IN ('connecting','romantic','playful','spicy','intimate')) DEFAULT 'connecting',
  is_private boolean DEFAULT true,
  times_used int DEFAULT 0,
  last_used_at timestamptz,
  report_count int DEFAULT 0,
  hidden_for_review boolean DEFAULT false,
  shared_to_community boolean DEFAULT false,
  community_usage_count int DEFAULT 0,
  created_at timestamptz DEFAULT now()
);

-- RLS Policies (same as custom_truth_or_dare_questions)
ALTER TABLE custom_this_or_that_questions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "custom_tot_questions_owner"
ON custom_this_or_that_questions FOR ALL
USING (auth.uid() = user_id);

CREATE POLICY "custom_tot_questions_relationship_read"
ON custom_this_or_that_questions FOR SELECT
USING (
  is_private = false
  AND hidden_for_review = false
  AND user_id IN (
    SELECT user_a FROM relationships WHERE user_b = auth.uid()
    UNION
    SELECT user_b FROM relationships WHERE user_a = auth.uid()
  )
);

-- Community questions readable by all authenticated users
CREATE POLICY "community_tot_questions_readable"
ON custom_this_or_that_questions FOR SELECT
USING (
  shared_to_community = true
  AND hidden_for_review = false
  AND auth.uid() IS NOT NULL
);
```

### 2.2 Helper function for community usage increment (updated)

```sql
-- Update the existing function to handle both tables
CREATE OR REPLACE FUNCTION increment_community_usage(
  p_question_id uuid,
  p_table text
)
RETURNS void AS $$
BEGIN
  IF p_table = 'this_or_that' THEN
    UPDATE custom_this_or_that_questions
    SET community_usage_count = community_usage_count + 1
    WHERE id = p_question_id;
  ELSIF p_table = 'truth_or_dare' THEN
    UPDATE custom_truth_or_dare_questions
    SET community_usage_count = community_usage_count + 1
    WHERE id = p_question_id;
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

---

## 3. COMMUNITY FEED SEEDING (NEW)

### 3.1 Seeding strategy

At feature launch (Month 3), seed the community feed with 20-30 hand-picked questions from the preset bank.

**Selection criteria:**
- High-quality questions that are likely to spark engagement
- Mix of types: Truth, Dare, This or That
- Mix of tones: Connecting, Romantic, Playful, Spicy (Intimate withheld pending clinical review)
- Questions that are not too generic or too niche

**Seed insertion:**

```sql
-- Example: Seed 5 This or That questions
INSERT INTO custom_this_or_that_questions (
  user_id,
  question_text,
  option_a,
  option_b,
  emoji_a,
  emoji_b,
  tone,
  is_private,
  shared_to_community,
  community_usage_count,
  created_at
)
SELECT
  '00000000-0000-0000-0000-000000000000', -- System user ID (create a dedicated system account)
  question_text,
  option_a,
  option_b,
  emoji_a,
  emoji_b,
  tone,
  false, -- not private (shared)
  true,  -- shared to community
  0,     -- start with 0 usage
  NOW()
FROM game_questions
WHERE game_type = 'this_or_that'
  AND active = true
  AND tone IN ('connecting', 'romantic', 'playful', 'spicy')
ORDER BY RANDOM()
LIMIT 5;

-- Same for Truth or Dare
INSERT INTO custom_truth_or_dare_questions (
  user_id,
  question_type,
  content,
  tone,
  is_private,
  shared_to_community,
  community_usage_count,
  created_at
)
SELECT
  '00000000-0000-0000-0000-000000000000',
  question_subtype,
  question_text,
  tone,
  false,
  true,
  0,
  NOW()
FROM game_questions
WHERE game_type = 'truth_or_dare'
  AND active = true
  AND tone IN ('connecting', 'romantic', 'playful', 'spicy')
ORDER BY RANDOM()
LIMIT 5;
```

### 3.2 Seed questions list (hand-picked)

**This or That (5 questions):**

| Question | Option A | Option B | Tone |
|----------|----------|----------|------|
| Morning person or night owl? | Morning person | Night owl | Connecting |
| City or countryside? | City | Countryside | Connecting |
| Netflix or sleep? | Netflix | Sleep | Playful |
| Pizza or pasta for life? | Pizza | Pasta | Playful |
| Sunset walk or candlelit dinner? | Sunset walk | Candlelit dinner | Romantic |

**Truth or Dare — Truths (5 questions):**

| Question | Tone |
|----------|------|
| What is something about yourself you are still learning? | Connecting |
| What is your favourite memory of us together? | Romantic |
| What is the most embarrassing thing that happened to you this week? | Playful |
| What is something you find attractive about me that you have never told me? | Spicy |
| What is a quality you find irresistible in a partner? | Spicy |

**Truth or Dare — Dares (5 questions):**

| Dare | Tone |
|------|------|
| Write three things you genuinely appreciate about your partner and read them aloud. | Connecting |
| List five things you love about your partner out loud. | Romantic |
| Do your best impression of your partner for 30 seconds. | Playful |
| Describe in detail your ideal evening together — start to finish. | Spicy |
| Tell your partner what you would do if you had a free night together. | Spicy |

**Total: 15 questions seeded at launch.** This ensures the feed is populated without being overwhelming. As users share more, the feed grows organically.

### 3.3 System user account

Create a dedicated system account for seeded questions:

```sql
-- Create a system user (if not exists)
-- This should be done in the auth.users table via Supabase
-- The ID will be used as the user_id for seeded questions
-- The display name should be "Community" (not shown to users, only for internal reference)
```

The system user is never shown — all questions are fully anonymous.

---

## 4. SCREEN DESIGNS (UPDATED)

### 4.1 Empty state (updated)

```
┌─────────────────────────────────────┐
│  ← Back   Community Questions        │
├─────────────────────────────────────┤
│                                     │
│          🌐                         │
│                                     │
│  No community questions yet         │
│                                     │
│  Browse our featured collection     │
│  or share your own question to      │
│  help build the community.          │
│                                     │
│  ┌─────────────────────────────┐   │
│  │  [Browse featured →]         │   │
│  └─────────────────────────────┘   │
│                                     │
│  ┌─────────────────────────────┐   │
│  │  [Create and share a         │   │
│  │   question →]               │   │
│  └─────────────────────────────┘   │
└─────────────────────────────────────┘
```

### 4.2 Community feed (with seeded questions)

```
┌─────────────────────────────────────┐
│  ← Back   Community Questions        │
├─────────────────────────────────────┤
│                                     │
│  🔍 Search questions...             │
│                                     │
│  [All] [Truth] [Dare] [This/That]   │
│  [All] [💙] [❤️] [😄] [🔥] [🌙]    │
│                                     │
│  ┌─────────────────────────────┐   │
│  │  🔀 This or That · 💙 Conn. │   │
│  │                              │   │
│  │  Morning person or night    │   │
│  │  owl?                       │   │
│  │                              │   │
│  │  Used 12 times    [Save →]  │   │  ← seeded question
│  └─────────────────────────────┘   │
│                                     │
│  ┌─────────────────────────────┐   │
│  │  🗣 Truth · 🔥 Spicy         │   │
│  │                              │   │
│  │  What is something you find  │   │
│  │  attractive about me that   │   │
│  │  you have never told me?    │   │
│  │                              │   │
│  │  Used 8 times     [Save →]  │   │
│  └─────────────────────────────┘   │
│                                     │
│  ┌─────────────────────────────┐   │
│  │  🎯 Dare · 💙 Connecting     │   │
│  │                              │   │
│  │  Write three things you     │   │
│  │  genuinely appreciate about │   │
│  │  your partner...            │   │
│  │                              │   │
│  │  Used 23 times    [Save →]  │   │
│  └─────────────────────────────┘   │
└─────────────────────────────────────┘
```

---

## 5. BUILD ORDER (UPDATED)

### Phase 1 — Data Layer (Pre-requisite, run before Month 3)
Step 1: Create `custom_this_or_that_questions` table if not exists (migration)
Step 2: Add RLS policies for community question visibility
Step 3: Verify `shared_to_community` and `community_usage_count` columns exist
Step 4: Add helper function for community usage increment
Step 5: Seed community feed with 15-20 hand-picked questions

### Phase 2 — Community Feed (Month 3)
Step 6: Entry point in Games Hub ("Browse community questions")
Step 7: Community feed screen with pagination
Step 8: Question card component (with Save/Unsave)
Step 9: Filters (type, tone)
Step 10: Search bar
Step 11: Empty state (with "Browse featured" option)

### Phase 3 — Sharing Management
Step 12: "Share with community" toggle on custom question create/edit
Step 13: Confirmation dialog for sharing
Step 14: "Unshare" confirmation dialog
Step 15: Usage count tracking integration

### Phase 4 — Save to Personal Bank
Step 16: Save community question to user's custom bank
Step 17: Increment community_usage_count on original
Step 18: "✓ Saved" state on question card
Step 19: Unsave (delete personal copy)

### Phase 5 — Moderation
Step 20: Report community question flow (1 report → hide)
Step 21: Moderation queue integration
Step 22: Admin actions (keep/remove)

---

## 6. OPEN QUESTIONS

All resolved.

| Status | Item |
|--------|------|
| ✅ Resolved | `custom_this_or_that_questions` table created |
| ✅ Resolved | Community feed seeded with 15-20 questions at launch |
| ✅ Resolved | Empty state copy updated |
| ✅ Resolved | System user account for seeded questions |

---

*This spec is complete and ready for implementation in Month 3-4.*  
*Do not build before Month 3 — requires sufficient user base.*  
*Seed the community feed during the build, not after.*  
*Review against ATTUNE_SOUL.md before shipping.*  
*Run algorithm_quality_review_checklist.md before merge.*  
*Last reviewed: June 2026*

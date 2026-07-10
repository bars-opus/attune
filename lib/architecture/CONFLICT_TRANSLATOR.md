# ATTUNE — CONFLICT TRANSLATOR SPECIFICATION v1.1

**Version:** 1.1 (corrected)  
**Created:** June 2026  
**Last updated:** July 2026  
**Status:** Ready for implementation  
**Part of:** Core Communication Features  
**Related documents:**  
- `ATTUNE_MASTER_SPEC.md`  
- `ATTUNE_SOUL.md`  
- `ATTUNE_PRINCIPLES_CHECKLIST.md`  
- `ATTUNE_CLINICAL.md`  
- `ATTUNE_GAMES_MODULE_SPEC.md`  
- `../algorithms/algorithm_quality_review_checklist.md`

---

## CORRECTIONS FROM V1.0

| Issue | V1.0 | V1.1 Fix |
|-------|------|----------|
| Claude API architecture | Client-side call with API key | Server-side edge function (Master Spec pattern) |
| Personal mode support | "No relationship_id stored" but schema says NOT NULL | Couples mode only; keep `relationship_id` required |
| Need-labeling ambiguity | Implicit, unclear | Explicit distinction: `core_need_identified` (canonical) vs `framing_note` (natural-language paraphrase) |

---

## TABLE OF CONTENTS

1. Feature Overview
2. User Flow
3. Screen Designs
4. Claude Prompt Design
5. Edge Function Architecture
6. Database Schema
7. Edge Cases
8. Notifications
9. Analytics Events
10. Build Order
11. Algorithm Quality Checklist (Acceptance Criteria)
12. Soul Document Compliance
13. Open Questions

---

## 1. FEATURE OVERVIEW

### 1.1 What it is

The Conflict Translator is a private thinking tool that helps users express difficult feelings more clearly. When a user taps **"Help me say this"** in the chat composer, the tool rewrites their message using Nonviolent Communication (NVC) principles — moving from accusation toward need expression. The recipient **never knows** the message was rewritten.

### 1.2 Core characteristics

| Characteristic | Value |
|----------------|-------|
| Trigger | **Pull only** — user must explicitly tap "Help me say this" |
| Recipient awareness | **Never** — no label, no indicator, no "polished with Attune" |
| Privacy | Rewrite is private to the sender — no record of original/rewrite stored |
| Frequency | As often as the user wants; no limit |
| Framing note | Private note shown to sender only: "underlying need: to be heard" |
| Input | The message the user has already typed (or is composing) |
| Output | One alternative phrasing — not multiple options |
| Confidence | High/Medium/Low — low confidence results shown with caveat |
| Architecture | Server-side via Supabase Edge Function (Master Spec pattern) |
| Mode support | Couples mode only |

---

## 2. USER FLOW

### 2.1 Complete flow diagram

```
User types message in chat composer
    │
    ▼
User taps "Help me say this" button (❓ or ✏️ icon)
    │
    ▼
Flutter app calls edge function:
    POST /functions/v1/translate-conflict
    Body: { message, context, relationship_id }
    │
    ▼
Edge function calls Claude (10s timeout)
    │
    ▼
Edge function returns rewrite + framing note + confidence
    │
    ▼
Sheet slides up with side‑by‑side UI
    │
    ├── Left: "What you wrote" (original)
    ├── Right: "One way to say this" (rewrite)
    │
    ▼
Framing note appears below:
    "Underlying need: to be heard"
    │
    ▼
User chooses:
    ├── [Send mine] → sends original message
    ├── [Send this] → sends rewritten message (recipient never knows)
    ├── [Edit this] → opens rewrite in composer for modification
    │
    ▼
If [Send this] or [Edit this]:
    └── Translator usage logged (no message content stored)
    │
    ▼
Sheet dismisses on navigation away
```

### 2.2 Pull vs Push — Locked In

| Design | Status |
|--------|--------|
| User taps "Help me say this" — pull | ✅ Locked |
| Automatic pop‑up or banner — push | ❌ Never |
| Suggestion that user "might want to rephrase" | ❌ Never |

### 2.3 Recipient Rule — Locked In

| Design | Status |
|--------|--------|
| Recipient never knows message was rewritten | ✅ Locked |
| No label, no indicator, no "polished with Attune" | ✅ Locked |
| If user edits rewrite, it's still a normal message | ✅ Locked |
| Any indicator that message was rewritten | ❌ Never |

---

## 3. SCREEN DESIGNS

### 3.1 Entry point — Chat composer

```
┌─────────────────────────────────────────────────────────────┐
│  ┌──────────────────────────────────────────────────────┐  │
│  │  Message...                                        │  │
│  └──────────────────────────────────────────────────────┘  │
│  [📎]  [❓ Help me say this]  [📷]  [➡️ Send]             │
└─────────────────────────────────────────────────────────────┘

Button icon: ❓ (question mark) or ✏️ (pencil)
Button label: "Help me say this" (not "Fix my message" or "Make this nicer")
Button state:
- Enabled only when there is text in the composer
- Disabled when composer is empty
```

### 3.2 Translator sheet (side‑by‑side UI)

```
┌─────────────────────────────────────────────────────────────┐
│  ✕                                                         │
│  ┌─────────────────────┐  ┌─────────────────────────────┐  │
│  │  What you wrote     │  │  One way to say this        │  │
│  │                     │  │                             │  │
│  │  "You never listen  │  │  "I need to feel heard.     │  │
│  │   to me. You always │  │   Could we pause and talk  │  │
│  │   interrupt when I  │  │   about what I'm trying    │  │
│  │   try to explain."  │  │   to say?"                 │  │
│  │                     │  │                             │  │
│  └─────────────────────┘  └─────────────────────────────┘  │
│                                                             │
│  ┌─────────────────────────────────────────────────────────┐│
│  │  Underlying need: to be heard                          ││
│  └─────────────────────────────────────────────────────────┘│
│                                                             │
│  ┌─────────────┐      ┌─────────────┐  ┌──────────────────┐│
│  │  [Send mine] │      │ [Send this] │  │  [Edit this]    ││
│  └─────────────┘      └─────────────┘  └──────────────────┘│
└─────────────────────────────────────────────────────────────┘
```

### 3.3 Low confidence state

```
┌─────────────────────────────────────────────────────────────┐
│  ✕                                                         │
│  ┌─────────────────────┐  ┌─────────────────────────────┐  │
│  │  What you wrote     │  │  One way to say this        │  │
│  │  [original]         │  │  [rewrite]                  │  │
│  └─────────────────────┘  └─────────────────────────────┘  │
│                                                             │
│  ┌─────────────────────────────────────────────────────────┐│
│  │  ⚠️ This rewrite is a suggestion — it may not capture ││
│  │  your exact meaning. Trust your instinct.              ││
│  └─────────────────────────────────────────────────────────┘│
│                                                             │
│  ┌─────────────┐      ┌─────────────┐  ┌──────────────────┐│
│  │  [Send mine] │      │ [Send this] │  │  [Edit this]    ││
│  └─────────────┘      └─────────────┘  └──────────────────┘│
└─────────────────────────────────────────────────────────────┘
```

---

## 4. CLAUDE PROMPT DESIGN

### 4.1 Global constraints (prepended to every prompt)

```
ABSOLUTE CONSTRAINTS — these override all other instructions:

1. Never attribute a negative behaviour to a named or implied partner.
   "Your partner withdraws" is forbidden. "A withdraw pattern exists" is permitted.

2. Never generate a sentence of form "[partner name] tends to X"
   where X is a negative or deficit behaviour.

3. Never use these words: toxic, narcissist, codependent, disorder, broken.

4. Never tell the user what to decide about the relationship.

5. Never diagnose. Observe patterns. Frame with agency.

6. Return ONLY valid JSON. No preamble. No markdown fences.
```

### 4.2 Prompt template

```
You are helping someone express a difficult feeling more clearly.

SENDER PROFILE:
- Attachment: {{attachment_style}}
- Communication style: {{communication_style}}
- Days together: {{days_together}}

ORIGINAL MESSAGE:
"{{original_message}}"

RECENT CONVERSATION TONE: {{last_3_messages_tone_summary}}

Return ONLY valid JSON:
{
  "rewrite": string,
  "core_need_identified": string,     // One of: respect, fairness, affection, security, autonomy, rest
  "framing_note": string,             // Natural-language paraphrase (max 15 words)
  "rewrite_confidence": "high" | "medium" | "low"
}

Rules:
- Preserve the sender's actual meaning — never soften a legitimate concern to nothing
- Rewrite should feel like THEM at their clearest, not a therapist
- If original is already healthy: rewrite = original, confidence = "high"
- Never add false warmth or make sender apologise for something undecided
- Max rewrite length: 1.5x original
- framing_note is private — never shown to recipient
```

Store this prompt template in `/prompts/v1/` and version it like every other Claude prompt in the app.

### 4.3 Need-labeling distinction (clarified)

| Field | Purpose | Example |
|-------|---------|---------|
| `core_need_identified` | Canonical taxonomy label | `respect` |
| `framing_note` | Natural-language paraphrase shown to user | `"to be heard"` |

**Mapping:**

| Canonical Need | Framing Note Example |
|----------------|---------------------|
| `respect` | "to feel heard" |
| `fairness` | "to feel fairly treated" |
| `affection` | "to feel valued" |
| `security` | "to feel safe" |
| `autonomy` | "to have space" |
| `rest` | "for relief" |

---

## 5. EDGE FUNCTION ARCHITECTURE

### 5.1 Edge function location

`supabase/functions/translate-conflict/index.ts`

The edge function must load the versioned prompt template from `/prompts/v1/` rather than embedding an unversioned one-off prompt.

### 5.2 Request format

```typescript
// Request body
{
  message: string,
  context: {
    attachment_style: string | null,
    communication_style: string | null,
    days_together: number | null,
    last_3_messages_tone_summary: string | null,
  },
  relationship_id: string,
}
```

### 5.3 Response format

```typescript
// Success response
{
  rewrite: string,
  core_need_identified: string,  // One of the six canonical needs
  framing_note: string,          // Natural-language paraphrase
  rewrite_confidence: 'high' | 'medium' | 'low'
}

// Error response
{
  error: true,
  code: 'TIMEOUT' | 'INVALID_INPUT' | 'RATE_LIMITED' | 'INTERNAL_ERROR',
  message: string  // Generic user-facing message
}
```

### 5.4 Edge function implementation (TypeScript)

```typescript
// supabase/functions/translate-conflict/index.ts

import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const CLAUDE_API_KEY = Deno.env.get('CLAUDE_API_KEY')
const CLAUDE_URL = 'https://api.anthropic.com/v1/messages'

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const { message, context, relationship_id } = await req.json()

    // Validate input
    if (!message || message.trim().length < 3) {
      return new Response(
        JSON.stringify({
          error: true,
          code: 'INVALID_INPUT',
          message: 'Please write a bit more before using the translator.'
        }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Build prompt
    const userPrompt = `
You are helping someone express a difficult feeling more clearly.

SENDER PROFILE:
- Attachment: ${context?.attachment_style || 'secure'}
- Communication style: ${context?.communication_style || 'assertive'}
- Days together: ${context?.days_together || 'unknown'}

ORIGINAL MESSAGE:
"${message}"

RECENT CONVERSATION TONE: ${context?.last_3_messages_tone_summary || 'neutral'}

Return ONLY valid JSON:
{
  "rewrite": string,
  "core_need_identified": string,     // One of: respect, fairness, affection, security, autonomy, rest
  "framing_note": string,             // Natural-language paraphrase (max 15 words)
  "rewrite_confidence": "high" | "medium" | "low"
}

Rules:
- Preserve the sender's actual meaning — never soften a legitimate concern to nothing
- Rewrite should feel like THEM at their clearest, not a therapist
- If original is already healthy: rewrite = original, confidence = "high"
- Never add false warmth or make sender apologise for something undecided
- Max rewrite length: 1.5x original
- framing_note is private — never shown to recipient
`

    const systemPrompt = `
ABSOLUTE CONSTRAINTS — these override all other instructions:

1. Never attribute a negative behaviour to a named or implied partner.
2. Never generate a sentence of form "[partner name] tends to X" where X is a negative or deficit behaviour.
3. Never use these words: toxic, narcissist, codependent, disorder, broken.
4. Never tell the user what to decide about the relationship.
5. Never diagnose. Observe patterns. Frame with agency.
6. Return ONLY valid JSON. No preamble. No markdown fences.
`

    // Call Claude with timeout
    let response
    try {
      response = await fetch(CLAUDE_URL, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'x-api-key': CLAUDE_API_KEY!,
          'anthropic-version': '2023-06-01',
        },
        body: JSON.stringify({
          model: 'claude-sonnet-4-20250514',
          max_tokens: 200,
          system: systemPrompt,
          messages: [{ role: 'user', content: userPrompt }],
        }),
        signal: AbortSignal.timeout(10000), // 10 second timeout
      })
    } catch (error) {
      console.error('Claude timeout:', error)
      return new Response(
        JSON.stringify({
          error: true,
          code: 'TIMEOUT',
          message: 'Couldn\'t rewrite. Please try again.'
        }),
        { status: 504, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    if (response.status !== 200) {
      console.error('Claude error:', response.status)
      return new Response(
        JSON.stringify({
          error: true,
          code: 'INTERNAL_ERROR',
          message: 'Couldn\'t rewrite. Please try again.'
        }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const data = await response.json()
    const content = data.content?.[0]?.text || ''
    let parsed

    try {
      parsed = JSON.parse(content.replace(/```json|```/g, '').trim())
    } catch (error) {
      console.error('JSON parse error:', error)
      return new Response(
        JSON.stringify({
          error: true,
          code: 'INTERNAL_ERROR',
          message: 'Couldn\'t rewrite. Please try again.'
        }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Validate prohibited content
    const prohibitedPatterns = [
      /your partner (always|never|tends to|keeps)/i,
      /\b(toxic|narcissist|codependent|disorder|broken)\b/i,
      /you should (leave|stay|break up|end)/i,
      /this relationship is/i,
    ]

    const outputText = JSON.stringify(parsed)
    for (const pattern of prohibitedPatterns) {
      if (pattern.test(outputText)) {
        console.error('Prohibited pattern detected:', pattern, outputText)
        return new Response(
          JSON.stringify({
            error: true,
            code: 'INTERNAL_ERROR',
            message: 'Couldn\'t rewrite. Please try again.'
          }),
          { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
      }
    }

    // Log usage (no message content)
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    )

    // Get user_id from auth context
    const authHeader = req.headers.get('Authorization')
    const token = authHeader?.replace('Bearer ', '')
    let userId = null

    if (token) {
      const { data: { user } } = await supabase.auth.getUser(token)
      userId = user?.id
    }

    // Build log entry (no message content)
    const logEntry: any = {
      user_id: userId,
      relationship_id,
      used_at: new Date().toISOString(),
      core_need_identified: parsed.core_need_identified,
      rewrite_confidence: parsed.rewrite_confidence,
      message_length_original: message.length,
      message_length_rewrite: parsed.rewrite.length,
    }

    try {
      await supabase.from('translator_logs').insert(logEntry)
    } catch (error) {
      // Logging failure doesn't block the response
      console.error('Logging error:', error)
    }

    // Return result
    return new Response(
      JSON.stringify({
        rewrite: parsed.rewrite,
        core_need_identified: parsed.core_need_identified,
        framing_note: parsed.framing_note,
        rewrite_confidence: parsed.rewrite_confidence,
      }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )

  } catch (error) {
    console.error('Error:', error.message)
    return new Response(
      JSON.stringify({
        error: true,
        code: 'INTERNAL_ERROR',
        message: 'Something went wrong. Please try again.'
      }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
```

---

## 6. DATABASE SCHEMA (UPDATED)

### 6.1 Translator logs (no message content stored)

```sql
CREATE TABLE translator_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES auth.users NOT NULL,
  relationship_id uuid REFERENCES relationships NOT NULL,
  used_at timestamptz DEFAULT now(),
  chose_rewrite boolean,                    -- whether user sent the rewrite
  core_need_identified text,                -- feeds into pattern memory
  rewrite_confidence text CHECK (rewrite_confidence IN ('high', 'medium', 'low')),
  message_length_original int,
  message_length_rewrite int
  -- CRITICAL: no message content stored here ever
);

-- RLS: private to the user who submitted
CREATE POLICY "translator_logs_private"
ON translator_logs FOR ALL
USING (auth.uid() = user_id);

-- Indexes
CREATE INDEX idx_translator_logs_user ON translator_logs(user_id);
CREATE INDEX idx_translator_logs_relationship ON translator_logs(relationship_id);
CREATE INDEX idx_translator_logs_created_at ON translator_logs(used_at DESC);
```

---

## 7. EDGE CASES

| Scenario | Behavior |
|----------|----------|
| User has no text in composer | "Help me say this" button disabled |
| User taps "Help me say this" with very short text (< 3 words) | Show: "Your message is short. Try writing a bit more first." |
| User taps "Help me say this" with only emojis | Show: "Try writing what you're feeling in words." |
| Claude API times out (10s) | Show: "Couldn't rewrite. Please try again." — no internal details |
| Claude API returns invalid JSON | Show: "Couldn't rewrite. Please try again." |
| Claude API returns prohibited content | Discard result, show: "Couldn't rewrite. Please try again." |
| User taps "Send mine" | Original message sent. Log `chose_rewrite = false` |
| User taps "Send this" | Rewrite sent. Recipient never knows. Log `chose_rewrite = true` |
| User taps "Edit this" | Rewrite opens in composer for modification. Log `chose_rewrite = true` |
| User dismisses sheet without sending | No log entry created |
| User has no attachment style profile | Prompt uses default values: `attachment_style: 'secure'` |

---

## 8. NOTIFICATIONS

**None.** The Conflict Translator is a private tool. No notifications are sent.

---

## 9. ANALYTICS EVENTS

| Event | Properties |
|-------|------------|
| `translator_used` | `relationship_id, message_length_original, confidence, core_need` |
| `translator_rewrite_sent` | `relationship_id, message_length_rewrite, confidence, core_need` |
| `translator_original_sent` | `relationship_id, message_length_original` |
| `translator_edited` | `relationship_id, edit_count` |
| `translator_timeout` | `relationship_id` |
| `translator_error` | `relationship_id, error_type` |

---

## 10. BUILD ORDER

### Phase 1 — Data Layer
Step 1: Create `translator_logs` table with required `relationship_id`  
Step 2: Add RLS policies  
Step 3: Add indexes  

### Phase 2 — Prompt Design
Step 4: Define prompt template with global constraints  
Step 5: Add core need detection mapping  
Step 6: Add confidence level handling  

### Phase 3 — Edge Function
Step 7: Implement `translate-conflict` edge function (TypeScript)  
Step 8: Implement JSON parsing with fallback  
Step 9: Implement prohibited content filtering  
Step 10: Implement timeout handling (10s)  
Step 11: Implement logging (no message content)  

### Phase 4 — UI (Chat Composer)
Step 12: Add "Help me say this" button in chat composer  
Step 13: Button enabled only when text is present  

### Phase 5 — Translator Sheet
Step 14: Side‑by‑side UI (original + rewrite)  
Step 15: Loading state with subtle animation  
Step 16: Framing note display ("Underlying need: ...")  
Step 17: Three buttons: [Send mine] [Send this] [Edit this]  
Step 18: Equal visual weight for buttons (no pre‑selection)  

### Phase 6 — Edge Cases
Step 19: Empty/short text handling  
Step 20: Low confidence caveat display  
Step 21: Timeout fallback  
Step 22: Prohibited content filtering  

### Phase 7 — Logging
Step 23: Log translator usage (no message content)  
Step 24: Pattern memory integration (after 5+ uses)  

---

## 11. ALGORITHM QUALITY CHECKLIST (ACCEPTANCE CRITERIA)

| # | Criterion | Verification Method |
|---|-----------|---------------------|
| 1.2 | Timeouts for external calls | Test: Claude API timeout → fallback shown, no crash |
| 1.5 | Authentication verified | Test: unauthenticated request → rejected with UNAUTHORIZED |
| 2.1 | Input sanitised | Test: message exceeds length limit? Not applicable (no hard limit) |
| 2.4 | Error messages don't leak | Test: trigger errors → user sees generic message, no stack trace |
| 2.10 | Resources released | Test: sheet dismissed → subscriptions disposed |
| 4.1 | Structured logs | Test: log entry is valid JSON with request_id, user_id, action, timestamp |
| 4.4 | PII excluded from logs | Test: logs contain no message content |
| 5.1 | Actionable error responses | Test: all failure states show user-friendly next step |
| 5.5 | No internal info leaked in UI | Test: generic error messages only |
| 6.1 | Edge cases covered | Test: all edge cases in Section 7 produce defined behaviour |

---

## 12. SOUL DOCUMENT COMPLIANCE

| Principle | Status | Evidence |
|-----------|--------|----------|
| **Pull not push** | ✅ | User must explicitly tap "Help me say this" |
| **Recipient never knows** | ✅ | No label, no indicator, no "polished with Attune" |
| **Private thinking tool** | ✅ | Rewrite is private to sender — no record of original/rewrite stored |
| **Framing note** | ✅ | Private note shown to sender only: "underlying need: to be heard" |
| **Respect user autonomy** | ✅ | User chooses whether to send original or rewrite — equal visual weight |
| **No false warmth** | ✅ | Rewrite preserves sender's actual meaning — never softens a legitimate concern to nothing |
| **No diagnostic language** | ✅ | Rewrite is warm, specific, not clinical |
| **No anxiety by design** | ✅ | No scoring, no pressure |

---

## 13. OPEN QUESTIONS

All resolved.

| Status | Item |
|--------|------|
| ✅ | Pull not push — user explicitly taps "Help me say this" |
| ✅ | Recipient never knows — no label, no indicator |
| ✅ | Framing note — private to sender: "underlying need: to be heard" |
| ✅ | Equal visual weight — neither button pre‑selected |
| ✅ | No message content stored in logs |
| ✅ | Claude timeout — 10 seconds, fallback shown |
| ✅ | Low confidence — caveat displayed |
| ✅ | Pattern memory integration — after 5+ uses |
| ✅ | Claude API — server-side edge function (Master Spec pattern) |
| ✅ | `relationship_id` required for translator logs |
| ✅ | Need-labeling — explicit distinction between canonical label and natural-language paraphrase |

---

*This spec is ready for implementation.*  
*Build in the exact order defined in Section 10.*  
*Review against ATTUNE_SOUL.md before shipping.*  
*Run algorithm quality checklist before merge.*  
*Last reviewed: July 2026*

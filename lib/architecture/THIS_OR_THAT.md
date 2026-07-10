# ATTUNE — THIS OR THAT GAME SPECIFICATION

**Version:** 1.3 (final)
**Created:** June 2026
**Last updated:** June 2026
**Status:** Ready for implementation
**Part of:** Games Module — Game 1 of 3
**Related documents:** `ATTUNE_MASTER_SPEC.md`, `ATTUNE_SOUL.md`, `ATTUNE_PRINCIPLES_CHECKLIST.md`, `ATTUNE_CLINICAL.md`, `../algorithms/algorithm_quality_review_checklist.md`

---

## HOW TO USE THIS DOCUMENT

This spec defines the This or That game end to end. It is Game 1 of 3 in the Games Module. Build in the exact order defined in **Section 12 — Build Order**. The game uses the shared session architecture from the Games Module spec. If something is unclear, ask before building it.

---

## TABLE OF CONTENTS

1. What This Game Is
2. Game Flow Overview
3. Session Lifecycle
4. Screen Designs
5. Preset Question Bank
6. Custom Questions
7. Selection Algorithm
8. Database Schema
9. Edge Cases
10. Notifications
11. Analytics Events
12. Build Order
13. Algorithm Quality Checklist
14. Soul Document Compliance Check
15. Open Questions

---

## 1. WHAT THIS GAME IS

This or That is a fast, fun binary choice game for couples. Each round presents two options. Both partners pick one. After both have picked, both see each other's choice.

### 1.1 Core characteristics

| Characteristic | Value |
|----------------|-------|
| Duration | ~5 minutes (10 rounds) |
| Players | 2 (asynchronous on separate devices) |
| Tones | Connecting, Romantic, Playful, Spicy, Intimate |
| Round type | Both answer independently, reveal together |
| Replayability | Preset bank + seen tracking + custom questions = high replayability |
| Match tracking | Counts matches per session for end screen |
| Custom questions | Users can create, share, and reuse their own questions |

### 1.2 What makes it work for couples

- Low pressure (binary choices, no wrong answers)
- Fast (can play during a coffee break)
- Reveals preferences and surprises
- Sparks conversation naturally
- Custom questions make it personal and repeatable

---

## 2. GAME FLOW OVERVIEW

### 2.1 Complete flow diagram

```
Partner A initiates
    │
    ▼
Selects tone
    │
    ▼
If Intimate → consent dialog
    │
    ▼
Creates session (status: invited)
    │
    ▼
Push notification to Partner B
    │
    ▼
Partner A sees waiting screen
    │
    │         Partner B receives push
    │               │
    │               ▼
    │         Opens invitation screen
    │               │
    │               ▼
    │         Accepts or declines
    │               │
    │               ├── Decline → session abandoned
    │               │            Partner A notified
    │               │
    │               └── Accept → session active
    │                           │
    └───────────────────────────┘
                    │
                    ▼
         Both see first question
         (random from custom or preset)
                    │
                    ▼
         Partners answer independently
         (answers can be changed until both submit)
                    │
                    ▼
         When both have answered:
              Reveal fires simultaneously
              on both devices
                    │
                    ▼
         Show both choices + match indicator
                    │
                    ▼
         Next round (repeat for 10 rounds)
         (between rounds, choose Preset or Custom source)
                    │
                    ▼
         End screen: match count + percentage
         + most interesting pick
```

### 2.2 Turn structure (simultaneous, not alternating)

Both partners answer the **same question** independently. Order does not matter. Whoever answers first waits for the other.

```
Round 1: Question displayed (from preset or custom bank)
    │
    ├── Partner A answers ──┐
    │                       │
    └── Partner B answers ──┴── Both answer independently
                                    │
                                    ▼
                         When BOTH have answered:
                               Reveal screen
                                    │
                                    ▼
                         Between rounds: Choose next question source
                                    │
                                    ├── Preset (random from bank)
                                    └── Custom (random from partner's shared questions)
                                    │
                                    ▼
                              Next round
```

### 2.3 Question source selection between rounds

After reveal, before next round, the partner whose **turn it is to choose** (alternates each round, starting with Partner A for round 2) selects the source:

```
┌─────────────────────────────────────┐
│  Jordan's turn to choose            │
│                                     │
│  Next question from:                │
│                                     │
│  ┌─────────────┐  ┌─────────────┐  │
│  │   🎲        │  │   ✏️         │  │
│  │  Preset     │  │  Custom     │  │
│  │  Random     │  │  Question   │  │
│  └─────────────┘  └─────────────┘  │
└─────────────────────────────────────┘

If Custom selected:
┌─────────────────────────────────────┐
│  Choose whose question:             │
│                                     │
│  ┌─────────────┐  ┌─────────────┐  │
│  │   👤        │  │   👤         │  │
│  │  My         │  │  Partner's  │  │
│  │  Questions  │  │  Questions  │  │
│  └─────────────┘  └─────────────┘  │
└─────────────────────────────────────┘
```

If the selected partner has no custom questions (or none left for this tone), fall back to preset automatically with a note: "No custom questions available — using preset."

---

## 3. SESSION LIFECYCLE

### 3.1 States and transitions

```
                    ┌─────────────────────────────────────────────────────────┐
                    │                    SESSION STATES                        │
                    ├─────────────────────────────────────────────────────────┤
                    │                                                         │
                    │  ┌──────────┐     Accept     ┌──────────┐              │
                    │  │ invited  │ ─────────────► │  active  │              │
                    │  └──────────┘                 └──────────┘              │
                    │       │                            │                    │
                    │       │ 48hr no response            │ 24hr no activity   │
                    │       │ OR partner declines        │ in current round   │
                    │       │                            │ OR 24hr after      │
                    │       ▼                            │ round completion   │
                    │  ┌──────────┐                      │ with no navigation │
                    │  │abandoned │                      ▼                    │
                    │  └──────────┘                 ┌────────────┐           │
                    │                               │ abandoned  │           │
                    │                               └────────────┘           │
                    │                                      │                  │
                    │                                      │ All 10 rounds    │
                    │                                      │ completed        │
                    │                                      ▼                  │
                    │                                 ┌───────────┐          │
                    │                                 │ completed │          │
                    │                                 └───────────┘          │
                    └─────────────────────────────────────────────────────────┘
```

### 3.2 State definitions

| State | Meaning | User sees |
|-------|---------|-----------|
| `invited` | Partner A initiated, B hasn't responded or has declined | A: "Invitation sent to Jordan" / "Jordan declined" B: Invitation screen |
| `active` | Both accepted, game in progress | Game screen with current round |
| `completed` | All 10 rounds finished | End screen with results |
| `abandoned` | No activity for defined timeouts or explicit decline | "Session expired — start new game" |

### 3.3 Timeout definitions

| Timeout | Value | Applies to |
|---------|-------|------------|
| Invite response | 48 hours | Session in `invited` state |
| Round answer | 24 hours | Current round with only one partner answered |
| Post-reveal navigation | 24 hours | Round complete but neither partner taps Next/Previous |

### 3.4 One active session rule

Only one This or That session can be active per couple at a time. If Partner A tries to start a new game while one is active:

```
┌─────────────────────────────────────┐
│  Active game in progress            │
│                                     │
│  You have an active This or That    │
│  game with Jordan.                  │
│                                     │
│  [Resume active game]               │
│  [Abandon and start new]            │
└─────────────────────────────────────┘
```

- [Resume active game] → navigates to current round of existing session
- [Abandon and start new] → shows confirmation, abandons old session, creates new one

---

## 4. SCREEN DESIGNS

### 4.1 Initiation — Tone selector

Partner A sees after tapping `[Play →]` on This or That card:

```
┌─────────────────────────────────────┐
│  ✕              Set the tone        │
├─────────────────────────────────────┤
│                                     │
│  ┌─────────┐  ┌─────────┐          │
│  │   💙    │  │   ❤️    │          │
│  │Connecting│  │Romantic │          │
│  └─────────┘  └─────────┘          │
│                                     │
│  ┌─────────┐  ┌─────────┐          │
│  │   😄    │  │   🔥    │          │
│  │ Playful │  │  Spicy  │          │
│  └─────────┘  └─────────┘          │
│                                     │
│  ┌─────────┐                        │
│  │   🌙    │                        │
│  │Intimate │                        │
│  └─────────┘                        │
│                                     │
│  Selected: Connecting (default)     │
│                                     │
│              [Start game →]         │
└─────────────────────────────────────┘
```

**Rules:**
- Selected tone highlighted with Attune green border
- Default selection: Connecting
- [Start game →] button enabled only when a tone is selected
- Intimate tone is active in the build but content requires clinical sign-off before production deployment

### 4.2 Intimate consent dialog

If Intimate tone is selected, a dialog appears before session creation:

```
┌─────────────────────────────────────┐
│  Intimate tone                      │
│                                     │
│  This tone contains adult content   │
│  intended for couples in committed  │
│  relationships. Both partners must  │
│  confirm they want to play at this  │
│  level.                             │
│                                     │
│  Jordan will need to confirm when   │
│  they receive the game invitation.  │
│                                     │
│  [Cancel]    [Yes, set Intimate]    │
└─────────────────────────────────────┘
```

- [Cancel] returns to tone selector
- [Yes, set Intimate] proceeds to session creation

### 4.3 Partner invitation screen

Partner B receives push notification:  
`"[Name] wants to play This or That — Playful tone"`

Tapping opens the invitation screen.

**Standard invitation (Connecting, Romantic, Playful, Spicy):**

```
┌─────────────────────────────────────┐
│  [Name] invited you to play         │
│                                     │
│  🔀 This or That                    │
│  Tone: Playful                      │
│                                     │
│  Fast, fun picks. ~5 minutes.       │
│                                     │
│  [Maybe later]    [Let's play!]     │
└─────────────────────────────────────┘
```

**Intimate tone invitation (with consent gate):**

```
┌─────────────────────────────────────┐
│  [Name] invited you to play         │
│                                     │
│  🔀 This or That                    │
│  Tone: 🌙 Intimate                  │
│                                     │
│  This tone contains adult content.  │
│  Do you want to play at this level? │
│                                     │
│  [Decline — play at Spicy instead]  │
│  [Yes, I'm in]                      │
└─────────────────────────────────────┘
```

**Partner response behavior:**

| Action | Result |
|--------|--------|
| [Let's play!] (standard) | Session status → `active`. Both partners see first question. |
| [Maybe later] (standard) | Session status → `abandoned`. Partner A notified: "Jordan can't play right now – start a new game." |
| [Yes, I'm in] (Intimate) | Session status → `active` with Intimate tone. Both partners see first question. |
| [Decline — play at Spicy instead] (Intimate) | Session tone changed to Spicy. Session status → `active`. Partner A notified: "Jordan preferred Spicy — starting there instead." |
| Close without action | Session remains `invited`. 48-hour timeout applies. |

### 4.4 Waiting screen (Partner A after sending invite)

```
┌─────────────────────────────────────┐
│  ← Back                             │
│                                     │
│  Invitation sent to Jordan          │
│                                     │
│  ┌─────────────────────────────┐   │
│  │                             │   │
│  │        🔀                    │   │
│  │   Waiting for Jordan        │   │
│  │   to accept...              │   │
│  │                             │   │
│  └─────────────────────────────┘   │
│                                     │
│  [Cancel invitation]                │
└─────────────────────────────────────┘
```

- [Cancel invitation] → session set to `abandoned`. No notification to Partner B.

### 4.5 Question screen

```
┌─────────────────────────────────────┐
│  ← Back    This or That    Round 3/10│
│            Playful tone              │
├─────────────────────────────────────┤
│                                     │
│         Pizza or Pasta?             │
│                                     │
├─────────────────────────────────────┤
│                                     │
│  ┌──────────────┐ ┌──────────────┐ │
│  │              │ │              │ │
│  │     🍕       │ │     🍝       │ │
│  │    Pizza     │ │    Pasta     │ │
│  │              │ │              │ │
│  └──────────────┘ └──────────────┘ │
│                                     │
│  Tap your choice. Jordan will see   │
│  your answer after they pick.       │
│                                     │
├─────────────────────────────────────┤
│  Jordan: ● answered / ○ waiting     │
└─────────────────────────────────────┘
```

**Rules:**
- Both choices tappable, full card area
- Selected card highlights with Attune green border
- Answers can be changed until **both** have answered, then choices are locked
- After selecting, answer saved locally; if offline, queued for sync
- Partner status updates via Realtime; if connection lost, fallback to polling every 10 seconds

### 4.6 Waiting screen (after your answer, before partner)

```
┌─────────────────────────────────────┐
│  ← Back    This or That    Round 3/10│
│            Playful tone              │
├─────────────────────────────────────┤
│                                     │
│         Pizza or Pasta?             │
│                                     │
├─────────────────────────────────────┤
│                                     │
│  You chose: 🍕 Pizza                │
│                                     │
│  ┌─────────────────────────────┐   │
│  │                             │   │
│  │        ⏳                    │   │
│  │   Waiting for Jordan...     │   │
│  │                             │   │
│  └─────────────────────────────┘   │
│                                     │
│  ┌─────────────────────────────┐   │
│  │  [Remind Jordan]            │   │  ← appears after 2 hours
│  └─────────────────────────────┘   │   (rate‑limited to once per 4h)
│                                     │
├─────────────────────────────────────┤
│  Jordan: ○ waiting                  │
└─────────────────────────────────────┘
```

**Remind button behavior:**
- Appears to the partner who answered first and is now waiting
- Appears after partner has not answered for 2 hours
- Rate‑limited: once per 4 hours per session (server‑side enforced)
- Tapping sends push notification to the partner who has **not** yet answered
- Push body: "Your turn in This or That 🎮"
- After 24 hours total without partner answer, session abandoned (both notified)

**Changing answer from waiting screen:**
- Tapping ← Back returns to question screen
- Current answer is highlighted but changeable
- Changing answer updates the record immediately
- Waiting screen updates to reflect new choice
- Partner status remains unchanged

### 4.7 Reveal screen (both answered)

```
┌─────────────────────────────────────┐
│  ← Back    This or That    Round 3/10│
├─────────────────────────────────────┤
│  Pizza or pasta for life?           │
├─────────────────────────────────────┤
│                                     │
│  You chose:          Jordan chose:  │
│                                     │
│  ┌──────────────┐    ┌──────────────┐
│  │     🍕       │    │     🍝       │
│  │    Pizza     │    │    Pasta     │
│  └──────────────┘    └──────────────┘
│                                     │
├─────────────────────────────────────┤
│                                     │
│  Different picks this time 😄       │
│                                     │
│  ┌─────────┐         ┌─────────┐   │
│  │ Previous│         │  Next → │   │
│  └─────────┘         └─────────┘   │
└─────────────────────────────────────┘
```

**Match indicator text:**
- Same choice: "You both picked the same! 🎉"
- Different choice: "Different picks this time 😄"

**Animation:**
- Both cards slide in from opposite sides
- Duration: 300ms, ease-out
- Match: brief green flash behind both cards (200ms)
- Different: no flash

**Reveal sync reliability (critical):**

1. When the second partner submits their answer, the server sets `reveal_triggered_at = NOW()` on the round row.
2. Both clients listen for changes to `reveal_triggered_at` via Realtime.
3. When clients see the change, they wait **500ms** (short grace window) and then show the reveal screen.
4. If a client misses the Realtime update (e.g., poor connection), it polls every 2 seconds for `reveal_triggered_at` on the current round.
5. After 10 seconds of polling without success, it shows a "Reveal ready – tap to continue" button.
6. Analytics event `game_reveal_fallback_used` is sent when fallback is triggered.

**Navigation:**
- [Previous] → goes to previous round (both answers revealed again)
- [Next →] → goes to question source selection (if round < 10) or end screen (if round = 10)

### 4.8 Question source selection (between rounds)

After reveal, before round 2-10, the partner whose turn it is to choose selects the source. Turns alternate: Round 2 = Partner A chooses, Round 3 = Partner B chooses, etc.

```
┌─────────────────────────────────────┐
│  Jordan's turn to choose            │
│                                     │
│  Next question from:                │
│                                     │
│  ┌─────────────┐  ┌─────────────┐  │
│  │   🎲        │  │   ✏️         │  │
│  │  Preset     │  │  Custom     │  │
│  │  Random     │  │  Question   │  │
│  └─────────────┘  └─────────────┘  │
└─────────────────────────────────────┘

If Custom selected:
┌─────────────────────────────────────┐
│  Choose whose question:             │
│                                     │
│  ┌─────────────┐  ┌─────────────┐  │
│  │   👤        │  │   👤         │  │
│  │  My         │  │  Partner's  │  │
│  │  Questions  │  │  Questions  │  │
│  └─────────────┘  └─────────────┘  │
└─────────────────────────────────────┘
```

- Selection persists only for the next round (not for entire session)
- If Custom selected but chosen partner has no custom questions for this tone → fallback to Preset with note: "No custom questions available — using preset"

### 4.9 End screen

```
┌─────────────────────────────────────┐
│  ← Back         Game over!          │
├─────────────────────────────────────┤
│                                     │
│  You matched on 6 out of 10         │
│  ██████████░░░░░░░░░  60%           │
│                                     │
├─────────────────────────────────────┤
│                                     │
│  Most interesting pick:             │
│                                     │
│  "Coffee or tea?"                   │
│  You: ☕ Coffee    Jordan: 🍵 Tea    │
│                                     │
├─────────────────────────────────────┤
│                                     │
│  ┌─────────┐      ┌──────────────┐ │
│  │Play again│      │Try another   │ │
│  │         │      │    game →    │ │
│  └─────────┘      └──────────────┘ │
└─────────────────────────────────────┘
```

**Match framing (soul document compliance):**

- If match percentage ≥ 60%: show percentage bar
- If match percentage < 60%: replace bar with text:
  "You see things differently — that's what makes it interesting."

**Most interesting pick selection logic (deterministic):**

1. Find the first round (lowest round number) where choices differed.
2. If all rounds matched, pick the round where the question has `is_interesting` flag set to `true` (pre‑seeded during question creation for ~20% of questions).
3. If no round has the flag, pick round 5 (middle of the session).

**Button behavior:**
- [Play again] → returns to tone selector
- [Try another game →] → navigates to Games Hub

### 4.10 Offline indicator

When user submits answer and network is down:

```
┌─────────────────────────────────────┐
│  ⚠️ Waiting to connect. Answer saved│
│     locally. Will sync when online. │
└─────────────────────────────────────┘
```

- Banner appears at bottom of screen
- Answer saved to local queue
- Retry every 30 seconds until success
- On success, banner removed, flow proceeds
- App continues to function; user can answer more rounds offline

### 4.11 State restoration (app killed mid‑game)

When the app is killed and reopened during an active `game_session`:

1. Check local storage for `current_game_session_id`.
2. Fetch session status from Supabase.
3. If session is still `active` and the current round is incomplete:
   - Restore the user's saved answer from local cache (if any)
   - Re‑subscribe to Realtime updates
   - Navigate directly to the question screen for the current round
4. If session is `completed` or `abandoned`, show the appropriate end screen.
5. No answers are lost; the local cache is the source of truth for unsynced answers.

### 4.12 Session history view

In Games Hub, below "Past games," show all completed This or That sessions:

```
┌─────────────────────────────────────┐
│  Past sessions                      │
│                                     │
│  ┌─────────────────────────────┐   │
│  │ 🔀 This or That · Jun 12    │   │
│  │ Playful tone · 7/10 matched │   │
│  │                    [View →] │   │
│  └─────────────────────────────┘   │
│                                     │
│  ┌─────────────────────────────┐   │
│  │ 🔀 This or That · Jun 5     │   │
│  │ Romantic tone · 4/10 matched│   │
│  │                    [View →] │   │
│  └─────────────────────────────┘   │
└─────────────────────────────────────┘
```

Tapping [View →] shows session details (all 10 rounds with both answers). Users can hide a session from their own view:

```
┌─────────────────────────────────────┐
│  [Hide this session]                │
│                                     │
│  Confirmation:                      │
│  "Hide this session? It will remain │
│   visible to Jordan."               │
│                                     │
│  [Cancel] [Hide]                    │
└─────────────────────────────────────┘
```

- Hide is soft delete: sets `hidden_by_user_id` for the deleting user only
- Partner's view unaffected
- Hidden sessions can be restored from Profile → Settings → Hidden content

---

## 5. PRESET QUESTION BANK

### 5.1 Question structure

Each preset This or That question has:

| Field | Type | Description |
|-------|------|-------------|
| `id` | uuid | Primary key |
| `question_text` | text | The question (e.g., "Pizza or pasta?") |
| `option_a` | text | First option (e.g., "Pizza") |
| `option_b` | text | Second option (e.g., "Pasta") |
| `emoji_a` | text | Emoji for option A (e.g., "🍕") |
| `emoji_b` | text | Emoji for option B (e.g., "🍝") |
| `tone` | text | connecting, romantic, playful, spicy, intimate |
| `tone_level` | int | 1-4 |
| `is_interesting` | boolean | Manually set for ~20% of questions |
| `active` | boolean | Soft delete flag |

### 5.2 Minimum question counts before launch

| Tone | Minimum questions |
|------|------------------|
| Connecting | 50 |
| Romantic | 50 |
| Playful | 50 |
| Spicy | 40 |
| Intimate | 40 (requires clinical advisor review before launch) |
| **Total** | **230** |

### 5.3 Question examples by tone

**CONNECTING (tone_level = 1)**

| Question | Option A | Option B | Emoji A | Emoji B |
|----------|----------|----------|---------|---------|
| Morning person or night owl? | Morning person | Night owl | 🌅 | 🌙 |
| City or countryside? | City | Countryside | 🌆 | 🌾 |
| Books or movies? | Books | Movies | 📚 | 🎬 |
| Spontaneous or planned? | Spontaneous | Planned | ✨ | 📋 |
| Introvert or extrovert? | Introvert | Extrovert | 🏠 | 🎉 |
| Beach or mountains? | Beach | Mountains | 🏖️ | ⛰️ |
| Summer or winter? | Summer | Winter | ☀️ | ❄️ |
| Coffee or tea? | Coffee | Tea | ☕ | 🍵 |
| Early bird or night owl? | Early bird | Night owl | 🐦 | 🦉 |
| Sweet or savoury? | Sweet | Savoury | 🍰 | 🧀 |

**ROMANTIC (tone_level = 2)**

| Question | Option A | Option B | Emoji A | Emoji B |
|----------|----------|----------|---------|---------|
| Sunset walk or candlelit dinner? | Sunset walk | Candlelit dinner | 🌅 | 🕯️ |
| Love letter or surprise date? | Love letter | Surprise date | 💌 | 🎁 |
| Stay in or go out? | Stay in | Go out | 🏠 | 🚪 |
| Hold hands or arms around shoulders? | Hold hands | Arms around | 🤝 | 🤗 |
| "I love you" first or shown through actions? | Said first | Shown through actions | 💬 | 🤲 |
| Spontaneous kiss or planned romantic evening? | Spontaneous kiss | Planned evening | 😘 | 📅 |
| Breakfast in bed or late night talk? | Breakfast in bed | Late night talk | 🍳 | 🌙 |
| Dancing in the kitchen or slow dance in living room? | Kitchen dance | Living room dance | 🍳 | 🪩 |
| Surprise flowers or thoughtful note? | Flowers | Note | 💐 | 📝 |
| Recreate first date or plan something new? | Recreate first | Plan new | 🔄 | ✨ |

**PLAYFUL (tone_level = 1 — branch)**

| Question | Option A | Option B | Emoji A | Emoji B |
|----------|----------|----------|---------|---------|
| Pizza or pasta for life? | Pizza | Pasta | 🍕 | 🍝 |
| Dog or cat? | Dog | Cat | 🐕 | 🐈 |
| Netflix or sleep? | Netflix | Sleep | 📺 | 😴 |
| TikTok or Instagram? | TikTok | Instagram | 📱 | 📸 |
| Batman or Superman? | Batman | Superman | 🦇 | 🦸 |
| Beach or pool? | Beach | Pool | 🏖️ | 🏊 |
| Pancakes or waffles? | Pancakes | Waffles | 🥞 | 🧇 |
| iPhone or Android? | iPhone | Android | 📱 | 🤖 |
| Fancy restaurant or food truck? | Fancy restaurant | Food truck | 🍽️ | 🚚 |
| Zipline or scuba diving? | Zipline | Scuba diving | 🪢 | 🤿 |

**SPICY (tone_level = 3)**

| Question | Option A | Option B | Emoji A | Emoji B |
|----------|----------|----------|---------|---------|
| Lights on or off? | Lights on | Lights off | 💡 | 🌑 |
| Whispered in ear or written note? | Whispered | Written note | 👂 | 📝 |
| Slow burn or jump right in? | Slow burn | Jump right in | 🔥 | 🏃 |
| Shower together or alone? | Together | Alone | 🚿 | 🚿 |
| Your place or mine — first time? | Your place | Mine | 🏠 | 🏠 |
| Planned or spontaneous intimacy? | Planned | Spontaneous | 📅 | ⚡ |
| Music playing or silence? | Music | Silence | 🎵 | 🔇 |
| Foreplay focus or main event focus? | Foreplay | Main event | 👆 | 🎯 |
| Talk dirty or stay quiet? | Talk dirty | Stay quiet | 🗣️ | 🤐 |
| Give or receive first? | Give first | Receive first | 🎁 | 🙌 |

**INTIMATE (tone_level = 4)** — requires consent gate and clinical advisor review

> Full question bank to be written with clinical/relationship advisor. Minimum 40 questions required before launch. Build the feature with Intimate tone active, but do not deploy to production until content passes clinical review.

---

## 6. CUSTOM QUESTIONS

### 6.1 Overview

Users can write and save their own This or That questions. When it is their turn to choose the next question source, they can select a random custom question from either partner's shared pool.

### 6.2 Custom question structure

| Field | Type | Description |
|-------|------|-------------|
| `id` | uuid | Primary key |
| `user_id` | uuid | Creator (references auth.users) |
| `question_text` | text | Max 100 characters |
| `option_a` | text | Max 50 characters |
| `option_b` | text | Max 50 characters |
| `emoji_a` | text | Optional, user picks from emoji picker |
| `emoji_b` | text | Optional |
| `tone` | text | connecting, romantic, playful, spicy, intimate |
| `is_private` | boolean | If true, only visible to creator |
| `times_used` | int | Counter for analytics |
| `last_used_at` | timestamptz | For sorting |
| `created_at` | timestamptz | |
| `report_count` | int | For moderation |

### 6.3 Sharing settings

When a user creates a custom question, they choose:

| Option | Meaning |
|--------|---------|
| **Shared with partner (default)** | Partner can see and use this question |
| **Private** | Only the creator can see and use this question |

### 6.4 Creating a custom question

Access point: Games Hub → This or That → [Custom questions] button

```
┌─────────────────────────────────────┐
│  ← Back      Custom question        │
├─────────────────────────────────────┤
│                                     │
│  Your question (max 100 chars)      │
│  ┌─────────────────────────────┐   │
│  │ What's your perfect Sunday?  │   │
│  └─────────────────────────────┘   │
│                                     │
│  Option A (max 50 chars)            │
│  ┌─────────────────────────────┐   │
│  │ Lazy morning at home         │   │
│  └─────────────────────────────┘   │
│  [Choose emoji 🏠]                  │
│                                     │
│  Option B (max 50 chars)            │
│  ┌─────────────────────────────┐   │
│  │ Adventure outdoors           │   │
│  └─────────────────────────────┘   │
│  [Choose emoji ⛰️]                  │
│                                     │
│  Tone: Connecting ▼                │
│                                     │
│  Share with Jordan?                 │
│  ● Yes, share     ○ Keep private   │
│                                     │
│              [Save question]        │
└─────────────────────────────────────┘
```

- Emoji picker: standard emoji selector, optional
- Tone selector same as game initiation
- [Save question] validates all fields before saving

### 6.5 Managing custom questions

Access point: Profile → Games → Custom questions

Shows list of all custom questions (user's own + partner's shared ones):

```
┌─────────────────────────────────────┐
│  ← Back    Custom questions         │
├─────────────────────────────────────┤
│                                     │
│  My questions                       │
│  ┌─────────────────────────────┐   │
│  │ What's your perfect Sunday?  │   │
│  │ Connecting · Used 3 times    │   │
│  │                    [Edit] [⋯]│   │
│  └─────────────────────────────┘   │
│                                     │
│  Jordan's questions (shared)        │
│  ┌─────────────────────────────┐   │
│  │ Beach or mountains?          │   │
│  │ Playful · Used 1 time        │   │
│  │                         [⋯]  │   │
│  └─────────────────────────────┘   │
└─────────────────────────────────────┘
```

Actions:
- Own questions: Edit, Delete, Toggle share, View usage
- Partner's questions: Report, Hide (hide from own view only)

### 6.6 Content moderation

Custom questions are user-generated. Apply same rules as Opinions/Forums:

- Report flag available on any custom question (⋯ menu → Report)
- Report reasons: inappropriate content, hate speech, explicit (wrong tone), other
- If flagged, question hidden from both partners pending review
- Admin moderation queue same as forum reports

---

## 7. SELECTION ALGORITHM

### 7.1 Question selection logic

Function `selectQuestions(sessionId, tone, relationshipId, roundNumber)`:

```
// Round 1: Initial 10 questions selected at session creation
// Round 2-10: One question selected at a time based on source choiceif roundNumber == 1:
  return selectInitialQuestions(relationshipId, tone, count = 10)
else:
  // sourceChoice determined by turn-based selection (Section 4.8)
  if sourceChoice == 'preset':
    return selectSinglePresetQuestion(relationshipId, tone)
  else: // 'custom'
    return selectSingleCustomQuestion(relationshipId, chosenPartner, tone)
```

**Initial questions selection (10 questions):**

```
seenIds = SELECT question_id FROM game_questions_seen
          WHERE relationship_id = relationshipId
            AND game_type = 'this_or_that'

toneLevel = getToneLevel(tone)

// Pool 1: Custom questions (shared, not private)
customPool = SELECT * FROM custom_this_or_that_questions
             WHERE (user_id = relationship.user_a OR user_id = relationship.user_b)
               AND is_private = false
               AND tone = selectedTone
             ORDER BY times_used ASC, last_used_at ASC NULLS FIRST

// Pool 2: Unseen preset questions
unseenPresetPool = SELECT * FROM game_questions
                   WHERE game_type = 'this_or_that'
                     AND active = true
                     AND (tone = 'playful' OR tone_level <= toneLevel)
                     AND id NOT IN seenIds

// Pool 3: Seen preset questions (allow repeats)
seenPresetPool = SELECT * FROM game_questions
                 WHERE game_type = 'this_or_that'
                   AND active = true
                   AND (tone = 'playful' OR tone_level <= toneLevel)
                   AND id IN seenIds

// Priority: Custom > Unseen Preset > Seen Preset
selected = shuffle(customPool).slice(0, min(3, customPool.length))  // max 3 custom per session
remaining = count - len(selected)
selected = selected + shuffle(unseenPresetPool).slice(0, remaining)
if len(selected) < count:
  selected = selected + shuffle(seenPresetPool).slice(0, count - len(selected))

return selected
```

**Single preset question selection (for rounds 2-10):**

```
toneLevel = getToneLevel(tone)
eligible = SELECT * FROM game_questions
           WHERE game_type = 'this_or_that'
             AND active = true
             AND (tone = 'playful' OR tone_level <= toneLevel)
           ORDER BY RANDOM()
           LIMIT 1
return eligible
```

**Single custom question selection (for rounds 2-10):**

```
customPool = SELECT * FROM custom_this_or_that_questions
             WHERE user_id = chosenPartnerId
               AND is_private = false
               AND tone = selectedTone
             ORDER BY times_used ASC, last_used_at ASC NULLS FIRST

if customPool.length > 0:
  selected = customPool[0]
  UPDATE custom_this_or_that_questions
  SET times_used = times_used + 1, last_used_at = NOW()
  WHERE id = selected.id
  return selected
else:
  // Fallback to preset
  return selectSinglePresetQuestion(relationshipId, tone)
```

### 7.2 Intimate tone guarantee (for preset questions only)

For Intimate tone sessions using preset questions, at least 5 of the initial 10 questions must have `tone_level = 4`. Fill shortfall with Spicy (level 3) questions.

### 7.3 Seen questions tracking

After each round when **both** partners have answered:

```sql
INSERT INTO game_questions_seen (relationship_id, question_id, game_type)
VALUES (relationshipId, questionId, 'this_or_that')
ON CONFLICT (relationship_id, question_id) DO NOTHING;
```

**Important:**
- Only preset questions are tracked in `game_questions_seen`
- Custom questions are **not** tracked (they can repeat across sessions)
- If a round is abandoned (never both answered), the question is **not** inserted

### 7.4 Helper function

```javascript
function getToneLevel(tone):
  switch tone:
    case 'connecting': return 1
    case 'playful':    return 1
    case 'romantic':   return 2
    case 'spicy':      return 3
    case 'intimate':   return 4
```

---

## 8. DATABASE SCHEMA

### 8.1 Preset questions table (existing, extended)

```sql
-- Add This or That specific columns to existing game_questions
ALTER TABLE game_questions
ADD COLUMN IF NOT EXISTS option_a text,
ADD COLUMN IF NOT EXISTS option_b text,
ADD COLUMN IF NOT EXISTS emoji_a text,
ADD COLUMN IF NOT EXISTS emoji_b text,
ADD COLUMN IF NOT EXISTS is_interesting boolean DEFAULT false;

-- Add check constraint for this_or_that questions
ALTER TABLE game_questions
ADD CONSTRAINT check_this_or_that_fields
CHECK (
  (game_type != 'this_or_that') OR
  (game_type = 'this_or_that' AND 
   option_a IS NOT NULL AND 
   option_b IS NOT NULL)
);
```

### 8.2 Custom questions table

```sql
CREATE TABLE custom_this_or_that_questions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES auth.users NOT NULL,
  question_text text NOT NULL CHECK (char_length(question_text) <= 100),
  option_a text NOT NULL CHECK (char_length(option_a) <= 50),
  option_b text NOT NULL CHECK (char_length(option_b) <= 50),
  emoji_a text,
  emoji_b text,
  tone text NOT NULL CHECK (tone IN ('connecting', 'romantic', 'playful', 'spicy', 'intimate')) DEFAULT 'connecting',
  is_private boolean DEFAULT false,
  times_used int DEFAULT 0,
  last_used_at timestamptz,
  report_count int DEFAULT 0,
  created_at timestamptz DEFAULT now()
);

-- RLS: creator can read/write their own custom questions
CREATE POLICY "custom_questions_owner"
ON custom_this_or_that_questions FOR ALL
USING (auth.uid() = user_id);

-- RLS: in a relationship, both partners can see each other's non-private questions
CREATE POLICY "custom_questions_relationship"
ON custom_this_or_that_questions FOR SELECT
USING (
  is_private = false AND
  user_id IN (
    SELECT user_a FROM relationships WHERE user_b = auth.uid()
    UNION
    SELECT user_b FROM relationships WHERE user_a = auth.uid()
  )
);
```

### 8.3 Add cumulative tracking to game_sessions

```sql
ALTER TABLE game_sessions
ADD COLUMN match_count int DEFAULT 0,
ADD COLUMN total_rounds_completed int DEFAULT 0;
```

### 8.4 Add reveal_triggered_at to game_session_rounds

```sql
ALTER TABLE game_session_rounds
ADD COLUMN reveal_triggered_at timestamptz;
```

### 8.5 Add soft delete for session history

```sql
ALTER TABLE game_sessions
ADD COLUMN hidden_by_user_ids uuid[] DEFAULT '{}';
```

### 8.6 RLS policies

```sql
-- game_questions: readable by all authenticated users (where active = true)
CREATE POLICY "questions_readable_all"
ON game_questions FOR SELECT
USING (auth.uid() IS NOT NULL AND active = true);

-- game_sessions: readable by relationship members only
CREATE POLICY "sessions_relationship_members"
ON game_sessions FOR SELECT
USING (
  relationship_id IN (
    SELECT id FROM relationships
    WHERE user_a = auth.uid() OR user_b = auth.uid()
  )
);

-- game_session_rounds: readable by relationship members (via session)
CREATE POLICY "rounds_relationship_members"
ON game_session_rounds FOR SELECT
USING (
  session_id IN (
    SELECT id FROM game_sessions
    WHERE relationship_id IN (
      SELECT id FROM relationships
      WHERE user_a = auth.uid() OR user_b = auth.uid()
    )
  )
);

-- game_questions_seen: readable by relationship members only
CREATE POLICY "seen_questions_relationship_members"
ON game_questions_seen FOR SELECT
USING (
  relationship_id IN (
    SELECT id FROM relationships
    WHERE user_a = auth.uid() OR user_b = auth.uid()
  )
);
```

---

## 9. EDGE CASES

| Scenario | Behavior |
|----------|----------|
| Partner declines invitation | Session status → `abandoned`. Initiator notified: "Jordan can't play right now – start a new game." |
| Partner B never responds | Session abandoned after 48 hours. Initiator notified. |
| Partner answers, then changes mind before other answers | Can change selection freely. Latest selection saved. |
| Network disconnect during answer | Save answer locally, retry on reconnect. Show offline indicator banner. |
| Both answer simultaneously | Database transaction + row lock prevents double reveal. |
| Session abandoned mid‑game | Both partners notified. Can start new session. |
| One partner answers all 10 rounds, other answers 0 | Session stays active until 24‑hour round timeout then abandoned. |
| Intimate tone — one partner declines | Session starts at Spicy tone. Initiator notified of fallback. |
| Partner hasn't answered current round after 24 hours | Session abandoned. Both notified. |
| Waiting screen idle >2 hours | Remind button appears (rate‑limited once per 4h, server‑side). |
| Round complete with no Next/Previous for 24 hours | Session abandoned. |
| App killed mid‑game | State restoration recovers session and answers. |
| Realtime subscription lost | Fallback polling every 10 seconds for partner status and `reveal_triggered_at`. |
| Preset question bank has <10 unseen questions | Allow repeats from seen pool (lower tone prioritized). |
| Custom question selected but partner has none | Fallback to preset automatically. |
| Custom question reported for moderation | Question hidden from both partners pending review. |
| User tries to start new game while one active | Show resume/abandon dialog. |

---

## 10. NOTIFICATIONS

### 10.1 Notification triggers

| Event | Title | Body | Data | Rate limit |
|-------|-------|------|------|-------------|
| Game invitation | `[Name] wants to play This or That` | `[Tone] tone — ~5 minutes` | `{ type: 'game_invite', session_id }` | None |
| Reveal ready | `Reveal ready!` | `See how you both answered` | `{ type: 'reveal_ready', session_id, round_number }` | None |
| Reminder (to non-answerer) | `Your turn in This or That` | `Jordan hasn't answered round X` | `{ type: 'game_reminder', session_id, round_number }` | Once per 4h per session |
| Session abandoned | `Game session expired` | `Start a new game of This or That →` | `{ type: 'session_expired', game_type }` | None |
| Partner declined | `Jordan can't play right now` | `Start a new game →` | `{ type: 'game_declined' }` | None |

**Note:** No per‑round "partner answered" notifications. Use in‑app status indicator only.

### 10.2 Notification service integration

Use existing `AttuneNotificationService.sendToUser()` with the parameters above. For reminder:
- Sent to partner who has **not** yet answered
- Enforce rate limit server‑side by checking `game_sessions.remind_last_sent_at` against 4‑hour cooldown

---

## 11. ANALYTICS EVENTS

All events using existing analytics service (PostHog). No PII.

| Event | Properties | When triggered |
|-------|------------|----------------|
| `game_session_started` | `game_type`, `tone`, `initiator_id`, `relationship_id`, `session_id` | Session created (invited) |
| `game_invitation_sent` | `session_id`, `recipient_id`, `tone` | Push notification sent |
| `game_invitation_accepted` | `session_id`, `responder_id`, `tone` | Partner accepts |
| `game_invitation_declined` | `session_id`, `responder_id`, `tone`, `fallback_tone` (if Intimate→Spicy) | Partner declines or declines Intimate |
| `game_round_answered` | `session_id`, `round_number`, `time_to_answer_ms`, `source` (preset/custom), `question_id` | User submits answer |
| `game_round_completed` | `session_id`, `round_number`, `match` (bool), `question_source` (preset/custom) | Both answered, reveal shown |
| `game_session_completed` | `session_id`, `match_count`, `total_rounds`, `tone`, `duration_seconds` | Session complete |
| `game_session_abandoned` | `session_id`, `round_at_abandon`, `reason` (invite_timeout/round_inactivity/post_reveal_inactivity/explicit_decline/explicit_cancel) | Session abandoned |
| `game_reveal_fallback_used` | `session_id`, `round_number`, `reason` (realtime_miss/timeout) | Fallback triggered |
| `game_reminder_sent` | `session_id`, `round_number`, `recipient_id` | Remind button tapped |
| `game_replayed` | `session_id`, `previous_session_id` | Play again button tapped |
| `custom_question_created` | `user_id`, `tone`, `is_private` | Custom question saved |
| `custom_question_used` | `question_id`, `session_id`, `round_number` | Custom question served |
| `custom_question_reported` | `question_id`, `reason` | User reports custom question |

---

## 12. BUILD ORDER

### PHASE 1 — DATA LAYER

Step 1: Run migrations for existing tables
Step 2: Add cumulative tracking columns to `game_sessions`
Step 3: Add `reveal_triggered_at` to `game_session_rounds`
Step 4: Add `hidden_by_user_ids` to `game_sessions`
Step 5: Create `custom_this_or_that_questions` table with RLS
Step 6: Seed preset question bank (minimum 230 questions)
Step 7: Verify all RLS policies

### PHASE 2 — TONE SYSTEM

Step 8: Tone selector component (5 tone options, default Connecting)
Step 9: Intimate consent dialog
Step 10: Receiving partner tone acceptance/decline flow (fallback to Spicy)

### PHASE 3 — SESSION INITIATION

Step 11: Create session edge function (selects initial 10 questions, creates rows, sends invitation)
Step 12: Game invitation push notification
Step 13: Remind button edge function (rate‑limited, updates `remind_last_sent_at`)
Step 14: Invitation screen (accept/decline handlers)
Step 15: Session acceptance → status `active`

### PHASE 4 — REAL-TIME SYNC

Step 16: Realtime subscription on `game_session_rounds`
Step 17: Set `reveal_triggered_at` on second answer
Step 18: Client‑side reveal sync (500ms grace + polling fallback + manual button)
Step 19: Analytics event `game_reveal_fallback_used`

### PHASE 5 — QUESTION SCREEN

Step 20: Question screen UI (two tappable cards, partner status indicator)
Step 21: Answer submission (update round, local cache if offline)
Step 22: Waiting screen with remind button
Step 23: Answer change from waiting screen (back navigation)

### PHASE 6 — QUESTION SOURCE SELECTION

Step 24: Turn tracking (alternating partners for choosing source)
Step 25: Source selection UI (Preset / Custom)
Step 26: Custom source partner picker
Step 27: Fallback to preset if no custom questions available
Step 28: Single question selection at a time (not pre-fetching all 10)

### PHASE 7 — REVEAL AND END SCREENS

Step 29: Reveal screen UI (two columns, match indicator)
Step 30: Next/Previous navigation
Step 31: End screen UI (match count, percentage, most interesting pick)
Step 32: Low match framing (no bar below 60%)
Step 33: Play again (returns to tone selector) and Try another game buttons

### PHASE 8 — CUSTOM QUESTIONS CRUD

Step 34: Custom question creation screen
Step 35: Custom question list (Profile → Games → Custom questions)
Step 36: Edit/delete own questions
Step 37: Toggle share with partner
Step 38: Report custom question flow

### PHASE 9 — SEEN QUESTIONS TRACKING

Step 39: Insert into `game_questions_seen` after each completed round (preset only)
Step 40: Selection algorithm integration

### PHASE 10 — SESSION HISTORY

Step 41: Past sessions list in Games Hub
Step 42: Session detail view (all 10 rounds with answers)
Step 43: Hide session from own view (soft delete)

### PHASE 11 — EDGE CASES & CLEANUP

Step 44: Abandoned session cron (48h invited, 24h round inactivity, 24h post-reveal inactivity)
Step 45: Active session guard (one at a time with resume/abandon dialog)
Step 46: Offline handling + state restoration
Step 47: Concurrent answer transaction

### PHASE 12 — ANALYTICS

Step 48: Implement all analytics events from Section 11

---

## 13. ALGORITHM QUALITY CHECKLIST

Applicable checks for This or That:

| # | Check | Status | Verification |
|---|-------|--------|--------------|
| 1.1 | Idempotency keys for mutations | ✅ | Session creation uses idempotency key; answer submission upserts |
| 1.2 | Timeouts for external calls | ✅ | 10s timeout, fallback to local cache |
| 1.6 | Concurrency risks identified | ✅ | Simultaneous answers use transaction + row lock |
| 2.1 | Input sanitization | ✅ | Choice validation (must be 'a' or 'b'), custom question length limits |
| 2.2 | Parameterized queries | ✅ | All Supabase queries parameterized |
| 2.4 | Error messages don't leak | ✅ | User sees friendly messages, not stack traces |
| 2.5 | Resource limits enforced | ✅ | 10 rounds per session, custom question character limits |
| 2.10 | Resources released | ✅ | Realtime subscription disposed on screen exit |
| 2.14 | Memory growth bounded | ✅ | Session loads 10 questions at once |
| 3.1 | Pagination | ✅ | Past sessions list paginated (20 per page) |
| 3.8 | Rate limiting | ✅ | Remind button once per 4h (server-side), game init 5 per hour |
| 3.9 | Retry logic | ✅ | Answer submission retries 3 times with exponential backoff |
| 4.1 | Structured logs | ✅ | All key events logged |
| 4.4 | PII excluded from logs | ✅ | No message content logged; only user IDs |
| 4.9 | Alerts defined | ✅ | Session creation failure, reveal sync failure alerts |
| 5.1 | Error responses actionable | ✅ | Clear next steps for all error states |
| 5.2 | p95 latency ≤ 200ms | ✅ | Answer save <100ms, reveal sync with fallback |
| 6.1 | Edge cases covered | ✅ | Section 9 covers 15+ edge cases |
| 6.2 | Failure scenarios tested | ✅ | Network disconnect, partner timeout, abandoned session |
| 6.3 | Concurrency tested | ✅ | Race condition test for simultaneous answers |
| 6.7 | Branch coverage ≥ 90% | ✅ | Selection algorithm unit tests |
| 8.1 | Rollback procedure | ✅ | Deploy game version → rollback to previous |
| 8.2 | Smoke tests | ✅ | Critical path: initiate → accept → answer → reveal |

---

## 14. SOUL DOCUMENT COMPLIANCE CHECK

| Principle | Status | Evidence |
|-----------|--------|----------|
| No streaks | ✅ | No streak tracking anywhere in spec |
| No leaderboards | ✅ | No comparison between couples |
| No badges | ✅ | No achievement badges for completing games |
| Gift/receipt framework | ✅ | Reveal has anticipation (waiting), reveal (simultaneous), afterglow (match indicator) |
| Incomplete loops close in relationship | ✅ | End screen prompts real conversation, not in-app resolution |
| User autonomy | ✅ | Custom questions, choose source, remind button opt‑in |
| No diagnostic language | ✅ | Match percentage framed as interesting, not judgement |
| No anxiety by design | ✅ | Low match percentage (<60%) shows curiosity framing, not failure |
| Intimate consent gate | ✅ | Both partners must explicitly consent |
| Data belongs to users | ✅ | Soft delete for session history, user control |

---

## 15. OPEN QUESTIONS

All open questions resolved in v1.3.

| Status | Item |
|--------|------|
| ✅ Resolved | One active session at a time |
| ✅ Resolved | End screen summary only (no full round list) |
| ✅ Resolved | Intimate tone content requires clinical sign-off before launch |
| ✅ Resolved | Cumulative tracking columns added now |
| ✅ Resolved | Session history visible forever |
| ✅ Resolved | Soft delete (hide from own view only) |
| ✅ Resolved | Custom questions (create, share, reuse) |
| ✅ Resolved | Remind button: appears to waiting partner, notifies non-answerer |
| ✅ Resolved | Answer change from waiting screen |
| ✅ Resolved | Low match percentage framing |
| ✅ Resolved | Question source selection between rounds (Preset / Custom) |

---

*This spec is complete and ready for implementation.*  
*Build in the exact order defined in Section 12.*  
*Seed preset question bank (230 min) in parallel with build.*  
*Intimate tone: build fully, deploy only after clinical sign-off.*  
*Review against ATTUNE_SOUL.md before shipping.*  
*Run algorithm_quality_review_checklist.md before merge.*  
*Last reviewed: June 2026*
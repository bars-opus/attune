# ATTUNE — PULSE SCORE + TIMELINE SPECIFICATION
### Combined implementation spec for the Pulse Score and Timeline features
**Version:** 1.0
**Created:** June 2026
**Status:** Ready for DeepSeek implementation
**Builder:** DeepSeek
**Reviewer:** Claude (this session)
**Related documents:** ATTUNE_MASTER_SPEC.md · ATTUNE_SOUL.md · ATTUNE_CLINICAL.md

---

> **HOW TO USE THIS DOCUMENT**
>
> This spec covers two features built as one:
> Part A — Timeline (log and display relationship moments)
> Part B — Pulse Score (weekly relationship health computation)
> Part C — Integration (how they feed each other)
>
> Build Part A first. The timeline produces the data
> that the pulse score consumes. Build Part B second.
> Part C wires them together.
>
> Build in the exact order defined in Section 9.
> Do not skip ahead. Do not add features not described here.

---

## TABLE OF CONTENTS

1. [Feature Overview](#1-feature-overview)
2. [Navigation and Entry Points](#2-navigation-and-entry-points)
3. [Part A — Timeline](#3-part-a--timeline)
4. [Part B — Pulse Score](#4-part-b--pulse-score)
5. [Part C — Integration](#5-part-c--integration)
6. [Weekly Check-In](#6-weekly-check-in)
7. [Data Confidence System](#7-data-confidence-system)
8. [Database Schema](#8-database-schema)
9. [Build Order](#9-build-order)
10. [Open Questions](#10-open-questions)

---

## 1. FEATURE OVERVIEW

### What the Timeline is

A shared relationship journal. Both partners can log moments —
milestones, conflicts, highlights, firsts, anniversaries — with
a mood score and optional note. Every logged moment is visible
to both partners immediately. The timeline builds the shared
memory of the relationship and feeds the pulse score.

### What the Pulse Score is

A weekly relationship health picture built from real data.
Five dimensions measured separately, combined into one overall
score (0-100). Displayed in three visual formats the user can
switch between. Updated every Sunday. Gets more accurate as
more data accumulates over time.

### What feeds the pulse score at launch

```
AVAILABLE NOW (build these):
✓ Timeline events logged by both partners
✓ Manual weekly check-in responses
✓ Attachment quiz completion (both partners)

AVAILABLE WHEN GAMES ARE BUILT (future):
○ 36 Questions game completion
○ Mirror game accuracy scores
○ Sliding scale game results

AVAILABLE WHEN CHAT AI PIPELINE IS BUILT (future):
○ Message tone scores
○ NVC violation detection
○ Bid-for-connection tracking
○ Response latency patterns
○ Session escalation scores

The pulse score is built to accept future data sources.
At launch it runs on timeline events and check-ins only.
Communication and Conflict Health dimensions will show
low confidence until chat AI pipeline is connected.
```

---

## 2. NAVIGATION AND ENTRY POINTS

### Where these features live

Both features live in the **Pulse tab** (first tab in the
bottom navigation bar).

```
BOTTOM TAB BAR:
┌──────────────────────────────────────────┐
│  Pulse  │  Chat  │  Games  │  Insights  │  Profile  │
└──────────────────────────────────────────┘
          ↑
          Pulse tab contains both
          Pulse Score and Timeline
```

### Pulse tab internal structure

```
PULSE TAB
├── Pulse Score screen    ← default view on tab open
│   ├── Score visualisation (ring / radar / number)
│   ├── Five dimension breakdown
│   ├── Trend chart (4-week history)
│   └── Entry point to weekly check-in
└── Timeline screen       ← accessible via tab or scroll
    ├── Horizontal calendar strip (top)
    └── Vertical moments list (below calendar)
```

### Tab switcher within Pulse tab

```
┌─────────────────────────────────────┐
│  ● Pulse    ○ Timeline              │  ← pill switcher
└─────────────────────────────────────┘

Default: Pulse screen selected on tab open
Switching between Pulse and Timeline: animated slide
```

---

## 3. PART A — TIMELINE

### 3.1 Timeline screen layout

```
┌─────────────────────────────────────┐
│  ● Pulse    ○ Timeline              │  ← tab switcher
├─────────────────────────────────────┤
│                                     │
│  June 2026          [< prev] [next >]│
│                                     │
│  Mo Tu We Th Fr Sa Su               │
│  ─────────────────────────────────  │
│   2   3  [4]  5   6   7   8         │  ← dates with dots for events
│   9  10  11  12  13  14  15         │
│  16  17  18  19  20  21  22         │
│  23  24  25  26  27  28  29         │
│  30                                 │
│                                     │  ← calendar scrolls horizontally
├─────────────────────────────────────┤  ← divider
│                                     │
│  [+ Log a moment]                   │  ← floating action button
│                                     │
│  ── June 2026 ──────────────────── │
│                                     │
│  [moment card]                      │
│  [moment card]                      │
│  [moment card]                      │
│                                     │
│  ── May 2026 ───────────────────── │
│                                     │
│  [moment card]                      │
│                                     │
└─────────────────────────────────────┘
```

### 3.2 Calendar strip behaviour

```
Layout:
- Shows full month view
- Horizontally swipeable between months
- [< prev] and [next >] arrows for navigation
- Today's date highlighted with Attune green circle
- Dates with logged moments show a small dot below the number
  Dot colour matches event type:
    Milestone   → Attune green dot
    Conflict    → red dot
    Highlight   → amber dot
    First       → purple dot
    Anniversary → pink dot
  If multiple events on one date: show up to 3 dots

Tapping a date:
- Scrolls the vertical list below to that date's events
- Highlights the selected date with a light background
- If no events on that date: scrolls to nearest date with events
```

### 3.3 Moment card design

```
┌─────────────────────────────────────┐
│  ●  Milestone              Jun 4    │  ← coloured dot + type + date
│                                     │
│  First trip together                │  ← title (required)
│                                     │
│  Weekend in Cape Coast. First time  │  ← note (optional)
│  travelling together. Felt easy     │
│  and natural.                       │
│                                     │
│  Mood: ████████░░  8/10             │  ← mood bar (if logged)
│                                     │
│  Logged by: You                     │  ← or "Logged by: Jordan"
│                                     │
│  [⋯ Edit]  [🗑 Delete]              │  ← only shown if logged by user
└─────────────────────────────────────┘

Moment types and colours:
┌─────────────────┬───────────────────┐
│ Type            │ Colour            │
├─────────────────┼───────────────────┤
│ Milestone       │ Attune green      │
│ Conflict        │ Red               │
│ Highlight       │ Amber             │
│ First           │ Purple            │
│ Anniversary     │ Pink              │
└─────────────────┴───────────────────┘

Visibility:
- Both partners see all moments from both loggers
- No privacy controls — everything is shared
- The logger's name is shown ("Logged by: Jordan")
  so each partner knows who recorded what
```

### 3.4 Log a moment flow

Triggered by tapping [+ Log a moment] button.

```
SCREEN 1 — Type selection:
┌─────────────────────────────────────┐
│  ← Back        Log a moment         │
│                                     │
│  What kind of moment is this?       │
│                                     │
│  ┌─────────┐  ┌─────────┐          │
│  │   ✦     │  │   ♥     │          │
│  │Milestone│  │Highlight│          │
│  └─────────┘  └─────────┘          │
│                                     │
│  ┌─────────┐  ┌─────────┐          │
│  │   ✕     │  │   ★     │          │
│  │Conflict │  │  First  │          │
│  └─────────┘  └─────────┘          │
│                                     │
│  ┌─────────┐                        │
│  │   ♦     │                        │
│  │Annivers-│                        │
│  │  ary    │                        │
│  └─────────┘                        │
└─────────────────────────────────────┘

SCREEN 2 — Details:
┌─────────────────────────────────────┐
│  ← Back        Milestone            │
│                                     │
│  Title (required)                   │
│  ┌─────────────────────────────┐   │
│  │ e.g. First trip together    │   │
│  └─────────────────────────────┘   │
│  Max 80 characters                  │
│                                     │
│  Date                               │
│  ┌─────────────────────────────┐   │
│  │ Today — Jun 4, 2026     ▼   │   │
│  └─────────────────────────────┘   │
│  (date picker, defaults to today)   │
│                                     │
│  How did this feel? (optional)      │
│  1  2  3  4  5  6  7  8  9  10     │
│  ○  ○  ○  ○  ○  ○  ○  ●  ○  ○      │
│  Difficult              Amazing     │
│                                     │
│  Add a note (optional)              │
│  ┌─────────────────────────────┐   │
│  │                             │   │
│  │                             │   │
│  └─────────────────────────────┘   │
│  Max 300 characters                 │
│                                     │
│                      [Save moment]  │
└─────────────────────────────────────┘

On save:
- Moment inserted into timeline_events table
- Calendar dot appears on the logged date immediately
- Moment card appears at correct position in vertical list
- Partner sees it immediately (real-time via Supabase Realtime)
- Partner receives push notification (see Section 10)
```

### 3.5 Edit and delete

```
Edit:
- Only the person who logged the moment can edit it
- Opens same Screen 2 form pre-filled with existing data
- All fields editable including date and type
- Save overwrites the existing record

Delete:
- Only the logger can delete
- Confirmation: "Delete this moment? This cannot be undone."
- [Cancel] [Delete]
- On confirm: soft delete (deleted_at = now())
- Moment disappears from both partners' timelines immediately
- Calendar dot removed if no other events on that date
```

### 3.6 Empty state

```
No moments logged yet:

┌─────────────────────────────────────┐
│  [Calendar strip — all dates empty] │
│                                     │
│  Your relationship story            │
│  starts here.                       │
│                                     │
│  Log your first moment —            │
│  a milestone, a highlight,          │
│  or even a conflict you worked      │
│  through.                           │
│                                     │
│       [+ Log your first moment]     │
└─────────────────────────────────────┘
```

---

## 4. PART B — PULSE SCORE

### 4.1 The five dimensions

```
1. COMMUNICATION (weight: 22% of overall score)
   What it measures: how clearly and kindly partners
   express themselves and respond to each other
   Data sources at launch: weekly check-in response,
   conflict events on timeline (negative signal),
   highlight events (positive signal)
   Future data: chat AI pipeline (tone, NVC, bids)

2. CONNECTION (weight: 22% of overall score)
   What it measures: emotional closeness, warmth,
   and active investment in the relationship
   Data sources at launch: milestone and highlight events,
   anniversary events, weekly check-in response
   Future data: bid-for-connection tracking from chat

3. CONFLICT HEALTH (weight: 20% of overall score)
   What it measures: how well the couple navigates
   disagreement — not the absence of conflict but
   the quality of how it is handled
   Data sources at launch: conflict events on timeline
   (frequency and mood score after conflict),
   weekly check-in response
   Future data: repair attempt detection from chat AI

4. ALIGNMENT (weight: 18% of overall score)
   What it measures: shared values, goals, and
   whether the couple feels they are moving in the
   same direction
   Data sources at launch: both partners completing
   attachment quiz, weekly check-in response
   Future data: games data (Sliding Scale, 36 Questions)

5. EMOTIONAL SAFETY (weight: 18% of overall score)
   What it measures: whether both partners feel safe
   being vulnerable, expressing needs, and being themselves
   Data sources at launch: mood scores on logged moments,
   weekly check-in response
   Future data: session analysis from chat AI
```

### 4.2 Computation schedule

```
Computed: every Sunday at 00:07 UTC (7-minute offset
          to avoid thundering herd — see master spec)
Minimum data threshold: at least 1 week of data
                        and at least 1 check-in completed
                        before first pulse is shown
On-demand: user can tap [Refresh] to recompute
           (rate limited to once per 24 hours)
```

### 4.3 Scoring algorithm

```javascript
// Run server-side via Supabase Edge Function
// Input: relationship_id, week ending date
// Output: pulse_score record inserted

const computePulseScore = async (relationshipId, weekEnding) => {

  // Fetch all data for this relationship
  const data = await fetchRelationshipData(relationshipId, weekEnding)

  // ── COMMUNICATION (0-100) ──────────────────────────────
  // At launch: derived from check-in and conflict events
  let communication = 50  // baseline — neutral start

  // Check-in contribution (if completed this week)
  if (data.checkin?.communication_rating) {
    communication = data.checkin.communication_rating * 10
    // check-in asks 1-10 → maps to 10-100
  }

  // Conflict events in last 30 days lower communication score
  // High mood-after-conflict actually raises it (shows resolution)
  const conflictPenalty = data.conflicts_30d * 3
  const resolutionBonus = data.conflict_high_mood_count * 5
  communication = clamp(communication - conflictPenalty
                        + resolutionBonus, 0, 100)

  // data_confidence: 'low' until chat AI pipeline connected
  const communicationConfidence = data.has_chat_analysis
    ? 'medium' : 'low'


  // ── CONNECTION (0-100) ─────────────────────────────────
  let connection = 50

  // Milestone and highlight events in last 30 days
  const positiveEvents = data.milestones_30d + data.highlights_30d
  connection = clamp(50 + (positiveEvents * 8), 0, 100)

  // Anniversary logged = strong positive signal
  if (data.anniversary_this_week) connection = clamp(connection + 15, 0, 100)

  // Check-in contribution
  if (data.checkin?.connection_rating) {
    connection = Math.round((connection +
                 data.checkin.connection_rating * 10) / 2)
  }

  const connectionConfidence = positiveEvents > 0 ? 'medium' : 'low'


  // ── CONFLICT HEALTH (0-100) ────────────────────────────
  let conflictHealth = 70  // optimistic baseline — assume health

  // If no conflicts logged: stays at baseline (neither good nor bad)
  // Conflicts logged with high mood after = healthy (resolution shown)
  // Conflicts logged with low mood after = concerning

  if (data.conflicts_30d > 0) {
    const avgMoodAfterConflict = data.avg_conflict_mood || 5
    conflictHealth = Math.round(avgMoodAfterConflict * 10)
    // mood 1-10 → 10-100
  }

  // Check-in contribution
  if (data.checkin?.conflict_health_rating) {
    conflictHealth = Math.round((conflictHealth +
                    data.checkin.conflict_health_rating * 10) / 2)
  }

  const conflictHealthConfidence = data.conflicts_30d > 0
    ? 'medium' : 'low'


  // ── ALIGNMENT (0-100) ──────────────────────────────────
  let alignment = 50

  // Both partners completed attachment quiz = positive signal
  if (data.both_completed_attachment_quiz) {
    alignment = clamp(alignment + 20, 0, 100)
  }

  // Check-in contribution
  if (data.checkin?.alignment_rating) {
    alignment = Math.round((alignment +
                data.checkin.alignment_rating * 10) / 2)
  }

  const alignmentConfidence = data.both_completed_attachment_quiz
    ? 'medium' : 'low'


  // ── EMOTIONAL SAFETY (0-100) ───────────────────────────
  let emotionalSafety = 50

  // Average mood score across all logged moments (last 30 days)
  if (data.avg_mood_all_events) {
    emotionalSafety = Math.round(data.avg_mood_all_events * 10)
  }

  // Check-in contribution
  if (data.checkin?.safety_rating) {
    emotionalSafety = Math.round((emotionalSafety +
                     data.checkin.safety_rating * 10) / 2)
  }

  const safetyConfidence = data.total_events_30d > 3
    ? 'medium' : 'low'


  // ── OVERALL SCORE ──────────────────────────────────────
  const overall = Math.round(
    communication  * 0.22 +
    connection     * 0.22 +
    conflictHealth * 0.20 +
    alignment      * 0.18 +
    emotionalSafety * 0.18
  )

  // ── DATA CONFIDENCE OVERALL ────────────────────────────
  const confidences = [communicationConfidence, connectionConfidence,
                       conflictHealthConfidence, alignmentConfidence,
                       safetyConfidence]
  const highCount   = confidences.filter(c => c === 'high').length
  const mediumCount = confidences.filter(c => c === 'medium').length

  const overallConfidence =
    highCount >= 4   ? 'high'   :
    mediumCount >= 3 ? 'medium' :
    mediumCount >= 1 ? 'low'    : 'none'


  // ── DELTAS VS PREVIOUS WEEK ────────────────────────────
  const previous = await getLastPulseScore(relationshipId)
  const deltas = previous ? {
    overall:         overall - previous.overall_score,
    communication:   communication - previous.communication,
    connection:      connection - previous.connection,
    conflictHealth:  conflictHealth - previous.conflict_health,
    alignment:       alignment - previous.alignment,
    emotionalSafety: emotionalSafety - previous.emotional_safety,
  } : null


  // ── SAVE ───────────────────────────────────────────────
  return {
    overall_score:    overall,
    communication,
    connection,
    conflict_health:  conflictHealth,
    alignment,
    emotional_safety: emotionalSafety,
    data_confidence:  overallConfidence,
    dimension_confidence: {
      communication:   communicationConfidence,
      connection:      connectionConfidence,
      conflict_health: conflictHealthConfidence,
      alignment:       alignmentConfidence,
      emotional_safety: safetyConfidence,
    },
    delta_vs_previous: deltas,
  }
}

// Helper: clamp value between min and max
const clamp = (val, min, max) => Math.min(Math.max(val, min), max)
```

### 4.4 Pulse score screen — layout

```
┌─────────────────────────────────────┐
│  ● Pulse    ○ Timeline              │
├─────────────────────────────────────┤
│  Updated Sunday · Jun 1, 2026       │
│  data_confidence shown here         │
│  (see Section 7)                    │
│                                     │
│  [Ring] [Radar] [Number]            │  ← visualisation switcher
│  ─────────────────────────────────  │
│                                     │
│  [selected visualisation]           │
│                                     │
│  ─────────────────────────────────  │
│                                     │
│  Dimensions                         │
│  (always shown below visualisation) │
│                                     │
│  Communication  ████████████░  82  +6│
│  Connection     █████████░░░░  71  -3│
│  Conflict health████████░░░░  68   ─ │
│  Alignment      ██████████░░  77  +2 │
│  Emotional safe █████████░░░  73  +4 │
│                                     │
│  ─────────────────────────────────  │
│                                     │
│  4-week trend                       │
│  [bar chart — 4 weeks]              │
│                                     │
│  ─────────────────────────────────  │
│                                     │
│  [Complete this week's check-in →]  │
│  (shown if check-in not yet done)   │
│                                     │
└─────────────────────────────────────┘
```

### 4.5 Three visualisations

User selects with the switcher. Selection persists in local
storage — remembered next time they open the tab.

#### Visualisation 1 — Ring (default)

```
A single circular ring, Apple Watch style.
Ring fills clockwise from the top.
Overall score (0-100) shown in the centre.
Ring colour: Attune green.
Background ring: light grey.

Example at score 74:
- Ring is approximately 74% filled (clockwise from top)
- "74" shown in centre, large
- "out of 100" shown below it, small

Animation on load:
- Ring fills from 0 to final score
- Duration: 1 second, ease-out
- Score number counts up from 0 to final
- Duration: 1 second, ease-out (synced with ring)
```

#### Visualisation 2 — Radar / Spider chart

```
A pentagon (5 points, one per dimension).
Each axis runs from 0 (centre) to 100 (edge).
Filled polygon shows current scores.
Light green fill with Attune green border.

Dimension labels at each point:
- Top: Emotional Safety
- Top-right: Communication
- Bottom-right: Conflict Health
- Bottom-left: Alignment
- Top-left: Connection

Animation on load:
- Polygon grows from centre outward
- Duration: 0.8 seconds, ease-out

Tapping any point label:
- Shows a tooltip with that dimension's score
  and a one-line description of what it measures
```

#### Visualisation 3 — Number

```
Large overall score centred on screen.
Font: large, bold, Attune green.
Below it: "Your relationship pulse this week"

Five dimensions listed below as a simple column:

Communication      82   ↑+6
Connection         71   ↓-3
Conflict health    68    —
Alignment          77   ↑+2
Emotional safety   73   ↑+4

Delta arrows:
↑ = improved (Attune green)
↓ = declined (red)
— = unchanged (grey)

No bars, no charts — just numbers.
Clean and readable.
```

### 4.6 The 4-week trend chart

```
Always shown below the visualisation.
Simple vertical bar chart.
4 bars — one per week.
Current week is Attune green.
Previous weeks are light grey.
Score shown above each bar.

Example:
  58    63    68    74
  ██    ██    ██    ██
 Week1 Week2 Week3 Week4(current)

If fewer than 4 weeks of data:
Show only the weeks that exist.
Empty weeks shown as dotted outline bars.
```

---

## 5. PART C — INTEGRATION

### How timeline feeds pulse score

```
Timeline events contribute to pulse score computation
in the following ways:

MILESTONE events:
+ Connection dimension: +8 points per milestone (30d)
+ Emotional Safety: mild positive signal

HIGHLIGHT events:
+ Connection dimension: +8 points per highlight (30d)
+ Emotional Safety: mild positive signal

CONFLICT events:
- Communication dimension: -3 points per conflict (30d)
+ Conflict Health: improved when mood_score after conflict
  is 7+ (shows the conflict was resolved)
- Conflict Health: decreased when mood_score is 3 or below

ANNIVERSARY events:
+ Connection dimension: +15 points (strong positive)
+ Emotional Safety: mild positive

FIRST events:
+ Connection dimension: +5 points (moderate positive)

MOOD SCORES on any event:
Average of all mood scores (30 days) → Emotional Safety score
```

### How quiz completion feeds pulse score

```
Both partners completed attachment quiz:
+ Alignment dimension: +20 points
Reason: taking the quiz together signals investment
in understanding each other

One partner completed, other has not:
+ Alignment dimension: +5 points only
(shows individual investment, not shared yet)
```

### Future integration points (not built now)

```
These are architecture hooks — the data structures
accept these inputs when the features are built later.

Games data → Connection and Alignment dimensions
Chat AI analysis → Communication and Conflict Health
Session repair attempts → Conflict Health
Bid-for-connection tracking → Connection
```

---

## 6. WEEKLY CHECK-IN

### What it is

A short weekly prompt that gives users a direct input
into their pulse score. Five questions, one per dimension.
Takes under 90 seconds to complete.

### When it appears

```
- Every Sunday, a push notification fires at 7pm local time:
  "How was your relationship this week? Takes 60 seconds."
- In-app: a banner appears on the Pulse tab if not completed
- The banner disappears once completed or if user dismisses it
  (and checks-in late that week — late check-ins still count)
```

### Check-in screen

```
┌─────────────────────────────────────┐
│  ← Back       Weekly check-in       │
│  Week of Jun 1 – Jun 7              │
│                                     │
│  Five quick questions.              │
│  Answer how it actually felt.       │
│                                     │
│  ─────────────────────────────────  │
│                                     │
│  Communication                      │
│  How well did you and Jordan        │
│  express yourselves this week?      │
│                                     │
│  1   2   3   4   5   6   7   8  9  10│
│  ○   ○   ○   ○   ○   ○   ●   ○  ○   ○│
│  Struggled              Excellent   │
│                                     │
│  ─────────────────────────────────  │
│                                     │
│  Connection                         │
│  How close did you feel to Jordan   │
│  this week?                         │
│                                     │
│  1   2   3   4   5   6   7   8  9  10│
│  ○   ○   ○   ○   ●   ○   ○   ○  ○   ○│
│                                     │
│  ─────────────────────────────────  │
│                                     │
│  Conflict health                    │
│  If there were any disagreements    │
│  this week, how well did you handle │
│  them together?                     │
│                                     │
│  1   2   3   4   5   6   7   8  9  10│
│  ○   ○   ○   ○   ○   ○   ○   ●  ○   ○│
│  Poorly                 Really well │
│                                     │
│  N/A — no disagreements this week   │  ← checkbox
│                                     │
│  ─────────────────────────────────  │
│                                     │
│  Alignment                          │
│  Did you and Jordan feel like you   │
│  are moving in the same direction?  │
│                                     │
│  1   2   3   4   5   6   7   8  9  10│
│  ○   ○   ○   ○   ○   ●   ○   ○  ○   ○│
│                                     │
│  ─────────────────────────────────  │
│                                     │
│  Emotional safety                   │
│  How safe did you feel being        │
│  yourself with Jordan this week?    │
│                                     │
│  1   2   3   4   5   6   7   8  9  10│
│  ○   ○   ○   ○   ○   ○   ●   ○  ○   ○│
│                                     │
│  ─────────────────────────────────  │
│                                     │
│              [Submit check-in]      │
└─────────────────────────────────────┘

Rules:
- All five questions shown on one scrollable screen
  (not paginated — the soul document says no streaks,
  so we keep this simple and frictionless)
- Submit button disabled until all five answered
  (or N/A checked for conflict health)
- Both partners complete independently
- Neither partner sees the other's check-in answers
  (answers are private — only the computed dimension
  scores are shared via the pulse score)
- Late check-ins accepted any time during the week
  up to the next Sunday
```

### After submission

```
Confirmation screen:
┌─────────────────────────────────────┐
│                                     │
│  Check-in complete.                 │
│                                     │
│  Your pulse score will update       │
│  on Sunday.                         │
│                                     │
│  [Back to Pulse]                    │
└─────────────────────────────────────┘

If BOTH partners have completed this week's check-in:
- Pulse score recomputed immediately (do not wait for Sunday)
- Both partners notified: "Your pulse score has been updated."
```

### No streaks

```
IMPORTANT: Do not implement streak tracking for check-ins.
Do not show "X week streak" anywhere.
Do not send "don't break your streak" notifications.
Do not penalise missed weeks in any visible way.

A missed week: the pulse score simply uses the data
available without that week's check-in.
No punishment. No guilt. No streak to protect.
This is a permanent constraint from ATTUNE_SOUL.md.
```

---

## 7. DATA CONFIDENCE SYSTEM

### The four confidence levels

```
NONE    → fewer than 2 data points of any kind
          "Not enough data yet — keep using Attune"

LOW     → some data but limited
          "Based on limited data — improves with time"

MEDIUM  → meaningful data but missing key sources
          "Based on X weeks of data"

HIGH    → rich data across multiple sources
          "Based on X weeks of comprehensive data"
          (requires chat AI pipeline — unlikely at launch)
```

### How confidence is displayed

```
On the pulse score screen, below the date:

NONE state:
┌─────────────────────────────────────┐
│  Not enough data yet                │
│  Complete a check-in to see         │
│  your first pulse score.            │
│  [Start check-in →]                 │
└─────────────────────────────────────┘

LOW state:
┌─────────────────────────────────────┐
│  Based on early data                │
│  Your score gets more accurate      │
│  as you log more moments and        │
│  complete weekly check-ins.         │
└─────────────────────────────────────┘

MEDIUM state:
┌─────────────────────────────────────┐
│  Based on 4 weeks of data           │
└─────────────────────────────────────┘
(small, unobtrusive — just one line)

HIGH state:
Nothing shown — the score speaks for itself.
```

### Per-dimension confidence

```
Each dimension row shows its individual confidence
as a subtle indicator:

Communication  ████████████░  82  +6  ●
                                      ↑
                              green dot = medium/high confidence
                              grey dot  = low confidence
                              no dot    = confidence shown in
                                          tooltip on tap

Tapping the dot shows:
"Communication is based on your weekly check-in.
 It will improve when chat analysis is active."
```

---

## 8. DATABASE SCHEMA

```sql
-- Timeline events
CREATE TABLE timeline_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  relationship_id uuid REFERENCES relationships NOT NULL,
  logged_by uuid REFERENCES auth.users NOT NULL,
  event_type text CHECK (event_type IN (
    'milestone', 'conflict', 'highlight', 'first', 'anniversary'
  )) NOT NULL,
  title text NOT NULL CHECK (char_length(title) <= 80),
  note text CHECK (char_length(note) <= 300),
  mood_score int CHECK (mood_score BETWEEN 1 AND 10),
  occurred_at date NOT NULL,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  deleted_at timestamptz               -- soft delete
);

-- Pulse scores (one record per week per relationship)
CREATE TABLE pulse_scores (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  relationship_id uuid REFERENCES relationships NOT NULL,
  week_ending date NOT NULL,           -- Sunday of the week
  computed_at timestamptz DEFAULT now(),
  overall_score int NOT NULL CHECK (overall_score BETWEEN 0 AND 100),
  communication int NOT NULL CHECK (communication BETWEEN 0 AND 100),
  connection int NOT NULL CHECK (connection BETWEEN 0 AND 100),
  conflict_health int NOT NULL CHECK (conflict_health BETWEEN 0 AND 100),
  alignment int NOT NULL CHECK (alignment BETWEEN 0 AND 100),
  emotional_safety int NOT NULL CHECK (emotional_safety BETWEEN 0 AND 100),
  data_confidence text CHECK (data_confidence IN (
    'none', 'low', 'medium', 'high'
  )) DEFAULT 'low',
  dimension_confidence jsonb,
  -- Example: {"communication": "low", "connection": "medium", ...}
  delta_vs_previous jsonb,
  -- Example: {"overall": 3, "communication": 6, "connection": -3, ...}
  UNIQUE (relationship_id, week_ending)
);

-- Weekly check-ins (one per user per week)
CREATE TABLE weekly_checkins (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES auth.users NOT NULL,
  relationship_id uuid REFERENCES relationships NOT NULL,
  week_ending date NOT NULL,
  communication_rating int CHECK (communication_rating BETWEEN 1 AND 10),
  connection_rating int CHECK (connection_rating BETWEEN 1 AND 10),
  conflict_health_rating int CHECK (conflict_health_rating BETWEEN 1 AND 10),
  conflict_health_na boolean DEFAULT false,
  alignment_rating int CHECK (alignment_rating BETWEEN 1 AND 10),
  safety_rating int CHECK (safety_rating BETWEEN 1 AND 10),
  submitted_at timestamptz DEFAULT now(),
  UNIQUE (user_id, week_ending)        -- one check-in per user per week
);

-- User visualisation preference (remembered between sessions)
CREATE TABLE user_preferences (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES auth.users NOT NULL UNIQUE,
  pulse_visualisation text CHECK (pulse_visualisation IN (
    'ring', 'radar', 'number'
  )) DEFAULT 'ring',
  updated_at timestamptz DEFAULT now()
);
```

### RLS Policies

```sql
-- Timeline events: both partners can read and write
CREATE POLICY "timeline_relationship_members"
ON timeline_events FOR SELECT
USING (
  deleted_at IS NULL AND
  relationship_id IN (
    SELECT id FROM relationships
    WHERE user_a = auth.uid() OR user_b = auth.uid()
  )
);

CREATE POLICY "timeline_insert_members"
ON timeline_events FOR INSERT
WITH CHECK (
  auth.uid() = logged_by AND
  relationship_id IN (
    SELECT id FROM relationships
    WHERE user_a = auth.uid() OR user_b = auth.uid()
  )
);

-- Only logger can update or delete their own events
CREATE POLICY "timeline_update_owner"
ON timeline_events FOR UPDATE
USING (auth.uid() = logged_by);

CREATE POLICY "timeline_delete_owner"
ON timeline_events FOR DELETE
USING (auth.uid() = logged_by);

-- Pulse scores: both partners can read
CREATE POLICY "pulse_scores_relationship_members"
ON pulse_scores FOR SELECT
USING (
  relationship_id IN (
    SELECT id FROM relationships
    WHERE user_a = auth.uid() OR user_b = auth.uid()
  )
);

-- Weekly check-ins: private to the user who submitted
CREATE POLICY "checkins_private"
ON weekly_checkins FOR ALL
USING (auth.uid() = user_id);

-- User preferences: private to owner
CREATE POLICY "preferences_private"
ON user_preferences FOR ALL
USING (auth.uid() = user_id);
```

### Indexes for performance

```sql
-- Timeline: fast lookups by relationship and date
CREATE INDEX idx_timeline_relationship_date
ON timeline_events (relationship_id, occurred_at DESC)
WHERE deleted_at IS NULL;

-- Pulse scores: fast lookups by relationship
CREATE INDEX idx_pulse_relationship_week
ON pulse_scores (relationship_id, week_ending DESC);

-- Check-ins: fast lookups by user and week
CREATE INDEX idx_checkins_user_week
ON weekly_checkins (user_id, week_ending DESC);
```

---

## 9. BUILD ORDER

```
PHASE 1 — DATA LAYER
Step 1:  Run all migrations from Section 8
         All tables, RLS policies, indexes
Step 2:  Verify relationships table exists
         (from master spec — needed for RLS)
Step 3:  Set up Supabase pg_cron extension
         Schedule pulse computation: Sunday 00:07 UTC
         Schedule check-in notifications: Sunday 19:00 local

PHASE 2 — TIMELINE DATA OPERATIONS
Step 4:  Log a moment — type selection screen (Screen 1)
Step 5:  Log a moment — details screen (Screen 2)
         Title, date picker, mood slider, note field
Step 6:  Save moment to timeline_events
         Capture logged_by, relationship_id at insert
Step 7:  Edit moment flow
         Pre-filled form, save overwrites record
Step 8:  Delete moment
         Soft delete, confirmation dialog

PHASE 3 — TIMELINE DISPLAY
Step 9:  Calendar strip component
         Month view, horizontal swipe between months,
         dot indicators per event type on dates
Step 10: Moment card component
         Type colour, title, note, mood bar,
         logged-by label, edit/delete menu (own only)
Step 11: Vertical moments list
         Grouped by month, chronological newest first
         Section headers ("June 2026", "May 2026")
Step 12: Calendar-to-list linking
         Tapping a date scrolls list to that date
Step 13: Real-time updates
         Partner's logged moment appears immediately
         via Supabase Realtime subscription
Step 14: Empty state screen

PHASE 4 — WEEKLY CHECK-IN
Step 15: Check-in screen (all 5 questions, one scroll)
         1-10 scale per dimension, N/A for conflict health
Step 16: Submit check-in → write to weekly_checkins
Step 17: Check-in completion screen
Step 18: Check-in banner on Pulse tab (if not completed)
         Dismiss button hides for 24 hours
Step 19: Sunday push notification via OneSignal
         7pm local time, one notification per week

PHASE 5 — PULSE SCORE COMPUTATION
Step 20: Edge function: computePulseScore
         Full algorithm from Section 4.3
         Writes to pulse_scores table
Step 21: Sunday cron trigger (pg_cron)
         Triggers computePulseScore for all active relationships
Step 22: On-demand recompute
         User taps [Refresh] → triggers edge function
         Rate limited: once per 24 hours per relationship
Step 23: Both-partners-submitted trigger
         When both check-ins for same week are submitted:
         trigger immediate recompute for that relationship

PHASE 6 — PULSE SCORE DISPLAY
Step 24: Visualisation 1 — Ring
         Animated fill, score in centre, ease-out 1 second
Step 25: Visualisation 2 — Radar / Spider chart
         Pentagon, 5 axes, animated from centre, 0.8 seconds
Step 26: Visualisation 3 — Number
         Large score, delta arrows per dimension
Step 27: Visualisation switcher (Ring / Radar / Number)
         Persists selection in user_preferences table
Step 28: Five dimension rows
         Bar, score, delta (↑↓—), confidence dot
         Confidence tooltip on dot tap
Step 29: 4-week trend bar chart
         Below dimensions, current week green
Step 30: Data confidence display (Section 7)
         NONE / LOW / MEDIUM states shown appropriately

PHASE 7 — NAVIGATION AND INTEGRATION
Step 31: Pulse tab structure
         Pill switcher (Pulse / Timeline)
         Default: Pulse view
Step 32: Entry point from Pulse to Timeline
         Switching animation
Step 33: Check-in entry point on Pulse screen
         Banner when not completed, disappears after
Step 34: [Refresh] button on pulse screen
         Rate-limited recompute trigger

PHASE 8 — NOTIFICATIONS
Step 35: Sunday check-in reminder (OneSignal, 7pm local)
Step 36: Pulse score updated notification
         "Your pulse score has been updated" → opens Pulse tab
Step 37: Partner logged a moment notification
         "[Name] logged a moment" → opens Timeline
         (send only for milestone, highlight, first, anniversary
          NOT for conflicts — too sensitive to notify about)
```

---

## 10. OPEN QUESTIONS

```
[NEEDS DECISION] Conflict moment notifications
  The build order says do NOT notify partner when a conflict
  is logged. This is recommended for sensitivity reasons —
  "Jordan just logged a conflict" is an uncomfortable
  notification to receive mid-day.
  But some teams prefer full transparency.
  Confirm: no notification for conflict events. Yes or no?
  Current spec: NO notification for conflicts.

[OPEN] Pulse score visibility
  Both partners see the same pulse score (same numbers).
  Confirm this is correct before Step 28.
  The alternative would be personal pulse scores
  (each person sees their own dimension scores).
  Current spec: shared — both see same score.

[OPEN] Check-in — both partners required?
  Currently: check-in from either partner improves the score.
  Check-in from both gives a more complete picture.
  Should there be a visual indicator showing whether
  both partners have completed this week's check-in?
  Suggested: yes — show "You ✓  Jordan ✗" on the
  check-in banner. Does not reveal Jordan's answers,
  just shows completion status.
  Confirm before Step 18.

[OPEN] On-demand recompute rate limit
  Set at once per 24 hours.
  If this feels too restrictive, can lower to once per 4 hours.
  Confirm before Step 22.

[FUTURE — not in this spec]
  When chat AI pipeline is built:
  Add message analysis data to Communication and
  Conflict Health dimensions.
  The schema and algorithm are ready to accept this —
  just add the data fetch in computePulseScore.

  When games are built:
  Add game completion data to Connection and Alignment.
  Same pattern — add data fetch, update weights.
```

---

*This spec is complete and ready for DeepSeek implementation.*
*Build Part A (Timeline) before Part B (Pulse Score).*
*The timeline produces data that the pulse score consumes.*
*Build in the exact order defined in Section 9.*
*Review against ATTUNE_SOUL.md before shipping.*
*No streaks. No streak notifications. No streak counters.*
*Last reviewed: June 2026*
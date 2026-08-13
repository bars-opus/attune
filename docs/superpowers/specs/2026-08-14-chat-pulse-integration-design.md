# Chat Analysis → Pulse Score Integration — Design

Date: 2026-08-14

## Problem

Two chat-message analysis pipelines are fully built and running in
production but produce output nothing consumes: `analyse-message`
(per-message: `tone_score`, `nvc_violations`, `bid_type`, written onto
`messages` rows, auto-triggered on every send) and `analyse-session`
(per-conversation-burst: `escalation_score`, `repair_attempted`,
`repair_landed`, `stonewalling_signals`, `pursue_withdraw_detected`, and
more, written to `analysis_sessions`). `compute-pulse` — the weekly
relationship-health score both partners see — reads only
`timeline_events`, `weekly_checkins`, and attachment-quiz completion.
`PULSE.md` §5 always intended chat data to feed Pulse ("Chat AI analysis
→ Communication and Conflict Health... these are architecture hooks...
accept these inputs when the features are built later") and §7's
`data_confidence` system explicitly reserves `'high'` confidence for
relationships with chat data ("requires chat AI pipeline"). The hook was
never built. This spec builds it.

## Pre-existing bugs fixed as part of this work

Both are in `compute-pulse`, both are pre-existing (not introduced by
chat-wiring), both block this feature from being verifiable if left
broken:

1. **`force_recompute` silently fails on the second call in a week.**
   `_computePulseScore` skips the existence check when `force_recompute:
   true` and does a bare `.insert()` against `pulse_scores`, which has a
   `UNIQUE (relationship_id, week_ending)` constraint. The insert's
   result is never checked. Both the `[Refresh]` button and the
   both-partners-submitted-checkin trigger pass `force_recompute: true`
   — so the second time either fires in the same week, the write fails
   silently while the caller believes it succeeded. Fix: use `upsert`
   with `onConflict: 'relationship_id,week_ending'` instead of `insert`,
   and check/surface the result.
2. **The confidence rollup doesn't match `PULSE.md` §4.3's own spec.**
   Spec: `highCount >= 4 ? 'high' : mediumCount >= 3 ? 'medium' :
   mediumCount >= 1 ? 'low' : 'none'`. Shipped code has no `'high'`
   branch at all, and uses `lowCount >= 3 ? 'low' : 'none'` instead of
   `mediumCount >= 1 ? 'low' : 'none'` — meaning `'none'` is nearly
   unreachable (every dimension starts at `'low'`, so `lowCount >= 3` is
   true almost immediately), so the "not enough data yet" empty state
   effectively never renders. Fix: restore the spec's exact rollup
   thresholds.

## Confidence model: rewrite as evidence-points, not a slot-in

The five current per-dimension confidence rules are five unrelated ad
hoc heuristics (`checkins.length >= 2`, `positiveEvents > 0`,
`conflicts.length >= 2`, a boolean, `allEventsWithMood.length >= 3`) that
throw away *provenance* — there's no way to express "this reached medium
via check-ins" vs "via chat," which is required to implement §7's "high
requires chat" rule. This can't be a small addition to the existing
pattern; the pattern itself needs to become provenance-aware.

Replace with a shared evidence-points model, one function reused by all
five dimensions:

```ts
// Points contributed by each source, capped so no single source alone
// reaches 'high'.
const EVIDENCE = {
  checkin: (n: number) => Math.min(n, 2) * 2,              // 0, 2, or 4
  timelineEvents: (n: number) => Math.min(n, 4) * 1,        // 0..4
  attachmentBoth: (b: boolean) => (b ? 3 : 0),
  analysedMessages: (n: number) =>
    Math.min(Math.floor(n / 10), 3) * 1.5,                  // 0..4.5
  analysedSessions: (n: number) => Math.min(n, 4) * 1.5,     // 0..6
};

function confidenceFrom(points: number, hasChatSignal: boolean): Confidence {
  if (points < 2) return 'none';
  if (points < 5) return 'low';
  if (points < 9) return 'medium';
  return hasChatSignal ? 'high' : 'medium'; // 'high' requires chat, per §7
}
```

`hasChatSignal` is `chatWeight > 0.5` (see the coverage ramp below) — a
relationship with lots of timeline/check-in data but no chat caps at
`'medium'`, matching §7's stated intent exactly.

The overall rollup is restored to `PULSE.md`'s exact spec (see bug fix
#2 above) — this is the same fix, not a separate one, since the rollup
consumes these same five per-dimension values.

## Signal-to-dimension mapping

All chat aggregates are computed over the same 30-day window the
existing timeline-event code already uses (`thirtyDaysAgo`), for
consistency, and are **rates, never raw counts** — chat volume isn't
deliberate the way logging a timeline event is, so raw counts would let
a chattier couple's score swing on volume alone rather than behavior.

### Aggregates (computed once, reused across dimensions)

```ts
// messages: relationship_id match, message_analysis_done = true,
// created_at >= thirtyDaysAgo. Select only tone_score, nvc_violations,
// bid_type, created_at — never select(*) (see Performance below).
const analysedCount = messages.length;
const tonedMessages = messages.filter((m) => m.tone_score != null);
const avgTone = tonedMessages.length
  ? mean(tonedMessages.map((m) => m.tone_score))
  : null; // -1..1

// nvc_violations is jsonb, nullable, not guaranteed to be an array for
// rows written before analyse-message's markMessageDone guarantee —
// always validate, never trust `?? []` alone.
const violationsOf = (m) => (Array.isArray(m.nvc_violations) ? m.nvc_violations : []);
const violationCount = sum(messages.map((m) => violationsOf(m).length));
const violationRate = analysedCount ? violationCount / analysedCount : null;
const severeCount = sum(
  messages.map(
    (m) => violationsOf(m).filter((v) => v === 'contempt' || v === 'character_attack').length,
  ),
);
const severeRate = analysedCount ? severeCount / analysedCount : null;

const bidsTotal = messages.filter((m) => m.bid_type != null).length;
const bidsToward = messages.filter((m) => m.bid_type === 'toward').length;
const bidTurnRate = bidsTotal >= 5 ? bidsToward / bidsTotal : null; // floor: 5

// analysis_sessions: relationship_id match, started_at >= thirtyDaysAgo,
// escalation_score IS NOT NULL (the "layer 2 actually completed" marker).
const sessions = allSessions.filter((s) => s.escalation_score != null);
const sessionCount = sessions.length;
const avgEscalation = sessionCount ? mean(sessions.map((s) => s.escalation_score)) : null;
const conflictSessions = sessions.filter((s) => s.escalation_score >= 0.5);
const repairRate = conflictSessions.length
  ? conflictSessions.filter((s) => s.repair_landed).length / conflictSessions.length
  : null;
const attemptRate = conflictSessions.length
  ? conflictSessions.filter((s) => s.repair_attempted).length / conflictSessions.length
  : null;
const stonewallRate = sessionCount
  ? sessions.filter((s) => s.stonewalling_signals).length / sessionCount
  : null;
const pursueWithdrawRate = sessionCount
  ? sessions.filter((s) => s.pursue_withdraw_detected).length / sessionCount
  : null;
```

`pursuer` (`'user_a' | 'user_b' | null` on `analysis_sessions`) is
**never read** anywhere in `compute-pulse`. It's a per-partner
attribution; even indirect influence on a shared score via this field is
a real privacy risk this spec explicitly avoids (see Privacy section).

### Coverage ramp — `chatWeight`, applied to every chat adjustment

```ts
const firstAnalysedAt = tonedMessages.length
  ? new Date(Math.min(...messages.map((m) => new Date(m.created_at).getTime())))
  : null;
const coverageDays = firstAnalysedAt
  ? Math.min(30, (Date.now() - firstAnalysedAt.getTime()) / 86_400_000)
  : 0;
const coverage = coverageDays / 30; // 0..1

// Below 25% coverage (~7.5 days), chat contributes nothing at all —
// prevents a phantom score swing the week the feature/chat activity
// first appears. Ramps linearly to full strength by 75% coverage
// (~22.5 days), so influence eases in over roughly three weeks rather
// than switching on.
const chatWeight = coverage < 0.25 ? 0 : Math.min((coverage - 0.25) / 0.5, 1);
```

**Backlog gate**: if the count of messages with `message_analysis_done =
true AND included_in_session_id IS NULL` for this relationship exceeds
50, force `chatWeight = 0` for that computation — the session-analysis
sweep is behind, and scoring on a known-incomplete picture is worse than
scoring on none. This is a cheap, indexed count query (see Performance),
not a fetch of the messages themselves.

`hasChatSignal` (feeds the confidence model above) is `chatWeight > 0.5`
— confidence should not promote to `'high'` on barely-ramped-in data
either.

### Per-dimension formulas

All floors below apply on top of `chatWeight > 0` — if `chatWeight` is
0, no chat adjustment fires regardless of floors.

**Communication:**

```ts
let communication = 50; // existing baseline, unchanged
// ...existing check-in/conflict-event logic runs first, unchanged...

if (avgTone != null && analysedCount >= 10) {
  const toneAdj = avgTone * 10; // -10..+10
  communication = clamp(communication + toneAdj * chatWeight, 0, 100);
}
if (violationRate != null && analysedCount >= 10) {
  const nvcPenalty = Math.min(violationRate / 0.2, 1) * 12;
  communication = clamp(communication - nvcPenalty * chatWeight, 0, 100);
}
if (stonewallRate != null && sessionCount >= 3) {
  communication = clamp(communication - stonewallRate * 10 * chatWeight, 0, 100);
}
```

**Connection:**

```ts
// ...existing milestone/highlight/anniversary logic runs first, unchanged...
if (bidTurnRate != null) {
  // 0.5 is neutral (half of bids landing toward is baseline).
  connection = clamp(connection + (bidTurnRate - 0.5) * 24 * chatWeight, 0, 100); // ±12
}
```

**Conflict Health** — restructured as an explicit weighted blend of
available sources, replacing the current overwrite-then-average chain
(mood overwrites the 70 baseline; check-in then averages against
whatever mood produced; a naively-appended chat term would depend on
evaluation order in a way nobody could reason about):

```ts
const sources: { v: number; w: number }[] = [];
if (validMoods.length > 0) sources.push({ v: avgMood * 10, w: 1.0 });
if (validCheckins.length > 0) sources.push({ v: checkinScore, w: 1.0 });
if (repairRate != null && conflictSessions.length >= 2) {
  const repairBonus = repairRate * 12 + (attemptRate - repairRate) * 3;
  sources.push({ v: 70 + repairBonus, w: 0.8 * chatWeight }); // weighted below human sources
}
if (avgEscalation != null && sessionCount >= 3) {
  // Centered at 0.4, not 0 — some escalation is normal; Conflict Health
  // measures repair quality, not conflict absence (PULSE.md §4.1).
  sources.push({ v: 70 - (avgEscalation - 0.4) * 50, w: 0.8 * chatWeight });
}
conflictHealth = sources.length ? Math.round(weightedMean(sources)) : 70;
```

**Emotional Safety:**

```ts
// ...existing mood-average logic runs first, unchanged...
if (severeRate != null && analysedCount >= 10) {
  // Contempt/character-attack get their own, harsher curve here — this
  // is a deliberate double-count with Communication's violationRate
  // above. Contempt genuinely damages both clarity and safety; see
  // Design Notes for why this is intentional, not an oversight.
  const safetyPenalty = Math.min(severeRate / 0.1, 1) * 12;
  emotionalSafety = clamp(emotionalSafety - safetyPenalty * chatWeight, 0, 100);
}
if (pursueWithdrawRate != null && sessionCount >= 3) {
  emotionalSafety = clamp(emotionalSafety - pursueWithdrawRate * 8 * chatWeight, 0, 100);
}
```

**Alignment**: no chat signal maps to it. Left entirely unchanged —
`PULSE.md` §4.1 already names games data (Sliding Scale, 36 Questions)
as Alignment's future source, not chat.

### Explicitly excluded signals

| Signal | Why excluded |
|---|---|
| `pursuer` | Named per-partner attribution. Never read, anywhere in this feature. |
| `root_need_detected` | No inherent valence (a detected need isn't good or bad) — any score mapping would require inventing a value judgment about which human needs are "better." |
| `escalation_trajectory` | Weak signal: `'peaked'` is ambiguous (peaked-then-resolved vs. peaked-and-ongoing), and it's highly correlated with `escalation_score` and `session_resolved` already in use. |
| `session_resolved` | Overlaps `repair_landed` almost completely — a session where repair landed is nearly always resolved. Keeping both would double-count without adding signal. |
| Layer 4 `patterns` (pattern_type/topic_cluster/severity) | Free-text, LLM-generated, unbounded value space — unreviewable as a score input. `severity: 'safety'` implies a product surface (safety escalation) far beyond a score nudge. This is a distinct future feature (surfacing named patterns to users), not a Pulse input. |
| `sentiment` (on `messages`) | A plausible Connection signal, but deferred to v2 to keep this version's signal set small enough to validate end-to-end. |

## Trigger architecture: loose coupling

`compute-pulse` never calls `analyse-session`. It only reads
`analysis_sessions` as an ordinary data source, exactly like
`timeline_events`. `analyse-session` keeps its own independent schedule.

**This work includes actually registering that schedule** — the
existing `supabase/sql/schedule_analyse_session.sql` is an operator-run
script, not a migration, and cannot be confirmed to have ever been
executed against the live project. This spec converts it into a proper
migration so the cron registration is deployed the same way everything
else in this codebase is (`cron.schedule('analyse-session-sweep', '7,37
* * * *', ...)`), removing the operator-script dependency entirely.

**Why not tight coupling** (`compute-pulse` calling `analyse-session`
directly before scoring): `analyse-session` makes up to 2 sequential
Claude calls per unanalyzed session, inside a loop over segments, inside
a loop over relationships — nesting that inside `compute-pulse`'s own
serial loop over all active relationships would make the weekly cron's
runtime unbounded, and would blow the `[Refresh]` button's latency
budget (`pulse_providers.dart`'s `recomputePulseProvider`, called
synchronously from the UI). It would also require building retry logic
against `analyse-session`'s current flat, uncategorized `500` error
response — there's no way today to distinguish "transient, retry" from
"permanent, don't retry" from that function's output.

**Staleness bound, stated explicitly** (Algorithm Quality Review
Checklist v3.1 item 1.9, consistency model): a Pulse score computed at
time T reflects chat sessions that went quiet (30-minute inactivity
boundary) more than roughly 30 minutes before T, since the sweep runs
twice hourly. Worst case ~60 minutes of staleness against a 30-day
scoring window — 0.14% of the window, immaterial. This bound is
documented in the compute-pulse code as a comment, not just this spec.

## Privacy: name the source, never the cause

Chat message content is already mutually visible to both partners — but
the AI's *judgment* about that content (this message was `contempt`,
this session had `pursue_withdraw_detected`) is new information neither
partner had access to before. A score movement that's traceable to that
judgment functionally hands one partner a system-authored assessment of
the other's specific words — which is precisely what the analysis
pipelines' own `GLOBAL_CONSTRAINTS` already forbid the AI from writing
directly in generated text. A silent number movement must not do the
same thing sideways.

**Rule: the UI may name chat as a data *source*. It may never explain a
score *change* in terms of chat-derived signal, ever, in any current or
future feature.**

Allowed (extends the existing dimension tooltip,
`pulse_screen.dart:346`'s `_showDimensionTooltip`, from "Communication is
based on your weekly check-in" to):

> "Communication reflects your weekly check-ins, logged moments, and
> patterns in your conversations."

Never build (regardless of how it's phrased or how indirect):

> "Your Communication score dropped because of harsh language detected
> in your messages this week."

This means: no "why did my score change" feature is ever built for
chat-derived signal. This is a permanent constraint on this feature, not
a v1 scope note.

**Concrete mitigations:**

- `pursuer` is never read (already covered above).
- Raw aggregates (`violationRate`, `severeCount`, `avgEscalation`, etc.)
  never reach any client-visible surface — not the main UI, not a debug
  screen, not an API response. If stored for tuning/observability, they
  go in a column **not covered by `pulse_scores`' existing RLS SELECT
  policy** (`pulse_scores_relationship_members` currently grants SELECT
  on the whole row to both partners — a naively-added diagnostic column
  would be exposed by default). Store diagnostics in a separate
  service-role-only table (`pulse_score_diagnostics`), not as a new
  column on `pulse_scores`.
- `delta_vs_previous` (the up/down arrows shown prominently in the UI,
  and the trigger for the "your pulse score has been updated"
  notification) is naturally damped by the `chatWeight` ramp — the week
  chat data first ramps in, its contribution to any single week's delta
  is capped by `chatWeight`, which starts at 0 and rises slowly. No
  additional delta cap is needed beyond the ramp itself, since the ramp
  already bounds week-over-week chat-attributable movement to a small
  fraction of the signal's full ±12-point range during the ramp-in
  period.

**Deferred, not built now:** a per-relationship "use my chat for Pulse
scoring" opt-out toggle. It's the principled long-term answer to the
attribution concern above, but it requires both partners to agree (a
one-sided disable is itself a signal), needs its own UI, and a
partner-asymmetric disabled state would break the shared-score
invariant `PULSE.md` §10 already settled. The schema here doesn't
preclude adding it later — "no chat signal" is already a fully
first-class, tested state (see Testing).

## Performance (Algorithm Quality Review Checklist v3.1, item 2.14)

Never `select('*')` on `messages` inside the per-relationship loop — a
couple sending 200 messages/day generates ~6,000 rows in a 30-day
window, and fetching full rows for every active relationship in a
single serial cron pass is an unbounded-memory risk. Select only
`tone_score, nvc_violations, bid_type, created_at`, and push the
aggregation into a Postgres RPC (`compute_relationship_chat_signals(relationship_id,
window_start)` returning one pre-aggregated row) rather than pulling raw
rows into the edge function and aggregating in JS. This is the same
shape as the existing `getEventsForMonth`-style repository pattern
already used elsewhere in this codebase — push aggregation to the
database, fetch one row per relationship.

The backlog-gate count query (`message_analysis_done = true AND
included_in_session_id IS NULL`) hits the existing partial index
`idx_messages_session_backlog` and is effectively free.

## Testing

- **No-op proof (the safety net for this whole feature):** run
  `compute-pulse` against a fixture with zero `messages`/
  `analysis_sessions` rows and assert every dimension score and the
  confidence values are byte-identical to the pre-chat-integration
  implementation's output on the same fixture. This is the test that
  proves the feature cannot regress a relationship that doesn't use
  chat.
- Coverage ramp: `chatWeight` at 0%, 10%, 25% (boundary), 50%, 75%
  (boundary), 100% coverage — assert 0/0/0/partial/full/full.
- Backlog gate: `chatWeight` forced to 0 when pending-analysis count
  exceeds 50, even with high coverage otherwise.
- Mid-analysis state (`analysedCount > 0, sessionCount === 0`):
  message-level adjustments apply, session-level ones don't — this is
  the most common real-world state (Layer 1 runs every message; Layer 2
  runs on a 30-90 minute delay) and the easiest state for an
  implementation to accidentally break via a shared guard.
- `nvc_violations` edge cases: `null`, non-array jsonb, empty array, and
  a row predating `analyse-message`'s array guarantee — all must not
  throw and must contribute 0 to `violationRate`.
- Confidence: `'high'` is reachable given sufficient timeline + check-in
  + chat evidence; `'high'` is capped at `'medium'` given sufficient
  timeline + check-in evidence alone (no chat) — this is the test that
  proves §7's "high requires chat" rule actually holds.
- `force_recompute` called twice in the same week: second call
  overwrites (not silently fails) — proves the `upsert` fix.
- Confidence rollup matches `PULSE.md` §4.3 exactly at all four
  boundary conditions (`highCount>=4`, `mediumCount>=3`,
  `mediumCount>=1`, none of the above).
- Privacy: a test asserting no chat-derived raw aggregate (violation
  rate, escalation score, etc.) appears anywhere in `compute-pulse`'s
  return payload or in any column covered by `pulse_scores`' existing
  RLS SELECT policy.

## Algorithm Quality Review Checklist v3.1 — scoping and gate

Scope tags: `[SERVICE]` (Supabase Edge Function) `[ASYNC]` (cron-invoked)
`[MUTATION]` (writes `pulse_scores`). Not `[MOBILE]`/`[UI]` directly —
the client-side tooltip-copy change is a small, separate `[UI]`-tagged
follow-up, not the core of this spec.

- **1.9 (P2, consistency model)**: documented above (staleness bound,
  ~60 min against a 30-day window).
- **1.11 (P1, data privacy)**: the Privacy section above is this
  feature's primary data-privacy assessment — PII here is specifically
  *AI-derived judgments about message content*, a category the existing
  checklist's PII glossary doesn't explicitly name but which this spec
  treats with equivalent care.
- **2.14 (P1, memory growth bounds)**: covered under Performance —
  column-selected fetches, RPC-based aggregation, no raw-row loops.
- **2.17 (P2, side-effect isolation)**: the confidence-points model and
  all per-dimension formulas are pure functions taking pre-fetched
  aggregates as input — no I/O inside the scoring math itself, making
  the 6.7 branch-coverage target achievable.
- **3.9/3.10 (retry logic)**: N/A, explicitly skipped with
  justification — `compute-pulse` makes no synchronous calls to
  `analyse-session` or any other function; the loose-coupling
  architecture eliminates the retry-classification problem entirely
  rather than solving it.
- **5.2 (P2, p95 latency for the `[Refresh]` button)**: preserved by
  loose coupling — `compute-pulse`'s Supabase-client-only read/write
  profile is unchanged in kind by this feature, only in the columns it
  reads.
- **6.1 (P1, edge cases)**: the full Testing section above.
- **1.6 (P1, concurrency)**: the `force_recompute` upsert fix directly
  addresses the concurrent-trigger risk (cron + `[Refresh]` +
  both-checkins-submitted can all fire in the same week).

## Out of scope for this spec

- Layer 4 pattern-memory surfacing (a distinct, larger feature about
  showing named relationship patterns to users — not a score input).
- `sentiment` → Connection (deferred to v2).
- Per-relationship chat-scoring opt-out toggle (deferred; schema doesn't
  preclude it later).
- Any "why did my score change" explanation UI (permanently excluded,
  not deferred — see Privacy).
- Games-data → Connection/Alignment (a separate, already-named future
  integration per `PULSE.md` §5).

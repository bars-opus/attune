// supabase/functions/compute-pulse/index.ts
//
// Pulse (Spec 1a Task 7; PULSE.md §11 ruling). The four SHARED dimensions
// come from shared moments, chat aggregates and games only; private check-in
// answers never enter them, their deltas or their confidence. Emotional
// safety is computed per member into pulse_private_scores (auth.uid()-only
// RLS). The caller must be a member of an ACTIVE relationship (or the
// service role, which the weekly cron uses); a forced recompute is limited
// to one per relationship per 24 h by claim_pulse_recompute.

import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { relationshipAiSuppressed } from '../_shared/ai_suppression.ts'
import { hostilitySignalsEnabled } from '../_shared/hostility_signals.ts'
import { constantTimeEqual } from '../_shared/attune_auth.ts'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

export interface RelationshipRow {
  id: string
  user_a: string | null
  user_b: string | null
  status: string
}

interface ClaimRow {
  granted: boolean
  retry_after_seconds: number
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}

function bearerToken(req: Request): string {
  return (req.headers.get('Authorization') ?? '').replace(/^Bearer\s+/i, '').trim()
}

/// A user may recompute only a relationship they belong to and that is
/// active. Paused/ended/missing/not-mine all read the same to the caller.
export function callerMayRecompute(
  callerId: string,
  rel: RelationshipRow | null | undefined,
): boolean {
  if (!rel || rel.status !== 'active') return false
  return rel.user_a === callerId || rel.user_b === callerId
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const supabase = createClient(Deno.env.get('SUPABASE_URL')!, serviceKey)

    const body = await req.json().catch(() => ({}))
    const relationshipId =
      typeof body?.relationship_id === 'string' ? body.relationship_id : null
    const forceRecompute = body?.force_recompute === true

    const token = bearerToken(req)
    // Constant time (checklist 2.3): the cron's token is the service key.
    const isService = token.length > 0 && constantTimeEqual(token, serviceKey)

    let relationships: RelationshipRow[]
    if (isService) {
      // The weekly cron (invoke_edge_function) and operators: one or all.
      let query = supabase
        .from('relationships')
        .select('id, user_a, user_b, status')
        .eq('status', 'active')
      if (relationshipId) query = query.eq('id', relationshipId)
      const { data } = await query
      relationships = (data ?? []) as RelationshipRow[]
    } else {
      if (!token) return json({ error: 'Not authenticated' }, 401)
      const { data: auth, error: authError } = await supabase.auth.getUser(token)
      if (authError || !auth?.user) return json({ error: 'Not authenticated' }, 401)
      if (!relationshipId) return json({ error: 'relationship_id is required' }, 400)

      const { data: rel } = await supabase
        .from('relationships')
        .select('id, user_a, user_b, status')
        .eq('id', relationshipId)
        .maybeSingle()
      if (!callerMayRecompute(auth.user.id, rel as RelationshipRow | null)) {
        // One answer for "not yours", "paused" and "does not exist".
        return json({ error: 'Not found' }, 404)
      }
      if (forceRecompute) {
        const { data: claim, error: claimError } = await supabase.rpc('claim_pulse_recompute', {
          p_relationship_id: relationshipId,
          p_user_id: auth.user.id,
        })
        if (claimError) throw claimError
        const row = (claim as ClaimRow[] | null)?.[0]
        if (!row?.granted) {
          return new Response(
            JSON.stringify({
              error: 'rate_limited',
              retry_after_seconds: row?.retry_after_seconds ?? 86400,
            }),
            { status: 429, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
          )
        }
      }
      relationships = [rel as RelationshipRow]
    }

    const weekEnding = getWeekEnding(new Date())
    const results = []
    for (const relationship of relationships) {
      const pulseScore = await _computePulseScore(supabase, relationship, weekEnding, {
        isService,
        force: forceRecompute,
      })
      if (pulseScore) results.push({ ...pulseScore })
    }

    return json({ success: true, computed: results.length, results })
  } catch (error) {
    // Only the error's name: a Postgrest message can quote row contents
    // (checklist 4.4 / 5.5).
    console.error('compute-pulse failed:', error instanceof Error ? error.name : typeof error)
    return json({ error: 'Could not compute pulse scores' }, 500)
  }
})

/// Service-role runs (the weekly cron) always write the shared row: a forced
/// mid-week refresh creates this week's row early, and a "skip if it exists"
/// guard would turn the Sunday run into a no-op (Review Focus 9). A granted
/// force rewrites it too. A user's non-forced call (the check-in submit)
/// never writes it -- not even to create a missing week, since that row's
/// computed_at would tell the partner when the private check-in happened --
/// and only refreshes the private pass.
export function shouldComputeShared(isService: boolean, force: boolean): boolean {
  return isService || force
}

async function _computePulseScore(
  supabase: any,
  relationship: RelationshipRow,
  weekEnding: Date,
  opts: { isService: boolean; force: boolean },
) {
  const relationshipId = relationship.id
  const weekKey = weekEndingKey(weekEnding)

  // ──────────────────────────────────────────────────────────
  // FETCH THE SHARED DATA SOURCES (no private answers in here)
  // ──────────────────────────────────────────────────────────

  // 1. Timeline events (last 30 days for scoring)
  const thirtyDaysAgo = new Date()
  thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30)

  const { data: timelineEvents }: { data: any[] | null } = await supabase
    .from('timeline_events')
    .select('*')
    .eq('relationship_id', relationshipId)
    // A private conflict never feeds the couple's shared score (Phase 4 R1).
    .eq('visibility', 'shared')
    .gte('occurred_at', thirtyDaysAgo.toISOString().split('T')[0])
    .is('deleted_at', null)

  // The shared mood base, reused by the private pass.
  const allEventsWithMood = timelineEvents?.filter(e => e.mood_score) || []
  const moodBase = allEventsWithMood.length > 0
    ? Math.round(
        (allEventsWithMood.reduce((sum, e) => sum + e.mood_score, 0) / allEventsWithMood.length) * 10,
      )
    : null

  // 2. Chat signal aggregates (last 30 days), via the pre-aggregating RPC
  // — never select(*) raw messages/sessions rows into this function
  // (Algorithm Quality Review Checklist v3.1 item 2.14).
  const { data: chatSignalRows } = await supabase
    .rpc('compute_relationship_chat_signals', {
      p_relationship_id: relationshipId,
      p_window_start: thirtyDaysAgo.toISOString(),
    })
  const chatRow = chatSignalRows?.[0] ?? null

  const rawChatSignals: ChatSignals = {
    analysedCount: chatRow?.analysed_count ?? 0,
    avgTone: chatRow?.avg_tone ?? null,
    violationRate: chatRow?.violation_rate ?? null,
    severeRate: chatRow?.severe_rate ?? null,
    bidTurnRate: chatRow?.bid_turn_rate ?? null,
    bidsTotal: chatRow?.bids_total ?? 0,
    sessionCount: chatRow?.session_count ?? 0,
    conflictSessionCount: chatRow?.conflict_session_count ?? 0,
    avgEscalation: chatRow?.avg_escalation ?? null,
    repairRate: chatRow?.repair_rate ?? null,
    attemptRate: chatRow?.attempt_rate ?? null,
    stonewallRate: chatRow?.stonewall_rate ?? null,
    pursueWithdrawRate: chatRow?.pursue_withdraw_rate ?? null,
  }

  const { data: gameSignalRows } = await supabase
    .rpc('compute_relationship_game_signals', {
      p_relationship_id: relationshipId,
      p_window_start: thirtyDaysAgo.toISOString(),
    })
  const gameRow = gameSignalRows?.[0] ?? null

  const gameSignals: GameSignals = {
    sessionsCompleted: gameRow?.sessions_completed ?? 0,
    slidingScalePairs: gameRow?.sliding_scale_pairs ?? 0,
    slidingScaleAvgGap: gameRow?.sliding_scale_avg_gap ?? null,
    mirrorRoundsScored: gameRow?.mirror_rounds_scored ?? 0,
  }

  // Spec 8 (plan review I12, I14): a suppressed couple reads exactly as one
  // with no chat data; stonewalling and contempt only behind their flag.
  const [suppressed, hostilitySignals] = await Promise.all([
    relationshipAiSuppressed(supabase, relationshipId),
    hostilitySignalsEnabled(supabase),
  ])
  const gatedChat = gateChatInputs(
    {
      signals: rawChatSignals,
      coverageDays: chatRow?.first_analysed_at
        ? Math.min(30, (Date.now() - new Date(chatRow.first_analysed_at).getTime()) / 86_400_000)
        : 0,
      pendingBacklog: chatRow?.pending_backlog_count ?? 0,
    },
    { suppressed, hostilitySignals },
  )
  const chatSignals = gatedChat.signals
  const pendingBacklog = gatedChat.pendingBacklog
  const coverageDays = gatedChat.coverageDays

  // Backlog gate: if the session-analysis sweep is more than 50 messages
  // behind, treat chat as having zero weight this run rather than score
  // on a known-incomplete picture.
  const chatWeight = pendingBacklog > 50 ? 0 : computeChatWeight(coverageDays)
  const hasChatSignal = chatWeight > 0.5

  // A check-in submit calls this non-forced: only the private pass runs, so
  // "Your week" fills in without creating or touching the shared row or the
  // caller's claim. The cron (service role) and a granted force fall through
  // and write the shared row.
  if (!shouldComputeShared(opts.isService, opts.force)) {
    await _computePrivateScores(supabase, relationship, weekKey, moodBase, chatSignals, chatWeight)
    return null
  }

  // 3. Attachment quiz completion status
  const { data: userAProfile } = await supabase
    .from('psych_profiles')
    .select('attachment_style')
    .eq('user_id', relationship.user_a)
    .maybeSingle()

  const { data: userBProfile } = await supabase
    .from('psych_profiles')
    .select('attachment_style')
    .eq('user_id', relationship.user_b)
    .maybeSingle()

  // != null: a missing profile row used to read as "completed" (undefined !== null).
  const bothCompletedAttachment =
    userAProfile?.attachment_style != null && userBProfile?.attachment_style != null

  // 4. Previous WEEK's score for deltas. A forced recompute of the current
  // week must diff against last week, never against its own earlier run
  // (spec1-map-f5 §3.2).
  const { data: previousPulse } = await supabase
    .from('pulse_scores')
    .select('*')
    .eq('relationship_id', relationshipId)
    .lt('week_ending', weekKey)
    .order('week_ending', { ascending: false })
    .limit(1)
    .maybeSingle()

  // ──────────────────────────────────────────────────────────
  // COMPUTE THE FOUR SHARED DIMENSIONS
  // ──────────────────────────────────────────────────────────

  // COMMUNICATION
  let communication = 50 // baseline

  const conflicts = timelineEvents?.filter(e => e.event_type === 'conflict') || []
  const conflictPenalty = conflicts.length * 3
  communication = clamp(communication - conflictPenalty, 0, 100)

  // Resolved conflicts (mood_score >= 7) give bonus
  const resolvedConflicts = conflicts.filter(c => c.mood_score && c.mood_score >= 7)
  const resolutionBonus = resolvedConflicts.length * 5
  communication = clamp(communication + resolutionBonus, 0, 100)

  // CONNECTION
  const positiveEvents = timelineEvents?.filter(e =>
    e.event_type === 'milestone' || e.event_type === 'highlight'
  ) || []
  let connection = clamp(50 + (positiveEvents.length * 8), 0, 100)

  const anniversaryEvents = timelineEvents?.filter(e => e.event_type === 'anniversary') || []
  if (anniversaryEvents.length > 0) {
    connection = clamp(connection + 15, 0, 100)
  }

  // CONFLICT HEALTH: an explicit weighted blend of the shared sources. Chat
  // sources sit at 0.8 weight, subordinate to the human-logged mood at 1.0.
  const conflictMoods = conflicts.filter(c => c.mood_score).map(c => c.mood_score)
  const avgConflictMood = conflictMoods.length
    ? conflictMoods.reduce((a: number, b: number) => a + b, 0) / conflictMoods.length
    : null

  const conflictSources: { v: number; w: number }[] = []
  if (avgConflictMood != null) conflictSources.push({ v: avgConflictMood * 10, w: 1.0 })
  if (
    chatSignals.repairRate != null &&
    chatSignals.attemptRate != null &&
    chatSignals.conflictSessionCount >= 2
  ) {
    const repairBonus =
      chatSignals.repairRate * 12 + (chatSignals.attemptRate - chatSignals.repairRate) * 3
    conflictSources.push({ v: 70 + repairBonus, w: 0.8 * chatWeight })
  }
  if (chatSignals.avgEscalation != null && chatSignals.sessionCount >= 3) {
    // Centered at 0.4, not 0 — some escalation is normal; Conflict Health
    // measures repair quality, not conflict absence (PULSE.md §4.1).
    conflictSources.push({ v: 70 - (chatSignals.avgEscalation - 0.4) * 50, w: 0.8 * chatWeight })
  }
  const conflictHealth = conflictSources.length
    ? clamp(Math.round(weightedMean(conflictSources)), 0, 100)
    : 70 // optimistic baseline

  // ALIGNMENT
  let alignment = 50
  if (bothCompletedAttachment) {
    alignment = clamp(alignment + 20, 0, 100)
  }

  // Chat adjustments (coverage-ramped). applyChatSignals also carries the
  // Emotional-safety penalties; here only the two shared outputs are used.
  const chatAdjusted = applyChatSignals(
    { communication, connection, emotionalSafety: 0 },
    chatSignals,
    chatWeight
  )
  communication = chatAdjusted.communication
  connection = chatAdjusted.connection

  // Game signals (§7: Connection <- engagement, Alignment <- values overlap).
  const gameAdjusted = applyGameSignals({ connection, alignment }, gameSignals)
  connection = gameAdjusted.connection
  alignment = gameAdjusted.alignment

  // ──────────────────────────────────────────────────────────
  // PER-DIMENSION CONFIDENCE (evidence-points model, shared sources only:
  // counting a partner's private answer here would publish that they
  // answered — SPEC §11 constraint 10)
  // ──────────────────────────────────────────────────────────
  const communicationPoints =
    Math.min(conflicts.length, 4) * 1 +
    Math.min(Math.floor(chatSignals.analysedCount / 10), 3) * 1.5
  const communicationConfidence = confidenceFrom(communicationPoints, hasChatSignal)

  const connectionPoints =
    Math.min(positiveEvents.length, 4) * 1 +
    Math.min(chatSignals.bidsTotal >= 5 ? 1 : 0, 1) * 4.5 +
    Math.min(gameSignals.sessionsCompleted, 3) * 1
  const connectionConfidence = confidenceFrom(connectionPoints, hasChatSignal)

  const conflictHealthPoints =
    Math.min(conflicts.length, 4) * 1 +
    Math.min(chatSignals.sessionCount, 4) * 1.5
  const conflictHealthConfidence = confidenceFrom(conflictHealthPoints, hasChatSignal)

  const alignmentPoints =
    (bothCompletedAttachment ? 3 : 0) +
    (gameSignals.slidingScalePairs >= 4 ? 2 : 0)
  const alignmentConfidence = confidenceFrom(alignmentPoints, hasChatSignal)

  // OVERALL SCORE (four shared dimensions, weights normalised from 22/22/20/18)
  const overall = overallFromShared({ communication, connection, conflictHealth, alignment })

  const confidences: Confidence[] = [
    communicationConfidence,
    connectionConfidence,
    conflictHealthConfidence,
    alignmentConfidence,
  ]
  const overallConfidence = rollupConfidence(confidences)

  // DELTAS vs the previous week
  let deltas = null
  if (previousPulse) {
    deltas = {
      overall: overall - previousPulse.overall_score,
      communication: communication - previousPulse.communication,
      connection: connection - previousPulse.connection,
      conflict_health: conflictHealth - previousPulse.conflict_health,
      alignment: alignment - previousPulse.alignment,
    }
  }

  // SAVE THE SHARED ROW
  const pulseData = {
    relationship_id: relationshipId,
    week_ending: weekKey,
    overall_score: overall,
    communication,
    connection,
    conflict_health: conflictHealth,
    alignment,
    // Self-facing since Spec 1a: never in the shared row.
    emotional_safety: null,
    data_confidence: overallConfidence,
    dimension_confidence: {
      communication: communicationConfidence,
      connection: connectionConfidence,
      conflict_health: conflictHealthConfidence,
      alignment: alignmentConfidence,
    },
    delta_vs_previous: deltas,
  }

  const { error: upsertError } = await supabase
    .from('pulse_scores')
    .upsert(pulseData, { onConflict: 'relationship_id,week_ending' })

  if (upsertError) {
    console.error('Failed to save pulse score:', upsertError.code ?? 'error')
    throw new Error(`Failed to save pulse score for relationship ${relationshipId}`)
  }

  // Each member's private Emotional safety (self-only table). Also runs on
  // the early-return path above, so it never depends on a shared recompute.
  await _computePrivateScores(supabase, relationship, weekKey, moodBase, chatSignals, chatWeight)

  // Diagnostics: raw chat aggregates for tuning/observability, written to
  // a service-role-only table never exposed to clients. Best-effort.
  const { error: diagnosticsError } = await supabase
    .from('pulse_score_diagnostics')
    .upsert(
      {
        relationship_id: relationshipId,
        week_ending: weekKey,
        chat_weight: chatWeight,
        raw_signals: chatSignals,
      },
      { onConflict: 'relationship_id,week_ending' }
    )
  if (diagnosticsError) {
    console.error('Failed to write pulse score diagnostics (non-fatal):', diagnosticsError.code ?? 'error')
  }

  return pulseData
}

/// The only reader of the check-in table in this function. One row per member
/// who checked in this week, into pulse_private_scores (auth.uid()-only).
async function _computePrivateScores(
  supabase: any,
  relationship: RelationshipRow,
  weekKey: string,
  moodBase: number | null,
  chatSignals: ChatSignals,
  chatWeight: number,
) {
  const { data: checkins }: { data: any[] | null } = await supabase
    .from('weekly_checkins')
    .select('user_id, safety_rating')
    .eq('relationship_id', relationship.id)
    .eq('week_ending', weekKey)

  for (const checkin of checkins ?? []) {
    const score = privateEmotionalSafety({
      moodBase,
      safetyRating: checkin.safety_rating ?? null,
      signals: chatSignals,
      chatWeight,
    })
    if (score == null) continue
    const { error } = await supabase
      .from('pulse_private_scores')
      .upsert(
        {
          relationship_id: relationship.id,
          user_id: checkin.user_id,
          week_ending: weekKey,
          emotional_safety: score,
          computed_at: new Date().toISOString(),
        },
        { onConflict: 'user_id,week_ending' },
      )
    if (error) {
      console.error('Failed to save private pulse score:', error.code ?? 'error')
    }
  }
}

/// The UTC Sunday on or after the UTC date of `date`. A Sunday is its own
/// week ending — the same rule as Dart's pulseWeekEnding, and the one the
/// Sunday 00:07 UTC cron needs (the old `7 - getDay()` made a Sunday roll a
/// whole week forward).
export function getWeekEnding(date: Date): Date {
  const day = new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()))
  const daysToSunday = (7 - day.getUTCDay()) % 7
  day.setUTCDate(day.getUTCDate() + daysToSunday)
  return day
}

export function weekEndingKey(date: Date): string {
  return getWeekEnding(date).toISOString().split('T')[0]
}

export function clamp(value: number, min: number, max: number): number {
  return Math.min(Math.max(value, min), max)
}

/// The shared weights (PULSE.md §4.1 minus Emotional safety), normalised at
/// use: 22/82, 22/82, 20/82, 18/82 ≈ 27 %, 27 %, 24 %, 22 %.
export const SHARED_WEIGHTS = {
  communication: 22,
  connection: 22,
  conflictHealth: 20,
  alignment: 18,
} as const

export interface SharedDimensions {
  communication: number
  connection: number
  conflictHealth: number
  alignment: number
}

export function overallFromShared(d: SharedDimensions): number {
  const total =
    SHARED_WEIGHTS.communication + SHARED_WEIGHTS.connection +
    SHARED_WEIGHTS.conflictHealth + SHARED_WEIGHTS.alignment
  return Math.round(
    (d.communication * SHARED_WEIGHTS.communication +
      d.connection * SHARED_WEIGHTS.connection +
      d.conflictHealth * SHARED_WEIGHTS.conflictHealth +
      d.alignment * SHARED_WEIGHTS.alignment) / total,
  )
}

/// One member's private Emotional safety: the shared mood base (or 50)
/// blended with their own rating, then the chat safety penalties. Null when
/// they have not checked in — there is nothing private to show.
export function privateEmotionalSafety(input: {
  moodBase: number | null
  safetyRating: number | null
  signals: ChatSignals
  chatWeight: number
}): number | null {
  if (input.safetyRating == null) return null
  const base = input.moodBase ?? 50
  const blended = Math.round((base + input.safetyRating * 10) / 2)
  const adjusted = applyChatSignals(
    { communication: 0, connection: 0, emotionalSafety: blended },
    input.signals,
    input.chatWeight,
  )
  return clamp(Math.round(adjusted.emotionalSafety), 0, 100)
}

/**
 * Weighted mean of independent score sources, each `{ v: value, w: weight }`.
 * Zero-weight sources fall out naturally. Returns the 70 optimistic baseline
 * when total weight is zero.
 */
export function weightedMean(sources: { v: number; w: number }[]): number {
  const totalWeight = sources.reduce((sum, s) => sum + s.w, 0)
  if (totalWeight === 0) return 70
  return sources.reduce((sum, s) => sum + s.v * s.w, 0) / totalWeight
}

export function computeChatWeight(coverageDays: number): number {
  const coverage = Math.min(coverageDays, 30) / 30
  if (coverage < 0.25) return 0
  return Math.min((coverage - 0.25) / 0.5, 1)
}

export interface ChatSignals {
  analysedCount: number
  avgTone: number | null
  violationRate: number | null
  severeRate: number | null
  bidTurnRate: number | null
  bidsTotal: number
  sessionCount: number
  conflictSessionCount: number
  avgEscalation: number | null
  repairRate: number | null
  attemptRate: number | null
  stonewallRate: number | null
  pursueWithdrawRate: number | null
}

/** What a couple with no analysed chat looks like. */
export const NO_CHAT_SIGNALS: ChatSignals = {
  analysedCount: 0,
  avgTone: null,
  violationRate: null,
  severeRate: null,
  bidTurnRate: null,
  bidsTotal: 0,
  sessionCount: 0,
  conflictSessionCount: 0,
  avgEscalation: null,
  repairRate: null,
  attemptRate: null,
  stonewallRate: null,
  pursueWithdrawRate: null,
}

export interface ChatInputs {
  signals: ChatSignals
  coverageDays: number
  pendingBacklog: number
}

/**
 * Spec 8 (F15 (1); plan review I12, I14). Suppressed: the no-chat-data
 * inputs, so every confidence and weight reads as sparsity. Hostility off:
 * stonewalling and contempt are dropped.
 */
export function gateChatInputs(
  raw: ChatInputs,
  opts: { suppressed: boolean; hostilitySignals: boolean },
): ChatInputs {
  if (opts.suppressed) {
    return { signals: NO_CHAT_SIGNALS, coverageDays: 0, pendingBacklog: 0 }
  }
  if (opts.hostilitySignals) return raw
  return { ...raw, signals: { ...raw.signals, stonewallRate: null, severeRate: null } }
}

/**
 * The dimensions adjusted by chat signal as relative deltas on an
 * already-computed baseline. emotionalSafety stays in this shape because
 * privateEmotionalSafety reuses the same penalties; the shared path ignores
 * that output.
 */
export interface DimensionState {
  communication: number
  connection: number
  emotionalSafety: number
}

export function applyChatSignals(
  dimensions: DimensionState,
  signals: ChatSignals,
  chatWeight: number
): DimensionState {
  let { communication, connection, emotionalSafety } = dimensions

  if (chatWeight > 0) {
    // COMMUNICATION
    if (signals.avgTone != null && signals.analysedCount >= 10) {
      communication = clamp(communication + signals.avgTone * 10 * chatWeight, 0, 100)
    }
    if (signals.violationRate != null && signals.analysedCount >= 10) {
      const nvcPenalty = Math.min(signals.violationRate / 0.2, 1) * 12
      communication = clamp(communication - nvcPenalty * chatWeight, 0, 100)
    }
    if (signals.stonewallRate != null && signals.sessionCount >= 3) {
      communication = clamp(communication - signals.stonewallRate * 10 * chatWeight, 0, 100)
    }

    // CONNECTION
    if (signals.bidTurnRate != null && signals.bidsTotal >= 5) {
      connection = clamp(connection + (signals.bidTurnRate - 0.5) * 24 * chatWeight, 0, 100)
    }

    // EMOTIONAL SAFETY (private path only)
    if (signals.severeRate != null && signals.analysedCount >= 10) {
      const safetyPenalty = Math.min(signals.severeRate / 0.1, 1) * 12
      emotionalSafety = clamp(emotionalSafety - safetyPenalty * chatWeight, 0, 100)
    }
    if (signals.pursueWithdrawRate != null && signals.sessionCount >= 3) {
      emotionalSafety = clamp(emotionalSafety - signals.pursueWithdrawRate * 8 * chatWeight, 0, 100)
    }
  }

  return { communication, connection, emotionalSafety }
}

export interface GameSignals {
  sessionsCompleted: number
  slidingScalePairs: number
  slidingScaleAvgGap: number | null
  mirrorRoundsScored: number
}

export interface GameDimensionState {
  connection: number
  alignment: number
}

/// Blends game signals into the two dimensions §7 says they belong to.
/// Deliberately does NOT consume mirrorRoundsScored (per-person, §11.1).
export function applyGameSignals(
  dimensions: GameDimensionState,
  signals: GameSignals
): GameDimensionState {
  let { connection, alignment } = dimensions

  if (signals.sessionsCompleted > 0) {
    connection = clamp(connection + Math.min(signals.sessionsCompleted * 2, 10), 0, 100)
  }

  if (signals.slidingScalePairs >= 4 && signals.slidingScaleAvgGap != null) {
    const maxGap = 9
    const clampedGap = Math.max(0, Math.min(maxGap, signals.slidingScaleAvgGap))
    const delta = ((maxGap / 2 - clampedGap) / (maxGap / 2)) * 15
    alignment = clamp(alignment + delta, 0, 100)
  }

  return { connection, alignment }
}

export type Confidence = 'none' | 'low' | 'medium' | 'high'

export function confidenceFrom(points: number, hasChatSignal: boolean): Confidence {
  if (points < 2) return 'none'
  if (points < 5) return 'low'
  if (points < 9) return 'medium'
  // 'high' requires chat signal per PULSE.md §7.
  return hasChatSignal ? 'high' : 'medium'
}

/// Fraction-based so it reads the same for four shared dimensions as it did
/// for five: ≥ 3/4 high → high; ≥ 1/2 medium → medium; any medium → low.
export function rollupConfidence(confidences: Confidence[]): Confidence {
  const n = confidences.length
  if (n === 0) return 'none'
  const highCount = confidences.filter((c) => c === 'high').length
  const mediumCount = confidences.filter((c) => c === 'medium').length
  if (highCount / n >= 0.75) return 'high'
  if (mediumCount / n >= 0.5) return 'medium'
  if (mediumCount >= 1) return 'low'
  return 'none'
}

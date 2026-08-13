// supabase/functions/compute-pulse/index.ts

import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    )

    const { relationship_id, force_recompute } = await req.json().catch(() => ({}))
    const weekEnding = getWeekEnding(new Date())

    // Get all active relationships
    let relationships: any[]
    if (relationship_id) {
      const { data } = await supabase
        .from('relationships')
        .select('id, user_a, user_b')
        .eq('id', relationship_id)
        .eq('status', 'active')
      relationships = data || []
    } else {
      const { data } = await supabase
        .from('relationships')
        .select('id, user_a, user_b')
        .eq('status', 'active')
      relationships = data || []
    }

    const results = []
    for (const relationship of relationships) {
      const pulseScore = await _computePulseScore(supabase, relationship.id, weekEnding, force_recompute)
      if (pulseScore) {
        results.push({ relationship_id: relationship.id, ...pulseScore })
      }
    }

    return new Response(
      JSON.stringify({ success: true, computed: results.length, results }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  } catch (error) {
    console.error('Error:', error.message)
    return new Response(
      JSON.stringify({ error: error.message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})

async function _computePulseScore(
  supabase: any,
  relationshipId: string,
  weekEnding: Date,
  forceRecompute: boolean
) {
  // Check if already computed for this week
  if (!forceRecompute) {
    const { data: existing } = await supabase
      .from('pulse_scores')
      .select('id')
      .eq('relationship_id', relationshipId)
      .eq('week_ending', weekEnding.toISOString().split('T')[0])
      .maybeSingle()

    if (existing) return null
  }

  // ──────────────────────────────────────────────────────────
  // FETCH ALL DATA SOURCES
  // ──────────────────────────────────────────────────────────

  // 1. Timeline events (last 30 days for scoring)
  const thirtyDaysAgo = new Date()
  thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30)

  const { data: timelineEvents } = await supabase
    .from('timeline_events')
    .select('*')
    .eq('relationship_id', relationshipId)
    .gte('occurred_at', thirtyDaysAgo.toISOString().split('T')[0])
    .is('deleted_at', null)

  // 2. Weekly check-ins for this week
  const { data: checkins } = await supabase
    .from('weekly_checkins')
    .select('*')
    .eq('relationship_id', relationshipId)
    .eq('week_ending', weekEnding.toISOString().split('T')[0])

  // 3. Attachment quiz completion status
  const { data: relationship } = await supabase
    .from('relationships')
    .select('user_a, user_b')
    .eq('id', relationshipId)
    .single()

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

  const bothCompletedAttachment = 
    userAProfile?.attachment_style !== null && 
    userBProfile?.attachment_style !== null

  // 4. Get previous pulse score for deltas
  const { data: previousPulse } = await supabase
    .from('pulse_scores')
    .select('*')
    .eq('relationship_id', relationshipId)
    .order('week_ending', { ascending: false })
    .limit(1)
    .maybeSingle()

  // 5. Chat signal aggregates (last 30 days), via the pre-aggregating RPC
  // — never select(*) raw messages/sessions rows into this function
  // (Algorithm Quality Review Checklist v3.1 item 2.14).
  const { data: chatSignalRows } = await supabase
    .rpc('compute_relationship_chat_signals', {
      p_relationship_id: relationshipId,
      p_window_start: thirtyDaysAgo.toISOString(),
    })
  const chatRow = chatSignalRows?.[0] ?? null

  const chatSignals: ChatSignals = {
    analysedCount: chatRow?.analysed_count ?? 0,
    avgTone: chatRow?.avg_tone ?? null,
    violationRate: chatRow?.violation_rate ?? null,
    severeRate: chatRow?.severe_rate ?? null,
    bidTurnRate: chatRow?.bid_turn_rate ?? null,
    bidsTotal: chatRow?.bids_total ?? 0,
    sessionCount: chatRow?.session_count ?? 0,
    avgEscalation: chatRow?.avg_escalation ?? null,
    repairRate: chatRow?.repair_rate ?? null,
    attemptRate: chatRow?.attempt_rate ?? null,
    stonewallRate: chatRow?.stonewall_rate ?? null,
    pursueWithdrawRate: chatRow?.pursue_withdraw_rate ?? null,
  }

  const pendingBacklog = chatRow?.pending_backlog_count ?? 0
  const coverageDays = chatRow?.first_analysed_at
    ? Math.min(30, (Date.now() - new Date(chatRow.first_analysed_at).getTime()) / 86_400_000)
    : 0

  // Backlog gate: if the session-analysis sweep is more than 50 messages
  // behind, treat chat as having zero weight this run rather than score
  // on a known-incomplete picture.
  const chatWeight = pendingBacklog > 50 ? 0 : computeChatWeight(coverageDays)
  const hasChatSignal = chatWeight > 0.5

  // ──────────────────────────────────────────────────────────
  // COMPUTE EACH DIMENSION
  // ──────────────────────────────────────────────────────────

  // COMMUNICATION (22% weight)
  let communication = 50 // baseline

  // Check-in contribution
  if (checkins && checkins.length > 0) {
    const avgRating = checkins.reduce((sum, c) => sum + (c.communication_rating || 0), 0) / checkins.length
    communication = Math.round(avgRating * 10)
  }

  // Conflict events affect communication
  const conflicts = timelineEvents?.filter(e => e.event_type === 'conflict') || []
  const conflictPenalty = conflicts.length * 3
  communication = clamp(communication - conflictPenalty, 0, 100)

  // Resolved conflicts (mood_score >= 7) give bonus
  const resolvedConflicts = conflicts.filter(c => c.mood_score && c.mood_score >= 7)
  const resolutionBonus = resolvedConflicts.length * 5
  communication = clamp(communication + resolutionBonus, 0, 100)


  // CONNECTION (22% weight)
  let connection = 50

  const positiveEvents = timelineEvents?.filter(e =>
    e.event_type === 'milestone' || e.event_type === 'highlight'
  ) || []
  connection = clamp(50 + (positiveEvents.length * 8), 0, 100)

  // Anniversary events
  const anniversaryEvents = timelineEvents?.filter(e => e.event_type === 'anniversary') || []
  if (anniversaryEvents.length > 0) {
    connection = clamp(connection + 15, 0, 100)
  }

  // Check-in contribution
  if (checkins && checkins.length > 0) {
    const avgRating = checkins.reduce((sum, c) => sum + (c.connection_rating || 0), 0) / checkins.length
    const checkinScore = avgRating * 10
    connection = Math.round((connection + checkinScore) / 2)
  }


  // CONFLICT HEALTH (20% weight)
  let conflictHealth = 70 // optimistic baseline

  if (conflicts.length > 0) {
    const validMoods = conflicts.filter(c => c.mood_score).map(c => c.mood_score)
    if (validMoods.length > 0) {
      const avgMood = validMoods.reduce((a, b) => a + b, 0) / validMoods.length
      conflictHealth = Math.round(avgMood * 10)
    }
  }

  // Check-in contribution
  if (checkins && checkins.length > 0) {
    const validCheckins = checkins.filter(c => !c.conflict_health_na && c.conflict_health_rating)
    if (validCheckins.length > 0) {
      const avgRating = validCheckins.reduce((sum, c) => sum + (c.conflict_health_rating || 0), 0) / validCheckins.length
      const checkinScore = avgRating * 10
      conflictHealth = Math.round((conflictHealth + checkinScore) / 2)
    }
  }


  // ALIGNMENT (18% weight)
  let alignment = 50

  if (bothCompletedAttachment) {
    alignment = clamp(alignment + 20, 0, 100)
  }

  if (checkins && checkins.length > 0) {
    const avgRating = checkins.reduce((sum, c) => sum + (c.alignment_rating || 0), 0) / checkins.length
    const checkinScore = avgRating * 10
    alignment = Math.round((alignment + checkinScore) / 2)
  }


  // EMOTIONAL SAFETY (18% weight)
  let emotionalSafety = 50

  const allEventsWithMood = timelineEvents?.filter(e => e.mood_score) || []
  if (allEventsWithMood.length > 0) {
    const avgMood = allEventsWithMood.reduce((sum, e) => sum + e.mood_score, 0) / allEventsWithMood.length
    emotionalSafety = Math.round(avgMood * 10)
  }

  if (checkins && checkins.length > 0) {
    const avgRating = checkins.reduce((sum, c) => sum + (c.safety_rating || 0), 0) / checkins.length
    const checkinScore = avgRating * 10
    emotionalSafety = Math.round((emotionalSafety + checkinScore) / 2)
  }


  // ──────────────────────────────────────────────────────────
  // APPLY CHAT SIGNAL ADJUSTMENTS (coverage-ramped)
  // — Alignment has no chat signal; not touched here.
  // ──────────────────────────────────────────────────────────
  const chatAdjusted = applyChatSignals(
    { communication, connection, conflictHealth, emotionalSafety },
    chatSignals,
    chatWeight
  )
  communication = chatAdjusted.communication
  connection = chatAdjusted.connection
  conflictHealth = chatAdjusted.conflictHealth
  emotionalSafety = chatAdjusted.emotionalSafety


  // ──────────────────────────────────────────────────────────
  // PER-DIMENSION CONFIDENCE (evidence-points model)
  // ──────────────────────────────────────────────────────────
  const communicationPoints =
    Math.min(checkins?.length ?? 0, 2) * 2 +
    Math.min(conflicts.length, 4) * 1 +
    Math.min(Math.floor(chatSignals.analysedCount / 10), 3) * 1.5
  const communicationConfidence = confidenceFrom(communicationPoints, hasChatSignal)

  const connectionPoints =
    Math.min(positiveEvents.length, 4) * 1 +
    Math.min(checkins?.length ?? 0, 2) * 2 +
    Math.min(chatSignals.bidsTotal >= 5 ? 1 : 0, 1) * 4.5
  const connectionConfidence = confidenceFrom(connectionPoints, hasChatSignal)

  const conflictHealthPoints =
    Math.min(conflicts.length, 4) * 1 +
    Math.min(checkins?.length ?? 0, 2) * 2 +
    Math.min(chatSignals.sessionCount, 4) * 1.5
  const conflictHealthConfidence = confidenceFrom(conflictHealthPoints, hasChatSignal)

  const alignmentPoints =
    (bothCompletedAttachment ? 3 : 0) +
    Math.min(checkins?.length ?? 0, 2) * 2
  // Alignment has no chat signal — hasChatSignal never promotes it past
  // what checkins/attachment alone earn, but the confidenceFrom function
  // itself still requires hasChatSignal for the 'high' branch, so
  // Alignment structurally cannot reach 'high' without chat existing
  // SOMEWHERE in the relationship's overall data — this matches the
  // spec's "no chat signal maps to Alignment" note; it simply never gets
  // the evidence points that would put it in the 9+ bracket from chat,
  // though hasChatSignal being true (from OTHER dimensions' chat data)
  // could still let it reach high on 9+ points from checkins/attachment
  // alone. This is acceptable: hasChatSignal is a relationship-level
  // gate (chat pipeline is active), not a per-dimension one.
  const alignmentConfidence = confidenceFrom(alignmentPoints, hasChatSignal)

  const safetyPoints =
    Math.min(allEventsWithMood.length, 4) * 1 +
    Math.min(checkins?.length ?? 0, 2) * 2 +
    Math.min(chatSignals.analysedCount >= 10 ? 1 : 0, 1) * 4.5
  const safetyConfidence = confidenceFrom(safetyPoints, hasChatSignal)


  // OVERALL SCORE
  const overall = Math.round(
    communication * 0.22 +
    connection * 0.22 +
    conflictHealth * 0.20 +
    alignment * 0.18 +
    emotionalSafety * 0.18
  )


  // DATA CONFIDENCE (overall)
  const confidences: Confidence[] = [
    communicationConfidence,
    connectionConfidence,
    conflictHealthConfidence,
    alignmentConfidence,
    safetyConfidence,
  ]
  const overallConfidence = rollupConfidence(confidences)


  // DELTAS vs previous week
  let deltas = null
  if (previousPulse) {
    deltas = {
      overall: overall - previousPulse.overall_score,
      communication: communication - previousPulse.communication,
      connection: connection - previousPulse.connection,
      conflict_health: conflictHealth - previousPulse.conflict_health,
      alignment: alignment - previousPulse.alignment,
      emotional_safety: emotionalSafety - previousPulse.emotional_safety,
    }
  }


  // SAVE TO DATABASE
  const pulseData = {
    relationship_id: relationshipId,
    week_ending: weekEnding.toISOString().split('T')[0],
    overall_score: overall,
    communication,
    connection,
    conflict_health: conflictHealth,
    alignment,
    emotional_safety: emotionalSafety,
    data_confidence: overallConfidence,
    dimension_confidence: {
      communication: communicationConfidence,
      connection: connectionConfidence,
      conflict_health: conflictHealthConfidence,
      alignment: alignmentConfidence,
      emotional_safety: safetyConfidence,
    },
    delta_vs_previous: deltas,
  }

  const { error: upsertError } = await supabase
    .from('pulse_scores')
    .upsert(pulseData, { onConflict: 'relationship_id,week_ending' })

  if (upsertError) {
    console.error('Failed to save pulse score:', upsertError.message)
    throw new Error(`Failed to save pulse score for relationship ${relationshipId}: ${upsertError.message}`)
  }

  return pulseData
}

export function getWeekEnding(date: Date): Date {
  const result = new Date(date)
  const daysToSunday = 7 - result.getDay() // Sunday = 0 in JS
  result.setDate(result.getDate() + daysToSunday)
  result.setHours(0, 0, 0, 0)
  return result
}

export function clamp(value: number, min: number, max: number): number {
  return Math.min(Math.max(value, min), max)
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
  avgEscalation: number | null
  repairRate: number | null
  attemptRate: number | null
  stonewallRate: number | null
  pursueWithdrawRate: number | null
}

export interface DimensionState {
  communication: number
  connection: number
  conflictHealth: number
  emotionalSafety: number
}

export function applyChatSignals(
  dimensions: DimensionState,
  signals: ChatSignals,
  chatWeight: number
): DimensionState {
  let { communication, connection, conflictHealth, emotionalSafety } = dimensions

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

    // CONFLICT HEALTH
    if (signals.repairRate != null && signals.attemptRate != null && signals.sessionCount >= 3) {
      const repairBonus = signals.repairRate * 12 + (signals.attemptRate - signals.repairRate) * 3
      conflictHealth = clamp(conflictHealth + repairBonus * chatWeight, 0, 100)
    }
    if (signals.avgEscalation != null && signals.sessionCount >= 3) {
      // Centered at 0.4, not 0 — some escalation is normal; Conflict
      // Health measures repair quality, not conflict absence.
      conflictHealth = clamp(conflictHealth - (signals.avgEscalation - 0.4) * 20 * chatWeight, 0, 100)
    }

    // EMOTIONAL SAFETY
    if (signals.severeRate != null && signals.analysedCount >= 10) {
      // Deliberate double-count with communication's violationRate above
      // — contempt/character_attack damage both clarity and safety.
      const safetyPenalty = Math.min(signals.severeRate / 0.1, 1) * 12
      emotionalSafety = clamp(emotionalSafety - safetyPenalty * chatWeight, 0, 100)
    }
    if (signals.pursueWithdrawRate != null && signals.sessionCount >= 3) {
      emotionalSafety = clamp(emotionalSafety - signals.pursueWithdrawRate * 8 * chatWeight, 0, 100)
    }
  }

  return { communication, connection, conflictHealth, emotionalSafety }
}

type Confidence = 'none' | 'low' | 'medium' | 'high'

export function confidenceFrom(points: number, hasChatSignal: boolean): Confidence {
  if (points < 2) return 'none'
  if (points < 5) return 'low'
  if (points < 9) return 'medium'
  // 'high' requires chat signal per PULSE.md §7 ("requires chat AI
  // pipeline") — a relationship with abundant timeline/check-in
  // evidence but no chat caps at 'medium'.
  return hasChatSignal ? 'high' : 'medium'
}

export function rollupConfidence(confidences: Confidence[]): Confidence {
  const highCount = confidences.filter((c) => c === 'high').length
  const mediumCount = confidences.filter((c) => c === 'medium').length
  if (highCount >= 4) return 'high'
  if (mediumCount >= 3) return 'medium'
  if (mediumCount >= 1) return 'low'
  return 'none'
}
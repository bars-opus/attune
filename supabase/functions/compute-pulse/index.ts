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
    const weekEnding = _getWeekEnding(new Date())

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

  // ──────────────────────────────────────────────────────────
  // COMPUTE EACH DIMENSION
  // ──────────────────────────────────────────────────────────

  // COMMUNICATION (22% weight)
  let communication = 50 // baseline
  let communicationConfidence: 'none' | 'low' | 'medium' | 'high' = 'low'

  // Check-in contribution
  if (checkins && checkins.length > 0) {
    const avgRating = checkins.reduce((sum, c) => sum + (c.communication_rating || 0), 0) / checkins.length
    communication = Math.round(avgRating * 10)
    communicationConfidence = checkins.length >= 2 ? 'medium' : 'low'
  }

  // Conflict events affect communication
  const conflicts = timelineEvents?.filter(e => e.event_type === 'conflict') || []
  const conflictPenalty = conflicts.length * 3
  communication = _clamp(communication - conflictPenalty, 0, 100)

  // Resolved conflicts (mood_score >= 7) give bonus
  const resolvedConflicts = conflicts.filter(c => c.mood_score && c.mood_score >= 7)
  const resolutionBonus = resolvedConflicts.length * 5
  communication = _clamp(communication + resolutionBonus, 0, 100)


  // CONNECTION (22% weight)
  let connection = 50
  let connectionConfidence: 'none' | 'low' | 'medium' | 'high' = 'low'

  const positiveEvents = timelineEvents?.filter(e => 
    e.event_type === 'milestone' || e.event_type === 'highlight'
  ) || []
  connection = _clamp(50 + (positiveEvents.length * 8), 0, 100)
  if (positiveEvents.length > 0) connectionConfidence = 'medium'

  // Anniversary events
  const anniversaryEvents = timelineEvents?.filter(e => e.event_type === 'anniversary') || []
  if (anniversaryEvents.length > 0) {
    connection = _clamp(connection + 15, 0, 100)
  }

  // Check-in contribution
  if (checkins && checkins.length > 0) {
    const avgRating = checkins.reduce((sum, c) => sum + (c.connection_rating || 0), 0) / checkins.length
    const checkinScore = avgRating * 10
    connection = Math.round((connection + checkinScore) / 2)
    connectionConfidence = checkins.length >= 2 ? 'medium' : connectionConfidence
  }


  // CONFLICT HEALTH (20% weight)
  let conflictHealth = 70 // optimistic baseline
  let conflictHealthConfidence: 'none' | 'low' | 'medium' | 'high' = 'low'

  if (conflicts.length > 0) {
    const validMoods = conflicts.filter(c => c.mood_score).map(c => c.mood_score)
    if (validMoods.length > 0) {
      const avgMood = validMoods.reduce((a, b) => a + b, 0) / validMoods.length
      conflictHealth = Math.round(avgMood * 10)
      conflictHealthConfidence = conflicts.length >= 2 ? 'medium' : 'low'
    }
  }

  // Check-in contribution
  if (checkins && checkins.length > 0) {
    const validCheckins = checkins.filter(c => !c.conflict_health_na && c.conflict_health_rating)
    if (validCheckins.length > 0) {
      const avgRating = validCheckins.reduce((sum, c) => sum + (c.conflict_health_rating || 0), 0) / validCheckins.length
      const checkinScore = avgRating * 10
      conflictHealth = Math.round((conflictHealth + checkinScore) / 2)
      conflictHealthConfidence = 'medium'
    }
  }


  // ALIGNMENT (18% weight)
  let alignment = 50
  let alignmentConfidence: 'none' | 'low' | 'medium' | 'high' = 'low'

  if (bothCompletedAttachment) {
    alignment = _clamp(alignment + 20, 0, 100)
    alignmentConfidence = 'medium'
  }

  if (checkins && checkins.length > 0) {
    const avgRating = checkins.reduce((sum, c) => sum + (c.alignment_rating || 0), 0) / checkins.length
    const checkinScore = avgRating * 10
    alignment = Math.round((alignment + checkinScore) / 2)
    alignmentConfidence = checkins.length >= 2 ? 'medium' : alignmentConfidence
  }


  // EMOTIONAL SAFETY (18% weight)
  let emotionalSafety = 50
  let safetyConfidence: 'none' | 'low' | 'medium' | 'high' = 'low'

  const allEventsWithMood = timelineEvents?.filter(e => e.mood_score) || []
  if (allEventsWithMood.length > 0) {
    const avgMood = allEventsWithMood.reduce((sum, e) => sum + e.mood_score, 0) / allEventsWithMood.length
    emotionalSafety = Math.round(avgMood * 10)
    safetyConfidence = allEventsWithMood.length >= 3 ? 'medium' : 'low'
  }

  if (checkins && checkins.length > 0) {
    const avgRating = checkins.reduce((sum, c) => sum + (c.safety_rating || 0), 0) / checkins.length
    const checkinScore = avgRating * 10
    emotionalSafety = Math.round((emotionalSafety + checkinScore) / 2)
    safetyConfidence = checkins.length >= 2 ? 'medium' : safetyConfidence
  }


  // OVERALL SCORE
  const overall = Math.round(
    communication * 0.22 +
    connection * 0.22 +
    conflictHealth * 0.20 +
    alignment * 0.18 +
    emotionalSafety * 0.18
  )


  // DATA CONFIDENCE (overall)
  const confidences = [communicationConfidence, connectionConfidence, conflictHealthConfidence, alignmentConfidence, safetyConfidence]
  const mediumCount = confidences.filter(c => c === 'medium').length
  const lowCount = confidences.filter(c => c === 'low').length

  let overallConfidence: 'none' | 'low' | 'medium' | 'high' = 'low'
  if (mediumCount >= 3) overallConfidence = 'medium'
  else if (lowCount >= 3) overallConfidence = 'low'
  else overallConfidence = 'none'


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

  await supabase.from('pulse_scores').insert(pulseData)

  return pulseData
}

function _getWeekEnding(date: Date): Date {
  const result = new Date(date)
  const daysToSunday = 7 - result.getDay() // Sunday = 0 in JS
  result.setDate(result.getDate() + daysToSunday)
  result.setHours(0, 0, 0, 0)
  return result
}

function _clamp(value: number, min: number, max: number): number {
  return Math.min(Math.max(value, min), max)
}
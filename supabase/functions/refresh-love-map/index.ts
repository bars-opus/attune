// supabase/functions/refresh-love-map/index.ts
//
// Weekly: opens three new Love Map prompts per active relationship,
// preferring domains the AI has already detected in that couple's chat.
//
// The model SELECTS a seeded question; it never writes one, and this
// function never reads `messages`. Topics come only from analysis_sessions'
// dominant_topic / root_need_detected. A generated prompt could quote
// something one partner said in confidence and put it in front of the
// other -- selection makes that class of leak structurally impossible
// rather than merely unlikely.

import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
}

/** Prompts opened per couple per run. */
const PROMPTS_PER_RUN = 3

/** Six months: a question becomes eligible again this long after it was
 *  answered. Mirrors kLoveMapReAskInterval on the client. */
const RE_ASK_DAYS = 182

/** Detected chat topics -> Love Map value domains. Anything unmapped simply
 *  contributes no preference, and selection falls back to plain rotation. */
const TOPIC_TO_DOMAIN: Record<string, string> = {
  work: 'stressors',
  money: 'stressors',
  finances: 'stressors',
  family: 'history',
  parents: 'history',
  future: 'dreams',
  plans: 'dreams',
  children: 'dreams',
  trust: 'fears',
  jealousy: 'fears',
  insecurity: 'fears',
  distance: 'fears',
  health: 'stressors',
  time: 'stressors',
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    )

    const { data: relationships, error: relError } = await supabase
      .from('relationships')
      .select('id, user_a, user_b')
      .eq('status', 'active')
      .not('user_b', 'is', null)

    if (relError) throw relError

    const { data: bank, error: bankError } = await supabase
      .from('game_questions')
      .select('id, value_domain')
      .eq('game_type', 'love_map')
      .eq('active', true)

    if (bankError) throw bankError

    const cutoff = new Date(Date.now() - RE_ASK_DAYS * 86400_000).toISOString()
    let opened = 0

    for (const rel of relationships ?? []) {
      // 1. What has the AI detected lately for this couple?
      const since = new Date(Date.now() - 30 * 86400_000).toISOString()
      const { data: sessions } = await supabase
        .from('analysis_sessions')
        .select('dominant_topic, root_need_detected')
        .eq('relationship_id', rel.id)
        .gte('started_at', since)
        .order('started_at', { ascending: false })
        .limit(50)

      const domains = new Set<string>()
      for (const s of sessions ?? []) {
        for (const raw of [s.dominant_topic, s.root_need_detected]) {
          const mapped = raw ? TOPIC_TO_DOMAIN[String(raw).toLowerCase()] : null
          if (mapped) domains.add(mapped)
        }
      }

      // 2. Which questions are eligible: never seen, or seen long enough ago.
      const { data: seen } = await supabase
        .from('game_questions_seen')
        .select('question_id, seen_at')
        .eq('relationship_id', rel.id)
        .eq('game_type', 'love_map')

      const blocked = new Set(
        (seen ?? [])
          .filter((s) => s.seen_at && s.seen_at > cutoff)
          .map((s) => s.question_id),
      )
      const eligible = (bank ?? []).filter((q) => !blocked.has(q.id))
      if (eligible.length === 0) continue

      // 3. Prefer detected domains, then everything else.
      const preferred = eligible.filter((q) => domains.has(q.value_domain))
      const rest = eligible.filter((q) => !domains.has(q.value_domain))
      const picked = [...preferred, ...rest].slice(0, PROMPTS_PER_RUN)

      // 4. Open a round per pick, alternating the subject so each partner is
      //    guessed about equally often.
      const { count: priorCount } = await supabase
        .from('game_session_rounds')
        .select('id', { count: 'exact', head: true })
        .eq('relationship_id', rel.id)

      let n = priorCount ?? 0
      for (const q of picked) {
        n += 1
        const { error: insertError } = await supabase
          .from('game_session_rounds')
          .insert({
            relationship_id: rel.id,
            round_number: n,
            question_id: q.id,
            both_answered: false,
            active_partner_id: n % 2 === 0 ? rel.user_b : rel.user_a,
          })
        if (insertError) continue

        await supabase.from('game_questions_seen').upsert(
          {
            relationship_id: rel.id,
            question_id: q.id,
            game_type: 'love_map',
            seen_at: new Date().toISOString(),
          },
          { onConflict: 'relationship_id,question_id' },
        )
        opened += 1
      }
    }

    return new Response(
      JSON.stringify({ ok: true, relationships: relationships?.length ?? 0, opened }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    )
  } catch (error) {
    return new Response(
      JSON.stringify({ ok: false, error: String(error) }),
      {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      },
    )
  }
})

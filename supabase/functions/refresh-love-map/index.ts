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
import { relationshipAiSuppressed } from '../_shared/ai_suppression.ts'

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

/** root_need_detected is a fixed seven-value enum written by analyse-session
 *  (respect | fairness | affection | security | autonomy | rest |
 *  communal_obligation — Spec 8; the definition awaits clinician sign-off).
 *  An exact lookup is right for it. */
const ROOT_NEED_TO_DOMAIN: Record<string, string> = {
  respect: 'fears',
  fairness: 'stressors',
  affection: 'fears',
  security: 'fears',
  autonomy: 'dreams',
  rest: 'stressors',
  // Family, roots and duty: the history domain (Spec 8, review M6).
  communal_obligation: 'history',
}

/** dominant_topic is NOT an enum: analyse-session asks the model for a free
 *  "max 5 words, semantic label", so real values look like "his mother
 *  visiting again" or "splitting the rent". An exact-match lookup on single
 *  words would essentially never fire, so this matches by keyword
 *  containment instead. Keys stay single lowercase words for that reason. */
const TOPIC_KEYWORD_TO_DOMAIN: Record<string, string> = {
  work: 'stressors',
  job: 'stressors',
  career: 'stressors',
  money: 'stressors',
  rent: 'stressors',
  finance: 'stressors',
  bills: 'stressors',
  health: 'stressors',
  tired: 'stressors',
  time: 'stressors',
  busy: 'stressors',
  family: 'history',
  mother: 'history',
  father: 'history',
  parent: 'history',
  childhood: 'history',
  past: 'history',
  future: 'dreams',
  plan: 'dreams',
  children: 'dreams',
  kids: 'dreams',
  marriage: 'dreams',
  move: 'dreams',
  travel: 'dreams',
  trust: 'fears',
  jealous: 'fears',
  insecur: 'fears',
  distance: 'fears',
  doubt: 'fears',
  afraid: 'fears',
}

/** Maps one analysis row's signals onto Love Map domains. */
export function domainsFor(
  dominantTopic: string | null,
  rootNeed: string | null,
): string[] {
  const out: string[] = []

  const need = rootNeed?.toLowerCase().trim()
  if (need && ROOT_NEED_TO_DOMAIN[need]) out.push(ROOT_NEED_TO_DOMAIN[need])

  const topic = dominantTopic?.toLowerCase() ?? ''
  for (const [keyword, domain] of Object.entries(TOPIC_KEYWORD_TO_DOMAIN)) {
    if (topic.includes(keyword)) out.push(domain)
  }
  return out
}

/**
 * Spec 7 (research 06 B9; plan review I3): while either partner is quiet
 * ("having a hard time", "going through a loss"), no fears, dreams or
 * children questions. Shared by both, so nothing says who is quiet.
 */
const QUIET_EXCLUDED_DOMAINS = new Set(['fears', 'dreams', 'children'])

export function forQuiet<T extends { value_domain: string | null }>(
  questions: T[],
  quiet: boolean,
): T[] {
  if (!quiet) return questions
  return questions.filter((q) => !QUIET_EXCLUDED_DOMAINS.has(q.value_domain ?? ''))
}

// What the AI detected lately for a couple, as Love map domains. Spec 8
// (plan review I11): nothing for a suppressed couple, before any read; they
// get the same unpersonalised rounds as a couple with no sessions.
// deno-lint-ignore no-explicit-any
export async function loveMapDomains(supabase: any, relationshipId: string): Promise<Set<string>> {
  const domains = new Set<string>()
  if (await relationshipAiSuppressed(supabase, relationshipId)) return domains
  const since = new Date(Date.now() - 30 * 86400_000).toISOString()
  const { data: sessions } = await supabase
    .from('analysis_sessions')
    .select('dominant_topic, root_need_detected')
    .eq('relationship_id', relationshipId)
    .gte('started_at', since)
    .order('started_at', { ascending: false })
    .limit(50)
  for (const row of sessions ?? []) {
    for (const d of domainsFor(row.dominant_topic, row.root_need_detected)) {
      domains.add(d)
    }
  }
  return domains
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
      const domains = await loveMapDomains(supabase, rel.id)

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
      const { data: quietRows, error: quietError } = await supabase
        .from('quiet_states')
        .select('user_id')
        .in('user_id', [rel.user_a, rel.user_b])
        .gt('until', new Date().toISOString())
      const eligible = forQuiet(
        (bank ?? []).filter((q) => !blocked.has(q.id)),
        // Fail closed: if we cannot tell, no fears/dreams (review M-5).
        quietError != null || (quietRows ?? []).length > 0,
      )
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

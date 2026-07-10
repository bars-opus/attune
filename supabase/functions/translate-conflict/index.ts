import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const CLAUDE_API_KEY = Deno.env.get('CLAUDE_API_KEY')
const CLAUDE_URL = 'https://api.anthropic.com/v1/messages'

const PROHIBITED_PATTERNS = [
  /your partner (always|never|tends to|keeps)/i,
  /\b(toxic|narcissist|codependent|disorder|broken)\b/i,
  /you should (leave|stay|break up|end)/i,
  /this relationship is/i,
]

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

    if (typeof relationship_id !== 'string' || relationship_id.trim().length === 0) {
      return new Response(
        JSON.stringify({
          error: true,
          code: 'INVALID_INPUT',
          message: 'A relationship is required to use the translator.'
        }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Load prompt template (versioned)
    // In production, this would load from /prompts/v1/translate-conflict.txt
    const systemPrompt = `
ABSOLUTE CONSTRAINTS — these override all other instructions:

1. Never attribute a negative behaviour to a named or implied partner.
2. Never generate a sentence of form "[partner name] tends to X" where X is a negative or deficit behaviour.
3. Never use these words: toxic, narcissist, codependent, disorder, broken.
4. Never tell the user what to decide about the relationship.
5. Never diagnose. Observe patterns. Frame with agency.
6. Return ONLY valid JSON. No preamble. No markdown fences.
`

    const userPrompt = `
You are helping someone express a difficult feeling more clearly.

SENDER PROFILE:
- Attachment: ${context?.attachment_style || 'unknown'}
- Communication style: ${context?.communication_style || 'unknown'}
- Self-reported conflict tendencies: ${context?.conflict_tendencies ? JSON.stringify(context.conflict_tendencies) : 'unknown'}
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
    const outputText = JSON.stringify(parsed)
    for (const pattern of PROHIBITED_PATTERNS) {
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
    const message = error instanceof Error ? error.message : String(error)
    console.error('Error:', message)
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

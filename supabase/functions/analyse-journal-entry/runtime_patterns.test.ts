// The journal summary is returned straight to the caller, so RUNTIME_PATTERNS
// is the only thing between a banned word and a user. These assert the regex
// behaves, not merely that the words appear in it.

import { assertEquals } from 'https://deno.land/std@0.177.0/testing/asserts.ts'

const RUNTIME_PATTERNS = [
  /you should (tell|confront|ask|leave)/i,
  /\b(toxic|narcissist|codependent|disorder|broken)\b/i,
]

const blocked = (t: string) => RUNTIME_PATTERNS.some((p) => p.test(t))

Deno.test('blocks every §11 #8 banned word', () => {
  for (const t of [
    'Your entries suggest a toxic dynamic.',
    'This reads as narcissist behaviour.',
    'A codependent pattern shows up.',
    'That sounds like a disorder.',
    'You seem broken by it.',
  ]) {
    assertEquals(blocked(t), true, `should have blocked: ${t}`)
  }
})

Deno.test('blocks advice, which a private diary has no addressee for', () => {
  assertEquals(blocked('Maybe you should tell him.'), true)
  assertEquals(blocked('You should confront her.'), true)
})

Deno.test('word boundaries spare innocent substrings', () => {
  // Without \b these would trip, and a legitimate summary would be
  // silently replaced by boilerplate.
  assertEquals(blocked('You mentioned the intoxicating early days.'), false)
  assertEquals(blocked('You wrote about feeling brokenhearted.'), false)
  assertEquals(blocked('A disorderly week, you called it.'), false)
})

Deno.test('ordinary summaries pass through', () => {
  assertEquals(
    blocked('You have written about work stress four times this month.'),
    false,
  )
  assertEquals(blocked('A recurring theme is wanting more rest.'), false)
})

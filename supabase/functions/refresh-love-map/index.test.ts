import { assertEquals } from 'https://deno.land/std@0.177.0/testing/asserts.ts'
import { domainsFor } from './index.ts'

Deno.test('root_need_detected maps exactly — it is a fixed enum', () => {
  assertEquals(domainsFor(null, 'autonomy'), ['dreams'])
  assertEquals(domainsFor(null, 'rest'), ['stressors'])
  assertEquals(domainsFor(null, 'security'), ['fears'])
})

Deno.test('dominant_topic matches free text by keyword, not equality', () => {
  // Real values are a model-written "max 5 words, semantic label", so an
  // exact lookup on 'work' would never fire on any of these.
  assertEquals(domainsFor('his mother visiting again', null), ['history'])
  assertEquals(domainsFor('splitting the rent', null), ['stressors'])
  assertEquals(domainsFor('feeling jealous lately', null), ['fears'])
  assertEquals(domainsFor('planning the move abroad', null).sort(), [
    'dreams',
    'dreams',
  ])
})

Deno.test('an unmapped topic contributes no preference', () => {
  assertEquals(domainsFor('something entirely unrelated', null), [])
  assertEquals(domainsFor(null, null), [])
})

Deno.test('both signals contribute together', () => {
  const out = domainsFor('work has been heavy', 'autonomy')
  assertEquals(out.includes('stressors'), true)
  assertEquals(out.includes('dreams'), true)
})

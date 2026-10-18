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

// Spec 7 (B9, plan review I3): while either partner is quiet, no fears,
// dreams or children questions (a loss is exactly when "dreams" hurts).
Deno.test('a quiet couple gets no fears, dreams or children rounds', async () => {
  const { forQuiet } = await import('./index.ts')
  const bank = [
    { id: '1', value_domain: 'fears' },
    { id: '2', value_domain: 'dreams' },
    { id: '3', value_domain: 'children' },
    { id: '4', value_domain: 'history' },
  ]
  assertEquals(forQuiet(bank, true).map((q) => q.id), ['4'])
  assertEquals(forQuiet(bank, false).map((q) => q.id), ['1', '2', '3', '4'])
  const src = await Deno.readTextFile(new URL('./index.ts', import.meta.url))
  if (!src.includes(".from('quiet_states')")) throw new Error('quiet state is not read')
})

// Final review M-5: a failed quiet-state read counts as quiet (fail closed).
Deno.test('an unreadable quiet state is treated as quiet', async () => {
  const src = await Deno.readTextFile(new URL('./index.ts', import.meta.url))
  if (!src.includes('quietError != null ||')) throw new Error('a read error falls open')
})

// Spec 8 (plan review P8, M6): the seventh need maps to history (family,
// roots) until clinician sign-off says otherwise.
Deno.test('communal obligation maps to history', () => {
  assertEquals(domainsFor(null, 'communal_obligation'), ['history'])
})

// Spec 8 (plan review I11): a suppressed couple's rounds are not shaped by
// what the AI saw in their chat; they look exactly like a couple with no
// sessions yet. Unsure counts as suppressed.
Deno.test('a suppressed couple: no analysis_sessions read, no preferred domains', async () => {
  const { loveMapDomains } = await import('./index.ts')
  const touched: string[] = []
  const client = {
    rpc: () => Promise.resolve({ data: true, error: null }),
    from: (t: string) => {
      touched.push(t)
      throw new Error('read ' + t)
    },
  }
  assertEquals([...(await loveMapDomains(client as never, 'r1'))], [])
  assertEquals(touched, [])
  const failing = { ...client, rpc: () => Promise.resolve({ data: null, error: { message: 'x' } }) }
  assertEquals([...(await loveMapDomains(failing as never, 'r1'))], [])
  assertEquals(touched, [])
})

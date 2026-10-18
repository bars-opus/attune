// Spec 8 (plan review I9, P7, P8; research 06 A8): the translator is the
// caller's own, for a relationship they are in; a "no" survives the
// rewrite; the seventh need exists.
// Run: PGDATABASE=attune_spec3a deno test --allow-net --allow-env --allow-read --allow-sys
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  buildTranslatePrompt,
  hasRefusal,
  processTranslateRequest,
  SEVEN_NEEDS,
  TranslateDeps,
  validateTranslateOutput,
  validateTranslateRequest,
} from "./handler.ts";
import { getSharedPgClient, makeRlsClientForUser, serviceRoleQuery } from "../_shared/test_support/pg_rls_client.ts";

const REL = "a8100000-0000-0000-0000-000000000001";
const A = "a8100000-0000-0000-0000-00000000000a";
const B = "a8100000-0000-0000-0000-00000000000b";
const C = "a8100000-0000-0000-0000-00000000000c";

async function reset(status = "active", archived = false) {
  await serviceRoleQuery(`DELETE FROM public.translator_daily_use WHERE user_id IN ($1, $2, $3)`, [A, B, C]);
  await serviceRoleQuery(`DELETE FROM public.relationships WHERE id = $1`, [REL]);
  await serviceRoleQuery(`DELETE FROM public.users WHERE id IN ($1, $2, $3)`, [A, B, C]);
  await serviceRoleQuery(`DELETE FROM auth.users WHERE id IN ($1, $2, $3)`, [A, B, C]);
  await serviceRoleQuery(`INSERT INTO auth.users (id, email) VALUES ($1, 'tr_a@t.test'), ($2, 'tr_b@t.test'), ($3, 'tr_c@t.test')`, [A, B, C]);
  await serviceRoleQuery(`INSERT INTO public.users (id, phone, display_name) VALUES ($1, '+15551118001', 'A'), ($2, '+15551118002', 'B'), ($3, '+15551118003', 'C')`, [A, B, C]);
  await serviceRoleQuery(
    `INSERT INTO public.relationships (id, user_a, user_b, status, chat_archived_at) VALUES ($1, $2, $3, $4, $5)`,
    [REL, A, B, status, archived ? new Date().toISOString() : null],
  );
}

const req = (body: unknown) => new Request("http://x/translate-conflict", { method: "POST", body: JSON.stringify(body) });
const never: TranslateDeps["callGemini"] = () => { throw new Error("the provider must not be called"); };
const reply = (rewrite: string, need = "rest"): TranslateDeps["callGemini"] => () =>
  Promise.resolve({ rewrite, core_need_identified: need, framing_note: "a quieter evening", rewrite_confidence: "high" });

async function call(user: string, body: unknown, callGemini: TranslateDeps["callGemini"]) {
  const client = await makeRlsClientForUser(user);
  return processTranslateRequest(req(body), { client: client as never, user: { id: user } }, { callGemini });
}

Deno.test("requests: 3-2000 characters, a relationship, an optional register; client context is ignored", () => {
  assert(validateTranslateRequest({ message: "hi there", relationship_id: REL }));
  assertEquals(validateTranslateRequest({ message: "hi there", relationship_id: REL })!.register, "nvc");
  assertEquals(validateTranslateRequest({ message: "hi there", relationship_id: REL, register: "plain" })!.register, "plain");
  assertEquals(validateTranslateRequest({ message: "hi", relationship_id: REL }), null);
  assertEquals(validateTranslateRequest({ message: "x".repeat(2001), relationship_id: REL }), null);
  assertEquals(validateTranslateRequest({ message: "hi there", relationship_id: REL, register: "shout" }), null);
  const p = buildTranslatePrompt({ message: "hi there", register: "nvc" });
  assert(!p.user.includes("Attachment"), "no profile or partner tone is sent");
});

Deno.test("seven needs, including communal obligation", () => {
  assertEquals(SEVEN_NEEDS.length, 7);
  assert(SEVEN_NEEDS.includes("communal_obligation"));
  assert(buildTranslatePrompt({ message: "x y z", register: "nvc" }).user.includes("communal_obligation"));
});

Deno.test("a no survives the rewrite (A8 boundary statements)", () => {
  assert(hasRefusal("I don't want to go to your mother's this weekend"));
  assert(!hasRefusal("I would love some time together"));
  const input = "I'm not going to your mother's on Sunday";
  assertEquals(validateTranslateOutput({ rewrite: "I'd love to see your mother on Sunday", core_need_identified: "rest", framing_note: "", rewrite_confidence: "high" }, input), null);
  assert(validateTranslateOutput({ rewrite: "I'm not able to come on Sunday; I need the day to rest", core_need_identified: "rest", framing_note: "", rewrite_confidence: "high" }, input));
  // Ghanaian in-law scenario (A8): the obligation is named, the "no" kept.
  assert(validateTranslateOutput({ rewrite: "I can't host your uncle this month, and I know family matters to you", core_need_identified: "communal_obligation", framing_note: "", rewrite_confidence: "medium" }, "We can't have your uncle staying here again this month"));
  assertEquals(validateTranslateOutput({ rewrite: "ok", core_need_identified: "money", framing_note: "", rewrite_confidence: "high" }, "fine whatever")!.core_need_identified, null);
});

Deno.test({ name: "a non-member and an archived chat are refused before the provider", sanitizeResources: false, sanitizeOps: false, async fn() {
  await reset();
  assertEquals((await call(C, { message: "please hear me", relationship_id: REL }, never)).status, 403);
  await reset("active", true);
  assertEquals((await call(A, { message: "please hear me", relationship_id: REL }, never)).status, 403);
  await reset("ended");
  assertEquals((await call(A, { message: "please hear me", relationship_id: REL }, never)).status, 403);
} });

Deno.test({ name: "my own disclosure gets the writer card, no provider, no use counted", sanitizeResources: false, sanitizeOps: false, async fn() {
  await reset();
  await serviceRoleQuery(`UPDATE public.feature_flags SET enabled = true WHERE key = 'private_safety_check'`);
  try {
    const res = await call(A, { message: "he hits me and I don't know what to say", relationship_id: REL }, never);
    assertEquals(await res.json(), { status: "writer_resources" });
    assertEquals(res.headers.get("cache-control"), "no-store");
    assertEquals((await serviceRoleQuery(`SELECT * FROM public.translator_daily_use WHERE user_id = $1`, [A])).length, 0);
  } finally {
    await serviceRoleQuery(`UPDATE public.feature_flags SET enabled = false WHERE key = 'private_safety_check'`);
  }
} });

// Final review I-6: with the draft list off (production today), the
// sentence goes to the model, as it did before Spec 8.
Deno.test({ name: "the draft list is off with its flag: the model is asked", sanitizeResources: false, sanitizeOps: false, async fn() {
  await reset();
  const res = await call(A, { message: "he hits me and I don't know what to say", relationship_id: REL }, reply("I don't know what to say, and I need us to talk"));
  assertEquals(res.status, 200);
} });

Deno.test({ name: "a rewrite that drops the no is not returned", sanitizeResources: false, sanitizeOps: false, async fn() {
  await reset();
  const res = await call(A, { message: "I don't want to go out tonight", relationship_id: REL }, reply("Let's go out tonight!"));
  assertEquals(res.status, 500);
  const ok = await call(A, { message: "I don't want to go out tonight", relationship_id: REL, register: "plain" }, reply("I don't want to go out tonight; I'm worn out"));
  assertEquals(ok.status, 200);
  assertEquals((await ok.json()).core_need_identified, "rest");
} });

Deno.test({ name: "the daily limit", sanitizeResources: false, sanitizeOps: false, async fn() {
  await reset();
  await serviceRoleQuery(`INSERT INTO public.translator_daily_use (user_id, day, uses) VALUES ($1, (now() AT TIME ZONE 'UTC')::date, 30)`, [A]);
  assertEquals((await call(A, { message: "please hear me", relationship_id: REL }, never)).status, 429);
} });

Deno.test({ name: "teardown", async fn() { await (await getSharedPgClient()).end(); } });

// Spec 2 W7b (§4.7, §6.4, §7.3): dating-moderation. Refuses without aal2
// (TOTP) before any call, and an unknown action or bad input before any
// call; calls exactly one moderation_* function with the signed-in
// moderator's id (an actor in the body is ignored); passes the database's
// not_moderator through; storage keys never leave (signed for 60 seconds,
// a key that fails to sign is url null); a server's text or an error is
// never answered (busy); the wiring: no-store, CORS only for the console's
// origin, an unauthorised caller is unauthorized, only an error's code is
// logged.
import { aalOf, ACTIONS, handleModeration, type ModerationDeps, PHOTO_BUCKET, REVIEW_BUCKET } from "./handler.ts";
import { consoleOrigin, handleRequest, type ModerationClient } from "./request.ts";
import { HttpError } from "../_shared/attune_auth.ts";

function eq(actual: unknown, expected: unknown, why = "") {
  const a = JSON.stringify(actual), e = JSON.stringify(expected);
  if (a !== e) throw new Error(`${why} expected ${e}, got ${a}`);
}

const ME = "99999999-2222-4333-8444-555555555555";
const CASE = "11111111-2222-4333-8444-555555555555";
const MOD = { userId: ME, aal: "aal2" };

interface Seen {
  rpc: Array<[string, Record<string, unknown>]>;
  signed: Array<[string, string[], number]>;
}

function deps(data: unknown, seen: Seen, opts: { error?: boolean; rejects?: boolean; signThrows?: boolean } = {}): ModerationDeps {
  return {
    rpc: (fn, args) => {
      seen.rpc.push([fn, args]);
      if (opts.rejects) return Promise.reject(new Error("server text: connection reset"));
      return Promise.resolve(opts.error ? { data: null, error: { message: "secret detail" } } : { data, error: null });
    },
    sign: (bucket, keys, seconds) => {
      seen.signed.push([bucket, keys, seconds]);
      if (opts.signThrows) return Promise.reject(new Error("storage down"));
      return Promise.resolve(keys.map((k) => ({ path: k, signedUrl: k === "bad" ? null : `https://s.test/${bucket}/${k}?t` })));
    },
  };
}

const fresh = (): Seen => ({ rpc: [], signed: [] });

Deno.test("no aal2, no call: TOTP is needed for every action", async () => {
  for (const aal of ["aal1", null]) {
    const seen = fresh();
    eq(await handleModeration({ action: "queue" }, { userId: ME, aal }, deps({ ok: true }, seen)), {
      ok: false,
      reason: "mfa_required",
    });
    eq(seen.rpc.length, 0);
  }
});

Deno.test("an unknown action or bad input is invalid, before any call", async () => {
  const seen = fresh();
  for (const body of [
    {},
    { action: "drop_table" },
    { action: "toString" },
    { action: "case", case_id: "x" },
    { action: "hold", case_id: CASE, category: "safety_concern" },
    { action: "restrict", case_id: CASE, type: "banned", category: "spam" },
    { action: "restrict", case_id: CASE, type: "suspended", category: "spam", ends_at: "soon" },
    { action: "note", case_id: CASE, note: "x".repeat(1001) },
    { action: "decide_appeal", case_id: CASE, accept: "yes" },
    { action: "verification_decide", session_id: CASE, outcome: "maybe" },
    { action: "publish_country", country: "gh", values: {} },
    { action: "opinions_remove", type: "forum_post", id: CASE },
  ]) {
    eq(await handleModeration(body, MOD, deps({ ok: true }, seen)), { ok: false, reason: "invalid" }, JSON.stringify(body));
  }
  eq(seen.rpc.length, 0);
});

Deno.test("one function per action, as the signed-in moderator (a body actor is ignored)", async () => {
  const seen = fresh();
  await handleModeration({ action: "restrict", case_id: CASE.toUpperCase(), type: "suspended", category: "threats",
    ends_at: "2026-12-05T10:00:00Z", p_actor: "someone-else" }, MOD, deps({ ok: true }, seen));
  // Fix round 1 (review M-1): p_actor is set last, so the token's moderator
  // wins over any argument builder's key.
  eq(seen.rpc, [["moderation_restrict", {
    p_case: CASE,
    p_type: "suspended",
    p_ends_at: "2026-12-05T10:00:00.000Z",
    p_category: "threats",
    p_actor: ME,
  }]]);
  const expected: Record<string, string> = {
    whoami: "moderation_whoami", queue: "moderation_queue", case: "moderation_case", claim: "moderation_claim",
    dismiss: "moderation_dismiss", hold: "moderation_place_hold", lift_hold: "moderation_lift_hold",
    restrict: "moderation_restrict", ask_for_id: "moderation_ask_for_id", confirm_minor: "moderation_confirm_minor",
    note: "moderation_note", decide_appeal: "moderation_decide_appeal", photos: "moderation_photos",
    photo_decide: "moderation_photo_decide", verifications: "moderation_verifications",
    verification_decide: "moderation_verification_decide", countries: "moderation_countries",
    publish_country: "moderation_publish_country", opinions_queue: "moderation_opinions_queue",
    opinions_remove: "moderation_opinions_remove", audit: "moderation_audit_log",
    escalate: "moderation_record_escalation", le_requests: "moderation_le_requests",
    le_record: "moderation_record_le_request", transparency: "moderation_transparency_summary",
  };
  for (const [action, fn] of Object.entries(expected)) eq(ACTIONS[action]?.fn, fn, action);
});

Deno.test("the database's refusals pass through as fixed codes; anything else is busy", async () => {
  eq(await handleModeration({ action: "queue" }, MOD, deps({ ok: false, reason: "not_moderator" }, fresh())), {
    ok: false,
    reason: "not_moderator",
  });
  eq(await handleModeration({ action: "queue" }, MOD, deps({ ok: false, reason: "Kofi is restricted" }, fresh())), {
    ok: false,
    reason: "busy",
  });
  eq(await handleModeration({ action: "queue" }, MOD, deps(null, fresh(), { error: true })), { ok: false, reason: "busy" });
  eq(await handleModeration({ action: "queue" }, MOD, deps(null, fresh(), { rejects: true })), { ok: false, reason: "busy" });
});

Deno.test("a case's photos, the photo queue and a verification are signed for 60 s; no key leaves", async () => {
  const seen = fresh();
  const a = await handleModeration({ action: "case", case_id: CASE }, MOD, deps({
    ok: true,
    case: { id: CASE },
    profile: { display_name: "Kofi", photos: [{ position: 1, key: "u/1.jpg" }, { position: 2, key: "bad" }] },
  }, seen));
  eq((a as Record<string, unknown>).profile, {
    display_name: "Kofi",
    photos: [{ position: 1, url: `https://s.test/${PHOTO_BUCKET}/u/1.jpg?t` }, { position: 2, url: null }],
  });
  const v = await handleModeration({ action: "verifications" }, MOD, deps({
    ok: true,
    sessions: [{ id: "s1", photos: [{ position: 1, key: "u/1.jpg" }], review_paths: ["s1/1.jpg", "s1/2.jpg"] }],
  }, seen));
  eq((v as Record<string, unknown>).sessions, [{
    id: "s1",
    photos: [{ position: 1, url: `https://s.test/${PHOTO_BUCKET}/u/1.jpg?t` }],
    review: [`https://s.test/${REVIEW_BUCKET}/s1/1.jpg?t`, `https://s.test/${REVIEW_BUCKET}/s1/2.jpg?t`],
  }]);
  const p = await handleModeration({ action: "photos" }, MOD, deps({ ok: true, photos: [{ id: "f1", key: "u/3.jpg" }] }, seen));
  eq((p as Record<string, unknown>).photos, [{ id: "f1", url: `https://s.test/${PHOTO_BUCKET}/u/3.jpg?t` }]);
  for (const [, , seconds] of seen.signed) eq(seconds, 60);
  for (const answer of [a, v, p]) {
    if (/"key"|review_paths|u\/1\.jpg"/.test(JSON.stringify(answer))) throw new Error("a storage key left the function");
  }
  const failed = await handleModeration({ action: "photos" }, MOD, deps({ ok: true, photos: [{ id: "f1", key: "k" }] }, fresh(), {
    signThrows: true,
  }));
  eq((failed as Record<string, unknown>).photos, [{ id: "f1", url: null }]);
});

Deno.test("W7c: an escalation is recorded (CSA 292 only with consent); the log and the summary", async () => {
  const seen = fresh();
  const ok = deps({ ok: true }, seen);
  eq(await handleModeration({ action: "escalate", case_id: CASE, kind: "csa_292" }, MOD, ok), { ok: false, reason: "invalid" });
  eq(await handleModeration({ action: "transparency", from: "2026-7-1", to: "2026-10-01" }, MOD, ok), {
    ok: false,
    reason: "invalid",
  });
  eq(await handleModeration({ action: "le_record", request_id: "x", values: {} }, MOD, ok), { ok: false, reason: "invalid" });
  eq(seen.rpc.length, 0);
  await handleModeration({ action: "escalate", case_id: CASE, kind: "csa_292_with_consent", reference: "CSA-1" }, MOD, ok);
  await handleModeration({ action: "le_record", values: { jurisdiction: "GH" } }, MOD, ok);
  await handleModeration({ action: "transparency", from: "2026-07-01", to: "2026-10-01" }, MOD, ok);
  eq(seen.rpc, [
    ["moderation_record_escalation", { p_case: CASE, p_kind: "csa_292_with_consent", p_reference: "CSA-1", p_actor: ME }],
    ["moderation_record_le_request", { p_request: null, p_values: { jurisdiction: "GH" }, p_actor: ME }],
    ["moderation_transparency_summary", { p_from: "2026-07-01", p_to: "2026-10-01", p_actor: ME }],
  ]);
});

Deno.test("aalOf reads the token's aal claim, and nothing else", () => {
  const enc = (o: unknown) => btoa(JSON.stringify(o)).replace(/=+$/, "").replace(/\+/g, "-").replace(/\//g, "_");
  eq(aalOf(`h.${enc({ sub: ME, aal: "aal2" })}.s`), "aal2");
  eq(aalOf(`h.${enc({ sub: ME })}.s`), null);
  eq(aalOf("garbage"), null);
  eq(aalOf("h.!!!.s"), null);
});

function client(data: unknown, seen: Seen): ModerationClient {
  return {
    rpc: (fn, args) => {
      seen.rpc.push([fn, args]);
      return Promise.resolve({ data, error: null });
    },
    storage: { from: () => ({ createSignedUrls: () => Promise.resolve({ data: [], error: null }) }) },
  };
}

Deno.test("the wiring: no-store, CORS only for the console's origin, unauthorized, codes only in logs", async () => {
  const aal2 = `h.${btoa(JSON.stringify({ aal: "aal2" }))}.s`;
  const post = (origin: string) =>
    new Request("https://f.test/dating-moderation", {
      method: "POST",
      headers: { Authorization: `Bearer ${aal2}`, Origin: origin, "Content-Type": "application/json" },
      body: JSON.stringify({ action: "whoami" }),
    });
  const seen = fresh();
  const wiring = { requireUser: () => Promise.resolve({ id: ME }), client: () => client({ ok: true, role: "moderator" }, seen),
    origin: "https://console.test" };
  const ok = await handleRequest(post("https://console.test"), wiring);
  eq(ok.headers.get("Cache-Control"), "no-store");
  eq(ok.headers.get("Access-Control-Allow-Origin"), "https://console.test");
  eq(await ok.json(), { ok: true, role: "moderator" });
  eq(seen.rpc, [["moderation_whoami", { p_actor: ME }]]);
  const other = await handleRequest(post("https://evil.test"), wiring);
  eq(other.headers.get("Access-Control-Allow-Origin"), null);
  const none = await handleRequest(post("https://console.test"), { ...wiring, origin: null });
  eq(none.headers.get("Access-Control-Allow-Origin"), null);
  const unauth = await handleRequest(post("https://console.test"), {
    ...wiring,
    requireUser: () => Promise.reject(new HttpError("Invalid authorization token", 401)),
  });
  eq(unauth.status, 401);
  eq(await unauth.json(), { ok: false, reason: "unauthorized" });
  const logged: unknown[][] = [];
  const original = console.error;
  console.error = (...args: unknown[]) => logged.push(args);
  try {
    const broken = await handleRequest(post("https://console.test"), {
      ...wiring,
      client: () => {
        throw Object.assign(new Error("phone +233244000000 leaked"), { code: "PGRST301" });
      },
    });
    eq(broken.status, 500);
    eq(await broken.json(), { ok: false, reason: "busy" });
  } finally {
    console.error = original;
  }
  eq(logged, [["dating-moderation failed:", "PGRST301"]]);
  eq((await handleRequest(new Request("https://f.test/x", { method: "GET" }), wiring)).status, 405);
});

// Task 6 rulings, against Task 5's live replies: decider_unknown and the
// country publish's config:* refusals are fixed codes too; a Postgres lock,
// deadlock or timeout error (console writes have no busy answer of their
// own) and a call that outlives the timeout are busy, never their text;
// the verification queue signs once per bucket, not once per session.
Deno.test("decider_unknown and the publish's config codes pass through; an unknown config code is busy", async () => {
  eq(await handleModeration({ action: "decide_appeal", case_id: CASE, accept: true }, MOD,
    deps({ ok: false, reason: "decider_unknown" }, fresh())), { ok: false, reason: "decider_unknown" });
  // Fix round 1 (review M-2): each of the live codes on its own.
  for (const code of [
    "config:invalid_country", "config:invalid_values", "config:unknown_key", "config:invalid_tz", "config:invalid_lists",
    "config:checklist_keys_removed", "config:invalid_regions", "config:no_calling_code", "config:production_checks_failed",
    "config:launch_not_ready", // Spec 2 W10
  ]) {
    eq(await handleModeration({ action: "publish_country", country: "GH", values: { tier: 1 } }, MOD,
      deps({ ok: false, reason: code, checks: { secret: "x" } }, fresh())), { ok: false, reason: code }, code);
  }
  eq(await handleModeration({ action: "publish_country", country: "GH", values: {} }, MOD,
    deps({ ok: false, reason: "config:Kofi" }, fresh())), { ok: false, reason: "busy" });
});

Deno.test("a lock, deadlock or timeout error is busy and its text never leaves; so is a call that outlives the timeout", async () => {
  for (const code of ["55P03", "40P01", "57014", "40001"]) {
    const seen = fresh();
    const d: ModerationDeps = {
      ...deps(null, seen),
      rpc: () => Promise.resolve({ data: null, error: { code, message: "lock on row for +233244000000" } }),
    };
    const answer = await handleModeration({ action: "dismiss", case_id: CASE }, MOD, d);
    eq(answer, { ok: false, reason: "busy" }, code);
  }
  const hung: ModerationDeps = { ...deps(null, fresh()), rpc: () => new Promise(() => {}), rpcTimeoutMs: 5 };
  eq(await handleModeration({ action: "claim", case_id: CASE }, MOD, hung), { ok: false, reason: "busy" });
});

Deno.test("the verification queue is signed in one call per bucket", async () => {
  const seen = fresh();
  const v = await handleModeration({ action: "verifications" }, MOD, deps({
    ok: true,
    sessions: [
      { id: "s1", photos: [{ position: 1, key: "u/1.jpg" }], review_paths: ["s1/1.jpg", "s1/2.jpg"] },
      { id: "s2", photos: [{ position: 1, key: "u/2.jpg" }, { position: 2, key: "bad" }], review_paths: [] },
    ],
  }, seen));
  eq(seen.signed.map(([bucket, keys]) => [bucket, keys]), [
    [PHOTO_BUCKET, ["u/1.jpg", "u/2.jpg", "bad"]],
    [REVIEW_BUCKET, ["s1/1.jpg", "s1/2.jpg"]],
  ]);
  eq((v as Record<string, unknown>).sessions, [
    {
      id: "s1",
      photos: [{ position: 1, url: `https://s.test/${PHOTO_BUCKET}/u/1.jpg?t` }],
      review: [`https://s.test/${REVIEW_BUCKET}/s1/1.jpg?t`, `https://s.test/${REVIEW_BUCKET}/s1/2.jpg?t`],
    },
    { id: "s2", photos: [{ position: 1, url: `https://s.test/${PHOTO_BUCKET}/u/2.jpg?t` }, { position: 2, url: null }], review: [] },
  ]);
});

Deno.test("the wiring: the console's preflight is allowed, a database error's code alone is logged", async () => {
  const preflight = (origin: string) =>
    new Request("https://f.test/dating-moderation", {
      method: "OPTIONS",
      headers: { Origin: origin, "Access-Control-Request-Method": "POST" },
    });
  const seen = fresh();
  const wiring = {
    requireUser: () => Promise.reject(new HttpError("Missing authorization token", 401)),
    client: () => client({ ok: true }, seen),
    origin: "https://console.test",
  };
  const ok = await handleRequest(preflight("https://console.test"), wiring);
  eq(ok.status, 200);
  eq(ok.headers.get("Access-Control-Allow-Origin"), "https://console.test");
  eq(ok.headers.get("Access-Control-Allow-Headers"), "authorization, content-type, apikey, x-client-info");
  eq(ok.headers.get("Access-Control-Allow-Methods"), "POST, OPTIONS");
  eq((await handleRequest(preflight("https://evil.test"), wiring)).headers.get("Access-Control-Allow-Origin"), null);
  const aal2 = `h.${btoa(JSON.stringify({ aal: "aal2" }))}.s`;
  const logged: unknown[][] = [];
  const original = console.error;
  console.error = (...args: unknown[]) => logged.push(args);
  let broken: Response;
  try {
    broken = await handleRequest(new Request("https://f.test/dating-moderation", {
      method: "POST",
      headers: { Authorization: `Bearer ${aal2}`, Origin: "https://console.test" },
      body: JSON.stringify({ action: "dismiss", case_id: CASE }),
    }), {
      ...wiring,
      requireUser: () => Promise.resolve({ id: ME }),
      client: () => ({
        ...client(null, seen),
        rpc: () => Promise.resolve({ data: null, error: { code: "55P03", message: "lock for +233244000000" } }),
      }),
    });
  } finally {
    console.error = original;
  }
  eq(await broken.json(), { ok: false, reason: "busy" });
  eq(logged, [["dating-moderation rpc failed:", "55P03"]]);
});

// Fix round 1 (task-6-review.md): the wiring's aal gate (I-1), the exact
// origin (M-3), the rpc-rejection, timeout and Storage logs (M-4, M-5), a
// normalised DATING_CONSOLE_ORIGIN (M-6), the preflight's max age (M-7), a
// note counted in code points as the database does (M-9), and the actor no
// argument builder can override (M-1).
const token = (claims: Record<string, unknown>) => `h.${btoa(JSON.stringify(claims))}.s`;
const postAs = (claims: Record<string, unknown>, body: Record<string, unknown>, origin = "https://console.test") =>
  new Request("https://f.test/dating-moderation", {
    method: "POST",
    headers: { Authorization: `Bearer ${token(claims)}`, Origin: origin, "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });

async function quietly(run: () => Promise<Response>): Promise<{ res: Response; logged: unknown[][] }> {
  const logged: unknown[][] = [];
  const original = console.error;
  console.error = (...args: unknown[]) => logged.push(args);
  try {
    return { res: await run(), logged };
  } finally {
    console.error = original;
  }
}

Deno.test("the wiring reads aal from the verified token: aal1 or no claim is mfa_required, before any call", async () => {
  for (const claims of [{ sub: ME, aal: "aal1" }, { sub: ME }]) {
    const seen = fresh();
    const res = await handleRequest(postAs(claims, { action: "queue" }), {
      requireUser: () => Promise.resolve({ id: ME }),
      client: () => client({ ok: true, cases: [] }, seen),
      origin: "https://console.test",
    });
    eq(await res.json(), { ok: false, reason: "mfa_required" }, JSON.stringify(claims));
    eq(seen.rpc.length, 0);
  }
  const seen = fresh();
  await handleRequest(postAs({ aal: "aal2" }, { action: "whoami", p_actor: "someone-else" }), {
    requireUser: () => Promise.resolve({ id: ME }),
    client: () => client({ ok: true }, seen),
    origin: "https://console.test",
  });
  eq(seen.rpc, [["moderation_whoami", { p_actor: ME }]]);
});

Deno.test("no argument builder can override the signed-in moderator", async () => {
  ACTIONS.__builder_test = { fn: "moderation_whoami", args: (b) => ({ p_actor: b.as }) };
  try {
    const seen = fresh();
    await handleModeration({ action: "__builder_test", as: "someone-else" }, MOD, deps({ ok: true }, seen));
    eq(seen.rpc, [["moderation_whoami", { p_actor: ME }]]);
  } finally {
    delete ACTIONS.__builder_test;
  }
});

Deno.test("CORS needs the exact origin; a lookalike or a longer origin gets nothing; the preflight is cached", async () => {
  const wiring = {
    requireUser: () => Promise.resolve({ id: ME }),
    client: () => client({ ok: true }, fresh()),
    origin: "https://console.example.com",
  };
  for (const origin of ["https://console.example.com.evil.com", "https://console.example.com:8443", "http://console.example.com",
    "https://console.example.co"]) {
    const res = await handleRequest(postAs({ aal: "aal2" }, { action: "whoami" }, origin), wiring);
    eq(res.headers.get("Access-Control-Allow-Origin"), null, origin);
  }
  const pre = await handleRequest(new Request("https://f.test/dating-moderation", {
    method: "OPTIONS",
    headers: { Origin: "https://console.example.com" },
  }), wiring);
  eq(pre.headers.get("Access-Control-Allow-Origin"), "https://console.example.com");
  eq(pre.headers.get("Access-Control-Max-Age"), "600");
});

Deno.test("DATING_CONSOLE_ORIGIN is read as an origin: a trailing slash or a path is dropped; anything else is none", () => {
  eq(consoleOrigin("https://console.example.com/"), "https://console.example.com");
  eq(consoleOrigin(" https://Console.Example.com:443/login "), "https://console.example.com");
  eq(consoleOrigin("http://localhost:5000"), "http://localhost:5000");
  for (const raw of [undefined, null, "", "   ", "console.example.com", "file:///tmp/x", "*", "null"]) {
    eq(consoleOrigin(raw), null, String(raw));
  }
});

Deno.test("a rejected rpc, a timeout and a Storage failure are busy or url null, and only a code is logged", async () => {
  const base = { requireUser: () => Promise.resolve({ id: ME }), origin: "https://console.test" };
  const rejected = await quietly(() =>
    handleRequest(postAs({ aal: "aal2" }, { action: "dismiss", case_id: CASE }), {
      ...base,
      client: () => ({
        ...client(null, fresh()),
        rpc: () => Promise.reject(Object.assign(new Error("socket to +233244000000 closed"), { code: "ECONNRESET" })),
      }),
    })
  );
  eq(await rejected.res.json(), { ok: false, reason: "busy" });
  eq(rejected.logged, [["dating-moderation rpc failed:", "ECONNRESET"]]);
  const hung = await quietly(() =>
    handleRequest(postAs({ aal: "aal2" }, { action: "claim", case_id: CASE }), {
      ...base,
      rpcTimeoutMs: 5,
      client: () => ({ ...client(null, fresh()), rpc: () => new Promise(() => {}) }),
    })
  );
  eq(await hung.res.json(), { ok: false, reason: "busy" });
  eq(hung.logged, [["dating-moderation timeout:", "moderation_claim"]]);
  for (const storage of [
    { createSignedUrls: () => Promise.resolve({ data: null, error: Object.assign(new Error("u/3.jpg missing"), { code: "S3_DOWN" }) }) },
    { createSignedUrls: () => Promise.reject(new Error("u/3.jpg unreachable")) },
  ]) {
    const signedOut = await quietly(() =>
      handleRequest(postAs({ aal: "aal2" }, { action: "photos" }), {
        ...base,
        client: () => ({ ...client({ ok: true, photos: [{ id: "f1", key: "u/3.jpg" }] }, fresh()), storage: { from: () => storage } }),
      })
    );
    eq(await signedOut.res.json(), { ok: true, photos: [{ id: "f1", url: null }] });
    if (signedOut.logged.length !== 1 || signedOut.logged[0][0] !== "dating-moderation sign failed:" ||
      JSON.stringify(signedOut.logged).includes("u/3.jpg")) {
      throw new Error(`sign failure logged as ${JSON.stringify(signedOut.logged)}`);
    }
  }
});

Deno.test("a note is counted in code points, as the database counts it", async () => {
  const seen = fresh();
  eq(await handleModeration({ action: "note", case_id: CASE, note: "😀".repeat(1000) }, MOD, deps({ ok: true }, seen)), {
    ok: true,
  });
  eq(seen.rpc.length, 1);
  eq(await handleModeration({ action: "note", case_id: CASE, note: "😀".repeat(1001) }, MOD, deps({ ok: true }, seen)), {
    ok: false,
    reason: "invalid",
  });
  eq(seen.rpc.length, 1);
});

// Fix round 2 (Task 5's fix round 1 replies): every console write's own
// busy, the party refusals, claim's claimed and took_over, lift's per-case
// count, and a replayed publish without checks, all pass through; nothing
// else does.
const WRITES: Array<Record<string, unknown>> = [
  { action: "claim", case_id: CASE },
  { action: "dismiss", case_id: CASE },
  { action: "hold", case_id: CASE, category: "harassment" },
  { action: "lift_hold", case_id: CASE },
  { action: "restrict", case_id: CASE, type: "under_review", ends_at: null, category: "spam" },
  { action: "ask_for_id", case_id: CASE },
  { action: "confirm_minor", case_id: CASE },
  { action: "note", case_id: CASE, note: "Checked the evidence." },
  { action: "decide_appeal", case_id: CASE, accept: false },
  { action: "photo_decide", photo_id: CASE, approve: false, reason: "unsafe" },
  { action: "verification_decide", session_id: CASE, outcome: "pass" },
  { action: "publish_country", country: "GH", values: { tier: 1 } },
  { action: "opinions_remove", type: "opinion", id: CASE },
];

Deno.test("every console write's own busy passes through as busy, after exactly one call", async () => {
  for (const body of WRITES) {
    const seen = fresh();
    eq(await handleModeration(body, MOD, deps({ ok: false, reason: "busy" }, seen)), { ok: false, reason: "busy" },
      String(body.action));
    eq(seen.rpc.length, 1, String(body.action));
  }
});

Deno.test("a party's refusals pass through: case_unavailable, photo_unavailable, session_unavailable", async () => {
  for (const body of [{ action: "case", case_id: CASE }, ...WRITES.filter((w) => typeof w.case_id === "string")]) {
    eq(await handleModeration(body, MOD, deps({ ok: false, reason: "case_unavailable" }, fresh())), {
      ok: false,
      reason: "case_unavailable",
    }, String(body.action));
  }
  eq(await handleModeration({ action: "photo_decide", photo_id: CASE, approve: true }, MOD,
    deps({ ok: false, reason: "photo_unavailable" }, fresh())), { ok: false, reason: "photo_unavailable" });
  eq(await handleModeration({ action: "verification_decide", session_id: CASE, outcome: "fail" }, MOD,
    deps({ ok: false, reason: "session_unavailable" }, fresh())), { ok: false, reason: "session_unavailable" });
});

Deno.test("claim: claimed passes through and a take-over keeps took_over; lift keeps its count", async () => {
  const claim = { action: "claim", case_id: CASE };
  eq(await handleModeration(claim, MOD, deps({ ok: false, reason: "claimed" }, fresh())), { ok: false, reason: "claimed" });
  eq(await handleModeration(claim, MOD, deps({ ok: true, took_over: true }, fresh())), { ok: true, took_over: true });
  eq(await handleModeration(claim, MOD, deps({ ok: true }, fresh())), { ok: true });
  eq(await handleModeration({ action: "lift_hold", case_id: CASE }, MOD, deps({ ok: true, lifted: 2 }, fresh())), {
    ok: true,
    lifted: 2,
  });
});

Deno.test("a replayed publish (no checks) is answered as it came", async () => {
  const replay = { ok: true, country: "GH", version: 4, dating_enabled: false, same_gender_enabled: false, environment: "testing" };
  eq(await handleModeration({ action: "publish_country", country: "GH", values: { tier: 1 } }, MOD, deps(replay, fresh())), replay);
});

// Spec 2 W7c Task 9, console round 3 (Task 8 fix round 1's replies): the
// case's escalations, the CSAM hold list and its lift are one function each
// (the lift needs a restriction id and a written reason of at most 1000 code
// points); the log's exists keeps the logged request's id and nothing else;
// already_disclosed, consent_kind_required, hold_unavailable and every
// owner-only refusal pass through as fixed codes.
const HOLD = "22222222-3333-4444-8555-666666666666";

Deno.test("W7c round 3: the case's escalations, the CSAM holds and the lift: one function each, bad input before any call", async () => {
  const expected: Record<string, string> = {
    case_escalations: "moderation_case_escalations",
    csam_holds: "moderation_csam_holds",
    lift_csam_hold: "moderation_lift_csam_hold",
  };
  for (const [action, fn] of Object.entries(expected)) eq(ACTIONS[action]?.fn, fn, action);
  const seen = fresh();
  const ok = deps({ ok: true }, seen);
  for (const body of [
    { action: "case_escalations" },
    { action: "case_escalations", case_id: "c1" },
    { action: "lift_csam_hold", restriction_id: HOLD },
    { action: "lift_csam_hold", restriction_id: HOLD, reason: "   " },
    { action: "lift_csam_hold", restriction_id: HOLD, reason: 7 },
    { action: "lift_csam_hold", restriction_id: HOLD, reason: "😀".repeat(1001) },
    { action: "lift_csam_hold", restriction_id: "h1", reason: "A false positive." },
    { action: "lift_csam_hold", reason: "A false positive." },
  ]) {
    eq(await handleModeration(body, MOD, ok), { ok: false, reason: "invalid" }, JSON.stringify(body).slice(0, 80));
  }
  eq(seen.rpc.length, 0);
  await handleModeration({ action: "case_escalations", case_id: CASE.toUpperCase() }, MOD, ok);
  await handleModeration({ action: "csam_holds", p_actor: "someone-else" }, MOD, ok);
  await handleModeration({ action: "lift_csam_hold", restriction_id: HOLD, reason: "😀".repeat(1000) }, MOD, ok);
  eq(seen.rpc, [
    ["moderation_case_escalations", { p_case: CASE, p_actor: ME }],
    ["moderation_csam_holds", { p_actor: ME }],
    ["moderation_lift_csam_hold", { p_restriction: HOLD, p_reason: "😀".repeat(1000), p_actor: ME }],
  ]);
});

Deno.test("W7c round 3: the answers pass through; exists keeps only the logged request's id", async () => {
  const LOGGED = "33333333-4444-4555-8666-777777777777";
  const record = { action: "le_record", values: { jurisdiction: "GH" } };
  eq(await handleModeration(record, MOD, deps({ ok: false, reason: "exists", id: LOGGED.toUpperCase(), scope: "One account" },
    fresh())), { ok: false, reason: "exists", id: LOGGED });
  eq(await handleModeration(record, MOD, deps({ ok: false, reason: "exists", id: "+233244000000" }, fresh())), {
    ok: false,
    reason: "exists",
  });
  eq(await handleModeration({ action: "escalate", case_id: CASE, kind: "police" }, MOD,
    deps({ ok: false, reason: "exists", id: LOGGED }, fresh())), { ok: false, reason: "exists" });
  eq(await handleModeration({ action: "dismiss", case_id: CASE }, MOD, deps({ ok: false, reason: "invalid", id: LOGGED }, fresh())), {
    ok: false,
    reason: "invalid",
  });
  for (const [body, reason] of [
    [{ action: "le_record", request_id: LOGGED, values: { decision: "refused" } }, "already_disclosed"],
    [{ action: "escalate", case_id: CASE, kind: "csa" }, "consent_kind_required"],
    [{ action: "lift_csam_hold", restriction_id: HOLD, reason: "A false positive." }, "hold_unavailable"],
    [{ action: "case_escalations", case_id: CASE }, "case_unavailable"],
    [{ action: "le_requests" }, "safety_owner_only"],
    [{ action: "le_record", values: {} }, "safety_owner_only"],
    [{ action: "transparency", from: "2026-07-01", to: "2026-10-01" }, "safety_owner_only"],
    [{ action: "csam_holds" }, "safety_owner_only"],
    [{ action: "lift_csam_hold", restriction_id: HOLD, reason: "A false positive." }, "safety_owner_only"],
    [{ action: "lift_csam_hold", restriction_id: HOLD, reason: "A false positive." }, "busy"],
  ] as Array<[Record<string, unknown>, string]>) {
    eq(await handleModeration(body, MOD, deps({ ok: false, reason, detail: "Kofi" }, fresh())), { ok: false, reason },
      `${body.action}/${reason}`);
  }
  // Task 8 fix round 2: each hold carries case_id (null for a hash hit's).
  const holds = {
    ok: true,
    holds: [
      { id: HOLD, since: "2026-11-20T10:00:00Z", carried: false, case_id: null, escalations: [] },
      { id: HOLD, since: "2026-11-21T10:00:00Z", carried: false, case_id: CASE, escalations: [] },
    ],
  };
  eq(await handleModeration({ action: "csam_holds" }, MOD, deps(holds, fresh())), holds);
  const escalations = { ok: true, escalations: [{ kind: "police", recorded_at: "2026-11-21T09:00:00Z", mine: true, reference: null }] };
  eq(await handleModeration({ action: "case_escalations", case_id: CASE }, MOD, deps(escalations, fresh())), escalations);
});

// Fix round 1 (owner: Ask for ID → awaiting_id): a case's state is the
// server's and passes through untouched, in the queue and on the case.
Deno.test("W7c fix round 1: a case waiting for ID keeps its state in the queue and on the case", async () => {
  const row = { id: CASE, kind: "report", priority: "P1", state: "awaiting_id", sla_due_at: "2026-11-23T10:00:00Z" };
  eq(await handleModeration({ action: "queue" }, MOD, deps({ ok: true, cases: [row] }, fresh())), { ok: true, cases: [row] });
  const read = await handleModeration({ action: "case", case_id: CASE }, MOD,
    deps({ ok: true, case: { id: CASE, state: "awaiting_id" }, profile: null }, fresh()));
  eq((read as Record<string, unknown>).case, { id: CASE, state: "awaiting_id" });
  eq(await handleModeration({ action: "ask_for_id", case_id: CASE }, MOD, deps({ ok: true }, fresh())), { ok: true });
});

// Server round 5: "No ID came" closes a waiting case (outcome
// no_id_received, the age check stays): its own action and function.
Deno.test("W7c round 5: No ID came is one function, a case id before any call, its answers pass through", async () => {
  eq(ACTIONS.close_no_id?.fn, "moderation_close_no_id");
  const seen = fresh();
  for (const body of [{ action: "close_no_id" }, { action: "close_no_id", case_id: "c1" }]) {
    eq(await handleModeration(body, MOD, deps({ ok: true }, seen)), { ok: false, reason: "invalid" });
  }
  eq(seen.rpc.length, 0);
  eq(await handleModeration({ action: "close_no_id", case_id: CASE.toUpperCase(), p_actor: "x" }, MOD, deps({ ok: true }, seen)), {
    ok: true,
  });
  eq(seen.rpc, [["moderation_close_no_id", { p_case: CASE, p_actor: ME }]]);
  for (const reason of ["case_unavailable", "busy", "not_moderator"]) {
    eq(await handleModeration({ action: "close_no_id", case_id: CASE }, MOD, deps({ ok: false, reason }, fresh())), {
      ok: false,
      reason,
    });
  }
});

// W7 final client fix (I-5): the queue reads one kind at a time (p_kind),
// the ID-check section among them; a kind the console doesn't know is
// invalid before any call; has_more and each case's id_check pass through.
Deno.test("final fix I-5: the queue passes its kind as p_kind; an unknown kind is invalid", async () => {
  for (const kind of ["report", "appeal", "signal", "photo", "verification", "csam_hit", "id_check"]) {
    const seen = fresh();
    await handleModeration({ action: "queue", kind, limit: 200 }, MOD, deps({ ok: true, cases: [] }, seen));
    eq(seen.rpc, [["moderation_queue", { p_limit: 200, p_kind: kind, p_actor: ME }]], kind);
  }
  const all = fresh();
  await handleModeration({ action: "queue" }, MOD, deps({ ok: true, cases: [] }, all));
  eq(all.rpc, [["moderation_queue", { p_limit: 50, p_kind: null, p_actor: ME }]], "no kind: every kind");
  for (const kind of ["appeals", "", 3, "ID_CHECK", "report; drop"]) {
    const seen = fresh();
    eq(await handleModeration({ action: "queue", kind }, MOD, deps({ ok: true }, seen)), { ok: false, reason: "invalid" });
    eq(seen.rpc.length, 0, `${kind}`);
  }
  const answer = {
    ok: true,
    has_more: true,
    cases: [{ id: CASE, kind: "report", state: "decided", id_check: { state: "no_id", restriction_live: true, code: "AB23CD45" } }],
  };
  eq(await handleModeration({ action: "queue", kind: "id_check" }, MOD, deps(answer, fresh())), answer);
  const read = { ok: true, case: { id: CASE, id_check: { state: "awaiting", restriction_live: true, code: "AB23CD45" } } };
  eq(await handleModeration({ action: "case", case_id: CASE }, MOD, deps(read, fresh())), read);
});

// W7 final client fix (server round 2): "Lift the case's holds" is its own
// function (an open case's interim holds and report age checks; never the
// asked check, never CSAM); a case id before any call; its count passes.
Deno.test("final fix round 2: lift_case_holds is one function, a case id before any call", async () => {
  const seen = fresh();
  eq(
    await handleModeration({ action: "lift_case_holds", case_id: CASE }, MOD, deps({ ok: true, lifted: 2 }, seen)),
    { ok: true, lifted: 2 },
  );
  eq(seen.rpc, [["moderation_lift_case_holds", { p_case: CASE, p_actor: ME }]]);
  for (const body of [{ action: "lift_case_holds" }, { action: "lift_case_holds", case_id: "c1" }]) {
    const none = fresh();
    eq(await handleModeration(body, MOD, deps({ ok: true }, none)), { ok: false, reason: "invalid" });
    eq(none.rpc.length, 0);
  }
  eq(
    await handleModeration({ action: "lift_case_holds", case_id: CASE }, MOD, deps({ ok: false, reason: "case_unavailable" }, fresh())),
    { ok: false, reason: "case_unavailable" },
  );
});

Deno.test("W10: readiness, metrics and fairness are one function each, bad input before any call", async () => {
  eq(ACTIONS.readiness?.fn, "moderation_launch_readiness");
  eq(ACTIONS.metrics?.fn, "moderation_metrics");
  eq(ACTIONS.fairness?.fn, "moderation_fairness");
  const seen = fresh();
  const ok = deps({ ok: true }, seen);
  await handleModeration({ action: "readiness" }, MOD, ok);
  await handleModeration({ action: "readiness", country: "GH", p_actor: "someone-else" }, MOD, ok);
  await handleModeration({ action: "metrics", days: 28 }, MOD, ok);
  await handleModeration({ action: "fairness" }, MOD, ok);
  await handleModeration({ action: "fairness", weeks: 12 }, MOD, ok);
  eq(seen.rpc, [
    ["moderation_launch_readiness", { p_country: null, p_actor: ME }],
    ["moderation_launch_readiness", { p_country: "GH", p_actor: ME }],
    ["moderation_metrics", { p_days: 28, p_actor: ME }],
    ["moderation_fairness", { p_weeks: 4, p_actor: ME }],
    ["moderation_fairness", { p_weeks: 12, p_actor: ME }],
  ]);
  const none = fresh();
  for (const body of [
    { action: "readiness", country: "gh" },
    { action: "readiness", country: "GHA" },
    { action: "readiness", country: 233 },
    { action: "metrics" },
    { action: "metrics", days: 30 },
    { action: "metrics", days: "7" },
  ]) {
    eq(await handleModeration(body, MOD, deps({ ok: true }, none)), { ok: false, reason: "invalid" }, JSON.stringify(body));
  }
  eq(none.rpc.length, 0);
  // An out-of-range week count reads the default window, as the lists' limits do.
  const weeks = fresh();
  await handleModeration({ action: "fairness", weeks: 13 }, MOD, deps({ ok: true }, weeks));
  eq(weeks.rpc, [["moderation_fairness", { p_weeks: 4, p_actor: ME }]]);
});

Deno.test("W10: the answers pass through; a moderator's refusal is safety_owner_only; no aal2, no call", async () => {
  const ready = { ok: true, ready: false, environment: "development", countries: ["GH", "GB"], open: [],
    gates: [{ gate: "environment", ok: false }, { gate: "flag_evidence", ok: false, detail: ["dating_couple_link"] }] };
  eq(await handleModeration({ action: "readiness" }, MOD, deps(ready, fresh())), ready);
  const metrics = { ok: true, days: 7, from: "2026-11-17", to: "2026-11-23", min_count: 50,
    metrics: [{ key: "dating.mutual", count: 50 }], suppressed: 3 };
  eq(await handleModeration({ action: "metrics", days: 7 }, MOD, deps(metrics, fresh())), metrics);
  for (const body of [{ action: "readiness" }, { action: "metrics", days: 7 }, { action: "fairness" }]) {
    eq(await handleModeration(body, MOD, deps({ ok: false, reason: "safety_owner_only" }, fresh())),
      { ok: false, reason: "safety_owner_only" }, body.action);
    const seen = fresh();
    eq(await handleModeration(body, { userId: ME, aal: "aal1" }, deps({ ok: true }, seen)),
      { ok: false, reason: "mfa_required" }, body.action);
    eq(seen.rpc.length, 0);
  }
  // A publish refused for the launch gates passes only its code.
  eq(await handleModeration({ action: "publish_country", country: "GH", values: { dating_enabled: true } }, MOD,
    deps({ ok: false, reason: "config:launch_not_ready", gates: ["age_assurance_live"] }, fresh())),
    { ok: false, reason: "config:launch_not_ready" });
});

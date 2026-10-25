// Spec 1 W2c (§4.5, §7.2): the Send SMS Hook — signature, channel routing,
// failover, the SMS fallback, the two message shapes, +999, rate limits,
// and no number or code in the logs. Batch 7 rulings: one delivery per code
// (n-4, M-1), no code ever spoken by a call (M-4), refusals Auth can pass
// on, the 4-second budget (M-3), bounded database calls (M-6) and
// Arkesel's own success answer (M-5).
import { type Decision, DELIVERY_BUDGET_MS, handleSendSms, type HookDeps, MIN_ATTEMPT_MS } from "./handler.ts";
import { smsText, voiceText } from "./messages.ts";
import { arkesel, meta, type OutgoingCode, PROVIDER_TIMEOUT_MS, providersFrom, twilio } from "./providers.ts";

const SECRET_BYTES = new Uint8Array(24).fill(5);
const SECRET = `v1,whsec_${btoa(String.fromCharCode(...SECRET_BYTES))}`;
const NOW = 1_800_000_000;
const PHONE = "233244123456";
const OTP = "561166";

async function signed(payload: unknown, secret = SECRET_BYTES, id = "msg_1"): Promise<Request> {
  const body = JSON.stringify(payload);
  const key = await crypto.subtle.importKey("raw", secret, { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const signature = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(`${id}.${NOW}.${body}`));
  return new Request("http://x/send-sms-hook", {
    method: "POST",
    headers: {
      "webhook-id": id,
      "webhook-timestamp": String(NOW),
      "webhook-signature": `v1,${btoa(String.fromCharCode(...new Uint8Array(signature)))}`,
    },
    body,
  });
}

const payload = (phone = PHONE, otp = OTP) => ({ user: { id: "u1", phone }, sms: { otp } });

function decision(over: Partial<Decision> = {}): Decision {
  return {
    allowed: true,
    reason: null,
    channel: "sms",
    platform: "ios",
    routes: [{ channel: "sms", provider: "arkesel" }, { channel: "sms", provider: "twilio" }],
    retry_after_s: null,
    ...over,
  };
}

type Outcome = "sent" | "failed" | "unconfigured" | "machine";

/// [outcomes], [delays] and [state.answer] may be changed between calls;
/// [delays] advance the fake clock (decide, check, or a provider's name).
function rig(answer: Decision, outcomes: Record<string, Outcome> = {}, delays: Record<string, number> = {}) {
  const delivered: (OutgoingCode & { provider: string; timeoutMs: number | undefined })[] = [];
  const bumps: string[] = [];
  const logs: string[] = [];
  const asked: [string, string, string][] = [];
  /// The user id each decision was asked with (final review I-2).
  const askedUsers: (string | null)[] = [];
  const checks: string[] = [];
  const marks: string[] = [];
  const events: string[] = [];
  const sentKeys = new Set<string>();
  const clock = { ms: 0 };
  const state = { answer };
  const provider = (name: string) => (code: OutgoingCode, timeoutMs?: number) => {
    delivered.push({ ...code, provider: name, timeoutMs });
    events.push(`deliver:${name}`);
    clock.ms += delays[name] ?? 0;
    return Promise.resolve(outcomes[name] ?? "sent");
  };
  const deps: HookDeps = {
    hookSecret: SECRET,
    hmacKey: "test-key",
    alreadySent: (key) => {
      checks.push(key);
      events.push("check");
      clock.ms += delays.check ?? 0;
      return Promise.resolve(sentKeys.has(key));
    },
    markSent: (key) => {
      marks.push(key);
      events.push("mark");
      sentKeys.add(key);
      return Promise.resolve();
    },
    decide: (hmac, country, prefix, userId) => {
      asked.push([hmac, country, prefix]);
      askedUsers.push(userId);
      events.push("decide");
      clock.ms += delays.decide ?? 0;
      return Promise.resolve(state.answer);
    },
    providers: { arkesel: provider("arkesel"), twilio: provider("twilio"), meta: provider("meta") },
    androidAppHashes: ["FA+9qCX9VSu"],
    bump: (key) => {
      bumps.push(key);
      return Promise.resolve();
    },
    nowSeconds: () => NOW,
    nowMs: () => clock.ms,
    log: (category) => logs.push(category),
  };
  return { deps, delivered, bumps, logs, asked, askedUsers, checks, marks, events, clock, state };
}

/// Auth passes a hook's error on only from a 200 answer (handler.ts), so
/// the error is read from the body: "{http_code} {message}", or null for
/// a success.
async function errorOf(response: Response): Promise<string | null> {
  const body = await response.json();
  if (!body.error) return null;
  return `${body.error.http_code} ${body.error.message}`;
}

Deno.test("a signed SMS goes by the first route, counted by country and route", async () => {
  const r = rig(decision());
  const response = await handleSendSms(await signed(payload()), r.deps);
  const error = await errorOf(response);
  if (response.status !== 200 || error) throw new Error(error ?? `status ${response.status}`);
  if (r.delivered.length !== 1 || r.delivered[0].provider !== "arkesel") {
    throw new Error(JSON.stringify(r.delivered));
  }
  if (r.bumps.join() !== "otp_sent:gh:sms:arkesel") throw new Error(r.bumps.join());
  const [hmac, country, prefix] = r.asked[0];
  if (!/^[0-9a-f]{64}$/.test(hmac) || country !== "GH" || prefix !== "+233244") {
    throw new Error(JSON.stringify(r.asked));
  }
});

Deno.test("a bad or missing signature, or no secret, sends nothing", async () => {
  const wrongKey = rig(decision());
  const response = await handleSendSms(await signed(payload(), new Uint8Array(24).fill(6)), wrongKey.deps);
  if (await errorOf(response) !== "401 unauthorized" || wrongKey.delivered.length) {
    throw new Error("a wrong signature was accepted");
  }
  const noSecret = rig(decision());
  noSecret.deps.hookSecret = undefined;
  if (await errorOf(await handleSendSms(await signed(payload()), noSecret.deps)) !== "500 otp:unavailable") {
    throw new Error("no secret did not fail closed");
  }
  const noKey = rig(decision());
  noKey.deps.hmacKey = undefined;
  if (await errorOf(await handleSendSms(await signed(payload()), noKey.deps)) !== "500 otp:unavailable") {
    throw new Error("no HMAC key did not fail closed");
  }
  for (const r of [wrongKey, noSecret, noKey]) {
    if (r.checks.length || r.asked.length || r.delivered.length) throw new Error("reached the database or a provider");
  }
});

Deno.test("a failed route fails over to the next; all failing is otp:unavailable", async () => {
  const r = rig(decision(), { arkesel: "failed" });
  await handleSendSms(await signed(payload()), r.deps);
  if (r.delivered.map((d) => d.provider).join() !== "arkesel,twilio" || r.bumps.join() !== "otp_sent:gh:sms:twilio") {
    throw new Error(JSON.stringify(r.delivered));
  }
  const none = rig(decision(), { arkesel: "unconfigured", twilio: "failed" });
  if (await errorOf(await handleSendSms(await signed(payload()), none.deps)) !== "503 otp:unavailable") {
    throw new Error("all routes failing did not answer otp:unavailable");
  }
});

Deno.test("WhatsApp and voice failures fall back to SMS", async () => {
  for (const channel of ["whatsapp", "voice"] as const) {
    const provider = channel === "whatsapp" ? "meta" : "twilio";
    const r = rig(
      decision({
        channel,
        routes: [{ channel, provider }, { channel: "sms", provider: "arkesel" }],
      }),
      { [provider]: "failed" },
    );
    await handleSendSms(await signed(payload()), r.deps);
    const last = r.delivered.at(-1)!;
    if (last.channel !== "sms" || r.bumps.join() !== "otp_sent:gh:sms:arkesel") {
      throw new Error(`${channel}: ${JSON.stringify(r.delivered)}`);
    }
  }
});

Deno.test("a decision of SMS never uses another channel", async () => {
  const r = rig(decision({
    channel: "sms",
    routes: [{ channel: "whatsapp", provider: "meta" }, { channel: "sms", provider: "twilio" }],
  }));
  await handleSendSms(await signed(payload()), r.deps);
  if (r.delivered.some((d) => d.channel !== "sms")) throw new Error(JSON.stringify(r.delivered));
});

Deno.test("iOS and Android message shapes, and the voice words", async () => {
  if (smsText(OTP, "ios", "FA+9qCX9VSu") !==
      "Your Attune code is 561166. It expires in 10 minutes. Don't share it.\n\n@invite.attune.barsopus.com #561166") {
    throw new Error(smsText(OTP, "ios", undefined));
  }
  if (smsText(OTP, "other", undefined) !== smsText(OTP, "ios", undefined)) throw new Error("other is not the iOS shape");
  if (smsText(OTP, "android", "FA+9qCX9VSu") !==
      "<#> Your Attune code is 561166. It expires in 10 minutes. Don't share it.\nFA+9qCX9VSu") {
    throw new Error(smsText(OTP, "android", "FA+9qCX9VSu"));
  }
  if (voiceText(OTP) !== "Your Attune code is 5, 6, 1, 1, 6, 6. Again: 5, 6, 1, 1, 6, 6.") {
    throw new Error(voiceText(OTP));
  }
  const r = rig(decision({ platform: "android" }));
  await handleSendSms(await signed(payload()), r.deps);
  if (!r.delivered[0].text.startsWith("<#> ")) throw new Error("the Android shape was not used");
});

Deno.test("+999 is refused before any decision; rate limits answer with the wait", async () => {
  const parked = rig(decision());
  const response = await handleSendSms(await signed(payload("999123456789012")), parked.deps);
  if (await errorOf(response) !== "400 otp:unavailable" || parked.asked.length || parked.delivered.length ||
      parked.checks.length) {
    throw new Error("a parked number reached a provider");
  }
  const limited = rig(decision({ allowed: false, reason: "number_hourly", routes: [], retry_after_s: 754 }));
  if (await errorOf(await handleSendSms(await signed(payload()), limited.deps)) !== "429 otp:rate_limited:754") {
    throw new Error("a rate limit was not passed on");
  }
  const blocked = rig(decision({ allowed: false, reason: "blocked", routes: [] }));
  if (await errorOf(await handleSendSms(await signed(payload()), blocked.deps)) !== "400 otp:unavailable") {
    throw new Error("a blocked destination was not refused");
  }
});

Deno.test("no number and no code ever reach the logs", async () => {
  const r = rig(decision(), { arkesel: "failed" });
  await handleSendSms(await signed(payload()), r.deps);
  const logs = r.logs.join(" ");
  if (logs.includes(PHONE) || logs.includes(OTP)) throw new Error(logs);
  for (const file of ["handler.ts", "providers.ts", "index.ts"]) {
    const source = await Deno.readTextFile(new URL(`./${file}`, import.meta.url));
    if (/console\.(log|error)\([^)]*(phone|otp|code\.to|text)\b/.test(source)) {
      throw new Error(`${file} logs a value`);
    }
  }
});

Deno.test("providers: unconfigured without secrets; the right request with them", async () => {
  const calls: { url: string; init: RequestInit }[] = [];
  const fetchFn = (url: string, init: RequestInit) => {
    calls.push({ url, init });
    return Promise.resolve(new Response("{}", { status: 200 }));
  };
  const code: OutgoingCode = { channel: "sms", to: "+233244123456", otp: OTP, text: "hello" };
  const none = (_: string) => undefined;
  for (const provider of [twilio(none, fetchFn), meta(none, fetchFn), arkesel(none, fetchFn)]) {
    if (await provider(code) !== "unconfigured") throw new Error("ran without secrets");
  }
  if (calls.length) throw new Error("called a provider without secrets");

  const env = (name: string) => ({
    TWILIO_ACCOUNT_SID: "AC1", TWILIO_AUTH_TOKEN: "t", TWILIO_SMS_FROM: "+15550000000",
    TWILIO_VOICE_FROM: "+15550000001", WHATSAPP_ACCESS_TOKEN: "w", WHATSAPP_PHONE_NUMBER_ID: "99",
    ARKESEL_API_KEY: "a", ARKESEL_SENDER_ID: "Attune",
  } as Record<string, string>)[name];
  if (await twilio(env, fetchFn)(code) !== "sent" || !calls[0].url.endsWith("/Accounts/AC1/Messages.json")) {
    throw new Error(JSON.stringify(calls[0]));
  }
  // Calls are off in W2 (ruling M-4): even fully configured, no call.
  if (await twilio(env, fetchFn)({ ...code, channel: "voice", text: "Your Attune code is 5 & 6" }) !== "unconfigured" ||
      calls.length !== 1) {
    throw new Error("a call was placed");
  }
  await meta(env, fetchFn)({ ...code, channel: "whatsapp" });
  const whatsapp = JSON.parse(String(calls[1].init.body));
  if (whatsapp.to !== "233244123456" || whatsapp.template.components[0].parameters[0].text !== OTP) {
    throw new Error(String(calls[1].init.body));
  }
  await arkesel(env, fetchFn)(code);
  const ghana = JSON.parse(String(calls[2].init.body));
  if (ghana.sender !== "Attune" || ghana.recipients[0] !== "233244123456") throw new Error(String(calls[2].init.body));

  const failing = (_: string, __: RequestInit) => Promise.resolve(new Response("no", { status: 500 }));
  if (await twilio(env, failing)(code) !== "failed") throw new Error("a 500 was sent");
  const throwing = (_: string, __: RequestInit) => Promise.reject(new Error("network"));
  if (await arkesel(env, throwing)(code) !== "failed") throw new Error("a network error was sent");
});

// ---------------------------------------------------------------------
// Batch 7 rulings.
// ---------------------------------------------------------------------

// Auth turns any hook answer of 400 or above into a generic 500, and reads
// {error: {http_code, message}} only from a 200 or 202 (supabase/auth
// internal/hooks/hookshttp + hookserrors). The app's `otp:rate_limited:{s}`
// and `otp:unavailable` (otp_failure.dart) reach it only that way.
Deno.test("every refusal Auth must pass on is a 200 carrying the error; a stranger gets a plain 401", async () => {
  const cases: [string, ReturnType<typeof rig>, Request][] = [];
  const limited = rig(decision({ allowed: false, reason: "prefix_hourly", routes: [], retry_after_s: 30 }));
  cases.push(["429 otp:rate_limited:30", limited, await signed(payload())]);
  const blocked = rig(decision({ allowed: false, reason: "blocked", routes: [] }));
  cases.push(["400 otp:unavailable", blocked, await signed(payload())]);
  const failing = rig(decision(), { arkesel: "failed", twilio: "failed" });
  cases.push(["503 otp:unavailable", failing, await signed(payload())]);
  const parked = rig(decision());
  cases.push(["400 otp:unavailable", parked, await signed(payload("999123456789012"))]);
  const noSecret = rig(decision());
  noSecret.deps.hookSecret = undefined;
  cases.push(["500 otp:unavailable", noSecret, await signed(payload())]);
  const garbled = rig(decision());
  cases.push(["400 otp:unavailable", garbled, await signed({ user: { phone: PHONE }, sms: { otp: "x" } })]);
  for (const [expected, r, request] of cases) {
    const response = await handleSendSms(request, r.deps);
    const type = response.headers.get("Content-Type");
    const error = await errorOf(response);
    if (response.status !== 200 || type !== "application/json" || error !== expected) {
      throw new Error(`expected 200 carrying ${expected}, got ${response.status} ${type} ${error}`);
    }
  }
  const stranger = rig(decision());
  const response = await handleSendSms(await signed(payload(), new Uint8Array(24).fill(6)), stranger.deps);
  if (response.status !== 401) throw new Error(`a bad signature answered ${response.status}`);
});

// n-4: Auth signs each retry of a hook call afresh — a new webhook-id, the
// same body (hookshttp: msgID is made inside the retry loop) — so the hook
// keys the delivery itself (number + code).
Deno.test("a retried or replayed delivery that was sent never sends a second code nor uses up a limit", async () => {
  const r = rig(decision());
  const first = await handleSendSms(await signed(payload()), r.deps);
  const retry = await handleSendSms(await signed(payload(), SECRET_BYTES, "msg_2"), r.deps);
  const replay = await handleSendSms(await signed(payload()), r.deps);
  for (const [what, response] of [["first", first], ["retry", retry], ["replay", replay]] as const) {
    const error = await errorOf(response);
    if (response.status !== 200 || error) throw new Error(`${what}: ${response.status} ${error}`);
  }
  if (r.delivered.length !== 1 || r.asked.length !== 1 || r.bumps.length !== 1) {
    throw new Error(`sent ${r.delivered.length}, decided ${r.asked.length}, counted ${r.bumps.length}`);
  }
  if (r.logs.filter((l) => l === "hook:duplicate").length !== 2) throw new Error(r.logs.join());
  const [key] = r.checks;
  if (!/^[0-9a-f]{64}$/.test(key) || r.checks.some((k) => k !== key) || key === r.asked[0][0]) {
    throw new Error(`delivery keys ${JSON.stringify(r.checks)}`);
  }
  // A new code for the same number is a new delivery.
  const before = r.delivered.length;
  await handleSendSms(await signed(payload(PHONE, "123456"), SECRET_BYTES, "msg_3"), r.deps);
  if (r.delivered.length !== before + 1 || r.checks.at(-1) === key) throw new Error("a new code was not sent");
});

// M-1 ruling: a delivery is marked sent only after a provider accepted it,
// so the retry of an attempt that sent nothing sends; never "sent" with
// nothing sent.
Deno.test("the retry of an attempt that sent nothing sends the code", async () => {
  const outcomes: Record<string, Outcome> = { arkesel: "failed", twilio: "failed" };
  const r = rig(decision(), outcomes);
  if (await errorOf(await handleSendSms(await signed(payload()), r.deps)) !== "503 otp:unavailable") {
    throw new Error("the failing first attempt did not fail");
  }
  if (r.marks.length) throw new Error("an attempt that sent nothing was marked sent");
  outcomes.arkesel = "sent";
  const retry = await handleSendSms(await signed(payload(), SECRET_BYTES, "msg_2"), r.deps);
  if (await errorOf(retry) !== null || r.asked.length !== 2 || r.delivered.at(-1)?.provider !== "arkesel") {
    throw new Error(`retry: decided ${r.asked.length}, ${JSON.stringify(r.delivered.map((d) => d.provider))}`);
  }
  if (r.marks.length !== 1 || r.bumps.join() !== "otp_sent:gh:sms:arkesel") throw new Error(r.marks.join());
});

Deno.test("the retry of a refused attempt is decided again, never answered as sent", async () => {
  const r = rig(decision({ allowed: false, reason: "number_hourly", routes: [], retry_after_s: 754 }));
  await handleSendSms(await signed(payload()), r.deps);
  const retry = await handleSendSms(await signed(payload(), SECRET_BYTES, "msg_2"), r.deps);
  if (r.asked.length !== 2 || await errorOf(retry) !== "429 otp:rate_limited:754" || r.marks.length) {
    throw new Error(`decided ${r.asked.length}, marked ${r.marks.length}`);
  }
  r.state.answer = decision();
  const third = await handleSendSms(await signed(payload(), SECRET_BYTES, "msg_3"), r.deps);
  if (await errorOf(third) !== null || r.delivered.length !== 1) throw new Error("the allowed retry did not send");
});

Deno.test("the mark comes only after a provider accepted; a failed mark still answers sent", async () => {
  const r = rig(decision(), { arkesel: "failed" });
  await handleSendSms(await signed(payload()), r.deps);
  if (r.events.join() !== "check,decide,deliver:arkesel,deliver:twilio,mark") throw new Error(r.events.join());
  const shaky = rig(decision());
  shaky.deps.markSent = () => Promise.reject(new Error("db down"));
  const response = await handleSendSms(await signed(payload()), shaky.deps);
  if (await errorOf(response) !== null || shaky.delivered.length !== 1 || !shaky.logs.includes("hook:mark_failed")) {
    throw new Error(`${shaky.logs.join()}`);
  }
});

Deno.test("a delivery check that can't be made sends nothing", async () => {
  const r = rig(decision());
  r.deps.alreadySent = () => Promise.reject(new Error("db down"));
  const response = await handleSendSms(await signed(payload()), r.deps);
  if (await errorOf(response) !== "503 otp:unavailable" || r.asked.length || r.delivered.length) {
    throw new Error("sent without a delivery check");
  }
});

// Batch 6 ruling: a code is never spoken to voicemail. A call a machine
// answers goes no further — not to another voice route — and the code goes
// by SMS. (No provider can answer "machine" in W2: calls are off, M-4.)
Deno.test("a call answered by a machine falls back to SMS, never another call", async () => {
  const r = rig(
    decision({
      channel: "voice",
      routes: [
        { channel: "voice", provider: "twilio" },
        { channel: "voice", provider: "meta" },
        { channel: "sms", provider: "arkesel" },
      ],
    }),
    { twilio: "machine" },
  );
  const response = await handleSendSms(await signed(payload()), r.deps);
  if (await errorOf(response) !== null) throw new Error("the SMS fallback was not sent");
  const used = r.delivered.map((d) => `${d.channel}:${d.provider}`).join();
  if (used !== "voice:twilio,sms:arkesel" || r.bumps.join() !== "otp_sent:gh:sms:arkesel") {
    throw new Error(`${used} / ${r.bumps.join()}`);
  }
  if (!r.logs.includes("hook:voice:twilio:machine")) throw new Error(r.logs.join());

  const noSms = rig(decision({ channel: "voice", routes: [{ channel: "voice", provider: "twilio" }] }), {
    twilio: "machine",
  });
  if (await errorOf(await handleSendSms(await signed(payload()), noSms.deps)) !== "503 otp:unavailable") {
    throw new Error("a machine answer counted as sent");
  }
});

// M-4 ruling: calls are hard-disabled in W2. No answering-machine check can
// finish inside Auth's 5 seconds, so no environment value may turn calls
// on; re-enabling them is a code change with real answering-machine
// handling. A decision of voice goes by SMS.
Deno.test("no environment value turns calls on; a voice decision goes by SMS", async () => {
  const calls: string[] = [];
  const fetchFn = (url: string, _: RequestInit) => {
    calls.push(url);
    return Promise.resolve(new Response("{}", { status: 201 }));
  };
  const secrets: Record<string, string> = {
    TWILIO_ACCOUNT_SID: "AC1", TWILIO_AUTH_TOKEN: "t", TWILIO_SMS_FROM: "+15550000000",
    TWILIO_VOICE_FROM: "+15550000001",
  };
  const voice: OutgoingCode = { channel: "voice", to: "+233244123456", otp: OTP, text: voiceText(OTP) };
  for (const value of [undefined, "", "1", "yes", "true", "TRUE", "on", "https://example.com/twiml"]) {
    // Every variable that isn't a Twilio secret answers [value]: whatever
    // a switch might be called, it is "on".
    const env = (name: string) => secrets[name] ?? value;
    if (await twilio(env, fetchFn)(voice) !== "unconfigured") throw new Error(`${value} placed a call`);
  }
  if (calls.length) throw new Error(`placed ${calls.join()}`);
  const source = await Deno.readTextFile(new URL("./providers.ts", import.meta.url));
  if (/OTP_VOICE/.test(source)) throw new Error("providers.ts still reads a voice switch");

  const r = rig(decision({
    channel: "voice",
    routes: [{ channel: "voice", provider: "twilio" }, { channel: "sms", provider: "twilio" }],
  }));
  r.deps.providers = providersFrom((name) => secrets[name] ?? "true", fetchFn);
  const response = await handleSendSms(await signed(payload()), r.deps);
  if (await errorOf(response) !== null || calls.length !== 1 || !calls[0].endsWith("/Messages.json")) {
    throw new Error(`calls ${calls.join()}`);
  }
  if (r.bumps.join() !== "otp_sent:gh:sms:twilio" || !r.logs.includes("hook:voice:twilio:unconfigured")) {
    throw new Error(`${r.bumps.join()} / ${r.logs.join()}`);
  }
});

// M-3: Auth gives the hook 5 seconds for the whole invocation, counted
// before the request reaches us (boot, transit); a late answer is a
// timeout whose code Auth throws away. The budget is 4 seconds from
// arrival: each provider gets at most what is left, none starts with
// under MIN_ATTEMPT_MS left, and two full provider calls fit.
Deno.test("the 4-second budget runs from arrival: a slow route leaves the next only what is left", async () => {
  if (DELIVERY_BUDGET_MS !== 4000 || PROVIDER_TIMEOUT_MS * 2 > DELIVERY_BUDGET_MS) {
    throw new Error(`budget ${DELIVERY_BUDGET_MS}, provider ${PROVIDER_TIMEOUT_MS}`);
  }
  const slow = rig(decision(), { arkesel: "failed" }, { decide: 200, arkesel: 2000 });
  await handleSendSms(await signed(payload()), slow.deps);
  const [first, second] = slow.delivered;
  if (first?.timeoutMs !== 2000 || second?.provider !== "twilio" || second.timeoutMs !== 1800) {
    throw new Error(JSON.stringify(slow.delivered.map((d) => [d.provider, d.timeoutMs])));
  }
  const late = rig(decision(), { arkesel: "failed" }, { decide: 1300, arkesel: 2000 });
  const response = await handleSendSms(await signed(payload()), late.deps);
  if (late.delivered.length !== 1 || await errorOf(response) !== "503 otp:unavailable") {
    throw new Error(`started a route with under ${MIN_ATTEMPT_MS} ms left: ${JSON.stringify(late.delivered)}`);
  }
  const stuck = rig(decision(), {}, { decide: 3300 });
  if (await errorOf(await handleSendSms(await signed(payload()), stuck.deps)) !== "503 otp:unavailable" ||
      stuck.delivered.length) {
    throw new Error("a provider was called after a slow decision");
  }
});

// M-6: the delivery check and the decision are bounded inside the budget;
// a timeout answers otp:unavailable and never sends, even if the answer
// comes later, and the call is aborted.
Deno.test("a decision that doesn't answer in time is otp:unavailable, aborted, and never sent", async () => {
  // The check leaves 850 ms: 50 ms for the decision, 800 for a provider.
  const r = rig(decision(), {}, { check: DELIVERY_BUDGET_MS - MIN_ATTEMPT_MS - 50 });
  let aborted = false;
  r.deps.decide = (_hmac, _country, _prefix, _userId, signal) => {
    r.asked.push(["late", "", ""]);
    signal.addEventListener("abort", () => aborted = true);
    return new Promise((resolve) => setTimeout(() => resolve(decision()), 300));
  };
  const startedAt = Date.now();
  const response = await handleSendSms(await signed(payload()), r.deps);
  const took = Date.now() - startedAt;
  if (await errorOf(response) !== "503 otp:unavailable" || took > 250 || !aborted) {
    throw new Error(`${took} ms, aborted ${aborted}`);
  }
  await new Promise((resolve) => setTimeout(resolve, 350));
  if (r.delivered.length || r.marks.length) throw new Error("the late decision sent a code");
});

Deno.test("with too little budget left for a decision and a send, no decision is asked", async () => {
  const r = rig(decision(), {}, { check: DELIVERY_BUDGET_MS - MIN_ATTEMPT_MS + 100 });
  const response = await handleSendSms(await signed(payload()), r.deps);
  if (await errorOf(response) !== "503 otp:unavailable" || r.asked.length || r.delivered.length) {
    throw new Error("decided without the time to send");
  }
});

Deno.test("a delivery check that doesn't answer in time is otp:unavailable and decides nothing", async () => {
  const r = rig(decision());
  let aborted = false;
  // Answers only when aborted (or, unbounded, after 2.5 s: too late).
  r.deps.alreadySent = (_key, signal) =>
    new Promise((_, reject) => {
      const tooLate = setTimeout(() => reject(new Error("never aborted")), 2500);
      signal.addEventListener("abort", () => {
        clearTimeout(tooLate);
        aborted = true;
        reject(new Error("aborted"));
      });
    });
  const startedAt = Date.now();
  const response = await handleSendSms(await signed(payload()), r.deps);
  const took = Date.now() - startedAt;
  if (await errorOf(response) !== "503 otp:unavailable" || r.asked.length || !aborted || took > 1500) {
    throw new Error(`${took} ms, decided ${r.asked.length}, aborted ${aborted}`);
  }
});

Deno.test("index.ts aborts every database call it makes", async () => {
  const source = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
  for (const rpc of ["otp_hook_delivery_sent", "otp_take_send_decision", "otp_mark_hook_delivery_sent", "bump_metric_server"]) {
    if (!new RegExp(`rpc\\("${rpc}",[^;]*?\\)\\s*\\.abortSignal\\(signal\\)`).test(source)) {
      throw new Error(`${rpc} is not aborted`);
    }
  }
});

// M-5: Arkesel's v2 send answers {"status": "success", "data": [{recipient,
// id}, …]} and {"status": "error", "message": …} (developers.arkesel.com
// spec/api_spec.v2.4.0.yaml, /api/v2/sms/send); an invalid number comes back
// as success with only {"invalid numbers": […]}. Sent means "success" with
// an id; anything else fails over.
Deno.test("Arkesel is sent only when its answer says success with an id", async () => {
  const env = (name: string) => ({ ARKESEL_API_KEY: "a", ARKESEL_SENDER_ID: "Attune" } as Record<string, string>)[name];
  const code: OutgoingCode = { channel: "sms", to: "+233244123456", otp: OTP, text: "t" };
  const answers: [number, string, string][] = [
    [200, '{"status":"success","data":[{"recipient":"233244123456","id":"9b752841-7ee7-4d40-b4fe-768bfb1da4f0"}]}', "sent"],
    [200, '{"status":"error","message":"Insufficient balance or invalid coverage!"}', "failed"],
    [200, '{"status":"success","data":[{"invalid numbers":["233244123456"]}]}', "failed"],
    [200, '{"status":"success","message":"SMS request sent successfully!"}', "failed"],
    [200, "OK", "failed"],
    [200, "", "failed"],
    [402, '{"status":"error","message":"Insufficient balance or invalid coverage!"}', "failed"],
    [200, `{"status":"success","data":[{"id":"x"}],"pad":"${"x".repeat(10_000)}"}`, "failed"],
  ];
  for (const [status, body, expected] of answers) {
    const fetchFn = (_: string, __: RequestInit) => Promise.resolve(new Response(body, { status }));
    const result = await arkesel(env, fetchFn)(code);
    if (result !== expected) throw new Error(`${status} ${body.slice(0, 60)}: ${result}`);
  }
});

Deno.test("Ghana fails over to Twilio when Arkesel answers 200 with an error", async () => {
  const calls: string[] = [];
  const fetchFn = (url: string, _: RequestInit) => {
    calls.push(url);
    return Promise.resolve(
      url.includes("arkesel")
        ? new Response('{"status":"error","message":"Insufficient balance or invalid coverage!"}', { status: 200 })
        : new Response('{"sid":"SM1"}', { status: 201 }),
    );
  };
  const secrets: Record<string, string> = {
    ARKESEL_API_KEY: "a", ARKESEL_SENDER_ID: "Attune",
    TWILIO_ACCOUNT_SID: "AC1", TWILIO_AUTH_TOKEN: "t", TWILIO_SMS_FROM: "+15550000000",
  };
  const r = rig(decision());
  r.deps.providers = providersFrom((name) => secrets[name], fetchFn);
  const response = await handleSendSms(await signed(payload()), r.deps);
  if (await errorOf(response) !== null || calls.length !== 2 || !calls[1].endsWith("/Messages.json") ||
      r.bumps.join() !== "otp_sent:gh:sms:twilio") {
    throw new Error(`${calls.join()} / ${r.bumps.join()}`);
  }
});

// Auth's payload carries the destination as sms.phone (for a phone change
// it differs from user.phone); limits, the delivery key and the send all use it.
Deno.test("the code goes to Auth's sms.phone when it is given", async () => {
  const r = rig(decision());
  await handleSendSms(await signed({ user: { id: "u1", phone: PHONE }, sms: { otp: OTP, phone: "447911123456" } }), r.deps);
  if (r.delivered[0]?.to !== "+447911123456" || r.asked[0][1] !== "GB" || r.asked[0][2] !== "+447911") {
    throw new Error(JSON.stringify([r.delivered, r.asked]));
  }
  const parked = rig(decision());
  await handleSendSms(await signed({ user: { id: "u1", phone: PHONE }, sms: { otp: OTP, phone: "999123456789012" } }), parked.deps);
  if (parked.delivered.length || parked.asked.length) throw new Error("a parked sms.phone was sent to");
});

Deno.test("a provider call is cut off at the time it is given", async () => {
  const hanging = (_: string, init: RequestInit) =>
    new Promise<Response>((_, reject) => init.signal?.addEventListener("abort", () => reject(new Error("aborted"))));
  const env = (name: string) => ({ ARKESEL_API_KEY: "a", ARKESEL_SENDER_ID: "Attune" } as Record<string, string>)[name];
  const startedAt = Date.now();
  const result = await arkesel(env, hanging)({ channel: "sms", to: "+233244123456", otp: OTP, text: "t" }, 50);
  const took = Date.now() - startedAt;
  if (result !== "failed" || took > 1000) throw new Error(`${result} after ${took} ms`);
});

// Final review I-2 (ruling): WhatsApp codes only for numbers with no account.
// The decision is asked with the account Auth will sign the code in to (its
// signed payload.user.id), so the server can send an existing account's
// code by SMS whatever was asked. No usable id is asked as none (null),
// which the server treats as an existing account: SMS.
Deno.test("the decision is asked with the payload's user id, and none when it has no usable one", async () => {
  const id = "5f1a0000-0000-4000-8000-0000000012b1";
  const r = rig(decision());
  const response = await handleSendSms(await signed({ user: { id, phone: PHONE }, sms: { otp: OTP } }), r.deps);
  if (await errorOf(response) !== null || r.askedUsers.length !== 1 || r.askedUsers[0] !== id) {
    throw new Error(`asked with ${JSON.stringify(r.askedUsers)}`);
  }
  if (r.logs.some((line) => line.includes(id))) throw new Error("the user id was logged");

  const unusable: unknown[] = [
    { phone: PHONE },
    { id: "u1", phone: PHONE },
    { id: 42, phone: PHONE },
    { id: `${id} OR 1=1`, phone: PHONE },
    undefined,
  ];
  for (const user of unusable) {
    const other = rig(decision());
    const answer = await handleSendSms(await signed({ user, sms: { otp: OTP, phone: PHONE } }), other.deps);
    if (await errorOf(answer) !== null || other.askedUsers.length !== 1 || other.askedUsers[0] !== null) {
      throw new Error(`${JSON.stringify(user)} was asked as ${JSON.stringify(other.askedUsers)}`);
    }
  }
});

Deno.test("index.ts passes the user id to otp_take_send_decision", async () => {
  const source = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
  if (!/rpc\("otp_take_send_decision",\s*\{[^}]*p_user_id:\s*userId,?[^}]*\}/.test(source)) {
    throw new Error("otp_take_send_decision is not asked with p_user_id");
  }
});

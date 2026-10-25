// Spec 1 W2c (§4.5, §7.2): the delivery intent endpoint.
import { handleIntent, type IntentRecord } from "./handler.ts";

const NONCE = btoa(String.fromCharCode(...new Uint8Array(16).fill(9)))
  .replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");

function rig(hmacKey: string | null = "test-key", fail = false) {
  const records: IntentRecord[] = [];
  const logs: string[] = [];
  return {
    records,
    logs,
    deps: {
      hmacKey: hmacKey ?? undefined,
      record: (intent: IntentRecord) => {
        if (fail) return Promise.reject(new Error("db down"));
        records.push(intent);
        return Promise.resolve();
      },
      log: (category: string) => logs.push(category),
    },
  };
}

const request = (body: unknown, ip = "203.0.113.9") =>
  new Request("http://x/otp-delivery-intent", {
    method: "POST",
    headers: { "x-forwarded-for": `${ip}, 10.0.0.1` },
    body: typeof body === "string" ? body : JSON.stringify(body),
  });

const good = { phone: "+233 24 412 3456", channel: "whatsapp", platform: "android", locale: "en-GH", device_nonce: NONCE };

Deno.test("a good request is stored as hashes only, and answered 204", async () => {
  const r = rig();
  const response = await handleIntent(request(good), r.deps);
  if (response.status !== 204) throw new Error(`status ${response.status}`);
  const stored = r.records[0];
  if (!stored || stored.p_channel !== "whatsapp" || stored.p_platform !== "android") {
    throw new Error(`stored ${JSON.stringify(stored)}`);
  }
  for (const value of [stored.p_phone_hmac, stored.p_device_hash, stored.p_ip_hash]) {
    if (!/^[0-9a-f]{64}$/.test(value)) throw new Error(`not a hash: ${value}`);
  }
  const text = JSON.stringify(stored) + r.logs.join(" ");
  for (const secret of ["233244123456", "203.0.113.9", NONCE]) {
    if (text.includes(secret)) throw new Error(`${secret} leaked`);
  }
});

Deno.test("204 whatever happens, and nothing stored for a bad request", async () => {
  for (const body of [
    "{not json",
    { ...good, device_nonce: undefined },
    { ...good, device_nonce: "too-short" },
    { ...good, channel: "pigeon" },
    { ...good, phone: "12" },
  ]) {
    const r = rig();
    const response = await handleIntent(request(body), r.deps);
    if (response.status !== 204) throw new Error(`status ${response.status} for ${JSON.stringify(body)}`);
    if (r.records.length !== 0) throw new Error(`stored ${JSON.stringify(body)}`);
  }
  const noKey = rig(null);
  if ((await handleIntent(request(good), noKey.deps)).status !== 204 || noKey.records.length !== 0) {
    throw new Error("stored without OTP_HMAC_KEY");
  }
  const failing = rig("k", true);
  if ((await handleIntent(request(good), failing.deps)).status !== 204) {
    throw new Error("a database failure changed the answer");
  }
});

Deno.test("an unknown platform is other; the locale is cut to 35 characters", async () => {
  const r = rig();
  await handleIntent(request({ ...good, platform: "symbian", locale: "x".repeat(60) }), r.deps);
  if (r.records[0].p_platform !== "other" || r.records[0].p_locale.length !== 35) {
    throw new Error(JSON.stringify(r.records[0]));
  }
});

Deno.test("the endpoint logs nothing but categories", async () => {
  const handler = await Deno.readTextFile(new URL("./handler.ts", import.meta.url));
  const index = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
  if (/console\./.test(handler)) throw new Error("the handler logs directly");
  if (/console\.log\([^)]*(phone|nonce|ip)\b/.test(index)) throw new Error("index logs a value");
});

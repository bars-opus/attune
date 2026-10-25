// Spec 1 W2c (batch 7 review I-1): the per-IP bucket is the address
// Supabase's front door saw, never the first x-forwarded-for entry, which
// the client writes (the front door appends to a client's header).
import { handleIntent, type IntentRecord } from "./handler.ts";

const NONCE = btoa(String.fromCharCode(...new Uint8Array(16).fill(9)))
  .replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
const good = { phone: "+233 24 412 3456", channel: "whatsapp", platform: "android", locale: "en-GH", device_nonce: NONCE };

async function bucket(headers: Record<string, string>): Promise<string> {
  const records: IntentRecord[] = [];
  await handleIntent(
    new Request("http://x/otp-delivery-intent", { method: "POST", headers, body: JSON.stringify(good) }),
    {
      hmacKey: "test-key",
      record: (intent) => {
        records.push(intent);
        return Promise.resolve();
      },
      log: () => {},
    },
  );
  if (records.length !== 1) throw new Error(`stored ${records.length}`);
  return records[0].p_ip_hash;
}

Deno.test("a forged first x-forwarded-for entry never makes a new bucket", async () => {
  const a = await bucket({ "x-forwarded-for": "1.1.1.1, 198.51.100.7", "cf-connecting-ip": "198.51.100.7" });
  const b = await bucket({ "x-forwarded-for": "2.2.2.2, 198.51.100.7", "cf-connecting-ip": "198.51.100.7" });
  if (a !== b) throw new Error("same bucket? false");
});

Deno.test("without cf-connecting-ip the right-most x-forwarded-for entry decides", async () => {
  const seen = await bucket({ "cf-connecting-ip": "198.51.100.7" });
  const c = await bucket({ "x-forwarded-for": "1.1.1.1, 198.51.100.7" });
  const d = await bucket({ "x-forwarded-for": "2.2.2.2, 198.51.100.7" });
  if (c !== d || c !== seen) throw new Error("the right-most entry did not decide");
  const other = await bucket({ "x-forwarded-for": "1.1.1.1, 198.51.100.8" });
  if (other === c) throw new Error("two addresses shared a bucket");
  const cfWins = await bucket({ "x-forwarded-for": "198.51.100.8", "cf-connecting-ip": "198.51.100.7" });
  if (cfWins !== seen) throw new Error("x-forwarded-for beat cf-connecting-ip");
});

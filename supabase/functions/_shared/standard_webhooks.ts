// supabase/functions/_shared/standard_webhooks.ts
//
// Verifies a Standard Webhooks signature (https://www.standardwebhooks.com),
// the scheme Supabase Auth signs its HTTP hooks with. No dependency: the
// HMAC is WebCrypto's, the comparison constant-time.
import { constantTimeEqual } from "./attune_auth.ts";

/// Five minutes either way, the standard's tolerance.
export const TOLERANCE_SECONDS = 5 * 60;

/// [secret] as the dashboard shows it: "v1,whsec_<base64>".
export async function verifyStandardWebhook(
  secret: string,
  headers: Headers,
  body: string,
  nowSeconds: number,
): Promise<boolean> {
  const id = headers.get("webhook-id");
  const timestamp = headers.get("webhook-timestamp");
  const signatures = headers.get("webhook-signature");
  if (!id || !timestamp || !signatures || !/^\d+$/.test(timestamp)) return false;
  if (Math.abs(nowSeconds - Number(timestamp)) > TOLERANCE_SECONDS) return false;

  const encoded = secret.replace(/^v1,/, "").replace(/^whsec_/, "");
  let key: Uint8Array;
  try {
    key = Uint8Array.from(atob(encoded), (c) => c.charCodeAt(0));
  } catch {
    return false;
  }
  if (key.length === 0) return false;
  const cryptoKey = await crypto.subtle.importKey(
    "raw",
    new Uint8Array(key),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signed = await crypto.subtle.sign(
    "HMAC",
    cryptoKey,
    new TextEncoder().encode(`${id}.${timestamp}.${body}`),
  );
  const expected = btoa(String.fromCharCode(...new Uint8Array(signed)));
  // Space-delimited per the standard; Supabase Auth joins its secrets'
  // signatures with ", ", so an entry may end with a comma (base64 never
  // does).
  return signatures
    .split(/\s+/)
    .map((entry) => entry.replace(/,$/, ""))
    .some((entry) => entry.startsWith("v1,") && constantTimeEqual(entry.slice(3), expected));
}

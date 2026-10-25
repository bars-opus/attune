// supabase/functions/_shared/otp_phone.ts
//
// Spec 1 W2c (§4.1 rule 5, §4.5): what the two phone-code functions share.
// A number is only ever HMACed (OTP_HMAC_KEY) or reduced to its country and
// leading digits; it is never logged or stored as is.

/// '+' and digits, or null when it can't be an E.164 number. Auth stores a
/// phone without the '+', the app sends it with one: both HMAC alike.
export function canonicalPhone(raw: unknown): string | null {
  if (typeof raw !== "string") return null;
  const digits = raw.replace(/\D/g, "");
  if (digits.length < 7 || digits.length > 15 || digits.startsWith("0")) return null;
  return `+${digits}`;
}

function hex(bytes: ArrayBuffer): string {
  return Array.from(new Uint8Array(bytes))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

/// HMAC-SHA256 of [message] under [key], lower-case hex.
export async function hmacHex(key: string, message: string): Promise<string> {
  const cryptoKey = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(key),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  return hex(await crypto.subtle.sign("HMAC", cryptoKey, new TextEncoder().encode(message)));
}

export async function sha256Hex(bytes: Uint8Array): Promise<string> {
  return hex(await crypto.subtle.digest("SHA-256", new Uint8Array(bytes)));
}

/// The phone's HMAC, as private.otp_* tables store it.
export function phoneHmac(key: string, phone: string): Promise<string> {
  return hmacHex(key, phone);
}

/// The leading digits the destination rules match on: '+' and at most six
/// digits. Enough for the longest rule, too few to identify anyone.
export function callingPrefix(phone: string): string {
  return phone.slice(0, 7);
}

/// Canadian area codes (NANP): +1 numbers outside them count as US.
const CANADA = new Set([
  "204", "226", "236", "249", "250", "257", "263", "289", "306", "343", "354",
  "365", "367", "368", "382", "403", "416", "418", "428", "431", "437", "438",
  "450", "460", "468", "474", "506", "514", "519", "548", "579", "581", "584",
  "587", "604", "613", "639", "647", "672", "683", "705", "709", "742", "753",
  "778", "780", "782", "807", "819", "825", "867", "873", "879", "902", "905",
]);

/// The launch countries (GH, GB, US, CA, NG, KE) by calling code; every
/// other number is 'XX' and uses the default routes.
export function countryOf(phone: string): string {
  if (phone.startsWith("+233")) return "GH";
  if (phone.startsWith("+234")) return "NG";
  if (phone.startsWith("+254")) return "KE";
  if (phone.startsWith("+44")) return "GB";
  if (phone.startsWith("+1")) return CANADA.has(phone.slice(2, 5)) ? "CA" : "US";
  return "XX";
}

/// The app's device nonce: 16 random bytes, base64url without padding.
export function decodeNonce(raw: unknown): Uint8Array | null {
  if (typeof raw !== "string" || !/^[A-Za-z0-9_-]{22}$/.test(raw)) return null;
  const base64 = raw.replace(/-/g, "+").replace(/_/g, "/") + "==";
  try {
    const bytes = Uint8Array.from(atob(base64), (c) => c.charCodeAt(0));
    return bytes.length === 16 ? bytes : null;
  } catch {
    return null;
  }
}

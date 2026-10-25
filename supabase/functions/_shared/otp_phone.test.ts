// Spec 1 W2c: the phone helpers the two code functions share.
import { callingPrefix, canonicalPhone, countryOf, decodeNonce, phoneHmac, sha256Hex } from "./otp_phone.ts";

function eq(actual: unknown, expected: unknown, what: string) {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(`${what}: expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`);
  }
}

Deno.test("the app's +E.164 and Auth's bare digits are one number", async () => {
  eq(canonicalPhone("+233 24 412 3456"), "+233244123456", "app form");
  eq(canonicalPhone("233244123456"), "+233244123456", "Auth form");
  eq(
    await phoneHmac("k", canonicalPhone("+233 24 412 3456")!),
    await phoneHmac("k", canonicalPhone("233244123456")!),
    "same HMAC",
  );
  eq(canonicalPhone("12"), null, "too short");
  eq(canonicalPhone("0244123456"), null, "a national number is not E.164");
  eq(canonicalPhone(42), null, "not a string");
});

Deno.test("country and prefix, never the whole number", () => {
  eq(countryOf("+233244123456"), "GH", "Ghana");
  eq(countryOf("+447911123456"), "GB", "UK");
  eq(countryOf("+14165550123"), "CA", "Toronto");
  eq(countryOf("+12025550123"), "US", "Washington");
  eq(countryOf("+2348031234567"), "NG", "Nigeria");
  eq(countryOf("+33612345678"), "XX", "elsewhere");
  eq(callingPrefix("+233244123456"), "+233244", "prefix");
});

Deno.test("a device nonce is 16 bytes of base64url, hashed", async () => {
  const bytes = new Uint8Array(16).fill(7);
  const nonce = btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
  eq(decodeNonce(nonce)?.length, 16, "decoded");
  eq(decodeNonce("short"), null, "too short");
  eq(decodeNonce(undefined), null, "missing");
  eq((await sha256Hex(bytes)).length, 64, "hex digest");
});

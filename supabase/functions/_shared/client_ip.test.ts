// Spec 1 W2c (batch 7 review I-1): the caller's address for per-IP limits.
import { clientIp } from "./client_ip.ts";

const ip = (headers: Record<string, string>) => clientIp(new Headers(headers));

function eq(actual: unknown, expected: unknown, what: string) {
  if (actual !== expected) throw new Error(`${what}: expected ${expected}, got ${actual}`);
}

Deno.test("cf-connecting-ip first, then the right-most x-forwarded-for entry, never the first", () => {
  eq(ip({ "cf-connecting-ip": " 198.51.100.7 ", "x-forwarded-for": "1.1.1.1, 203.0.113.4" }), "198.51.100.7", "cf");
  eq(ip({ "x-forwarded-for": "1.1.1.1, 203.0.113.4" }), "203.0.113.4", "right-most");
  eq(ip({ "x-forwarded-for": "1.1.1.1, 203.0.113.4, , " }), "203.0.113.4", "right-most non-empty");
  eq(ip({ "x-forwarded-for": "203.0.113.4" }), "203.0.113.4", "one entry");
  eq(ip({ "cf-connecting-ip": "2001:DB8::1" }), "2001:db8::1", "IPv6, lower-cased");
});

Deno.test("anything that isn't an address is unknown, never a value the client chose", () => {
  eq(ip({}), "unknown", "no header");
  eq(ip({ "cf-connecting-ip": "not-an-ip", "x-forwarded-for": "1.1.1.1, 203.0.113.4" }), "203.0.113.4", "bad cf");
  eq(ip({ "x-forwarded-for": "203.0.113.4, evil" }), "unknown", "junk right-most");
  eq(ip({ "x-forwarded-for": "203.0.113.4, 999.1.1.1" }), "unknown", "not an IPv4");
  eq(ip({ "x-forwarded-for": "   " }), "unknown", "blank");
});

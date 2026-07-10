// Run with: deno test supabase/functions/_shared/sanitize.test.ts

import {
  assertEquals,
  assertThrows,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  redactForLog,
  sanitizeAmount,
  sanitizeCurrency,
  sanitizeIdentifier,
  sanitizeText,
} from "./sanitize.ts";

// ── sanitizeText ────────────────────────────────────────────

Deno.test("sanitizeText: returns empty for null/undefined", () => {
  assertEquals(sanitizeText(null), "");
  assertEquals(sanitizeText(undefined), "");
});

Deno.test("sanitizeText: strips control chars and ANSI escapes", () => {
  const dirty = "hello\x00world\x1B[31mred\x1B[0m";
  assertEquals(sanitizeText(dirty), "helloworldred");
});

Deno.test("sanitizeText: collapses whitespace", () => {
  assertEquals(sanitizeText("a   b\t\tc\n\nd"), "a b c d");
});

Deno.test("sanitizeText: strips HTML by default", () => {
  assertEquals(
    sanitizeText("<b>hi</b> <script>alert(1)</script> world"),
    "hi  world",
  );
});

Deno.test("sanitizeText: rejects HTML when rejectHtml=true", () => {
  assertThrows(
    () => sanitizeText("<b>nope</b>", { rejectHtml: true }),
    Error,
    "HTML not allowed",
  );
});

Deno.test("sanitizeText: caps at maxLength", () => {
  const long = "x".repeat(1500);
  assertEquals(sanitizeText(long, { maxLength: 100 }).length, 100);
});

Deno.test("sanitizeText: throws when shorter than minLength", () => {
  assertThrows(
    () => sanitizeText("ab", { minLength: 5 }),
    Error,
    "minimum length is 5",
  );
});

Deno.test("sanitizeText: throws on non-string input", () => {
  assertThrows(() => sanitizeText(42 as unknown as string), Error);
});

// ── sanitizeIdentifier ──────────────────────────────────────

Deno.test("sanitizeIdentifier: strips disallowed chars", () => {
  assertEquals(
    sanitizeIdentifier("abc-123_DEF; DROP TABLE--"),
    "abc-123_DEFDROPTABLE--",
  );
});

Deno.test("sanitizeIdentifier: caps at maxLength", () => {
  assertEquals(sanitizeIdentifier("a".repeat(200), 10).length, 10);
});

// ── sanitizeAmount ──────────────────────────────────────────

Deno.test("sanitizeAmount: accepts numbers and numeric strings", () => {
  assertEquals(sanitizeAmount(50), 50);
  assertEquals(sanitizeAmount("50.5"), 50.5);
});

Deno.test("sanitizeAmount: rounds to 2 decimal places", () => {
  assertEquals(sanitizeAmount(50.567), 50.57);
});

Deno.test("sanitizeAmount: rejects NaN / Infinity", () => {
  assertThrows(() => sanitizeAmount("not a number"));
  assertThrows(() => sanitizeAmount(Infinity));
});

Deno.test("sanitizeAmount: enforces min/max", () => {
  assertThrows(
    () => sanitizeAmount(5, { min: 10 }),
    Error,
    "below minimum",
  );
  assertThrows(
    () => sanitizeAmount(10_000, { max: 5000 }),
    Error,
    "above maximum",
  );
});

// ── sanitizeCurrency ────────────────────────────────────────

Deno.test("sanitizeCurrency: uppercases and validates ISO format", () => {
  assertEquals(sanitizeCurrency("ghs"), "GHS");
  assertEquals(sanitizeCurrency(" usd "), "USD");
});

Deno.test("sanitizeCurrency: rejects non-3-letter codes", () => {
  assertThrows(() => sanitizeCurrency("GH"));
  assertThrows(() => sanitizeCurrency("GHANA"));
  assertThrows(() => sanitizeCurrency("12X"));
});

// ── redactForLog ────────────────────────────────────────────

Deno.test("redactForLog: redacts well-known sensitive keys", () => {
  const input = {
    user: "alice",
    password: "secret",
    api_key: "sk_live_xxx",
    nested: { token: "abc" },
  };
  const out = redactForLog(input) as Record<string, unknown>;
  assertEquals(out.user, "alice");
  assertEquals(out.password, "[REDACTED]");
  assertEquals(out.api_key, "[REDACTED]");
  assertEquals(
    (out.nested as Record<string, unknown>).token,
    "[REDACTED]",
  );
});

Deno.test("redactForLog: handles arrays", () => {
  const input = [{ secret: "x" }, { ok: "y" }];
  const out = redactForLog(input) as Array<Record<string, unknown>>;
  assertEquals(out[0].secret, "[REDACTED]");
  assertEquals(out[1].ok, "y");
});

Deno.test("redactForLog: bottoms out at depth limit", () => {
  // Build a 10-deep nested object; depth limit is 5.
  let obj: Record<string, unknown> = { x: "leaf" };
  for (let i = 0; i < 10; i++) obj = { wrap: obj };
  const out = redactForLog(obj);
  // Just verifies it doesn't blow the stack; the leaf will be "[depth-limit]".
  assertEquals(typeof out, "object");
});

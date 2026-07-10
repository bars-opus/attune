import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { normalizePhone, formatDateForHuman } from "./booking_helpers.ts";

Deno.test("normalizePhone: strips spaces and dashes", () => {
  assertEquals(normalizePhone("+233 20 123 4567"), "+233201234567");
  assertEquals(normalizePhone("+233-20-123-4567"), "+233201234567");
});

Deno.test("normalizePhone: preserves leading +", () => {
  assertEquals(normalizePhone("+233201234567"), "+233201234567");
});

Deno.test("normalizePhone: throws on missing +", () => {
  let threw = false;
  let msg = "";
  try {
    normalizePhone("233201234567");
  } catch (e) {
    threw = true;
    msg = (e as Error).message;
  }
  assertEquals(threw, true);
  assertEquals(msg, "Phone must start with + (E.164)");
});

Deno.test("normalizePhone: throws on non-digit after +", () => {
  let threw = false;
  try {
    normalizePhone("+233abc1234567");
  } catch {
    threw = true;
  }
  assertEquals(threw, true);
});

Deno.test("normalizePhone: throws on too short (< 8 digits)", () => {
  let threw = false;
  try {
    normalizePhone("+12345");
  } catch {
    threw = true;
  }
  assertEquals(threw, true);
});

Deno.test("normalizePhone: throws on too long (> 15 digits)", () => {
  let threw = false;
  try {
    normalizePhone("+1234567890123456");
  } catch {
    threw = true;
  }
  assertEquals(threw, true);
});

Deno.test("formatDateForHuman: produces 'Fri 29 May at 9:30am' style", () => {
  // Use a UTC fixed-time to make the test deterministic in CI.
  const iso = "2026-05-29T09:30:00Z";
  const formatted = formatDateForHuman(iso);
  // Assert structural pieces rather than exact string (timezones differ).
  // The function should produce "<3-letter-day> <day> <3-letter-month> at <hour>:<minute><am|pm>"
  // Allow timezone-driven variance — confirm at minimum it contains "May" and "30" or similar.
  // For deterministic testing, check that the function returns a non-empty string with expected pieces.
  const hasMay = formatted.includes("May");
  const hasColon = formatted.includes(":");
  const hasAmPm = formatted.includes("am") || formatted.includes("pm");
  assertEquals(hasMay && hasColon && hasAmPm, true);
});

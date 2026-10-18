import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { STATIC_PROHIBITED_PATTERNS } from "./gemini_json.ts";

Deno.test("STATIC_PROHIBITED_PATTERNS: flags banned diagnostic words", () => {
  const text = '{"observation":"this pattern seems toxic"}';
  const hit = STATIC_PROHIBITED_PATTERNS.some((p) => p.test(text));
  assertEquals(hit, true);
});

Deno.test("STATIC_PROHIBITED_PATTERNS: flags partner-directed always/never framing", () => {
  const text = '{"observation":"your partner always dismisses you"}';
  const hit = STATIC_PROHIBITED_PATTERNS.some((p) => p.test(text));
  assertEquals(hit, true);
});

Deno.test("STATIC_PROHIBITED_PATTERNS: allows neutral, sourced language", () => {
  const text = '{"observation":"you described this using always/never terms"}';
  const hit = STATIC_PROHIBITED_PATTERNS.some((p) => p.test(text));
  assertEquals(hit, false);
});

Deno.test("callGeminiJson: returns null when GEMINI_API_KEY is missing", async () => {
  const original = Deno.env.get("GEMINI_API_KEY");
  Deno.env.delete("GEMINI_API_KEY");
  try {
    const { callGeminiJson } = await import("./gemini_json.ts?no-key-test");
    const result = await callGeminiJson({
      promptId: "test",
      systemPrompt: "sys",
      userPrompt: "usr",
      maxOutputTokens: 100,
      attribution: { fn: "test" },
    });
    assertEquals(result, null);
  } finally {
    if (original) Deno.env.set("GEMINI_API_KEY", original);
  }
});

// Spec 8 (research 06 F15 (4); 05 S11): no negative attribution of a named
// third party (family, friends, an ex, a boss) — the model never sides
// against someone who is not in the room.
Deno.test("STATIC_PROHIBITED_PATTERNS: flags negative attribution of a third party", () => {
  for (const text of [
    "her mother always interferes",
    "your family is so controlling",
    "his ex is the problem here",
    "their parents never respect your choices",
    "your sister is trying to split you up",
    "your in-laws are to blame",
    "your mum always criticises how you cook",
    "her brother is trying to turn you against her",
    "your family is against you",
    "his dad hates you",
  ]) {
    assertEquals(STATIC_PROHIBITED_PATTERNS.some((p) => p.test(text)), true, text);
  }
});

Deno.test("STATIC_PROHIBITED_PATTERNS: allows neutral mentions of family", () => {
  for (const text of [
    "you mentioned your mother's visit on Sunday",
    "her family is coming over this weekend",
    "you both talked about his parents' anniversary",
    "family obligations came up a few times",
    // Final review I-7: neutral and kind mentions are not blame.
    "Your mother is trying to help you.",
    "Your parents always call on Sundays.",
    "Her family is against the move for good reasons, and you can talk it through.",
    "His boss hates late reports",
    "My mother-in-law always visits on Sundays and I need notice",
    "your parents always support you",
    "their friends never miss a birthday",
  ]) {
    assertEquals(STATIC_PROHIBITED_PATTERNS.some((p) => p.test(text)), false, text);
  }
});

Deno.test("claude_json uses the same, single list (no stale copy)", async () => {
  const src = await Deno.readTextFile(new URL("./claude_json.ts", import.meta.url));
  assertEquals(/export const STATIC_PROHIBITED_PATTERNS\s*=/.test(src), false);
});

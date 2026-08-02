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
    });
    assertEquals(result, null);
  } finally {
    if (original) Deno.env.set("GEMINI_API_KEY", original);
  }
});

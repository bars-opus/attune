// Every LLM-calling function must go through Gemini.
//
// Five of the seven had their own inline Anthropic client -- separate
// request shapes, separate timeouts, separate JSON extraction, and in two
// cases no prohibited-pattern filter at all. Those copies are why the port
// touched seven files instead of one, and why this test guards the seam
// rather than any single function.
//
// A reverted import is silent: CLAUDE_API_KEY is unset, so callClaudeJson
// returns null and the caller falls back to boilerplate. The feature looks
// "working but bland" rather than broken, which is exactly how these five
// sat unnoticed after the switch to Gemini.

import { assertEquals, assertStringIncludes } from
  "https://deno.land/std@0.208.0/assert/mod.ts";

const FUNCTIONS = [
  "analyse-message",
  "analyse-session",
  "generate-verdict",
  "translate-conflict",
  "generate-healing-portrait",
  "generate-healing-post-mortem",
  "generate-thirty-six-reflection",
];

async function source(fn: string): Promise<string> {
  return await Deno.readTextFile(
    new URL(`../${fn}/index.ts`, import.meta.url),
  );
}

Deno.test("no function calls Anthropic directly", async () => {
  for (const fn of FUNCTIONS) {
    const src = await source(fn);
    assertEquals(
      src.includes("api.anthropic.com"),
      false,
      `${fn} still posts to the Anthropic API`,
    );
    assertEquals(
      src.includes("CLAUDE_API_KEY"),
      false,
      `${fn} still reads CLAUDE_API_KEY, which is not set -- it would fall ` +
        `back to boilerplate with no error`,
    );
    assertEquals(
      src.includes("callClaudeJson"),
      false,
      `${fn} still calls the Claude helper`,
    );
  }
});

Deno.test("every LLM call goes through the shared Gemini helper", async () => {
  for (const fn of FUNCTIONS) {
    const src = await source(fn);
    assertStringIncludes(
      src,
      "callGeminiJson",
      `${fn} does not use the shared helper`,
    );
    assertStringIncludes(
      src,
      "gemini_json.ts",
      `${fn} does not import the shared helper`,
    );
  }
});

Deno.test("partnerNamePatterns moved with the port", async () => {
  // analyse-message and analyse-session pass these as runtime prohibited
  // patterns. It lived in claude_json.ts; had it not moved, the import
  // would break -- but a future edit could quietly drop the argument
  // instead, silently removing the filter that stops the model
  // characterising a named partner in absolutes.
  const helper = await Deno.readTextFile(
    new URL("./gemini_json.ts", import.meta.url),
  );
  assertStringIncludes(helper, "export function partnerNamePatterns");

  for (const fn of ["analyse-message", "analyse-session"]) {
    const src = await source(fn);
    assertStringIncludes(
      src,
      "runtimeProhibitedPatterns",
      `${fn} no longer passes its runtime pattern filter`,
    );
  }
});

Deno.test("the persisted model name is not a stale Claude constant", async () => {
  // generate-verdict and the two healing functions write model_name onto
  // the row they generate. Left as the Claude constant it would label
  // every Gemini output as claude-sonnet, corrupting the provenance of
  // any later quality review.
  for (
    const fn of [
      "generate-verdict",
      "generate-healing-portrait",
      "generate-healing-post-mortem",
    ]
  ) {
    const src = await source(fn);
    if (!src.includes("model_name")) continue;
    assertEquals(
      src.includes('"claude-sonnet-4-20250514"'),
      false,
      `${fn} would record a Claude model name for a Gemini generation`,
    );
  }
});

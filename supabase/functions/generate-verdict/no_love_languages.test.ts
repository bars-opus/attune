// Spec 5 (R5-5, §8.7): what feels loving is never a readout input.
import { assert } from "https://deno.land/std@0.224.0/assert/mod.ts";

const src = await Deno.readTextFile(new URL("./index.ts", import.meta.url));

Deno.test("generate-verdict does not read love_languages", () => {
  assert(!src.includes("love_languages"), "love_languages is selected or used");
  assert(!src.includes('"love_language"'), "the love_language quiz type is read");
});

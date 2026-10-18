// Spec 8 (plan review I7; sync audit M-13): the writer-facing corpus, on its
// own. Self-harm always runs; the [DRAFT] victimisation list only where its
// flag is on.
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { normalizeForTokenPhrase } from "./chat_safety.ts";
import { detectSelfDisclosure, SELF_DISCLOSURE_CONFIG } from "./self_disclosure.ts";

const on = { victimisation: true };
const off = { victimisation: false };

Deno.test("victimisation, any gender, only with the flag", () => {
  for (
    const t of [
      "he hits me when he's drunk", "she hurt me", "they hurt me", "my partner hurt me",
      "my wife threatened me", "I'm scared of them", "he hit me last night", "he won't let me see my friends", "he choked me",
    ]
  ) {
    assertEquals(detectSelfDisclosure(t, on), "victimisation", t);
    assertEquals(detectSelfDisclosure(t, off), null, t);
  }
});

Deno.test("self-harm runs either way", () => {
  assertEquals(detectSelfDisclosure("I want to kill myself", on), "self_harm");
  assertEquals(detectSelfDisclosure("I want to kill myself", off), "self_harm");
});

Deno.test("ordinary sentences are not disclosures", () => {
  for (const t of ["we had a lovely dinner", "the film hit me hard", "you hurt my feelings earlier", ""]) {
    assertEquals(detectSelfDisclosure(t, on), null, t);
  }
});

Deno.test("a draft corpus, pre-normalised", () => {
  assert(SELF_DISCLOSURE_CONFIG.config_version.endsWith("-draft"), "clinician sign-off pending");
  for (const family of Object.values(SELF_DISCLOSURE_CONFIG.families)) {
    for (const p of family.phrases) assertEquals(normalizeForTokenPhrase(p).trim(), p, p);
  }
});

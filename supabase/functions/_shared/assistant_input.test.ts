// Spec 8 (research 06 F11, F15 (2); plan review C3, I6, I7): what Understand,
// Assist and the translator do before any provider call.
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { normalizeForTokenPhrase } from "./chat_safety.ts";
import { DO_NOT_INTERPRET_CONFIG, matchesDoNotInterpret } from "./do_not_interpret.ts";
import { detectSelfDisclosure, SELF_DISCLOSURE_CONFIG } from "./self_disclosure.ts";
import { classifyAssistantInput } from "./assistant_input.ts";

Deno.test("a no is recognised; ordinary sentences with the same words are not", () => {
  for (const yes of ["Not tonight.", "Stop.", "stop", "No.", "I don't want to", "Please stop!", "Leave me alone",
    "I said no.", "Okay. Not tonight, I'm tired.", "no means no",
    // Final review m-1: a refusal with a longer tail is still a refusal.
    "I don't want to talk about it", "I don't want to talk about this right now."]) {
    assert(matchesDoNotInterpret(yes), yes);
  }
  for (const no of ["I can't stop thinking about you", "Can you stop by the shop on the way?", "No worries at all",
    "There's no milk left, can you get some?", "I don't want to miss the bus", "Bus stop at 6?",
    // ...and a polite "no" about something else is not a boundary to protect.
    "No, I'm fine", "no thanks", "No, I'm fine, thanks for asking!"]) {
    assert(!matchesDoNotInterpret(no), no);
  }
});

Deno.test("every corpus pattern is already normalised", () => {
  for (const p of [...DO_NOT_INTERPRET_CONFIG.phrases, ...DO_NOT_INTERPRET_CONFIG.long_tail_phrases, ...DO_NOT_INTERPRET_CONFIG.short_sentence_tokens]) {
    assertEquals(normalizeForTokenPhrase(p).trim(), p, p);
  }
  for (const family of Object.values(SELF_DISCLOSURE_CONFIG.families)) {
    for (const p of family.phrases) assertEquals(normalizeForTokenPhrase(p).trim(), p, p);
  }
  assert(SELF_DISCLOSURE_CONFIG.config_version.endsWith("-draft"), "clinician sign-off pending");
});

Deno.test("self-disclosure families", () => {
  const on = { victimisation: true };
  assertEquals(detectSelfDisclosure("I want to kill myself", on), "self_harm");
  assertEquals(detectSelfDisclosure("he hits me when he's drunk", on), "victimisation");
  assertEquals(detectSelfDisclosure("we had a lovely dinner", on), null);
  // Final review m-2: not only he/she.
  for (const t of ["they hurt me", "my partner hurt me", "my wife threatened me", "I'm scared of them"]) {
    assertEquals(detectSelfDisclosure(t, on), "victimisation", t);
  }
});

// Final review I-6: the victimisation list is a draft; it runs only where
// its flag is on. Self-harm (the reviewed sessions corpus) always runs.
Deno.test("the draft list runs only with its flag", () => {
  const off = { victimisation: false };
  assertEquals(detectSelfDisclosure("he hits me", off), null);
  assertEquals(detectSelfDisclosure("I want to kill myself", off), "self_harm");
  const partnerOff = (t: string) =>
    classifyAssistantInput({ targetContent: t, targetByRequester: false, draftLexicon: false });
  const mineOff = (t: string) =>
    classifyAssistantInput({ targetContent: t, targetByRequester: true, draftLexicon: false });
  assertEquals(partnerOff("he hits me"), { outcome: "proceed" });
  assertEquals(mineOff("he hits me"), { outcome: "proceed" });
  assertEquals(partnerOff("I want to kill myself"), { outcome: "supporter" });
  assertEquals(partnerOff("I'll kill you"), { outcome: "unsafe_to_infer" });
});

Deno.test("the outcome table (review §2.2)", () => {
  const partner = (t: string) =>
    classifyAssistantInput({ targetContent: t, targetByRequester: false, draftLexicon: true });
  const mine = (t: string, instruction?: string) =>
    classifyAssistantInput({ targetContent: t, targetByRequester: true, instruction, draftLexicon: true });
  assertEquals(partner("Not tonight."), { outcome: "boundary" });
  assertEquals(partner("I want to kill myself"), { outcome: "supporter" });
  assertEquals(partner("I'll kill you"), { outcome: "unsafe_to_infer" });
  assertEquals(partner("he hits me"), { outcome: "unsafe_to_infer" });
  assertEquals(partner("dinner at 7?"), { outcome: "proceed" });
  assertEquals(mine("I want to kill myself"), { outcome: "writer_resources" });
  assertEquals(mine("dinner?", "he hits me and I don't know what to say"), { outcome: "writer_resources" });
  // A person's own "no" is not interpreted at them.
  assertEquals(mine("Not tonight."), { outcome: "proceed" });
});

Deno.test("only the outcome travels: no family, rule or tier", () => {
  for (const t of ["Not tonight.", "I want to kill myself", "I'll kill you", "hello"]) {
    assertEquals(
      Object.keys(classifyAssistantInput({ targetContent: t, targetByRequester: false, draftLexicon: true })),
      ["outcome"],
    );
  }
});

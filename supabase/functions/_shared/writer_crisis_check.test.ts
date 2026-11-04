// Spec 1 W9e: the writer-facing crisis check, shared by the Journal (W9c)
// and Healing (W9e). Deterministic; any doubt is a match.
import { assert, assertEquals, assertStrictEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { foldTypography, writerTextDiscloses } from "./writer_crisis_check.ts";
import { JOURNAL_SELF_HARM_PENDING, matchesPendingSelfHarm } from "./self_harm_pending.ts";
import * as journalList from "../analyse-journal-entry/journal_self_harm_pending.ts";

const ORDINARY = "We walked by the lagoon and I thought about what I would do differently next time.";
const THROWS = { toString(): string { throw new Error("unreadable"); } } as unknown as string;

Deno.test("the reviewed corpus and the pending list match, whatever private_safety_check says", () => {
  for (const victimisation of [true, false]) {
    for (const text of ["I want to kill myself", "Some days I want to die", "I took all of my pills", "nobody would even miss me"]) {
      assert(writerTextDiscloses(text, victimisation), `${text} (victimisation ${victimisation})`);
    }
  }
});

Deno.test("the [DRAFT] victimisation list only with private_safety_check on", () => {
  assert(writerTextDiscloses("he hit me last night", true));
  assertEquals(writerTextDiscloses("he hit me last night", false), false);
});

Deno.test("ordinary words do not match", () => {
  assertEquals(writerTextDiscloses(ORDINARY, true), false);
  assertEquals(writerTextDiscloses("", true), false);
});

Deno.test("typographic apostrophes and quotes are folded first", () => {
  assert(writerTextDiscloses("I don\u2019t want to exist", false));
  for (const a of ["\u2018", "\u2019", "\u201B", "\u02BB", "\u02BC", "\uFF07", "\u0060", "\u00B4", "\u2032"]) {
    assert(writerTextDiscloses(`I don${a}t want to exist`, false), a);
  }
  assert(writerTextDiscloses("\u201CI want to die\u201D", false));
  assertEquals(foldTypography("don\u2019t \u201Chi\u201D"), "don't \"hi\"");
});

Deno.test("hyphens read as spaces, invisible characters neither split nor join a phrase", () => {
  assert(writerTextDiscloses("thinking about an over-dose", false));
  assert(writerTextDiscloses("thinking about an over\u2011dose", false));
  assert(writerTextDiscloses("I want to kill\u200Bmyself", false));
  assert(writerTextDiscloses("I want to end\u200Bmy life", false));
  assert(writerTextDiscloses("I want to ki\u00ADll myself", false));
});

Deno.test("fail safe: an unknown flag or a detector that throws is a match", () => {
  assert(writerTextDiscloses(ORDINARY, null));
  assert(writerTextDiscloses(THROWS, false));
});

Deno.test("fail safe: a throw inside the detector itself is a match", () => {
  // Survives the fold and the invisible-character replace, then makes the detector throw.
  // deno-lint-ignore no-explicit-any
  const DETECTOR_THROWS: any = { replace: () => DETECTOR_THROWS, toString(): string { throw new Error("unreadable"); } };
  assert(writerTextDiscloses(DETECTOR_THROWS as string, false));
});

Deno.test("one pending list for the Journal and Healing, never a copy", () => {
  assertStrictEquals(journalList.JOURNAL_SELF_HARM_PENDING, JOURNAL_SELF_HARM_PENDING);
  assertStrictEquals(journalList.matchesPendingSelfHarm, matchesPendingSelfHarm);
  assertEquals(JOURNAL_SELF_HARM_PENDING.config_version, "journal_self_harm_pending-0.3.0");
  assertEquals(JOURNAL_SELF_HARM_PENDING.review_status, "PENDING CLINICIAN REVIEW (W9c gate)");
  assertEquals(JOURNAL_SELF_HARM_PENDING.phrases.length, 52);
  assertEquals(JOURNAL_SELF_HARM_PENDING.patterns.length, 4);
});

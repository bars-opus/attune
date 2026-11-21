// Spec 2 W6b (§6.1, §7.2 S1, S8, S9, S21, S22, §7.3; I-17): the engine on
// the v1 lexicon. Golden positives per family (English, Ghanaian and
// Nigerian Pidgin, Twi typed with ɛ/ɔ and with e/o, leetspeak, a
// zero-width split) and near-miss negatives; age_signal in the base form
// only; the first-14-days terms only in a new match; one rule per family;
// a malformed config is no detection; the module has no fold table of its
// own (Spec 1's normaliser is the one).
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import lexicon from "./dating_chat_lexicon_v1.json" with { type: "json" };
import { baseForm, matchForm } from "./unicode_normaliser.ts";
import { detect, FAMILIES, parseConfig } from "./dating_chat_safety.ts";

const config = parseConfig({ version: "dating_chat_v1", config: lexicon })!;
const fams = (text: string, newMatch = false): string[] => detect(text, config, { newMatch }).map((h) => h.family);

Deno.test("the v1 lexicon reads, every family, every term in its stored form", () => {
  if (!config) throw new Error("the v1 lexicon did not parse");
  assertEquals([...config.families.keys()].sort(), [...FAMILIES].sort());
  for (const [family, f] of Object.entries(lexicon.families)) {
    for (const t of [...f.terms, ...(f.new_match_terms ?? [])]) {
      assertEquals(f.form === "base" ? baseForm(t) : matchForm(t), t, `${family}: ${t}`);
    }
  }
});

Deno.test("golden positives, one per family", () => {
  const cases: [string, string, boolean][] = [
    ["Please send me momo for transport", "financial_request", false],
    ["s3nd m3 m0m0 now", "financial_request", false],
    ["sɛnd me momo abeg", "financial_request", false],
    ["send me mo​mo today", "financial_request", false],
    ["I sent it by mistake, send it back", "financial_request", false],
    ["Abeg send small, I go pay you", "financial_request", false],
    ["Fa sika brɛ me", "financial_request", true],
    ["Buy me an iTunes card", "financial_request", false],
    ["W.E.S.T.E.R.N U.N.I.O.N is fine", "financial_request", false],
    ["I have your video. Pay or I post it", "sextortion", false],
    ["add me on WhatsApp instead", "contact_migration_pressure", false],
    ["call me on Sunday", "contact_migration_pressure", true],
    ["come to my place tonight", "meet_private_pressure", false],
    ["How old are your kids?", "child_access", false],
    ["I'm 16 but mature", "age_signal", false],
    ["I know where you live", "threat_intimidation", false],
    ["send nudes", "sexual_pressure", false],
    ["you are so stupid", "harassment_abuse", false],
    ["I am a US soldier on a peacekeeping mission", "identity_inconsistency", false],
  ];
  for (const [text, family, newMatch] of cases) {
    if (!fams(text, newMatch).includes(family)) throw new Error(`${JSON.stringify(text)} did not fire ${family}: ${fams(text, newMatch)}`);
  }
});

Deno.test("near-miss negatives stay silent", () => {
  const negatives: [string, boolean][] = [
    ["let's split the trotro fare", true],
    ["I paid my school fees myself", false],
    ["momo is down today", false],
    ["call me on Sunday", false],
    ["I'm 160 cm tall", false],
    ["I'm 1 6 years from retiring", false],
    ["Shall we meet at the mall?", true],
    ["What does a good Saturday look like for you?", true],
  ];
  for (const [text, newMatch] of negatives) {
    assertEquals(fams(text, newMatch), [], JSON.stringify(text));
  }
});

Deno.test("age_signal reads the base form only: no leetspeak folding", () => {
  assertEquals(fams("I'm 16"), ["age_signal"]);
  // In the match form "16" is "i6" (leetspeak), so "I'm i6" would fire;
  // the base form keeps digits as digits.
  assertEquals(fams("I'm i6"), []);
  assertEquals(fams("I'm l6"), []);
});

Deno.test("one rule per family; the rule names its term", () => {
  const hits = detect("send me momo, gift card, western union", config, { newMatch: false });
  assertEquals(hits.length, 1);
  assertEquals(hits[0], { rule_id: "financial_request:send me momo", family: "financial_request", tier: 2 });
});

Deno.test("a malformed config is no detection", () => {
  for (const raw of [null, {}, { version: "x" }, { version: "BAD!", config: lexicon },
                     { version: "v", config: { families: { couples_control: { tier: 1, terms: ["x"] } } } },
                     { version: "v", config: { families: { sextortion: { tier: 4, terms: ["x"] } } } },
                     { version: "v", config: { families: { sextortion: { tier: 2, terms: [1] } } } }]) {
    assertEquals(parseConfig(raw), null, JSON.stringify(raw));
  }
});

Deno.test("I-17: the engine has no fold table of its own", async () => {
  const src = await Deno.readTextFile(new URL("./dating_chat_safety.ts", import.meta.url));
  if (!src.includes('from "./unicode_normaliser.ts"')) throw new Error("the engine does not use Spec 1's normaliser");
  for (const own of ["new Map([", "fold_table", "charMap", "CONFUSABLES", "WEST_AFRICAN", "normalize("]) {
    if (src.includes(own)) throw new Error(`the engine folds on its own: ${own}`);
  }
});

// Task 5's complete_dating_safety_job takes a hit only when its rule is
// exactly family || ':' || one of that version's stored terms (contract
// Q): the rule is the stored term itself, never a re-normalised copy.
Deno.test("every rule is its family and a stored term, exactly as stored", () => {
  for (const [family, f] of Object.entries(lexicon.families)) {
    const stored = new Set([...f.terms, ...(f.new_match_terms ?? [])].map((t) => `${family}:${t}`));
    for (const t of [...f.terms, ...(f.new_match_terms ?? [])]) {
      const hit = detect(t, config, { newMatch: true }).find((h) => h.family === family);
      if (!hit) throw new Error(`${family}: ${t} does not fire on itself`);
      if (!stored.has(hit.rule_id)) throw new Error(`${family}: ${hit.rule_id} is not a stored term`);
    }
  }
  const odd = parseConfig({ version: "v", config: { families: { sextortion: { tier: 2, terms: ["Pay  OR I"] } } } })!;
  assertEquals(detect("pay or i post it", odd, { newMatch: false }), [{ rule_id: "sextortion:Pay  OR I", family: "sextortion", tier: 2 }]);
});

// Bodies are capped at 1,000 characters at send; the engine reads no
// further, so no input can cost more than a sent message.
Deno.test("the engine reads at most the send cap", () => {
  assertEquals(fams("send nudes " + "a ".repeat(5000)), ["sexual_pressure"]);
  assertEquals(fams("a ".repeat(1000) + "send nudes"), []);
  // The cap counts characters (code points), as the send's char_length does.
  assertEquals(fams("😀".repeat(989) + " send nudes"), ["sexual_pressure"]);
  assertEquals(fams("😀".repeat(990) + " send nudes"), []);
});

// Fix round 1 (review C-1): the base form keeps $ + , . / : @ _, so a
// base-form term is read by words: punctuation is not part of a word.
// Fix round 2 (N-4): punctuation between digits parts them too ("16.5" is
// "16 5", "1.6" is "1 6", never "16").
Deno.test("C-1: a base-form term next to punctuation fires", () => {
  for (const text of ["I'm 16.", "I'm 16, you?", "I'm in SHS.", "year 10.", "I'm in year 10.", "still in JHS, form 2",
                      "after BECE.", "I'm 16:)", "(I'm 16)", "I'm 16_", "I'm 16🙂"]) {
    assertEquals(fams(text), ["age_signal"], JSON.stringify(text));
  }
  for (const text of ["I'm 1.6 m tall", "I'm 160, not 16.5"]) {
    assertEquals(fams(text), [], JSON.stringify(text));
  }
});

// Fix round 1 (review I-1; chat spec §3.4 word-boundary matching): a
// squashed match starts at the start of a word and ends at the end of one.
Deno.test("I-1: a squashed term starts and ends on word boundaries", () => {
  const negatives: [string, boolean][] = [
    ["The new release feels great", false],
    ["the customs feel strict there", false],
    ["I got a credit message from my bank", false],
    ["I will find your book tomorrow", false],
    ["I will hurt your feelings if I say", false],
    ["don't expose yourself to the sun", false],
    ["we watch your background check", false],
    ["call me once you are home", true],
    ["my useless manager again", false],
    ["I need some air time to think", true],
  ];
  for (const [text, newMatch] of negatives) {
    assertEquals(fams(text, newMatch), [], JSON.stringify(text));
  }
  const positives: [string, string, boolean][] = [
    ["s e n d  n u d e s", "sexual_pressure", false],
    ["sendnudes", "sexual_pressure", false],
    ["y o u  a r e  s o  s t u p i d", "harassment_abuse", false],
    ["a d d me on w h a t s a p p", "contact_migration_pressure", false],
    ["c o m e  t o  m y  p l a c e", "meet_private_pressure", false],
    ["i k n o w where you live", "threat_intimidation", false],
    ["W.E.S.T.E.R.N U.N.I.O.N", "financial_request", false],
    ["e x p o s e  y o u", "sextortion", false],
    ["how old are your k i d s", "child_access", false],
    ["i am a u.s. soldier", "identity_inconsistency", false],
  ];
  for (const [text, family, newMatch] of positives) {
    assertEquals(fams(text, newMatch), [family], JSON.stringify(text));
  }
});

// Fix round 1 (review M-2): repeated letters, an emoji inside a phrase, a
// diacritic on an age term, and a short term spelled one letter at a time
// (a squashed short term must cover single letters only).
Deno.test("M-2: repeated letters, emoji, diacritics, letter-by-letter short terms", () => {
  const cases: [string, string, boolean][] = [
    ["seeend nudes", "sexual_pressure", false],
    ["sennnd me nuuudes", "sexual_pressure", false],
    ["send🍑nudes", "sexual_pressure", false],
    ["Ï'm 16", "age_signal", false],
    ["i'mmm 16", "age_signal", false],
    ["pay in b.t.c", "financial_request", false],
    ["u s d t only", "financial_request", false],
    ["send m.o.m.o", "financial_request", true],
  ];
  for (const [text, family, newMatch] of cases) {
    assertEquals(fams(text, newMatch), [family], JSON.stringify(text));
  }
  // Age reads the base form only: no leetspeak, squashed or not.
  assertEquals(fams("my h0usemistress said"), []);
  assertEquals(fams("I'm 116"), []);
});

// Lexicon (fix round 1): the age terms people type without the apostrophe.
Deno.test("the age terms without the apostrophe fire", () => {
  for (const text of ["im 16", "I am 16", "i am 15.", "Im 17"]) assertEquals(fams(text), ["age_signal"], text);
});

// Fix round 1 (review M-8): anything but a string is an engine error.
Deno.test("M-8: a body that is not a string throws", () => {
  for (const body of [[], null, 12, { length: 3 }]) {
    let threw = false;
    try {
      detect(body as unknown as string, config, { newMatch: false });
    } catch {
      threw = true;
    }
    assertEquals(threw, true, JSON.stringify(body));
  }
});

// Fix round 2 (re-review N-1): a text already in the squeezed spelling
// fires as the repeated one does.
Deno.test("N-1: a text written squeezed fires", () => {
  assertEquals(fams("useles man"), ["harassment_abuse"]);
  assertEquals(fams("i wil kil you"), ["threat_intimidation"]);
  assertEquals(fams("ad me on whatsap"), ["contact_migration_pressure"]);
});

// Fix round 2 (re-review N-4): an age joined to digit punctuation fires;
// a longer number, a decimal below it and a 3-digit number do not.
Deno.test("N-4: an age joined by digit punctuation fires", () => {
  for (const text of ["I'm 17/18", "I'm 16.5", "I'm 16,17", "I'm 15-16"]) assertEquals(fams(text), ["age_signal"], text);
  for (const text of ["I'm 160 cm", "I'm 1.6 m", "I'm 116", "I'm 1,600 km away"]) assertEquals(fams(text), [], text);
});

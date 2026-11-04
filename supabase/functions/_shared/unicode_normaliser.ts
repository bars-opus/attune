// supabase/functions/_shared/unicode_normaliser.ts
//
// Spec 1 W9a (spec 4.3 W9a, review I-17): the TypeScript port of the one
// shared normaliser. The rules live in ./unicode_fold_table.json, which the
// SQL functions private.normalize_for_filter and private.match_form
// (migration 20261104100000) are written from; the shared goldens
// (supabase/tests/fixtures/unicode_normaliser_goldens.json) must give the
// same output here and in SQL. Spec 2's _shared/dating_chat_safety.ts
// imports this module and has no fold table of its own. The couples
// chat_safety.ts is not touched.
import table from "./unicode_fold_table.json" with { type: "json" };

function charMap(from: string, to: string): Map<string, string> {
  const f = [...from];
  const t = [...to];
  if (f.length !== t.length) throw new Error("unicode_fold_table: from and to differ in length");
  return new Map(f.map((c, i) => [c, t[i]]));
}

const COMPAT_PINS = charMap(table.base.compat_pins.from, table.base.compat_pins.to);
const REMOVE = new Set([...table.base.remove]);
const CONFUSABLES = charMap(table.base.confusables.from, table.base.confusables.to);
const DIGITS = charMap(table.base.digits.from, table.base.digits.to);
const SEPARATORS = new Set([...table.base.separators]);
const WEST_AFRICAN = charMap(table.match.west_african.from, table.match.west_african.to);
const WEST_AFRICAN_MULTI = new Map(Object.entries(table.match.west_african.multi as Record<string, string>));
const STRIP_MARKS = new Set([...table.match.strip_marks]);
const LEET = charMap(table.match.leet.from, table.match.leet.to);
const BETWEEN_LETTERS = charMap(table.match.between_ascii_letters.from, table.match.between_ascii_letters.to);
const ASCII_LETTER = /^[A-Za-z]$/;
const MATCH_SEPARATORS = new Set([...table.match.separators]);

// Postgres lowers with the pg_c_utf8 collation: Unicode SIMPLE case mapping,
// one code point at a time. String.prototype.toLowerCase is the FULL
// mapping, which differs only for U+0130 (to "i" + U+0307) and, in context,
// for a final sigma; lowering each code point on its own and special-casing
// U+0130 gives the simple mapping.
function simpleLower(text: string): string {
  let out = "";
  for (const c of text) out += c === "\u0130" ? "i" : c.toLowerCase();
  return out;
}

function collapse(text: string): string {
  return text.replace(/ {2,}/g, " ").replace(/^ +| +$/g, "");
}

// base.compat_pins, before NFKC: the characters whose fold differs
// between PostgreSQL 17's Unicode 15.1 and V8's Unicode 16 (batch-2 review
// I-2), mapped the same way in both ports.
function pinCompat(text: string): string {
  let out = "";
  for (const c of text) out += COMPAT_PINS.get(c) ?? c;
  return out;
}

// match.between_ascii_letters: "!" and "|" with an ASCII letter on both
// sides read as "i" and "l" (r!tard, he|lo). Match form only; the base
// form keeps them as separators.
function foldBetweenLetters(text: string): string {
  const cs = [...text];
  let out = "";
  for (let i = 0; i < cs.length; i++) {
    const to = BETWEEN_LETTERS.get(cs[i]);
    out += to !== undefined && i > 0 && i < cs.length - 1 && ASCII_LETTER.test(cs[i - 1]) && ASCII_LETTER.test(cs[i + 1])
      ? to
      : cs[i];
  }
  return out;
}

/// The base form: the compat pins, NFKC, lower case, invisible and bidi controls removed,
/// look-alikes folded to Latin, other-script digits to 0-9, separators to
/// single spaces. Letters and their marks stay as typed; $ + , . / : @ _
/// are kept. The base form is a match key, never stored or shown; unlike
/// W1's display-name set it removes ZWNJ/ZWJ.
export function baseForm(text: string): string {
  let out = "";
  for (const c of simpleLower(pinCompat(text).normalize("NFKC"))) {
    if (REMOVE.has(c)) continue;
    const folded = CONFUSABLES.get(c) ?? DIGITS.get(c) ?? c;
    out += SEPARATORS.has(folded) ? " " : folded;
  }
  // A removed character can part a letter from its mark ("e", U+200B,
  // U+0301): NFC joins them again (review M-1).
  return collapse(out.normalize("NFC"));
}

/// The match form: "!" and "|" between ASCII letters read as i and l,
/// then the base form, the West African letter fold, combining
/// marks dropped (tone marks, Zalgo; NFD, strip, NFC), the look-alike fold
/// again (a look-alike that carried a mark), the leetspeak fold, then the
/// kept punctuation to spaces. Term lists are stored and matched in this
/// form.
export function matchForm(text: string): string {
  let letters = "";
  for (const c of baseForm(foldBetweenLetters(text))) {
    letters += WEST_AFRICAN_MULTI.get(c) ?? WEST_AFRICAN.get(c) ?? c;
  }
  let bare = "";
  for (const c of letters.normalize("NFD")) {
    if (!STRIP_MARKS.has(c)) bare += c;
  }
  let out = "";
  for (const c of bare.normalize("NFC")) {
    const plain = CONFUSABLES.get(c) ?? c;
    const leet = LEET.get(plain) ?? plain;
    out += MATCH_SEPARATORS.has(leet) ? " " : leet;
  }
  return collapse(out);
}

/// The match form without spaces, for distinctive ("squashed") terms.
export function squashedForm(text: string): string {
  return matchForm(text).replaceAll(" ", "");
}

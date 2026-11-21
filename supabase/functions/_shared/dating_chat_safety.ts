// supabase/functions/_shared/dating_chat_safety.ts
//
// Spec 2 W6b (§6.1; chat spec §3, §9; I-17): the dating chat's
// deterministic engine. No LLM; no fold table of its own: every text and
// every lexicon term is read through Spec 1's ./unicode_normaliser.ts
// (baseForm, matchForm), so a Twi or Pidgin term matches the same way here
// as in a D10 prompt. The couples chat_safety.ts is not touched. The config
// is the active dating_safety_configs row (the v1 lexicon is
// ./dating_chat_lexicon_v1.json): one entry per family, its tier, its form
// ("match", or "base" for age_signal, where leetspeak would turn "16" into
// letters), its terms, and the terms that apply only in a match's first 14
// days (chat spec §3.3: sensitivity may only increase with unfamiliarity).
// A config that can't be read is no detection.
//
// Fix round 1 (review C-1, I-1, M-2, M-3, M-8): a text and a term are read
// as words (chat spec §3.4, word-boundary matching):
// - a word is a run of letters, digits and marks; anything else (a space,
//   an emoji, the punctuation the base form keeps) parts words, between
//   digits too (fix round 2, N-4: "16.5" and "17/18" read "16 5" and
//   "17 18"; "1.6" reads "1 6", never "16");
// - in the base form, a word of letters alone is read in its match form
//   (marks dropped: "Ï'm" is "i m"); a word with a digit stays as typed,
//   so "i6" is never "16";
// - a term matches whole words, as typed or with repeated letters squeezed
//   on both sides ("seeend" is "send"; fix round 2, N-1: a text already
//   written squeezed, "useles man", fires too); a match-form term also
//   matches across the words of the text squashed together, starting at
//   the start of a word and ending at the end of one; a short term (under
//   SQUASH_MIN letters) only across single letters ("b.t.c", "m o m o");
// - each term's words are computed once, in parseConfig.
import { baseForm, matchForm } from "./unicode_normaliser.ts";

export const FAMILIES = [
  "sexual_pressure",
  "harassment_abuse",
  "contact_migration_pressure",
  "meet_private_pressure",
  "threat_intimidation",
  "financial_request",
  "sextortion",
  "child_access",
  "age_signal",
  "identity_inconsistency",
] as const;
export type Family = typeof FAMILIES[number];
export type Tier = 1 | 2 | 3;

/// A term as read: [raw] is the term as stored (the rule names it), then
/// its words joined by spaces and squashed, as typed and squeezed.
export interface Term {
  raw: string;
  words: string;
  bare: string;
  squeezedWords: string;
  squeezedBare: string;
}

export interface FamilyConfig {
  tier: Tier;
  form: "match" | "base";
  terms: Term[];
  newMatchTerms: Term[];
}

export interface DatingSafetyConfig {
  version: string;
  families: Map<Family, FamilyConfig>;
}

export interface Hit {
  rule_id: string;
  family: Family;
  tier: Tier;
}

/// A distinctive term (at least this many letters without spaces) matches
/// across any whole words of the squashed text ("s e n d  n u d e s"); a
/// shorter one only across single letters ("b.t.c").
export const SQUASH_MIN = 8;

/// A message is at most this many characters (code points) at send
/// (dating_messages_body_check); the engine reads no further, so no input
/// costs more than a sent message.
export const MAX_CHARS = 1000;

const WORD_CHAR = /[\p{L}\p{N}\p{M}]/u;
const DIGIT = /\p{N}/u;
const LETTERS_ONLY = /^[\p{L}\p{M}]+$/u;

/// The words of a normalised form (one pass, no backtracking).
function split(form: string): string[] {
  const cs = Array.from(form);
  const out: string[] = [];
  let word = "";
  for (let i = 0; i < cs.length; i++) {
    const c = cs[i];
    if (WORD_CHAR.test(c)) {
      word += c;
    } else if (word !== "") {
      out.push(word);
      word = "";
    }
  }
  if (word !== "") out.push(word);
  return out;
}

function matchWords(text: string): string[] {
  return split(matchForm(text));
}

function baseWords(text: string): string[] {
  return split(baseForm(text)).flatMap((w) => LETTERS_ONLY.test(w) ? split(matchForm(w)) : [w]);
}

/// A word with each run of one repeated letter read once (digits stay).
function squeeze(word: string): string {
  let out = "";
  let prev = "";
  for (const c of word) {
    if (c !== prev || DIGIT.test(c)) out += c;
    prev = c;
  }
  return out;
}

interface View {
  padded: string;
  squashed: string;
  /// offset in [squashed] where word i starts → i; where word i ends → i.
  starts: Map<number, number>;
  ends: Map<number, number>;
}

function view(words: string[]): View {
  const starts = new Map<number, number>();
  const ends = new Map<number, number>();
  let at = 0;
  words.forEach((w, i) => {
    starts.set(at, i);
    at += w.length;
    ends.set(at, i);
  });
  return { padded: ` ${words.join(" ")} `, squashed: words.join(""), starts, ends };
}

/// [words] (joined) as whole words of [v], or, when [squash], [bare] across
/// whole words of the squashed text (single letters for a short term).
function found(v: View, words: string, bare: string, squash: boolean): boolean {
  if (words === "") return false;
  if (v.padded.includes(` ${words} `)) return true;
  if (!squash) return false;
  for (let at = v.squashed.indexOf(bare); at !== -1; at = v.squashed.indexOf(bare, at + 1)) {
    const first = v.starts.get(at);
    const last = v.ends.get(at + bare.length);
    if (first === undefined || last === undefined) continue;
    if (bare.length >= SQUASH_MIN || last - first + 1 === bare.length) return true;
  }
  return false;
}

function term(raw: string, form: "match" | "base"): Term {
  const words = form === "base" ? baseWords(raw) : matchWords(raw);
  const squeezed = words.map(squeeze);
  return {
    raw,
    words: words.join(" "),
    bare: words.join(""),
    squeezedWords: squeezed.join(" "),
    squeezedBare: squeezed.join(""),
  };
}

function strings(raw: unknown): string[] | null {
  if (raw === undefined) return [];
  if (!Array.isArray(raw) || raw.some((t) => typeof t !== "string" || t.trim() === "")) return null;
  return raw as string[];
}

/// The config as the database sends it ({version, config}), or null when
/// any part of it is malformed: no detection, never a guess.
export function parseConfig(raw: unknown): DatingSafetyConfig | null {
  if (!raw || typeof raw !== "object") return null;
  const { version, config } = raw as { version?: unknown; config?: unknown };
  if (typeof version !== "string" || !/^[a-z0-9_]{1,40}$/.test(version)) return null;
  const families = (config as { families?: unknown } | null)?.families;
  if (!families || typeof families !== "object") return null;
  const out = new Map<Family, FamilyConfig>();
  for (const [name, value] of Object.entries(families as Record<string, unknown>)) {
    if (!(FAMILIES as readonly string[]).includes(name) || !value || typeof value !== "object") return null;
    const v = value as Record<string, unknown>;
    const terms = strings(v.terms);
    const newMatchTerms = strings(v.new_match_terms);
    const form = v.form === undefined ? "match" : v.form;
    if (![1, 2, 3].includes(v.tier as number) || terms === null || newMatchTerms === null || (form !== "match" && form !== "base")) {
      return null;
    }
    out.set(name as Family, {
      tier: v.tier as Tier,
      form,
      terms: terms.map((t) => term(t, form)),
      newMatchTerms: newMatchTerms.map((t) => term(t, form)),
    });
  }
  return { version, families: out };
}

/// The families [text] trips (at most one rule per family), in FAMILIES
/// order. [newMatch]: the message was sent in the match's first 14 days.
/// Anything but a string throws (the worker's engine_error).
export function detect(text: string, config: DatingSafetyConfig, opts: { newMatch: boolean }): Hit[] {
  if (typeof text !== "string") throw new TypeError("detect: the text is not a string");
  text = Array.from(text.slice(0, 2 * MAX_CHARS)).slice(0, MAX_CHARS).join("");
  const views = (words: string[]) => ({ plain: view(words), squeezed: view(words.map(squeeze)) });
  const match = views(matchWords(text));
  const base = views(baseWords(text));
  const hits: Hit[] = [];
  for (const family of FAMILIES) {
    const f = config.families.get(family);
    if (!f) continue;
    const terms = opts.newMatch ? [...f.terms, ...f.newMatchTerms] : f.terms;
    const v = f.form === "base" ? base : match;
    const squash = f.form === "match";
    for (const t of terms) {
      if (found(v.plain, t.words, t.bare, squash) ||
          found(v.squeezed, t.squeezedWords, t.squeezedBare, squash)) {
        // The rule is the term as stored: the database takes a hit only
        // when its rule is family:term for one of the version's terms.
        hits.push({ rule_id: `${family}:${t.raw}`, family, tier: f.tier });
        break;
      }
    }
  }
  return hits;
}

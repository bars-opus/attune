// supabase/functions/_shared/dating_mask.ts
//
// Spec 2 W6a (§6.1 contact masking, §7.3 parity; carry 3): the TypeScript
// mirror of private.dating_mask_contacts(text) and
// private.dating_caption_invites(text) (migration
// 20261120100000_dating_v2_chat.sql). Both run the same fixture,
// supabase/tests/fixtures/dating_mask_cases.json, and must give the same
// output for every case. The SQL function is the one that masks: it fills
// dating_messages.body_masked at insert and masks photo captions on the
// card. Each span becomes "•••". Masking is presentation only: it never
// blocks delivery and never lifts by itself.
//
// How it works (the SQL function is a line-by-line port):
// 1. A shadow of the text, one entry per character it folds to, each
//    remembering the text character it came from: invisible characters
//    dropped, spaces to " ", NFKD, lower case, marks dropped, a few
//    look-alike letters folded (Cyrillic, Greek, West African).
// 2. Views of the shadow, one character for one: "li"/"ll" (leetspeak
//    next to a letter read as a letter, 1 as i or l), "dv" (dates and
//    times blanked, then o next to a digit as 0, l/i as 1).
// 3. Each rule's matches in its view are spans of the shadow; the spans are
//    merged and mapped back to the text, and each becomes "•••".

export const MASK = "•••";
export const MASK_VERSION = 1;

import { baseForm, matchForm } from "./unicode_normaliser.ts";

// The fold of one character. ASCII: lower case, any ASCII space a space.
// Anything else: Spec 1's own base form of that character (NFKC, lower case,
// invisible characters removed, look-alikes, other-script digits, its
// separators to a space; I-17: no fold table here), then its match form
// when that is still not ASCII (the West African fold, marks dropped). The
// character is read between two "0"s, which neither form changes into
// anything but one character, so a space or nothing survives as itself.
// A character outside the BMP that is left (an emoji) reads as U+FFFD.
// Fix round 1: every control character (U+0001-U+001F, U+007F) reads as a
// space, so the SQL scan's marker (U+0001) never occurs in a view.
function middle(t: string): string {
  const cs = [...t];
  return cs.slice(1, cs.length - 1).join("");
}

function foldChar(c: string): string {
  const cp = c.codePointAt(0)!;
  if (cp < 0x80) return /[\u0000-\u0020\u007f]/.test(c) ? " " : c.toLowerCase();
  let mid = middle(baseForm(`0${c}0`));
  if (/[^\u0000-\u007f]/.test(mid)) mid = middle(matchForm(`0${mid}0`));
  let out = "";
  for (const x of mid) out += x.codePointAt(0)! > 0xffff ? "\uFFFD" : /[\u0000-\u001f\u007f]/.test(x) ? " " : x;
  return out;
}

type Shadow = { s: string; pos: number[]; changed: boolean[]; n: number };

function shadow(chars: string[]): Shadow {
  let s = "";
  const pos: number[] = [];
  const changed: boolean[] = [];
  chars.forEach((c, i) => {
    const f = foldChar(c);
    const outside = c.codePointAt(0)! >= 0x80; // fix round 1: as the SQL marks it
    for (const x of f) {
      s += x;
      pos.push(i);
      changed.push(outside);
    }
  });
  return { s, pos, changed, n: chars.length };
}

// The views (each one character for one of the shadow).
const LEET: [string, string][] = [["4", "a"], ["3", "e"], ["0", "o"], ["5", "s"], ["7", "t"], ["@", "a"], ["\\$", "s"]];
function leet(s: string, one: string): string {
  let v = s;
  for (let pass = 0; pass < 2; pass++) {
    for (const [d, l] of [...LEET, ["1", one] as [string, string]]) {
      v = v.replace(new RegExp(`(?<=[a-z])${d}|${d}(?=[a-z])`, "g"), l);
    }
  }
  return v;
}

export const DATES = [
  "(?<![0-9])[0-9]{1,2}[/.-][0-9]{1,2}[/.-](?:[0-9]{4}|[0-9]{2})(?![0-9])",
  "(?<![0-9])[0-9]{4}[/.-][0-9]{1,2}[/.-][0-9]{1,2}(?![0-9])",
  "(?<![0-9])(?:19|20)[0-9]{2} ?[-/] ?(?:(?:19|20)[0-9]{2}|[0-9]{2})(?![0-9])",
  "(?<![0-9])[0-9]{1,2}:[0-5][0-9](?![0-9])",
  // Fix round 1 (M-2): a date with spaces ("12 03 1995") and a run of years
  // ("1990 2000 2010"), each only with no other digits beside it (a number
  // that holds a year is still a number).
  "(?<![0-9][^a-z0-9]{0,3})[0-9]{1,2} [0-9]{1,2} (?:19|20)[0-9]{2}(?![^a-z0-9]{0,3}[0-9])",
  "(?<![0-9][^a-z0-9]{0,3})(?:19|20)[0-9]{2}(?:[ ,/&-]{1,3}(?:19|20)[0-9]{2})+(?![^a-z0-9]{0,3}[0-9])",
];
function digitsView(s: string): string {
  let v = s;
  for (const d of DATES) v = v.replace(new RegExp(d, "g"), (m) => "x".repeat(m.length));
  for (let pass = 0; pass < 2; pass++) {
    v = v.replace(/(?<=[0-9])o|o(?=[0-9])/g, "0");
    v = v.replace(/(?<=[0-9])[li]|[li](?=[0-9])/g, "1");
  }
  return v;
}

// Word lists (alternations longest first, so both engines take the same).
const STRONG =
  "snap[ _-]?chat|tele[ _-]?gram|whats[ _-]?app|wats[ _-]?app|insta[ _-]?gram|face[ _-]?book|only[ _-]?fans|linked[ _-]?in|you[ _-]?tube|cash[ _-]?app|tik[ _-]?tok|pay[ _-]?pal|we[ _-]?chat|whtsapp|instgrm|twitter|discord|snpcht|wassap|reddit|tlgrm|botim|viber|venmo|whtsp|fcbk|momo|kik";
const WEAK = "the[ _-]?gram|messenger|threads|signal|insta|snap|line|imo|sc|ig|fb|tg|yt|wa|x";
// Fix round 1 (I-2): the platforms a whole message of "<platform> <handle>"
// names ("ig amab"); fb, wa, x, line and signal stay out ("Fb memories").
const BARE = "insta|snap|sc|ig|tg|yt";
const PROVIDER = "protonmail|googlemail|hotmail|outlook|icloud|proton|yahoo|gmail|ymail|aol|gmx";
const TLD = "info|link|app|biz|com|edu|gov|net|org|xyz|co|gh|io|ly|me|ng|uk";
const NUMWORD = "mmiensa|mmienu|nwotwe|triple|double|baako|seven|three|eight|nkron|hwee|enan|enum|four|five|nine|nsia|nson|zero|one|six|two|oh|o";
// Words that are never a handle ("my snapchat is ..." reads past "is");
// fix round 1 (M-2) adds plain words ("Signal is bad", "I use gmail").
export const STOP = new Set(
  "a about account again also am an and are at banned be blocked but call chat closed dead deleted different dm dms down for from gone handle here i id im in is it its later link locked me my name new no not now number of off ok okay old on or page please pls private public same so that the then there this to too up us user username video was we with yes you your awful bad better fine good great poor really slow soon strong terrible today tomorrow tonight use used using very weak work worked working works worse".split(" "),
);
// Every platform word, for the evasive and spaced-out forms.
export const PLATFORM_WORDS = new Set(
  "snapchat telegram whatsapp watsapp instagram facebook onlyfans linkedin youtube cashapp tiktok paypal wechat whtsapp instgrm twitter discord snpcht wassap reddit tlgrm botim viber venmo whtsp fcbk momo kik thegram messenger threads signal insta snap line imo".split(" "),
);

// The platform words an evasive spelling is checked against.
const EVASIVE = [...PLATFORM_WORDS].sort((a, b) => b.length - a.length || (a < b ? -1 : 1)).join("|");

const W = "(?<![a-z0-9])";
export const E = "(?![a-z0-9])";
export const H = "(@?[a-z0-9][a-z0-9_.-]*[a-z0-9_])";
// Fix round 1 (I-2): what an invitation off the app says before the
// platform ("add me on ", "follow me on ", "hit me up on ").
export const INVITED = "(?<=(?:^|[^a-z0-9])(?:add|find|follow|message|contact|hit|dm|text|ping|reach|inbox|catch)(?: +(?:me|us))?(?: +up)? +(?:on|at|via|in) +)";
export const GAP = `(?:[ :=@_-]+(?:is|its|id|handle|username|user|name|account|page)${E})*[ :=@_-]+`;

type Rule = { name: string; view: "s" | "li" | "ll" | "dv"; re: string; handle?: number; check?: string };

// The rules, in order. handle: the capture group holding a handle (a stop
// word there rejects the match). check: extra code below.
export const RULES: Rule[] = [
  // A platform that is only a platform, then a handle ("telegram amab").
  { name: "strong", view: "li", re: `${W}(?:${STRONG})${E}${GAP}${H}${E}`, handle: 1, check: "names" },
  { name: "strong", view: "ll", re: `${W}(?:${STRONG})${E}${GAP}${H}${E}`, handle: 1, check: "names" },
  // A platform word that is also a word, then ":", "@", "=" or "is".
  { name: "weak_said", view: "li", re: `${W}(?:${WEAK})${E}(?: *[:=@] *| +(?:is|id|handle|username) *[:=]? *)${H}${E}`, handle: 1 },
  { name: "weak_said", view: "ll", re: `${W}(?:${WEAK})${E}(?: *[:=@] *| +(?:is|id|handle|username) *[:=]? *)${H}${E}`, handle: 1 },
  // "my ig handle amab", "my sc is amab".
  { name: "my_platform", view: "li", re: `${W}(?:my|mine|our)(?: +|_)(?:${STRONG}|${WEAK})${E}(?:[ _]+(?:handle|id|name|username|account|page)${E})?(?:[ _]+is${E})?[ :=@_-]+${H}${E}`, handle: 1 },
  // A weak platform word, then something that looks like a handle.
  { name: "weak_handle", view: "li", re: `${W}(?:${WEAK})${E}[ :=_-]+(@?(?:[a-z0-9_.-]*[0-9_.][a-z0-9_.-]*[a-z0-9_]|[0-9]+))${E}`, handle: 1 },
  // A platform word spelled to dodge (sn@p, 5nap, ⓢⓝⓐⓟ), and its handle.
  { name: "evasive", view: "li", re: `${W}(${EVASIVE})${E}`, check: "evasive" },
  { name: "evasive", view: "ll", re: `${W}(${EVASIVE})${E}`, check: "evasive" },
  // Letters spaced out (s n a p c h a t, s.n.a.p) that spell a platform.
  { name: "spaced", view: "li", re: `${W}[a-z](?:[ ._-][a-z]){2,}${E}`, check: "spaced" },
  // "ama.b on IG", "amab on yt" (a whole message).
  { name: "on_platform", view: "li", re: `${W}(@?[a-z0-9_.-]*[0-9_.][a-z0-9_.-]*[a-z0-9_]) +on +(?:${STRONG}|${WEAK})${E}`, handle: 1 },
  { name: "on_platform_alone", view: "li", re: `^ *([a-z0-9][a-z0-9_.-]*[a-z0-9_]) +on +(?:${STRONG}|${WEAK}) *[.!]* *$`, handle: 1 },
  // A LINE id, a reddit u/handle, a "handle is ...".
  { name: "line_id", view: "li", re: `${W}line[ _-]?id${E}[ :=_-]*${H}${E}`, handle: 1 },
  { name: "reddit", view: "s", re: "(?<![a-z0-9/])u/[a-z0-9_-]+" },
  { name: "handle_is", view: "li", re: `${W}(?:handle|username|user[ _-]?name|user[ _-]?id)(?: +is)?[ :=@_-]+${H}${E}`, handle: 1 },
  // @handle (never "@ the beach").
  { name: "at_handle", view: "s", re: "(?<![a-z0-9_.@])@[a-z0-9_]+(?:\\.[a-z0-9_]+)*" },
  // Emails: symbol, then a provider in words.
  { name: "email", view: "s", re: "[a-z0-9._%+-]*[a-z0-9]@ ?[a-z0-9-]+(?:\\.[a-z0-9-]+)*" },
  { name: "email", view: "s", re: "[a-z0-9._%+-]*[a-z0-9] @[a-z0-9-]+(?:\\.[a-z0-9-]+)*" },
  { name: "email", view: "s", re: `${W}[a-z0-9._%+-]*[a-z0-9] +@ +(?:${PROVIDER})${E}(?:\\.[a-z]+)*` },
  { name: "provider", view: "s", re: `${W}([a-z0-9._-]+) +(?:at +|\\(at\\) *|\\[at\\] *)?(?:${PROVIDER})${E}(?: *(?:\\.|dot${E}|\\(dot\\)) *(?:com|net|co|uk)${E})*`, handle: 1 },
  // Fix round 1 (M-2): a provider alone ("I work at Yahoo") is no address;
  // with a domain after it, it is ("at gmail dot com").
  { name: "provider", view: "s", re: `${W}(?:at +|\\(at\\) *|\\[at\\] *)?(?:${PROVIDER})${E}(?: *(?:\\.|dot${E}|\\(dot\\)) *(?:com|net|co|uk)${E})+` },
  // "name at domain dot tld" (and "(at)", "[at]", " . ").
  { name: "spelled_email", view: "s", re: `${W}[a-z0-9._-]+(?: dot [a-z0-9_-]+)* *(?: at |\\(at\\)|\\[at\\]) *[a-z0-9-]+(?: +[a-z0-9-]{2,})? *(?: dot |\\(dot\\)|\\[dot\\]| \\. ) *(?:${TLD})${E}(?:(?: dot |\\.)(?:${TLD})${E})*` },
  // "ama dot com".
  { name: "spelled_domain", view: "s", re: `${W}[a-z0-9-]+ (?:dot|\\.) (?:${TLD})${E}(?: (?:dot|\\.) (?:${TLD})${E})*` },
  // URLs and domains.
  { name: "url", view: "s", re: "https?://[^ ]+|(?<![a-z0-9])www\\.[^ ]+" },
  { name: "domain", view: "s", re: `${W}[a-z0-9][a-z0-9-]*(?:\\.[a-z0-9-]+)*\\.(?:${TLD})${E}(?:/[^ ]*)?` },
  { name: "domain_path", view: "s", re: `${W}[a-z0-9][a-z0-9-]*\\.[a-z]{2,}/[^ ]+` },
  // A cashtag; crypto addresses.
  { name: "cashtag", view: "s", re: "(?<![a-z0-9$])\\$[a-z][a-z0-9_]*" },
  { name: "crypto", view: "s", re: `${W}(?:0x[0-9a-f]{40}|bc1[0-9a-z]{25,62}|t[1-9a-z]{33})${E}` },
  // Phone numbers: 7 or more digits with spaces, dots, dashes, slashes or
  // brackets between, with or without +.
  // Fix round 1 (I-2): any 1-3 characters that are not a letter or a digit
  // between two digits (",", "+", "*", "|", "~", "#", an emoji as U+FFFD).
  { name: "phone", view: "dv", re: "(?<![0-9])\\+?\\(?[0-9](?:[^a-z0-9]{0,3}[0-9]){6,}\\)?" },
  // Numbers in words (and digits among them), 7 or more in all.
  { name: "number_words", view: "s", re: `${W}(?:${NUMWORD}|[0-9]+)${E}(?:[ ,.-]+(?:${NUMWORD}|[0-9]+)${E})+`, check: "number_words" },
  // Fix round 1 (I-2): a platform, "me" (and "on", "at"), then a handle with
  // a letter ("telegram me amab"; a number after it is the phone rule's).
  { name: "strong_me", view: "li", re: `${W}(?:${STRONG})${E} +(?:me|us)${E}(?: +(?:on|at|via)${E})?[ :=@_-]+(@?(?=[a-z0-9_.-]*[a-z])[a-z0-9][a-z0-9_.-]*[a-z0-9_])${E}`, handle: 1 },
  { name: "strong_me", view: "ll", re: `${W}(?:${STRONG})${E} +(?:me|us)${E}(?: +(?:on|at|via)${E})?[ :=@_-]+(@?(?=[a-z0-9_.-]*[a-z])[a-z0-9][a-z0-9_.-]*[a-z0-9_])${E}`, handle: 1 },
  // An invitation, then a platform and a handle ("add me on snap amab"):
  // the platform and the handle are masked.
  { name: "invite_platform", view: "li", re: `${INVITED}(?:${STRONG}|${WEAK})${E}[ :=@_-]+${H}${E}`, handle: 1 },
  { name: "invite_platform", view: "ll", re: `${INVITED}(?:${STRONG}|${WEAK})${E}[ :=@_-]+${H}${E}`, handle: 1 },
  // The whole message is a platform and a bare handle ("ig amab").
  { name: "platform_alone", view: "li", re: `^ *(?:${BARE})${E}[ :=_-]+${H}${E}(?= *[.!]* *$)`, handle: 1 },
];

function compile(r: Rule): RegExp {
  return new RegExp(r.re, "g");
}
const COMPILED = RULES.map((r) => [r, compile(r)] as const);

function countNumber(m: string): number | null {
  let n = 0;
  let word = false;
  for (const t of m.split(/[ ,.-]+/)) {
    if (t === "") continue;
    if (/^[0-9]+$/.test(t)) n += t.length;
    else {
      n += 1;
      word = true;
    }
  }
  return word ? n : null;
}

type Span = [number, number];

// The shadow spans the rules find (half-open, in shadow positions).
function spans(sh: Shadow, chars: string[]): Span[] {
  const views: Record<Rule["view"], string> = { s: sh.s, li: leet(sh.s, "i"), ll: leet(sh.s, "l"), dv: digitsView(sh.s) };
  const out: Span[] = [];
  for (const [r, re] of COMPILED) {
    const v = views[r.view];
    let from = 0;
    while (from <= v.length) {
      re.lastIndex = from;
      const m = re.exec(v);
      if (!m) break;
      const a = m.index;
      let b = a + m[0].length;
      let ok = m[0].length > 0;
      if (ok && r.handle !== undefined) {
        const h = (m[r.handle] ?? "").replace(/^@/, "");
        if (STOP.has(h)) ok = false;
      }
      if (ok && r.check === "evasive") {
        ok = (sh.s.slice(a, b) !== v.slice(a, b) || sh.changed.slice(a, b).some((x) => x));
        if (ok) b = afterHandle(v, b);
      }
      if (ok && r.check === "spaced") {
        ok = PLATFORM_WORDS.has(m[0].replace(/[ ._-]/g, ""));
        if (ok) b = afterHandle(v, b);
      }
      if (ok && r.check === "number_words") ok = (countNumber(m[0]) ?? 0) >= 7;
      if (ok && r.check === "names") b = afterNames(v, b, chars, sh);
      if (ok) {
        out.push([a, b]);
        from = b;
      } else {
        from = a + 1;
      }
    }
  }
  return out;
}

// After an evasive or spaced platform word: its handle, if one follows.
function afterHandle(v: string, b: number): number {
  const m = new RegExp(`^${GAP}${H}${E}`).exec(v.slice(b));
  if (!m) return b;
  return STOP.has(m[1].replace(/^@/, "")) ? b : b + m[0].length;
}

// "facebook Ama Boateng": up to two more capitalised words of a name.
function afterNames(v: string, b: number, chars: string[], sh: Shadow): number {
  let end = b;
  for (let k = 0; k < 2; k++) {
    const m = /^ +([a-z][a-z'-]*[a-z])(?![a-z0-9])/.exec(v.slice(end));
    if (!m) break;
    const first = end + m[0].length - m[1].length;
    const c = chars[sh.pos[first]];
    if (c === undefined || c === c.toLowerCase() || STOP.has(m[1])) break;
    end += m[0].length;
  }
  return end;
}

/// The text with every contact detail span replaced by "•••".
export function maskContacts(text: string): string {
  const chars = [...text];
  const sh = shadow(chars);
  const found = spans(sh, chars)
    .filter(([a, b]) => b > a)
    // Fix round 1 (M-6): a span ends where the next folded character
    // begins, so marks that fold to nothing (a keycap's U+FE0F U+20E3) go
    // with the digit they follow.
    .map(([a, b]) => [sh.pos[a], Math.max(sh.pos[b - 1] + 1, b < sh.pos.length ? sh.pos[b] : sh.n)] as Span)
    .sort((x, y) => x[0] - y[0] || x[1] - y[1]);
  const merged: Span[] = [];
  for (const [a, b] of found) {
    const last = merged[merged.length - 1];
    if (last && a <= last[1]) last[1] = Math.max(last[1], b);
    else merged.push([a, b]);
  }
  let out = "";
  let i = 0;
  for (const [a, b] of merged) {
    out += chars.slice(i, a).join("") + MASK;
    i = b;
  }
  return out + chars.slice(i).join("");
}

export const INVITES = [
  `${W}(?:add|find|message|contact|hit|dm|text|call|ping|inbox|follow) +(?:me|us)${E}`,
  `${W}(?:slide|come) +into +my +dms?${E}`,
  `${W}(?:${STRONG}|${WEAK}) +(?:me|us)${E}`,
  `${W}of +link${E}`,
  `${W}link +in +(?:my +)?bio${E}`,
];
const INVITE_RES = INVITES.map((r) => new RegExp(r));

/// Captions only: an invitation to move off the app with nothing to mask
/// ("DM me", "add me on snap"). The card drops such a caption.
export function captionInvites(text: string): boolean {
  const sh = shadow([...text]);
  const li = leet(sh.s, "i");
  const ll = leet(sh.s, "l");
  return INVITE_RES.some((re) => re.test(li) || re.test(ll));
}

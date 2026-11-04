// Spec 1 W9a (spec 7.2, review I-17): the TypeScript port gives exactly the
// SQL functions' base and match forms for every shared golden, and honours
// every entry of the fold table. opinion_filter_contracts.sql runs the same
// goldens through private.normalize_for_filter / private.match_form.
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import table from "./unicode_fold_table.json" with { type: "json" };
import goldens from "../../tests/fixtures/unicode_normaliser_goldens.json" with { type: "json" };
import { baseForm, matchForm, squashedForm } from "./unicode_normaliser.ts";

Deno.test("every shared golden gives the SQL base and match forms", () => {
  if (goldens.cases.length < 73) throw new Error("the goldens file lost cases");
  for (const c of goldens.cases) {
    assertEquals(baseForm(c.input), c.base, `${c.name}: base form`);
    assertEquals(matchForm(c.input), c.match, `${c.name}: match form`);
  }
});

Deno.test("each fold table entry does what it says", () => {
  for (const c of table.base.remove) assertEquals(baseForm(`a${c}b`), "ab", `remove U+${c.codePointAt(0)!.toString(16)}`);
  const pairs = (from: string, to: string) => [...from].map((c, i) => [c, [...to][i]] as const);
  for (const [f, t] of pairs(table.base.compat_pins.from, table.base.compat_pins.to)) {
    assertEquals(baseForm(`x${f}x`), `x${t}x`, `compat pin U+${f.codePointAt(0)!.toString(16)}`);
  }
  for (const [f, t] of pairs(table.match.between_ascii_letters.from, table.match.between_ascii_letters.to)) {
    assertEquals(matchForm(`x${f}x`), `x${t}x`, `between letters ${f}`);
    assertEquals(matchForm(`x${f} x`), "x x", `between letters ${f}, a space on one side`);
  }
  for (const [f, t] of pairs(table.base.confusables.from, table.base.confusables.to)) {
    assertEquals(baseForm(`x${f}x`), `x${t}x`, `confusable U+${f.codePointAt(0)!.toString(16)}`);
  }
  for (const [f, t] of pairs(table.base.digits.from, table.base.digits.to)) assertEquals(baseForm(f), t, `digit U+${f.codePointAt(0)!.toString(16)}`);
  for (const s of table.base.separators) {
    // A separator NFKC rewrites could never fire, so none is listed.
    assertEquals(s.normalize("NFKC"), s, `separator U+${s.codePointAt(0)!.toString(16)} survives NFKC`);
    assertEquals(baseForm(`a${s}b`), "a b", `separator U+${s.codePointAt(0)!.toString(16)}`);
  }
  for (const k of table.base.kept) assertEquals(baseForm(`a${k}b`), `a${k}b`, `kept ${k}`);
  for (const [f, t] of pairs(table.match.west_african.from, table.match.west_african.to)) {
    assertEquals(matchForm(`x${f}x`), `x${t}x`);
  }
  for (const [f, t] of Object.entries(table.match.west_african.multi)) assertEquals(matchForm(`x${f}x`), `x${t}x`);
  for (const m of table.match.strip_marks) assertEquals(matchForm(`x${m}x`), "xx", `strip mark U+${m.codePointAt(0)!.toString(16)}`);
  for (const [f, t] of pairs(table.match.leet.from, table.match.leet.to)) assertEquals(matchForm(`x${f}x`), `x${t}x`);
  for (const s of table.match.separators) assertEquals(matchForm(`a${s}b`), "a b", `match separator ${s}`);
});

Deno.test("a Twi word matches typed with or without its letters", () => {
  assertEquals(matchForm("k\u0254k\u0254\u0254"), matchForm("kokoo"));
  assertEquals(matchForm("\u0190NA"), "ena");
  assertEquals(matchForm("d\u0254\u0301 y\u025b\u0301"), matchForm("do ye"));
});

Deno.test("the base form keeps what contact and money rules need", () => {
  assertEquals(baseForm("I'm 16"), "i m 16");
  assertEquals(baseForm("Send $40 to kofi@gmail.com"), "send $40 to kofi@gmail.com");
  assertEquals(squashedForm("f u c k"), "fuck");
});

Deno.test("review fix round 1: splitters, marks and look-alikes", () => {
  // I-1: an invisible splitter never hides a word; a braille blank is a space.
  assertEquals(squashedForm("f\u034fu\ufe0fc\u{E0041}k"), "fuck");
  assertEquals(squashedForm("f\u2800u\u2800c\u2800k"), "fuck");
  // I-2: the base form keeps marks; the match form drops them.
  assertEquals(baseForm("y\u025b\u0301"), "y\u025b\u0301");
  assertEquals(matchForm("y\u025b\u0301"), "ye");
  assertEquals(squashedForm("f\u0338u\u0338c\u0338k\u0338"), "fuck");
  // A look-alike that carries a mark still folds.
  assertEquals(matchForm("sh\u0457t"), "shit");
  // M-1: a removed character between a letter and its mark.
  assertEquals(baseForm("e\u200b\u0301"), "\u00e9");
});

Deno.test("the match form is idempotent: a stored term is its own match form", () => {
  // Task 3's term CHECK (term = private.match_form(term)) relies on this.
  const once = (x: string) => {
    const m = matchForm(x);
    assertEquals(matchForm(m), m, `match form of ${JSON.stringify(x)} is not idempotent`);
  };
  for (const c of goldens.cases) {
    once(c.input);
    once(c.match);
  }
  // A fixed-seed random sample: code points from the fold table, the strip
  // blocks and the whole code space, mixed with ASCII.
  const pool = [
    ...table.base.remove, ...table.base.confusables.from, ...table.base.digits.from,
    ...table.base.separators, ...table.base.kept, ...table.match.west_african.from,
    ...table.match.strip_marks, ...table.match.leet.from, "\u2260", "\u226e", "\u226f", "\u014b",
  ];
  let seed = 20261104;
  const next = () => (seed = (seed * 1103515245 + 12345) % 2147483648) / 2147483648;
  for (let i = 0; i < 5000; i++) {
    let x = "";
    const len = 1 + Math.floor(next() * 12);
    for (let j = 0; j < len; j++) {
      const r = next();
      if (r < 0.4) x += pool[Math.floor(next() * pool.length)];
      else if (r < 0.7) x += String.fromCharCode(32 + Math.floor(next() * 95));
      else {
        let cp = Math.floor(next() * 0x110000);
        if (cp >= 0xd800 && cp <= 0xdfff) cp = 0x41;
        x += String.fromCodePoint(cp);
      }
    }
    once(x);
  }
});

Deno.test("every code point folds as pinned: an ICU or PostgreSQL Unicode upgrade fails here", async () => {
  // batch-2 review I-2: the goldens' parity entry is the sha256 of both
  // forms of x<c>x for every code point in its ranges. The SQL side
  // (supabase/tests/opinion_filter_parity_contracts.sql) checks the same
  // hash, so the two ports agree on every code point, not only on goldens.
  const lines: string[] = [];
  for (const [a, b] of goldens.parity.ranges) {
    for (let cp = a; cp <= b; cp++) {
      if (cp >= 0xd800 && cp <= 0xdfff) continue;
      const x = "x" + String.fromCodePoint(cp) + "x";
      lines.push(cp.toString(16) + "\t" + baseForm(x) + "\t" + matchForm(x) + "\n");
    }
  }
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(lines.join(""))));
  const hex = [...digest].map((b) => b.toString(16).padStart(2, "0")).join("");
  assertEquals(hex, goldens.parity.sha256, "the per-code-point fold moved: re-pin it in base.compat_pins");
});

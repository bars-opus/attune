import { assertEquals } from "https://deno.land/std@0.177.0/testing/asserts.ts";
import { parsePreview } from "./og.ts";

Deno.test("reads og tags in either attribute order and quote style", () => {
  const p = parsePreview(
    `<head><meta content="Ubud &amp; the &quot;villa&quot;" property="og:title">
     <meta property='og:description' content='Pool &#8211; view &#x2014; rice'>
     <meta property="og:image" content="/img/cover.jpg"></head>`,
    "https://villa.example/stay/ubud",
  );
  assertEquals(p.title, 'Ubud & the "villa"');
  assertEquals(p.description, "Pool – view — rice");
  assertEquals(p.imageUrl, "https://villa.example/img/cover.jpg");
});

Deno.test("falls back to <title> and meta description", () => {
  const p = parsePreview(
    `<title> Plain\n page </title><meta name="description" content="About us">`,
    "https://a.example/",
  );
  assertEquals(p.title, "Plain page");
  assertEquals(p.description, "About us");
  assertEquals(p.imageUrl, null);
});

Deno.test("strips control characters and markup, caps lengths by code point", () => {
  const p = parsePreview(
    `<meta property="og:title" content="A\u0000B\u0007C <b>bold</b> ${"😀".repeat(300)}">
     <meta property="og:description" content="${"x".repeat(900)}">`,
    "https://a.example/",
  );
  assertEquals(p.title!.startsWith("A B C bold "), true);
  assertEquals(Array.from(p.title!).length, 200);
  assertEquals(p.description!.length, 500);
});

Deno.test("only http(s) images are kept; bad entities do not throw", () => {
  const p = parsePreview(
    `<meta property="og:image" content="javascript:alert(1)"><meta property="og:title" content="&#99999999; &bogus; ok">`,
    "https://a.example/",
  );
  assertEquals(p.imageUrl, null);
  assertEquals(p.title, "&#99999999; &bogus; ok");
});

Deno.test("a page's own oEmbed link is found, made absolute, and only if http(s)", () => {
  const p = parsePreview(
    `<link rel="alternate" type="application/json+oembed" href="/oembed.json?url=https%3A%2F%2Fpin.example%2Fpin%2F1" title="x">`,
    "https://pin.example/pin/1/",
  );
  assertEquals(p.oembedUrl, "https://pin.example/oembed.json?url=https%3A%2F%2Fpin.example%2Fpin%2F1");
  assertEquals(
    parsePreview(`<link type="application/json+oembed" rel="alternate" href="javascript:x">`, "https://a.example/").oembedUrl,
    null,
  );
  assertEquals(parsePreview(`<link rel="stylesheet" href="/a.css">`, "https://a.example/").oembedUrl, null);
});

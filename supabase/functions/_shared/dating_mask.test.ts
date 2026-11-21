// Spec 2 W6a (§6.1, §7.3 masking parity; carry 3): the TypeScript mirror
// gives every fixture case's expected output, and says a caption is dropped
// exactly for the caption_drop cases. dating_v2_chat_contracts.sql runs the
// same file through private.dating_mask_contacts and
// private.dating_caption_invites.
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import fixture from "../../tests/fixtures/dating_mask_cases.json" with { type: "json" };
import { captionInvites, MASK, MASK_VERSION, maskContacts } from "./dating_mask.ts";

Deno.test("the fixture is the version this mirror masks", () => {
  assertEquals(fixture.mask_version, MASK_VERSION);
  assertEquals(fixture.mask, MASK);
  if (fixture.cases.length < 207) throw new Error("the fixture lost cases");
  for (const scope of ["mask", "caption_drop"]) {
    if (!fixture.cases.some((c) => c.scope === scope)) throw new Error(`no ${scope} case`);
  }
});

Deno.test("every case masks to its expected output", () => {
  for (const c of fixture.cases) assertEquals(maskContacts(c.text), c.expect, `${c.note}: ${JSON.stringify(c.text)}`);
});

Deno.test("a caption is dropped exactly for the caption_drop cases", () => {
  for (const c of fixture.cases) {
    assertEquals(captionInvites(c.text), c.scope === "caption_drop", `${c.note}: ${JSON.stringify(c.text)}`);
  }
});

Deno.test("masking never lifts by itself: masked text masks to itself", () => {
  for (const c of fixture.cases) assertEquals(maskContacts(c.expect), c.expect, JSON.stringify(c.expect));
});

Deno.test("a 1,000-character message masks in bounded time", () => {
  const long = "Call me on 0244 123 456 or snap amab_gh, ama@x.io. ".repeat(20).slice(0, 1000);
  const t0 = performance.now();
  const out = maskContacts(long);
  if (performance.now() - t0 > 2000) throw new Error("too slow");
  if (out.includes("0244") || out.includes("ama@x.io")) throw new Error("a contact detail got through");
});

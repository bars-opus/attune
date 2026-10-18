// Spec 5 (plan review I8): the weekly check-in reminder names nobody.
import { assert, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";

const src = await Deno.readTextFile(new URL("./index.ts", import.meta.url));

Deno.test("checkin_reminder copy names nobody", () => {
  const at = src.indexOf('case "checkin_reminder":');
  const block = src.slice(at, src.indexOf("break;", at));
  assert(at > -1);
  assert(!block.includes("partnerName"), "the copy names the partner");
  assertStringIncludes(block, "A minute to look back on your week.");
});

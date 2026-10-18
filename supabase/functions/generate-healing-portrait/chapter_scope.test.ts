// Spec 3b (F13 (1)): the Healing portrait reads only the journey's own
// relationship's insights.
import { assert, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";

const src = await Deno.readTextFile(new URL("./index.ts", import.meta.url));

Deno.test("insights are scoped to the journey's relationship", () => {
  const read = src.slice(src.indexOf('.from("personal_insights")'), src.indexOf(".limit(5)"));
  assertStringIncludes(read, '.eq("relationship_id", journey.relationship_id)');
  assert(src.includes("if (!journey.relationship_id)"), "no insights for a self-reported breakup");
});

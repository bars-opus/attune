// Spec 8 (plan review P8): Layer 2 knows the seventh need.
import { assert } from "https://deno.land/std@0.224.0/assert/mod.ts";

const src = await Deno.readTextFile(new URL("./index.ts", import.meta.url));

Deno.test("Layer 2 prompt and validator include communal_obligation", () => {
  assert(src.includes('"rest"|"communal_obligation"|null'), "prompt");
  assert(/\["respect", "fairness", "affection", "security", "autonomy", "rest", "communal_obligation"\]\.includes\(/.test(src), "validator");
});

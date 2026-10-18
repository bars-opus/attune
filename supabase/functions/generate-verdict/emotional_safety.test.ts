// Spec 1a: Emotional safety is self-facing; a shared verdict may not carry it
// forward as evidence.
import { assert } from "https://deno.land/std@0.208.0/assert/mod.ts";

Deno.test("generate-verdict builds no emotional_safety evidence", async () => {
  const source = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
  const fn = source.slice(source.indexOf("function buildEvidence"));
  const pulseLoop = fn.slice(0, fn.indexOf("for (const pattern of"));
  assert(pulseLoop.length > 0, "buildEvidence's pulse loop exists");
  assert(!pulseLoop.includes("emotional_safety"));
});

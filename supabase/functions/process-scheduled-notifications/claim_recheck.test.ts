// Spec 1b follow-up (M7): the quiet-hours guard re-checks the worker's claim
// and can bounce it back to 'pending' (a row reached late in a backlog past
// 22:00). The worker must send only rows that actually became 'processing'.
import { assert, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";

const src = await Deno.readTextFile(new URL("./index.ts", import.meta.url));

Deno.test("the claim reads back the row's status and skips a bounced claim", () => {
  const claim = src.slice(src.indexOf('.update({ status: "processing"'));
  const select = claim.slice(0, claim.indexOf(".maybeSingle()"));
  assertStringIncludes(select, "status");
  assert(
    /if \(!job \|\| job\.status !== "processing"\) continue;/.test(src),
    "a claim the guard bounced back to pending is not sent",
  );
});

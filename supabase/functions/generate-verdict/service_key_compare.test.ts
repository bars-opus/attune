// supabase/functions/generate-verdict/service_key_compare.test.ts
//
// The service-role check compares the presented token with the service key
// in constant time (checklist 2.3; stories Wave 5 final review M8), using
// constantTimeEqual from _shared/attune_auth.ts, never === or !==.
import { assert } from "https://deno.land/std@0.224.0/assert/mod.ts";

Deno.test("the service key is never compared with === or !==", async () => {
  const src = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
  assert(
    /import\s*\{[^}]*\bconstantTimeEqual\b[^}]*\}\s*from\s*["']\.\.\/_shared\/attune_auth\.ts["']/
      .test(src),
    "constantTimeEqual is not imported from _shared/attune_auth.ts",
  );
  const offending = src
    .split("\n")
    .filter((line) => /[!=]==/.test(line) && /serviceKey|SERVICE_ROLE_KEY/.test(line));
  assertEqualsEmpty(offending);
  assert(
    /constantTimeEqual\([^)]*(serviceKey|SERVICE_ROLE_KEY)/.test(src),
    "the service-key check does not use constantTimeEqual",
  );
});

function assertEqualsEmpty(lines: string[]) {
  assert(lines.length === 0, `plain comparison left in:\n${lines.join("\n")}`);
}

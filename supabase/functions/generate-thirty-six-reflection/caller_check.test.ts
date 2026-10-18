// Spec 3b (R3b-6; plan review I3): only a member of an active shared space
// can ask for a reflection; the journey is read as the caller, so RLS (the
// chapter gate) proves membership before the service role is used.
import { assert, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";

const src = await Deno.readTextFile(new URL("./index.ts", import.meta.url));

Deno.test("requires a signed-in caller and reads the journey as them", () => {
  assertStringIncludes(src, "requireUser(req)");
  assertStringIncludes(src, "SUPABASE_ANON_KEY");
  const asCaller = src.indexOf("asCaller");
  const service = src.indexOf("SUPABASE_SERVICE_ROLE_KEY");
  assert(asCaller > -1 && service > asCaller, "caller check before the service role");
});

Deno.test("refuses a space that is not active", () => {
  assertStringIncludes(src, 'status !== "active"');
  assertStringIncludes(src, "409");
});

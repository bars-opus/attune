// Spec 3c (Review Focus 3): the link is only ever to the caller's own file.
import { assert, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";

const src = await Deno.readTextFile(new URL("./index.ts", import.meta.url));

Deno.test("scoped by the verified caller, never by a request id", () => {
  assertStringIncludes(src, "requireUser(req)");
  assertStringIncludes(src, '.eq("user_id", user.id)');
  assert(!src.includes("req.json"), "no request body is read");
  assertStringIncludes(src, "createSignedUrl(key, 900");
});

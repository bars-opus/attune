// Spec 3b (R3b-4; plan review I6): the person's relationships are ended and
// their shared-answer data and media are dealt with BEFORE the auth user is
// deleted, and a failure in either step is recorded, never half-silent.
import { assert, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";

const src = await Deno.readTextFile(new URL("./index.ts", import.meta.url));

Deno.test("prepare_account_deletion runs before deleteUser", () => {
  const prepare = src.indexOf('rpc("prepare_account_deletion"');
  const del = src.indexOf("auth.admin.deleteUser(");
  assert(prepare > -1, "calls prepare_account_deletion");
  assert(del > prepare, "deleteUser comes after it");
});

Deno.test("a failed prepare stops the deletion and is recorded", () => {
  const prepare = src.slice(src.indexOf('rpc("prepare_account_deletion"'), src.indexOf("auth.admin.deleteUser("));
  assertStringIncludes(prepare, "failure_reason");
  assertStringIncludes(prepare, "throw");
});

Deno.test("the confirmation e-mail says what happened to shared things", () => {
  assert(!src.includes("has been anonymised"), "no claim that shared data was anonymised");
  assertStringIncludes(src, "If you were in a shared space, it has ended; your messages, photos and game answers were removed from it");
});

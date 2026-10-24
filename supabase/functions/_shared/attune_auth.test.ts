// supabase/functions/_shared/attune_auth.test.ts
// Stories Wave 5 (06 #22, 07b V10; checklist P0-U 2.3): the service-role
// bearer is compared in time that does not depend on where it differs.
import { assert, assertEquals, assertThrows } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { constantTimeEqual, HttpError, requireServiceRole } from "./attune_auth.ts";

const KEY = "service-role-key-0123456789abcdef";

function req(authorization?: string): Request {
  return new Request("http://worker/", {
    headers: authorization === undefined ? {} : { Authorization: authorization },
  });
}

Deno.test("constantTimeEqual: only the identical string matches", () => {
  assert(constantTimeEqual(KEY, KEY));
  assert(!constantTimeEqual(KEY.slice(0, -1) + "X", KEY), "last byte differs");
  assert(!constantTimeEqual("X" + KEY.slice(1), KEY), "first byte differs");
  assert(!constantTimeEqual(KEY.slice(0, 5), KEY), "a prefix");
  assert(!constantTimeEqual(KEY + "extra", KEY), "longer");
  assert(!constantTimeEqual("", KEY), "empty");
  assert(!constantTimeEqual("é", "e"), "multi-byte");
});

Deno.test("requireServiceRole accepts exactly the service-role bearer", () => {
  Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", KEY);
  requireServiceRole(req(`Bearer ${KEY}`));
  requireServiceRole(req(`bearer   ${KEY}  `));
  for (const bad of [undefined, "", "Bearer", `Bearer ${KEY}x`, `Bearer ${KEY.slice(1)}`, `Bearer ${KEY.toUpperCase()}`]) {
    const e = assertThrows(() => requireServiceRole(req(bad)), HttpError);
    assertEquals(e.status, 403, String(bad));
  }
});

Deno.test("the check never compares the secret with === or !==", async () => {
  const src = await Deno.readTextFile(new URL("./attune_auth.ts", import.meta.url));
  const start = src.indexOf("export function requireServiceRole");
  const fn = src.slice(start, src.indexOf("\n}\n", start));
  assert(fn.includes("constantTimeEqual("), fn);
  assert(!/[!=]==/.test(fn), `plain comparison left in:\n${fn}`);
});

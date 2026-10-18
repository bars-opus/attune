// Spec 3a (research 06 §3 F1 (1); R3-2, R3-15): ending sends nothing to the
// other partner -- no push, SMS or email -- and runs as the caller (the RPC
// reads auth.uid(); a service-role client has none).
import { assert, assertFalse } from "https://deno.land/std@0.224.0/assert/mod.ts";

const src = await Deno.readTextFile(new URL("./index.ts", import.meta.url));

Deno.test("no notification path at all", () => {
  for (const banned of ["push_queue", "enqueuePush", "sendPush", "onesignal", "in_app_notifications", "sendSms", "sendEmail", "WEBHOOK_URL"]) {
    assertFalse(src.includes(banned), `index.ts mentions ${banned}`);
  }
});

Deno.test("the RPC runs as the caller, not the service role", () => {
  assertFalse(src.includes("serviceRoleClient"), "service-role client used");
  assert(src.includes("SUPABASE_ANON_KEY"), "user-scoped client");
  assert(/Authorization/.test(src), "forwards the caller's JWT");
  assert(src.includes('rpc("end_relationship"'), "calls end_relationship");
});

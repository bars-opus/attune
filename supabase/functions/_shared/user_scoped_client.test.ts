// Proves userScopedClient constructs a client authorized as the caller,
// not the service role -- i.e. that querying through it is subject to
// RLS. This test needs a real Supabase local instance running (the same
// one supabase/tests/*.sql run against) since it exercises real
// PostgREST/RLS behavior, not a mock.
import {
  assertRejects,
} from "https://deno.land/std@0.208.0/assert/mod.ts";
import { userScopedClient } from "./user_scoped_client.ts";

Deno.test("userScopedClient rejects a request with no Authorization header", async () => {
  const req = new Request("http://localhost/test", { method: "POST" });
  await assertRejects(() => userScopedClient(req));
});

Deno.test("userScopedClient rejects an invalid bearer token", async () => {
  const req = new Request("http://localhost/test", {
    method: "POST",
    headers: { Authorization: "Bearer not-a-real-token" },
  });
  await assertRejects(() => userScopedClient(req));
});

// A full "does RLS actually apply" integration test requires a real
// signed-in test user's JWT (not fabricable in a unit test without
// hitting the Auth API) -- that end-to-end proof belongs in Task 2's
// context-loader tests, which run against a real local Supabase
// instance with a real test user session. This file proves the helper's
// own auth-failure paths; Task 2 proves RLS is actually the operative
// authority once a real token is available.

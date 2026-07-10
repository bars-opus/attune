// supabase/functions/resolve-link/index.test.ts
//
// Pure handler-level tests. The handler is exported from index.ts so we can
// exercise routing/validation without spinning up the function server.
// Network-touching paths (Postgres queries) are not asserted here; those are
// covered by the smoke test in the task plan.

import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";

Deno.test("resolve-link: returns 400 when slug missing", async () => {
  const req = new Request("https://x/resolve-link");
  const { handler } = await import("./index.ts");
  const res = await handler(req);
  assertEquals(res.status, 400);
  const body = await res.json();
  assertEquals(body.error, "Missing slug");
});

Deno.test("resolve-link: returns 400 when slug is blank whitespace", async () => {
  const req = new Request("https://x/resolve-link?slug=%20%20%20");
  const { handler } = await import("./index.ts");
  const res = await handler(req);
  assertEquals(res.status, 400);
});

Deno.test("resolve-link: returns 405 on non-GET method", async () => {
  const req = new Request("https://x/resolve-link?slug=foo", { method: "POST" });
  const { handler } = await import("./index.ts");
  const res = await handler(req);
  assertEquals(res.status, 405);
});

Deno.test("resolve-link: handles OPTIONS preflight from allowed origin", async () => {
  const req = new Request("https://x/resolve-link", {
    method: "OPTIONS",
    headers: { "Origin": "https://aurain.barsopus.com" },
  });
  const { handler } = await import("./index.ts");
  const res = await handler(req);
  assertEquals(res.status, 204);
  assertEquals(
    res.headers.get("Access-Control-Allow-Origin"),
    "https://aurain.barsopus.com",
  );
});

Deno.test("resolve-link: omits Allow-Origin for unknown origins", async () => {
  const req = new Request("https://x/resolve-link", {
    method: "OPTIONS",
    headers: { "Origin": "https://evil.example.com" },
  });
  const { handler } = await import("./index.ts");
  const res = await handler(req);
  assertEquals(res.status, 204);
  assertEquals(res.headers.get("Access-Control-Allow-Origin"), null);
});

import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";

Deno.test("whatsapp-send: rejects non-POST", async () => {
  const { handler } = await import("./index.ts");
  const req = new Request("https://x/whatsapp-send", { method: "GET" });
  const res = await handler(req);
  assertEquals(res.status, 405);
});

Deno.test("whatsapp-send: rejects missing auth", async () => {
  const { handler } = await import("./index.ts");
  const req = new Request("https://x/whatsapp-send", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ to: "+233200000099", template: "x", params: {} }),
  });
  const res = await handler(req);
  assertEquals(res.status, 401);
});

Deno.test("whatsapp-send: rejects missing 'to'", async () => {
  // Set a fake service role key for the env-check pass-through.
  Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "test-service-role-key");
  const { handler } = await import("./index.ts");
  const req = new Request("https://x/whatsapp-send", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: "Bearer test-service-role-key",
    },
    body: JSON.stringify({ template: "x", params: {} }),
  });
  const res = await handler(req);
  assertEquals(res.status, 400);
});

Deno.test("whatsapp-send: rejects missing 'template'", async () => {
  Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "test-service-role-key");
  const { handler } = await import("./index.ts");
  const req = new Request("https://x/whatsapp-send", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: "Bearer test-service-role-key",
    },
    body: JSON.stringify({ to: "+233200000099", params: {} }),
  });
  const res = await handler(req);
  assertEquals(res.status, 400);
});

Deno.test("whatsapp-send: rejects invalid JSON", async () => {
  Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "test-service-role-key");
  const { handler } = await import("./index.ts");
  const req = new Request("https://x/whatsapp-send", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: "Bearer test-service-role-key",
    },
    body: "not json",
  });
  const res = await handler(req);
  assertEquals(res.status, 400);
});

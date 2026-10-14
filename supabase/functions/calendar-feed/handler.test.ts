import { assert, assertEquals } from "https://deno.land/std@0.208.0/assert/mod.ts";
import { handleFeedRequest, sha256Hex, tokenFromPath } from "./handler.ts";

const TOKEN = "a".repeat(64);
const url = (p: string) => `https://x.supabase.co/functions/v1/calendar-feed/${p}`;
const NOW = new Date("2026-11-01T10:00:00Z");

Deno.test("the token comes from the last path segment, with or without .ics", () => {
  assertEquals(tokenFromPath(`/calendar-feed/${TOKEN}.ics`), TOKEN);
  assertEquals(tokenFromPath(`/functions/v1/calendar-feed/${TOKEN}`), TOKEN);
  assertEquals(tokenFromPath("/calendar-feed/not-a-token.ics"), null);
  assertEquals(tokenFromPath("/calendar-feed/"), null);
});

Deno.test("sha256Hex matches Postgres's encode(sha256(...), 'hex')", async () => {
  assertEquals(
    await sha256Hex("abc"),
    "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
  );
});

Deno.test("bad, unknown and revoked links get the very same 404", async () => {
  const none = () => Promise.resolve(null);
  const responses = [
    await handleFeedRequest(new Request(url("short.ics")), none, NOW),
    await handleFeedRequest(new Request(url(`${TOKEN}.ics`)), none, NOW),
    await handleFeedRequest(new Request(url(`${TOKEN}.ics`), { method: "POST" }), none, NOW),
  ];
  const bodies = await Promise.all(responses.map((r) => r.text()));
  for (const r of responses) assertEquals(r.status, 404);
  assertEquals(new Set(bodies).size, 1);
  assertEquals(new Set(responses.map((r) => r.headers.get("content-type"))).size, 1);
});

Deno.test("a live link gets the calendar, asking by the token's hash", async () => {
  let asked = "";
  const res = await handleFeedRequest(new Request(url(`${TOKEN}.ics`)), (h) => {
    asked = h;
    return Promise.resolve({ items: [] });
  }, NOW);
  assertEquals(res.status, 200);
  assertEquals(asked, await sha256Hex(TOKEN));
  assert(res.headers.get("content-type")!.startsWith("text/calendar"));
  assert((await res.text()).startsWith("BEGIN:VCALENDAR"));
});

Deno.test("a server failure says try later, not 'no such link'", async () => {
  const res = await handleFeedRequest(new Request(url(`${TOKEN}.ics`)), () => Promise.reject(new Error("db down")), NOW);
  assertEquals(res.status, 503);
});

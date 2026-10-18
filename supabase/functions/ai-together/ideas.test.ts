import { assert, assertEquals, assertStringIncludes } from "https://deno.land/std@0.208.0/assert/mod.ts";
import { buildIdeasPrompt, parseIdeas, validateIdeasRequest } from "./ideas.ts";

Deno.test("ideas requests: a window of 1–24 hours", () => {
  assert(validateIdeasRequest({ window_start_local: "2026-11-05T19:00", window_end_local: "2026-11-05T22:00" }).ok);
  assert(!validateIdeasRequest({ window_start_local: "2026-11-05T19:00", window_end_local: "2026-11-05T19:30" }).ok);
  assert(!validateIdeasRequest({ window_start_local: "2026-11-05T19:00", window_end_local: "2026-11-06T20:00" }).ok);
});

Deno.test("the prompt carries only the window", () => {
  const p = buildIdeasPrompt({ startLocal: "2026-11-05T19:00", endLocal: "2026-11-05T22:00" });
  assertStringIncludes(p.user, "Thursday 2026-11-05, 19:00–22:00 (3 hours)");
  assertStringIncludes(p.system, "exactly three");
});

Deno.test("exactly three short ideas, or nothing", () => {
  const three = [1, 2, 3].map((i) => ({ title: `Idea ${i}`, blurb: "A line." }));
  assertEquals(parseIdeas({ ideas: three })?.length, 3);
  assertEquals(parseIdeas({ ideas: three.slice(0, 2) }), null);
  assertEquals(parseIdeas({ ideas: [...three, three[0]] }), null);
  assertEquals(parseIdeas({ ideas: [{ title: "", blurb: "x" }, three[1], three[2]] }), null);
  assertEquals(parseIdeas({ ideas: [{ title: "x".repeat(61), blurb: "x" }, three[1], three[2]] }), null);
});

Deno.test("a fully free day (08:00–22:00, 14 hours) can get ideas", () => {
  assert(validateIdeasRequest({ window_start_local: "2026-11-07T08:00", window_end_local: "2026-11-07T22:00" }).ok);
  assert(!validateIdeasRequest({ window_start_local: "2026-11-07T08:00", window_end_local: "2026-11-08T08:30" }).ok);
});

// Spec 7 (B9, plan review M12): a quiet person's ideas stay gentle; the
// prompt never says why.
Deno.test("a quiet requester gets gentle ideas, with no state named", () => {
  const p = buildIdeasPrompt({ startLocal: "2026-11-05T19:00", endLocal: "2026-11-05T22:00", quiet: true });
  assertStringIncludes(p.system, "Keep ideas gentle, low-effort and unceremonious.");
  for (const word of ["quiet", "loss", "grief", "hard time", "depress", "sad"]) {
    assert(!p.system.toLowerCase().includes(word) && !p.user.toLowerCase().includes(word), word);
  }
  const plain = buildIdeasPrompt({ startLocal: "2026-11-05T19:00", endLocal: "2026-11-05T22:00" });
  assert(!plain.system.includes("gentle, low-effort"));
});

Deno.test("the handler asks whether the requester is quiet", async () => {
  const src = await Deno.readTextFile(new URL("./handler.ts", import.meta.url));
  assertStringIncludes(src, 'deps.service.rpc("user_is_quiet"');
});

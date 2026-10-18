// Spec 8 (plan review I8): a Pause, its reply, an "I noticed…" note, or any
// message kept out of analysis never reaches Understand, Assist or Sessions
// as a target or as context.
import { assert, assertFalse } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { isOrdinaryTextRow } from "./ai_context_loader.ts";
import { isEligibleWindowRow } from "./ai_session_context.ts";

const row = (over: Record<string, unknown> = {}) => ({
  content: "dinner at 7?", deleted_at: null, is_system_notice: false, message_origin: "user",
  media_url: null, game_session_id: null, media_type: null, message_analysis_skipped: false, ...over,
});

Deno.test("only ordinary, analysable text is eligible", () => {
  for (const check of [isOrdinaryTextRow, isEligibleWindowRow]) {
    assert(check(row()));
    assertFalse(check(row({ media_type: "pause" })));
    assertFalse(check(row({ media_type: "pause_reply" })));
    assertFalse(check(row({ media_type: "appreciation" })));
    assertFalse(check(row({ message_analysis_skipped: true })));
  }
});

Deno.test("the loaders select the columns they filter on", async () => {
  // media_type is client-readable; message_analysis_skipped is not (the
  // messages column allowlist). The user-scoped assistant loader filters on
  // type and must never select it; the shared-window loader runs as the
  // service role (every caller passes it), so it selects the column and its
  // skipped check is real (sync audit M-11).
  for (const [f, skipped] of [["./ai_context_loader.ts", false], ["./ai_session_context.ts", true]] as const) {
    const src = await Deno.readTextFile(new URL(f, import.meta.url));
    const selects = [...src.matchAll(/\.select\(\s*"([^"]+)"/g)].map((m) => m[1]).filter((s) => s.includes("content"));
    assert(selects.length > 0, f);
    for (const s of selects) {
      assert(s.includes("media_type"), `${f}: ${s}`);
      assert(s.includes("message_analysis_skipped") === skipped, `${f}: message_analysis_skipped selected: ${!skipped}`);
    }
  }
  const sessions = await Deno.readTextFile(new URL("../ai-sessions/index.ts", import.meta.url));
  for (const m of sessions.matchAll(/selectSharedWindow\(\s*(\w+)/g)) {
    assert(m[1] === "service", `selectSharedWindow called with ${m[1]}, not the service client`);
  }
});

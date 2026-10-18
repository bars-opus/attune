// Sync audit I-3: an AI session's target is an ordinary text message in the
// same relationship — never a pause, a note, a notice, Assist output, media
// or a deleted row (the same rule the window and the assistant loaders use).
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { targetIsOrdinary } from "./index.ts";

function service(row: Record<string, unknown> | null) {
  const builder = {
    select: () => builder,
    eq: () => builder,
    maybeSingle: () => Promise.resolve({ data: row, error: null }),
  };
  return { from: () => builder };
}

const ordinary = {
  id: "m1",
  relationship_id: "r1",
  content: "dinner at 7?",
  deleted_at: null,
  is_system_notice: false,
  message_origin: "user",
  media_url: null,
  media_type: null,
  game_session_id: null,
  message_analysis_skipped: false,
};

Deno.test("an ordinary message in the relationship is a target", async () => {
  assertEquals(await targetIsOrdinary(service(ordinary) as never, "r1", "m1"), true);
});

Deno.test("anything else is not", async () => {
  for (
    const row of [
      null,
      { ...ordinary, relationship_id: "r2" },
      { ...ordinary, media_type: "pause" },
      { ...ordinary, media_type: "appreciation" },
      { ...ordinary, is_system_notice: true },
      { ...ordinary, message_origin: "attune_assist" },
      { ...ordinary, deleted_at: "2026-10-18T00:00:00Z" },
      { ...ordinary, message_analysis_skipped: true },
    ]
  ) {
    assertEquals(await targetIsOrdinary(service(row) as never, "r1", "m1"), false, JSON.stringify(row));
  }
});

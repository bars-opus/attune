// A Together event alarm must carry its event id to the app (deep link),
// through the privacy allowlist like reminder_id and entry_id do.
import { assertStringIncludes } from "https://deno.land/std@0.208.0/assert/mod.ts";

Deno.test("push data may carry event_id", async () => {
  const source = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
  const allow = source.slice(source.indexOf("function privacySafeData"));
  assertStringIncludes(allow.slice(0, allow.indexOf("];")), '"event_id"');
});

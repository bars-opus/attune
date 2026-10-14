// The verdict is shared by the couple, so a private conflict is never
// evidence (Together spec §3.5, plan Phase 4 R1).

import { assertMatch } from "https://deno.land/std@0.208.0/assert/mod.ts";

Deno.test("generate-verdict reads only shared moments", async () => {
  const source = await Deno.readTextFile(
    new URL("./index.ts", import.meta.url),
  );
  const query = source.slice(source.indexOf('.from("timeline_events")'));
  const statement = query.slice(0, query.indexOf(";"));
  assertMatch(statement, /\.eq\("visibility", "shared"\)/);
});

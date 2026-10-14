// Pulse is one score per couple that both partners read, so a private
// conflict must not feed it (Together plan Phase 4 R1). The function runs
// as the service role, so the query has to filter for itself.

import { assertMatch } from "https://deno.land/std@0.208.0/assert/mod.ts";

Deno.test("compute-pulse reads only shared moments", async () => {
  const source = await Deno.readTextFile(
    new URL("./index.ts", import.meta.url),
  );
  const query = source.slice(source.indexOf(".from('timeline_events')"));
  const statement = query.slice(0, query.indexOf("// 2."));
  assertMatch(statement, /\.eq\('visibility', 'shared'\)/);
});

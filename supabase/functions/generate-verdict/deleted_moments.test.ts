// The verdict must never read a soft-deleted moment as evidence
// (Together spec §8.1 #10). The function runs as the service role, so
// the read policy's `deleted_at IS NULL` does not protect it; the query
// has to filter for itself.

import { assertMatch } from "https://deno.land/std@0.208.0/assert/mod.ts";

Deno.test("generate-verdict reads only moments that are not deleted", async () => {
  const source = await Deno.readTextFile(
    new URL("./index.ts", import.meta.url),
  );
  const query = source.slice(source.indexOf('.from("timeline_events")'));
  const statement = query.slice(0, query.indexOf(";"));
  assertMatch(statement, /\.is\("deleted_at", null\)/);
});

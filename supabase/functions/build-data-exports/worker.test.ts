// Spec 3c: the worker is the service role's, builds from the SQL source of
// truth, and never logs a person's data.
import { assert, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";

const entry = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
const src = await Deno.readTextFile(new URL("./parts.ts", import.meta.url));

Deno.test("service role only; SQL decides the content", () => {
  assertStringIncludes(entry, "requireServiceRole(req)");
  assertStringIncludes(src, 'rpc("export_bundle"');
  assertStringIncludes(src, 'rpc("export_media_manifest"');
  assertStringIncludes(src, 'rpc("export_chat_page"');
  assert(!/\.from\("(messages|planning_|story_items|couple_events)/.test(src), "no table read outside the SQL bundle");
});

Deno.test("a failure is retried per part and logs only its kind", () => {
  assertStringIncludes(src, 'rpc("export_retry_part"');
  assert(!/console\.(log|error)\([^)]*bundle/.test(src), "no bundle in logs");
});

Deno.test("a part per run: the file is queued before it is stored", () => {
  const begin = src.indexOf('rpc("export_begin_part"');
  const upload = src.indexOf('.from("data-exports")');
  const finish = src.indexOf('rpc("export_finish_part"');
  assert(begin > -1 && upload > begin && finish > upload, "begin -> upload -> finish");
  assertStringIncludes(src, "chatPagesPerPart");
  assertStringIncludes(src, "maxParts");
  assert(!src.includes("${job.user_id}/"), "no user id in a path");
});

Deno.test("sizes are checked before downloading; a missing file is listed, not dropped", () => {
  const admit = src.indexOf("budget.admit(item.size_bytes)");
  const download = src.indexOf(".download(item.object_name)");
  assert(admit > -1 && download > admit);
  assertStringIncludes(src, 'reason: "unavailable"');
});

Deno.test("runs in the background so the cron's call returns at once", () => {
  assertStringIncludes(entry, "waitUntil");
});

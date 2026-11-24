// Spec 2 W9 (§7.3, S-4, I-13): the dating part comes only from
// dating_export_for_job with the job being built; nothing else is asked.
import { assert, assertEquals, assertRejects } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { addDatingPart } from "./dating_part.ts";

type Call = { fn: string; params: Record<string, unknown> };

function fake(answer: { data?: unknown; error?: unknown }) {
  const calls: Call[] = [];
  const files: Record<string, Uint8Array> = {};
  const client = {
    rpc: (fn: string, params: Record<string, unknown> = {}) => {
      calls.push({ fn, params });
      return Promise.resolve({ data: answer.data ?? null, error: answer.error ?? null });
    },
  };
  const zip = { add: (name: string, bytes: Uint8Array) => (files[name] = bytes) };
  return { client, calls, files, zip };
}

Deno.test("dating.json is the job's own call, by the job id alone", async () => {
  const part = { format: "attune-dating-export", conversations: [{ name: "conversation-1", my_messages: [] }] };
  const { client, calls, files, zip } = fake({ data: part });
  assertEquals(await addDatingPart(client, "job-7", zip), true);
  assertEquals(calls, [{ fn: "dating_export_for_job", params: { p_job_id: "job-7" } }]);
  assertEquals(Object.keys(files), ["dating.json"]);
  assertEquals(JSON.parse(new TextDecoder().decode(files["dating.json"])), part);
});

Deno.test("no Dating data: no file", async () => {
  const { client, files, zip } = fake({ data: null });
  assertEquals(await addDatingPart(client, "job-8", zip), false);
  assertEquals(Object.keys(files), []);
});

Deno.test("a refusal fails the part (the worker retries it; nothing is written)", async () => {
  const { client, files, zip } = fake({ error: { message: "export:not_building" } });
  await assertRejects(() => addDatingPart(client, "job-9", zip));
  assertEquals(Object.keys(files), []);
});

Deno.test("the data phase adds the part after the bundle, and never names a user id", async () => {
  const src = await Deno.readTextFile(new URL("./parts.ts", import.meta.url));
  const bundle = src.indexOf('rpc("export_bundle"');
  const dating = src.indexOf("addDatingPart(supabase, job.id, zip)");
  assert(bundle > -1 && dating > bundle, "export_bundle, then the dating part");
  assert(dating < src.indexOf('if (job.phase === "chat")'), "in the data phase");
  const part = await Deno.readTextFile(new URL("./dating_part.ts", import.meta.url));
  assert(!/user_id|p_user/.test(part.replace(/\/\/.*$/gm, "")), "no user id is sent");
});

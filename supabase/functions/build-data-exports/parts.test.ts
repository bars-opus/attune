// Spec 3c re-review (I2-I5, M5): one part per run, against a fake client.
import { assert, assertEquals, assertRejects } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { unzipSync } from "https://esm.sh/fflate@0.8.2";
import { ZipStream } from "./bundle.ts";
import { buildPart, type Job, type Limits, runOnce } from "./parts.ts";

const limits: Limits = {
  chatPage: 2, chatPagesPerPart: 10, chatPartBytes: 1_000_000, partCeiling: 2_000_000,
  mediaWindow: 100, maxParts: 12,
};

function job(over: Partial<Job> = {}): Job {
  return {
    id: "j1", user_id: "u1", relationship_ids: ["r1", "r2"], phase: "chat", rel_index: 1,
    chat_after_at: null, chat_after_id: null, chat_page: 0,
    media_after_bucket: null, media_after_name: null, storage_keys: ["k1"], left_out: [], ...over,
  };
}

type Call = { fn: string; params: Record<string, unknown> };

// deno-lint-ignore no-explicit-any
function fake(handlers: Record<string, (p: any) => unknown>, downloads: Record<string, { error?: unknown; bytes?: number }> = {}) {
  const calls: Call[] = [];
  const uploads: string[] = [];
  const client = {
    rpc: (fn: string, params: Record<string, unknown> = {}) => {
      calls.push({ fn, params });
      try {
        return Promise.resolve({ data: handlers[fn]?.(params) ?? null, error: null });
      } catch (error) {
        return Promise.resolve({ data: null, error });
      }
    },
    storage: {
      from: (_bucket: string) => ({
        download: (name: string) => {
          const d = downloads[name] ?? { bytes: 1 };
          return Promise.resolve(d.error
            ? { data: null, error: d.error }
            : { data: new Blob([new Uint8Array(d.bytes ?? 1)]), error: null });
        },
        upload: (key: string) => {
          uploads.push(key);
          return Promise.resolve({ error: null });
        },
      }),
    },
  };
  return { client, calls, uploads };
}

const rowsOf = (n: number, text = "x") => Array.from({ length: n }, (_, i) => ({ ref: `m${i}`, text }));

Deno.test("chat: an empty chapter does not end the part; the next one is read in the same run (I3)", async () => {
  const { client } = fake({
    export_chat_page: (p) => p.p_relationship_id === "r1"
      ? [{ rows: [], last_at: null, last_id: null }]
      : [{ rows: rowsOf(1), last_at: "t", last_id: "i" }],
  });
  const zip = new ZipStream();
  const { next } = await buildPart(client, job(), zip, limits);
  assertEquals(zip.count, 1);
  assertEquals(next.phase, "media");
  const files = unzipSync(new Uint8Array(await zip.finish().arrayBuffer()));
  assert(files["relationship-2/chat/page-1.json"], Object.keys(files).join());
});

Deno.test("chat: a part stops at its byte budget and carries on from the cursor (I3)", async () => {
  let n = 0;
  const { client } = fake({
    export_chat_page: () => [{ rows: rowsOf(2, "y".repeat(400)), last_at: `t${++n}`, last_id: `i${n}` }],
  });
  const zip = new ZipStream();
  const { next } = await buildPart(client, job({ relationship_ids: ["r1"] }), zip, { ...limits, chatPartBytes: 500 });
  assertEquals(zip.count, 1);
  assertEquals(next, { ...next, phase: "chat", rel_index: 1, chat_after_at: "t1", chat_after_id: "i1", chat_page: 1 });
});

Deno.test("chat: a page too big for one part is asked for again in smaller pieces (I3)", async () => {
  const limitsSeen: number[] = [];
  const { client } = fake({
    export_chat_page: (p) => {
      limitsSeen.push(p.p_limit);
      return [{ rows: rowsOf(p.p_limit, "z".repeat(1000)), last_at: "t", last_id: "i" }];
    },
  });
  const zip = new ZipStream();
  await buildPart(client, job({ relationship_ids: ["r1"] }), zip, { ...limits, chatPage: 8, partCeiling: 3000 });
  assertEquals(limitsSeen.slice(0, 2), [8, 2]);
  assertEquals(zip.count, 1);
});

Deno.test("media: walked by cursor; a full part records the last file taken (M5)", async () => {
  const { client, calls } = fake({
    export_media_manifest: () => [
      { bucket: "b", object_name: "a", zip_path: "media/a", size_bytes: 10 },
      { bucket: "b", object_name: "c", zip_path: "media/c", size_bytes: 10 },
    ],
  });
  const zip = new ZipStream();
  const { next } = await buildPart(
    client, job({ phase: "media", media_after_bucket: "b", media_after_name: "0" }), zip,
    { ...limits, mediaBudget: { files: 1, bytes: 100, perFile: 50 } },
  );
  const manifest = calls.find((c) => c.fn === "export_media_manifest")!;
  assertEquals([manifest.params.p_after_bucket, manifest.params.p_after_name], ["b", "0"]);
  assertEquals([next.phase, next.media_after_bucket, next.media_after_name], ["media", "b", "a"]);
});

Deno.test("media: a missing file is listed; any other download error fails the part (I4)", async () => {
  const manifest = () => [{ bucket: "b", object_name: "gone", zip_path: "media/gone", size_bytes: 5 }];
  const gone = fake({ export_media_manifest: manifest }, { gone: { error: { status: 404 } } });
  const { leftOut } = await buildPart(gone.client, job({ phase: "media" }), new ZipStream(), limits);
  assertEquals(leftOut, [{ file: "media/gone", reason: "unavailable" }]);
  const busy = fake({ export_media_manifest: manifest }, { gone: { error: { status: 503 } } });
  await assertRejects(() => buildPart(busy.client, job({ phase: "media" }), new ZipStream(), limits));
});

Deno.test("media: the last allowed part lists what did not fit and finishes", async () => {
  const { client, calls } = fake({
    export_media_manifest: () => [
      { bucket: "b", object_name: "a", zip_path: "media/a", size_bytes: 10 },
      { bucket: "b", object_name: "c", zip_path: "media/c", size_bytes: 10 },
    ],
  });
  const { next, leftOut } = await buildPart(
    client, job({ phase: "media", storage_keys: Array(11).fill("k") }), new ZipStream(),
    { ...limits, mediaBudget: { files: 1, bytes: 100, perFile: 50 } },
  );
  assertEquals(calls.find((c) => c.fn === "export_media_manifest")!.params.p_limit, null);
  assertEquals(next.phase, "done");
  assertEquals(leftOut, [{ file: "media/c", reason: "over_limit" }]);
});

Deno.test("a run with nothing to store uploads nothing and records progress (I3)", async () => {
  const { client, calls, uploads } = fake({
    claim_data_export: () => [job({ phase: "media", storage_keys: ["k1", "k2"] })],
    export_media_manifest: () => [],
  });
  await runOnce(client, limits);
  assertEquals(uploads, []);
  assert(!calls.some((c) => c.fn === "export_begin_part"));
  const finish = calls.find((c) => c.fn === "export_finish_part")!;
  assertEquals([finish.params.p_key, finish.params.p_done], [null, true]);
});

Deno.test("an error retries the part instead of failing the download (I2)", async () => {
  const { client, calls } = fake({
    claim_data_export: () => [job({ phase: "media" })],
    export_media_manifest: () => { throw new Error("503"); },
  });
  await runOnce(client, limits);
  assert(calls.some((c) => c.fn === "export_retry_part"));
  assert(!calls.some((c) => c.fn === "fail_data_export"));
});

// Spec 1 W7b (§7.2, review I-10; plan P-18): the one match path. The
// quarantine copy happens before the record call, for both the queued and
// the inline entry point; a copy that keeps failing is recorded as
// unquarantined (held and escalated, the original kept as evidence).
// The copy is the exact bytes the matcher scanned (B4 N2), at a path no
// earlier match used; an object already at a path never counts as this
// match's evidence (PF-M2). Each try is bounded in time, so a hung upload
// still records the match (B5 I-2); the record carries the exact path
// written (B5 I-4); the store writes only to safety-quarantine (B5 M5).
import {
  inlineRecorder,
  type MatchRpcClient,
  newMatchId,
  QUARANTINE_BUCKET,
  quarantineAndRecord,
  quarantineBudget,
  type QuarantineOutcome,
  quarantinePath,
  queuedRecorder,
  type StorageBucketLike,
  type StorageLike,
  storageQuarantine,
} from "./csam_match_path.ts";

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

const enc = new TextEncoder();
const BYTES = enc.encode("evidence");

function sameBytes(a: Uint8Array, b: Uint8Array): boolean {
  return a.length === b.length && a.every((x, i) => x === b[i]);
}

function ids() {
  let n = 0;
  return () => `m${++n}`;
}

function rig(puts: QuarantineOutcome[], rpcData: unknown = 41) {
  const log: string[] = [];
  const sent: Uint8Array[] = [];
  const store = {
    put(path: string, bytes: Uint8Array, mime: string) {
      log.push(`put ${path} ${mime}`);
      sent.push(bytes);
      return Promise.resolve(puts.shift() ?? "failed");
    },
  };
  const client: MatchRpcClient = {
    rpc(fn, args) {
      log.push(`rpc ${fn} ${JSON.stringify(args)}`);
      return Promise.resolve({ data: rpcData, error: null });
    },
  };
  return { log, sent, store, client };
}

// sanitizeOps (B5 N-4): a fast copy leaves no timer behind (putWithin clears it).
Deno.test("queued: the scanned bytes copied to quarantine first, then complete_media_scan(match) with the lease", { sanitizeOps: true }, async () => {
  const r = rig(["stored"]);
  const result = await quarantineAndRecord({
    bucket: "message-media",
    objectName: "rel/1/a.jpg",
    bytes: BYTES,
    mime: "image/jpeg",
    store: r.store,
    record: queuedRecorder(r.client, 7, "photodna", "trk-1", "lease-7"),
    matchId: ids(),
  });
  assert(r.log[0] === "put message-media/rel/1/a.jpg/m1 image/jpeg", r.log.join(" | "));
  assert(sameBytes(r.sent[0], BYTES), "the quarantine copy is the scanned bytes");
  assert(
    r.log[1] ===
      'rpc complete_media_scan {"p_job_id":7,"p_result":"match","p_vendor":"photodna","p_vendor_ref":"trk-1","p_lease_id":"lease-7","p_quarantine_path":"message-media/rel/1/a.jpg/m1"}',
    r.log.join(" | "),
  );
  assert(r.log.length === 2 && result.quarantined && result.recorded, JSON.stringify(result));
  assert(result.quarantinePath === "message-media/rel/1/a.jpg/m1", JSON.stringify(result));
});

Deno.test("inline: copied to quarantine first, then record_inline_csam_match", async () => {
  const r = rig(["stored"], 99);
  const result = await quarantineAndRecord({
    bucket: "dating-profile-photos",
    objectName: "u/1.jpg",
    bytes: BYTES,
    mime: "image/jpeg",
    store: r.store,
    record: inlineRecorder(r.client, {
      bucket: "dating-profile-photos",
      objectName: "u/1.jpg",
      ownerUserId: "5f7b0000-0000-0000-0000-000000000002",
      vendor: "photodna",
      vendorRef: "trk-3",
    }),
    retryDelayMs: 0,
  });
  assert(r.log[0].startsWith("put dating-profile-photos/u/1.jpg/"), r.log.join(" | "));
  assert(r.log[1].startsWith("rpc record_inline_csam_match ") && r.log[1].includes('"p_quarantined":true'), r.log[1]);
  assert(r.log[1].endsWith(`"p_quarantine_path":${JSON.stringify(result.quarantinePath)}}`) && result.quarantinePath !== null, r.log[1]);
  assert(result.escalationId === 99 && result.quarantined, JSON.stringify(result));
});

Deno.test("a copy that keeps failing: three tries, then recorded unquarantined", async () => {
  const q = rig(["failed", "failed", "failed"]);
  const queued = await quarantineAndRecord({
    bucket: "avatars",
    objectName: "u/avatar.jpg",
    bytes: BYTES,
    mime: "image/jpeg",
    store: q.store,
    record: queuedRecorder(q.client, 8, "photodna", "trk-4", "lease-8"),
    retryDelayMs: 0,
  });
  assert(q.log.filter((l) => l.startsWith("put")).length === 3, q.log.join(" | "));
  assert(q.log[3].includes('"p_result":"match_unquarantined"') && q.log[3].includes('"p_quarantine_path":null'), q.log[3]);
  assert(!queued.quarantined && queued.recorded && queued.quarantinePath === null, JSON.stringify(queued));

  const i = rig(["failed", "stored"]);
  const inline = await quarantineAndRecord({
    bucket: "dating-profile-photos",
    objectName: "u/2.jpg",
    bytes: BYTES,
    mime: "image/jpeg",
    store: i.store,
    record: inlineRecorder(i.client, { bucket: "dating-profile-photos", objectName: "u/2.jpg", ownerUserId: null, vendor: "safer", vendorRef: null }),
    matchId: ids(),
    retryDelayMs: 0,
  });
  assert(inline.quarantined && i.log.filter((l) => l.startsWith("put")).length === 2, i.log.join(" | "));
  assert(i.log[2].includes('"p_quarantine_path":"dating-profile-photos/u/2.jpg/m2"'), i.log[2]);
  assert(i.log[0] !== i.log[1] && inline.quarantinePath === "dating-profile-photos/u/2.jpg/m2", i.log.join(" | "));
  assert(i.sent.every((b) => sameBytes(b, BYTES)), "every try sends the scanned bytes");

  const f = rig(["failed", "failed", "failed"], 77);
  const inlineFailed = await quarantineAndRecord({
    bucket: "dating-profile-photos",
    objectName: "u/3.jpg",
    bytes: BYTES,
    mime: "image/jpeg",
    store: f.store,
    record: inlineRecorder(f.client, { bucket: "dating-profile-photos", objectName: "u/3.jpg", ownerUserId: null, vendor: "photodna", vendorRef: "trk-5" }),
    retryDelayMs: 0,
  });
  assert(f.log[3].startsWith("rpc record_inline_csam_match ") && f.log[3].includes('"p_quarantined":false'), f.log.join(" | "));
  assert(f.log[3].includes('"p_quarantine_path":null'), f.log[3]);
  assert(!inlineFailed.quarantined && inlineFailed.recorded && inlineFailed.escalationId === 77, JSON.stringify(inlineFailed));

  // A store that throws is a failed try; tries are bounded (1..5).
  let thrown = 0;
  const throwing = { put: () => (thrown++, Promise.reject(new Error("net"))) };
  const t = rig([]);
  const many = await quarantineAndRecord({
    bucket: "avatars", objectName: "u/x.jpg", bytes: BYTES, mime: "image/jpeg",
    store: throwing, record: queuedRecorder(t.client, 9, "photodna", null, "lease-9"), tries: 50, retryDelayMs: 0,
  });
  assert(thrown === 5 && !many.quarantined && many.recorded, `${thrown} ${JSON.stringify(many)}`);
  thrown = 0;
  await quarantineAndRecord({
    bucket: "avatars", objectName: "u/x.jpg", bytes: BYTES, mime: "image/jpeg",
    store: throwing, record: queuedRecorder(t.client, 9, "photodna", null, "lease-9"), tries: 0, retryDelayMs: 0,
  });
  assert(thrown === 1, `tries 0 still tries once: ${thrown}`);
});

Deno.test("retries back off: try n+1 waits n times the delay", async () => {
  const r = rig(["failed", "failed", "stored"]);
  const started = performance.now();
  const result = await quarantineAndRecord({
    bucket: "avatars", objectName: "u/avatar.jpg", bytes: BYTES, mime: "image/jpeg",
    store: r.store, record: queuedRecorder(r.client, 8, "photodna", "trk-4", "lease-8"), retryDelayMs: 30,
  });
  const waited = performance.now() - started;
  assert(result.quarantined && waited >= 85, `waited ${waited} ms`);
});

Deno.test("an object already at the path is never this match's evidence", async () => {
  const r = rig(["exists", "exists", "exists"]);
  const result = await quarantineAndRecord({
    bucket: "message-media",
    objectName: "rel/1/a.jpg",
    bytes: BYTES,
    mime: "image/jpeg",
    store: r.store,
    record: queuedRecorder(r.client, 7, "photodna", "trk-1", "lease-7"),
    matchId: ids(),
    retryDelayMs: 0,
  });
  const puts = r.log.filter((l) => l.startsWith("put"));
  assert(puts.length === 3 && new Set(puts).size === 3, r.log.join(" | "));
  assert(!result.quarantined && r.log[3].includes('"p_result":"match_unquarantined"'), JSON.stringify(result));

  const e = rig(["exists", "stored"]);
  const fresh = await quarantineAndRecord({
    bucket: "message-media", objectName: "rel/1/a.jpg", bytes: BYTES, mime: "image/jpeg",
    store: e.store, record: queuedRecorder(e.client, 7, "photodna", "trk-1", "lease-7"), matchId: ids(), retryDelayMs: 0,
  });
  assert(fresh.quarantined && fresh.quarantinePath === "message-media/rel/1/a.jpg/m2", JSON.stringify(fresh));
});

Deno.test("PF-M2: a second match of the same object keeps its new bytes beside the first", async () => {
  const objects = new Map<string, Uint8Array>();
  const bucket: StorageBucketLike = {
    upload(path, body) {
      if (objects.has(path)) return Promise.resolve({ error: { message: "The resource already exists", statusCode: "409" } });
      objects.set(path, body);
      return Promise.resolve({ error: null });
    },
  };
  const store = storageQuarantine({ from: () => bucket });
  const first = enc.encode("first upload");
  const second = enc.encode("second upload, after the first escalation closed");
  const r = rig([]);
  const a = await quarantineAndRecord({
    bucket: "message-media", objectName: "rel/1/a.jpg", bytes: first, mime: "image/jpeg",
    store, record: queuedRecorder(r.client, 7, "photodna", "trk-1", "lease-1"),
  });
  const b = await quarantineAndRecord({
    bucket: "message-media", objectName: "rel/1/a.jpg", bytes: second, mime: "image/jpeg",
    store, record: queuedRecorder(r.client, 7, "photodna", "trk-2", "lease-2"),
  });
  assert(a.quarantined && b.quarantined && a.quarantinePath !== b.quarantinePath, JSON.stringify([a, b]));
  assert(sameBytes(objects.get(a.quarantinePath!)!, first) && sameBytes(objects.get(b.quarantinePath!)!, second), "evidence kept");
  assert(a.quarantinePath!.startsWith("message-media/rel/1/a.jpg/") && objects.size === 2, a.quarantinePath!);
});

Deno.test("match ids: unique, sortable by time, storage-safe", () => {
  const at = new Date("2026-11-03T22:10:05.123Z");
  const x = newMatchId(at);
  const y = newMatchId(at);
  assert(x !== y && x.startsWith("20261103T221005123Z-"), `${x} ${y}`);
  assert(/^[0-9A-Za-z-]+$/.test(x), x);
  assert(newMatchId(new Date("2026-11-04T00:00:00Z")) > x, "later sorts after");
  assert(quarantinePath("b", "o/p.jpg", "id") === "b/o/p.jpg/id", "path");
});

Deno.test("the storage quarantine writes only to safety-quarantine, never overwrites, reports exists", async () => {
  const calls: unknown[] = [];
  const buckets: string[] = [];
  const answer = (error: { message: string; statusCode?: string } | null) =>
    storageQuarantine({
      from(id) {
        buckets.push(id);
        return {
          upload(path, body, options) {
            calls.push([path, options]);
            assert(sameBytes(body, BYTES), "uploads the given bytes");
            return Promise.resolve({ error });
          },
        };
      },
    });
  assert(await answer(null).put("b/x.jpg", BYTES, "image/jpeg") === "stored", "stored");
  assert(JSON.stringify(calls[0]) === '["b/x.jpg",{"contentType":"image/jpeg","upsert":false}]', JSON.stringify(calls[0]));
  assert(await answer({ message: "The resource already exists", statusCode: "409" }).put("b/x.jpg", BYTES, "image/jpeg") === "exists", "409");
  assert(await answer({ message: "Internal error", statusCode: "500" }).put("b/x.jpg", BYTES, "image/jpeg") === "failed", "500");
  const throwing = storageQuarantine({ from: () => ({ upload: () => Promise.reject(new Error("net")) }) });
  assert(await throwing.put("b/x.jpg", BYTES, "") === "failed", "thrown");
  assert(buckets.length === 3 && buckets.every((b) => b === QUARANTINE_BUCKET) && QUARANTINE_BUCKET === "safety-quarantine", buckets.join());
  const noBucket: StorageLike = { from: () => { throw new Error("no such bucket"); } };
  assert(await storageQuarantine(noBucket).put("b/x.jpg", BYTES, "image/jpeg") === "failed", "from() throwing");
});

Deno.test("B5 I-2: a hung upload is a failed try; the match is still recorded, unquarantined, in time", async () => {
  const r = rig([]);
  let puts = 0;
  const hung = { put: () => (puts++, new Promise<QuarantineOutcome>(() => {})) };
  const started = performance.now();
  const result = await quarantineAndRecord({
    bucket: "message-media", objectName: "rel/1/a.jpg", bytes: BYTES, mime: "image/jpeg",
    store: hung, record: queuedRecorder(r.client, 7, "photodna", "trk-1", "lease-7"), copyTimeoutMs: 30, retryDelayMs: 0,
  });
  const took = performance.now() - started;
  assert(puts === 3 && !result.quarantined && result.recorded && result.quarantinePath === null, `${puts} ${JSON.stringify(result)}`);
  assert(r.log[0].includes('"p_result":"match_unquarantined"') && took >= 85 && took < 1_000, `${took} ${r.log.join(" | ")}`);

  // A store that throws synchronously is a failed try too.
  const sync = { put: (): Promise<QuarantineOutcome> => { throw new Error("sync"); } };
  const t = rig([]);
  const s = await quarantineAndRecord({
    bucket: "avatars", objectName: "u/x.jpg", bytes: BYTES, mime: "image/jpeg",
    store: sync, record: queuedRecorder(t.client, 9, "photodna", null, "lease-9"), tries: 1,
  });
  assert(!s.quarantined && s.recorded, JSON.stringify(s));
});

Deno.test("B5 I-2: the copy budget is bounded", () => {
  const d = quarantineBudget({});
  assert(d.tries === 3 && d.copyTimeoutMs === 8_000 && d.retryDelayMs === 250 && d.worstCaseMs === 24_750, JSON.stringify(d));
  const big = quarantineBudget({ tries: 99, copyTimeoutMs: 1e9, retryDelayMs: 1e9 });
  assert(big.tries === 5 && big.copyTimeoutMs === 10_000 && big.retryDelayMs === 1_000 && big.worstCaseMs === 60_000, JSON.stringify(big));
  const odd = quarantineBudget({ tries: Number.NaN, copyTimeoutMs: -5, retryDelayMs: -1 });
  assert(odd.tries === 3 && odd.copyTimeoutMs === 1 && odd.retryDelayMs === 0, JSON.stringify(odd));
  const nan = quarantineBudget({ copyTimeoutMs: Number.NaN, retryDelayMs: Number.NaN });
  assert(nan.copyTimeoutMs === 8_000 && nan.retryDelayMs === 250, JSON.stringify(nan));
});

Deno.test("a record call that throws is not recorded, after the copy", async () => {
  const r = rig(["stored"]);
  const client: MatchRpcClient = { rpc: () => Promise.reject(new Error("down")) };
  const result = await quarantineAndRecord({
    bucket: "message-media", objectName: "rel/1/a.jpg", bytes: BYTES, mime: "image/jpeg",
    store: r.store, record: queuedRecorder(client, 7, "photodna", "trk-1", "lease-7"),
  });
  assert(result.quarantined && !result.recorded && result.escalationId === null, JSON.stringify(result));
});

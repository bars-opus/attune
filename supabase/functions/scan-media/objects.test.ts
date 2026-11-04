// Spec 1 W7b (B6 fix I-2, M-11): scan-media's object reader. The kind is
// sniffed from a 4 KiB Range read; the whole object is read only for an
// image under the size cap; every request is aborted when its time is up;
// only "object not found" is a missing object.
import { storageObjectReader } from "./objects.ts";

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

const enc = new TextEncoder();
const URL_BASE = "https://example.supabase.co/";

interface Call {
  url: string;
  headers: Record<string, string>;
  signal: AbortSignal | undefined;
}

function recorder(answer: (call: Call) => Response | Promise<Response>) {
  const calls: Call[] = [];
  const fetchFn = (input: RequestInfo | URL, init?: RequestInit) => {
    const call = { url: String(input), headers: (init?.headers ?? {}) as Record<string, string>, signal: init?.signal ?? undefined };
    calls.push(call);
    return Promise.resolve(answer(call));
  };
  return { calls, fetchFn };
}

/// A body that streams [total] bytes of [fill] in 64 KiB chunks and says when it was cancelled.
function bigBody(total: number, fill = 0x41) {
  let sent = 0;
  const state = { cancelled: false, sent: () => sent };
  const stream = new ReadableStream<Uint8Array>({
    pull(controller) {
      if (sent >= total) return controller.close();
      const n = Math.min(65_536, total - sent);
      sent += n;
      controller.enqueue(new Uint8Array(n).fill(fill));
    },
    cancel() {
      state.cancelled = true;
    },
  });
  return { stream, state };
}

const reader = (fetchFn: ReturnType<typeof recorder>["fetchFn"], o: { headTimeoutMs?: number; readTimeoutMs?: number } = {}) =>
  storageObjectReader({ url: URL_BASE, key: "service-key", fetch: fetchFn, ...o });

// sanitizeOps: each request clears its abort timer.
Deno.test("head: a 4 KiB Range read with the service role; the size from Content-Range", { sanitizeOps: true }, async () => {
  const video = bigBody(4096);
  const r = recorder(() =>
    new Response(video.stream, { status: 206, headers: { "Content-Range": "bytes 0-4095/314572800", "Content-Length": "4096" } })
  );
  const head = await reader(r.fetchFn).head("story-media", "rel 1/clip.mp4");
  assert(head.ok && head.bytes.length === 4096 && head.size === 314_572_800, JSON.stringify(head.ok ? { n: head.bytes.length, s: head.size } : head));
  assert(r.calls.length === 1, `calls ${r.calls.length}`);
  assert(r.calls[0].url === "https://example.supabase.co/storage/v1/object/story-media/rel%201/clip.mp4", r.calls[0].url);
  assert(r.calls[0].headers.Range === "bytes=0-4095", JSON.stringify(r.calls[0].headers));
  assert(r.calls[0].headers.Authorization === "Bearer service-key" && r.calls[0].headers.apikey === "service-key", "service role");
});

Deno.test("head: a server that ignores Range is read only to 4 KiB, then cancelled", async () => {
  const body = bigBody(50 * 1024 * 1024);
  const r = recorder(() => new Response(body.stream, { status: 200, headers: { "Content-Length": String(50 * 1024 * 1024) } }));
  const head = await reader(r.fetchFn).head("message-media", "a.bin");
  assert(head.ok && head.bytes.length === 4096 && head.size === 50 * 1024 * 1024, "head of an ignored range");
  assert(body.state.cancelled && body.state.sent() <= 3 * 65_536, `read ${body.state.sent()} bytes, cancelled ${body.state.cancelled}`);
});

Deno.test("head: a small object comes back whole, with its size", async () => {
  const r = recorder(() => new Response(enc.encode("GIF89a-small"), { status: 206, headers: { "Content-Range": "bytes 0-11/12" } }));
  const head = await reader(r.fetchFn).head("avatars", "u/a.gif");
  assert(head.ok && head.bytes.length === 12 && head.size === 12, "small object");
});

Deno.test("head: a refused Range (416) is read again without one, never assumed empty", async () => {
  let n = 0;
  const r = recorder(() => (++n === 1 ? new Response("", { status: 416 }) : new Response(enc.encode("GIF89a!"), { status: 200 })));
  const head = await reader(r.fetchFn).head("avatars", "u/b.gif");
  assert(head.ok && head.bytes.length === 7 && r.calls.length === 2 && r.calls[1].headers.Range === undefined, JSON.stringify(r.calls));
});

Deno.test("M-11: only an object that is not found is missing; any other error is unavailable", async () => {
  const cases: [Response, string][] = [
    [new Response(JSON.stringify({ statusCode: "404", error: "not_found", message: "Object not found" }), { status: 400 }), "skipped:object_missing"],
    [new Response(JSON.stringify({ statusCode: "404", error: "Not Found", message: "Object not found" }), { status: 404 }), "skipped:object_missing"],
    [new Response(JSON.stringify({ statusCode: "404", error: "Bucket not found", message: "Bucket not found" }), { status: 404 }), "unavailable:download_failed"],
    [new Response("<html>not found</html>", { status: 404 }), "unavailable:download_failed"],
    [new Response(JSON.stringify({ message: "Internal error" }), { status: 500 }), "unavailable:download_failed"],
    [new Response("", { status: 403 }), "unavailable:download_failed"],
  ];
  for (const [response, want] of cases) {
    const r = recorder(() => response);
    const head = await reader(r.fetchFn).head("message-media", "x.jpg");
    const got = head.ok ? "ok" : `${head.outcome}:${head.reason}`;
    assert(got === want, `${response.status} -> ${got}, want ${want}`);
  }
  const thrown = await reader(() => Promise.reject(new TypeError("network"))).head("message-media", "x.jpg");
  assert(!thrown.ok && thrown.reason === "download_failed", "a network error is unavailable");
});

Deno.test("read: the whole object under the cap; over it is too_large without reading the body", async () => {
  const r = recorder(() => new Response(enc.encode("GIF89a whole image"), { status: 200, headers: { "Content-Length": "18" } }));
  const whole = await reader(r.fetchFn).read("message-media", "a.gif", 1024);
  assert(whole.ok && new TextDecoder().decode(whole.bytes) === "GIF89a whole image", "whole");
  assert(r.calls[0].headers.Range === undefined, "no range on the full read");

  const declared = bigBody(40 * 1024 * 1024);
  const big = recorder(() => new Response(declared.stream, { status: 200, headers: { "Content-Length": String(40 * 1024 * 1024) } }));
  const tooBig = await reader(big.fetchFn).read("message-media", "big.jpg", 4 * 1024 * 1024);
  assert(!tooBig.ok && tooBig.outcome === "unavailable" && tooBig.reason === "too_large", JSON.stringify(tooBig));
  assert(declared.state.sent() <= 65_536, `read ${declared.state.sent()} bytes of a declared-too-large body`);

  // No Content-Length: the read stops just past the cap.
  const undeclared = bigBody(40 * 1024 * 1024);
  const sneaky = recorder(() => new Response(undeclared.stream, { status: 200 }));
  const capped = await reader(sneaky.fetchFn).read("message-media", "big.jpg", 4 * 1024 * 1024);
  assert(!capped.ok && capped.reason === "too_large", JSON.stringify(capped));
  assert(undeclared.state.cancelled && undeclared.state.sent() <= 4 * 1024 * 1024 + 3 * 65_536, `read ${undeclared.state.sent()}`);
});

Deno.test("a hung request is aborted when its time is up (head and read)", async () => {
  const signals: AbortSignal[] = [];
  const hanging = (_input: RequestInfo | URL, init?: RequestInit) =>
    new Promise<Response>((_resolve, reject) => {
      signals.push(init!.signal!);
      const guard = setTimeout(() => reject(new Error("never aborted")), 2_000);
      init!.signal!.addEventListener("abort", () => {
        clearTimeout(guard);
        reject(init!.signal!.reason);
      });
    });
  const objects = storageObjectReader({ url: URL_BASE, key: "k", fetch: hanging, headTimeoutMs: 20, readTimeoutMs: 20 });
  const head = await objects.head("message-media", "slow.jpg");
  const read = await objects.read("message-media", "slow.jpg", 1024);
  assert(!head.ok && head.reason === "download_timeout", JSON.stringify(head));
  assert(!read.ok && read.reason === "download_timeout", JSON.stringify(read));
  assert(signals.length === 2 && signals.every((s) => s.aborted), "the signal fired");

  // A body that stalls mid-read is aborted too.
  const stalled = (_input: RequestInfo | URL, init?: RequestInit) => {
    const stream = new ReadableStream<Uint8Array>({
      start(controller) {
        controller.enqueue(enc.encode("GIF89a"));
        init!.signal!.addEventListener("abort", () => controller.error(init!.signal!.reason));
      },
    });
    return Promise.resolve(new Response(stream, { status: 200 }));
  };
  const midway = await storageObjectReader({ url: URL_BASE, key: "k", fetch: stalled, readTimeoutMs: 20 }).read("message-media", "s.gif", 1024);
  assert(!midway.ok && midway.reason === "download_timeout", JSON.stringify(midway));
});

Deno.test("N-1: an unknown size is never taken for the whole object", async () => {
  // A 206 whose total is "*": 4 KiB of something larger, size unknown.
  const partial = bigBody(4096);
  const star = recorder(() => new Response(partial.stream, { status: 206, headers: { "Content-Range": "bytes 0-4095/*" } }));
  const a = await reader(star.fetchFn).head("message-media", "a.jpg");
  assert(a.ok && a.size === null && a.bytes.length === 4096 && a.whole === false, JSON.stringify(a.ok ? { s: a.size, w: a.whole } : a));

  // A 200 (Range ignored) streamed with no Content-Length and more than 4 KiB.
  const streamed = bigBody(1024 * 1024);
  const noLength = recorder(() => new Response(streamed.stream, { status: 200 }));
  const b = await reader(noLength.fetchFn).head("message-media", "b.jpg");
  assert(b.ok && b.size === null && b.bytes.length === 4096 && b.whole === false, JSON.stringify(b.ok ? { s: b.size, w: b.whole } : b));

  // A 206 that says it is all of a 4096-byte object, and a short 200 that ended: whole.
  const exact = recorder(() => new Response(new Uint8Array(4096), { status: 206, headers: { "Content-Range": "bytes 0-4095/4096" } }));
  const c = await reader(exact.fetchFn).head("message-media", "c.jpg");
  assert(c.ok && c.size === 4096 && c.whole === true, JSON.stringify(c.ok ? { s: c.size, w: c.whole } : c));
  const short = recorder(() => new Response(enc.encode("GIF89a tiny"), { status: 200 }));
  const d = await reader(short.fetchFn).head("message-media", "d.gif");
  assert(d.ok && d.size === null && d.whole === true, JSON.stringify(d.ok ? { s: d.size, w: d.whole } : d));

  // A 206 that claims a total larger than what it sent is not whole.
  const lying = recorder(() => new Response(new Uint8Array(100), { status: 206, headers: { "Content-Range": "bytes 0-4095/9000" } }));
  const e = await reader(lying.fetchFn).head("message-media", "e.jpg");
  assert(e.ok && e.size === 9000 && e.whole === false, JSON.stringify(e.ok ? { s: e.size, w: e.whole } : e));
});

import {
  assert,
  assertEquals,
  assertRejects,
} from "https://deno.land/std@0.177.0/testing/asserts.ts";
import {
  type Conn,
  guardedFetch,
  isForbiddenIp,
  PreviewError,
  validateUrl,
} from "./guard.ts";

Deno.test("private, loopback, metadata and special addresses are forbidden", () => {
  for (const ip of [
    "127.0.0.1", "127.255.0.9", "10.1.2.3", "172.16.0.1", "172.31.255.255",
    "192.168.1.1", "169.254.169.254", "100.64.0.1", "100.127.255.254",
    "0.0.0.0", "224.0.0.1", "239.1.1.1", "240.0.0.1", "255.255.255.255",
    "192.0.0.8", "198.18.0.1",
    "::", "::1", "fc00::1", "fd12:3456::1", "fe80::1", "febf::1", "ff02::1",
    "::ffff:127.0.0.1", "::ffff:7f00:1", "::ffff:a9fe:a9fe", "::127.0.0.1",
    "64:ff9b::a9fe:a9fe", "2002:7f00:1::1", "2001:db8::1", "2001::1",
    "fe80::1%en0", "not-an-ip", "",
  ]) {
    assert(isForbiddenIp(ip), `${ip} should be forbidden`);
  }
});

Deno.test("public addresses are allowed", () => {
  for (const ip of [
    "93.184.216.34", "8.8.8.8", "172.32.0.1", "100.128.0.1", "192.169.0.1",
    "2606:4700:4700::1111", "2a00:1450:4001:80b::200e", "::ffff:8.8.8.8",
    "64:ff9b::808:808",
  ]) {
    assert(!isForbiddenIp(ip), `${ip} should be allowed`);
  }
});

Deno.test("only plain http(s) on default ports to public names is accepted", () => {
  for (const raw of [
    "file:///etc/passwd", "javascript:alert(1)", "ftp://example.com/",
    "http://user:pw@example.com/", "http://example.com:8080/",
    "https://example.com:22/", "http://localhost/", "http://foo.localhost/",
    "http://printer.local/", "http://db.internal/", "http://intranet/",
    "http://127.1/", "http://2130706433/", "http://0x7f000001/",
    "http://[::1]/", "http://[::ffff:127.0.0.1]/", "http://169.254.169.254/latest/",
    "not a url",
  ]) {
    let threw = false;
    try { validateUrl(raw); } catch (e) { threw = e instanceof PreviewError; }
    assert(threw, `${raw} should be rejected`);
  }
  assertEquals(validateUrl("https://villa.example/ubud?x=1").hostname, "villa.example");
  assertEquals(validateUrl("http://93.184.216.34/").hostname, "93.184.216.34");
});

// A scripted server: each connect pops the next canned response.
function fakeNet(responses: string[], resolved: Record<string, string[]>) {
  const connects: { ip: string; port: number; tlsHost: string | null; request: string }[] = [];
  const resolves: string[] = [];
  const resolver = (host: string) => {
    resolves.push(host);
    return Promise.resolve(resolved[host] ?? []);
  };
  const connector = (ip: string, port: number, tlsHost: string | null): Promise<Conn> => {
    const body = new TextEncoder().encode(responses.shift() ?? "");
    const record = { ip, port, tlsHost, request: "" };
    connects.push(record);
    let offset = 0;
    return Promise.resolve({
      write(p: Uint8Array) { record.request += new TextDecoder().decode(p); return Promise.resolve(p.length); },
      read(p: Uint8Array) {
        if (offset >= body.length) return Promise.resolve(null);
        const n = Math.min(p.length, body.length - offset, 7); // tiny reads
        p.set(body.subarray(offset, offset + n));
        offset += n;
        return Promise.resolve(n);
      },
      close() {},
    });
  };
  return { connects, resolves, resolver, connector };
}

const ok = (body: string, type = "text/html; charset=utf-8") =>
  `HTTP/1.1 200 OK\r\nContent-Type: ${type}\r\nContent-Length: ${new TextEncoder().encode(body).length}\r\n\r\n${body}`;

Deno.test("connects to the validated IP and sends the original Host and SNI", async () => {
  const net = fakeNet([ok("<title>Hi</title>")], { "villa.example": ["93.184.216.34"] });
  const res = await guardedFetch("https://villa.example/ubud?x=1", { maxBytes: 1024, accept: "html", ...net });
  assertEquals(new TextDecoder().decode(res.body), "<title>Hi</title>");
  assertEquals(net.connects[0].ip, "93.184.216.34");
  assertEquals(net.connects[0].port, 443);
  assertEquals(net.connects[0].tlsHost, "villa.example");
  assert(net.connects[0].request.startsWith("GET /ubud?x=1 HTTP/1.1\r\nHost: villa.example\r\n"));
  assertEquals(net.resolves, ["villa.example"]); // resolved once: no rebinding window
});

Deno.test("a name resolving to any private address is refused before connecting", async () => {
  const net = fakeNet([ok("x")], { "evil.example": ["93.184.216.34", "10.0.0.5"] });
  await assertRejects(() => guardedFetch("http://evil.example/", { maxBytes: 1024, accept: "html", ...net }), PreviewError, "blocked_address");
  assertEquals(net.connects.length, 0);
  const none = fakeNet([], {});
  await assertRejects(() => guardedFetch("http://nx.example/", { maxBytes: 1024, accept: "html", ...none }), PreviewError, "dns_failed");
});

Deno.test("redirects are re-validated, relative ones followed, at most 3", async () => {
  const toMeta = fakeNet(
    ["HTTP/1.1 302 Found\r\nLocation: http://169.254.169.254/latest/meta-data\r\nContent-Length: 0\r\n\r\n"],
    { "a.example": ["93.184.216.34"] },
  );
  await assertRejects(() => guardedFetch("http://a.example/", { maxBytes: 1024, accept: "html", ...toMeta }), PreviewError, "blocked_url");
  assertEquals(toMeta.connects.length, 1);

  const rebind = fakeNet(
    ["HTTP/1.1 301 Moved\r\nLocation: http://b.example/\r\nContent-Length: 0\r\n\r\n"],
    { "a.example": ["93.184.216.34"], "b.example": ["127.0.0.1"] },
  );
  await assertRejects(() => guardedFetch("http://a.example/", { maxBytes: 1024, accept: "html", ...rebind }), PreviewError, "blocked_address");

  const relative = fakeNet(
    ["HTTP/1.1 301 Moved\r\nLocation: /final\r\nContent-Length: 0\r\n\r\n", ok("done")],
    { "a.example": ["93.184.216.34"] },
  );
  const res = await guardedFetch("http://a.example/start", { maxBytes: 1024, accept: "html", ...relative });
  assertEquals(res.url, "http://a.example/final");
  assertEquals(new TextDecoder().decode(res.body), "done");

  const hop = "HTTP/1.1 302 Found\r\nLocation: /next\r\nContent-Length: 0\r\n\r\n";
  const loop = fakeNet([hop, hop, hop, hop, ok("never")], { "a.example": ["93.184.216.34"] });
  await assertRejects(() => guardedFetch("http://a.example/", { maxBytes: 1024, accept: "html", ...loop }), PreviewError, "too_many_redirects");
  assertEquals(loop.connects.length, 4);
});

Deno.test("HTML is truncated at the cap; an oversized image is refused", async () => {
  const big = "a".repeat(5000);
  const page = fakeNet([ok(big)], { "a.example": ["93.184.216.34"] });
  const res = await guardedFetch("http://a.example/", { maxBytes: 1000, accept: "html", ...page });
  assertEquals(res.body.length, 1000);

  const img = fakeNet([ok(big, "image/png")], { "a.example": ["93.184.216.34"] });
  await assertRejects(() => guardedFetch("http://a.example/i.png", { maxBytes: 1000, accept: "image", ...img }), PreviewError, "too_large");
});

Deno.test("the wrong content type is refused", async () => {
  const net = fakeNet([ok("PK..", "application/zip")], { "a.example": ["93.184.216.34"] });
  await assertRejects(() => guardedFetch("http://a.example/", { maxBytes: 1000, accept: "html", ...net }), PreviewError, "wrong_type");
});

Deno.test("chunked bodies are decoded", async () => {
  const net = fakeNet(
    ["HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nTransfer-Encoding: chunked\r\n\r\n5\r\nHello\r\n7\r\n, world\r\n0\r\n\r\n"],
    { "a.example": ["93.184.216.34"] },
  );
  const res = await guardedFetch("http://a.example/", { maxBytes: 1000, accept: "html", ...net });
  assertEquals(new TextDecoder().decode(res.body), "Hello, world");
});

Deno.test("a server that never answers times out", async () => {
  const resolver = () => Promise.resolve(["93.184.216.34"]);
  const connector = (): Promise<Conn> => Promise.resolve({
    write: (p: Uint8Array) => Promise.resolve(p.length),
    read: () => new Promise<number | null>(() => {}),
    close() {},
  });
  const started = Date.now();
  await assertRejects(
    () => guardedFetch("http://a.example/", { maxBytes: 1000, accept: "html", resolver, connector, totalMs: 100, connectMs: 50 }),
    PreviewError, "timeout",
  );
  assert(Date.now() - started < 1000);
  const slowConnect = () => new Promise<Conn>(() => {});
  await assertRejects(
    () => guardedFetch("http://a.example/", { maxBytes: 1000, accept: "html", resolver, connector: slowConnect, totalMs: 500, connectMs: 50 }),
    PreviewError, "timeout",
  );
});

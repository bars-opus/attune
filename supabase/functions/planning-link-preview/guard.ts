// SSRF guard for link previews (spec §7.1). The hostname is resolved once,
// every resolved address must be public, and the connection goes to that
// validated IP with the original Host header and TLS server name -- so a
// DNS answer that changes between "check" and "connect" (rebinding) never
// reaches a private address. Redirects repeat the whole check per hop.

export class PreviewError extends Error {
  constructor(readonly code: string) {
    super(code);
    this.name = "PreviewError";
  }
}

/// The subset of Deno.Conn the HTTP exchange uses (tests script it).
export interface Conn {
  read(p: Uint8Array): Promise<number | null>;
  write(p: Uint8Array): Promise<number>;
  close(): void;
}
export type Resolver = (host: string) => Promise<string[]>;
export type Connector = (ip: string, port: number, tlsHost: string | null) => Promise<Conn>;

export interface FetchOptions {
  maxBytes: number;
  accept: "html" | "image";
  resolver?: Resolver;
  connector?: Connector;
  totalMs?: number;
  connectMs?: number;
  maxRedirects?: number;
}
export interface FetchResult {
  url: string;
  contentType: string;
  body: Uint8Array;
}

// ---- Addresses -------------------------------------------------------------

function parseIpv4(s: string): number[] | null {
  const m = /^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/.exec(s);
  if (!m) return null;
  const parts = m.slice(1).map((p) => (p.length > 1 && p.startsWith("0") ? NaN : Number(p)));
  return parts.every((n) => n >= 0 && n <= 255) ? parts : null;
}

function parseIpv6(input: string): number[] | null {
  if (input.includes("%")) return null; // zone ids are link-local by definition
  let s = input.toLowerCase();
  const lastColon = s.lastIndexOf(":");
  if (lastColon < 0) return null;
  const last = s.slice(lastColon + 1);
  if (last.includes(".")) {
    const v4 = parseIpv4(last);
    if (!v4) return null;
    s = s.slice(0, lastColon + 1) + ((v4[0] << 8) | v4[1]).toString(16) + ":" + ((v4[2] << 8) | v4[3]).toString(16);
  }
  const halves = s.split("::");
  if (halves.length > 2) return null;
  const groups = (p: string) => (p === "" ? [] : p.split(":").map((g) => (/^[0-9a-f]{1,4}$/.test(g) ? parseInt(g, 16) : NaN)));
  const head = groups(halves[0]);
  const tail = halves.length === 2 ? groups(halves[1]) : [];
  if ([...head, ...tail].some(Number.isNaN)) return null;
  if (halves.length === 1) return head.length === 8 ? head : null;
  const fill = 8 - head.length - tail.length;
  if (fill < 1) return null;
  return [...head, ...new Array(fill).fill(0), ...tail];
}

// [network, prefix length]: this-network, RFC1918, CGNAT, loopback,
// link-local (cloud metadata), IETF/TEST-NETs, 6to4 relay, benchmarking,
// multicast, reserved and broadcast.
const V4_BLOCKED: [number[], number][] = [
  [[0, 0, 0, 0], 8], [[10, 0, 0, 0], 8], [[100, 64, 0, 0], 10], [[127, 0, 0, 0], 8],
  [[169, 254, 0, 0], 16], [[172, 16, 0, 0], 12], [[192, 0, 0, 0], 24], [[192, 0, 2, 0], 24],
  [[192, 88, 99, 0], 24], [[192, 168, 0, 0], 16], [[198, 18, 0, 0], 15], [[198, 51, 100, 0], 24],
  [[203, 0, 113, 0], 24], [[224, 0, 0, 0], 4], [[240, 0, 0, 0], 4],
];
const v4Int = (p: number[]) => ((p[0] << 24) >>> 0) + (p[1] << 16) + (p[2] << 8) + p[3];

function v4Forbidden(p: number[]): boolean {
  const ip = v4Int(p);
  return V4_BLOCKED.some(([net, bits]) => {
    const mask = bits === 0 ? 0 : (0xffffffff << (32 - bits)) >>> 0;
    return ((ip & mask) >>> 0) === v4Int(net);
  });
}

function v6Forbidden(g: number[]): boolean {
  const zero = (from: number, to: number) => g.slice(from, to).every((x) => x === 0);
  const embedded = (hi: number, lo: number) => [hi >> 8, hi & 0xff, lo >> 8, lo & 0xff];
  if (zero(0, 5) && g[5] === 0xffff) return v4Forbidden(embedded(g[6], g[7])); // ::ffff:a.b.c.d
  if (zero(0, 6)) return true; // ::, ::1, deprecated ::a.b.c.d
  if (g[0] === 0x64 && g[1] === 0xff9b && zero(2, 6)) return v4Forbidden(embedded(g[6], g[7])); // NAT64
  if (g[0] === 0x2002) return v4Forbidden(embedded(g[1], g[2])); // 6to4
  if ((g[0] & 0xe000) !== 0x2000) return true; // not global unicast: ULA, link-local, multicast, ...
  if (g[0] === 0x2001 && g[1] < 0x0200) return true; // 2001::/23 incl. Teredo
  if (g[0] === 0x2001 && g[1] === 0x0db8) return true; // documentation
  return false;
}

/// True for anything that is not a well-formed public unicast address.
export function isForbiddenIp(ip: string): boolean {
  const v4 = parseIpv4(ip);
  if (v4) return v4Forbidden(v4);
  const v6 = parseIpv6(ip);
  if (v6) return v6Forbidden(v6);
  return true;
}

// ---- URLs ------------------------------------------------------------------

const BLOCKED_SUFFIXES = ["localhost", "local", "internal", "lan", "home.arpa", "intranet"];

/// Accepts only http(s) on the default port, no credentials, and a public
/// address or a dotted public-looking name. WHATWG URL parsing has already
/// normalized numeric hosts (127.1, 2130706433, 0x7f000001 -> 127.0.0.1).
export function validateUrl(raw: string): URL {
  let u: URL;
  try {
    u = new URL(raw);
  } catch {
    throw new PreviewError("blocked_url");
  }
  if (u.protocol !== "http:" && u.protocol !== "https:") throw new PreviewError("blocked_url");
  if (u.username || u.password || u.port !== "") throw new PreviewError("blocked_url");
  const host = u.hostname.toLowerCase().replace(/\.$/, "");
  if (host.startsWith("[")) {
    if (isForbiddenIp(host.slice(1, -1))) throw new PreviewError("blocked_url");
    return u;
  }
  if (parseIpv4(host)) {
    if (isForbiddenIp(host)) throw new PreviewError("blocked_url");
    return u;
  }
  if (!host.includes(".") || BLOCKED_SUFFIXES.some((s) => host === s || host.endsWith(`.${s}`))) {
    throw new PreviewError("blocked_url");
  }
  return u;
}

// ---- Network ---------------------------------------------------------------

export const denoResolver: Resolver = async (host) => {
  const out: string[] = [];
  for (const type of ["A", "AAAA"] as const) {
    try {
      out.push(...(await Deno.resolveDns(host, type)));
    } catch {
      // no records of this type
    }
  }
  return out;
};

export const denoConnector: Connector = async (ip, port, tlsHost) => {
  const conn = await Deno.connect({ hostname: ip, port });
  if (tlsHost === null) return conn;
  // SNI and certificate verification use the original name, not the IP.
  return await Deno.startTls(conn, { hostname: tlsHost });
};

/// Races [p] against the deadline. A late result is handed to [onLate]
/// (to close a connection nobody will use); a late rejection is swallowed.
async function withDeadline<T>(p: Promise<T>, ms: number, onLate?: (v: T) => void): Promise<T> {
  if (ms <= 0) throw new PreviewError("timeout");
  let timedOut = false;
  let timer: ReturnType<typeof setTimeout> | undefined;
  p.then((v) => { if (timedOut) onLate?.(v); }, () => {});
  try {
    return await Promise.race([
      p,
      new Promise<never>((_, reject) => {
        timer = setTimeout(() => { timedOut = true; reject(new PreviewError("timeout")); }, ms);
      }),
    ]);
  } finally {
    clearTimeout(timer);
  }
}

function concat(a: Uint8Array, b: Uint8Array): Uint8Array {
  const out = new Uint8Array(a.length + b.length);
  out.set(a);
  out.set(b, a.length);
  return out;
}

function indexOfSeq(hay: Uint8Array, needle: number[], from = 0): number {
  outer: for (let i = from; i <= hay.length - needle.length; i++) {
    for (let j = 0; j < needle.length; j++) if (hay[i + j] !== needle[j]) continue outer;
    return i;
  }
  return -1;
}

const CRLF = [13, 10];
const HEADER_END = [13, 10, 13, 10];
const MAX_HEADER_BYTES = 16384;

function decodeChunked(raw: Uint8Array): Uint8Array {
  const parts: Uint8Array[] = [];
  let pos = 0;
  while (pos < raw.length) {
    const lineEnd = indexOfSeq(raw, CRLF, pos);
    if (lineEnd < 0) break;
    const size = parseInt(new TextDecoder().decode(raw.subarray(pos, lineEnd)).split(";")[0].trim(), 16);
    if (!Number.isFinite(size) || size < 0) throw new PreviewError("bad_response");
    if (size === 0) break;
    const start = lineEnd + 2;
    parts.push(raw.subarray(start, Math.min(start + size, raw.length))); // a cut-off last chunk is kept
    pos = start + size + 2;
  }
  return parts.reduce(concat, new Uint8Array());
}

interface RawResponse {
  status: number;
  headers: Map<string, string>;
  body: Uint8Array;
}

async function exchange(conn: Conn, u: URL, opts: FetchOptions, deadline: number): Promise<RawResponse> {
  const request =
    `GET ${u.pathname}${u.search} HTTP/1.1\r\nHost: ${u.host}\r\nUser-Agent: AttuneLinkPreview/1.0\r\n` +
    `Accept: ${opts.accept === "html" ? "text/html,application/xhtml+xml" : "image/jpeg,image/png,image/gif,image/webp"}\r\n` +
    `Accept-Encoding: identity\r\nConnection: close\r\n\r\n`;
  await withDeadline(conn.write(new TextEncoder().encode(request)), deadline - Date.now());

  let buf: Uint8Array = new Uint8Array();
  const chunk = new Uint8Array(16384);
  const readMore = async (): Promise<boolean> => {
    const n = await withDeadline(conn.read(chunk), deadline - Date.now());
    if (n === null) return false;
    buf = concat(buf, chunk.subarray(0, n));
    return true;
  };

  let headerEnd = -1;
  while ((headerEnd = indexOfSeq(buf, HEADER_END)) < 0) {
    if (buf.length > MAX_HEADER_BYTES || !(await readMore())) throw new PreviewError("bad_response");
  }
  const lines = new TextDecoder().decode(buf.subarray(0, headerEnd)).split("\r\n");
  const status = Number(/^HTTP\/1\.[01] (\d{3})/.exec(lines[0])?.[1]);
  if (!status) throw new PreviewError("bad_response");
  const headers = new Map<string, string>();
  for (const line of lines.slice(1)) {
    const i = line.indexOf(":");
    if (i > 0) headers.set(line.slice(0, i).trim().toLowerCase(), line.slice(i + 1).trim());
  }
  if (status >= 300 && status < 400) return { status, headers, body: new Uint8Array() };
  if (status !== 200) throw new PreviewError("bad_response");

  const type = (headers.get("content-type") ?? "").toLowerCase();
  const typeOk = opts.accept === "html"
    ? /^(text\/html|application\/xhtml\+xml)/.test(type)
    : /^image\/(jpeg|png|gif|webp)/.test(type);
  if (!typeOk) throw new PreviewError("wrong_type");

  const chunked = /chunked/i.test(headers.get("transfer-encoding") ?? "");
  const declared = Number(headers.get("content-length") ?? NaN);
  if (!chunked && opts.accept === "image" && declared > opts.maxBytes) throw new PreviewError("too_large");
  // Read one byte past the cap (plus framing slack when chunked) so an
  // overflow is detectable, then stop: nothing past that is ever read.
  const rawCap = opts.maxBytes + 1 + (chunked ? 65536 : 0);
  let body = buf.subarray(headerEnd + 4);
  while (body.length < rawCap && (Number.isNaN(declared) || chunked || body.length < declared)) {
    const before = buf.length;
    if (!(await readMore())) break;
    body = buf.subarray(headerEnd + 4);
    if (buf.length === before) break;
  }
  let decoded = chunked ? decodeChunked(body) : body.subarray(0, Number.isNaN(declared) ? body.length : declared);
  if (decoded.length > opts.maxBytes) {
    if (opts.accept === "image") throw new PreviewError("too_large");
    decoded = decoded.subarray(0, opts.maxBytes);
  }
  return { status, headers, body: decoded };
}

async function resolvePublic(host: string, resolver: Resolver, ms: number): Promise<string> {
  const addrs = await withDeadline(resolver(host), ms);
  if (addrs.length === 0) throw new PreviewError("dns_failed");
  // Every answer must be public: a mixed answer is how rebinding starts.
  if (addrs.some(isForbiddenIp)) throw new PreviewError("blocked_address");
  return addrs.find((a) => a.includes(".")) ?? addrs[0];
}

export async function guardedFetch(raw: string, opts: FetchOptions): Promise<FetchResult> {
  const resolver = opts.resolver ?? denoResolver;
  const connector = opts.connector ?? denoConnector;
  const deadline = Date.now() + (opts.totalMs ?? 3000);
  const connectMs = opts.connectMs ?? 1000;
  const maxRedirects = opts.maxRedirects ?? 3;
  let current = raw;

  for (let hop = 0; ; hop++) {
    const u = validateUrl(current);
    const host = u.hostname.replace(/^\[|\]$/g, "");
    const literal = parseIpv4(host) !== null || host.includes(":");
    const ip = literal ? host : await resolvePublic(host, resolver, deadline - Date.now());
    const tls = u.protocol === "https:";
    const conn = await withDeadline(
      connector(ip, tls ? 443 : 80, tls ? host : null),
      Math.min(connectMs, deadline - Date.now()),
      (late) => late.close(),
    );
    let res: RawResponse;
    try {
      res = await exchange(conn, u, opts, deadline);
    } finally {
      conn.close();
    }
    if (res.status >= 300 && res.status < 400) {
      const location = res.headers.get("location");
      if (!location) throw new PreviewError("bad_response");
      if (hop >= maxRedirects) throw new PreviewError("too_many_redirects");
      try {
        current = new URL(location, u).toString();
      } catch {
        throw new PreviewError("blocked_url");
      }
      continue;
    }
    return { url: u.toString(), contentType: res.headers.get("content-type") ?? "", body: res.body };
  }
}

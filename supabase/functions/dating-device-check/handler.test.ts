// Spec 2 W8b (§2.3, §4.7, §7.3; R-71..R-76): dating-device-check. The IP
// becomes a country in the request and is never stored, logged, passed on
// or answered; the network country is two upper-case letters or nothing;
// a phone with no install id is device_unavailable; refusals are fixed
// codes, a server error or a slow call busy; the answer carries only
// trusted, away and the place's country for the note. The IP table: ranges
// from DB-IP's CSV, merged, gaps and the space outside answer null, IPv6
// by its top 64 bits; no table or a bad one answers null for every IP.
import { type Caller, type DeviceCheckDeps, handleDeviceCheck, RPC_TIMEOUT_MS } from "./handler.ts";
import { handleRequest } from "./request.ts";
import { checksum, HEADER, loadResolver, NO_RESOLVER, parseIpv6, RangeTable, tableOnce } from "./ip_country.ts";
import { type BuildStats, buildTable } from "./ip_table_build.ts";
import { HttpError } from "../_shared/attune_auth.ts";
import { deviceHashOf as verificationHash } from "../dating-verification/handler.ts";
import { deviceHashOf } from "../dating-photo-urls/handler.ts";

function eq(actual: unknown, expected: unknown, why = "") {
  const a = JSON.stringify(actual), e = JSON.stringify(expected);
  if (a !== e) throw new Error(`${why} expected ${e}, got ${a}`);
}

const USER = "99999999-2222-4333-8444-555555555555";
const HASH = "a".repeat(64);
const CALLER: Caller = { userId: USER, deviceHash: HASH, ipCountry: "AE" };
const never = <T>() => new Promise<T>(() => {});

interface Opts {
  error?: boolean;
  rejects?: boolean;
  hangs?: boolean;
}

function deps(data: unknown, seen: Array<[string, Record<string, unknown>]>, opts: Opts = {}): DeviceCheckDeps {
  return {
    rpc: (fn, args) => {
      seen.push([fn, args]);
      if (opts.rejects) return Promise.reject(new Error("server text: connection reset"));
      if (opts.hangs) return never();
      return Promise.resolve({ data: opts.error ? null : data, error: opts.error ? { message: "server text" } : null });
    },
    rpcTimeoutMs: 20,
  };
}

const OK = { ok: true, trusted: true, away: true, here: "AE" };

Deno.test("the check: the caller's id, the phone's hash, the IP and network countries; the answer's three fields", async () => {
  const seen: Array<[string, Record<string, unknown>]> = [];
  const a = await handleDeviceCheck({ network_country: "AE", p_user: "someone-else" }, CALLER, deps(OK, seen));
  eq(a, { ok: true, trusted: true, away: true, note: { country: "AE" } });
  eq(seen, [["record_dating_device_check", { p_user: USER, p_device_hash: HASH, p_ip_country: "AE", p_network_country: "AE" }]]);
  const b = await handleDeviceCheck({}, { ...CALLER, ipCountry: null }, deps({ ok: true, trusted: false, away: false, here: null }, seen));
  eq(b, { ok: true, trusted: false, away: false, note: null });
  eq(seen[1][1].p_ip_country, null);
  eq(seen[1][1].p_network_country, null);
  // A same-gender trip: the phone is trusted, Dating isn't hidden, the
  // note names the place.
  const c = await handleDeviceCheck({}, CALLER, deps({ ok: true, trusted: true, away: false, here: "GH" }, seen));
  eq(c, { ok: true, trusted: true, away: false, note: { country: "GH" } });
});

Deno.test("a bad network country is invalid and calls nothing; a bad IP country is no country", async () => {
  for (const bad of ["ae", "AEE", 7, "A1", "", {}]) {
    const seen: Array<[string, Record<string, unknown>]> = [];
    eq(await handleDeviceCheck({ network_country: bad }, CALLER, deps(OK, seen)), { ok: false, reason: "invalid" }, String(bad));
    eq(seen.length, 0);
  }
  const seen: Array<[string, Record<string, unknown>]> = [];
  await handleDeviceCheck({}, { ...CALLER, ipCountry: "1.2.3.4" }, deps(OK, seen));
  eq(seen[0][1].p_ip_country, null);
});

Deno.test("no install id: device_unavailable, nothing called", async () => {
  const seen: Array<[string, Record<string, unknown>]> = [];
  eq(await handleDeviceCheck({}, { ...CALLER, deviceHash: null }, deps(OK, seen)), { ok: false, reason: "device_unavailable" });
  eq(seen.length, 0);
});

Deno.test("refusals are fixed codes; errors, rejections and slow calls are busy; a bad place is no note", async () => {
  const seen: Array<[string, Record<string, unknown>]> = [];
  eq(await handleDeviceCheck({}, CALLER, deps({ ok: false, reason: "invalid" }, seen)), { ok: false, reason: "invalid" });
  eq(await handleDeviceCheck({}, CALLER, deps({ ok: false, reason: "unavailable" }, seen)), { ok: false, reason: "unavailable" });
  eq(await handleDeviceCheck({}, CALLER, deps({ ok: false, reason: "server text" }, seen)), { ok: false, reason: "busy" });
  eq(await handleDeviceCheck({}, CALLER, deps(OK, seen, { error: true })), { ok: false, reason: "busy" });
  eq(await handleDeviceCheck({}, CALLER, deps(OK, seen, { rejects: true })), { ok: false, reason: "busy" });
  eq(await handleDeviceCheck({}, CALLER, deps(OK, seen, { hangs: true })), { ok: false, reason: "busy" });
  eq(await handleDeviceCheck({}, CALLER, deps("text", seen)), { ok: false, reason: "busy" });
  eq(await handleDeviceCheck({}, CALLER, deps({ ...OK, here: "Abu Dhabi" }, seen)), { ok: true, trusted: true, away: true, note: null });
  eq(RPC_TIMEOUT_MS, 5000);
});

// Task 4 (record_dating_device_check): with an unresolved IP, "here" is the
// phone's country and no code comes back, so Dating can be hidden with no
// place to name. The note is then null: never the request's IP country,
// never a guess.
Deno.test("away with no place: hidden, and no note", async () => {
  const seen: Array<[string, Record<string, unknown>]> = [];
  const away = { ok: true, trusted: true, away: true, here: null };
  eq(await handleDeviceCheck({ network_country: "AE" }, CALLER, deps(away, seen)), { ok: true, trusted: true, away: true, note: null });
  eq(await handleDeviceCheck({}, { ...CALLER, ipCountry: null }, deps(away, seen)), { ok: true, trusted: true, away: true, note: null });
  eq(await handleDeviceCheck({}, CALLER, deps({ ok: true, trusted: false, away: true }, seen)), { ok: true, trusted: false, away: true, note: null });
});

const CSV = [
  "1.0.0.0,1.0.0.255,AU",
  "1.0.1.0,1.0.3.255,CN",
  "1.0.4.0,1.0.7.255,CN",
  "5.0.0.0,5.0.0.255,AE",
  '"41.66.0.0","41.66.255.255","GH"',
  "255.255.255.0,255.255.255.255,ZZX",
  "2001:db8::,2001:db8:ffff:ffff:ffff:ffff:ffff:ffff,GB",
  "2c0f:f000::,2c0f:f0ff:ffff:ffff:ffff:ffff:ffff:ffff,GH",
  "not,a,row",
].join("\n");

Deno.test("the table: ranges, merges, gaps and the space outside; IPv6 by its top 64 bits", () => {
  const t = new RangeTable(buildTable(CSV));
  eq(t.country("1.0.0.0"), "AU");
  eq(t.country("1.0.0.255"), "AU");
  eq(t.country("1.0.2.9"), "CN");
  eq(t.country("1.0.7.255"), "CN");
  eq(t.country("1.0.8.0"), null);
  eq(t.country("0.255.255.255"), null);
  eq(t.country("5.0.0.7"), "AE");
  eq(t.country("41.66.12.1"), "GH");
  eq(t.country("41.67.0.0"), null);
  eq(t.country("255.255.255.9"), null);
  eq(t.country("2001:db8::1"), "GB");
  eq(t.country("2001:DB8:0:0:1::"), "GB");
  eq(t.country("2001:db9::"), null);
  eq(t.country("2c0f:f012:3::4"), "GH");
  eq(t.country("::1"), null);
  eq(t.country("not an address"), null);
  eq(t.country("1.2.3.256"), null);
  // Fix round 1 (M-7): a leading zero is not an address.
  eq(t.country("1.0.0.05"), null);
  eq(t.country("01.0.0.5"), null);
  // CN's two adjacent ranges are one: 1.0.0.0 (AU), 1.0.1.0 (CN), 1.0.8.0
  // (gap), 5.0.0.0 (AE), 5.0.1.0 (gap), 41.66.0.0 (GH), 41.67.0.0 (gap).
  const bytes = buildTable(CSV);
  const view = new DataView(bytes.buffer);
  eq([view.getUint32(9), view.getUint32(13)], [7, 4]);
  eq(parseIpv6("::ffff:1.2.3.4"), null);
  eq(parseIpv6("1::2::3"), null);
});

function isNone(r: unknown, why: string) {
  if (r !== NO_RESOLVER) throw new Error(`${why}: a resolver was loaded`);
}

// Every console method, captured; restored after.
async function logsOf<T>(f: () => Promise<T>): Promise<[T, unknown[][]]> {
  const logged: unknown[][] = [];
  const c = console as unknown as Record<string, (...a: unknown[]) => void>;
  const names = ["log", "info", "debug", "warn", "error"];
  const real = names.map((n) => c[n]);
  for (const n of names) c[n] = (...a: unknown[]) => logged.push(a);
  try {
    return [await f(), logged];
  } finally {
    names.forEach((n, i) => (c[n] = real[i]));
  }
}

const UNAVAILABLE = [["dating-device-check:", "ip_table_unavailable"]];
const STALE = [["dating-device-check:", "ip_table_stale"]];
const DAY = 86_400_000;
const BUILT = new Date(Date.UTC(2026, 0, 1));

// Fix round 1 (M-1..M-3, M-6, M-7): DB-IP's ZZ is no country; an overlap of
// one country is one range and keeps its tail; a span two countries claim
// (here a /64 split below 64 bits) is no country, never the first one's;
// an IPv4-mapped IPv6 address is its IPv4.
const CSV2 = [
  "10.0.0.0,10.0.0.255,ZZ",
  "20.0.0.0,20.0.0.255,FR",
  "20.0.0.128,20.0.1.255,FR",
  "30.0.0.0,30.0.0.255,DE",
  "30.0.0.200,30.0.1.255,NL",
  "40.0.0.0,40.0.0.255,IT",
  "40.0.0.0,40.0.0.255,IT",
  "2a00:1::,2a00:1::7fff:ffff:ffff:ffff,GB",
  "2a00:1::8000:0:0:0,2a00:1:0:5:ffff:ffff:ffff:ffff,FR",
].join("\n");

Deno.test("the table: ZZ, overlaps, a shared /64 and IPv4-mapped addresses", () => {
  const stats: BuildStats = { conflicts: 0 };
  const bytes = buildTable(CSV2, BUILT, stats);
  const t = new RangeTable(bytes);
  eq(t.country("10.0.0.5"), null, "ZZ");
  eq(t.country("20.0.0.200"), "FR");
  eq(t.country("20.0.1.200"), "FR", "the overlap's tail");
  eq(t.country("20.0.2.0"), null);
  eq(t.country("30.0.0.100"), "DE");
  eq(t.country("30.0.0.220"), null, "two countries");
  eq(t.country("30.0.1.5"), "NL");
  eq(t.country("40.0.0.9"), "IT");
  eq(t.country("40.0.1.0"), null);
  eq(t.country("2a00:1::1"), null, "a /64 two countries share");
  eq(t.country("2a00:1::8000:0:0:1"), null, "a /64 two countries share");
  eq(t.country("2a00:1:0:1::"), "FR");
  eq(t.country("2a00:1:0:5:ffff::"), "FR");
  eq(t.country("2a00:1:0:6::"), null);
  eq(t.country("::ffff:20.0.0.9"), "FR");
  eq(t.country("::FFFF:30.0.1.5"), "NL");
  eq(t.country("::ffff:10.0.0.5"), null);
  eq(t.country("::ffff:20.0.0.09"), null);
  eq(t.country("::ffff:1.2.3"), null);
  const view = new DataView(bytes.buffer);
  eq([view.getUint32(5), view.getUint32(9), view.getUint32(13)], [BUILT.getTime() / DAY, 8, 2]);
  eq(stats, { conflicts: 2 });
  eq(HEADER, 17);
});

Deno.test("no table, or a bad one, resolves nothing and says so once, by code", async () => {
  const x = new URL("file:///x");
  const from = (b: Uint8Array) => () => Promise.resolve(b);
  const [missing, l1] = await logsOf(() => loadResolver(new URL("./no-such-table.bin", import.meta.url)));
  isNone(missing, "no file");
  eq(missing.country("5.0.0.7"), null);
  eq(l1, UNAVAILABLE, "no file");
  const bads: Array<[string, Uint8Array]> = [];
  bads.push(["a header only", new Uint8Array([0x41, 0x49, 0x50, 0x43, 2, 0, 0])]);
  bads.push(["one byte short", buildTable(CSV).slice(0, -1)]);
  const v3 = buildTable(CSV);
  v3[4] = 3;
  bads.push(["another version", v3]);
  const flipped = buildTable(CSV);
  flipped[HEADER + 3] ^= 1;
  bads.push(["a flipped body byte", flipped]);
  const country = buildTable(CSV);
  country[country.length - 8] = 0x55; // the last IPv6 "GH" -> "UH": still letters
  bads.push(["a changed country", country]);
  // Starts out of order, with the checksum made to match: refused anyway.
  for (const [name, at, width] of [["IPv4 order", HEADER, 4], ["IPv6 order", HEADER + 7 * 6, 8]] as const) {
    const swapped = buildTable(CSV);
    const a = swapped.slice(at, at + width), b = swapped.slice(at + width, at + 2 * width);
    swapped.set(b, at);
    swapped.set(a, at + width);
    new DataView(swapped.buffer).setUint32(swapped.length - 4, checksum(swapped.subarray(0, swapped.length - 4)));
    bads.push([name, swapped]);
  }
  // Four bytes more than the header's counts, the checksum made to match.
  const whole = buildTable(CSV);
  const padded = new Uint8Array(whole.length + 4);
  padded.set(whole.subarray(0, whole.length - 4));
  new DataView(padded.buffer).setUint32(padded.length - 4, checksum(padded.subarray(0, padded.length - 4)));
  bads.push(["a padded body", padded]);
  for (const [why, bytes] of bads) {
    const [r, logged] = await logsOf(() => loadResolver(x, from(bytes)));
    isNone(r, why);
    eq(logged, UNAVAILABLE, why);
  }
  const [good, l2] = await logsOf(() => loadResolver(x, from(buildTable(CSV))));
  eq(good.country("41.66.0.1"), "GH");
  eq(l2, [], "a good table");
  // A table over 60 days old is still used, and says so once.
  const old = buildTable(CSV, BUILT);
  const [day60, l3] = await logsOf(() => loadResolver(x, from(old), BUILT.getTime() + 60 * DAY));
  eq([day60.country("41.66.0.1"), l3], ["GH", []], "60 days");
  const [day61, l4] = await logsOf(() => loadResolver(x, from(old), BUILT.getTime() + 61 * DAY));
  eq([day61.country("41.66.0.1"), l4], ["GH", STALE], "61 days");
  // Read once per instance: three calls, one read, one log line.
  let reads = 0;
  const once = tableOnce(new URL("file:///secret/path/ip_country.bin"), () => (reads++, Promise.reject(new Error("ENOENT /secret/path"))));
  const [, l5] = await logsOf(async () => {
    for (let i = 0; i < 3; i++) isNone(await once(), "once");
  });
  eq([reads, l5], [1, UNAVAILABLE]);
});

Deno.test("the request: the address becomes a country and goes no further; no-store; fixed refusals", async () => {
  const logged: unknown[][] = [];
  const realError = console.error, realLog = console.log, realWarn = console.warn;
  const realInfo = console.info, realDebug = console.debug;
  console.error = (...a: unknown[]) => logged.push(a);
  console.log = (...a: unknown[]) => logged.push(a);
  console.warn = (...a: unknown[]) => logged.push(a);
  console.info = (...a: unknown[]) => logged.push(a);
  console.debug = (...a: unknown[]) => logged.push(a);
  try {
    const calls: Array<[string, Record<string, unknown>]> = [];
    const looked: string[] = [];
    const wiring = {
      requireUser: (_: Request) => Promise.resolve({ id: USER }),
      client: () => ({
        rpc: (fn: string, args: Record<string, unknown>) => {
          calls.push([fn, args]);
          return Promise.resolve({ data: OK, error: null });
        },
      }),
      resolver: () => Promise.resolve({ country: (ip: string) => (looked.push(ip), "AE") }),
    };
    const id = "0123456789abcdef0123456789abcdef";
    const res = await handleRequest(new Request("https://fn.test/dating-device-check", {
      method: "POST",
      headers: { "cf-connecting-ip": "5.0.0.7", "x-forwarded-for": "9.9.9.9", "x-attune-device": id },
      body: JSON.stringify({ network_country: "AE" }),
    }), wiring);
    eq(res.headers.get("Cache-Control"), "no-store");
    const text = await res.text();
    eq(JSON.parse(text), { ok: true, trusted: true, away: true, note: { country: "AE" } });
    eq(looked, ["5.0.0.7"]);
    eq(calls[0][1].p_device_hash, await deviceHashOf(id));
    for (const where of [text, JSON.stringify(calls), JSON.stringify(logged)]) {
      if (where.includes("5.0.0.7") || where.includes("9.9.9.9")) throw new Error(`the address leaked: ${where}`);
    }
    // No address the front door gave: no lookup, no country.
    looked.length = 0;
    await handleRequest(new Request("https://fn.test/", { method: "POST", headers: { "x-attune-device": id }, body: "{}" }), wiring);
    eq(looked, []);
    eq(calls[1][1].p_ip_country, null);
    // A resolver that throws is no country, never an error.
    const broken = { ...wiring, resolver: () => Promise.reject(new Error("table")) };
    const r2 = await handleRequest(new Request("https://fn.test/", {
      method: "POST",
      headers: { "cf-connecting-ip": "5.0.0.7", "x-attune-device": id },
      body: "{}",
    }), broken);
    eq(r2.status, 200);
    eq(calls[2][1].p_ip_country, null);
    const denied = await handleRequest(new Request("https://fn.test/", { method: "POST", body: "{}" }), {
      ...wiring,
      requireUser: () => Promise.reject(new HttpError("unauthorized", 401)),
    });
    eq([denied.status, await denied.json()], [401, { ok: false, reason: "unauthorized" }]);
    eq((await handleRequest(new Request("https://fn.test/", { method: "GET" }), wiring)).status, 405);
    eq((await handleRequest(new Request("https://fn.test/", { method: "OPTIONS" }), wiring)).status, 200);
    const failing = await handleRequest(new Request("https://fn.test/", {
      method: "POST",
      headers: { "cf-connecting-ip": "5.0.0.7", "x-attune-device": id },
      body: "{}",
    }), { ...wiring, client: () => { throw new Error("5.0.0.7 server text"); } });
    eq([failing.status, await failing.json()], [500, { ok: false, reason: "busy" }]);
    if (JSON.stringify(logged).includes("5.0.0.7")) throw new Error("an error's text was logged");
    // Fix round 1 (I-2): only the front door's own header is a place. A
    // forwarded hop alone, or a cf-connecting-ip that isn't an address, is
    // no lookup and no country; an IPv4-mapped one is looked up.
    looked.length = 0;
    const before = calls.length;
    const fronts: Array<Record<string, string>> = [
      { "x-forwarded-for": "9.9.9.9", "x-attune-device": id },
      { "cf-connecting-ip": "5.0.0.7, 9.9.9.9", "x-forwarded-for": "9.9.9.9", "x-attune-device": id },
      { "cf-connecting-ip": "unknown", "x-forwarded-for": "9.9.9.9", "x-attune-device": id },
      { "cf-connecting-ip": "05.0.0.7", "x-attune-device": id },
    ];
    for (const headers of fronts) {
      const r = await handleRequest(new Request("https://fn.test/", { method: "POST", headers, body: "{}" }), wiring);
      eq(r.status, 200);
    }
    eq(looked, []);
    eq(calls.slice(before).map((c) => c[1].p_ip_country), [null, null, null, null]);
    await handleRequest(new Request("https://fn.test/", {
      method: "POST",
      headers: { "cf-connecting-ip": " ::FFFF:5.0.0.7 ", "x-attune-device": id },
      body: "{}",
    }), wiring);
    eq(looked, ["::ffff:5.0.0.7"]);
    eq(calls.at(-1)![1].p_ip_country, "AE");
    eq(logged, [["dating-device-check failed:", "none"]], "only the one error's code");
  } finally {
    console.error = realError;
    console.log = realLog;
    console.warn = realWarn;
    console.info = realInfo;
    console.debug = realDebug;
  }
});

Deno.test("the phone's hash is dating-verification's", async () => {
  const id = "0123456789abcdef0123456789abcdef";
  eq(await deviceHashOf(id), await verificationHash(id));
});

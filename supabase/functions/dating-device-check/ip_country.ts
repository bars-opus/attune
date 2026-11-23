// supabase/functions/dating-device-check/ip_country.ts
// Spec 2 W8b (§2.3; R-74): the IP country, behind the IpCountryResolver
// seam. The table is DB-IP's IP to Country Lite (CC BY 4.0, refreshed
// monthly), built into a compact file at deploy time
// (scripts/ip_country/build_ip_country.ts) and shipped as this function's
// static file, never committed. An address is only ever looked up here, in
// memory: never stored, logged or sent. No table, an unreadable one, or an
// address it doesn't cover answers null, and the database then uses the
// phone and network countries (§2.3: as for a VPN).
//
// The file ("AIPC", version 2): magic(4) version(1) built(u32 BE, days since
// 1970-01-01 UTC) n4(u32 BE) n6(u32 BE), then n4 IPv4 range starts (u32 BE)
// and their n4 countries (2 ASCII bytes; "--" is no country), then n6 IPv6
// range starts as their top 64 bits (u64 BE) and their n6 countries, then an
// FNV-1a 32-bit checksum (u32 BE) of everything before it. Starts strictly
// ascend; a range runs to the next start.
//
// Fix round 1: a table that can't be used is logged once, by the fixed code
// ip_table_unavailable (I-1); a body that is corrupt or out of order is
// refused (M-4); a table over STALE_DAYS old is still used and logged once
// as ip_table_stale (M-5); an IPv4-mapped IPv6 address is its IPv4 (M-6).
// Never the path, the URL or an error's text.

export interface IpCountryResolver {
  /// Upper-case ISO 3166-1 alpha-2, or null.
  country(ip: string): string | null;
}

export const NO_RESOLVER: IpCountryResolver = { country: () => null };

const MAGIC = [0x41, 0x49, 0x50, 0x43]; // "AIPC"
export const TABLE_VERSION = 2;
/// magic, version, built, n4, n6.
export const HEADER = 17;
export const STALE_DAYS = 60;
const DAY_MS = 86_400_000;
const IPV4 = /^(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}$/;
const MAPPED = /^::ffff:([0-9.]+)$/;

export function parseIpv4(ip: string): number | null {
  if (!IPV4.test(ip)) return null;
  return ip.split(".").reduce((n, part) => n * 256 + Number(part), 0);
}

/// The top 64 bits of an IPv6 address (enough for every allocation the
/// table holds), or null. An IPv4-mapped address is not IPv6 here.
export function parseIpv6(ip: string): bigint | null {
  const s = ip.trim().toLowerCase();
  if (!s.includes(":") || !/^[0-9a-f:.]+$/.test(s) || s.split("::").length > 2) return null;
  const [head, tail] = s.includes("::") ? s.split("::") : [s, undefined];
  const groups = (part: string | undefined) => (part === undefined || part === "" ? [] : part.split(":"));
  const left = groups(head);
  const right = groups(tail);
  let words: string[];
  if (tail === undefined) {
    words = left;
  } else {
    const fill = 8 - left.length - right.length;
    if (fill < 1) return null;
    words = [...left, ...Array(fill).fill("0"), ...right];
  }
  if (words.length !== 8 || words.some((w) => !/^[0-9a-f]{1,4}$/.test(w))) return null;
  let top = 0n;
  for (const w of words.slice(0, 4)) top = (top << 16n) | BigInt(parseInt(w, 16));
  return top;
}

/// "::ffff:a.b.c.d" (lower-cased) as its IPv4 number, or null.
function mappedIpv4(s: string): number | null {
  const m = MAPPED.exec(s);
  return m ? parseIpv4(m[1]) : null;
}

/// An address this function looks up: IPv4, IPv6 or IPv4-mapped IPv6.
export function isIpLiteral(ip: string): boolean {
  const s = ip.trim().toLowerCase();
  return parseIpv4(s) !== null || parseIpv6(s) !== null || mappedIpv4(s) !== null;
}

/// FNV-1a, 32 bits: the table's last four bytes, over all before them.
export function checksum(bytes: Uint8Array): number {
  let h = 0x811c9dc5;
  for (let i = 0; i < bytes.length; i++) h = Math.imul(h ^ bytes[i], 0x01000193);
  return h >>> 0;
}

function countryAt(bytes: Uint8Array, at: number): string | null {
  const code = String.fromCharCode(bytes[at], bytes[at + 1]);
  return /^[A-Z]{2}$/.test(code) ? code : null;
}

export class RangeTable implements IpCountryResolver {
  readonly #bytes: Uint8Array;
  readonly #view: DataView;
  readonly #n4: number;
  readonly #n6: number;
  /// The day the table was built (days since 1970-01-01, UTC).
  readonly builtDay: number;

  /// Throws on a file that isn't a whole, intact version-2 table.
  constructor(bytes: Uint8Array) {
    if (bytes.length < HEADER + 4 || MAGIC.some((m, i) => bytes[i] !== m) || bytes[4] !== TABLE_VERSION) {
      throw new Error("ip_table_invalid");
    }
    this.#bytes = bytes;
    const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
    this.#view = view;
    this.builtDay = view.getUint32(5);
    this.#n4 = view.getUint32(9);
    this.#n6 = view.getUint32(13);
    if (bytes.length !== HEADER + this.#n4 * 6 + this.#n6 * 10 + 4) throw new Error("ip_table_invalid");
    if (checksum(bytes.subarray(0, bytes.length - 4)) !== view.getUint32(bytes.length - 4)) throw new Error("ip_table_invalid");
    for (let k = 1; k < this.#n4; k++) {
      if (view.getUint32(HEADER + k * 4) <= view.getUint32(HEADER + (k - 1) * 4)) throw new Error("ip_table_invalid");
    }
    const base = HEADER + this.#n4 * 6;
    for (let k = 1; k < this.#n6; k++) {
      if (view.getBigUint64(base + k * 8) <= view.getBigUint64(base + (k - 1) * 8)) throw new Error("ip_table_invalid");
    }
  }

  country(ip: string): string | null {
    const s = ip.trim().toLowerCase();
    const v4 = parseIpv4(s) ?? mappedIpv4(s);
    if (v4 !== null) {
      const i = this.#last(this.#n4, (k) => this.#view.getUint32(HEADER + k * 4) <= v4);
      return i < 0 ? null : countryAt(this.#bytes, HEADER + this.#n4 * 4 + i * 2);
    }
    const v6 = parseIpv6(s);
    if (v6 === null) return null;
    const base = HEADER + this.#n4 * 6;
    const i = this.#last(this.#n6, (k) => this.#view.getBigUint64(base + k * 8) <= v6);
    return i < 0 ? null : countryAt(this.#bytes, base + this.#n6 * 8 + i * 2);
  }

  /// The last index in [0, n) whose start is at or below the address.
  #last(n: number, atOrBelow: (k: number) => boolean): number {
    let lo = 0;
    let hi = n - 1;
    let found = -1;
    while (lo <= hi) {
      const mid = (lo + hi) >>> 1;
      if (atOrBelow(mid)) {
        found = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return found;
  }
}

/// The table at [url]; no file or an unusable one is NO_RESOLVER, logged
/// once as ip_table_unavailable. A table over STALE_DAYS old (at [now]) is
/// used, logged once as ip_table_stale.
export async function loadResolver(
  url: URL,
  read: (u: URL) => Promise<Uint8Array> = Deno.readFile,
  now: number = Date.now(),
): Promise<IpCountryResolver> {
  let table: RangeTable;
  try {
    table = new RangeTable(await read(url));
  } catch {
    console.error("dating-device-check:", "ip_table_unavailable");
    return NO_RESOLVER;
  }
  if (now - table.builtDay * DAY_MS > STALE_DAYS * DAY_MS) console.warn("dating-device-check:", "ip_table_stale");
  return table;
}

/// One load per instance: the first call reads the table (and logs, at
/// most once); every later call shares that answer.
export function tableOnce(
  url: URL,
  read?: (u: URL) => Promise<Uint8Array>,
  now?: number,
): () => Promise<IpCountryResolver> {
  let table: Promise<IpCountryResolver> | null = null;
  return () => (table ??= loadResolver(url, read, now));
}

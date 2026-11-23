// supabase/functions/dating-device-check/ip_table_build.ts
// Spec 2 W8b (R-74): DB-IP's country CSV ("start,end,country" per line,
// IPv4 and IPv6 mixed) to the compact table ip_country.ts reads (version 2:
// the build day in the header, a checksum at the end). IPv6 is kept at its
// top 64 bits.
//
// Fix round 1 (M-1..M-3): ranges are swept, not skipped. A span one country
// covers is that country (an overlap of one country is one range, its tail
// kept); a span no range covers, or that two countries claim (an overlap,
// or a /64 split below 64 bits), is "--", no country: never a wrong one.
// Adjacent spans of one country are one. DB-IP's "ZZ" (reserved, unknown)
// and anything that isn't two upper-case letters is no country (M-2).
// Used by scripts/ip_country/build_ip_country.ts at deploy time, and by the
// tests.
import { checksum, HEADER, parseIpv4, parseIpv6, TABLE_VERSION } from "./ip_country.ts";

const DAY_MS = 86_400_000;
const NO_COUNTRY: ReadonlySet<string> = new Set(["ZZ"]);

type Range<T> = { start: T; end: T; country: string };

/// What a build found: spans two countries claimed (written as "--").
export interface BuildStats {
  conflicts: number;
}

/// Sorted starts and countries. [after] is the address after [x]; [top] is
/// one past the top of the space (nothing starts there).
function sweep<T extends number | bigint>(ranges: Range<T>[], after: (x: T) => T, top: T, stats: BuildStats): Array<[T, string]> {
  const events: Array<[T, number, string]> = [];
  for (const r of ranges) {
    events.push([r.start, 1, r.country]);
    events.push([after(r.end), -1, r.country]);
  }
  events.sort((a, b) => (a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : 0));
  const live = new Map<string, number>();
  const out: Array<[T, string]> = [];
  let i = 0;
  while (i < events.length) {
    const at = events[i][0];
    for (; i < events.length && events[i][0] === at; i++) {
      const [, delta, c] = events[i];
      const n = (live.get(c) ?? 0) + delta;
      if (n === 0) live.delete(c);
      else live.set(c, n);
    }
    if (at === top) break;
    if (live.size > 1) stats.conflicts++;
    const country = live.size === 1 ? (live.keys().next().value as string) : "--";
    const last = out[out.length - 1];
    if (last === undefined ? country !== "--" : last[1] !== country) out.push([at, country]);
  }
  return out;
}

export function buildTable(csv: string, built: Date = new Date(), stats: BuildStats = { conflicts: 0 }): Uint8Array {
  const v4: Range<number>[] = [];
  const v6: Range<bigint>[] = [];
  for (const raw of csv.split(/\r?\n/)) {
    const [a, b, c] = raw.replaceAll('"', "").split(",").map((x) => x.trim());
    if (!a || !b || !c || !/^[A-Z]{2}$/.test(c) || NO_COUNTRY.has(c)) continue;
    const s4 = parseIpv4(a), e4 = parseIpv4(b);
    if (s4 !== null && e4 !== null && s4 <= e4) {
      v4.push({ start: s4, end: e4, country: c });
      continue;
    }
    const s6 = parseIpv6(a), e6 = parseIpv6(b);
    if (s6 !== null && e6 !== null && s6 <= e6) v6.push({ start: s6, end: e6, country: c });
  }
  const r4 = sweep(v4, (x) => x + 1, 2 ** 32, stats);
  const r6 = sweep(v6, (x) => x + 1n, 1n << 64n, stats);
  const out = new Uint8Array(HEADER + r4.length * 6 + r6.length * 10 + 4);
  const view = new DataView(out.buffer);
  out.set([0x41, 0x49, 0x50, 0x43, TABLE_VERSION]);
  view.setUint32(5, Math.floor(built.getTime() / DAY_MS));
  view.setUint32(9, r4.length);
  view.setUint32(13, r6.length);
  let at = HEADER;
  for (const [start] of r4) (view.setUint32(at, start), (at += 4));
  for (const [, c] of r4) (out.set([c.charCodeAt(0), c.charCodeAt(1)], at), (at += 2));
  for (const [start] of r6) (view.setBigUint64(at, start), (at += 8));
  for (const [, c] of r6) (out.set([c.charCodeAt(0), c.charCodeAt(1)], at), (at += 2));
  view.setUint32(at, checksum(out.subarray(0, at)));
  return out;
}

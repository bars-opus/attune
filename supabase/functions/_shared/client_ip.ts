// supabase/functions/_shared/client_ip.ts
//
// Spec 1 W2c (batch 7 review I-1): the caller's address, for per-IP limits.
// Supabase's front door (Cloudflare) sets cf-connecting-ip itself, over
// any value a client sent, and appends the address it saw to whatever
// x-forwarded-for the client sent. So: cf-connecting-ip when it is an IP
// literal; otherwise the right-most x-forwarded-for entry; never the first,
// which the client writes. Anything else is "unknown" (one shared bucket:
// the worst a shared bucket does is send codes by SMS).

const IPV4 = /^(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}$/;
const IPV6 = /^[0-9a-f:.]{2,45}$/;

function ipLiteral(raw: string | null | undefined): string | null {
  const value = (raw ?? "").trim().toLowerCase();
  if (IPV4.test(value)) return value;
  if (value.includes(":") && IPV6.test(value)) return value;
  return null;
}

export function clientIp(headers: Headers): string {
  const edge = ipLiteral(headers.get("cf-connecting-ip"));
  if (edge) return edge;
  const hops = (headers.get("x-forwarded-for") ?? "")
    .split(",")
    .map((entry) => entry.trim())
    .filter((entry) => entry.length > 0);
  return ipLiteral(hops.at(-1)) ?? "unknown";
}

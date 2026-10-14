// The calendar-feed request path (plan Phase 5 R5): anything it can't serve
// gets one identical 404, so a link never reveals whether a couple exists.
import { buildCalendar, type FeedItem } from "./ics.ts";

export function tokenFromPath(pathname: string): string | null {
  const last = pathname.split("/").filter(Boolean).pop() ?? "";
  const token = last.endsWith(".ics") ? last.slice(0, -4) : last;
  return /^[0-9a-f]{64}$/.test(token) ? token : null;
}

export async function sha256Hex(s: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

const notFound = () =>
  new Response("Not found", {
    status: 404,
    headers: { "content-type": "text/plain; charset=utf-8", "cache-control": "no-store" },
  });

export async function handleFeedRequest(
  req: Request,
  fetchFeed: (hash: string) => Promise<{ items: FeedItem[] } | null>,
  now: Date = new Date(),
): Promise<Response> {
  if (req.method !== "GET" && req.method !== "HEAD") return notFound();
  const token = tokenFromPath(new URL(req.url).pathname);
  if (!token) return notFound();
  let feed: { items: FeedItem[] } | null;
  try {
    feed = await fetchFeed(await sha256Hex(token));
  } catch (_) {
    return new Response("Try again later", {
      status: 503,
      headers: { "content-type": "text/plain; charset=utf-8", "retry-after": "3600" },
    });
  }
  if (!feed) return notFound();
  return new Response(req.method === "HEAD" ? null : buildCalendar(feed.items, now), {
    status: 200,
    headers: {
      "content-type": "text/calendar; charset=utf-8",
      "content-disposition": 'inline; filename="together.ics"',
      "cache-control": "private, max-age=900",
    },
  });
}

// RFC 5545 for the Together calendar feed (plan Phase 5 R1, R2). Pure: the
// edge function hands it the rows and the clock.

export type FeedItem = {
  kind: "event" | "reminder" | "planning_date";
  id: string;
  date: string; // YYYY-MM-DD: the day this row falls on
  starts_at: string | null;
  ends_at: string | null;
  all_day: boolean;
  title: string;
  note: string | null;
  location: string | null;
  recurring: boolean;
  continuation: boolean;
};

type VEvent = {
  uid: string;
  start: string; // property value incl. params, e.g. ";VALUE=DATE:20261107" or ":20261107T180000Z"
  end: string;
  title: string;
  note: string | null;
  location: string | null;
  transparent: boolean;
};

export function escapeText(s: string): string {
  return s
    .replace(/\\/g, "\\\\")
    .replace(/;/g, "\\;")
    .replace(/,/g, "\\,")
    .replace(/\r?\n/g, "\\n");
}

// Lines over 75 octets fold with CRLF + space, never inside a character.
export function foldLine(line: string): string {
  const enc = new TextEncoder();
  const parts: string[] = [];
  let cur = "";
  let bytes = 0;
  let limit = 75;
  for (const ch of line) {
    const b = enc.encode(ch).length;
    if (bytes + b > limit) {
      parts.push(cur);
      cur = "";
      bytes = 0;
      limit = 74; // the leading space takes one octet
    }
    cur += ch;
    bytes += b;
  }
  parts.push(cur);
  return parts.join("\r\n ");
}

const utc = (d: Date) => d.toISOString().replace(/[-:]/g, "").replace(/\.\d{3}/, "");
const ymd = (date: string) => date.replaceAll("-", "");
function addDays(date: string, n: number): string {
  const d = new Date(`${date}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + n);
  return d.toISOString().slice(0, 10);
}
const prefix = (kind: FeedItem["kind"]) => kind === "planning_date" ? "planning" : kind;

function toEvents(items: FeedItem[]): VEvent[] {
  const out: VEvent[] = [];
  const allDayRuns = new Map<string, FeedItem[]>();
  // One row per item per day: e.g. a plan with two date blocks on the same
  // day would otherwise repeat a UID, which some calendar apps reject.
  const seenDays = new Set<string>();
  for (const i of items) {
    if (!i.all_day) {
      if (i.continuation || !i.starts_at) continue;
      const start = new Date(i.starts_at);
      const end = i.ends_at ? new Date(i.ends_at) : new Date(start.getTime() + 3600_000);
      out.push({
        uid: i.recurring ? `event-${i.id}-${ymd(i.date)}` : `event-${i.id}`,
        start: `:${utc(start)}`,
        end: `:${utc(end)}`,
        title: i.title, note: i.note, location: i.location, transparent: false,
      });
      continue;
    }
    const day = `${i.kind}:${i.id}:${i.date}`;
    if (seenDays.has(day)) continue;
    seenDays.add(day);
    // One-off all-day items: consecutive days of the same item form one entry.
    const key = i.recurring || i.kind === "reminder" ? `${i.kind}:${i.id}:${i.date}` : `${i.kind}:${i.id}`;
    const run = allDayRuns.get(key) ?? [];
    run.push(i);
    allDayRuns.set(key, run);
  }
  for (const rows of allDayRuns.values()) {
    rows.sort((a, b) => a.date.localeCompare(b.date));
    let first = rows[0];
    let last = rows[0];
    const flush = () => {
      const oneOffEvent = first.kind === "event" && !first.recurring;
      out.push({
        uid: oneOffEvent
          ? `event-${first.id}`
          : `${prefix(first.kind)}-${first.id}-${ymd(first.date)}`,
        start: `;VALUE=DATE:${ymd(first.date)}`,
        end: `;VALUE=DATE:${ymd(addDays(last.date, 1))}`,
        title: first.title, note: first.note, location: first.location,
        transparent: first.kind !== "event",
      });
    };
    for (const r of rows.slice(1)) {
      if (r.date === addDays(last.date, 1)) {
        last = r;
      } else {
        flush();
        first = r;
        last = r;
      }
    }
    flush();
  }
  return out;
}

// feed: false builds a one-off file (Spec 3c export): no refresh hints.
export function buildCalendar(
  items: FeedItem[],
  now: Date,
  options: { feed?: boolean } = {},
): string {
  const feed = options.feed ?? true;
  const lines = [
    "BEGIN:VCALENDAR",
    "VERSION:2.0",
    "PRODID:-//Attune//Together//EN",
    "CALSCALE:GREGORIAN",
    "METHOD:PUBLISH",
    feed ? "X-WR-CALNAME:Together" : "X-WR-CALNAME:Attune export",
    ...(feed ? ["REFRESH-INTERVAL;VALUE=DURATION:PT6H", "X-PUBLISHED-TTL:PT6H"] : []),
  ];
  const stamp = utc(now);
  for (const e of toEvents(items)) {
    lines.push(
      "BEGIN:VEVENT",
      `UID:${e.uid}@together.attune`,
      `DTSTAMP:${stamp}`,
      `DTSTART${e.start}`,
      `DTEND${e.end}`,
      `SUMMARY:${escapeText(e.title)}`,
    );
    if (e.location) lines.push(`LOCATION:${escapeText(e.location)}`);
    if (e.note) lines.push(`DESCRIPTION:${escapeText(e.note)}`);
    lines.push(`TRANSP:${e.transparent ? "TRANSPARENT" : "OPAQUE"}`, "END:VEVENT");
  }
  lines.push("END:VCALENDAR");
  return lines.map(foldLine).join("\r\n") + "\r\n";
}

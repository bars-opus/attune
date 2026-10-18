import { assert, assertEquals, assertStringIncludes } from "https://deno.land/std@0.208.0/assert/mod.ts";
import { buildCalendar, escapeText, type FeedItem, foldLine } from "./ics.ts";

const NOW = new Date("2026-11-01T10:00:00Z");
const base: FeedItem = {
  kind: "event", id: "e1", date: "2026-11-07", starts_at: null, ends_at: null,
  all_day: false, title: "Dinner", note: null, location: null, recurring: false, continuation: false,
};
const lines = (ics: string) => ics.replace(/\r\n /g, "").split("\r\n");

Deno.test("an empty feed is still a valid calendar with CRLF line ends", () => {
  const ics = buildCalendar([], NOW);
  assert(ics.startsWith("BEGIN:VCALENDAR\r\nVERSION:2.0\r\n"));
  assert(ics.endsWith("END:VCALENDAR\r\n"));
  assertStringIncludes(ics, "X-WR-CALNAME:Together\r\n");
  assert(!/[^\r]\n/.test(ics), "bare LF found");
});

Deno.test("a timed event is in UTC with a stable id", () => {
  const ics = buildCalendar([{ ...base, starts_at: "2026-11-07T18:00:00+00:00", ends_at: "2026-11-07T20:00:00+00:00" }], NOW);
  const l = lines(ics);
  assert(l.includes("UID:event-e1@together.attune"));
  assert(l.includes("DTSTART:20261107T180000Z"));
  assert(l.includes("DTEND:20261107T200000Z"));
  assert(l.includes("DTSTAMP:20261101T100000Z"));
  assert(l.includes("SUMMARY:Dinner"));
});

Deno.test("a timed event with no end lasts an hour; its later days are skipped", () => {
  const ics = buildCalendar([
    { ...base, starts_at: "2026-11-07T23:00:00Z", ends_at: null },
    { ...base, date: "2026-11-08", starts_at: "2026-11-07T23:00:00Z", continuation: true },
  ], NOW);
  assertEquals(lines(ics).filter((x) => x === "BEGIN:VEVENT").length, 1);
  assert(lines(ics).includes("DTEND:20261108T000000Z"));
});

Deno.test("a multi-day all-day event is one entry; a daily repeat stays separate", () => {
  const trip = ["2026-11-07", "2026-11-08", "2026-11-09"].map((d) => ({ ...base, id: "trip", all_day: true, date: d }));
  const daily = ["2026-11-07", "2026-11-08"].map((d) => ({ ...base, id: "gym", all_day: true, date: d, recurring: true, title: "Busy" }));
  const l = lines(buildCalendar([...trip, ...daily], NOW));
  assert(l.includes("UID:event-trip@together.attune"));
  assert(l.includes("DTSTART;VALUE=DATE:20261107"));
  assert(l.includes("DTEND;VALUE=DATE:20261110"));
  assert(l.includes("UID:event-gym-20261107@together.attune"));
  assert(l.includes("UID:event-gym-20261108@together.attune"));
  assertEquals(l.filter((x) => x === "BEGIN:VEVENT").length, 3);
});

Deno.test("reminders and Planning dates don't block time", () => {
  const l = lines(buildCalendar([
    { ...base, kind: "reminder", id: "r1", all_day: true, title: "Kofi's birthday" },
    { ...base, kind: "planning_date", id: "p1", all_day: true, title: "Trip plan" },
  ], NOW));
  assert(l.includes("UID:reminder-r1-20261107@together.attune"));
  assert(l.includes("UID:planning-p1-20261107@together.attune"));
  assertEquals(l.filter((x) => x === "TRANSP:TRANSPARENT").length, 2);
});

Deno.test("text is escaped and long lines fold without splitting a character", () => {
  assertEquals(escapeText("a,b;c\\d\ne"), "a\\,b\\;c\\\\d\\ne");
  const long = "SUMMARY:" + "🎉".repeat(40);
  const folded = foldLine(long);
  for (const part of folded.split("\r\n")) {
    assert(new TextEncoder().encode(part).length <= 75, `line too long: ${part}`);
  }
  assertEquals(folded.replace(/\r\n /g, ""), long);
  const ics = buildCalendar([{ ...base, starts_at: "2026-11-07T18:00:00Z", title: "Dinner, at Buka; 7pm", note: "Bring cash\nand gift", location: "Osu, Accra" }], NOW);
  const l = lines(ics);
  assert(l.includes("SUMMARY:Dinner\\, at Buka\\; 7pm"));
  assert(l.includes("DESCRIPTION:Bring cash\\nand gift"));
  assert(l.includes("LOCATION:Osu\\, Accra"));
});

Deno.test("the same item on the same day twice is one entry (no duplicate UIDs)", () => {
  const plan = { ...base, kind: "planning_date" as const, id: "p1", all_day: true, title: "Trip plan" };
  const l = lines(buildCalendar([plan, { ...plan }], NOW));
  assertEquals(l.filter((x) => x === "UID:planning-p1-20261107@together.attune").length, 1);
  const uids = l.filter((x) => x.startsWith("UID:"));
  assertEquals(new Set(uids).size, uids.length);
});

// Spec 3c: a downloaded file is not a subscription -- no refresh hints.
Deno.test("file mode omits the feed refresh lines", () => {
  const out = buildCalendar([], new Date("2026-10-18T09:00:00Z"), { feed: false });
  assert(!out.includes("REFRESH-INTERVAL"), "no REFRESH-INTERVAL");
  assert(!out.includes("X-PUBLISHED-TTL"), "no X-PUBLISHED-TTL");
  assert(out.includes("X-WR-CALNAME:Attune export"), "named as an export");
  const feed = buildCalendar([], new Date("2026-10-18T09:00:00Z"));
  assert(feed.includes("REFRESH-INTERVAL"), "the feed keeps its refresh hint");
});

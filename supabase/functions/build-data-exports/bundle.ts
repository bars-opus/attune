// Spec 3c: the pure parts of the export worker -- media budget, calendar
// mapping, README, ZIP. index.ts does the I/O.
import { Zip, ZipPassThrough } from "https://esm.sh/fflate@0.8.2";
import type { FeedItem } from "../calendar-feed/ics.ts";

/**
 * One part's media: at most 150 files, 40 MB, 25 MB a file (final review C1:
 * an edge function has ~2 s CPU and 256 MB per run, so a download is built
 * a part per run). Sizes come from the manifest, so nothing over budget is
 * downloaded; an unknown size is not fetched blind.
 */
export class MediaBudget {
  readonly limits: { files: number; bytes: number; perFile: number };
  private files = 0;
  private bytes = 0;

  constructor(limits = { files: 150, bytes: 40 * 1024 * 1024, perFile: 25 * 1024 * 1024 }) {
    this.limits = limits;
  }

  /** True (and counted) if a file of [size] bytes still fits. */
  admit(size: number | null): boolean {
    if (size == null || size > this.limits.perFile) return false;
    if (this.files + 1 > this.limits.files || this.bytes + size > this.limits.bytes) {
      return false;
    }
    this.files += 1;
    this.bytes += size;
    return true;
  }
}

type CalendarRow = {
  kind: FeedItem["kind"];
  id: string;
  date: string;
  starts_at: string | null;
  ends_at: string | null;
  all_day: boolean;
  title: string;
  note?: string | null;
  location?: string | null;
  recurring?: boolean;
  continuation?: boolean;
};

// deno-lint-ignore no-explicit-any
export function calendarItems(bundle: any): FeedItem[] {
  const out: FeedItem[] = [];
  for (const rel of bundle.relationships ?? []) {
    for (const row of (rel.calendar ?? []) as CalendarRow[]) {
      out.push({
        kind: row.kind,
        id: row.id,
        date: row.date,
        starts_at: row.starts_at,
        ends_at: row.ends_at,
        all_day: row.all_day,
        title: row.title,
        note: row.note ?? null,
        location: row.location ?? null,
        recurring: row.recurring ?? false,
        continuation: row.continuation ?? false,
      });
    }
  }
  return out;
}

// deno-lint-ignore no-explicit-any
export function readme(bundle: any): string {
  return [
    "Your Attune download",
    "",
    "A copy of what's yours: your messages and the photos you shared, plans,",
    "calendar, stories, check-ins, journal, quiz answers, and the insights and",
    "readouts Attune showed you. Never anything about safety, never anyone's",
    "private items, and never the behind-the-scenes analysis of your chats.",
    "",
    "If it came in parts (attune-export-1.zip, attune-export-2.zip and so on),",
    "unzip them all into one folder.",
    "",
    "data.json                 everything as data",
    "calendar.ics              your calendar, to open in any calendar app",
    "relationship-N/chat/      your conversations, a page per file",
    "media/                    photos, voice notes and videos",
    "",
    `Shared spaces in this download: ${(bundle.relationships ?? []).length}.`,
  ].join("\n") + "\n";
}

/** A storage error that means the file is gone, not a passing failure (re-review I4). */
export function isMissingObject(error: unknown): boolean {
  // deno-lint-ignore no-explicit-any
  const e = error as any;
  const status = Number(e?.status ?? e?.statusCode ?? e?.originalError?.status);
  return status === 404 || status === 400;
}

export type LeftOut = { file: string; reason: "too_large" | "unavailable" | "over_limit" };

/** What media_not_included.txt says, counted by reason (final review I5). */
export function leftOutNote(items: LeftOut[]): string {
  const count = (r: LeftOut["reason"]) => items.filter((i) => i.reason === r).length;
  const files = (n: number) => `${n} file${n === 1 ? " was" : "s were"}`;
  const lines = ["Some media is not in this download:", ""];
  if (count("too_large")) lines.push(`${files(count("too_large"))} too large (over 25 MB).`);
  if (count("unavailable")) {
    const n = count("unavailable");
    lines.push(`${n} file${n === 1 ? "" : "s"} could not be read (it may have been deleted).`);
  }
  if (count("over_limit")) lines.push(`${files(count("over_limit"))} over this download's size limit.`);
  lines.push("", "The full list is in media_not_included.json.");
  return lines.join("\n") + "\n";
}

/**
 * A ZIP built entry by entry, stored (no deflate: the CPU budget is ~2 s a
 * run; final review C1). Each file's bytes can be released once added.
 */
export class ZipStream {
  private readonly chunks: Uint8Array[] = [];
  private readonly zip: Zip;
  private entries = 0;

  /** Files added so far; a part with none is not stored (re-review I3). */
  get count(): number {
    return this.entries;
  }

  constructor() {
    this.zip = new Zip((err, chunk) => {
      if (err) throw err;
      this.chunks.push(chunk);
    });
  }

  add(name: string, data: Uint8Array): void {
    const entry = new ZipPassThrough(name);
    this.zip.add(entry);
    entry.push(data, true);
    this.entries += 1;
  }

  finish(): Blob {
    this.zip.end();
    return new Blob(this.chunks as BlobPart[], { type: "application/zip" });
  }
}

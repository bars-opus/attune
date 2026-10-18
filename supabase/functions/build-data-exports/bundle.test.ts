// Spec 3c (R3c-1, R3c-4): the pure parts of the export worker.
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { unzipSync, strFromU8 } from "https://esm.sh/fflate@0.8.2";
import { calendarItems, isMissingObject, leftOutNote, MediaBudget, readme, ZipStream } from "./bundle.ts";

Deno.test("one part's media budget: 150 files, 40 MB, 25 MB a file (final review C1)", () => {
  const b = new MediaBudget({ files: 2, bytes: 100, perFile: 60 });
  assert(b.admit(40));
  assert(!b.admit(61), "per-file cap");
  assert(b.admit(50));
  assert(!b.admit(1), "file cap");
  const c = new MediaBudget({ files: 10, bytes: 100, perFile: 100 });
  assert(c.admit(90));
  assert(!c.admit(20), "byte cap");
  assert(c.admit(10), "a small one still fits");
  assert(!c.admit(null), "an unknown size is not fetched blind");
  assertEquals(new MediaBudget().limits, { files: 150, bytes: 40 * 1024 * 1024, perFile: 25 * 1024 * 1024 });
});

Deno.test("calendar rows become feed items, every relationship", () => {
  const items = calendarItems({
    relationships: [
      { name: "relationship-1", calendar: [
        { kind: "event", id: "c1", date: "2026-10-20", starts_at: null, ends_at: null, all_day: true, title: "Dinner",
          note: "at Mum's", location: "Osu", recurring: true, continuation: false },
      ] },
      { name: "relationship-2", calendar: [] },
    ],
  });
  assertEquals(items.length, 1);
  assertEquals(items[0], {
    kind: "event", id: "c1", date: "2026-10-20", starts_at: null, ends_at: null, all_day: true,
    title: "Dinner", note: "at Mum's", location: "Osu", recurring: true, continuation: false,
  });
});

Deno.test("the README says what is inside and never claims to hold what it left out", () => {
  const text = readme({ relationships: [{}] });
  assert(text.includes("anything about safety"));
  assert(!text.includes("never includes Attune's own analysis"), "insights and readouts are included (final review I3)");
  assert(text.includes("attune-export-1.zip"));
  const note = leftOutNote([{ file: "media/chat/a.jpg", reason: "too_large" }, { file: "media/chat/b.jpg", reason: "unavailable" }]);
  assert(note.includes("1 file was too large"));
  assert(note.includes("1 file could not be read"));
});

Deno.test("the streamed zip holds every file under its path", async () => {
  const zip = new ZipStream();
  zip.add("data.json", new TextEncoder().encode("{}"));
  zip.add("media/a.jpg", new Uint8Array([1, 2]));
  const blob = zip.finish();
  const files = unzipSync(new Uint8Array(await blob.arrayBuffer()));
  assertEquals(strFromU8(files["data.json"]), "{}");
  assertEquals(Array.from(files["media/a.jpg"]), [1, 2]);
});

Deno.test("only a gone file counts as missing (re-review I4)", () => {
  assert(isMissingObject({ status: 404 }));
  assert(isMissingObject({ statusCode: "400" }));
  assert(isMissingObject({ originalError: { status: 404 } }));
  assert(!isMissingObject({ status: 429 }));
  assert(!isMissingObject({ status: 503 }));
  assert(!isMissingObject(new Error("network")));
});

Deno.test("the README does not promise parts to a one-part download (re-review M9)", () => {
  assert(readme({ relationships: [] }).includes("If it came in parts"));
});

Deno.test("the zip counts its entries", () => {
  const zip = new ZipStream();
  assertEquals(zip.count, 0);
  zip.add("a", new Uint8Array([1]));
  assertEquals(zip.count, 1);
});

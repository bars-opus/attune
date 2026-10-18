// supabase/functions/build-data-exports/parts.ts
//
// Spec 3c: one bounded part of a download per run (final review C1; re-review
// I2-I5). index.ts only authenticates and schedules this.
//   data   -> data.json, calendar.ics, README.txt
//   chat   -> chat pages, across chapters, up to 10 pages / ~30 MB
//   media  -> up to 150 files / 40 MB, walked by a (bucket, name) cursor
// A run with nothing to store records its progress and uploads nothing.
import { buildCalendar } from "../calendar-feed/ics.ts";
import {
  calendarItems,
  isMissingObject,
  type LeftOut,
  leftOutNote,
  MediaBudget,
  readme,
  ZipStream,
} from "./bundle.ts";

export type Limits = {
  chatPage: number;
  chatPagesPerPart: number;
  /** Stop adding chat pages once a part holds this much. */
  chatPartBytes: number;
  /** Never let one part grow past this (the bucket takes 50 MB). */
  partCeiling: number;
  /** Manifest rows read per media part. */
  mediaWindow: number;
  maxParts: number;
  mediaBudget?: { files: number; bytes: number; perFile: number };
};

export const LIMITS: Limits = {
  chatPage: 2000,
  chatPagesPerPart: 10,
  chatPartBytes: 30 * 1024 * 1024,
  partCeiling: 45 * 1024 * 1024,
  mediaWindow: 1000,
  maxParts: 12,
};

export type Job = {
  id: string;
  user_id: string;
  relationship_ids: string[];
  phase: "data" | "chat" | "media";
  rel_index: number;
  chat_after_at: string | null;
  chat_after_id: string | null;
  chat_page: number;
  media_after_bucket: string | null;
  media_after_name: string | null;
  storage_keys: string[];
  left_out: LeftOut[];
};

export type Progress = {
  phase: "data" | "chat" | "media" | "done";
  rel_index: number;
  chat_after_at: string | null;
  chat_after_id: string | null;
  chat_page: number;
  media_after_bucket: string | null;
  media_after_name: string | null;
};

const fresh = { chat_after_at: null, chat_after_id: null, chat_page: 0, media_after_bucket: null, media_after_name: null };

// deno-lint-ignore no-explicit-any
export async function buildPart(supabase: any, job: Job, zip: ZipStream, limits: Limits = LIMITS): Promise<{ next: Progress; leftOut: LeftOut[] }> {
  const enc = new TextEncoder();
  const rels = job.relationship_ids ?? [];
  const leftOut: LeftOut[] = [];

  if (job.phase === "data") {
    const { data: bundle, error } = await supabase.rpc("export_bundle", {
      p_user_id: job.user_id,
      p_relationship_ids: rels,
    });
    if (error) throw error;
    zip.add("data.json", enc.encode(JSON.stringify(bundle)));
    zip.add("calendar.ics", enc.encode(buildCalendar(calendarItems(bundle), new Date(), { feed: false })));
    zip.add("README.txt", enc.encode(readme(bundle)));
    return { next: { ...fresh, phase: rels.length > 0 ? "chat" : "media", rel_index: 1 }, leftOut };
  }

  if (job.phase === "chat") {
    let rel = job.rel_index;
    let afterAt = job.chat_after_at;
    let afterId = job.chat_after_id;
    let page = job.chat_page;
    let pageLimit = limits.chatPage;
    let pages = 0;
    let bytes = 0;
    while (rel <= rels.length && pages < limits.chatPagesPerPart && bytes < limits.chatPartBytes) {
      const { data, error } = await supabase.rpc("export_chat_page", {
        p_user_id: job.user_id,
        p_relationship_id: rels[rel - 1],
        p_after_at: afterAt,
        p_after_id: afterId,
        p_limit: pageLimit,
      });
      if (error) throw error;
      const row = Array.isArray(data) ? data[0] : data;
      const rows = (row?.rows ?? []) as unknown[];
      if (rows.length > 0) {
        const body = enc.encode(JSON.stringify(rows));
        if (bytes + body.length > limits.partCeiling) {
          if (bytes > 0) break; // the next part starts with this page
          if (pageLimit > 1) {
            // One page alone is too big (long imported messages): ask again
            // for fewer rows from the same cursor.
            pageLimit = Math.max(1, Math.floor(pageLimit / 4));
            continue;
          }
        }
        page += 1;
        pages += 1;
        bytes += body.length;
        zip.add(`relationship-${rel}/chat/page-${page}.json`, body);
        afterAt = row.last_at;
        afterId = row.last_id;
      }
      if (rows.length < pageLimit) {
        // This chapter's chat is done: the next one, in this same part.
        rel += 1;
        afterAt = null;
        afterId = null;
        page = 0;
        pageLimit = limits.chatPage;
      }
    }
    return {
      next: rel > rels.length
        ? { ...fresh, phase: "media", rel_index: rel }
        : { ...fresh, phase: "chat", rel_index: rel, chat_after_at: afterAt, chat_after_id: afterId, chat_page: page },
      leftOut,
    };
  }

  // media
  const lastPart = job.storage_keys.length + 1 >= limits.maxParts;
  const { data: manifest, error: manifestError } = await supabase.rpc("export_media_manifest", {
    p_user_id: job.user_id,
    p_relationship_ids: rels,
    p_after_bucket: job.media_after_bucket,
    p_after_name: job.media_after_name,
    // The last allowed part reads the rest, to list what did not fit.
    p_limit: lastPart ? null : limits.mediaWindow,
  });
  if (manifestError) throw manifestError;
  const items = (manifest ?? []) as { bucket: string; object_name: string; zip_path: string; size_bytes: number | null }[];
  const budget = new MediaBudget(limits.mediaBudget);
  let i = 0;
  let added = 0;
  let cursor: { bucket: string | null; name: string | null } = { bucket: job.media_after_bucket, name: job.media_after_name };
  const take = (item: (typeof items)[number]) => {
    cursor = { bucket: item.bucket, name: item.object_name };
    i += 1;
  };
  while (i < items.length) {
    const item = items[i];
    if (item.size_bytes != null && item.size_bytes > budget.limits.perFile) {
      leftOut.push({ file: item.zip_path, reason: "too_large" });
      take(item);
      continue;
    }
    if (item.size_bytes == null) {
      leftOut.push({ file: item.zip_path, reason: "unavailable" });
      take(item);
      continue;
    }
    if (!budget.admit(item.size_bytes)) {
      if (added === 0) {
        // Cannot happen with perFile <= bytes, but never loop forever.
        leftOut.push({ file: item.zip_path, reason: "too_large" });
        take(item);
        continue;
      }
      break; // this part is full; the next run carries on after the cursor
    }
    const { data: blob, error } = await supabase.storage.from(item.bucket).download(item.object_name);
    if (error || !blob) {
      // Only a file that is gone is listed; anything else (rate limit, 5xx)
      // fails the part, which is retried (re-review I4).
      if (error && !isMissingObject(error)) throw error;
      leftOut.push({ file: item.zip_path, reason: "unavailable" });
      take(item);
      continue;
    }
    zip.add(item.zip_path, new Uint8Array(await blob.arrayBuffer()));
    added += 1;
    take(item);
  }
  let done = i >= items.length && (lastPart || items.length < limits.mediaWindow);
  if (i < items.length && lastPart) {
    for (const rest of items.slice(i)) leftOut.push({ file: rest.zip_path, reason: "over_limit" });
    done = true;
  }
  return {
    next: { ...fresh, phase: done ? "done" : "media", rel_index: job.rel_index, media_after_bucket: cursor.bucket, media_after_name: cursor.name },
    leftOut,
  };
}

// deno-lint-ignore no-explicit-any
export async function runOnce(supabase: any, limits: Limits = LIMITS): Promise<number> {
  const { data: claimed, error: claimError } = await supabase.rpc("claim_data_export");
  if (claimError) throw claimError;
  const job = (Array.isArray(claimed) ? claimed[0] : claimed) as Job | undefined;
  if (!job) return 0;

  try {
    const zip = new ZipStream();
    const { next, leftOut } = await buildPart(supabase, job, zip, limits);
    const done = next.phase === "done";
    if (done) {
      const all = [...(job.left_out ?? []), ...leftOut];
      if (all.length > 0) {
        const enc = new TextEncoder();
        zip.add("media_not_included.txt", enc.encode(leftOutNote(all)));
        zip.add("media_not_included.json", enc.encode(JSON.stringify(all)));
      }
    }
    let key: string | null = null;
    if (zip.count > 0) {
      const { data, error: keyError } = await supabase.rpc("export_begin_part", { p_job_id: job.id });
      if (keyError) throw keyError;
      key = data as string;
      const { error: uploadError } = await supabase.storage
        .from("data-exports")
        .upload(key, zip.finish(), { contentType: "application/zip", upsert: true });
      if (uploadError) throw uploadError;
    }
    const { error: finishError } = await supabase.rpc("export_finish_part", {
      p_job_id: job.id,
      p_key: key,
      p_phase: done ? "done" : next.phase,
      p_rel_index: next.rel_index,
      p_chat_after_at: next.chat_after_at,
      p_chat_after_id: next.chat_after_id,
      p_chat_page: next.chat_page,
      p_media_after_bucket: next.media_after_bucket,
      p_media_after_name: next.media_after_name,
      p_left_out: leftOut,
      p_done: done,
    });
    if (finishError) throw finishError;
    return 1;
  } catch (error) {
    // Back to the queue with its finished parts kept; the third error on the
    // same part fails it (re-review I2). Only the error's kind is logged.
    const kind = error instanceof Error ? error.name : typeof error;
    await supabase.rpc("export_retry_part", { p_job_id: job.id, p_error: kind });
    console.error("build-data-exports part failed:", kind);
    return 0;
  }
}

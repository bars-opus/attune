// supabase/functions/_architecture/push_queue_writers.test.ts
//
// Spec 2 W8 final server fix (carry Re-2-M2): the TypeScript side of the
// push audit. The SQL contract (dating_v2_device_contracts.sql §A) audits
// every SQL function that writes the push queue; this test pins which edge
// function files may touch the queue tables or send a push at all, so a
// new TypeScript writer (a Dating one above all) fails here until it is
// reviewed and listed. A file is a writer when its code (comments aside)
// names a queue table, uses the shared enqueuePush helper (or imports its
// module), reaches OneSignal, or (Spec 2 W9, carry 2) calls the
// send-notification function (functions.invoke or its URL). The list is
// exact both ways: a listed
// file that stops touching what it is listed for fails too, so the list
// never keeps a stale entry.
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";

/** The push and notification queue tables. */
const QUEUE_TABLES = [
  "scheduled_notifications",
  "in_app_notifications",
  "message_notification_outbox",
  "verdict_notification_outbox",
];

/**
 * Every file allowed to touch a queue or send, and exactly what it touches.
 * The four writers the W8 final server review found (send-notification,
 * process-chat-notification-outbox, accept-invite,
 * evaluate-ask2-eligibility), the helper they share, the one deliverer
 * and the one OneSignal caller, and generate-verdict's own outbox. None is
 * a Dating function.
 */
export const ALLOWED: Record<string, string[]> = {
  "_shared/push_queue.ts": ["enqueuePush", "scheduled_notifications"],
  "_shared/onesignal_push.ts": ["onesignal"],
  "send-notification/index.ts": ["enqueuePush"],
  "process-chat-notification-outbox/index.ts": ["enqueuePush", "in_app_notifications", "message_notification_outbox"],
  "accept-invite/accept.ts": ["enqueuePush"],
  "evaluate-ask2-eligibility/index.ts": ["in_app_notifications", "scheduled_notifications"],
  "process-scheduled-notifications/index.ts": ["onesignal", "scheduled_notifications"],
  "generate-verdict/index.ts": ["verdict_notification_outbox"],
  // Spec 2 W9 (carry 2): the check-in reminders call send-notification.
  "send-checkin-reminders/index.ts": ["sendNotification"],
};

const root = new URL("../", import.meta.url);

async function* sources(dir: URL): AsyncGenerator<URL> {
  for await (const e of Deno.readDir(dir)) {
    if (e.isDirectory) {
      if (e.name === "node_modules") continue;
      yield* sources(new URL(`${e.name}/`, dir));
    } else if (/\.(ts|tsx|js|mjs)$/.test(e.name) && !/\.test\.(ts|tsx|js|mjs)$/.test(e.name)) {
      yield new URL(e.name, dir);
    }
  }
}

/**
 * The source with its comments blanked (string and template literals
 * kept, as a table name or a module path lives in one).
 */
export function stripComments(src: string): string {
  let out = "";
  let i = 0;
  let quote: string | null = null;
  while (i < src.length) {
    const c = src[i];
    const next = src[i + 1];
    if (quote !== null) {
      out += c;
      if (c === "\\") {
        out += next ?? "";
        i += 2;
        continue;
      }
      if (c === quote) quote = null;
      i++;
      continue;
    }
    if (c === '"' || c === "'" || c === "`") {
      quote = c;
      out += c;
      i++;
      continue;
    }
    if (c === "/" && next === "/") {
      while (i < src.length && src[i] !== "\n") i++;
      continue;
    }
    if (c === "/" && next === "*") {
      const end = src.indexOf("*/", i + 2);
      i = end < 0 ? src.length : end + 2;
      out += " ";
      continue;
    }
    out += c;
    i++;
  }
  return out;
}

/** What a file's code touches: queue tables, the queue helper, OneSignal,
 * the send-notification function (Spec 2 W9). */
export function touches(src: string): string[] {
  const code = stripComments(src);
  const found = new Set<string>();
  for (const t of QUEUE_TABLES) {
    if (new RegExp(`(?<![A-Za-z0-9_])${t}(?![A-Za-z0-9_])`).test(code)) found.add(t);
  }
  if (/\benqueuePush\b/.test(code) || /push_queue(\.ts)?["'`]/.test(code)) found.add("enqueuePush");
  if (/onesignal\.com/i.test(code) || /\bsendOneSignalPush\b/.test(code) || /onesignal_push(\.ts)?["'`]/.test(code)) {
    found.add("onesignal");
  }
  if (/\.invoke\(\s*["'`]send-notification["'`]/.test(code) || /functions\/v1\/send-notification/.test(code)) {
    found.add("sendNotification");
  }
  return [...found].sort();
}

Deno.test("only the listed edge functions touch the push queue or send a push", async () => {
  const seen: Record<string, string[]> = {};
  for await (const file of sources(root)) {
    const rel = file.pathname.slice(root.pathname.length);
    const t = touches(await Deno.readTextFile(file));
    if (t.length > 0) seen[rel] = t;
  }
  const sorted = (o: Record<string, string[]>) =>
    Object.fromEntries(Object.keys(o).sort().map((k) => [k, [...o[k]].sort()]));
  assertEquals(sorted(seen), sorted(ALLOWED));
});

Deno.test("no Dating edge function is a push writer", () => {
  assertEquals(Object.keys(ALLOWED).filter((f) => /dating/i.test(f)), []);
});

Deno.test("the detector sees each kind of writer and ignores comments", () => {
  assertEquals(touches(`await db.from("scheduled_notifications").insert({})`), ["scheduled_notifications"]);
  assertEquals(touches("await db.from(`in_app_notifications`).insert({})"), ["in_app_notifications"]);
  assertEquals(touches(`await fetch(url + "/rest/v1/scheduled_notifications")`), ["scheduled_notifications"]);
  assertEquals(touches(`import { enqueuePush as q } from "../_shared/push_queue.ts";`), ["enqueuePush"]);
  assertEquals(touches(`import * as pq from "../_shared/push_queue.ts";`), ["enqueuePush"]);
  assertEquals(touches(`await fetch("https://api.onesignal.com/notifications", {})`), ["onesignal"]);
  assertEquals(touches(`import { sendOneSignalPush } from "../_shared/onesignal_push.ts";`), ["onesignal"]);
  assertEquals(touches(`// writes scheduled_notifications through enqueuePush\n/* OneSignal */ const x = 1;`), []);
  assertEquals(touches(`const idx = "in_app_notifications_chat_outbox_idx";`), []);
  // Spec 2 W9 (carry 2): calling send-notification sends a push.
  assertEquals(touches(`await supabase.functions.invoke('send-notification', { body })`), ["sendNotification"]);
  assertEquals(touches("await db.functions.invoke(`send-notification`, {})"), ["sendNotification"]);
  assertEquals(touches(`await fetch(url + "/functions/v1/send-notification", {})`), ["sendNotification"]);
  assertEquals(touches(`// functions.invoke('send-notification') is not called here`), []);
});

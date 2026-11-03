// Spec 1 W6a (§4.4 S-8, §4.5): fail-open alerts, against a fake client.
import { ALERT_SOURCES, type AlertClient, sendAlerts } from "./handler.ts";

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

function rig(due: unknown, o: { readFails?: boolean; markFails?: boolean; childDue?: unknown } = {}) {
  const calls: string[] = [];
  const client: AlertClient = {
    rpc(fn, args) {
      calls.push(`${fn}:${JSON.stringify(args ?? {})}`);
      if (fn === "identity_alerts_due") {
        return Promise.resolve(o.readFails ? { data: null, error: { message: "boom" } } : { data: due, error: null });
      }
      if (fn === "child_safety_alerts_due") {
        return Promise.resolve({ data: o.childDue ?? { ids: [], count: 0, first_at: null, last_at: null }, error: null });
      }
      // Every other source (batch 3: stuck parks, parked accounts kept for a
      // review) has nothing due here.
      if (fn.endsWith("_due")) {
        return Promise.resolve({ data: { ids: [], count: 0, first_at: null, last_at: null }, error: null });
      }
      return Promise.resolve({ data: null, error: o.markFails ? { message: "boom" } : null });
    },
  };
  return { client, calls };
}

const DUE = { ids: [7, 8, 9], count: 3, first_at: "2026-11-03T10:00:00Z", last_at: "2026-11-03T10:05:00Z" };

Deno.test("due fail-opens: one message, counts and times only, then marked", async () => {
  const r = rig(DUE);
  const posts: string[] = [];
  const result = await sendAlerts(r.client, "https://hooks.example/x", async (_url, body) => {
    posts.push(body);
    return { ok: true, status: 200 };
  });
  assert(result.hook_fail_open === "sent", JSON.stringify(result));
  assert(posts.length === 1, `posts ${posts.length}`);
  const text = JSON.parse(posts[0]).text as string;
  assert(text.includes("3 time(s)") && text.includes("2026-11-03T10:00:00Z") && text.includes("incident"), text);
  assert(Object.keys(JSON.parse(posts[0])).join(",") === "text", posts[0]);
  assert(r.calls[1] === 'mark_identity_alerts_sent:{"p_ids":[7,8,9]}', r.calls.join(" "));
});

Deno.test("nothing due posts nothing; a failed post or no webhook marks nothing", async () => {
  let posted = 0;
  const post = async () => {
    posted++;
    return { ok: false, status: 500 };
  };
  const none = rig({ ids: [], count: 0, first_at: null, last_at: null });
  assert((await sendAlerts(none.client, "https://hooks.example/x", post)).hook_fail_open === "none", "none");
  assert(posted === 0, "posted for nothing");
  const failed = rig(DUE);
  assert((await sendAlerts(failed.client, "https://hooks.example/x", post)).hook_fail_open === "post_failed", "failed");
  assert(!failed.calls.some((c) => c.startsWith("mark_")), "marked after a failed post");
  const thrown = rig(DUE);
  const result = await sendAlerts(thrown.client, "https://hooks.example/x", () => Promise.reject(new Error("dns")));
  assert(result.hook_fail_open === "post_failed" && !thrown.calls.some((c) => c.startsWith("mark_")), "thrown");
  const unset = rig(DUE);
  assert((await sendAlerts(unset.client, undefined, post)).hook_fail_open === "not_configured", "unset");
  assert(!unset.calls.some((c) => c.startsWith("mark_")), "marked with no webhook");
});

Deno.test("W6c: new child-safety reports post a count and a time, never the words, then are marked", async () => {
  const reportId = "8af0ab2d-8d85-4f80-8c49-e9ff2b1ec04b";
  const r = rig({ ids: [], count: 0, first_at: null, last_at: null }, {
    childDue: { ids: [reportId], count: 1, first_at: "2026-11-03T11:00:00Z", last_at: "2026-11-03T11:00:00Z" },
  });
  const posts: string[] = [];
  const result = await sendAlerts(r.client, "https://hooks.example/x", async (_url, body) => {
    posts.push(body);
    return { ok: true, status: 200 };
  });
  assert(result.hook_fail_open === "none" && result.child_safety_report === "sent", JSON.stringify(result));
  assert(posts.length === 1, `posts ${posts.length}`);
  const text = JSON.parse(posts[0]).text as string;
  assert(text.includes("1 new report(s) of a concern about a child") && text.includes("2026-11-03T11:00:00Z"), text);
  assert(!text.includes(reportId), "the report's id was posted");
  assert(r.calls.at(-1) === `mark_child_safety_alerts_sent:{"p_ids":["${reportId}"]}`, r.calls.join(" "));
});

Deno.test("a failed read or mark is reported, never thrown", async () => {
  const ok = async () => ({ ok: true, status: 200 });
  assert((await sendAlerts(rig(DUE, { readFails: true }).client, "https://x", ok)).hook_fail_open === "read_failed", "read");
  assert((await sendAlerts(rig(DUE, { markFails: true }).client, "https://x", ok)).hook_fail_open === "mark_failed", "mark");
});

// Batch 3 (preflight F4; batch 2 review M-4 ruling): two more sources,
// each one message of counts and times, marked by its own RPC.
const P1 = "5f6a0000-0000-0000-0000-0000000000d1";
const K1 = "5f6a0000-0000-0000-0000-0000000000e1";
const K2 = "5f6a0000-0000-0000-0000-0000000000e2";

function rigDues(dues: Record<string, unknown>, failMark: string | null = null) {
  const calls: string[] = [];
  const client: AlertClient = {
    rpc(fn, args) {
      calls.push(`${fn}:${JSON.stringify(args ?? {})}`);
      if (fn.endsWith("_due")) {
        return Promise.resolve({ data: dues[fn] ?? { ids: [], count: 0, first_at: null, last_at: null }, error: null });
      }
      return Promise.resolve({ data: null, error: fn === failMark ? { message: "boom" } : null });
    },
  };
  return { client, calls };
}

Deno.test("a stuck park and a parked account kept for a review each post counts and times, then are marked", async () => {
  const names = ALERT_SOURCES.map((s) => s.name);
  assert(
    names.includes("hook_fail_open") && names.includes("fresh_start_unparked") && names.includes("parked_kept_for_review"),
    names.join(","),
  );
  const r = rigDues({
    fresh_start_park_alerts_due: { ids: [P1], count: 1, first_at: "2026-11-03T09:00:00Z", last_at: "2026-11-03T09:00:00Z" },
    parked_kept_for_review_alerts_due: { ids: [K1, K2], count: 2, first_at: "2026-10-01T00:00:00Z", last_at: "2026-10-02T00:00:00Z" },
  });
  const posts: string[] = [];
  const result = await sendAlerts(r.client, "https://hooks.example/x", async (_url, body) => {
    posts.push(body);
    return { ok: true, status: 200 };
  });
  assert(
    result.hook_fail_open === "none" && result.fresh_start_unparked === "sent" && result.parked_kept_for_review === "sent",
    JSON.stringify(result),
  );
  assert(posts.length === 2, `posts ${posts.length}`);
  const [park, kept] = posts.map((p) => JSON.parse(p).text as string);
  assert(park.includes("1 fresh start(s)") && park.includes("2026-11-03T09:00:00Z") && park.includes("+999"), park);
  assert(kept.includes("2 parked account(s)") && kept.includes("2026-10-01T00:00:00Z") && kept.includes("review"), kept);
  for (const body of posts) {
    assert(Object.keys(JSON.parse(body)).join(",") === "text", body);
    assert(![P1, K1, K2].some((id) => body.includes(id)), `an id was posted: ${body}`);
  }
  assert(r.calls.includes(`mark_fresh_start_park_alerts_sent:{"p_ids":["${P1}"]}`), r.calls.join(" "));
  assert(r.calls.includes(`mark_parked_kept_for_review_alerts_sent:{"p_ids":["${K1}","${K2}"]}`), r.calls.join(" "));
});

Deno.test("one source's failed post or mark never stops or marks another", async () => {
  const dues = {
    fresh_start_park_alerts_due: { ids: [P1], count: 1, first_at: "2026-11-03T09:00:00Z", last_at: "2026-11-03T09:00:00Z" },
    parked_kept_for_review_alerts_due: { ids: [K1], count: 1, first_at: "2026-10-01T00:00:00Z", last_at: "2026-10-01T00:00:00Z" },
  };
  const r = rigDues(dues);
  const result = await sendAlerts(r.client, "https://hooks.example/x", (_url, body) =>
    Promise.resolve(body.includes("fresh start") ? { ok: false, status: 502 } : { ok: true, status: 200 }));
  assert(result.fresh_start_unparked === "post_failed" && result.parked_kept_for_review === "sent", JSON.stringify(result));
  assert(!r.calls.some((c) => c.startsWith("mark_fresh_start_park_alerts_sent")), r.calls.join(" "));
  const m = rigDues(dues, "mark_fresh_start_park_alerts_sent");
  const marked = await sendAlerts(m.client, "https://hooks.example/x", () => Promise.resolve({ ok: true, status: 200 }));
  assert(marked.fresh_start_unparked === "mark_failed" && marked.parked_kept_for_review === "sent", JSON.stringify(marked));
});

// Fix round 1 M-3: a recovery-hold purge that failed in 3 runs goes to the
// back of the purge list, is counted in identity health and alerted once.
Deno.test("a purge stuck after 3 failed runs posts a count and a time, then is marked", async () => {
  assert(ALERT_SOURCES.some((s) => s.name === "recovery_purge_stuck"), ALERT_SOURCES.map((s) => s.name).join(","));
  const r = rigDues({
    recovery_purge_stuck_alerts_due: { ids: [K1], count: 1, first_at: "2026-10-05T00:00:00Z", last_at: "2026-10-05T00:00:00Z" },
  });
  const posts: string[] = [];
  const result = await sendAlerts(r.client, "https://hooks.example/x", async (_url, body) => {
    posts.push(body);
    return { ok: true, status: 200 };
  });
  assert(result.recovery_purge_stuck === "sent" && posts.length === 1, JSON.stringify(result));
  const text = JSON.parse(posts[0]).text as string;
  assert(text.includes("1 parked account(s)") && text.includes("3") && text.includes("2026-10-05T00:00:00Z"), text);
  assert(!posts[0].includes(K1), `an id was posted: ${posts[0]}`);
  assert(r.calls.includes(`mark_recovery_purge_stuck_alerts_sent:{"p_ids":["${K1}"]}`), r.calls.join(" "));
});

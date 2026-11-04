// supabase/functions/scan-media/accept.ts
//
// Spec 1 W7b (B6 fix I-1): the scan-media cron calls through pg_net
// (public.invoke_edge_function), which gives up after 5 s, while a run can
// take up to about two minutes. So scan-media answers 202 as soon as it
// has taken the run and runs it in EdgeRuntime.waitUntil, as
// build-data-exports, process-story-archival and
// process-scheduled-notifications (accept.ts, whose shape this is) do.
// Background work has the same wall-clock limit, so handler.ts's budget
// still holds. Without that runtime (Deno tests, a plain local serve) the
// run finishes before the answer. The run logs its own counts or failure;
// nothing here logs, and a failure's message never reaches the response.
import { jsonResponse } from "../_shared/attune_auth.ts";

export type WaitUntil = (work: Promise<unknown>) => void;

/** The Supabase edge runtime's waitUntil, or null outside it. */
export function edgeWaitUntil(): WaitUntil | null {
  // deno-lint-ignore no-explicit-any
  const runtime = (globalThis as any).EdgeRuntime;
  return runtime && typeof runtime.waitUntil === "function" ? (work) => runtime.waitUntil(work) : null;
}

export async function acceptAndRun(
  run: () => Promise<Record<string, unknown>>,
  waitUntil: WaitUntil | null = edgeWaitUntil(),
): Promise<Response> {
  if (waitUntil) {
    // Caught here: the run has already logged why.
    waitUntil(run().catch(() => undefined));
    return jsonResponse({ success: true, accepted: true }, 202);
  }
  try {
    return jsonResponse({ success: true, ...(await run()) });
  } catch {
    return jsonResponse({ error: "scan_failed" }, 500);
  }
}

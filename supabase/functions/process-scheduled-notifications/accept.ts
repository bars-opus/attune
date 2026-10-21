// supabase/functions/process-scheduled-notifications/accept.ts
//
// Plan 1b final review M1: the chat outbox worker wakes this sender and
// gives up after 3 s (it must answer pg_net inside ~5 s), while a batch of
// up to 50 sends, one OneSignal round-trip each, can take longer. The
// sender therefore answers 202 as soon as it has accepted the batch and
// runs it in EdgeRuntime.waitUntil, so a wake is "woken" when the sender
// took it, not when the backlog is done. Where no such runtime exists
// (Deno tests, a plain local serve) the batch runs before the answer, as
// it always did. Claim and finish semantics are the batch's own.

import { jsonResponse } from "../_shared/attune_auth.ts";

export type WaitUntil = (work: Promise<unknown>) => void;

/** The Supabase edge runtime's waitUntil, or null outside it. */
export function edgeWaitUntil(): WaitUntil | null {
  // deno-lint-ignore no-explicit-any
  const runtime = (globalThis as any).EdgeRuntime;
  return runtime && typeof runtime.waitUntil === "function"
    ? (work) => runtime.waitUntil(work)
    : null;
}

export async function acceptAndRun(
  run: () => Promise<Record<string, unknown>>,
  waitUntil: WaitUntil | null = edgeWaitUntil(),
): Promise<Response> {
  if (waitUntil) {
    const work = run().catch((error) => {
      console.error("process-scheduled-notifications batch failed", errorCode(error));
    });
    waitUntil(work);
    return jsonResponse({ success: true, accepted: true }, 202);
  }
  try {
    return jsonResponse({ success: true, ...(await run()) });
  } catch (error) {
    return jsonResponse({ success: false, error: errorCode(error) }, 500);
  }
}

function errorCode(error: unknown) {
  const message = error instanceof Error ? error.message : "unknown_error";
  return message.slice(0, 120);
}

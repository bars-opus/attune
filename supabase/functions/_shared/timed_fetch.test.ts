// B6 fix I-2: a fetch that aborts after [ms], keeping the caller's own signal.
import { timedFetch } from "./timed_fetch.ts";

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

const hanging = (_input: RequestInfo | URL, init?: RequestInit) =>
  new Promise<Response>((_resolve, reject) => {
    const guard = setTimeout(() => reject(new Error("never aborted")), 2_000);
    init?.signal?.addEventListener("abort", () => {
      clearTimeout(guard);
      reject(init.signal!.reason);
    });
  });

Deno.test("timedFetch aborts a call that hangs", async () => {
  let error: unknown;
  try {
    await timedFetch(20, hanging)("https://x.invalid/");
  } catch (e) {
    error = e;
  }
  assert(error instanceof DOMException && error.name === "TimeoutError", String(error));
});

Deno.test("timedFetch keeps the caller's signal", async () => {
  const controller = new AbortController();
  const call = timedFetch(5_000, hanging)("https://x.invalid/", { signal: controller.signal });
  controller.abort(new Error("caller"));
  let error: unknown;
  try {
    await call;
  } catch (e) {
    error = e;
  }
  assert(error instanceof Error && error.message === "caller", String(error));
});

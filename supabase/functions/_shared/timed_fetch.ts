// supabase/functions/_shared/timed_fetch.ts
//
// A fetch that gives up after [ms], keeping the caller's own signal (B6 fix
// I-2), so a hung Storage or RPC call is aborted, not just abandoned. The
// same shape as process-story-archival's (06 #23), which is left as it is.
export type FetchLike = (input: RequestInfo | URL, init?: RequestInit) => Promise<Response>;

export function timedFetch(ms: number, base: FetchLike = fetch): FetchLike {
  return (input, init) => {
    const timeout = AbortSignal.timeout(ms);
    const signal = init?.signal ? AbortSignal.any([init.signal, timeout]) : timeout;
    return base(input, { ...init, signal });
  };
}

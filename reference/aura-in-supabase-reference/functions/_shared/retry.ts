// supabase/functions/_shared/retry.ts
//
// Exponential-backoff retry for transient failures (network blips, provider
// 5xx, rate-limit 429). Caller declares which errors are retryable.

export interface RetryOptions {
  /** Total number of attempts including the first. Default 3. */
  attempts?: number;
  /** Base delay in ms. Each retry doubles. Default 500ms. */
  baseDelayMs?: number;
  /** Optional jitter cap in ms added to each backoff. Default 100ms. */
  jitterMs?: number;
  /** Decide whether an error is transient. Default: HTTP 5xx + 429 + network. */
  isRetryable?: (err: unknown) => boolean;
  /** Label for logs. Default 'op'. */
  label?: string;
}

/** Default retryable check: 5xx, 429, or fetch network error. */
export function defaultIsRetryable(err: unknown): boolean {
  if (err instanceof Response) {
    return err.status >= 500 || err.status === 429;
  }
  if (err instanceof Error) {
    const m = err.message.toLowerCase();
    return (
      m.includes('network') ||
      m.includes('timeout') ||
      m.includes('econnreset') ||
      m.includes('socket')
    );
  }
  return false;
}

/**
 * Run `fn` with exponential backoff. Returns the result of the last attempt
 * (resolved or thrown). Retries only when `isRetryable(err)` returns true.
 */
export async function retry<T>(
  fn: () => Promise<T>,
  opts: RetryOptions = {},
): Promise<T> {
  const attempts = Math.max(1, opts.attempts ?? 3);
  const baseDelay = opts.baseDelayMs ?? 500;
  const jitter = opts.jitterMs ?? 100;
  const isRetryable = opts.isRetryable ?? defaultIsRetryable;
  const label = opts.label ?? 'op';

  let lastErr: unknown;
  for (let i = 0; i < attempts; i++) {
    try {
      return await fn();
    } catch (err) {
      lastErr = err;
      const final = i === attempts - 1;
      if (final || !isRetryable(err)) throw err;
      const wait = baseDelay * Math.pow(2, i) + Math.random() * jitter;
      console.warn(
        `↻ ${label} attempt ${i + 1}/${attempts} failed (${
          err instanceof Error ? err.message : String(err)
        }) — retrying in ${Math.round(wait)}ms`,
      );
      await new Promise((r) => setTimeout(r, wait));
    }
  }
  throw lastErr;
}

/**
 * Convenience wrapper around `fetch` that retries on transient HTTP failures
 * and surfaces non-2xx as thrown Response objects so the caller can branch
 * on `instanceof Response`.
 */
export async function retryFetch(
  input: string,
  init?: RequestInit,
  opts?: Omit<RetryOptions, 'isRetryable'> & {
    /** Treat these statuses as terminal (don't retry). Default: 4xx except 429. */
    nonRetryableStatuses?: number[];
  },
): Promise<Response> {
  return retry<Response>(
    async () => {
      const resp = await fetch(input, init);
      if (!resp.ok) {
        const isClientErr = resp.status >= 400 && resp.status < 500;
        const nonRetryable = (opts?.nonRetryableStatuses ?? []).includes(
          resp.status,
        );
        if (nonRetryable || (isClientErr && resp.status !== 429)) {
          // Drain the body so the consumer can read the error before throwing.
          const text = await resp.text();
          throw new Error(`HTTP ${resp.status}: ${text || resp.statusText}`);
        }
        throw resp;
      }
      return resp;
    },
    { ...opts, label: opts?.label ?? `fetch ${input}` },
  );
}

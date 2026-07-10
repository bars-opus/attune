// Rate limiting for guest-facing edge functions.
//
// Reads the caller's IP from CF-Connecting-IP / X-Forwarded-For / X-Real-IP
// (Supabase puts the originating IP in one of these depending on the network
// path) and falls back to "unknown" for direct test invocations.
//
// Returns { allowed: boolean, remainingMs?: number }. On allowed=false the
// caller should reply 429 with a Retry-After header.
//
// Fails open on DB errors (logs the issue and lets the request through). The
// rate limit is defense-in-depth; if the DB is down we have bigger problems.

import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";
import { redactError } from "./sanitize.ts";

export interface RateLimitResult {
  allowed: boolean;
  retryAfterSeconds: number;
}

/**
 * Extract the client IP from common reverse-proxy headers. Falls back to
 * "unknown" for direct/test invocations (which still get rate-limited but
 * as one shared bucket).
 */
export function getClientIp(req: Request): string {
  const cf = req.headers.get("CF-Connecting-IP");
  if (cf) return cf;
  const xff = req.headers.get("X-Forwarded-For");
  if (xff) return xff.split(",")[0].trim();
  const xr = req.headers.get("X-Real-IP");
  if (xr) return xr;
  return "unknown";
}

/**
 * Check whether `req` is allowed to call `endpoint`. Wraps the
 * check_rate_limit RPC.
 */
export async function checkRateLimit(
  supabase: SupabaseClient,
  endpoint: string,
  req: Request,
  opts: { max: number; windowSeconds: number },
): Promise<RateLimitResult> {
  const ip = getClientIp(req);
  const key = `${endpoint}:${ip}`;

  try {
    const { data, error } = await supabase.rpc("check_rate_limit", {
      p_key: key,
      p_max: opts.max,
      p_window_seconds: opts.windowSeconds,
    });
    if (error) {
      console.error("rate_limit RPC error (failing open):", redactError(error));
      return { allowed: true, retryAfterSeconds: 0 };
    }
    return {
      allowed: data === true,
      retryAfterSeconds: data === true ? 0 : opts.windowSeconds,
    };
  } catch (e) {
    console.error("rate_limit threw (failing open):", redactError(e));
    return { allowed: true, retryAfterSeconds: 0 };
  }
}

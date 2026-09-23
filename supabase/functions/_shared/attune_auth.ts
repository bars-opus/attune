import { createClient, SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";

export interface AuthenticatedUser {
  id: string;
  email: string | null;
  phone: string | null;
}

export function jsonResponse(
  body: Record<string, unknown>,
  status = 200,
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json",
    },
  });
}

export function requireEnv(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`Missing environment variable: ${name}`);
  return value;
}

export function serviceRoleClient() {
  return createClient(
    requireEnv("SUPABASE_URL"),
    requireEnv("SUPABASE_SERVICE_ROLE_KEY"),
    {
      auth: {
        persistSession: false,
        autoRefreshToken: false,
      },
    },
  );
}

export function requireServiceRole(req: Request): void {
  const authorization = req.headers.get("Authorization") ?? "";
  const token = authorization.replace(/^Bearer\s+/i, "").trim();
  if (!token || token !== requireEnv("SUPABASE_SERVICE_ROLE_KEY")) {
    throw new HttpError("Forbidden", 403);
  }
}

export async function requireUser(req: Request): Promise<AuthenticatedUser> {
  const authorization = req.headers.get("Authorization") ?? "";
  const token = authorization.replace(/^Bearer\s+/i, "").trim();
  if (!token) throw new HttpError("Missing authorization token", 401);

  const supabase = serviceRoleClient();
  const { data, error } = await supabase.auth.getUser(token);
  if (error || !data.user) {
    throw new HttpError("Invalid authorization token", 401);
  }

  return {
    id: data.user.id,
    email: data.user.email ?? null,
    phone: data.user.phone ?? null,
  };
}

export class HttpError extends Error {
  constructor(message: string, readonly status: number) {
    super(message);
    this.name = "HttpError";
  }
}

/// Claims this request's provider-start marker via the trusted RPC, and
/// returns whether THIS call is the one that claimed it. `false` means
/// the marker was already set (a retry, a duplicate, or a concurrent
/// call for the same request_id) -- the caller must not dispatch to any
/// provider in that case. See migration 20260952010000 and spec §6.2/
/// §8.2.2 for why this check happens once, immediately before the FIRST
/// external call a request makes, never repeated per-provider within
/// one request (Nearby's Gemini-then-Mapbox pair shares one claim).
///
/// Unreachable via current entrypoints by design: on the two shipped
/// callers (ai-assist, ai-understand), a replayed request_id is already
/// rejected by reserve_ai_assistant_quota's own already_reserved check
/// before this function is ever called, so it always returns true today.
/// Do not remove as dead code -- required for Plan B's Sessions dispatch
/// RPC, which reserves once and can dispatch to a provider more than
/// once across retries.
export async function claimProviderStart(
  service: SupabaseClient,
  actorId: string,
  requestId: string,
): Promise<boolean> {
  const result = await service.rpc("claim_ai_assistant_provider_start", {
    p_actor_id: actorId,
    p_request_id: requestId,
  });
  if (result.error) {
    throw new Error(`claim_ai_assistant_provider_start failed: ${result.error.message}`);
  }
  // RETURNS boolean (not TABLE) -- supabase-js/PostgREST wraps a scalar
  // RPC return in [{ <function_name>: value }], and this test suite's
  // pg_rls_client.ts RpcCaller mirrors that exact shape (see its own
  // doc comment on why RPC results are always an array of rows).
  const row = result.data?.[0] as Record<string, unknown> | undefined;
  return row?.claim_ai_assistant_provider_start === true;
}

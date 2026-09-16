// A Supabase client scoped to the calling user's own JWT, so every query
// issued through it runs under RLS as that user -- not the service-role
// key every other edge function in this codebase uses today.
//
// Spec: docs/superpowers/specs/2026-09-15-ai-assistant-design.md §4.2.
// "Each function uses a user-JWT-scoped Supabase client for content
// reads -- not an unrestricted service-role read." This is new
// infrastructure: no existing edge function in this repository does
// this (verified: every one of analyse-message, analyse-session,
// translate-conflict, generate-verdict, etc. reads via
// serviceRoleClient() and authorizes by hand in application code).
// Building this helper, and using it for every content read in
// ai-assist/ai-understand, is what makes "the client cannot fabricate
// context" a database-enforced guarantee rather than an
// application-code promise.

import { createClient, SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";
import { requireEnv, requireUser, AuthenticatedUser } from "./attune_auth.ts";

export interface UserScopedContext {
  client: SupabaseClient;
  user: AuthenticatedUser;
}

export async function userScopedClient(req: Request): Promise<UserScopedContext> {
  // requireUser already validates the bearer token via auth.getUser and
  // throws HttpError(401) on failure -- reuse it rather than re-deriving
  // the same check, so both functions fail identically to every other
  // authenticated edge function in this codebase.
  const user = await requireUser(req);

  const authorization = req.headers.get("Authorization") ?? "";
  const token = authorization.replace(/^Bearer\s+/i, "").trim();

  const client = createClient(
    requireEnv("SUPABASE_URL"),
    requireEnv("SUPABASE_ANON_KEY"),
    {
      global: { headers: { Authorization: `Bearer ${token}` } },
      auth: { persistSession: false, autoRefreshToken: false },
    },
  );

  return { client, user };
}

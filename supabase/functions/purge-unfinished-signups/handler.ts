// supabase/functions/purge-unfinished-signups/handler.ts
//
// Spec 1 W1c (§4.5, §4.8): an Auth user that never finished sign-up (no
// public.users row) is deleted once it has been idle for 24 hours. "Not now"
// at consent and an abandoned code both leave one behind; signInWithOtp
// creates the Auth user before anything else.
//
// Batch 5 review #1: idle means no activity (created, signed in or updated)
// for 24 hours, and each id is re-checked with is_unfinished_signup just
// before its delete, so an account that came back to finish signing up after
// the list was read is skipped, never deleted.
// Batch 5 review #8: the job runs hourly, and a run starts no new delete
// after RUN_BUDGET_MS; what it leaves is reported as `remaining` and picked
// up by the next run.
//
// Logs and returns counts only, never an id or a phone (spec §4.1 rule 5).

type RpcResult = PromiseLike<{ data: unknown; error: { message: string } | null }>;

export interface PurgeClient {
  rpc(fn: "unfinished_signup_candidates" | "is_unfinished_signup", args?: { p_user_id: string }): RpcResult;
  auth: {
    admin: {
      deleteUser(id: string): PromiseLike<{ error: { message: string } | null }>;
    };
  };
}

export interface PurgeResult {
  candidates: number;
  deleted: number;
  failed: number;
  skipped: number;
  remaining: number;
}

export interface PurgeOptions {
  /** Milliseconds since some fixed point; injected by tests. */
  now?: () => number;
  /** No new delete starts once this much time has passed since the start. */
  budgetMs?: number;
}

/** About a minute: well inside the edge function wall clock. */
export const RUN_BUDGET_MS = 60_000;

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/// A SETOF uuid comes back as bare values or as one-key rows depending on
/// the PostgREST version; both are read, anything else is skipped.
export function candidateIds(data: unknown): string[] {
  if (!Array.isArray(data)) return [];
  const ids: string[] = [];
  for (const row of data) {
    const value = typeof row === "string"
      ? row
      : row !== null && typeof row === "object"
      ? Object.values(row as Record<string, unknown>)[0]
      : null;
    if (typeof value === "string" && UUID.test(value)) ids.push(value);
  }
  return ids;
}

export async function purgeUnfinishedSignups(
  client: PurgeClient,
  options: PurgeOptions = {},
): Promise<PurgeResult> {
  const now = options.now ?? Date.now;
  const budgetMs = options.budgetMs ?? RUN_BUDGET_MS;
  const startedAt = now();
  const { data, error } = await client.rpc("unfinished_signup_candidates");
  if (error) throw new Error("unfinished_signup_candidates_failed");
  const ids = candidateIds(data);
  let deleted = 0;
  let failed = 0;
  let skipped = 0;
  let remaining = 0;
  for (let i = 0; i < ids.length; i++) {
    if (now() - startedAt >= budgetMs) {
      remaining = ids.length - i;
      break;
    }
    const id = ids[i];
    try {
      const { data: stillUnfinished, error: recheckError } = await client.rpc("is_unfinished_signup", {
        p_user_id: id,
      });
      if (recheckError) {
        failed++;
        continue;
      }
      if (stillUnfinished !== true) {
        skipped++;
        continue;
      }
      const { error: deleteError } = await client.auth.admin.deleteUser(id);
      if (deleteError) {
        failed++;
      } else {
        deleted++;
      }
    } catch {
      failed++;
    }
  }
  return { candidates: ids.length, deleted, failed, skipped, remaining };
}

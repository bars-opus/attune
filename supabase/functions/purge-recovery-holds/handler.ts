// supabase/functions/purge-recovery-holds/handler.ts
//
// Spec 1 W6a (§4.5, §4.8): an account parked for a fresh start is kept for
// 180 days of support-only recovery, then deleted through the existing
// deletion path: prepare_account_deletion, then auth.admin.deleteUser
// (delete-account's order; its cascade reaches everything below
// public.users). Spec 2's deletion steps read parked_phone_hmac, so carry-
// over follows the real number, not +999. Each id is re-checked with
// is_recovery_hold_due just before its delete (support may have resolved
// the hold since the list was read), and no new delete starts after
// RUN_BUDGET_MS. Logs and returns counts only.
//
// Preflight F8: like delete-account, each delete first writes an
// account_deletion_requests row (no FK to users, so it outlives the
// account), then sets completed_at, or failure_reason as a code
// (recovery_purge:prepare|delete, never an error's text). No row, no
// delete: a real account is never destroyed without evidence. The row's
// source is 'recovery_purge' (batch 3 fix M-2; a person's own deletion
// leaves it NULL), and three failed rows for one hold send that account to
// the back of recovery_hold_candidates, counted and alerted as
// recovery_purge_stuck (fix M-3), so it can never block the queue.
type RpcResult = PromiseLike<{ data: unknown; error: { message: string } | null }>;

export interface RecoveryPurgeClient {
  rpc(
    fn: "recovery_hold_candidates" | "is_recovery_hold_due" | "prepare_account_deletion",
    args?: Record<string, unknown>,
  ): RpcResult;
  from(table: "account_deletion_requests"): {
    insert(row: { user_ref: string; source: "recovery_purge" }): {
      select(columns: "id"): {
        maybeSingle(): PromiseLike<{ data: { id: string } | null; error: { message: string } | null }>;
      };
    };
    update(values: { completed_at?: string; failure_reason?: string }): {
      eq(column: "id", value: string): PromiseLike<{ error: { message: string } | null }>;
    };
  };
  auth: {
    admin: {
      deleteUser(id: string): PromiseLike<{ error: { message: string } | null }>;
    };
  };
}

export interface RecoveryPurgeResult {
  candidates: number;
  deleted: number;
  failed: number;
  skipped: number;
  remaining: number;
}

export const RUN_BUDGET_MS = 60_000;

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/// Bare values or one-key rows, whichever PostgREST sends; anything else is
/// skipped.
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

export async function purgeRecoveryHolds(
  client: RecoveryPurgeClient,
  options: { now?: () => number; budgetMs?: number } = {},
): Promise<RecoveryPurgeResult> {
  const now = options.now ?? Date.now;
  const budgetMs = options.budgetMs ?? RUN_BUDGET_MS;
  const startedAt = now();
  const { data, error } = await client.rpc("recovery_hold_candidates");
  if (error) throw new Error("recovery_hold_candidates_failed");
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
      const { data: due, error: recheckError } = await client.rpc("is_recovery_hold_due", { p_user: id });
      if (recheckError) {
        failed++;
        continue;
      }
      if (due !== true) {
        skipped++;
        continue;
      }
      const { data: audit, error: auditError } = await client
        .from("account_deletion_requests")
        .insert({ user_ref: id, source: "recovery_purge" })
        .select("id")
        .maybeSingle();
      if (auditError || !audit?.id) {
        failed++;
        continue;
      }
      // Best effort after the row exists (delete-account's rule): a failed
      // update never turns a delete into a failure or a failure into a retry.
      const record = async (values: { completed_at?: string; failure_reason?: string }) => {
        try {
          await client.from("account_deletion_requests").update(values).eq("id", audit.id);
        } catch {
          // The row stays without an outcome; the count is already right.
        }
      };
      const { error: prepareError } = await client.rpc("prepare_account_deletion", { p_user_id: id });
      if (prepareError) {
        failed++;
        await record({ failure_reason: "recovery_purge:prepare" });
        continue;
      }
      const { error: deleteError } = await client.auth.admin.deleteUser(id);
      if (deleteError) {
        failed++;
        await record({ failure_reason: "recovery_purge:delete" });
      } else {
        deleted++;
        await record({ completed_at: new Date().toISOString() });
      }
    } catch {
      failed++;
    }
  }
  return { candidates: ids.length, deleted, failed, skipped, remaining };
}

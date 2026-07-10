// supabase/functions/_shared/audit.ts
//
// Records sensitive payment operations to `payment_audit_log` via the
// SECURITY DEFINER `record_payment_audit` RPC. Failures are logged but never
// propagate — audit can never block the caller's primary operation.
//
// Usage:
//   await audit(supabase, {
//     action: 'subaccount.create',
//     actorUserId: user.id,
//     shopId,
//     targetId: recipientCode,
//     outcome: 'success',
//     context: { provider: 'paystack', currency: 'GHS' },
//   });

import { redactForLog } from "./sanitize.ts";

export type AuditOutcome = 'success' | 'failure' | 'denied';

export interface AuditEntry {
  /** Short verb.noun identifier, ≤ 64 chars. e.g. 'subaccount.create'. */
  action: string;
  actorUserId?: string | null;
  shopId?: string | null;
  /** Domain identifier — recipient code, withdrawal id, payment intent, etc. */
  targetId?: string | null;
  outcome: AuditOutcome;
  /** Free-form structured context. Redacted before send. */
  context?: Record<string, unknown>;
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
type SupabaseLike = { rpc: (fn: string, params: Record<string, unknown>) => Promise<{ error: unknown }> };

export async function audit(
  supabase: SupabaseLike,
  entry: AuditEntry,
): Promise<void> {
  try {
    const { error } = await supabase.rpc('record_payment_audit', {
      p_action: entry.action.slice(0, 64),
      p_actor_user_id: entry.actorUserId ?? null,
      p_shop_id: entry.shopId ?? null,
      p_target_id: entry.targetId ?? null,
      p_outcome: entry.outcome,
      p_context: redactForLog(entry.context ?? {}),
    });
    if (error) {
      console.error('audit insert failed:', (error as Error).message);
    }
  } catch (e) {
    console.error('audit threw:', (e as Error).message);
  }
}

// supabase/functions/process-withdrawal/index.ts

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";
import {
  isDebugLogging,
  redactForLog,
  sanitizeIdentifier,
} from "../_shared/sanitize.ts";
import { audit } from "../_shared/audit.ts";
import { getProvider } from "../_shared/providers/registry.ts";
import { PaymentProviderError, type PaymentProviderName } from "../_shared/providers/port.ts";

// ============================================================================
// Configuration
// ============================================================================

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
);

// Internal callers (DB webhook trigger) must include this secret in the Authorization header
const INTERNAL_WEBHOOK_SECRET = Deno.env.get('INTERNAL_WEBHOOK_SECRET');

// ============================================================================
// Main Handler
// ============================================================================

serve(async (req) => {
  // Verify internal caller secret — this endpoint is not user-facing
  if (!INTERNAL_WEBHOOK_SECRET) {
    console.error('❌ INTERNAL_WEBHOOK_SECRET not configured');
    return new Response(JSON.stringify({ error: 'Server misconfiguration' }), { status: 500 });
  }

  const authHeader = req.headers.get('Authorization');
  if (authHeader !== `Bearer ${INTERNAL_WEBHOOK_SECRET}`) {
    return new Response(JSON.stringify({ error: 'Unauthorized' }), { status: 401 });
  }

  try {
    const body = await req.json();
    let withdrawalId: string;
    try {
      withdrawalId = sanitizeIdentifier(body.withdrawal_id, 64);
    } catch (sanErr) {
      return new Response(
        JSON.stringify({ error: (sanErr as Error).message }),
        { status: 400 },
      );
    }

    if (!withdrawalId) {
      return new Response(
        JSON.stringify({ error: 'withdrawal_id required' }),
        { status: 400 }
      );
    }

    const result = await processWithdrawal(withdrawalId);

    return new Response(
      JSON.stringify(result),
      { headers: { 'Content-Type': 'application/json' } }
    );
  } catch (error) {
    console.error('Error processing withdrawal:', (error as Error).message);
    if (isDebugLogging()) {
      console.error('full error:', redactForLog(error));
    }
    return new Response(
      JSON.stringify({ error: (error as Error).message }),
      { status: 500 }
    );
  }
});

// ============================================================================
// Main Processing Logic
// ============================================================================

async function processWithdrawal(withdrawalId: string) {
  console.log(`📦 Processing withdrawal: ${withdrawalId}`);

  // 1. Get withdrawal request with shop details
  const { data: withdrawal, error: fetchError } = await supabase
    .from('withdrawal_requests')
    .select(`
      *,
      shops!inner (
        id,
        user_id,
        shop_name
      )
    `)
    .eq('id', withdrawalId)
    .single();

  if (fetchError || !withdrawal) {
    console.error('Withdrawal not found:', fetchError);
    throw new Error('Withdrawal request not found');
  }

  console.log(`💰 Withdrawal amount: ${withdrawal.amount} ${withdrawal.payment_provider}`);

  // 2. Only process pending withdrawals
  if (withdrawal.status !== 'pending') {
    console.log(`⏭️ Withdrawal already ${withdrawal.status}, skipping`);
    return { success: false, message: `Withdrawal already ${withdrawal.status}` };
  }

  // 3. Update status to processing
  await supabase
    .from('withdrawal_requests')
    .update({ 
      status: 'processing', 
      updated_at: new Date().toISOString() 
    })
    .eq('id', withdrawalId);

  try {
    let transferResult;
    try {
      const provider = getProvider(withdrawal.payment_provider as PaymentProviderName);
      transferResult = await provider.processPayout({
        amount: withdrawal.net_amount ?? withdrawal.amount,
        currency: await getWalletCurrency(withdrawal.shops.id),
        destinationAccountId: withdrawal.transfer_recipient_id,
        reference: withdrawal.idempotency_key,
        reason: "Withdrawal",
      });
    } catch (e) {
      // Preserve PaymentProviderError so the outer catch can branch on
      // `retryable` to decide retry-vs-terminal. The old code re-threw as
      // plain Error which collapsed both paths to "fail immediately".
      throw e;
    }

    // The port returns providerTransferId in the same field shape as before.
    const transferIdForCompletion = transferResult.providerTransferId;

    // 5. Complete withdrawal
    await completeWithdrawal(withdrawalId, transferIdForCompletion);

    await audit(supabase, {
      action: 'withdrawal.complete',
      actorUserId: withdrawal.shops.user_id,
      shopId: withdrawal.shops.id,
      targetId: withdrawalId,
      outcome: 'success',
      context: {
        provider: withdrawal.payment_provider,
        amount: withdrawal.amount,
        net_amount: withdrawal.net_amount,
        transfer_id: transferIdForCompletion,
      },
    });

    // 6. Send success notification (resolve currency from wallet, not hardcoded)
    const currency = await getWalletCurrency(withdrawal.shops.id);
    await sendNotification(
      withdrawal.shops.user_id,
      'success',
      withdrawal.amount,
      withdrawal.net_amount || withdrawal.amount,
      undefined,
      currency,
    );

    console.log(`✅ Withdrawal completed: ${withdrawalId}`);
    return { success: true, transfer: transferResult };

  } catch (error) {
    console.error(`❌ Withdrawal failed for ${withdrawalId}:`, error);

    const isProviderError = error instanceof PaymentProviderError;
    const isRetryable = isProviderError && (error as PaymentProviderError).retryable;
    const errMessage = (error as Error).message;

    if (isRetryable) {
      const nextRunAt = nextAttemptAt(withdrawal.attempt_count ?? 0);

      if (nextRunAt) {
        // Transient failure — schedule retry, leave wallet debited.
        await scheduleWithdrawalRetry(withdrawalId, nextRunAt, errMessage);
        await audit(supabase, {
          action: 'withdrawal.retry_scheduled',
          actorUserId: withdrawal.shops.user_id,
          shopId: withdrawal.shops.id,
          targetId: withdrawalId,
          outcome: 'failure',
          context: {
            provider: withdrawal.payment_provider,
            amount: withdrawal.amount,
            attempt: (withdrawal.attempt_count ?? 0) + 1,
            next_attempt_at: nextRunAt.toISOString(),
            error: errMessage,
          },
        });
        return { success: false, retrying: true, nextAttemptAt: nextRunAt.toISOString() };
      }

      // Retries exhausted — dead-letter (RPC refunds the wallet).
      const reason = `exhausted ${withdrawal.attempt_count ?? 0} retries: ${errMessage}`;
      await deadLetterWithdrawal(withdrawalId, reason);
      await audit(supabase, {
        action: 'withdrawal.dead_letter',
        actorUserId: withdrawal.shops.user_id,
        shopId: withdrawal.shops.id,
        targetId: withdrawalId,
        outcome: 'failure',
        context: {
          provider: withdrawal.payment_provider,
          amount: withdrawal.amount,
          reason,
          last_error: errMessage,
        },
      });
      const dlCurrency = await getWalletCurrency(withdrawal.shops.id);
      await sendDeadLetterNotification(
        withdrawal.shops.user_id,
        withdrawal.amount,
        errMessage,
        dlCurrency,
      );
      return { success: false, dead_letter: true };
    }

    // Non-retryable provider error OR any other Error — terminal failure + refund.
    await failWithdrawal(withdrawalId, errMessage);
    await audit(supabase, {
      action: 'withdrawal.fail',
      actorUserId: withdrawal.shops.user_id,
      shopId: withdrawal.shops.id,
      targetId: withdrawalId,
      outcome: 'failure',
      context: {
        provider: withdrawal.payment_provider,
        amount: withdrawal.amount,
        error: errMessage,
      },
    });
    const currency = await getWalletCurrency(withdrawal.shops.id);
    await sendNotification(
      withdrawal.shops.user_id,
      'failure',
      withdrawal.amount,
      withdrawal.net_amount || withdrawal.amount,
      errMessage,
      currency,
    );
    return { success: false, error: errMessage };
  }
}

// ============================================================================
// Database Operations
// ============================================================================

async function completeWithdrawal(withdrawalId: string, providerTransferId: string) {
  const { error } = await supabase.rpc('complete_withdrawal', {
    p_withdrawal_id: withdrawalId,
    p_provider_transfer_id: providerTransferId,
  });

  if (error) {
    console.error('Failed to complete withdrawal in DB:', error);
    throw new Error('Failed to update withdrawal status');
  }
}

async function failWithdrawal(withdrawalId: string, reason: string) {
  const { error } = await supabase.rpc('fail_withdrawal', {
    p_withdrawal_id: withdrawalId,
    p_failed_reason: reason,
  });

  if (error) {
    console.error('Failed to fail withdrawal in DB:', error);
    // Don't throw - we already tried to refund
  }
}

// ============================================================================
// Notifications
// ============================================================================

async function sendNotification(
  userId: string,
  type: 'success' | 'failure',
  amount: number,
  netAmount: number,
  error?: string,
  currency: string = 'GHS',
) {
  try {
    const notification = {
      user_id: userId,
      type: `withdrawal_${type}`,
      title: type === 'success' ? 'Withdrawal Completed' : 'Withdrawal Failed',
      body: type === 'success'
        ? `${currency} ${amount.toFixed(2)} has been sent to your account. Net amount: ${currency} ${netAmount.toFixed(2)}`
        : `Withdrawal of ${currency} ${amount.toFixed(2)} failed: ${error?.substring(0, 200) ?? 'Unknown error'}`,
      metadata: {
        withdrawal_amount: amount,
        net_amount: netAmount,
        currency,
        error: error,
      },
      created_at: new Date().toISOString(),
    };

    await supabase.from('notifications').insert(notification);
    console.log(`📧 Notification sent to user ${userId}`);
  } catch (e) {
    console.error('Failed to send notification:', (e as Error).message);
  }
}

async function getWalletCurrency(shopId: string): Promise<string> {
  try {
    const { data } = await supabase
      .from('wallets')
      .select('currency')
      .eq('shop_id', shopId)
      .maybeSingle();
    return (data?.currency as string | undefined) ?? 'GHS';
  } catch {
    return 'GHS';
  }
}

// ============================================================================
// Retry-queue helpers
// ============================================================================

// Backoff schedule indexed by attempt_count (the number of FAILED attempts so far).
// attempt_count=0 → first retry in 1 min. attempt_count=4 → last retry in 6 h.
// attempt_count >= length → dead-letter (no more retries).
const BACKOFF_SCHEDULE_SECONDS = [
  60,      // +1 minute  (after 1st failure)
  300,     // +5 minutes (after 2nd failure)
  1800,    // +30 min    (after 3rd failure)
  7200,    // +2 hours   (after 4th failure)
  21600,   // +6 hours   (after 5th failure)
];

function nextAttemptAt(currentAttemptCount: number): Date | null {
  if (currentAttemptCount >= BACKOFF_SCHEDULE_SECONDS.length) return null;
  return new Date(
    Date.now() + BACKOFF_SCHEDULE_SECONDS[currentAttemptCount] * 1000,
  );
}

async function scheduleWithdrawalRetry(
  withdrawalId: string,
  nextRunAt: Date,
  lastError: string,
) {
  const { error } = await supabase.rpc('schedule_withdrawal_retry', {
    p_withdrawal_id:   withdrawalId,
    p_next_attempt_at: nextRunAt.toISOString(),
    p_last_error:      lastError.substring(0, 500),
  });
  if (error) {
    console.error('schedule_withdrawal_retry RPC failed:', error);
  }
}

async function deadLetterWithdrawal(withdrawalId: string, reason: string) {
  const { error } = await supabase.rpc('dead_letter_withdrawal', {
    p_withdrawal_id: withdrawalId,
    p_reason:        reason.substring(0, 500),
  });
  if (error) {
    console.error('dead_letter_withdrawal RPC failed:', error);
  }
}

async function sendDeadLetterNotification(
  userId: string,
  amount: number,
  lastError: string,
  currency: string,
) {
  try {
    await supabase.from('notifications').insert({
      user_id: userId,
      type: 'withdrawal_dead_letter',
      title: 'Withdrawal Needs Review',
      body: `Your ${currency} ${amount.toFixed(2)} withdrawal could not be processed after multiple attempts. Our team has been notified and will investigate. You will not be charged.`,
      metadata: {
        withdrawal_amount: amount,
        currency,
        last_error: lastError.substring(0, 200),
      },
      created_at: new Date().toISOString(),
    });
  } catch (e) {
    console.error('Failed to send dead-letter notification:', (e as Error).message);
  }
}
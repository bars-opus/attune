import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";
import {
  isDebugLogging,
  redactForLog,
  sanitizeIdentifier,
} from "../_shared/sanitize.ts";
import { getProvider, isProviderEnabled } from "../_shared/providers/registry.ts";
import { PaymentProviderError, type PaymentProviderName } from "../_shared/providers/port.ts";

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
);

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const json = (data: unknown, status = 200) =>
  new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });

  try {
    // ── Auth ───────────────────────────────────────────────────────────────────
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) return json({ success: false, error: 'Unauthorized' }, 401);

    const { data: { user }, error: authError } = await supabase.auth.getUser(
      authHeader.replace('Bearer ', '')
    );
    if (authError || !user) return json({ success: false, error: 'Invalid token' }, 401);

    const raw = await req.json() as { reference: string; provider: string };
    let reference: string;
    let provider: string;
    try {
      reference = sanitizeIdentifier(raw.reference, 128);
      provider = sanitizeIdentifier(raw.provider, 32);
    } catch (sanErr) {
      return json({ success: false, error: (sanErr as Error).message }, 400);
    }
    if (!reference || !provider) {
      return json({ success: false, error: 'Missing reference or provider' }, 400);
    }

    console.log('🔍 verify-payment called:', reference);
    if (isDebugLogging()) {
      console.log('verify-payment context:', redactForLog({ reference, provider, userId: user.id }));
    }

    // ── Step 1: Check if booking already exists (webhook may have already fired) ─
    const { data: existingBooking } = await supabase
      .from('bookings')
      .select('*')
      .eq('payment_intent_id', reference)
      .maybeSingle();

    if (existingBooking) {
      console.log('✅ Booking already exists:', existingBooking.id);
      return json({ success: true, booking: existingBooking });
    }

    // ── Step 2: Verify the transaction via the provider port ──────────────────
    if (!isProviderEnabled(provider as PaymentProviderName)) {
      return json({ success: false, confirmed: false });
    }
    // Stripe relies exclusively on webhooks — verifyTransaction would return
    // 'pending' until the customer completes checkout. Skip the round-trip and
    // wait for the webhook to fire.
    if (provider !== 'paystack') {
      return json({ success: false, confirmed: false });
    }

    let verification;
    try {
      verification = await getProvider(provider as PaymentProviderName)
        .verifyTransaction({ reference });
    } catch (e) {
      if (e instanceof PaymentProviderError) {
        console.error('Provider verify failed:', e.message);
        return json(
          { success: false, error: 'Provider verification temporarily unavailable, please retry' },
          502,
        );
      }
      throw e;
    }

    console.log('📡 Verify response:', verification.status);
    if (isDebugLogging()) {
      console.log('📡 verify body:', redactForLog(verification));
    }

    if (verification.status !== 'success') {
      return json({ success: false, confirmed: false, paystack_status: verification.status });
    }

    // ── Step 4: Payment confirmed — load the pending_payment record ───────────
    const { data: pending } = await supabase
      .from('pending_payments')
      .select('*')
      .eq('payment_intent_id', reference)
      .maybeSingle();

    if (!pending) {
      console.error('❌ Payment confirmed by Paystack but no pending_payment found:', reference);
      return json({ success: false, error: 'Payment confirmed but booking data not found. Contact support.' });
    }

    // If pending is already completed (race with webhook), fetch the booking
    if (pending.status === 'completed' && pending.booking_id) {
      const { data: completedBooking } = await supabase
        .from('bookings').select('*').eq('id', pending.booking_id).maybeSingle();
      if (completedBooking) {
        console.log('✅ Pending already completed — returning existing booking:', completedBooking.id);
        return json({ success: true, booking: completedBooking });
      }
    }

    const bookingData = pending.booking_data;
    const paidAmount = verification.amount;

    // ── Step 5: Create the booking ────────────────────────────────────────────
    // bookings table columns (from BookingModel.toJson):
    //   id, user_id, shop_id, booking_date, start_time, end_time,
    //   actual_end_time, status, total_amount, deposit_amount, platform_fee,
    //   payment_method, payment_status, payment_intent_id, created_at, updated_at
    // NOT present: services (JSONB), payment_provider
    const { data: newBooking, error: bookingError } = await supabase
      .from('bookings')
      .insert({
        shop_id: pending.shop_id,
        user_id: pending.user_id,
        booking_date: bookingData.startTime,   // required — use start_time as date
        payment_intent_id: reference,
        payment_method: pending.payment_provider, // column is payment_method
        payment_status: 'paid',
        status: 'confirmed',
        total_amount: pending.amount,
        deposit_amount: bookingData.depositAmount,
        platform_fee: bookingData.platformFee,
        start_time: bookingData.startTime,
        end_time: bookingData.endTime,
        actual_end_time: bookingData.actualEndTime,
        created_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      })
      .select()
      .single();

    if (bookingError || !newBooking) {
      // Unique constraint race: webhook beat us — check one more time
      const { data: raceBooking } = await supabase
        .from('bookings').select('*').eq('payment_intent_id', reference).maybeSingle();
      if (raceBooking) {
        console.log('✅ Race resolved — booking created by webhook:', raceBooking.id);
        return json({ success: true, booking: raceBooking });
      }
      console.error('❌ Failed to create booking:', bookingError);
      return json({ success: false, error: `Failed to create booking: ${bookingError?.message}` });
    }

    // ── Step 5b: Insert booking_services rows ─────────────────────────────────
    if (Array.isArray(bookingData.services) && bookingData.services.length > 0) {
      const serviceRows = (bookingData.services as any[]).map((s: any) => ({
        booking_id: newBooking.id,
        slot_id: s.slotId,
        worker_id: s.workerId ?? null,
        price_at_booking: s.priceAtBooking,
        duration_minutes: s.durationMinutes,
        service_name: s.serviceName,
        worker_name: s.workerName ?? null,
        start_time: bookingData.startTime,
        created_at: new Date().toISOString(),
      }));
      const { error: servicesError } = await supabase.from('booking_services').insert(serviceRows);
      if (servicesError) console.error('⚠️ booking_services insert failed (non-fatal):', servicesError);
    }

    console.log('✅ Booking created via verify-payment:', newBooking.id);

    // Phase 13: record promo redemption if a code was applied at checkout.
    // promotionId + promoAmountOff are carried through pending.booking_data
    // from booking_confirmation_screen.dart → processPayment → create-booking.
    // Non-fatal: if redemption fails, the booking still stands.
    if (bookingData.promotionId) {
      const { error: redeemError } = await supabase.rpc('redeem_promotion', {
        p_promotion_id: bookingData.promotionId,
        p_booking_id: newBooking.id,
        p_user_id: newBooking.user_id,
        p_guest_profile_id: newBooking.guest_profile_id,
        p_discount_amount: bookingData.promoAmountOff ?? 0,
      });
      if (redeemError) {
        console.error('⚠️ promo redemption failed (non-fatal):', redeemError);
      } else {
        console.log(`🎟️  Promo redemption recorded for booking ${newBooking.id}`);
      }
    }

    // ── Step 6: Mark pending payment as completed ─────────────────────────────
    await supabase
      .from('pending_payments')
      .update({
        status: 'completed',
        booking_id: newBooking.id,
        completed_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      })
      .eq('payment_intent_id', reference);

    // ── Step 7: Credit shop wallet ────────────────────────────────────────────
    const platformFee = (bookingData.platformFee as number) ?? 0;
    const netAmount = paidAmount - platformFee;
    const { error: walletError } = await supabase.rpc('add_wallet_transaction', {
      p_shop_id: pending.shop_id,
      p_amount: netAmount,
      p_type: 'deposit',
      p_booking_id: newBooking.id,
      p_description: `Payment for booking ${newBooking.id.substring(0, 8)}`,
      p_reference: reference,
    });
    if (walletError) console.error('⚠️ Wallet credit failed (non-fatal):', walletError);

    // ── Step 8: Schedule notifications ────────────────────────────────────────
    await scheduleBookingNotifications(newBooking, bookingData, pending.shop_id, pending.user_id);

    return json({ success: true, booking: newBooking });

  } catch (error) {
    console.error('verify-payment error:', error);
    return json({ success: false, error: error.message }, 500);
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// Notification scheduling (mirrors paystack-webhook logic)
// Non-fatal: a failure here must never prevent the booking response returning.
// ─────────────────────────────────────────────────────────────────────────────
async function scheduleBookingNotifications(
  booking: { id: string },
  bookingData: any,
  shopId: string,
  clientUserId: string,
): Promise<void> {
  try {
    const now = new Date();
    const startTime = new Date(bookingData.startTime);
    const endTime = new Date(bookingData.actualEndTime ?? bookingData.endTime);

    const serviceNames = (bookingData.services as Array<{ serviceName: string }>)
      .map((s) => s.serviceName)
      .join(', ');

    const formattedTime = startTime.toLocaleString('en-GB', {
      weekday: 'short', day: 'numeric', month: 'short',
      hour: '2-digit', minute: '2-digit',
    });

    const { data: shop } = await supabase
      .from('shops').select('user_id').eq('id', shopId).single();
    const shopOwnerId: string | null = shop?.user_id ?? null;

    // In-app inbox entries
    const inAppRows: any[] = [
      {
        user_id: clientUserId,
        title: 'Booking Confirmed ✅',
        body: `Your ${serviceNames} appointment on ${formattedTime} is confirmed.`,
        data: { type: 'booking_confirmed', booking_id: booking.id, shop_id: shopId },
        is_read: false,
        created_at: now.toISOString(),
      },
    ];
    if (shopOwnerId) {
      inAppRows.push({
        user_id: shopOwnerId,
        title: 'New Booking',
        body: `New booking confirmed for ${serviceNames} on ${formattedTime}.`,
        data: { type: 'new_booking_shop', booking_id: booking.id, shop_id: shopId },
        is_read: false,
        created_at: now.toISOString(),
      });
    }
    const { error: inAppError } = await supabase.from('in_app_notifications').insert(inAppRows);
    if (inAppError) console.error('⚠️ in_app_notifications insert failed:', inAppError);

    // Scheduled notifications (push + reminders)
    const scheduledRows: any[] = [
      {
        user_id: clientUserId,
        notification_type: 'immediate',
        booking_id: booking.id,
        shop_id: shopId,
        scheduled_for: now.toISOString(),
        status: 'pending',
        metadata: {
          title: 'Booking Confirmed ✅',
          body: `Your ${serviceNames} appointment on ${formattedTime} is confirmed.`,
          type: 'booking_confirmed',
          booking_id: booking.id,
        },
        created_at: now.toISOString(),
        updated_at: now.toISOString(),
      },
    ];

    // Phase 12: client reminder scheduling moved to the
    // schedule_booking_reminders AFTER INSERT trigger on bookings
    // (migration 20260605130600). The 1h and 5min variants are sunset
    // per the consolidated cadence.

    const tReview = new Date(endTime.getTime() + 30 * 60 * 1000);
    if (tReview > now) {
      scheduledRows.push({
        user_id: clientUserId, notification_type: 'review_request',
        booking_id: booking.id, shop_id: shopId,
        scheduled_for: tReview.toISOString(), status: 'pending',
        metadata: { title: 'How was your appointment?', body: `Leave a review for your recent ${serviceNames} appointment.`, booking_id: booking.id, shop_id: shopId },
        created_at: now.toISOString(), updated_at: now.toISOString(),
      });
    }

    if (shopOwnerId) {
      const t15min = new Date(startTime.getTime() - 15 * 60 * 1000);
      if (t15min > now) {
        scheduledRows.push({
          user_id: shopOwnerId, notification_type: 'shop_reminder_15min',
          booking_id: booking.id, shop_id: shopId,
          scheduled_for: t15min.toISOString(), status: 'pending',
          metadata: { title: 'Client Arriving Soon', body: `A client arrives in 15 minutes for ${serviceNames}.`, booking_id: booking.id },
          created_at: now.toISOString(), updated_at: now.toISOString(),
        });
      }
    }

    const { error: schedError } = await supabase.from('scheduled_notifications').insert(scheduledRows);
    if (schedError) console.error('⚠️ scheduled_notifications insert failed:', schedError);

  } catch (err) {
    console.error('⚠️ scheduleBookingNotifications failed (non-fatal):', err);
  }
}

// supabase/functions/stripe-webhook/index.ts

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import type Stripe from "https://esm.sh/stripe@13.6.0";
import { getProvider } from "../_shared/providers/registry.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";
import { isDebugLogging, redactForLog } from "../_shared/sanitize.ts";
import { markEventProcessed } from "../_shared/webhook_dedup.ts";

const supabase = createClient(
  Deno.env.get('SUPABASE_URL') ?? '',
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
);

serve(async (req) => {
  if (req.method !== 'POST') {
    return new Response('Method not allowed', { status: 405 });
  }

  const signature = req.headers.get('stripe-signature') ?? '';
  if (!signature) {
    return new Response('Missing stripe-signature header', { status: 400 });
  }

  const body = await req.text();
  const provider = getProvider('stripe');
  const isValid = await provider.verifyWebhookSignature({
    rawBody: body,
    signatureHeader: signature,
  });
  if (!isValid) {
    return new Response('Webhook signature verification failed', { status: 400 });
  }

  // Signature is valid; safe to parse the event payload.
  const event = JSON.parse(body) as Stripe.Event;

  // Event-ID dedup. Stripe replays aggressively; event.id is canonical.
  const dedup = await markEventProcessed(supabase, 'stripe', event.id, event.type);
  if (!dedup.firstTime && !dedup.error) {
    console.log('↩️  Stripe event already processed, skipping:', event.id);
    return new Response(JSON.stringify({ received: true, deduplicated: true }), {
      headers: { 'Content-Type': 'application/json' },
    });
  }

  try {
    switch (event.type) {
      case 'checkout.session.completed':
        await handleCheckoutSessionCompleted(event.data.object as Stripe.Checkout.Session);
        break;

      case 'checkout.session.expired':
        await handleCheckoutSessionExpired(event.data.object as Stripe.Checkout.Session);
        break;

      case 'account.updated':
        await handleAccountUpdated(event.data.object as Stripe.Account);
        break;

      case 'account.application.deauthorized':
        await handleDeauthorized(event.account!);
        break;

      default:
        console.log(`Unhandled Stripe event type: ${event.type}`);
        break;
    }

    return new Response(JSON.stringify({ received: true }), {
      headers: { 'Content-Type': 'application/json' },
    });
  } catch (err) {
    console.error(`Error handling webhook event ${event.type}:`, err);
    // Return 500 so Stripe retries — do NOT return 200 on handler errors
    return new Response('Webhook handler error', { status: 500 });
  }
});

async function handleAccountUpdated(account: Stripe.Account) {
  // Find the shop connected to this Stripe account
  const { data: settings } = await supabase
    .from('payment_settings')
    .select('shop_id')
    .eq('stripe_account_id', account.id)
    .single();

  if (!settings) {
    // Account not in our system — could be a test account or already disconnected
    return;
  }

  await supabase
    .from('payment_settings')
    .update({
      stripe_account_status: account.charges_enabled ? 'active' : 'pending',
      stripe_charges_enabled: account.charges_enabled ?? false,
      stripe_payouts_enabled: account.payouts_enabled ?? false,
    })
    .eq('shop_id', settings.shop_id);

  console.log(`Updated account status for shop ${settings.shop_id}: charges=${account.charges_enabled}, payouts=${account.payouts_enabled}`);
}

async function handleDeauthorized(stripeAccountId: string) {
  // Merchant deauthorised the app from Stripe's side — mirror that locally
  const { data: settings } = await supabase
    .from('payment_settings')
    .select('shop_id')
    .eq('stripe_account_id', stripeAccountId)
    .single();

  if (!settings) return;

  await supabase
    .from('payment_settings')
    .update({
      payment_provider: 'none',
      stripe_account_id: null,
      stripe_account_status: null,
      stripe_charges_enabled: null,
      stripe_payouts_enabled: null,
      payout_schedule: null,
      payout_minimum: null,
      payout_currency: null,
      connected_at: null,
    })
    .eq('shop_id', settings.shop_id);

  console.log(`Shop ${settings.shop_id} deauthorised Stripe from dashboard — local record cleared`);
}

// ============================================================================
// Handle Stripe Checkout Session Completed
// Mirrors paystack-webhook handlePaymentSuccess — this is the event that fires
// when a client successfully pays. Without this, Stripe bookings were never created.
// ============================================================================
async function handleCheckoutSessionCompleted(session: Stripe.Checkout.Session) {
  const sessionId = session.id;
  const amountPaid = (session.amount_total ?? 0) / 100; // cents → dollars

  console.log('💳 Stripe checkout completed:', sessionId);
  if (isDebugLogging()) {
    console.log('💳 details:', redactForLog({ sessionId, amountPaid, paymentStatus: session.payment_status }));
  }

  // Only process sessions that were actually paid
  if (session.payment_status !== 'paid') {
    console.log('⏭️ Session not paid, skipping:', sessionId);
    return;
  }

  // Idempotency — don't create booking twice
  const { data: existing } = await supabase
    .from('bookings')
    .select('id')
    .eq('payment_intent_id', sessionId)
    .maybeSingle();

  if (existing) {
    console.log('⚠️ Booking already exists for session:', sessionId);
    return;
  }

  // Load pending payment (contains full booking data written by create-booking)
  const { data: pending, error: pendingError } = await supabase
    .from('pending_payments')
    .select('*')
    .eq('payment_intent_id', sessionId)
    .eq('status', 'pending')
    .maybeSingle();

  if (pendingError || !pending) {
    console.error('❌ No pending payment found for session:', sessionId);
    return;
  }

  // Guard against expired payment windows
  if (pending.expires_at && new Date(pending.expires_at) < new Date()) {
    console.error('❌ Pending payment expired for session:', sessionId);
    await supabase
      .from('pending_payments')
      .update({ status: 'expired', updated_at: new Date().toISOString() })
      .eq('payment_intent_id', sessionId);
    return;
  }

  const bookingData = pending.booking_data;

  // Create the confirmed booking. Column set must match the actual `bookings`
  // schema — no `services` JSON, no `payment_provider`; services go in the
  // sibling `booking_services` table.
  const { data: booking, error: bookingError } = await supabase
    .from('bookings')
    .insert({
      shop_id: pending.shop_id,
      user_id: pending.user_id,                       // null on guest path
      guest_profile_id: pending.guest_profile_id,     // NEW
      guest_name: pending.guest_profile_id
        ? bookingData.guestName ?? null
        : null,                                       // NEW snapshot
      guest_phone: pending.guest_profile_id
        ? bookingData.guestPhone ?? null
        : null,                                       // NEW snapshot
      client_address: bookingData.clientAddress ?? null,        // NEW
      client_address_lat: bookingData.clientAddressLat ?? null, // NEW
      client_address_lng: bookingData.clientAddressLng ?? null, // NEW
      delivery_channel: pending.delivery_channel ?? 'push',     // NEW
      booking_date: bookingData.startTime,
      payment_intent_id: sessionId,
      payment_method: 'stripe',
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

  if (bookingError || !booking) {
    // Race: verify-payment may have inserted first.
    const { data: raceBooking } = await supabase
      .from('bookings')
      .select('id')
      .eq('payment_intent_id', sessionId)
      .maybeSingle();
    if (raceBooking) {
      console.log('✅ Race resolved — booking created by verify-payment:', raceBooking.id);
      return;
    }
    console.error('❌ Failed to create booking from Stripe session:', bookingError);
    throw bookingError; // Throw so Stripe retries the webhook
  }

  console.log('✅ Booking created from Stripe payment:', booking.id);

  // Phase 13: record promo redemption if a code was applied at checkout.
  // promotionId + promoAmountOff are carried through pending.booking_data
  // from booking_confirmation_screen.dart → processPayment → create-booking.
  // Non-fatal: if redemption fails, the booking still stands.
  if (bookingData.promotionId) {
    const { error: redeemError } = await supabase.rpc('redeem_promotion', {
      p_promotion_id: bookingData.promotionId,
      p_booking_id: booking.id,
      p_user_id: booking.user_id,
      p_guest_profile_id: booking.guest_profile_id,
      p_discount_amount: bookingData.promoAmountOff ?? 0,
    });
    if (redeemError) {
      console.error('⚠️ promo redemption failed (non-fatal):', redeemError);
    } else {
      console.log(`🎟️  Promo redemption recorded for booking ${booking.id}`);
    }
  }

  // NEW: record guest booking history for prefill cache
  if (pending.guest_profile_id && Array.isArray(bookingData.services)) {
    const { recordGuestBookingHistory } = await import("../_shared/booking_helpers.ts");
    for (const svc of bookingData.services) {
      await recordGuestBookingHistory(
        supabase,
        pending.guest_profile_id,
        svc.serviceName,
        pending.shop_id ?? null,
      );
    }
  }

  // NEW: schedule WhatsApp notifications if guest opted into WhatsApp channel
  if (pending.delivery_channel === 'whatsapp' && pending.guest_profile_id) {
    try {
      const startTime = new Date(bookingData.startTime);
      const endTime = new Date(bookingData.actualEndTime ?? bookingData.endTime);

      // Resolve shop name + address for the templates.
      let targetName = "Your booking";
      let address = "";
      if (pending.shop_id) {
        const { data: shop } = await supabase
          .from("shops")
          .select("shop_name, address")
          .eq("id", pending.shop_id)
          .single();
        targetName = (shop as any)?.shop_name ?? targetName;
        address = bookingData.clientAddress ?? (shop as any)?.address ?? "";
      }

      const { buildConfirmationParams } = await import("../_shared/booking_helpers.ts");

      const remainingAmount = (
        bookingData.totalAmount - bookingData.depositAmount
      ).toFixed(2);
      const depositAmount = bookingData.depositAmount.toFixed(2);

      const confirmationParams = buildConfirmationParams({
        guestName: bookingData.guestName,
        targetName,
        startTime: bookingData.startTime,
        address,
        depositAmount,
        remainingAmount,
      });

      // Meta rejects (#131008) any empty body param. Default to em-dash.
      const safe = (v: string) => (v && v.trim().length > 0 ? v : "—");
      const reminder24Params = {
        "1": safe(targetName),
        "2": safe(new Date(bookingData.startTime).toLocaleTimeString("en-GB", {
          hour: "numeric", minute: "2-digit", hour12: true,
        })),
        "3": safe(address),
      };
      const reminder2Params = { ...reminder24Params };
      const reviewParams = {
        "1": safe(targetName),
        "2": safe(`https://aurain.barsopus.com/r/${booking.id}`),
      };

      const baseMetadata = {
        phone: bookingData.guestPhone,
        booking_id: booking.id,
      };

      const nowIso = new Date().toISOString();

      // See paystack-webhook for has_reference rationale.
      const refCols = {
        booking_id: booking.id,
        shop_id: pending.shop_id,
      };

      const { error: waSchedError } = await supabase
        .from("scheduled_notifications")
        .insert([
          {
            ...refCols,
            notification_type: "booking_confirmation",
            guest_profile_id: pending.guest_profile_id,
            scheduled_for: nowIso,
            delivery_channel: "whatsapp",
            whatsapp_template: "booking_confirmation_v1",
            whatsapp_params: confirmationParams,
            status: "pending",
            metadata: baseMetadata,
            created_at: nowIso,
            updated_at: nowIso,
          },
          // Phase 12: booking_reminder_24h + booking_reminder_2h removed.
          // The AFTER INSERT/UPDATE trigger on bookings
          // (migration 20260605130600) is now the SINGLE source of
          // booking reminders. See .planning/phases/12-autonomous-retention-engine.
          {
            ...refCols,
            notification_type: "booking_review_prompt",
            guest_profile_id: pending.guest_profile_id,
            scheduled_for: new Date(endTime.getTime() + 90 * 60 * 1000).toISOString(),
            delivery_channel: "whatsapp",
            whatsapp_template: "booking_review_prompt_v1",
            whatsapp_params: reviewParams,
            status: "pending",
            metadata: baseMetadata,
            created_at: nowIso,
            updated_at: nowIso,
          },
        ]);

      if (waSchedError) {
        console.error('⚠️ WhatsApp scheduled_notifications insert failed (non-fatal):', waSchedError);
      } else {
        console.log(`📲 Scheduled 4 WhatsApp notifications for booking ${booking.id}`);
      }
    } catch (waErr) {
      console.error('⚠️ WhatsApp scheduling failed (non-fatal):', waErr);
    }
  }

  // Insert booking_services rows
  if (Array.isArray(bookingData.services) && bookingData.services.length > 0) {
    const serviceRows = (bookingData.services as any[]).map((s: any) => ({
      booking_id: booking.id,
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

  // Mark pending payment as completed
  await supabase
    .from('pending_payments')
    .update({
      status: 'completed',
      booking_id: booking.id,
      completed_at: new Date().toISOString(),
    })
    .eq('payment_intent_id', sessionId);

  // Credit shop wallet — net of platform fee
  const platformFee = bookingData.platformFee ?? 0;
  const netAmount = amountPaid - platformFee;

  const { error: walletError } = await supabase.rpc('add_wallet_transaction', {
    p_shop_id: pending.shop_id,
    p_amount: netAmount,
    p_type: 'deposit',
    p_booking_id: booking.id,
    p_description: `Stripe payment for booking ${booking.id.substring(0, 8)}`,
    p_reference: sessionId,
  });

  if (walletError) {
    console.error('⚠️ Wallet transaction failed (non-fatal):', walletError);
  }

  // Shop dashboard notification (business-level event log)
  await supabase.from('notifications').insert({
    shop_id: pending.shop_id,
    type: 'payment_received',
    title: 'New Booking Confirmed',
    message: `New booking confirmed via Stripe. Payment of ${bookingData.totalAmount?.toFixed(2) ?? amountPaid.toFixed(2)} received.`,
    read: false,
    created_at: new Date().toISOString(),
  });

  // Push notification + in-app inbox entries + all booking reminders.
  // Guest path (pending.user_id is null) skips this — WhatsApp scheduling above
  // handles guest notifications instead.
  if (pending.user_id) {
    await scheduleBookingNotifications(booking, bookingData, pending.shop_id, pending.user_id);
  }

  console.log('✅ Stripe payment flow complete for booking:', booking.id);
}

// ============================================================================
// Handle Stripe Checkout Session Expired
// Marks the pending payment as failed so it doesn't linger indefinitely.
// ============================================================================
async function handleCheckoutSessionExpired(session: Stripe.Checkout.Session) {
  console.log('⏰ Stripe session expired:', session.id);

  await supabase
    .from('pending_payments')
    .update({
      status: 'failed',
      updated_at: new Date().toISOString(),
    })
    .eq('payment_intent_id', session.id)
    .eq('status', 'pending');
}

// ============================================================================
// scheduleBookingNotifications
//
// Shared by handleCheckoutSessionCompleted. Writes to three places:
//   1. in_app_notifications  — client's notification bell (instant inbox)
//   2. in_app_notifications  — shop owner's notification bell
//   3. scheduled_notifications (type: 'immediate') — OneSignal push to client
//      via process-scheduled-notifications cron (~1 min delay). This fires even
//      when the user never returns to the app after paying.
//   4. scheduled_notifications (future) — 24 h / 1 h / 5 min reminders,
//      shop owner 15-min heads-up, post-appointment review request.
//
// Non-fatal: a notification failure must never roll back the booking.
// ============================================================================
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
      weekday: 'short',
      day: 'numeric',
      month: 'short',
      hour: '2-digit',
      minute: '2-digit',
    });

    const { data: shop } = await supabase
      .from('shops')
      .select('user_id')
      .eq('id', shopId)
      .single();
    const shopOwnerId: string | null = shop?.user_id ?? null;

    // ── In-app inbox entries ───────────────────────────────────────────────────
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

    // ── Scheduled notifications (push + reminders) ────────────────────────────
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
    // per the consolidated cadence; see Phase 12 plan.

    const tReview = new Date(endTime.getTime() + 30 * 60 * 1000);
    if (tReview > now) {
      scheduledRows.push({
        user_id: clientUserId,
        notification_type: 'review_request',
        booking_id: booking.id,
        shop_id: shopId,
        scheduled_for: tReview.toISOString(),
        status: 'pending',
        metadata: { title: 'How was your appointment?', body: `Leave a review for your recent ${serviceNames} appointment.`, booking_id: booking.id, shop_id: shopId },
        created_at: now.toISOString(),
        updated_at: now.toISOString(),
      });
    }

    if (shopOwnerId) {
      const t15min = new Date(startTime.getTime() - 15 * 60 * 1000);
      if (t15min > now) {
        scheduledRows.push({
          user_id: shopOwnerId,
          notification_type: 'shop_reminder_15min',
          booking_id: booking.id,
          shop_id: shopId,
          scheduled_for: t15min.toISOString(),
          status: 'pending',
          metadata: { title: 'Client Arriving Soon', body: `A client arrives in 15 minutes for ${serviceNames}.`, booking_id: booking.id },
          created_at: now.toISOString(),
          updated_at: now.toISOString(),
        });
      }
    }

    const { error: schedError } = await supabase.from('scheduled_notifications').insert(scheduledRows);
    if (schedError) console.error('⚠️ scheduled_notifications insert failed:', schedError);

    console.log(`📬 Scheduled ${scheduledRows.length} notifications for booking ${booking.id}`);
  } catch (err) {
    console.error('⚠️ scheduleBookingNotifications failed (non-fatal):', err);
  }
}
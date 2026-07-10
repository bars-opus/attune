// supabase/functions/create-booking/payment-intent/index.ts

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";
import {
  sanitizeText,
  sanitizeAmount,
  sanitizeIdentifier,
  redactForLog,
  isDebugLogging,
} from "../_shared/sanitize.ts";
import { getProvider } from "../_shared/providers/registry.ts";
import { PaymentProviderError, type PaymentProviderName } from "../_shared/providers/port.ts";
import { buildCorsHeaders } from "../_shared/cors.ts";
import { checkRateLimit } from "../_shared/rate_limit.ts";

// ============================================================================
// INITIALIZATION
// ============================================================================

const supabase = createClient(
  Deno.env.get('SUPABASE_URL') ?? '',
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
);

// ============================================================================
// TYPES
// ============================================================================

interface BookingRequest {
  shopId: string;
  // userId is optional on the guest (web) path; required on the mobile (auth) path.
  userId?: string;
  // userEmail is required on the auth path; optional on the guest path
  // (synthesized from phone for the payment provider).
  userEmail?: string;
  services: Array<{
    slotId: string;
    workerId: string | null;
    priceAtBooking: number;
    durationMinutes: number;
    serviceName: string;
    workerName: string | null;
  }>;
  startTime: string;
  endTime: string;
  actualEndTime: string;
  totalAmount: number;
  depositAmount: number;
  platformFee: number;
  paymentMethod: 'stripe' | 'paystack';
  paymentProvider: 'stripe' | 'paystack';
  idempotencyKey: string;
  successUrl?: string;
  cancelUrl?: string;

  // NEW guest mode fields (web link booking path):
  guestName?: string;
  guestPhone?: string;
  clientAddress?: string;
  clientAddressLat?: number;
  clientAddressLng?: number;
  deliveryChannel?: "push" | "whatsapp";
}

interface ValidationResult {
  isValid: boolean;
  errors: string[];
}

// ============================================================================
// MAIN HANDLER
// ============================================================================

serve(async (req) => {
  const corsHeaders = buildCorsHeaders(req, "POST, OPTIONS");
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    // Authorization is required (anon key for the web/guest path; user JWT for the
    // mobile/auth path). We resolve the user lazily — if the bearer is a valid
    // user JWT, authUser is populated; if it's the anon key, authUser is null
    // and we route to the guest path based on body fields.
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) {
      return new Response(
        JSON.stringify({ success: false, error: 'Missing authorization header' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    const { data: { user: authUser } } = await supabase.auth.getUser(
      authHeader.replace('Bearer ', '')
    );

    const rawBody = await req.json() as BookingRequest;

    // Decide intent: auth path requires userId + matching JWT; guest path
    // requires guestName + guestPhone and forbids userId.
    const wantsAuth = !!rawBody.userId;
    const wantsGuest = !!(rawBody.guestName && rawBody.guestPhone);

    if (wantsAuth === wantsGuest) {
      return new Response(
        JSON.stringify({
          success: false,
          error: wantsAuth
            ? 'Cannot specify both userId and guest fields'
            : 'Must specify either userId or guestName + guestPhone',
        }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    if (wantsAuth) {
      // Mobile/auth path: JWT must be a real user and match the submitted userId.
      if (!authUser) {
        return new Response(
          JSON.stringify({ success: false, error: 'Invalid or expired token' }),
          { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        );
      }
      if (rawBody.userId !== authUser.id) {
        return new Response(
          JSON.stringify({ success: false, error: 'Unauthorized' }),
          { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        );
      }

      // ======================================================================
      // RATE LIMITING — 10 payment intents per user per 10 minutes
      // (auth path only; guest path is rate-limited at the link layer)
      // ======================================================================
      const windowStart = new Date(Date.now() - 10 * 60 * 1000).toISOString();
      const { count: recentAttempts } = await supabase
        .from('pending_payments')
        .select('id', { count: 'exact', head: true })
        .eq('user_id', authUser.id)
        .gte('created_at', windowStart);

      if ((recentAttempts ?? 0) >= 10) {
        console.warn('🚫 Rate limit exceeded for user:', authUser.id);
        return new Response(
          JSON.stringify({ success: false, error: 'Too many payment attempts. Please wait a few minutes before trying again.' }),
          {
            status: 429,
            headers: {
              ...corsHeaders,
              'Content-Type': 'application/json',
              'Retry-After': '600',
            },
          }
        );
      }
    } else if (wantsGuest) {
      // Guest path: 5 booking attempts per IP per 10 minutes. The earlier
      // comment claimed rate limiting happened at the link layer — it didn't.
      const rl = await checkRateLimit(supabase, "create-booking-guest", req, {
        max: 5,
        windowSeconds: 600,
      });
      if (!rl.allowed) {
        return new Response(
          JSON.stringify({
            success: false,
            error: "Too many booking attempts. Please wait a few minutes before trying again.",
          }),
          {
            status: 429,
            headers: {
              ...corsHeaders,
              "Content-Type": "application/json",
              "Retry-After": String(rl.retryAfterSeconds),
            },
          },
        );
      }
    }

    // ========================================================================
    // INPUT SANITIZATION — fail fast on malformed input at the edge.
    // ========================================================================
    let body: BookingRequest;
    try {
      body = {
        ...rawBody,
        shopId: sanitizeIdentifier(rawBody.shopId, 64),
        userId: rawBody.userId ? sanitizeIdentifier(rawBody.userId, 64) : undefined,
        userEmail: rawBody.userEmail
          ? sanitizeText(rawBody.userEmail, { maxLength: 320, rejectHtml: true })
          : undefined,
        idempotencyKey: sanitizeIdentifier(rawBody.idempotencyKey, 128),
        totalAmount: sanitizeAmount(rawBody.totalAmount, { min: 0.01 }),
        depositAmount: sanitizeAmount(rawBody.depositAmount, { min: 0.01 }),
        platformFee: sanitizeAmount(rawBody.platformFee, { min: 0 }),
        services: (rawBody.services ?? []).map((s) => ({
          slotId: sanitizeIdentifier(s.slotId, 64),
          workerId: s.workerId ? sanitizeIdentifier(s.workerId, 64) : null,
          priceAtBooking: sanitizeAmount(s.priceAtBooking, { min: 0 }),
          durationMinutes: Math.max(0, Math.floor(Number(s.durationMinutes) || 0)),
          serviceName: sanitizeText(s.serviceName, { maxLength: 200 }),
          workerName: s.workerName
            ? sanitizeText(s.workerName, { maxLength: 200 })
            : null,
        })),
        // NEW guest fields — sanitize only if present.
        guestName: rawBody.guestName
          ? sanitizeText(rawBody.guestName, { maxLength: 120, rejectHtml: true })
          : undefined,
        guestPhone: rawBody.guestPhone
          // Phone is validated for E.164 in validateRequest; here we just strip
          // shape. Allow + digits spaces dashes — normalizePhone tolerates the rest.
          ? sanitizeText(rawBody.guestPhone, { maxLength: 32, rejectHtml: true })
          : undefined,
        clientAddress: rawBody.clientAddress
          ? sanitizeText(rawBody.clientAddress, { maxLength: 500, rejectHtml: true })
          : undefined,
        clientAddressLat: typeof rawBody.clientAddressLat === 'number'
          ? rawBody.clientAddressLat
          : undefined,
        clientAddressLng: typeof rawBody.clientAddressLng === 'number'
          ? rawBody.clientAddressLng
          : undefined,
        deliveryChannel: rawBody.deliveryChannel === 'whatsapp' ? 'whatsapp'
          : rawBody.deliveryChannel === 'push' ? 'push'
          : undefined,
      };
    } catch (sanErr) {
      return new Response(
        JSON.stringify({
          success: false,
          error: 'Invalid input',
          details: [(sanErr as Error).message],
        }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    // ========================================================================
    // STEP 1: VALIDATION
    // ========================================================================

    const validation = await validateRequest(body);
    if (!validation.isValid) {
      return new Response(
        JSON.stringify({ 
          success: false, 
          error: 'Validation failed',
          details: validation.errors 
        }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

 


    // ========================================================================
// STEP 2: GET SHOP DETAILS (Payment settings optional)
// ========================================================================

// Get shop details to know the country

const { data: shop, error: shopError } = await supabase
  .from('shops')
  .select('id, country, currency')
  .eq('id', body.shopId)
  .single();

if (shopError || !shop) {
  return new Response(
    JSON.stringify({ success: false, error: 'Shop not found' }),
    { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
  );
}

// ✅ IGNORE client's paymentProvider - determine from shop country
const africanCountries = [
  'ghana', 'nigeria', 'kenya', 'south africa', 'uganda', 'tanzania',
  'rwanda', 'zambia', 'botswana', 'mauritius', 'senegal', 'ivory coast',
  'cameroon', 'egypt', 'morocco', 'tunisia', 'algeria', 'angola',
  'mozambique', 'zimbabwe', 'malawi', 'namibia', 'lesotho', 'eswatini',
  'gabon', 'equatorial guinea', 'republic of the congo', 'democratic republic of the congo',
  'central african republic', 'chad', 'mali', 'burkina faso', 'niger',
  'mauritania', 'benin', 'togo', 'liberia', 'sierra leone', 'guinea',
  'guinea-bissau', 'gambia', 'senegal', 'djibouti', 'eritrea', 'ethiopia',
  'somalia', 'sudan', 'south sudan', 'comoros', 'seychelles', 'são tomé and príncipe',
  'gh', 'ng', 'ke', 'za', 'ug', 'tz', 'rw', 'zm', 'bw'
];


const shopCountry = shop.country?.toLowerCase().trim() || '';
const shopCurrency = shop.currency?.toUpperCase().trim() || 'GHS';

// Currency is the reliable fallback when shop.country is null/empty.
const africanCurrencies = new Set([
  'GHS', 'GHC', 'NGN', 'KES', 'ZAR', 'UGX', 'TZS', 'RWF', 'ZMW', 'BWP',
  'XOF', 'XAF', 'EGP', 'MAD', 'TND', 'DZD', 'ETB', 'MZN', 'AOA',
]);

const isAfrican =
  africanCountries.some(country => shopCountry === country || shopCountry.includes(country)) ||
  africanCurrencies.has(shopCurrency);

const provider = isAfrican ? 'paystack' : 'stripe';

// Gate verbose request logging behind PAYMENT_DEBUG_LOGS=true so production
// edge-function logs don't accumulate PII.
if (isDebugLogging()) {
  console.log('🔍 Provider detection:', {
    rawCountry: shop.country,
    rawCurrency: shop.currency,
    shopCountry,
    shopCurrency,
    isAfrican,
    provider,
  });
}

// Hard failsafe: if we resolved to Stripe but no Stripe key is configured,
// return a clear error instead of a cryptic Stripe auth failure.
if (provider === 'stripe' && !Deno.env.get('STRIPE_SECRET_KEY')) {
  return new Response(
    JSON.stringify({
      success: false,
      error: 'This shop is not in a supported region for the available payment provider. Please contact support.',
    }),
    { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
  );
}





// ✅ NO PAYMENT SETTINGS VALIDATION - shops add this later for withdrawals
// Proceed with payment processing

    // ========================================================================
    // STEP 3: CHECK IDEMPOTENCY (Prevent duplicate payments)
    // ========================================================================
    
    // Only treat as "already processed" if an actual booking row exists.
    // A stale pending_payments row with status='completed' but no booking
    // means a previous attempt failed mid-flow (e.g., webhook never delivered
    // a valid signature), so the user must be allowed to retry.
    const { data: existingBooking } = await supabase
      .from('bookings')
      .select('*')
      .eq('payment_intent_id', body.idempotencyKey)
      .maybeSingle();

    if (existingBooking) {
      return new Response(
        JSON.stringify({
          success: true,
          message: 'Payment already processed',
          booking: existingBooking,
        }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // ========================================================================
    // STEP 4: INITIALIZE CHECKOUT VIA THE PROVIDER PORT
    // ========================================================================
    const callbackBase = body.successUrl ?? "nanoembryo://payment-success";

    // Paystack + Stripe both require an email. For guest bookings (no auth user
    // and no userEmail) synthesize a stable, deliverability-free placeholder
    // derived from the E.164 phone. The receipt won't be emailed — webhooks
    // surface the booking via WhatsApp / push.
    // Paystack validates the email TLD strictly — '.local' is rejected as
    // not a real top-level domain. Use a real subdomain we control. Mail
    // sent here black-holes; users get receipts via WhatsApp / push.
    const customerEmail = body.userEmail
      ?? (body.guestPhone
        ? `guest_${body.guestPhone.replace(/[^\d]/g, '')}@guests.aurain.barsopus.com`
        : undefined);
    if (!customerEmail) {
      return new Response(
        JSON.stringify({ success: false, error: 'Missing customer contact' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    let checkoutResult;
    try {
      checkoutResult = await getProvider(provider as PaymentProviderName).initCheckout({
        amount: body.depositAmount,
        currency: shopCurrency,
        reference: provider === "paystack"
          ? `booking_${body.idempotencyKey}`.slice(0, 100)
          : body.idempotencyKey,
        customerEmail,
        callbackUrl: callbackBase,
        destinationAccountId: await resolveDestinationAccountId(body.shopId, provider),
        platformFeeAmount: body.platformFee,
        metadata: {
          shop_id: body.shopId,
          user_id: body.userId ?? '',
          total_amount: String(body.totalAmount),
          deposit_amount: String(body.depositAmount),
          platform_fee: String(body.platformFee),
          idempotency_key: body.idempotencyKey,
          services: body.services.map((s) => s.serviceName).join(", "),
        },
      });
    } catch (e) {
      if (e instanceof PaymentProviderError) {
        return new Response(
          JSON.stringify({ success: false, error: e.message }),
          { status: e.category === "invalid_request" ? 400 : 502, headers: { ...corsHeaders, "Content-Type": "application/json" } },
        );
      }
      throw e;
    }

    const paymentResult = {
      success: true,
      paymentIntentId: checkoutResult.providerReference,
      authorizationUrl: checkoutResult.checkoutUrl,
      reference: checkoutResult.providerReference,
    };

    // ========================================================================
    // STEP 5: STORE PENDING PAYMENT (verify-payment + webhook depend on this)
    // ========================================================================
    //
    // Critical: if this fails silently, neither the webhook nor verify-payment
    // can resolve the payment — the user would pay and never see a booking.
    // We treat a missing pending_payments row as a fatal error.

    // NEW: on the guest path, upsert the guest profile so the webhook can
    // resolve the customer when finalizing the booking. We do this *after*
    // the payment intent is created so a provider error doesn't leave a
    // stray guest_profiles row (the upsert is by phone, so a retry is safe
    // anyway, but ordering this way keeps the table cleaner).
    let guestProfileId: string | null = null;
    if (body.guestName && body.guestPhone) {
      try {
        const { upsertGuestProfile } = await import('../_shared/booking_helpers.ts');
        guestProfileId = await upsertGuestProfile(
          supabase,
          body.guestPhone,
          body.guestName,
        );
      } catch (e) {
        console.error('❌ Failed to upsert guest profile:', (e as Error).message);
        return new Response(
          JSON.stringify({
            success: false,
            error: 'Could not register guest profile. Please try again.',
          }),
          { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
        );
      }
    }

    const { error: pendingError } = await supabase
      .from('pending_payments')
      .upsert({
        idempotency_key: body.idempotencyKey,
        shop_id: body.shopId,
        user_id: body.userId ?? null,
        guest_profile_id: guestProfileId,
        amount: body.totalAmount,
        payment_intent_id: paymentResult.paymentIntentId,
        payment_provider: provider,
        status: 'pending',
        booking_data: body,
        delivery_channel: body.deliveryChannel ?? 'push',
        created_at: new Date().toISOString(),
        expires_at: new Date(Date.now() + 30 * 60 * 1000).toISOString(),
      }, { onConflict: 'idempotency_key' });

    if (pendingError) {
      console.error('❌ Failed to persist pending_payment:', pendingError);
      return new Response(
        JSON.stringify({
          success: false,
          error:
            'Could not store payment state. Please try again — you have not been charged.',
        }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    // ========================================================================
    // STEP 6: RETURN PAYMENT URL FOR WEBVIEW
    // ========================================================================
    
    return new Response(
      JSON.stringify({
        success: true,
        paymentIntentId: paymentResult.paymentIntentId,
        authorizationUrl: paymentResult.authorizationUrl,
        reference: paymentResult.reference,
        // Return server-determined provider — defeats client tampering and
        // matches what's stored in pending_payments.
        provider,
      }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );

  } catch (error) {
    console.error('Payment error:', (error as Error).message);
    if (isDebugLogging()) {
      console.error('Payment error redacted body:', redactForLog(error));
    }
    return new Response(
      JSON.stringify({ success: false, error: error.message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }
});

// ============================================================================
// VALIDATION FUNCTIONS
// ============================================================================

async function validateRequest(req: BookingRequest): Promise<ValidationResult> {
  const errors: string[] = [];

  // NEW: enforce exactly one of userId or (guestName + guestPhone).
  const hasUser = !!req.userId;
  const hasGuest = !!(req.guestName && req.guestPhone);
  if (hasUser === hasGuest) {
    errors.push(
      hasUser
        ? 'Cannot specify both userId and guest fields'
        : 'Must specify either userId or guestName + guestPhone',
    );
    return { isValid: false, errors };
  }

  // NEW: guest path requires E.164 phone (validated via shared helper).
  if (hasGuest) {
    try {
      const { normalizePhone } = await import('../_shared/booking_helpers.ts');
      normalizePhone(req.guestPhone!);
    } catch (e) {
      errors.push(`Invalid guest phone: ${(e as Error).message}`);
      return { isValid: false, errors };
    }
  }

  // NEW: if clientAddress + lat/lng is supplied (freelancer booking with
  // travel), confirm the freelancer assigned to this shop can reach it.
  // Skip when no freelancer worker is configured — the shop is location-based.
  if (
    req.clientAddress != null &&
    req.clientAddressLat != null &&
    req.clientAddressLng != null
  ) {
    const { data: freelancerWorker } = await supabase
      .from('workers')
      .select(`
        id, is_freelancer,
        freelancer_details:freelancer_details(can_travel, travel_radius_km, base_latitude, base_longitude)
      `)
      .eq('shop_id', req.shopId)
      .eq('is_active', true)
      .eq('is_freelancer', true)
      .limit(1)
      .maybeSingle();

    if (freelancerWorker) {
      const details = Array.isArray((freelancerWorker as any).freelancer_details)
        ? (freelancerWorker as any).freelancer_details[0]
        : (freelancerWorker as any).freelancer_details;
      if (
        details?.can_travel &&
        typeof details.base_latitude === 'number' &&
        typeof details.base_longitude === 'number'
      ) {
        const distance = haversineKm(
          details.base_latitude,
          details.base_longitude,
          req.clientAddressLat,
          req.clientAddressLng,
        );
        if (distance > (details.travel_radius_km ?? 0)) {
          errors.push(
            `Address is ${distance.toFixed(1)}km away (max ${details.travel_radius_km}km)`,
          );
        }
      }
    }
  }

  // Validate shop exists
  const { data: shop, error: shopError } = await supabase
    .from('shops')
    .select('id, user_id, shop_name')
    .eq('id', req.shopId)
    .single();

  if (shopError || !shop) {
    errors.push('Invalid shop');
  }

  // Validate services exist and are active
  for (const service of req.services) {
    const { data: slot, error: slotError } = await supabase
      .from('appointment_slots')
      .select('id, service_name, price, max_clients, is_active')
      .eq('id', service.slotId)
      .single();

    // if (slotError || !slot || !slot.is_active) {
    //   errors.push(`Service ${service.serviceName} is not available`);
    // }

    // Validate price matches current price (optional - prevents price tampering)
    if (slot && Math.abs(slot.price - service.priceAtBooking) > 0.01) {
      errors.push(`Price mismatch for ${service.serviceName}`);
    }
  }

  // Validate worker exists and is active (if assigned)
  for (const service of req.services) {
    if (service.workerId) {
      const { data: worker, error: workerError } = await supabase
        .from('workers')
        .select('id, name, is_active')
        .eq('id', service.workerId)
        .single();

      if (workerError || !worker || !worker.is_active) {
        errors.push(`Worker ${service.workerName} is not available`);
      }
    }
  }

  // Validate time slot availability per assigned worker (not whole shop),
  // so shops with multiple workers can serve clients concurrently.
  //
  // The `bookings` table has no JSON `services` column — worker assignments
  // live in `booking_services`. We join via the overlapping bookings.
  const workerIds = req.services
    .map(s => s.workerId)
    .filter((id): id is string => !!id);

  // Overlap: existing.start_time < req.endTime AND existing.end_time > req.startTime
  const { data: overlapping, error: overlapErr } = await supabase
    .from('bookings')
    .select('id')
    .eq('shop_id', req.shopId)
    .eq('status', 'confirmed')
    .lt('start_time', req.endTime)
    .gt('end_time', req.startTime);

  if (overlapErr) {
    // Treat a query error as conservative-block. Better to fail booking than to
    // double-book a slot.
    errors.push('Could not verify slot availability — please retry');
  } else if (overlapping && overlapping.length > 0) {
    const overlappingIds = overlapping.map((b: { id: string }) => b.id);

    if (workerIds.length > 0) {
      // Multi-worker shop: only flag if a *requested* worker is already booked
      // in this window.
      const { data: workerHits, error: bsErr } = await supabase
        .from('booking_services')
        .select('worker_id')
        .in('booking_id', overlappingIds)
        .in('worker_id', workerIds);

      if (bsErr) {
        errors.push('Could not verify worker availability — please retry');
      } else if (workerHits && workerHits.length > 0) {
        errors.push('Selected worker is not available for this time slot');
      }
    }
    // No-worker path: allow through. The webhook + booking assignment logic
    // handles auto-assignment; we don't pre-block based on shop-wide overlap.
  }

  // Validate amount matches calculation
  const calculatedAmount = req.services.reduce((sum, s) => sum + s.priceAtBooking, 0);
  if (Math.abs(calculatedAmount - req.totalAmount) > 0.01) {
    errors.push('Amount mismatch');
  }

  return {
    isValid: errors.length === 0,
    errors,
  };
}

/**
 * Haversine great-circle distance between two lat/lng coordinates in km.
 * Used to enforce freelancer travel_radius_km on guest bookings that include
 * a client address.
 */
function haversineKm(
  lat1: number,
  lng1: number,
  lat2: number,
  lng2: number,
): number {
  const R = 6371;
  const dLat = ((lat2 - lat1) * Math.PI) / 180;
  const dLng = ((lng2 - lng1) * Math.PI) / 180;
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos((lat1 * Math.PI) / 180) *
      Math.cos((lat2 * Math.PI) / 180) *
      Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(a));
}


// ============================================================================
// PROVIDER HELPERS
// ============================================================================

async function resolveDestinationAccountId(
  shopId: string,
  provider: "paystack" | "stripe",
): Promise<string | undefined> {
  const { data: settings } = await supabase
    .from("payment_settings")
    .select("paystack_subaccount_code, stripe_account_id, stripe_verified")
    .eq("shop_id", shopId)
    .maybeSingle();
  if (!settings) return undefined;
  if (provider === "paystack") return settings.paystack_subaccount_code ?? undefined;
  if (provider === "stripe") {
    return settings.stripe_verified ? (settings.stripe_account_id ?? undefined) : undefined;
  }
  return undefined;
}
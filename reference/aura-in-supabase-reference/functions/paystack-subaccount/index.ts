// supabase/functions/paystack-subaccount/index.ts

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";
import { retryFetch } from "../_shared/retry.ts";
import {
  isDebugLogging,
  redactForLog,
  sanitizeCurrency,
  sanitizeIdentifier,
  sanitizeText,
} from "../_shared/sanitize.ts";
import { audit } from "../_shared/audit.ts";

const PAYSTACK_SECRET_KEY = Deno.env.get('PAYSTACK_SECRET_KEY')!;
const PAYSTACK_BASE_URL = 'https://api.paystack.co';

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
);

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const PLATFORM_PERCENTAGE_CHARGE = '2.9';

// ============================================================================
// Mobile money provider codes — NOT valid settlement_bank values for /subaccount.
// ============================================================================
const MOBILE_MONEY_CODES = new Set(['MTN', 'VOD', 'ATL', 'TGO']);

function isMobileMoney(bankCode: string): boolean {
  return MOBILE_MONEY_CODES.has(bankCode.toUpperCase());
}

// Maps Paystack currency codes to the correct transfer recipient type.
// https://paystack.com/docs/transfers/single-transfers/#create-a-transfer-recipient
function recipientTypeForCurrency(currencyCode: string): string {
  switch (currencyCode.toUpperCase()) {
    case 'GHS': return 'ghipss';   // Ghana Interbank Payment System
    case 'NGN': return 'nuban';    // Nigeria Uniform Bank Account Number
    case 'ZAR': return 'basa';     // South Africa
    case 'USD': return 'ach';      // USD ACH (Paystack USD accounts)
    default:    return 'nuban';    // Fallback — Paystack's most common type
  }
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) {
      return new Response(JSON.stringify({ error: 'Unauthorized' }), {
        status: 401,
        headers: corsHeaders,
      });
    }

    const token = authHeader.replace('Bearer ', '');
    const { data: { user }, error: userError } = await supabase.auth.getUser(token);

    if (userError || !user) {
      return new Response(JSON.stringify({ error: 'Unauthorized' }), {
        status: 401,
        headers: corsHeaders,
      });
    }

    const body = await req.json();
    const { action } = body;

    if (action === 'fetch-banks') {
      const { currencyCode } = body;
      if (!currencyCode) {
        return new Response(JSON.stringify({ error: 'currencyCode required' }), {
          status: 400,
          headers: corsHeaders,
        });
      }
      return await fetchBanks(currencyCode);
    }

    if (action === 'create-subaccount') {
      // Sanitize all user-supplied inputs before they reach Paystack or the DB.
      let shopId: string;
      let bankCode: string;
      let accountNumber: string;
      let currencyCode: string;
      let businessName: string;
      try {
        shopId = sanitizeIdentifier(body.shopId, 64);
        // bank/MoMo codes are 3–10 alphanumeric chars (e.g. "MTN", "058", "GH050100").
        bankCode = sanitizeIdentifier(body.bankCode, 16);
        // Account numbers / MoMo phone numbers — digits only, cap at 20.
        accountNumber = sanitizeIdentifier(body.accountNumber, 20);
        currencyCode = sanitizeCurrency(body.currencyCode || 'GHS');
        businessName = body.businessName
          ? sanitizeText(body.businessName, { maxLength: 200, rejectHtml: true })
          : '';
      } catch (sanErr) {
        return new Response(
          JSON.stringify({ error: (sanErr as Error).message }),
          { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
        );
      }

      if (!shopId || !bankCode || !accountNumber) {
        return new Response(JSON.stringify({ error: 'shopId, bankCode, and accountNumber required' }), {
          status: 400,
          headers: corsHeaders,
        });
      }

      // Rate limit: max 5 subaccount connections per user per hour to prevent abuse
      const rlWindowStart = new Date(Date.now() - 60 * 60 * 1000).toISOString();
      const { data: userShops } = await supabase
        .from('shops')
        .select('id')
        .eq('user_id', user.id);
      const userShopIds = (userShops ?? []).map((s: { id: string }) => s.id);

      if (userShopIds.length > 0) {
        const { count: recentConnections } = await supabase
          .from('payment_settings')
          .select('shop_id', { count: 'exact', head: true })
          .in('shop_id', userShopIds)
          .gte('connected_at', rlWindowStart);

        if ((recentConnections ?? 0) >= 5) {
          console.warn('🚫 Paystack subaccount rate limit exceeded for user:', user.id);
          return new Response(
            JSON.stringify({ error: 'Too many connection attempts. Please wait an hour before trying again.' }),
            {
              status: 429,
              headers: { ...corsHeaders, 'Content-Type': 'application/json', 'Retry-After': '3600' },
            }
          );
        }
      }

      const { data: shop, error: shopError } = await supabase
        .from('shops')
        .select('id, user_id, shop_name')
        .eq('id', shopId)
        .single();

      if (shopError || !shop) {
        return new Response(JSON.stringify({ error: 'Shop not found' }), {
          status: 404,
          headers: corsHeaders,
        });
      }

      if (shop.user_id !== user.id) {
        return new Response(JSON.stringify({ error: 'Unauthorized' }), {
          status: 403,
          headers: corsHeaders,
        });
      }

      return await createSubaccount(
        shop.id,
        businessName || shop.shop_name,
        bankCode,
        accountNumber,
        currencyCode,
        user.id,
      );
    }

    if (action === 'get-status') {
      const { shopId } = body;
      if (!shopId) {
        return new Response(JSON.stringify({ error: 'shopId required' }), {
          status: 400,
          headers: corsHeaders,
        });
      }
      // Verify the caller owns this shop
      const { data: ownedShop } = await supabase
        .from('shops')
        .select('id')
        .eq('id', shopId)
        .eq('user_id', user.id)
        .single();
      if (!ownedShop) {
        return new Response(JSON.stringify({ error: 'Unauthorized' }), {
          status: 403,
          headers: corsHeaders,
        });
      }
      return await getSubaccountStatus(shopId);
    }

    if (action === 'disconnect') {
      const { shopId } = body;
      if (!shopId) {
        return new Response(JSON.stringify({ error: 'shopId required' }), {
          status: 400,
          headers: corsHeaders,
        });
      }
      // Verify the caller owns this shop
      const { data: ownedShop } = await supabase
        .from('shops')
        .select('id')
        .eq('id', shopId)
        .eq('user_id', user.id)
        .single();
      if (!ownedShop) {
        return new Response(JSON.stringify({ error: 'Unauthorized' }), {
          status: 403,
          headers: corsHeaders,
        });
      }
      return await disconnectSubaccount(shopId, user.id);
    }

    return new Response(JSON.stringify({ error: 'Invalid action' }), {
      status: 400,
      headers: corsHeaders,
    });
  } catch (error) {
    console.error('paystack-subaccount error:', (error as Error).message);
    if (isDebugLogging()) {
      console.error('full error:', redactForLog(error));
    }
    return new Response(JSON.stringify({ error: (error as Error).message }), {
      status: 500,
      headers: corsHeaders,
    });
  }
});

// ============================================================================
// Fetch Banks
// ============================================================================
async function fetchBanks(currencyCode: string) {
  try {
    // Validate currency before sending — defends against Paystack 400s.
    const safeCurrency = sanitizeCurrency(currencyCode);

    const response = await retryFetch(
      `${PAYSTACK_BASE_URL}/bank?currency=${safeCurrency}`,
      { headers: { 'Authorization': `Bearer ${PAYSTACK_SECRET_KEY}` } },
      { attempts: 3, baseDelayMs: 500, label: 'paystack.banks' },
    );

    const data = await response.json();

    if (!data.status) {
      return new Response(
        JSON.stringify({ error: data.message }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    const banks = data.data
      .filter((bank: any) => bank.currency === safeCurrency)
      .map((bank: any) => ({
        code: bank.code,
        name: bank.name,
      }));

    return new Response(
      JSON.stringify(banks),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  } catch (err) {
    console.error('fetchBanks error:', (err as Error).message);
    return new Response(
      JSON.stringify({ error: 'Failed to fetch banks' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }
}

// ============================================================================
// Create Subaccount
//
// Two paths:
//   A) Mobile money (mtn / vod / atl / tgo)
//      → Skip /subaccount (not supported by Paystack for MoMo)
//      → Only create a transfer recipient with type "mobile_money"
//      → Store recipient_code; subaccount_code is null
//
//   B) Bank account (all other codes)
//      → Create /subaccount  (settlement_bank = bankCode)
//      → Create transfer recipient with type "ghipss"
//      → Store both codes
// ============================================================================
async function createSubaccount(
  shopId: string,
  businessName: string,
  bankCode: string,
  accountNumber: string,
  currencyCode: string,
  actorUserId: string,
) {
  // Guard: don't create duplicates
  const { data: existing } = await supabase
    .from('payment_settings')
    .select('paystack_subaccount_code, paystack_recipient_id')
    .eq('shop_id', shopId)
    .single();

  if (existing?.paystack_subaccount_code || existing?.paystack_recipient_id) {
    return new Response(
      JSON.stringify({ error: 'Payment details already exist for this shop. Disconnect first.' }),
      { status: 409, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }

  const mobileMoneyFlow = isMobileMoney(bankCode);

  try {
    let subaccountCode: string | null = null;
    let recipientCode: string | null = null;

    // ------------------------------------------------------------------
    // PATH A — Mobile Money
    // ------------------------------------------------------------------
    if (mobileMoneyFlow) {
      recipientCode = await createMobileMoneyRecipient({
        businessName,
        bankCode,
        accountNumber,
        currencyCode,
      });
    }
    // ------------------------------------------------------------------
    // PATH B — Bank Account
    // ------------------------------------------------------------------
    else {
      // Step 1: Create subaccount
      const subaccountBody = {
        business_name: businessName,
        settlement_bank: bankCode,
        account_number: accountNumber,
        percentage_charge: PLATFORM_PERCENTAGE_CHARGE,
      };

      console.log('📦 Creating subaccount for shop:', shopId);
      if (isDebugLogging()) {
        console.log('subaccount body:', redactForLog(subaccountBody));
      }

      const subRes = await retryFetch(
        `${PAYSTACK_BASE_URL}/subaccount`,
        {
          method: 'POST',
          headers: {
            'Authorization': `Bearer ${PAYSTACK_SECRET_KEY}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify(subaccountBody),
        },
        { attempts: 3, baseDelayMs: 500, label: 'paystack.subaccount' },
      );

      const subData = await subRes.json();

      if (!subData.status) {
        throw new Error(subData.message || 'Subaccount creation failed');
      }

      subaccountCode = subData.data.subaccount_code;
      console.log('✅ Subaccount created:', subaccountCode);

      // Step 2: Create transfer recipient (ghipss = Ghana Interbank Payment)
      try {
        recipientCode = await createBankRecipient({
          businessName,
          bankCode,
          accountNumber,
          currencyCode,
        });
      } catch (recipientErr) {
        // Paystack has no DELETE for subaccounts — deactivate it so it can't receive funds.
        console.error('❌ Transfer recipient failed, deactivating orphaned subaccount:', subaccountCode);
        await retryFetch(
          `${PAYSTACK_BASE_URL}/subaccount/${subaccountCode}`,
          {
            method: 'PUT',
            headers: {
              'Authorization': `Bearer ${PAYSTACK_SECRET_KEY}`,
              'Content-Type': 'application/json',
            },
            body: JSON.stringify({ active: false }),
          },
          { attempts: 2, baseDelayMs: 500, label: 'paystack.deactivate' },
        ).catch(err =>
          console.error('⚠️ Subaccount deactivation failed (manual cleanup needed):', subaccountCode, (err as Error).message),
        );
        throw recipientErr;
      }
    }

    // ------------------------------------------------------------------
    // Step 3: Persist to database (same table, works for both paths)
    // ------------------------------------------------------------------
    await supabase
      .from('payment_settings')
      .upsert({
        shop_id: shopId,
        payment_provider: 'paystack',
        paystack_subaccount_code: subaccountCode,
        paystack_recipient_id: recipientCode,
        paystack_verified: true,
        paystack_currency: currencyCode,
        connected_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      });

    console.log('✅ Saved to payment_settings');

    await audit(supabase, {
      action: 'subaccount.create',
      actorUserId,
      shopId,
      targetId: recipientCode ?? subaccountCode,
      outcome: 'success',
      context: {
        provider: 'paystack',
        currency: currencyCode,
        flow: mobileMoneyFlow ? 'mobile_money' : 'bank',
      },
    });

    return new Response(
      JSON.stringify({
        success: true,
        subaccount_code: subaccountCode,   // null for mobile money — that's fine
        recipient_code: recipientCode,
      }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );

  } catch (error) {
    console.error('❌ Error in createSubaccount:', (error as Error).message);
    await audit(supabase, {
      action: 'subaccount.create',
      actorUserId,
      shopId,
      outcome: 'failure',
      context: {
        provider: 'paystack',
        currency: currencyCode,
        flow: mobileMoneyFlow ? 'mobile_money' : 'bank',
        error: (error as Error).message,
      },
    });
    return new Response(
      JSON.stringify({ error: (error as Error).message }),
      { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }
}

// ============================================================================
// Helper — Create transfer recipient for a Ghana bank account (ghipss)
// ============================================================================
async function createBankRecipient(params: {
  businessName: string;
  bankCode: string;
  accountNumber: string;
  currencyCode: string;
}): Promise<string> {
  const recipientType = recipientTypeForCurrency(params.currencyCode);

  const body = {
    type: recipientType,
    name: params.businessName,
    account_number: params.accountNumber,
    bank_code: params.bankCode,
    currency: params.currencyCode,
  };

  const res = await retryFetch(
    `${PAYSTACK_BASE_URL}/transferrecipient`,
    {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${PAYSTACK_SECRET_KEY}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(body),
    },
    { attempts: 3, baseDelayMs: 500, label: 'paystack.bankRecipient' },
  );

  const data = await res.json();

  if (!data.status) {
    throw new Error(data.message || 'Bank transfer recipient creation failed');
  }

  console.log('✅ Bank transfer recipient created (type:', recipientType, ')');
  return data.data.recipient_code;
}

// ============================================================================
// Helper — Create transfer recipient for Ghana mobile money
//
// Paystack expects:
//   type         → "mobile_money"
//   bank_code    → the MoMo provider code  (mtn | vod | atl)
//   account_number → the subscriber's phone number  e.g. "0241234567"
//   currency     → "GHS"
// ============================================================================
async function createMobileMoneyRecipient(params: {
  businessName: string;
  bankCode: string;
  accountNumber: string;
  currencyCode: string;
}): Promise<string> {
  const body = {
    type: 'mobile_money',
    name: params.businessName,
    account_number: params.accountNumber,
    bank_code: params.bankCode,
    currency: params.currencyCode,
  };

  console.log('💳 Creating mobile money recipient for provider:', params.bankCode);

  const res = await retryFetch(
    `${PAYSTACK_BASE_URL}/transferrecipient`,
    {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${PAYSTACK_SECRET_KEY}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(body),
    },
    { attempts: 3, baseDelayMs: 500, label: 'paystack.momoRecipient' },
  );

  const data = await res.json();

  if (!data.status) {
    throw new Error(data.message || 'Mobile money recipient creation failed');
  }

  console.log('✅ Mobile money recipient created');
  return data.data.recipient_code;
}

// ============================================================================
// Get Subaccount Status
// ============================================================================
async function getSubaccountStatus(shopId: string) {
  const { data: settings } = await supabase
    .from('payment_settings')
    .select('paystack_subaccount_code, paystack_verified, paystack_recipient_id, paystack_payment_type')
    .eq('shop_id', shopId)
    .single();

  return new Response(
    JSON.stringify({
      // For mobile money, subaccount_code is null — connected is true if recipient exists
      connected: !!(settings?.paystack_subaccount_code || settings?.paystack_recipient_id),
      verified: settings?.paystack_verified,
      has_recipient: !!settings?.paystack_recipient_id,
      payment_type: settings?.paystack_payment_type ?? null,
    }),
    { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
  );
}

// ============================================================================
// Disconnect Subaccount
// ============================================================================
async function disconnectSubaccount(shopId: string, actorUserId: string) {
  const { error } = await supabase
    .from('payment_settings')
    .update({
      payment_provider: null,
      paystack_subaccount_code: null,
      paystack_recipient_id: null,
      paystack_verified: false,
      paystack_business_name: null,
      paystack_account_number: null,
      paystack_currency: null,
      paystack_payment_type: null,
      connected_at: null,
    })
    .eq('shop_id', shopId);

  await audit(supabase, {
    action: 'subaccount.disconnect',
    actorUserId,
    shopId,
    outcome: error ? 'failure' : 'success',
    context: error ? { error: error.message } : { provider: 'paystack' },
  });

  return new Response(
    JSON.stringify({ success: true }),
    { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
  );
}
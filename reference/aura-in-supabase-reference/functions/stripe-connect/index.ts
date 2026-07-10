// supabase/functions/stripe-connect/index.ts

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import Stripe from "https://esm.sh/stripe@13.6.0";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";

const stripe = new Stripe(Deno.env.get('STRIPE_SECRET_KEY')!, {
  apiVersion: '2023-10-16',
});

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
);

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
};

const STRIPE_REDIRECT_URI = Deno.env.get('STRIPE_REDIRECT_URI')!;
const APP_ORIGIN = Deno.env.get('APP_ORIGIN')!;

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

function withTimeout<T>(promise: Promise<T>, ms: number): Promise<T> {
  return Promise.race([
    promise,
    new Promise<never>((_, reject) =>
      setTimeout(() => reject(new Error(`Operation timed out after ${ms}ms`)), ms)
    ),
  ]);
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  const url = new URL(req.url);
  const action = url.searchParams.get('action');

  if (action === 'handle-callback') {
    return await handleOAuthCallback(
      url.searchParams.get('code'),
      url.searchParams.get('state'),
      url.searchParams.get('error'),
    );
  }

  try {
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) return json({ error: 'Unauthorized' }, 401);

    const token = authHeader.replace('Bearer ', '');
    const { data: { user }, error: userError } = await supabase.auth.getUser(token);
    if (userError || !user) return json({ error: 'Unauthorized' }, 401);

    const { data: shop } = await supabase
      .from('shops')
      .select('id')
      .eq('user_id', user.id)
      .single();

    if (!shop) return json({ error: 'Shop not found' }, 404);

    switch (action) {
      case 'create-oauth-link':
        return await createOAuthLink(shop.id, user.id);
      case 'get-status':
        return await getAccountStatus(shop.id);
      case 'disconnect':
        return await disconnectAccount(shop.id);
      default:
        return json({ error: 'Invalid action' }, 400);
    }
  } catch (error) {
    console.error('Unhandled error:', error);
    return json({ error: 'Internal server error' }, 500);
  }
});

// ============================================================================
// Create OAuth Link
// ============================================================================
async function createOAuthLink(shopId: string, userId: string) {
  // Rate limit: max 5 pending OAuth initiations per user to prevent OAuth-state table flooding
  const { count: pendingCount } = await supabase
    .from('oauth_states')
    .select('state_nonce', { count: 'exact', head: true })
    .eq('user_id', userId)
    .gte('expires_at', new Date().toISOString());

  if ((pendingCount ?? 0) >= 5) {
    console.warn('🚫 Stripe OAuth rate limit exceeded for user:', userId);
    return json(
      { error: 'Too many pending connection attempts. Please wait a few minutes before trying again.' },
      429,
    );
  }

  const stateNonce = crypto.randomUUID();

  const { error } = await supabase.from('oauth_states').insert({
    state_nonce: stateNonce,
    shop_id: shopId,
    user_id: userId,
    expires_at: new Date(Date.now() + 10 * 60 * 1000).toISOString(),
  });

  if (error) {
    console.error('Failed to store oauth state:', error);
    return json({ error: 'Failed to initiate OAuth flow' }, 500);
  }

  const oauthLink = stripe.oauth.authorizeUrl({
    client_id: Deno.env.get('STRIPE_CLIENT_ID')!,
    redirect_uri: STRIPE_REDIRECT_URI,
    state: stateNonce,
    scope: 'read_write',
  });

  return json({ url: oauthLink });
}

// ============================================================================
// Handle OAuth Callback
// ============================================================================
async function handleOAuthCallback(
  code: string | null,
  state: string | null,
  stripeError: string | null,
) {
  const htmlResponse = (type: 'success' | 'error', payload?: string) => new Response(
    `<!DOCTYPE html><html><body><script>
      const msg = { type: '${type === 'success' ? 'STRIPE_CONNECT_SUCCESS' : 'STRIPE_CONNECT_ERROR'}' ${payload ? `, error: ${JSON.stringify(payload)}` : ''} };
      if (window.opener) {
        window.opener.postMessage(msg, ${JSON.stringify(APP_ORIGIN)});
      }
      window.close();
    </script></body></html>`,
    { headers: { 'Content-Type': 'text/html' } },
  );

  if (stripeError) {
    return htmlResponse('error', `Stripe error: ${stripeError}`);
  }

  if (!code || !state) {
    return htmlResponse('error', 'Missing code or state parameter');
  }

  const { data: oauthState, error: stateError } = await supabase
    .from('oauth_states')
    .select('shop_id, user_id, expires_at')
    .eq('state_nonce', state)
    .single();

  if (stateError || !oauthState) {
    return htmlResponse('error', 'Invalid state token');
  }

  if (new Date(oauthState.expires_at) < new Date()) {
    await supabase.from('oauth_states').delete().eq('state_nonce', state);
    return htmlResponse('error', 'OAuth session expired. Please try again.');
  }

  const { data: ownerCheck } = await supabase
    .from('shops')
    .select('id')
    .eq('id', oauthState.shop_id)
    .eq('user_id', oauthState.user_id)
    .single();

  if (!ownerCheck) {
    await supabase.from('oauth_states').delete().eq('state_nonce', state);
    return htmlResponse('error', 'Shop ownership verification failed');
  }

  await supabase.from('oauth_states').delete().eq('state_nonce', state);

  try {
    // 1. Exchange auth code for access token
    const tokenResponse = await withTimeout(
      stripe.oauth.token({ grant_type: 'authorization_code', code }),
      10_000,
    );

    const { stripe_user_id } = tokenResponse;
    if (!stripe_user_id) throw new Error('No stripe_user_id in token response');

    // 2. Fetch capabilities BEFORE writing — avoids a race window where
    //    stripe_verified=true is committed but the account isn't ready yet.
    const account = await withTimeout(
      stripe.accounts.retrieve(stripe_user_id),
      10_000,
    );

    const isVerified = !!(account.charges_enabled && account.payouts_enabled);
    const currency = (account.default_currency ?? 'usd').toUpperCase();

    // 3. Single atomic upsert with the correct verified status
    const { error: upsertError } = await supabase.from('payment_settings').upsert({
      shop_id: oauthState.shop_id,
      payment_provider: 'stripe',
      stripe_account_id: stripe_user_id,
      stripe_verified: isVerified,
      stripe_currency: currency,
      connected_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
    });

    if (upsertError) throw upsertError;

    return htmlResponse('success');
  } catch (error) {
    console.error('Stripe OAuth token exchange failed:', error);
    // Clean up any partial state — only removes the row if it was just created.
    await supabase
      .from('payment_settings')
      .delete()
      .eq('shop_id', oauthState.shop_id)
      .eq('payment_provider', 'stripe');
    return htmlResponse('error', 'Failed to connect Stripe account. Please try again.');
  }
}

// ============================================================================
// Get Account Status
// ============================================================================
async function getAccountStatus(shopId: string) {
  const { data: settings } = await supabase
    .from('payment_settings')
    .select('stripe_account_id, stripe_verified, stripe_currency')
    .eq('shop_id', shopId)
    .single();

  return json({
    connected: !!settings?.stripe_account_id,
    verified: settings?.stripe_verified ?? false,
    currency: settings?.stripe_currency ?? null,
  });
}

// ============================================================================
// Disconnect Account
// ============================================================================
async function disconnectAccount(shopId: string) {
  const { data: settings } = await supabase
    .from('payment_settings')
    .select('stripe_account_id')
    .eq('shop_id', shopId)
    .single();

  if (settings?.stripe_account_id) {
    try {
      await withTimeout(
        stripe.oauth.deauthorize({
          client_id: Deno.env.get('STRIPE_CLIENT_ID')!,
          stripe_user_id: settings.stripe_account_id,
        }),
        8_000,
      );
    } catch (err) {
      console.warn('Stripe deauthorise call failed (proceeding with local disconnect):', err.message);
    }
  }

  // ✅ Clear only Stripe fields (keep Paystack if present)
  await supabase
    .from('payment_settings')
    .update({
      payment_provider: null,
      stripe_account_id: null,
      stripe_verified: null,
      stripe_currency: null,
      connected_at: null,
      updated_at: new Date().toISOString(),
    })
    .eq('shop_id', shopId);

  return json({ success: true });
}
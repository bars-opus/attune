import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";

// ── Config ────────────────────────────────────────────────────────────────────

const ONE_SIGNAL_APP_ID = Deno.env.get("ONE_SIGNAL_APP_ID")!;
const ONE_SIGNAL_API_KEY = Deno.env.get("ONE_SIGNAL_API_KEY")!;
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

// ── Auth ──────────────────────────────────────────────────────────────────────

/**
 * Validates the Authorization header.
 *
 * Accepts two modes:
 *  - Service-role Bearer token → trusted internal call (edge function → edge function).
 *    Can target ANY userId.
 *  - User JWT → must be a valid Supabase session. Can only target their own userId
 *    unless they provide no userId (derived from JWT).
 *
 * Returns the verified Supabase user ID, or null on failure.
 */
async function verifyAuth(
  authHeader: string | null,
  bodyUserId: string
): Promise<{ authorizedUserId: string } | null> {
  if (!authHeader) return null;

  // ── Internal service-role call (process-scheduled-notifications, etc.) ──────
  if (authHeader === `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`) {
    if (!bodyUserId) return null;
    return { authorizedUserId: bodyUserId };
  }

  // ── User JWT call ─────────────────────────────────────────────────────────
  const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: authHeader } },
  });

  const {
    data: { user },
    error,
  } = await supabase.auth.getUser();

  if (error || !user) return null;

  // Users can only push to themselves (prevents one user spamming another).
  // If no userId in body, default to the requesting user.
  const targetUserId = bodyUserId || user.id;
  if (targetUserId !== user.id) return null;

  return { authorizedUserId: user.id };
}

// ── Handler ───────────────────────────────────────────────────────────────────

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const body = await req.json();
    const { userId, title, body: notifBody, data, priority } = body;

    if (!title || !notifBody) {
      return new Response(
        JSON.stringify({ error: "title and body are required" }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    const authHeader = req.headers.get("Authorization");
    const auth = await verifyAuth(authHeader, userId);

    if (!auth) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const payload = {
      app_id: ONE_SIGNAL_APP_ID,
      include_external_user_ids: [auth.authorizedUserId],
      headings: { en: title },
      contents: { en: notifBody },
      data: data ?? {},
      priority: priority === "high" ? 10 : 5,
    };

    const response = await fetch("https://onesignal.com/api/v1/notifications", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Basic ${ONE_SIGNAL_API_KEY}`,
      },
      body: JSON.stringify(payload),
    });

    const result = await response.json();

    if (!response.ok) {
      console.error("OneSignal error:", result);
      return new Response(
        JSON.stringify({ error: "OneSignal delivery failed", detail: result }),
        {
          status: 502,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    return new Response(JSON.stringify({ success: true, result }), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    console.error("send-onesignal-push error:", error);
    return new Response(JSON.stringify({ error: String(error) }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";

// ── Config ────────────────────────────────────────────────────────────────────

const SENDBIRD_APP_ID = Deno.env.get("SENDBIRD_APP_ID")!;
const SENDBIRD_API_TOKEN = Deno.env.get("SENDBIRD_API_TOKEN")!;
const SENDBIRD_BASE = `https://api-${SENDBIRD_APP_ID}.sendbird.com/v3`;

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const sendbirdHeaders = {
  "Api-Token": SENDBIRD_API_TOKEN,
  "Content-Type": "application/json",
};

// ── Helpers ───────────────────────────────────────────────────────────────────

async function ensureSendbirdUser(
  userId: string,
  nickname: string,
  profileUrl: string,
): Promise<void> {
  const res = await fetch(`${SENDBIRD_BASE}/users`, {
    method: "POST",
    headers: sendbirdHeaders,
    body: JSON.stringify({
      user_id: userId,
      nickname: nickname || userId,
      profile_url: profileUrl || "",
    }),
  });

  if (!res.ok) {
    const body = await res.json();
    // 400202 = user already exists — update nickname/avatar to stay in sync.
    if (body?.code === 400202) {
      await fetch(`${SENDBIRD_BASE}/users/${userId}`, {
        method: "PUT",
        headers: sendbirdHeaders,
        body: JSON.stringify({
          nickname: nickname || userId,
          profile_url: profileUrl || "",
        }),
      });
    } else {
      throw new Error(`Sendbird user upsert failed: ${JSON.stringify(body)}`);
    }
  }
}

async function issueSendbirdToken(userId: string): Promise<string> {
  const res = await fetch(`${SENDBIRD_BASE}/users/${userId}/token`, {
    method: "POST",
    headers: sendbirdHeaders,
    body: JSON.stringify({}),
  });

  if (!res.ok) {
    const body = await res.json();
    throw new Error(`Sendbird token request failed: ${JSON.stringify(body)}`);
  }

  const data = await res.json();
  return data.token as string;
}

// ── Handler ───────────────────────────────────────────────────────────────────

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // 1. Verify caller is authenticated via their Supabase JWT.
    //    The Flutter SDK attaches the session token automatically when calling
    //    supabase.functions.invoke(), so we can trust the Authorization header.
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const jwt = authHeader.replace(/^Bearer\s+/i, "");

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
    );

    const {
      data: { user },
      error: authError,
    } = await supabase.auth.getUser(jwt);

    if (authError || !user) {
      console.error("Auth failed:", authError?.message);
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const userId = user.id;

    // 2. Fetch the user's Supabase profile so Sendbird gets the real name/avatar.
    const supabaseAdmin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );
    const { data: profile } = await supabaseAdmin
      .from("profiles")
      .select("display_name, username, avatar_url")
      .eq("id", userId)
      .single();

    const nickname = profile?.display_name || profile?.username || userId;
    const profileUrl = profile?.avatar_url ?? "";

    // 3. Ensure the Sendbird user exists with real name/avatar.
    await ensureSendbirdUser(userId, nickname, profileUrl);

    // 4. Issue a session token — user is now guaranteed to exist.
    const token = await issueSendbirdToken(userId);

    return new Response(JSON.stringify({ token }), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (err) {
    console.error("sendbird-auth error:", err);
    return new Response(JSON.stringify({ error: String(err) }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});

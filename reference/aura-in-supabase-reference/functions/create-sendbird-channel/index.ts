import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";

const SENDBIRD_APP_ID = Deno.env.get("SENDBIRD_APP_ID")!;
const SENDBIRD_API_TOKEN = Deno.env.get("SENDBIRD_API_TOKEN")!;
const SENDBIRD_BASE = `https://api-${SENDBIRD_APP_ID}.sendbird.com/v3`;

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const sbHeaders = {
  "Api-Token": SENDBIRD_API_TOKEN,
  "Content-Type": "application/json",
};

// Create user if they don't exist; update nickname+avatar if they do.
async function upsertSendbirdUser(
  userId: string,
  nickname: string,
  profileUrl: string,
): Promise<void> {
  const createResp = await fetch(`${SENDBIRD_BASE}/users`, {
    method: "POST",
    headers: sbHeaders,
    body: JSON.stringify({
      user_id: userId,
      nickname: nickname || userId,
      profile_url: profileUrl || "",
    }),
  });

  if (!createResp.ok) {
    const body = await createResp.json();
    // 400202 = user already exists — update their profile instead.
    if (body?.code === 400202) {
      await fetch(`${SENDBIRD_BASE}/users/${userId}`, {
        method: "PUT",
        headers: sbHeaders,
        body: JSON.stringify({
          nickname: nickname || userId,
          profile_url: profileUrl || "",
        }),
      });
    } else {
      console.error(`upsertSendbirdUser(${userId}) failed:`, body);
    }
  }
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // 1. Verify caller identity via Supabase JWT.
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // In supabase-js v2, getUser() without args looks for a stored session
    // which doesn't exist in a freshly-created server-side client.
    // Pass the JWT directly so it validates against the Auth API.
    const jwt = authHeader.replace(/^Bearer\s+/i, "");

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
    );

    const { data: { user }, error: authError } = await supabase.auth.getUser(jwt);
    if (authError || !user) {
      console.error("Auth failed:", authError?.message);
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // 2. Parse request body.
    const { target_user_id, channel_name } = await req.json();
    if (!target_user_id) {
      return new Response(JSON.stringify({ error: "target_user_id is required" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const currentUserId = user.id;

    // 3. Fetch both user profiles from Supabase so Sendbird gets real names.
    const [{ data: currentProfile }, { data: targetProfile }] = await Promise.all([
      supabase.from("profiles").select("display_name, username, avatar_url").eq("id", currentUserId).single(),
      supabase.from("profiles").select("display_name, username, avatar_url").eq("id", target_user_id).single(),
    ]);

    const currentNickname = currentProfile?.display_name || currentProfile?.username || currentUserId;
    const targetNickname = targetProfile?.display_name || targetProfile?.username || target_user_id;

    // 4. Ensure both users exist in Sendbird (creates or updates).
    await Promise.all([
      upsertSendbirdUser(currentUserId, currentNickname, currentProfile?.avatar_url ?? ""),
      upsertSendbirdUser(target_user_id, targetNickname, targetProfile?.avatar_url ?? ""),
    ]);

    // 5. Create (or retrieve the existing) distinct 1:1 channel via Platform API.
    //    Sendbird returns the existing channel when the exact member set + isDistinct
    //    already exists, so this is safe to call multiple times.
    const channelResp = await fetch(`${SENDBIRD_BASE}/group_channels`, {
      method: "POST",
      headers: sbHeaders,
      body: JSON.stringify({
        user_ids: [currentUserId, target_user_id],
        is_distinct: true,
        name: channel_name || targetNickname,
      }),
    });

    const channelData = await channelResp.json();
    if (!channelResp.ok) {
      console.error("Sendbird channel creation failed:", channelData);
      return new Response(
        JSON.stringify({ error: "Channel creation failed", details: channelData }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    console.log(`Channel ready: ${channelData.channel_url} | members=${channelData.member_count}`);

    return new Response(
      JSON.stringify({
        channel_url: channelData.channel_url,
        name: channelData.name,
        member_count: channelData.member_count,
      }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (err) {
    console.error("create-sendbird-channel error:", err);
    return new Response(JSON.stringify({ error: String(err) }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});

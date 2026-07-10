import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    const now = new Date();
    const inviteCutoff = new Date(now.getTime() - 48 * 60 * 60 * 1000)
      .toISOString();
    const inactivityCutoff = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000)
      .toISOString();

    const { data: expiredInvites, error: inviteError } = await supabase
      .from("game_sessions")
      .update({
        status: "abandoned",
        abandon_reason: "invite_expired",
        abandoned_at: now.toISOString(),
      })
      .eq("game_type", "36_questions")
      .eq("status", "invited")
      .lt("created_at", inviteCutoff)
      .select("id");

    if (inviteError) throw inviteError;

    const { data: inactiveChapters, error: inactiveError } = await supabase
      .from("game_sessions")
      .update({
        status: "abandoned",
        abandon_reason: "inactivity",
        abandoned_at: now.toISOString(),
      })
      .eq("game_type", "36_questions")
      .eq("status", "active")
      .lt("started_at", inactivityCutoff)
      .select("id");

    if (inactiveError) throw inactiveError;

    return new Response(
      JSON.stringify({
        expired_invites: expiredInvites?.length ?? 0,
        inactive_chapters: inactiveChapters?.length ?? 0,
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (error) {
    console.error("expire-thirty-six-chapters error:", error);
    return new Response(
      JSON.stringify({ error: errorMessage(error) }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});

function errorMessage(error: unknown) {
  return error instanceof Error ? error.message : "Unknown error";
}

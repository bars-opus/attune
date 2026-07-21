// supabase/functions/activate-topics/index.ts
//
// Was hand-rolling activation/expiry logic with an inverted filter
// (`voting_expires_at < now()` — "already expired" — instead of `> now()`,
// "still open"), so it only ever considered topics whose 14-day voting
// window had already closed, the opposite of FORUM.md §5.3's "activate as
// soon as the threshold is crossed." The correct logic already existed as
// two DB RPCs (activate_pending_topics, expire_old_topics — see
// 20260716120000_forums_opinions_launch.sql) that the client also calls
// opportunistically on forum-list load; this function now just delegates to
// those instead of re-implementing (and re-breaking) the same conditions.
// Also replaces the previous console.log-only "notification" with a real
// OneSignal push via the shared helper.

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";

import { jsonResponse, requireServiceRole, serviceRoleClient } from "../_shared/attune_auth.ts";
import { sendOneSignalPush } from "../_shared/onesignal_push.ts";

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return jsonResponse({ ok: true });
  }

  const supabase = serviceRoleClient();

  try {
    requireServiceRole(req);

    // Snapshot which topics are eligible BEFORE activating, so we know which
    // rows the RPC actually flipped (it returns only a count) and can look up
    // their voters for notifications.
    const { data: eligible, error: eligibleError } = await supabase
      .from("forum_topics")
      .select("id, content")
      .eq("status", "voting")
      .gte("seen_count", 20)
      .gt("voting_expires_at", new Date().toISOString());
    if (eligibleError) throw eligibleError;

    const candidates = (eligible ?? []).filter((t) => typeof t.id === "string");

    const { data: activatedCount, error: activateError } = await supabase.rpc(
      "activate_pending_topics",
    );
    if (activateError) throw activateError;

    const { data: expiredCount, error: expireError } = await supabase.rpc(
      "expire_old_topics",
    );
    if (expireError) throw expireError;

    // Re-check which of the candidates actually activated (activate_pending_topics
    // re-applies the >50%/seen>=20/still-open filter itself, so a candidate here
    // may not have crossed the threshold) and notify their voters.
    const notified: string[] = [];
    if (candidates.length > 0 && Number(activatedCount) > 0) {
      const { data: nowActive, error: activeError } = await supabase
        .from("forum_topics")
        .select("id, content")
        .in("id", candidates.map((t) => t.id))
        .eq("status", "active");
      if (activeError) throw activeError;

      for (const topic of nowActive ?? []) {
        await notifyTopicVoters(supabase, String(topic.id), String(topic.content));
        notified.push(String(topic.id));
      }
    }

    return jsonResponse({
      success: true,
      activated: Number(activatedCount) || 0,
      expired: Number(expiredCount) || 0,
      notified: notified.length,
    });
  } catch (error) {
    return jsonResponse(
      { success: false, error: error instanceof Error ? error.message : String(error) },
      500,
    );
  }
});

async function notifyTopicVoters(
  supabase: ReturnType<typeof serviceRoleClient>,
  topicId: string,
  content: string,
) {
  const { data: votes, error } = await supabase
    .from("topic_votes")
    .select("user_id, vote_type")
    .eq("topic_id", topicId);
  if (error) throw error;

  const shortTitle = content.length > 50 ? `${content.slice(0, 50)}...` : content;

  for (const vote of votes ?? []) {
    const userId = typeof vote.user_id === "string" ? vote.user_id : null;
    if (!userId) continue;
    const side = vote.vote_type === "up" ? "FOR" : "AGAINST";

    try {
      await sendOneSignalPush({
        userId,
        title: "Your topic is live",
        body: `'${shortTitle}' is now a debate. You're ${side} →`,
        data: { type: "forum_topic_activated", topic_id: topicId },
        idempotencyKey: `forum-topic-activated-${topicId}-${userId}`,
      });
    } catch (pushError) {
      // One recipient's push failing (e.g. no registered device) must not
      // abort notifying the rest of the voters.
      console.error(`Failed to notify ${userId} for topic ${topicId}:`, pushError);
    }
  }
}

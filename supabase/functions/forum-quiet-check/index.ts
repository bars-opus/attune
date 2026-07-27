// supabase/functions/forum-quiet-check/index.ts
//
// FORUM.md §10 notification #6 ("Forum going quiet").
//
// FORUM.md §11 step 35 defines quiet as "7 days no posts -> status = 'quiet'"
// and step 36 as "forum quiet notifications (sent once only)".
//
// This function does ONLY the notify half. The active -> quiet transition
// itself is NOT done here, on purpose: a pre-existing pg_cron job
// (`mark-quiet-forums`, registered directly against the database, not
// tracked in any migration in this repo -- discovered only by querying
// cron.job) already performs that transition daily. mark_quiet_topics()
// in 20260727130000_forum_activity_notifications.sql was originally written
// to also do this, but was decided against being registered to avoid two
// independent definitions of "quiet" drifting apart -- see that migration's
// header comment for the one known gap in the existing job (it requires
// last_post_at IS NOT NULL, so a topic that activated but never received a
// single post can never go quiet) and the follow-up patch for it.
//
// notify_quiet_topic (same migration) only INSERTs into scheduled_notifications
// once per topic (enforced by quiet_notification_sent), regardless of which
// job flipped the status -- it polls status = 'quiet', it does not care how a
// topic got there. Delivery is NOT done here either:
// process-scheduled-notifications is what actually calls OneSignal.

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";

import { jsonResponse, requireServiceRole, serviceRoleClient } from "../_shared/attune_auth.ts";

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return jsonResponse({ ok: true });
  }

  const supabase = serviceRoleClient();

  try {
    requireServiceRole(req);

    // Notify participants of every topic that is quiet and not yet notified.
    // The active -> quiet transition itself happens elsewhere (see file header) --
    // this deliberately doesn't care which run (or which job) flipped a given
    // topic to 'quiet'. The quiet_notification_sent flag, not this function's
    // control flow, is what enforces "sent once only".
    const { data: pending, error: pendingError } = await supabase
      .from("forum_topics")
      .select("id")
      .eq("status", "quiet")
      .eq("quiet_notification_sent", false)
      .limit(200);
    if (pendingError) throw pendingError;

    let notifiedTopics = 0;
    let queuedNotifications = 0;

    for (const topic of pending ?? []) {
      const topicId = typeof topic.id === "string" ? topic.id : null;
      if (!topicId) continue;

      try {
        // notify_quiet_topic claims the topic by flipping
        // quiet_notification_sent inside the same transaction as the inserts,
        // so a concurrent run of this sweep queues nothing and returns 0.
        const { data: queued, error: notifyError } = await supabase.rpc("notify_quiet_topic", {
          p_topic_id: topicId,
        });
        if (notifyError) throw notifyError;

        queuedNotifications += Number(queued) || 0;
        notifiedTopics++;
      } catch (topicError) {
        // One topic failing (bad data, transient DB error) must not abort the
        // rest of the batch -- same per-recipient isolation as activate-topics.
        // The topic keeps quiet_notification_sent = false and is retried next run.
        console.error(`Failed to queue quiet notifications for topic ${topicId}:`, topicError);
      }
    }

    return jsonResponse({
      success: true,
      notified_topics: notifiedTopics,
      queued_notifications: queuedNotifications,
    });
  } catch (error) {
    return jsonResponse(
      { success: false, error: error instanceof Error ? error.message : String(error) },
      500,
    );
  }
});

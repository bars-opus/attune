// supabase/functions/send-notification/index.ts

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { sendOneSignalPush } from "../_shared/onesignal_push.ts";
import { requireServiceRole } from "../_shared/attune_auth.ts";

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
    requireServiceRole(req);
    const {
      userId,
      type,
      partnerName,
      newScore,
      delta,
      eventType,
      title,
      chapter,
      journeyId,
      sessionId,
    } = await req.json();

    // Build notification based on type
    let titleText = "";
    let bodyText = "";
    let notificationData = {};

    switch (type) {
      case "checkin_reminder":
        titleText = "Weekly check-in";
        bodyText = `How was your week with ${partnerName}? Takes 60 seconds.`;
        notificationData = {
          type: "checkin_reminder",
          screen: "weekly_checkin",
        };
        break;

      case "pulse_updated":
        titleText = "Pulse score updated";
        if (delta && delta > 0) {
          bodyText =
            `Your pulse score is ${newScore} — up ${delta} points from last week.`;
        } else if (delta && delta < 0) {
          bodyText = `Your pulse score is ${newScore}. See what's changed.`;
        } else {
          bodyText = `Your pulse score has been updated to ${newScore}.`;
        }
        notificationData = {
          type: "pulse_updated",
          screen: "pulse",
          score: newScore,
        };
        break;

      case "moment_logged":
        const eventDisplay = _getEventTypeDisplay(eventType);
        titleText = `${partnerName} logged a moment`;
        bodyText = `${eventDisplay}: ${title}`;
        notificationData = {
          type: "moment_logged",
          screen: "timeline",
          event_type: eventType,
        };
        break;

      case "thirty_six_question_invite":
        titleText = `${partnerName ?? "Your partner"} invited you to continue`;
        bodyText = `36 Questions Journey · Chapter ${chapter ?? ""}`;
        notificationData = {
          type: "thirty_six_question_invite",
          screen: "thirty_six_questions",
          journey_id: journeyId,
          session_id: sessionId,
          chapter,
        };
        break;

      default:
        return new Response(
          JSON.stringify({ error: "Unknown notification type" }),
          { status: 400, headers: corsHeaders },
        );
    }

    await sendOneSignalPush({
      userId,
      title: titleText,
      body: bodyText,
      data: notificationData,
    });

    return new Response(
      JSON.stringify({ success: true, userId, type }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (error) {
    const message = errorMessage(error);
    console.error("Error:", message);
    return new Response(
      JSON.stringify({ error: message }),
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

function _getEventTypeDisplay(eventType: string): string {
  switch (eventType) {
    case "milestone":
      return "Milestone";
    case "highlight":
      return "Highlight";
    case "first":
      return "First";
    case "anniversary":
      return "Anniversary";
    default:
      return eventType;
  }
}

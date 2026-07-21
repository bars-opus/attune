// supabase/functions/evaluate-ask2-eligibility/index.ts
import { serve } from "https://deno.land/std@0.177.0/http/server.ts";

import { jsonResponse, requireServiceRole, serviceRoleClient } from "../_shared/attune_auth.ts";

const REMINDER_WINDOW_MS = 7 * 24 * 60 * 60 * 1000;

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return jsonResponse({ ok: true });
  }

  const supabase = serviceRoleClient();

  try {
    requireServiceRole(req);

    const newlyEligible = await sweepNewlyEligible(supabase);
    const reminded = await sweepReminders(supabase);

    return jsonResponse({
      success: true,
      prompted: newlyEligible.length,
      reminded: reminded.length,
    });
  } catch (error) {
    return jsonResponse(
      { success: false, error: error instanceof Error ? error.message : String(error) },
      500,
    );
  }
});

async function sweepNewlyEligible(
  supabase: ReturnType<typeof serviceRoleClient>,
) {
  // Candidates: active relationships with no ask2_state row yet, or a row
  // still in 'pending' (created but not yet found eligible on a prior sweep).
  const { data: candidates, error } = await supabase
    .from("relationships")
    .select("id, ask2_state(status)")
    .eq("status", "active")
    .not("user_b", "is", null);
  if (error) throw error;

  const results = [];

  for (const relationship of candidates ?? []) {
    const stateRows = relationship.ask2_state as Array<{ status: string }> | null;
    const currentStatus = stateRows && stateRows.length > 0 ? stateRows[0].status : null;
    if (currentStatus && currentStatus !== "pending") continue;

    const { data: eligibility, error: eligError } = await supabase
      .rpc("ask2_eligibility", { p_relationship_id: relationship.id })
      .single();
    if (eligError) throw eligError;

    const row = eligibility as {
      eligible: boolean;
      first_positive_message_id: string | null;
      first_positive_at: string | null;
    };

    if (!row.eligible) {
      await supabase
        .from("ask2_state")
        .upsert({ relationship_id: relationship.id, status: "pending" }, { onConflict: "relationship_id" });
      continue;
    }

    const now = new Date().toISOString();
    await supabase.from("ask2_state").upsert({
      relationship_id: relationship.id,
      status: "prompted",
      eligible_at: now,
      first_positive_message_id: row.first_positive_message_id,
      prompted_at: now,
      updated_at: now,
    }, { onConflict: "relationship_id" });

    await sendAsk2Notification(supabase, String(relationship.id));
    results.push(relationship.id);
  }

  return results;
}

async function sweepReminders(
  supabase: ReturnType<typeof serviceRoleClient>,
) {
  const cutoff = new Date(Date.now() - REMINDER_WINDOW_MS).toISOString();

  const { data: dueForReminder, error } = await supabase
    .from("ask2_state")
    .select("relationship_id, prompted_at")
    .eq("status", "prompted")
    .lt("prompted_at", cutoff);
  if (error) throw error;

  const results = [];

  for (const row of dueForReminder ?? []) {
    const now = new Date().toISOString();
    await supabase
      .from("ask2_state")
      .update({ status: "reminded", reminded_at: now, updated_at: now })
      .eq("relationship_id", row.relationship_id)
      .eq("status", "prompted"); // guard against a race with a concurrent completion

    await sendAsk2Notification(supabase, String(row.relationship_id));
    results.push(row.relationship_id);
  }

  return results;
}

async function sendAsk2Notification(
  supabase: ReturnType<typeof serviceRoleClient>,
  relationshipId: string,
) {
  const { data: relationship, error } = await supabase
    .from("relationships")
    .select("user_a, user_b")
    .eq("id", relationshipId)
    .single();
  if (error) throw error;

  const title = "We noticed something good";
  const body =
    "You two have a real rhythm going. Want to see what Attune can tell you about how you communicate?";
  const data = { type: "ask2_invite", relationship_id: relationshipId };

  for (const userId of [relationship.user_a, relationship.user_b]) {
    if (!userId) continue;
    const { error: inAppError } = await supabase.from("in_app_notifications").insert({
      user_id: userId,
      title,
      body,
      data,
    });
    if (inAppError) throw inAppError;

    const { error: scheduledError } = await supabase.from("scheduled_notifications").insert({
      user_id: userId,
      notification_type: "ask2_invite",
      scheduled_for: new Date().toISOString(),
      status: "pending",
      metadata: data,
    });
    if (scheduledError) throw scheduledError;
  }
}

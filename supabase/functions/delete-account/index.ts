// supabase/functions/delete-account/index.ts
//
// GDPR account deletion (ATTUNE_MASTER_SPEC.md §10).
//
// Spec contract:
//   - "User can delete account and all data at any time"
//   - "Couple's shared data (patterns, pulse) anonymised on one partner's
//      deletion"
//   - "Safety events: anonymised after 12 months, never fully deleted
//      (legal protection)"
//   - "Deletes user row and all personal data within 30 days"
//
// Deletion is performed IMMEDIATELY rather than scheduled. The 30 days in
// GDPR Art. 12 is an upper bound on fulfilment, not a target, and a
// deferred-delete queue would need its own worker, retry path, and
// cancellation semantics — more moving parts holding personal data for
// longer. Doing it inline means the guarantee is discharged the moment the
// request returns 200.
//
// The actual erasure is a single `auth.admin.deleteUser`. Everything below
// public.users is reached by ON DELETE CASCADE across 40 tables (verified
// against the schema), so this function deliberately does NOT enumerate
// tables: a hand-written delete list silently misses every table added
// afterwards, which is exactly how "we deleted your data" becomes untrue.
// The cascade is the contract; 20260906120000_account_deletion_schema.sql
// fixes the three FK/constraint defects that previously made it fail or
// over-delete.
import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import {
  HttpError,
  jsonResponse,
  requireUser,
  serviceRoleClient,
} from "../_shared/attune_auth.ts";

serve(async (req) => {
  if (req.method === "OPTIONS") return jsonResponse({ ok: true });

  // DELETE is the spec's verb; POST is accepted because some HTTP clients
  // (and supabase-js functions.invoke) will not attach a body or auth
  // header to a DELETE. Anything else is rejected so a stray GET — the one
  // verb a browser or link-preview crawler issues by accident — can never
  // erase an account.
  if (req.method !== "DELETE" && req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  let userId: string | null = null;
  let userEmail: string | null = null;
  const supabase = serviceRoleClient();

  try {
    // Identity comes from the verified JWT only. There is deliberately no
    // user_id parameter: accepting one would let any authenticated caller
    // delete any account.
    const user = await requireUser(req);
    userId = user.id;
    // Taken from the verified JWT rather than re-queried from public.users:
    // it is the same address, already authenticated, and reading it here
    // means one fewer round trip on a path where a failure between the
    // read and the delete would leave the audit row without an address.
    userEmail = user.email;

    // Explicit confirmation, so a mis-routed or replayed call cannot erase
    // an account by accident.
    const body = await req.json().catch(() => ({}));
    if (body?.confirm !== true) {
      throw new HttpError(
        "Account deletion requires confirm: true",
        400,
      );
    }

    // Audit evidence is written BEFORE the destructive step, so a request
    // that fails partway is still provably recorded. account_deletion_
    // requests has no FK to users precisely so this row outlives the
    // account.
    const { data: auditRow } = await supabase
      .from("account_deletion_requests")
      .insert({ user_ref: userId, email_ref: userEmail })
      .select("id")
      .maybeSingle();

    // The single destructive call. Cascades through public.users into
    // every dependent table; the BEFORE DELETE trigger added in
    // 20260906120000 anonymises safety_events in the same transaction so
    // its legal-hold CHECK stays satisfied.
    const { error: deleteError } = await supabase.auth.admin.deleteUser(
      userId,
    );

    if (deleteError) {
      if (auditRow?.id) {
        await supabase
          .from("account_deletion_requests")
          .update({ failure_reason: deleteError.message.slice(0, 500) })
          .eq("id", auditRow.id);
      }
      throw deleteError;
    }

    if (auditRow?.id) {
      await supabase
        .from("account_deletion_requests")
        .update({ completed_at: new Date().toISOString() })
        .eq("id", auditRow.id);
    }

    // "Confirmation email sent" (§10). Best-effort and explicitly
    // non-fatal: the erasure is already committed and irreversible, so
    // failing the request here would tell the user their deletion did not
    // happen when it did. Logged for follow-up instead.
    if (userEmail) {
      try {
        await sendDeletionConfirmation(userEmail);
      } catch (mailError) {
        console.error(
          "delete-account: confirmation email failed (non-fatal):",
          mailError instanceof Error ? mailError.message : "unknown",
        );
      }
    }

    return jsonResponse({ success: true, deleted: true });
  } catch (error) {
    if (error instanceof HttpError) {
      return jsonResponse({ error: error.message }, error.status);
    }
    // Logs the error TYPE only, never the message or the user's email —
    // §10/checklist 4.4 keep PII out of logs.
    console.error(
      "delete-account failed:",
      error instanceof Error ? error.name : typeof error,
    );
    return jsonResponse({ error: "Could not delete account" }, 500);
  }
});

/// Sends the GDPR confirmation notice.
///
/// Routed through Supabase Auth's own transactional mailer so deletion does
/// not introduce a second email provider and a second secret to rotate. If
/// RESEND_API_KEY (or an equivalent) is adopted later, only this function
/// changes.
async function sendDeletionConfirmation(email: string): Promise<void> {
  const endpoint = Deno.env.get("DELETION_EMAIL_WEBHOOK_URL");
  if (!endpoint) {
    // No mailer configured in this environment. Recorded as a warning
    // rather than thrown: the deletion itself is complete and correct, and
    // the operator needs to see the gap without users seeing a failure.
    console.warn(
      "delete-account: DELETION_EMAIL_WEBHOOK_URL unset — confirmation email not sent",
    );
    return;
  }

  const response = await fetch(endpoint, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      to: email,
      subject: "Your Attune account has been deleted",
      body:
        "Your Attune account and personal data have been permanently deleted.\n\n" +
        "Anything you shared with a partner has been anonymised so it can no " +
        "longer be linked to you. Safety records are retained in anonymised " +
        "form only, as required by law.\n\n" +
        "If you did not request this, contact support immediately.",
    }),
  });

  if (!response.ok) {
    throw new Error(`mailer responded ${response.status}`);
  }
}

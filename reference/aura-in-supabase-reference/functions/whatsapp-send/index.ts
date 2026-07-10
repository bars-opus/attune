// supabase/functions/whatsapp-send/index.ts
//
// Internal edge function (service-role auth required). Sends a single
// WhatsApp template message via Meta Cloud API. Caller is responsible
// for scheduling and tracking status — this function just does the send.
//
// Used by process-scheduled-notifications (Task 5) and could be called
// from paystack-webhook / stripe-webhook for immediate confirmation if
// desired. Plan A's webhooks currently schedule confirmation with
// scheduled_for=now() and let the worker pick it up — same effect.

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import {
  sendWhatsAppTemplate,
  WhatsAppTemplateNotFoundError,
} from "../_shared/whatsapp_client.ts";
import { redactError } from "../_shared/sanitize.ts";

export async function handler(req: Request): Promise<Response> {
  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  // Require service-role bearer token in the Authorization header.
  // The platform JWT-verify check would accept any Supabase-signed JWT,
  // so we add an explicit service-role check here.
  const auth = req.headers.get("Authorization") ?? "";
  const serviceRole = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!serviceRole || auth !== `Bearer ${serviceRole}`) {
    return json({ error: "Unauthorized" }, 401);
  }

  let body: {
    to?: string;
    template?: string;
    params?: Record<string, string>;
    languageCode?: string;
  };
  try {
    body = await req.json();
  } catch {
    return json({ error: "Invalid JSON" }, 400);
  }

  if (!body.to || !body.template) {
    return json({ error: "Missing 'to' or 'template'" }, 400);
  }

  // Convert params object {"1": "Kwame", "2": "Limit"} into an ordered array.
  // Plan A's webhooks emit the object form so the JSON is self-describing.
  const params = body.params ?? {};
  const ordered = Object.keys(params)
    .sort((a, b) => parseInt(a) - parseInt(b))
    .map((k) => params[k]);

  try {
    const result = await sendWhatsAppTemplate({
      to: body.to,
      templateName: body.template,
      languageCode: body.languageCode,
      bodyParams: ordered,
    });
    return json({ success: true, messageId: result.messageId }, 200);
  } catch (e) {
    if (e instanceof WhatsAppTemplateNotFoundError) {
      // 202 lets the caller defer + retry instead of treating as fatal.
      return json(
        {
          success: false,
          error: "template_not_found",
          message: (e as Error).message,
        },
        202,
      );
    }
    console.error("whatsapp-send error:", redactError(e));
    return json(
      {
        success: false,
        error: "send_failed",
        // Don't echo provider error text to the caller — could leak the phone
        // number from a 400 response or token info from a 401.
        message: "Failed to send WhatsApp message",
      },
      502,
    );
  }
}

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

serve(handler);

// supabase/functions/_shared/booking_helpers.ts
//
// Shared helpers for guest-mode booking. Used by create-booking,
// paystack-webhook, and stripe-webhook to keep guest handling DRY.

import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";
import { redactError } from "./sanitize.ts";

/**
 * Normalize phone to E.164 (+<digits>). Strips spaces and dashes.
 * Throws if format is invalid (does not start with + or too short).
 */
export function normalizePhone(raw: string): string {
  const stripped = raw.replace(/[\s-]/g, "");
  if (!stripped.startsWith("+")) {
    throw new Error("Phone must start with + (E.164)");
  }
  const digits = stripped.slice(1);
  if (!/^\d+$/.test(digits)) {
    throw new Error("Phone must contain only digits after +");
  }
  if (digits.length < 8 || digits.length > 15) {
    throw new Error("Phone must be 8-15 digits");
  }
  return stripped;
}

/**
 * Upsert a guest profile by phone. Latest-writer-wins on name.
 * Returns the profile id.
 */
export async function upsertGuestProfile(
  supabase: SupabaseClient,
  phone: string,
  name: string,
): Promise<string> {
  const normalized = normalizePhone(phone);
  const { data, error } = await supabase
    .from("guest_profiles")
    .upsert(
      {
        phone: normalized,
        name,
        last_seen_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      },
      { onConflict: "phone" },
    )
    .select("id")
    .single();

  if (error || !data) {
    throw new Error(`guest_profiles upsert failed: ${error?.message ?? "no data"}`);
  }
  return (data as { id: string }).id;
}

/**
 * Append a row to guest_booking_history for prefill ordering.
 * Fire-and-forget; failure does not block the booking flow.
 */
export async function recordGuestBookingHistory(
  supabase: SupabaseClient,
  guestProfileId: string,
  serviceName: string,
  shopId: string | null,
): Promise<void> {
  try {
    await supabase.from("guest_booking_history").insert({
      guest_profile_id: guestProfileId,
      service_name: serviceName,
      shop_id: shopId,
      booked_at: new Date().toISOString(),
    });
  } catch (e) {
    console.error("guest_booking_history insert failed (non-fatal):", redactError(e));
  }
}

/**
 * Build the params object for WhatsApp template booking_confirmation_v1.
 * Template: "Hi {{1}}, your booking at {{2}} is confirmed for {{3}}.
 *           Address: {{4}}. Deposit paid: {{5}}. Remaining: {{6}} (pay after service)."
 */
export function buildConfirmationParams(args: {
  guestName: string;
  targetName: string;
  startTime: string; // ISO
  address: string;
  depositAmount: string;
  remainingAmount: string;
}): Record<string, string> {
  // Meta rejects (#131008) any template send where a body param is empty.
  // Default missing strings to an em-dash so the message still goes through
  // for shops that haven't set an address yet.
  const safe = (v: string) => (v && v.trim().length > 0 ? v : "—");
  return {
    "1": safe(args.guestName),
    "2": safe(args.targetName),
    "3": safe(formatDateForHuman(args.startTime)),
    "4": safe(args.address),
    "5": safe(args.depositAmount),
    "6": safe(args.remainingAmount),
  };
}

/**
 * Format an ISO timestamp into a human-friendly string suitable for WhatsApp
 * messages, e.g., "Fri 29 May at 10:30am".
 */
export function formatDateForHuman(iso: string): string {
  const d = new Date(iso);
  const dayName = d.toLocaleDateString("en-GB", { weekday: "short" });
  const day = d.getDate();
  const month = d.toLocaleDateString("en-GB", { month: "short" });
  const hour = d.getHours() % 12 || 12;
  const minute = d.getMinutes().toString().padStart(2, "0");
  const ampm = d.getHours() < 12 ? "am" : "pm";
  return `${dayName} ${day} ${month} at ${hour}:${minute}${ampm}`;
}

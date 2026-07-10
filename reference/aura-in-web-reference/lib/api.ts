// aura-in-web/lib/api.ts
//
// Typed wrappers around the Supabase edge functions deployed in Plan A.
//
// Usage split:
//   - resolveLink: called from a Server Component on /b/[slug]; cached
//     at the Vercel edge for 30s (matches the function's own
//     Cache-Control: s-maxage=30 from resolve-link/index.ts).
//   - lookupGuest, createBooking: called client-side from the booking form.
//   - fetchBookingByReference: called from the /success page (server or
//     client) to poll while the webhook finalizes the booking.

import type {
  ResolveLinkResponse,
  LookupGuestResponse,
  CreateBookingRequest,
  CreateBookingResponse,
  GetSlotsRequest,
  GetSlotsResponse,
  BookingDetail,
} from "./types";

/**
 * Read Supabase env vars lazily, per-call, instead of at module load.
 *
 * Why: Next 16's `next build` collects page data by actually invoking server
 * components — that means modules imported by those components are evaluated
 * during the build, not just at runtime. A module-level throw on missing env
 * vars therefore breaks the build whenever .env.local isn't present (CI
 * preview builds, fresh checkouts, etc.), even though the values would be
 * injected fine at deploy/runtime. Lazy evaluation pushes the failure into
 * the first actual fetch, which is where the error message belongs.
 */
function getSupabaseEnv(): { supabaseUrl: string; anonKey: string } {
  const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const anonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
  if (!supabaseUrl || !anonKey) {
    throw new Error(
      "Supabase env vars missing — set NEXT_PUBLIC_SUPABASE_URL and " +
        "NEXT_PUBLIC_SUPABASE_ANON_KEY in .env.local (see .env.local.example).",
    );
  }
  return { supabaseUrl, anonKey };
}

/**
 * Resolve a slug to shop + services + workers + metadata. The edge
 * function returns 404 with `{ error: "Slug not found" }` for unknown
 * slugs; we translate that to `null` so the caller can render notFound().
 *
 * Other non-2xx responses throw — they indicate the function is broken,
 * not that the slug is unknown.
 */
export async function resolveLink(
  slug: string,
): Promise<ResolveLinkResponse | null> {
  const { supabaseUrl, anonKey } = getSupabaseEnv();
  const url = `${supabaseUrl}/functions/v1/resolve-link?slug=${encodeURIComponent(slug)}`;
  const res = await fetch(url, {
    headers: { Authorization: `Bearer ${anonKey}` },
    // Edge-cache parity with the function's own Cache-Control header.
    next: { revalidate: 30 },
  });
  if (res.status === 404) return null;
  if (!res.ok) {
    throw new Error(`resolve-link failed: ${res.status} ${res.statusText}`);
  }
  return (await res.json()) as ResolveLinkResponse;
}

/**
 * Look up a guest profile by phone for prefill on returning visitors.
 *
 * Contract (from lookup-guest/index.ts):
 *   - 200 + `null` body → unknown phone (intentional: avoids
 *     enumeration via differential status codes).
 *   - 200 + `{ name, lastServices }` → known phone.
 *   - 400 → malformed phone (treat as no-match; don't surface to user).
 *   - 5xx → server error (treat as no-match; the form still works
 *     without prefill).
 *
 * We collapse all non-success cases to `null` so the caller has one
 * branch to handle.
 */
export async function lookupGuest(
  phone: string,
): Promise<LookupGuestResponse | null> {
  const { supabaseUrl, anonKey } = getSupabaseEnv();
  const url = `${supabaseUrl}/functions/v1/lookup-guest`;
  let res: Response;
  try {
    res = await fetch(url, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${anonKey}`,
      },
      body: JSON.stringify({ phone }),
    });
  } catch {
    // Network failure — fall back silently. Prefill is a nice-to-have.
    return null;
  }
  if (!res.ok) return null;
  const body = (await res.json().catch(() => null)) as
    | LookupGuestResponse
    | null;
  return body; // either null or { name, lastServices }
}

/**
 * Submit a booking and receive the payment provider's authorization URL
 * to redirect the browser to.
 *
 * Always returns a `CreateBookingResponse` — non-2xx responses are
 * mapped to `{ success: false, error }` so the form has a single error
 * surface. Network failures throw (the caller's outer try/catch will
 * show a generic "couldn't reach the server" message).
 */
export async function createBooking(
  req: CreateBookingRequest,
): Promise<CreateBookingResponse> {
  const { supabaseUrl, anonKey } = getSupabaseEnv();
  const url = `${supabaseUrl}/functions/v1/create-booking`;
  const res = await fetch(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${anonKey}`,
    },
    body: JSON.stringify(req),
  });
  if (!res.ok) {
    const errBody = (await res.json().catch(() => null)) as
      | { error?: string }
      | null;
    return {
      success: false,
      error: errBody?.error ?? `HTTP ${res.status} ${res.statusText}`,
    };
  }
  return (await res.json()) as CreateBookingResponse;
}

/**
 * Lazy slot lookup. Called from the booking page after the visitor picks
 * services + (optionally) a worker. Always returns a response shape — any
 * non-2xx is collapsed to `{ slots: [] }` so the SlotPicker can render an
 * empty-state without a separate error branch. Network errors throw and
 * the caller's surrounding try/catch handles them.
 */
export async function getSlots(
  req: GetSlotsRequest,
): Promise<GetSlotsResponse> {
  const { supabaseUrl, anonKey } = getSupabaseEnv();
  const url = `${supabaseUrl}/functions/v1/get-slots`;
  const res = await fetch(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${anonKey}`,
    },
    body: JSON.stringify(req),
    cache: "no-store",
  });
  if (!res.ok) return { slots: [] };
  return (await res.json()) as GetSlotsResponse;
}

/**
 * Poll bookings by payment reference to detect webhook completion. The
 * /success page calls this every few seconds until either the row
 * appears as `confirmed` or a timeout elapses.
 *
 * We query PostgREST directly (no edge function needed) because the
 * `bookings` table has an RLS policy that lets anyone read a confirmed
 * booking by `payment_intent_id` (the reference is unguessable). If RLS
 * blocks the read, this returns null and the success page keeps polling.
 */
export async function fetchBookingByReference(
  reference: string,
): Promise<{ id: string; status: string } | null> {
  const { supabaseUrl, anonKey } = getSupabaseEnv();
  // Guests can't SELECT bookings directly (RLS restricts to user_id /
  // shop owners). The SECURITY DEFINER RPC scopes the lookup to the
  // specific reference and returns only {id, status}.
  const url = `${supabaseUrl}/rest/v1/rpc/get_booking_by_reference`;
  const res = await fetch(url, {
    method: "POST",
    headers: {
      apikey: anonKey,
      Authorization: `Bearer ${anonKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ p_reference: reference }),
    cache: "no-store",
  });
  if (!res.ok) return null;
  const rows = (await res.json().catch(() => [])) as Array<{
    id: string;
    status: string;
  }>;
  return rows[0] ?? null;
}

/**
 * Fetch the public detail view of a confirmed booking by ID. Powers the
 * /booking/[id] page reachable from the WhatsApp confirmation link.
 *
 * Server-side RPC returns null for unknown / unconfirmed IDs; the page
 * treats null as 404.
 */
export async function fetchBookingDetail(
  id: string,
): Promise<BookingDetail | null> {
  const { supabaseUrl, anonKey } = getSupabaseEnv();
  const res = await fetch(`${supabaseUrl}/rest/v1/rpc/get_booking_detail`, {
    method: "POST",
    headers: {
      apikey: anonKey,
      Authorization: `Bearer ${anonKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ p_id: id }),
    cache: "no-store",
  });
  if (!res.ok) return null;
  const data = (await res.json().catch(() => null)) as BookingDetail | null;
  return data;
}

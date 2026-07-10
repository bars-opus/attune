// supabase/functions/resolve-link/index.ts
//
// Public edge function (verify_jwt = false). Resolves a booking slug to the
// underlying shop, plus the services / workers / metadata the booking page
// needs to render. One round-trip = one paint on a slow connection.
//
// Data-model reminder for future readers (because the abstraction surprises
// people):
//   * All booking endpoints are shops. A freelancer is just a worker with
//     workers.is_freelancer = true whose shop has a single worker (themselves).
//   * Travel info (can_travel, travel_radius_km) lives on freelancer_details,
//     keyed by worker_id.
//   * Services are stored in `appointment_slots` (not `services`). The
//     historical name stuck.
//   * Shop logo is shop_logo_url; coordinates live in shop_locations (with
//     is_primary flag), not on the shops row itself.
//
// Response contract (200):
//   {
//     targetType: 'shop' | 'freelancer',
//     target:     { id, name, type, logoUrl, address, latitude, longitude,
//                   currency, ... },
//     services:   [{ id, name, price, durationMinutes, description }],
//     workers:    [{ id, name, profileImageUrl, specialties }],   // empty for freelancer
//     canTravel:  boolean,                                        // freelancer-only signal
//     travelRadiusKm: number | null,
//     availableSlots: [],                                         // v1: fetched lazily
//                                                                 // after service-pick;
//                                                                 // see comment below
//     depositFraction: number,
//     platformFeeFraction: number
//   }
//
// targetType is derived from workers: every active worker is_freelancer ⇒
// 'freelancer'. Otherwise 'shop'. The web layer uses targetType to decide
// whether to show the worker picker and require an address.

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient, SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";
import { buildCorsHeaders } from "../_shared/cors.ts";
import { checkRateLimit } from "../_shared/rate_limit.ts";

// Lazy-init the Supabase client so the module can be imported in tests
// without env vars set. The Supabase JS client throws synchronously when
// SUPABASE_URL is empty, which would break import-time test setup.
let _supabase: SupabaseClient | null = null;
function getSupabase(): SupabaseClient {
  if (_supabase) return _supabase;
  _supabase = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  );
  return _supabase;
}

// v1 booking-economics defaults. Move to system_config once we have a
// per-shop override story.
const DEPOSIT_FRACTION = 0.3;
const PLATFORM_FEE_FRACTION = 0.029;

export async function handler(req: Request): Promise<Response> {
  const cors = buildCorsHeaders(req, "GET, OPTIONS");
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: cors });
  }
  if (req.method !== "GET") {
    return jsonResponse(cors, { error: "Method not allowed" }, 405);
  }

  const url = new URL(req.url);
  const slug = url.searchParams.get("slug");
  if (!slug || slug.trim().length === 0) {
    return jsonResponse(cors, { error: "Missing slug" }, 400);
  }

  const supabase = getSupabase();

  // Rate limit: 60 reads / minute / IP. A real visitor opens the page once
  // and stays; 60/min is well above any human pattern but kills enumeration.
  const rl = await checkRateLimit(supabase, "resolve-link", req, {
    max: 60,
    windowSeconds: 60,
  });
  if (!rl.allowed) {
    return jsonResponse(
      cors,
      { error: "Too many requests" },
      429,
      { "Retry-After": String(rl.retryAfterSeconds) },
    );
  }

  // 1. Look up the shop by cached booking_slug (Tasks 1+2 keep this column
  //    in sync with short_links via trigger). No embedded join — shops and
  //    shop_locations have no FK relationship registered in PostgREST's
  //    schema cache, so we fetch locations as a separate query below.
  const { data: shop, error: shopErr } = await supabase
    .from("shops")
    .select(`
      id,
      shop_name,
      shop_type,
      shop_logo_url,
      luxury_level,
      verified,
      address,
      currency
    `)
    .eq("booking_slug", slug)
    .maybeSingle();

  if (shopErr) {
    console.error("resolve-link: shop fetch error", shopErr);
    return jsonResponse(cors, { error: "Internal error" }, 500);
  }
  if (!shop) {
    return jsonResponse(cors, { error: "Slug not found" }, 404);
  }

  // 2. Parallel fetch: services (appointment_slots), workers (with
  //    freelancer_details join), and shop_locations. Click-tracking is
  //    kicked off separately and never awaited.
  const [servicesRes, workersRes, locationsRes] = await Promise.all([
    supabase
      .from("appointment_slots")
      .select("id, service_name, description, duration, price, slot_type")
      .eq("shop_id", shop.id)
      // Phase 11 archive filter: public link must not list archived
      // services. Matches the SQL cascade in
      // supabase/migrations/20260605000300_archive_filter_cascade.sql.
      .is("archived_at", null),
    supabase
      .from("workers")
      .select(`
        id,
        name,
        profile_image_url,
        specialties,
        is_freelancer,
        freelancer_details:freelancer_details(
          can_travel,
          travel_radius_km,
          base_latitude,
          base_longitude,
          rating
        )
      `)
      .eq("shop_id", shop.id)
      .eq("is_active", true),
    supabase
      .from("shop_locations")
      .select("address, city, country, latitude, longitude, is_primary")
      .eq("shop_id", shop.id),
  ]);

  if (servicesRes.error) {
    console.error("resolve-link: services fetch error", servicesRes.error);
  }
  if (workersRes.error) {
    console.error("resolve-link: workers fetch error", workersRes.error);
  }
  if (locationsRes.error) {
    console.error("resolve-link: locations fetch error", locationsRes.error);
  }

  const servicesRaw = servicesRes.data ?? [];
  const workersRaw = workersRes.data ?? [];
  const locationsRaw = (locationsRes.data ?? []) as any[];

  // 3. Derive targetType from workers.
  //    Freelancer flow ⇔ every active worker is_freelancer (and there is one).
  const allFreelancers =
    workersRaw.length > 0 &&
    workersRaw.every((w: any) => w.is_freelancer === true);
  const targetType: "shop" | "freelancer" = allFreelancers ? "freelancer" : "shop";

  // 4. Pull travel/location signals from the freelancer's freelancer_details
  //    row. PostgREST returns the joined table as either an object or a
  //    single-element array depending on relationship cardinality; handle both.
  let canTravel = false;
  let travelRadiusKm: number | null = null;
  if (targetType === "freelancer" && workersRaw.length > 0) {
    const first: any = workersRaw[0];
    const details = Array.isArray(first.freelancer_details)
      ? first.freelancer_details[0]
      : first.freelancer_details;
    canTravel = details?.can_travel === true;
    travelRadiusKm = details?.travel_radius_km ?? null;
  }

  // 5. Available slots.
  //
  //    The generate_available_slots RPC requires concrete service_ids and
  //    quantities — it can't enumerate "all slots in the next 7 days" in one
  //    shot. The booking page calls it lazily after the visitor picks their
  //    services. For v1 we return an empty array so the web layer can render
  //    the catalog/worker picker on first paint and resolve slots in a
  //    follow-up request. Document deviation; safe to evolve.
  const availableSlots: unknown[] = [];

  // 6. Flatten the shop response. Primary location wins; fall back to first.
  let latitude: number | null = null;
  let longitude: number | null = null;
  let resolvedAddress: string | null = (shop as any).address ?? null;
  let country: string | null = null;
  if (locationsRaw.length > 0) {
    const primary =
      locationsRaw.find((l: any) => l.is_primary === true) ?? locationsRaw[0];
    latitude = primary?.latitude ?? null;
    longitude = primary?.longitude ?? null;
    resolvedAddress = primary?.address ?? resolvedAddress;
    country = primary?.country ?? null;
  }

  const target = {
    id: (shop as any).id,
    name: (shop as any).shop_name,
    type: (shop as any).shop_type,
    logoUrl: (shop as any).shop_logo_url,
    luxuryLevel: (shop as any).luxury_level,
    verified: (shop as any).verified,
    address: resolvedAddress,
    country,
    latitude,
    longitude,
    currency: (shop as any).currency ?? null,
  };

  // 7. Normalize services payload.
  const services = servicesRaw.map((s: any) => ({
    id: s.id,
    name: s.service_name,
    description: s.description,
    durationMinutes: parseDurationMinutes(s.duration),
    price: typeof s.price === "number" ? s.price : Number(s.price ?? 0),
    slotType: s.slot_type,
  }));

  // 8. Worker payload — strip freelancer_details before returning to the
  //    public client (it contains owner-only fields). For freelancer flow,
  //    the web page hides the worker picker, so omit workers entirely.
  const workers =
    targetType === "freelancer"
      ? []
      : workersRaw.map((w: any) => ({
          id: w.id,
          name: w.name,
          profileImageUrl: w.profile_image_url,
          specialties: Array.isArray(w.specialties) ? w.specialties : [],
        }));

  // 9. Click tracking (fire-and-forget). We use the existing
  //    increment_link_clicks RPC, which the mobile app already uses, so
  //    counts stay coherent. Failures are silently swallowed — analytics
  //    must never block resolution.
  supabase
    .rpc("increment_link_clicks", {
      link_slug: slug,
      click_data: {
        platform: "web",
        source: "resolve-link",
      },
    })
    .then(({ error }: any) => {
      if (error) console.error("resolve-link: click track failed", error);
    });

  return jsonResponse(
    cors,
    {
      targetType,
      target,
      services,
      workers,
      canTravel,
      travelRadiusKm,
      availableSlots,
      depositFraction: DEPOSIT_FRACTION,
      platformFeeFraction: PLATFORM_FEE_FRACTION,
    },
    200,
    { "Cache-Control": "public, max-age=30, s-maxage=30" },
  );
}

// appointment_slots.duration is stored as a Postgres INTERVAL/text (see
// booking schema comment near generate_available_slots). The DB layer
// emits values like "00:30:00" or "1 hour"; for the web page we only need
// minutes. Best-effort parse; fall back to 0 so a malformed row doesn't
// break the page.
function parseDurationMinutes(raw: unknown): number {
  if (raw == null) return 0;
  if (typeof raw === "number") return Math.round(raw);
  const s = String(raw).trim();
  // Postgres INTERVAL text often comes through as HH:MM:SS
  const hhmm = s.match(/^(\d+):(\d{2}):(\d{2})/);
  if (hhmm) {
    return Number(hhmm[1]) * 60 + Number(hhmm[2]);
  }
  // "30 minutes", "1 hour 30 minutes"
  let mins = 0;
  const hourMatch = s.match(/(\d+)\s*hour/);
  if (hourMatch) mins += Number(hourMatch[1]) * 60;
  const minMatch = s.match(/(\d+)\s*min/);
  if (minMatch) mins += Number(minMatch[1]);
  if (mins > 0) return mins;
  // Plain number-as-string
  const n = Number(s);
  return Number.isFinite(n) ? n : 0;
}

function jsonResponse(
  cors: Record<string, string>,
  body: unknown,
  status: number,
  extraHeaders: Record<string, string> = {},
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...cors,
      "Content-Type": "application/json",
      ...extraHeaders,
    },
  });
}

serve(handler);

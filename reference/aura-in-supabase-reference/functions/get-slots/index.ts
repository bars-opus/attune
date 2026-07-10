// supabase/functions/get-slots/index.ts
//
// Public edge function (verify_jwt = false). Lazy slot lookup called from
// the web booking page once the visitor has picked services + quantities.
//
// Why this exists:
//   resolve-link returns `availableSlots: []` because generate_available_slots
//   requires concrete service_ids + quantities the visitor hasn't chosen at
//   first paint. This endpoint is the follow-up the booking page makes after
//   ServicePicker / WorkerPicker.
//
// RPC signature (from supabase/migrations/20260525040000_fix_generate_slots_preselected_direct.sql):
//   generate_available_slots(
//     p_shop_id                 UUID,
//     p_date                    DATE,
//     p_service_ids             UUID[],
//     p_quantities              INT[],
//     p_selected_worker_ids     UUID[] DEFAULT NULL,
//     p_default_buffer_minutes  INT    DEFAULT NULL
//   ) RETURNS TABLE (
//     slot_id, service_name, start_time, end_time, actual_end_time, price,
//     available_workers, remaining_spots, requires_worker_selection,
//     buffer_minutes
//   )
//
// Request:  POST { shopId, serviceIds, quantities, workerIds?, days? }
// Response: 200 { slots: [{ startTime, endTime, workerId }] }
//
// We loop the RPC over the next N days (default 7) and union the rows. The
// RPC returns one row per (service, time-window), so when a slot has
// multiple available workers we explode the row into one entry per worker
// — the web SlotPicker filters by selected workerId.

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient, SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";
import { buildCorsHeaders } from "../_shared/cors.ts";
import { checkRateLimit } from "../_shared/rate_limit.ts";

// Lazy-init for test-importability (matches resolve-link's pattern).
let _supabase: SupabaseClient | null = null;
function getSupabase(): SupabaseClient {
  if (_supabase) return _supabase;
  _supabase = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  );
  return _supabase;
}

export async function handler(req: Request): Promise<Response> {
  const cors = buildCorsHeaders(req, "POST, OPTIONS");
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: cors });
  }
  if (req.method !== "POST") {
    return json(cors, { error: "Method not allowed" }, 405);
  }

  let body: {
    shopId?: string;
    serviceIds?: string[];
    quantities?: number[];
    workerIds?: string[] | null;
    days?: number;
  };
  try {
    body = await req.json();
  } catch {
    return json(cors, { error: "Invalid JSON" }, 400);
  }

  if (
    !body.shopId ||
    !Array.isArray(body.serviceIds) ||
    body.serviceIds.length === 0
  ) {
    return json(cors, { error: "Missing shopId or serviceIds" }, 400);
  }

  const quantities =
    body.quantities && body.quantities.length === body.serviceIds.length
      ? body.quantities
      : body.serviceIds.map(() => 1);

  const supabase = getSupabase();

  // Rate limit: 30/min/IP. Each service-pick triggers one call; visitors
  // change services a few times before settling. 30/min kills slot-scraping.
  const rl = await checkRateLimit(supabase, "get-slots", req, {
    max: 30,
    windowSeconds: 60,
  });
  if (!rl.allowed) {
    return new Response(
      JSON.stringify({ error: "Too many requests" }),
      {
        status: 429,
        headers: {
          ...cors,
          "Content-Type": "application/json",
          "Retry-After": String(rl.retryAfterSeconds),
        },
      },
    );
  }

  // Loop the RPC over the next N days (default 7). The RPC is per-date by
  // design — it inspects shop_opening_hours for the weekday. Cap at 30 to
  // bound runtime; the booking page only needs the next week or so anyway.
  const days = Math.min(Math.max(body.days ?? 7, 1), 30);
  const today = new Date();
  today.setHours(0, 0, 0, 0);

  const allSlots: Array<{
    startTime: string;
    endTime: string;
    workerId: string | null;
  }> = [];

  for (let i = 0; i < days; i++) {
    const date = new Date(today);
    date.setDate(date.getDate() + i);
    const dateStr = date.toISOString().slice(0, 10);

    const { data, error } = await supabase.rpc("generate_available_slots", {
      p_shop_id: body.shopId,
      p_date: dateStr,
      p_service_ids: body.serviceIds,
      p_quantities: quantities,
      p_selected_worker_ids:
        body.workerIds && body.workerIds.length > 0 ? body.workerIds : null,
      p_default_buffer_minutes: 0,
    });
    if (error) {
      console.error(`get-slots: ${dateStr} RPC failed:`, error);
      continue;
    }
    for (const row of (data ?? []) as any[]) {
      const start = row.start_time;
      const end = row.end_time;
      if (!start || !end) continue;

      const workersJsonb = row.available_workers;
      const workerList: any[] = Array.isArray(workersJsonb) ? workersJsonb : [];

      if (workerList.length === 0) {
        // Slot is bookable without a specific worker (e.g. service has
        // select_preferred_worker = false). Surface a single entry with
        // workerId = null so the SlotPicker still shows it.
        allSlots.push({
          startTime: typeof start === "string" ? start : new Date(start).toISOString(),
          endTime: typeof end === "string" ? end : new Date(end).toISOString(),
          workerId: null,
        });
      } else {
        // Multiple workers can fulfil this time-window. Explode into one
        // SlotEntry per worker so the web layer can filter by worker
        // selection without re-querying.
        for (const w of workerList) {
          allSlots.push({
            startTime: typeof start === "string" ? start : new Date(start).toISOString(),
            endTime: typeof end === "string" ? end : new Date(end).toISOString(),
            workerId: w?.id ?? null,
          });
        }
      }
    }
  }

  return json(cors, { slots: allSlots }, 200);
}

function json(cors: Record<string, string>, body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}

serve(handler);

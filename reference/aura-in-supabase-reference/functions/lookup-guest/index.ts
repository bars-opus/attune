// supabase/functions/lookup-guest/index.ts
//
// Public edge function (verify_jwt = false). Returns cached guest profile
// (name + last service names) for a given phone, or null if not seen before.
// Used by the Next.js booking page to prefill the form for returning clients.
//
// Privacy posture: returns 200+null (not 404) for unknown phones — prevents
// timing/status-code enumeration of which numbers are in the system.
// Validates E.164-lite before any DB query (so a malformed phone can't probe).

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient, SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";
import { buildCorsHeaders } from "../_shared/cors.ts";
import { redactError } from "../_shared/sanitize.ts";
import { checkRateLimit } from "../_shared/rate_limit.ts";

// Lazy-init the Supabase client so the module can be imported in tests
// without env vars set. The Supabase JS client throws synchronously when
// SUPABASE_URL is empty, which would break import-time test setup. Mirrors
// the pattern used in resolve-link/index.ts for consistency.
let _supabase: SupabaseClient | null = null;
function getSupabase(): SupabaseClient {
  if (_supabase) return _supabase;
  _supabase = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  );
  return _supabase;
}

// E.164 lite: + followed by 8-15 digits. We validate before any DB hit so a
// malformed phone can't probe storage (and so the user gets a fast 400).
const PHONE_RE = /^\+\d{8,15}$/;

export async function handler(req: Request): Promise<Response> {
  const cors = buildCorsHeaders(req, "POST, OPTIONS");
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: cors });
  }
  if (req.method !== "POST") {
    return json(cors, { error: "Method not allowed" }, 405);
  }

  let body: { phone?: string };
  try {
    body = await req.json();
  } catch {
    return json(cors, { error: "Invalid JSON" }, 400);
  }

  const phone = (body.phone ?? "").trim();
  if (!PHONE_RE.test(phone)) {
    return json(cors, { error: "Invalid phone format" }, 400);
  }

  const supabase = getSupabase();

  // Rate limit: 20/min/IP. The web form debounces input so a real visitor
  // hits this 1–3 times per session; 20/min kills phone-number enumeration.
  const rl = await checkRateLimit(supabase, "lookup-guest", req, {
    max: 20,
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

  const { data: profile, error: profileErr } = await supabase
    .from("guest_profiles")
    .select("id, name")
    .eq("phone", phone)
    .maybeSingle();

  if (profileErr) {
    console.error("lookup-guest: guest_profiles fetch error", redactError(profileErr));
    return json(cors, { error: "Internal error" }, 500);
  }

  if (!profile) {
    // 200 + null to avoid enumeration via differential status codes.
    return json(cors, null, 200);
  }

  // Pull recent booking history; dedupe to 3 distinct service names in JS
  // (Postgres DISTINCT ON + ORDER BY combos get messy through PostgREST).
  // 10-row ceiling keeps the response small while giving enough headroom
  // to find 3 distinct names for a repeat customer who books the same
  // service back-to-back.
  const { data: history, error: historyErr } = await supabase
    .from("guest_booking_history")
    .select("service_name")
    .eq("guest_profile_id", (profile as any).id)
    .order("booked_at", { ascending: false })
    .limit(10);

  if (historyErr) {
    console.error("lookup-guest: guest_booking_history fetch error", redactError(historyErr));
    // Non-fatal — still return the name we found. lastServices = [] is a
    // valid prefill state ("we know you, but we don't remember what you
    // booked").
  }

  const seen = new Set<string>();
  const lastServices: string[] = [];
  for (const row of history ?? []) {
    const n = (row as any).service_name as string | null | undefined;
    if (!n) continue;
    if (seen.has(n)) continue;
    seen.add(n);
    lastServices.push(n);
    if (lastServices.length >= 3) break;
  }

  return json(cors, { name: (profile as any).name, lastServices }, 200);
}

function json(cors: Record<string, string>, body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}

serve(handler);

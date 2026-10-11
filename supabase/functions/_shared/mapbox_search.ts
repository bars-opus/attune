// Mapbox Search Box integration and the fixed Nearby category allowlist.
// Spec §5.2, §5.3, §2.
//
// MOVED HERE FROM ai-assist/index.ts BY PLAN C's RULING 6, unchanged in
// behaviour. The reason for the move is deployment, not tidiness:
// `ai-sessions` needs the same helper, and NO function in this repo
// imports across function directories -- only `_shared/` is crossed.
// `deno check` resolving `../ai-assist/index.ts` would prove type
// resolution, not that the Supabase bundler ships the file, so the
// helper lives in the one directory the bundler is known to carry into
// every function.
//
// ===========================================================================
// THIS MODULE IS THE CROSS-PROVIDER BOUNDARY (spec §2).
//
// Spec §2's precise privacy claim has three clauses; two of them are
// enforced by this file's TYPES rather than by a caller's discipline:
//
//   "chat/session free text never reaches Mapbox"
//     searchMapboxCategory's parameters are a NearbyCategory -- one of
//     six compile-time string literals -- and two finite numbers. There
//     is no `string` parameter and no options bag, so there is no slot
//     into which a caller could pass instruction text, a prompt, a
//     prior turn, a user id or a session id, even by mistake. Adding
//     such a slot is a visible signature change on a shared module,
//     which is exactly the review event the constraint wants.
//
//   "Mapbox response text never re-enters Gemini"
//     PlaceSource is the ONLY type this module returns, and it is a
//     terminal type: nothing in `_shared/` consumes it, and
//     gemini_json.ts's callGeminiJson takes `systemPrompt`/`userPrompt`
//     as plain strings it never builds itself. So there is no function
//     anywhere that accepts a PlaceSource and produces prompt text --
//     the path does not exist to be taken. See ai-sessions/index.ts's
//     NearbyCategoryRequest/buildSessionUserPrompt for the
//     caller-side half of the same property.
//
// The third clause -- "automatically collected coordinates never reach
// Gemini" -- is the caller's, because the caller is what holds the
// coordinates. ai-sessions/index.ts enforces it by never putting the
// location into the prompt-building struct at all.
// ===========================================================================

export const NEARBY_CATEGORY_ALLOWLIST = [
  "restaurant",
  "cafe",
  "park",
  "cinema",
  "museum",
  "recreation",
] as const;
export type NearbyCategory = typeof NEARBY_CATEGORY_ALLOWLIST[number];

export interface NearbyCategoryOutput {
  category: NearbyCategory;
}

/// Exported for direct unit testing. This is the ONLY place a Gemini
/// category string is allowed to reach a decision -- anything outside
/// the fixed six-value allowlist (spec §5.2) returns null, which the
/// caller must treat as UNSUPPORTED_REQUEST and never forward to Mapbox.
export function validateNearbyCategoryOutput(
  parsed: unknown,
): NearbyCategoryOutput | null {
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
    return null;
  }
  const record = parsed as Record<string, unknown>;
  const allowedKeys = new Set(["category"]);
  for (const key of Object.keys(record)) {
    if (!allowedKeys.has(key)) return null;
  }
  const category = record.category;
  if (typeof category !== "string") return null;
  if (!(NEARBY_CATEGORY_ALLOWLIST as readonly string[]).includes(category)) {
    return null;
  }
  return { category: category as NearbyCategory };
}

// ---------------------------------------------------------------------------
// Mapbox Search Box integration -- spec §5.2. Server-owned category
// mapping; Mapbox never receives message text, model output beyond the
// allowlisted category, user/relationship IDs, or names. Gemini never
// receives Mapbox candidates.
// ---------------------------------------------------------------------------

const MAPBOX_CATEGORY_MAP: Record<NearbyCategory, string> = {
  restaurant: "restaurant",
  cafe: "cafe",
  park: "park",
  cinema: "cinema",
  museum: "museum",
  recreation: "recreation",
};

export interface PlaceSource {
  provider_id: string;
  name: string;
  formatted_address: string | null;
  category: string | null;
  map_url: string | null;
}

/// Exported for testing with a fake fetch. Never called for Ideas, and
/// never called before quota is reserved. Returns null on any
/// transport/parse failure (PROVIDER_UNAVAILABLE) or an empty valid
/// result set (NO_RESULTS is decided by the caller against this
/// function's empty-array return, so this itself never throws).
///
/// THE PARAMETER LIST IS THE PRIVACY CONTRACT, not a convenience: a
/// NearbyCategory (six literals) and two finite numbers. See this
/// file's header.
export async function searchMapboxCategory(
  category: NearbyCategory,
  location: { latitude: number; longitude: number },
): Promise<PlaceSource[] | null> {
  const token = Deno.env.get("MAPBOX_SERVER_ACCESS_TOKEN");
  if (!token) {
    console.error("mapbox_missing_server_token");
    return null;
  }
  const mapboxCategory = MAPBOX_CATEGORY_MAP[category];
  const url = `https://api.mapbox.com/search/searchbox/v1/category/${
    encodeURIComponent(mapboxCategory)
  }?access_token=${token}&longitude=${location.longitude}&latitude=${location.latitude}&limit=10`;

  try {
    const response = await fetch(url, { signal: AbortSignal.timeout(8000) });
    if (!response.ok) {
      console.error("mapbox_http_error", { status: response.status });
      return null;
    }
    const payload = await response.json();
    const features = Array.isArray(payload?.features) ? payload.features : [];
    const results: PlaceSource[] = [];
    for (const feature of features) {
      if (results.length >= 3) break;
      const properties = feature?.properties;
      const providerId = typeof properties?.mapbox_id === "string"
        ? properties.mapbox_id
        : null;
      const name = typeof properties?.name === "string"
        ? properties.name
        : null;
      if (!providerId || !name) continue;
      const formattedAddress = typeof properties?.full_address === "string"
        ? properties.full_address
        : (typeof properties?.address === "string"
          ? properties.address
          : null);
      results.push({
        provider_id: providerId,
        name,
        formatted_address: formattedAddress,
        category: mapboxCategory,
        map_url: `https://www.mapbox.com/search/${
          encodeURIComponent(providerId)
        }`,
      });
    }
    return results;
  } catch (err) {
    console.error("mapbox_fetch_failed", {
      error: err instanceof Error ? err.message : String(err),
    });
    return null;
  }
}

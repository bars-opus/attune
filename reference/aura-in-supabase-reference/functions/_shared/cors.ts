// Origin-restricted CORS for guest-facing edge functions. The booking page
// at aurain.barsopus.com is the only legitimate browser origin; the mobile
// app and server-to-server callers don't trigger CORS preflight at all.
//
// Returns headers with the request's Origin echoed only if it's in the
// allow-list; otherwise omits Allow-Origin entirely (browser blocks).

const ALLOWED_ORIGINS = new Set([
  "https://aurain.barsopus.com",
  "https://aura-in-web.vercel.app", // Vercel preview/default
  "http://localhost:3000",
  "http://127.0.0.1:3000",
]);

export function buildCorsHeaders(
  req: Request,
  methods: string = "GET, POST, OPTIONS",
): Record<string, string> {
  const origin = req.headers.get("Origin") ?? "";
  const headers: Record<string, string> = {
    "Access-Control-Allow-Methods": methods,
    "Access-Control-Allow-Headers": "Content-Type, Authorization, apikey",
    "Vary": "Origin",
  };
  if (ALLOWED_ORIGINS.has(origin)) {
    headers["Access-Control-Allow-Origin"] = origin;
  }
  return headers;
}

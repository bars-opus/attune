// supabase/functions/_shared/csam_matcher.ts
//
// Spec 1 W7b (§4.5 scan-media; plan P-23): the CSAM hash-matching seam.
// CSAM_MATCHER picks the adapter: `photodna` (Microsoft PhotoDNA Cloud
// Service), `safer` (Thorn Safer) or `stub` (a test hash list, development
// only). Every adapter answers clear, match, unavailable or skipped, and
// is written so that anything it does not positively understand is
// `unavailable`, never `clear`: an unknown status, a malformed body, a
// timeout, a missing key, a body that is not JSON. The stub runs only
// when BOTH get_attune_environment() reads 'development' AND SUPABASE_URL's
// host is exactly the development project's,
// `mrgjtyacrzfylawyzabm.supabase.co` (the ref of
// private.assert_development_project(); plan PF-H1, B5 M1), or exactly one
// of the local-serve hosts (`supabase functions serve`: kong, localhost,
// 127.0.0.1, host.docker.internal; B5 c3). Anywhere else, and always when
// the environment reads production, it is refused: it answers
// `unavailable` for everything, so nothing is ever marked clear by a stub
// and a person hears within 24 hours (scan_failed).
// Nothing here depends on an LLM, and nothing here logs. No adapter hashes
// video in W7b (plan P-19): scan-media skips a video and scans its poster
// image, which every app upload path stores as its own image object.
export type MatchOutcome = "clear" | "match" | "unavailable" | "skipped";

export interface MatchResult {
  outcome: MatchOutcome;
  vendor: string;
  /// The vendor's reference for this answer (tracking id), or why it was
  /// unavailable. Never the image, never a person.
  vendorRef: string | null;
}

export interface CsamMatcher {
  readonly name: string;
  readonly supportsVideo: boolean;
  match(bytes: Uint8Array, mime: string): Promise<MatchResult>;
}

export type FetchFn = (input: string, init: RequestInit) => Promise<Response>;
export type AttuneEnvironment = "development" | "production";

export interface MatcherConfig {
  /// The function's environment variables (Deno.env.get). The stub also
  /// reads SUPABASE_URL here (PF-H1).
  env(name: string): string | undefined;
  fetch: FetchFn;
  /// get_attune_environment(); anything unreadable is production.
  environment: AttuneEnvironment;
  /// Per call, clamped to 1..MATCHER_MAX_TIMEOUT_MS (B5 N-3); the default
  /// and the ceiling leave room in scan-media's run budget.
  timeoutMs?: number;
}

export const PHOTODNA_DEFAULT_URL = "https://api.microsoftmoderator.com/photodna/v1.0/Match";

/// The image types PhotoDNA's Match call accepts.
export const PHOTODNA_TYPES = ["image/jpeg", "image/png", "image/gif", "image/bmp", "image/tiff"];

/// The largest image scan-media reads whole and sends (B6 fix I-2): 4 MiB,
/// taken as PhotoDNA's Match limit and NOT verified against the vendor's
/// reference; the owner confirms it against the contract (PF-L9). Larger
/// is `unavailable:too_large` (never clear), so a person hears through
/// scan_failed.
export const PHOTODNA_MAX_BYTES = 4 * 1024 * 1024;

/// SHA-256 of the UTF-8 text "attune-csam-stub-match": the stub's built-in
/// match.
export const STUB_MATCH_SHA256 = "e626741fb1d4120438b2d38427087d3ae68863b1d657cc4d43eaa744ffbd93bc";

/// SHA-256 of "attune-csam-stub-unavailable": the stub answers unavailable.
export const STUB_UNAVAILABLE_SHA256 = "0c46e55b57ee5b883d1f28bd61366c046dea0b2fe64e7140e2b113b5a90e7292";

/// The GIF signature, "GIF89a". scan-media reads an object's kind from its
/// bytes (B4 I-3), so the stub's test images are those texts behind it:
/// they sniff as GIF and reach the matcher. (GIF, not PNG: the signature
/// is plain ASCII, so the test file stays valid UTF-8 for the repo's
/// text-scanning architecture tests.)
export const STUB_IMAGE_PREFIX: Uint8Array = new TextEncoder().encode("GIF89a");

/// SHA-256 of STUB_IMAGE_PREFIX + "attune-csam-stub-match" (28 bytes):
/// scan-media/testdata/stub-match.gif holds exactly those bytes.
export const STUB_MATCH_IMAGE_SHA256 = "968384e8ecfc58a3595a52954945897563dca5e9ca10db5555b86a10c2d90888";

/// SHA-256 of STUB_IMAGE_PREFIX + "attune-csam-stub-unavailable".
export const STUB_UNAVAILABLE_IMAGE_SHA256 = "5ecf12224f0aafbb3b504465061186e070c9815ecee2ce36fa5261c1c38fcca7";

/// The development project's ref (spec §1.3 Q19b), as in
/// private.assert_development_project() (20261025100400), and its host.
export const DEVELOPMENT_PROJECT_REF = "mrgjtyacrzfylawyzabm";
export const DEVELOPMENT_PROJECT_HOST = `${DEVELOPMENT_PROJECT_REF}.supabase.co`;

/// The hosts SUPABASE_URL has under `supabase functions serve` and local
/// runs (B5 c3). Exact names only; never a hosted project's URL.
export const LOCAL_SERVE_HOSTS: ReadonlySet<string> = new Set(["localhost", "127.0.0.1", "kong", "host.docker.internal"]);

/// A vendor call's timeout is clamped to 1..15 000 ms (B5 N-3), so
/// scan-media's run budget holds whatever a caller passes.
export const MATCHER_MAX_TIMEOUT_MS = 15_000;
const DEFAULT_TIMEOUT_MS = MATCHER_MAX_TIMEOUT_MS;

/// [ms] whole, within 1..MATCHER_MAX_TIMEOUT_MS; missing, NaN or infinite
/// is the ceiling.
export function matcherTimeoutMs(ms: number | undefined): number {
  const v = typeof ms === "number" && Number.isFinite(ms) ? Math.trunc(ms) : MATCHER_MAX_TIMEOUT_MS;
  return Math.min(Math.max(v, 1), MATCHER_MAX_TIMEOUT_MS);
}

export async function sha256Hex(bytes: Uint8Array): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new Uint8Array(bytes));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

/// PF-H1 (B5 M1, c3): true only when [url]'s host is exactly the
/// development project's or exactly a local-serve host. Unset, empty or
/// unparsable is never development. matcherFromEnv asks this only after
/// the environment read development.
export function isDevelopmentProjectUrl(url: string | undefined): boolean {
  const text = (url ?? "").trim();
  if (!text) return false;
  let host: string;
  try {
    host = new URL(text).hostname;
  } catch {
    return false;
  }
  return host === DEVELOPMENT_PROJECT_HOST || LOCAL_SERVE_HOSTS.has(host);
}

/// An https URL, or null. A vendor's key and the image never go out in
/// plain text.
function httpsUrl(text: string | undefined): URL | null {
  try {
    const url = new URL((text ?? "").trim());
    return url.protocol === "https:" ? url : null;
  } catch {
    return null;
  }
}

/// A vendor's error body is released, never read (B5 M3).
async function release(response: Response): Promise<void> {
  try {
    await response.body?.cancel();
  } catch {
    // nothing to release
  }
}

/// The body as JSON; anything that isn't is `unreadable_response` (or
/// `timeout` when the read itself ran out of time). Never clear.
async function readJson(response: Response): Promise<{ ok: true; body: unknown } | { ok: false; reason: string }> {
  try {
    return { ok: true, body: await response.json() };
  } catch (error) {
    return { ok: false, reason: failureReason(error, "unreadable_response") };
  }
}

function failureReason(error: unknown, otherwise: string): string {
  return error instanceof Error && error.name === "TimeoutError" ? "timeout" : otherwise;
}

function unavailable(vendor: string, reason: string): CsamMatcher {
  return {
    name: vendor,
    supportsVideo: false,
    match: () => Promise.resolve({ outcome: "unavailable", vendor, vendorRef: reason }),
  };
}

/// Microsoft PhotoDNA Cloud Service, Match: the image bytes in the body,
/// the subscription key in Ocp-Apim-Subscription-Key; a 200 whose
/// Status.Code is 3000 carries IsMatch and a TrackingId.
/// [url] must be https (B5 M2); its own query is kept and enhance=false set.
export function photoDnaMatcher(key: string, url: string, fetchFn: FetchFn, timeoutMs = DEFAULT_TIMEOUT_MS): CsamMatcher {
  const timeout = matcherTimeoutMs(timeoutMs);
  const endpoint = httpsUrl(url);
  if (!endpoint) return unavailable("photodna", "not_configured");
  endpoint.searchParams.set("enhance", "false");
  const target = endpoint.toString();
  return {
    name: "photodna",
    supportsVideo: false,
    async match(bytes, mime) {
      const type = mime.toLowerCase();
      if (!PHOTODNA_TYPES.includes(type)) {
        return { outcome: "unavailable", vendor: "photodna", vendorRef: `unsupported_type:${type}` };
      }
      try {
        const response = await fetchFn(target, {
          method: "POST",
          headers: { "Ocp-Apim-Subscription-Key": key, "Content-Type": type },
          body: new Uint8Array(bytes),
          signal: AbortSignal.timeout(timeout),
        });
        if (!response.ok) {
          await release(response);
          return { outcome: "unavailable", vendor: "photodna", vendorRef: `http:${response.status}` };
        }
        const read = await readJson(response);
        if (!read.ok) return { outcome: "unavailable", vendor: "photodna", vendorRef: read.reason };
        return readPhotoDnaMatch(read.body);
      } catch (error) {
        return { outcome: "unavailable", vendor: "photodna", vendorRef: failureReason(error, "network") };
      }
    },
  };
}

export function readPhotoDnaMatch(body: unknown): MatchResult {
  const b = (body ?? {}) as Record<string, unknown>;
  const status = (b.Status ?? {}) as Record<string, unknown>;
  const tracking = typeof b.TrackingId === "string" ? b.TrackingId : null;
  if (status.Code !== 3000) {
    return { outcome: "unavailable", vendor: "photodna", vendorRef: `status:${String(status.Code ?? "missing")}` };
  }
  if (b.IsMatch === true) return { outcome: "match", vendor: "photodna", vendorRef: tracking };
  if (b.IsMatch === false) return { outcome: "clear", vendor: "photodna", vendorRef: tracking };
  return { outcome: "unavailable", vendor: "photodna", vendorRef: "status:3000_without_answer" };
}

/// Thorn Safer. UNVERIFIED (plan P-24): built to the PUBLIC shape only, not
/// checked against Thorn's API reference, which Thorn publishes to
/// customers only. It follows the response published for Thorn-backed hash
/// matching (output.file.reasons holds "matched" on a match and is empty
/// otherwise; output.hashes lists what matched) with the image sent as
/// multipart `media` and the key as `Authorization: Token <key>`. The owner
/// checks the request and the response against Thorn's reference before
/// setting CSAM_MATCHER=safer; PhotoDNA is the first vendor. Any other
/// shape is unavailable, never clear.
export function saferMatcher(key: string, url: string, fetchFn: FetchFn, timeoutMs = DEFAULT_TIMEOUT_MS): CsamMatcher {
  const timeout = matcherTimeoutMs(timeoutMs);
  // The adapter guards itself, as photoDnaMatcher does (B6 M-5).
  const endpoint = httpsUrl(url);
  if (!endpoint) return unavailable("safer", "not_configured");
  const target = endpoint.toString();
  return {
    name: "safer",
    supportsVideo: false,
    async match(bytes, mime) {
      try {
        const form = new FormData();
        form.append("media", new Blob([new Uint8Array(bytes)], { type: mime }), "upload");
        const response = await fetchFn(target, {
          method: "POST",
          headers: { Authorization: `Token ${key}` },
          body: form,
          signal: AbortSignal.timeout(timeout),
        });
        if (!response.ok) {
          await release(response);
          return { outcome: "unavailable", vendor: "safer", vendorRef: `http:${response.status}` };
        }
        const read = await readJson(response);
        if (!read.ok) return { outcome: "unavailable", vendor: "safer", vendorRef: read.reason };
        return readSaferMatch(read.body);
      } catch (error) {
        return { outcome: "unavailable", vendor: "safer", vendorRef: failureReason(error, "network") };
      }
    },
  };
}

/// UNVERIFIED shape (plan P-24); see saferMatcher.
export function readSaferMatch(body: unknown): MatchResult {
  const b = (body ?? {}) as Record<string, unknown>;
  const output = (b.output ?? {}) as Record<string, unknown>;
  const file = (output.file ?? {}) as Record<string, unknown>;
  const reasons = file.reasons;
  const hashes = output.hashes;
  const id = typeof b.id === "string" ? b.id : null;
  if (!Array.isArray(reasons) || !Array.isArray(hashes)) {
    return { outcome: "unavailable", vendor: "safer", vendorRef: "unreadable_response" };
  }
  if (reasons.includes("matched")) {
    const first = hashes[0] as Record<string, unknown> | undefined;
    const source = Array.isArray(first?.sources) ? (first!.sources as Record<string, unknown>[])[0] : undefined;
    const matchRow = Array.isArray(source?.matches) ? (source!.matches as Record<string, unknown>[])[0] : undefined;
    const sourceId = typeof matchRow?.sourceId === "string" ? matchRow.sourceId : null;
    return { outcome: "match", vendor: "safer", vendorRef: id ?? sourceId };
  }
  if (reasons.length === 0 && hashes.length === 0) {
    return { outcome: "clear", vendor: "safer", vendorRef: id };
  }
  return { outcome: "unavailable", vendor: "safer", vendorRef: "unreadable_response" };
}

/// Development only: a match when the bytes' SHA-256 is on the test list
/// (STUB_MATCH_SHA256, STUB_MATCH_IMAGE_SHA256 and any in
/// CSAM_STUB_MATCH_SHA256, comma separated), unavailable for
/// STUB_UNAVAILABLE_SHA256 and STUB_UNAVAILABLE_IMAGE_SHA256, otherwise
/// clear. Its vendorRef
/// is never the hash (B5 M7): it is stored on the queue and the escalation.
/// Tests and matcherFromEnv only: an entry point that called it directly
/// would skip the production refusal (B5 M6, Task 8 checks).
export function stubMatcher(extraMatches: string[] = []): CsamMatcher {
  const matches = new Set([
    STUB_MATCH_SHA256,
    STUB_MATCH_IMAGE_SHA256,
    ...extraMatches.map((h) => h.trim().toLowerCase()).filter(Boolean),
  ]);
  const unavailables = new Set([STUB_UNAVAILABLE_SHA256, STUB_UNAVAILABLE_IMAGE_SHA256]);
  return {
    name: "stub",
    supportsVideo: false,
    async match(bytes) {
      const hash = await sha256Hex(bytes);
      if (matches.has(hash)) return { outcome: "match", vendor: "stub", vendorRef: "stub:match" };
      if (unavailables.has(hash)) return { outcome: "unavailable", vendor: "stub", vendorRef: "stub:unavailable" };
      return { outcome: "clear", vendor: "stub", vendorRef: null };
    },
  };
}

export function matcherFromEnv(config: MatcherConfig): CsamMatcher {
  const choice = (config.env("CSAM_MATCHER") ?? "").trim().toLowerCase();
  const timeoutMs = matcherTimeoutMs(config.timeoutMs);
  switch (choice) {
    case "photodna": {
      const key = config.env("PHOTODNA_SUBSCRIPTION_KEY")?.trim();
      if (!key) return unavailable("photodna", "not_configured");
      // An http or unparsable override is not configured (B5 M2).
      return photoDnaMatcher(key, config.env("PHOTODNA_URL")?.trim() || PHOTODNA_DEFAULT_URL, config.fetch, timeoutMs);
    }
    case "safer": {
      const key = config.env("SAFER_API_KEY")?.trim();
      const url = config.env("SAFER_MATCH_URL")?.trim();
      if (!key || !url || !httpsUrl(url)) return unavailable("safer", "not_configured");
      return saferMatcher(key, url, config.fetch, timeoutMs);
    }
    case "stub":
      // Both checks, each on its own (PF-H1): the environment, then the project.
      if (config.environment !== "development") return unavailable("stub", "stub_refused_in_production");
      if (!isDevelopmentProjectUrl(config.env("SUPABASE_URL"))) return unavailable("stub", "stub_refused_in_production");
      return stubMatcher((config.env("CSAM_STUB_MATCH_SHA256") ?? "").split(","));
    default:
      return unavailable(choice || "none", "matcher_not_configured");
  }
}

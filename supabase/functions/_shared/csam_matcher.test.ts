// Spec 1 W7b (§4.5, §7.2; plan P-23, P-24): the matcher seam, on mocked
// fetch. Nothing a matcher doesn't positively understand is clear; the
// stub is refused in production. PF-H1 (B5 M1, c3): the stub also needs
// SUPABASE_URL's host to be exactly the development project's
// (mrgjtyacrzfylawyzabm.supabase.co, private.assert_development_project())
// or a local-serve host; neither ever beats environment: production.
import {
  type FetchFn,
  isDevelopmentProjectUrl,
  matcherFromEnv,
  PHOTODNA_DEFAULT_URL,
  photoDnaMatcher,
  readPhotoDnaMatch,
  readSaferMatch,
  saferMatcher,
  MATCHER_MAX_TIMEOUT_MS,
  matcherTimeoutMs,
  STUB_IMAGE_PREFIX,
  STUB_MATCH_IMAGE_SHA256,
  STUB_MATCH_SHA256,
  STUB_UNAVAILABLE_IMAGE_SHA256,
  STUB_UNAVAILABLE_SHA256,
  sha256Hex,
  stubMatcher,
} from "./csam_matcher.ts";

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

const enc = new TextEncoder();
const IMAGE = enc.encode("not really a jpeg");
const DEV_URL = "https://mrgjtyacrzfylawyzabm.supabase.co";

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}

function recorder(answer: () => Response | Promise<Response>) {
  const calls: { url: string; init: RequestInit }[] = [];
  const fetchFn: FetchFn = async (url, init) => {
    calls.push({ url, init });
    return await answer();
  };
  return { calls, fetchFn };
}

const env = (values: Record<string, string>) => (name: string): string | undefined => values[name];

/// A vendor that never answers. Only the matcher's own timeout ends it; if
/// that is missing (or not the one configured), the guard fails the call
/// after a second as a non-timeout error, so the test turns red quickly.
function hangingFetch(): FetchFn {
  return (_url, init) =>
    new Promise((_resolve, reject) => {
      const guard = setTimeout(() => reject(new Error("the matcher set no timeout")), 1_000);
      init.signal?.addEventListener("abort", () => {
        clearTimeout(guard);
        reject(init.signal?.reason);
      });
    });
}

Deno.test("stub: the test hashes match and are unavailable; anything else is clear", async () => {
  assert(STUB_MATCH_SHA256 === await sha256Hex(enc.encode("attune-csam-stub-match")), "match hash");
  assert(STUB_UNAVAILABLE_SHA256 === await sha256Hex(enc.encode("attune-csam-stub-unavailable")), "unavailable hash");
  const stub = stubMatcher();
  const hit = await stub.match(enc.encode("attune-csam-stub-match"), "image/png");
  assert(hit.outcome === "match" && hit.vendorRef === "stub:match", JSON.stringify(hit));
  assert((await stub.match(enc.encode("attune-csam-stub-unavailable"), "image/png")).outcome === "unavailable", "unavail");
  assert((await stub.match(IMAGE, "image/jpeg")).outcome === "clear", "clear");
  const extra = stubMatcher([` ${(await sha256Hex(IMAGE)).toUpperCase()} `]);
  assert((await extra.match(IMAGE, "image/jpeg")).outcome === "match", "extra hash");
});

Deno.test("stub: its GIF test images match and are unavailable (scan-media sniffs them as images)", async () => {
  const image = (text: string) => {
    const t = enc.encode(text);
    const out = new Uint8Array(STUB_IMAGE_PREFIX.length + t.length);
    out.set(STUB_IMAGE_PREFIX);
    out.set(t, STUB_IMAGE_PREFIX.length);
    return out;
  };
  assert(new TextDecoder().decode(STUB_IMAGE_PREFIX) === "GIF89a", "the GIF signature");
  assert(STUB_MATCH_IMAGE_SHA256 === await sha256Hex(image("attune-csam-stub-match")), "match image hash");
  assert(STUB_UNAVAILABLE_IMAGE_SHA256 === await sha256Hex(image("attune-csam-stub-unavailable")), "unavailable image hash");
  const stub = stubMatcher();
  const hit = await stub.match(image("attune-csam-stub-match"), "image/gif");
  assert(hit.outcome === "match" && hit.vendorRef === "stub:match", JSON.stringify(hit));
  const down = await stub.match(image("attune-csam-stub-unavailable"), "image/gif");
  assert(down.outcome === "unavailable" && down.vendorRef === "stub:unavailable", JSON.stringify(down));
  assert((await stub.match(image("an ordinary photo"), "image/gif")).outcome === "clear", "an ordinary gif");
});

Deno.test("B5 N-1: Safer needs an https URL: anything else is not configured and nothing is sent", async () => {
  const { calls, fetchFn } = recorder(() => json({ id: "s-1", output: { file: { reasons: [] }, hashes: [] } }));
  for (const url of ["http://plain", "http://safer.example/match", "not a url", "ftp://safer.example/match"]) {
    const m = matcherFromEnv({ env: env({ CSAM_MATCHER: "safer", SAFER_API_KEY: "k", SAFER_MATCH_URL: url }), fetch: fetchFn, environment: "production" });
    const r = await m.match(IMAGE, "image/jpeg");
    assert(r.outcome === "unavailable" && r.vendorRef === "not_configured", `${url} -> ${JSON.stringify(r)}`);
  }
  // M-5: the adapter guards itself too (Spec 2's inline pipeline may build it directly).
  for (const url of ["http://plain", "not a url"]) {
    const r = await saferMatcher("k", url, fetchFn).match(IMAGE, "image/jpeg");
    assert(r.outcome === "unavailable" && r.vendorRef === "not_configured", `direct ${url} -> ${JSON.stringify(r)}`);
  }
  assert(calls.length === 0, `the key or the image went to a non-https URL (${calls.length} calls)`);
});

Deno.test("B5 N-3: the matcher timeout is clamped to 1..15 000 ms, for both adapters", async () => {
  assert(MATCHER_MAX_TIMEOUT_MS === 15_000, "the ceiling");
  const cases: [number | undefined, number][] = [
    [undefined, 15_000], [NaN, 15_000], [Infinity, 15_000], [-Infinity, 15_000], [1e12, 15_000],
    [15_001, 15_000], [-5, 1], [0, 1], [20, 20], [2_500.7, 2_500],
  ];
  for (const [input, want] of cases) assert(matcherTimeoutMs(input) === want, `${input} -> ${matcherTimeoutMs(input)}`);

  const original = AbortSignal.timeout;
  const asked: number[] = [];
  AbortSignal.timeout = (ms: number) => {
    asked.push(ms);
    return original.call(AbortSignal, 1_000);
  };
  try {
    const pdna = recorder(() => json({ Status: { Code: 3000 }, IsMatch: false }));
    await matcherFromEnv({ env: env({ CSAM_MATCHER: "photodna", PHOTODNA_SUBSCRIPTION_KEY: "k" }), fetch: pdna.fetchFn, environment: "production", timeoutMs: 1e12 })
      .match(IMAGE, "image/jpeg");
    const safer = recorder(() => json({ id: "s", output: { file: { reasons: [] }, hashes: [] } }));
    await matcherFromEnv({
      env: env({ CSAM_MATCHER: "safer", SAFER_API_KEY: "k", SAFER_MATCH_URL: "https://safer.example/match" }),
      fetch: safer.fetchFn,
      environment: "production",
      timeoutMs: 1e12,
    }).match(IMAGE, "image/jpeg");
    await photoDnaMatcher("k", PHOTODNA_DEFAULT_URL, pdna.fetchFn, 1e12).match(IMAGE, "image/jpeg");
    await saferMatcher("k", "https://safer.example/match", safer.fetchFn, -3).match(IMAGE, "image/jpeg");
  } finally {
    AbortSignal.timeout = original;
  }
  assert(asked.join(",") === "15000,15000,15000,1", `timeouts asked: ${asked.join(",")}`);
});

Deno.test("stub is refused in production: unavailable for everything, never clear", async () => {
  const { calls, fetchFn } = recorder(() => json({}));
  // Neither the development project's URL nor a local-serve host makes
  // production development.
  for (const url of [DEV_URL, "http://kong:8000"]) {
    const m = matcherFromEnv({ env: env({ CSAM_MATCHER: "stub", SUPABASE_URL: url }), fetch: fetchFn, environment: "production" });
    for (const bytes of [IMAGE, enc.encode("attune-csam-stub-match")]) {
      const r = await m.match(bytes, "image/jpeg");
      assert(r.outcome === "unavailable" && r.vendorRef === "stub_refused_in_production", `${url} ${JSON.stringify(r)}`);
    }
  }
  assert(calls.length === 0, "the stub called out");
  const dev = matcherFromEnv({ env: env({ CSAM_MATCHER: "stub", SUPABASE_URL: DEV_URL }), fetch: fetchFn, environment: "development" });
  assert((await dev.match(IMAGE, "image/jpeg")).outcome === "clear", "dev stub");
});

Deno.test("PF-H1: a development environment on any other host refuses the stub", async () => {
  const { calls, fetchFn } = recorder(() => json({}));
  const notDevelopment = [
    undefined,
    "",
    "not a url",
    "https://abcdefghijklmnopqrst.supabase.co",
    "https://abcdefghijklmnopqrst.supabase.co/mrgjtyacrzfylawyzabm.",
    "https://mrgjtyacrzfylawyzabmx.supabase.co",
    "https://xmrgjtyacrzfylawyzabm.supabase.co",
    // B5 M1: lookalikes of the exact host
    "https://mrgjtyacrzfylawyzabm.evil.com",
    "https://mrgjtyacrzfylawyzabm.supabase.co.evil.com",
    "https://mrgjtyacrzfylawyzabm.",
    "https://mrgjtyacrzfylawyzabm%2Eevil.com",
    "https://mrgjtyacrzfylawyzabm.supabase.co.",
    "https://mrgjtyacrzfylawyzabm.supabase.co@evil.com",
    // B5 c3: only the exact local-serve hosts
    "http://kong.evil.com",
    "http://localhost.evil.com",
    "http://127.0.0.1.evil.com",
    "http://evil.kong",
  ];
  for (const url of notDevelopment) {
    assert(!isDevelopmentProjectUrl(url), `${url} read as development`);
    const values: Record<string, string> = { CSAM_MATCHER: "stub" };
    if (url !== undefined) values.SUPABASE_URL = url;
    const m = matcherFromEnv({ env: env(values), fetch: fetchFn, environment: "development" });
    for (const bytes of [IMAGE, enc.encode("attune-csam-stub-match")]) {
      const r = await m.match(bytes, "image/jpeg");
      assert(r.outcome === "unavailable" && r.vendorRef === "stub_refused_in_production", `${url} -> ${JSON.stringify(r)}`);
    }
  }
  assert(calls.length === 0, "the stub called out");
  const development = [
    ` ${DEV_URL}/ `,
    "https://MRGJTYACRZFYLAWYZABM.supabase.co",
    "https://evil.com@mrgjtyacrzfylawyzabm.supabase.co",
    // B5 c3: `supabase functions serve` and local runs, development only
    "http://kong:8000",
    "http://localhost:54321",
    "http://127.0.0.1:54321",
    "http://host.docker.internal:54321",
  ];
  for (const url of development) {
    assert(isDevelopmentProjectUrl(url), `${url} not read as development`);
    const dev = matcherFromEnv({ env: env({ CSAM_MATCHER: "stub", SUPABASE_URL: url }), fetch: fetchFn, environment: "development" });
    assert((await dev.match(IMAGE, "image/jpeg")).outcome === "clear", `${url} dev stub`);
  }
});

Deno.test("config is threaded: stub extras, the timeout, blank keys, https only", async () => {
  const { calls, fetchFn } = recorder(() => json({}));
  const extra = matcherFromEnv({
    env: env({ CSAM_MATCHER: "stub", SUPABASE_URL: DEV_URL, CSAM_STUB_MATCH_SHA256: ` ${await sha256Hex(IMAGE)} ,` }),
    fetch: fetchFn,
    environment: "development",
  });
  const hit = await extra.match(IMAGE, "image/jpeg");
  assert(hit.outcome === "match" && hit.vendorRef === "stub:match", JSON.stringify(hit));

  const slow = hangingFetch();
  const timed = matcherFromEnv({ env: env({ CSAM_MATCHER: "photodna", PHOTODNA_SUBSCRIPTION_KEY: "k" }), fetch: slow, environment: "production", timeoutMs: 20 });
  assert((await timed.match(IMAGE, "image/jpeg")).vendorRef === "timeout", "photodna timeoutMs");
  const timedSafer = matcherFromEnv({
    env: env({ CSAM_MATCHER: "safer", SAFER_API_KEY: "k", SAFER_MATCH_URL: "https://safer.example/match" }),
    fetch: slow,
    environment: "production",
    timeoutMs: 20,
  });
  assert((await timedSafer.match(IMAGE, "image/jpeg")).vendorRef === "timeout", "safer timeoutMs");

  const unconfigured: Record<string, string>[] = [
    { CSAM_MATCHER: "photodna", PHOTODNA_SUBSCRIPTION_KEY: "   " },
    { CSAM_MATCHER: "photodna", PHOTODNA_SUBSCRIPTION_KEY: "k", PHOTODNA_URL: "http://plain/Match" },
    { CSAM_MATCHER: "photodna", PHOTODNA_SUBSCRIPTION_KEY: "k", PHOTODNA_URL: "not a url" },
    { CSAM_MATCHER: "safer", SAFER_API_KEY: "  ", SAFER_MATCH_URL: "https://safer.example/match" },
  ];
  for (const values of unconfigured) {
    const r = await matcherFromEnv({ env: env(values), fetch: fetchFn, environment: "production" }).match(IMAGE, "image/jpeg");
    assert(r.outcome === "unavailable" && r.vendorRef === "not_configured", `${JSON.stringify(values)} -> ${JSON.stringify(r)}`);
  }
  assert(calls.length === 0, "an unconfigured matcher called out");

  // The key is trimmed; a regional URL with its own query keeps it.
  const ok = recorder(() => json({ Status: { Code: 3000 }, IsMatch: false }));
  const regional = matcherFromEnv({
    env: env({ CSAM_MATCHER: "photodna", PHOTODNA_SUBSCRIPTION_KEY: " k-2 ", PHOTODNA_URL: " https://x.example/Match?v=1 " }),
    fetch: ok.fetchFn,
    environment: "production",
  });
  assert((await regional.match(IMAGE, "image/jpeg")).outcome === "clear", "regional");
  assert(ok.calls[0].url === "https://x.example/Match?v=1&enhance=false", ok.calls[0].url);
  assert((ok.calls[0].init.headers as Record<string, string>)["Ocp-Apim-Subscription-Key"] === "k-2", "trimmed key");
  const direct = await photoDnaMatcher("k", "http://plain/Match", ok.fetchFn).match(IMAGE, "image/jpeg");
  assert(direct.vendorRef === "not_configured" && ok.calls.length === 1, "plain-http photodna called out");
});

Deno.test("no matcher, an unknown one, or a vendor without its key: unavailable", async () => {
  const { fetchFn } = recorder(() => json({}));
  const configs: Record<string, string>[] = [
    {},
    { CSAM_MATCHER: "magic" },
    { CSAM_MATCHER: "photodna" },
    { CSAM_MATCHER: "safer", SAFER_API_KEY: "k" },
    { CSAM_MATCHER: "safer", SAFER_API_KEY: "k", SAFER_MATCH_URL: "http://plain" },
  ];
  for (const values of configs) {
    const m = matcherFromEnv({ env: env(values), fetch: fetchFn, environment: "development" });
    const r = await m.match(IMAGE, "image/jpeg");
    assert(r.outcome === "unavailable", `${JSON.stringify(values)} -> ${JSON.stringify(r)}`);
  }
});

Deno.test("photodna: the documented request; 3000 answers; anything else unavailable", async () => {
  const ok = recorder(() => json({ Status: { Code: 3000, Description: "OK" }, IsMatch: false, TrackingId: "trk-1" }));
  const m = matcherFromEnv({ env: env({ CSAM_MATCHER: "photodna", PHOTODNA_SUBSCRIPTION_KEY: "k-1" }), fetch: ok.fetchFn, environment: "production" });
  const r = await m.match(IMAGE, "IMAGE/JPEG");
  assert(r.outcome === "clear" && r.vendor === "photodna" && r.vendorRef === "trk-1", JSON.stringify(r));
  const call = ok.calls[0];
  const headers = call.init.headers as Record<string, string>;
  assert(call.url === `${PHOTODNA_DEFAULT_URL}?enhance=false` && call.init.method === "POST", call.url);
  assert(headers["Ocp-Apim-Subscription-Key"] === "k-1" && headers["Content-Type"] === "image/jpeg", JSON.stringify(headers));
  const sent = call.init.body as Uint8Array;
  assert(sent.length === IMAGE.length && sent.every((b, i) => b === IMAGE[i]), "the image bytes are the body");

  assert(readPhotoDnaMatch({ Status: { Code: 3000 }, IsMatch: true, TrackingId: "trk-2" }).outcome === "match", "match");
  for (const body of [{ Status: { Code: 3208 }, IsMatch: false }, { Status: { Code: 3000 } }, { IsMatch: false }, null, "x"]) {
    const read = readPhotoDnaMatch(body);
    assert(read.outcome === "unavailable", `${JSON.stringify(body)} -> ${read.outcome}`);
  }
  const busy = photoDnaMatcher("k", PHOTODNA_DEFAULT_URL, recorder(() => json({}, 429)).fetchFn);
  assert((await busy.match(IMAGE, "image/png")).vendorRef === "http:429", "429");
  const down = photoDnaMatcher("k", PHOTODNA_DEFAULT_URL, () => Promise.reject(new TypeError("dns")));
  assert((await down.match(IMAGE, "image/png")).outcome === "unavailable", "network");
  const webp = photoDnaMatcher("k", PHOTODNA_DEFAULT_URL, ok.fetchFn);
  assert((await webp.match(IMAGE, "image/webp")).vendorRef === "unsupported_type:image/webp", "webp");
  // B5 I-3: a 200 that is not JSON is unavailable, never clear.
  const html = await photoDnaMatcher("k", PHOTODNA_DEFAULT_URL, recorder(() => new Response("<html>", { status: 200 })).fetchFn)
    .match(IMAGE, "image/jpeg");
  assert(html.outcome === "unavailable" && html.vendorRef === "unreadable_response", JSON.stringify(html));
  // B5 M3: a non-OK body is released.
  let cancelled = false;
  const body = new ReadableStream({ cancel() { cancelled = true; } });
  const busyBody = await photoDnaMatcher("k", PHOTODNA_DEFAULT_URL, () => Promise.resolve(new Response(body, { status: 503 })))
    .match(IMAGE, "image/jpeg");
  assert(busyBody.vendorRef === "http:503" && cancelled, "the 503 body was not cancelled");
});

Deno.test("photodna: a slow answer times out as unavailable", async () => {
  const slow = hangingFetch();
  const r = await photoDnaMatcher("k", PHOTODNA_DEFAULT_URL, slow, 20).match(IMAGE, "image/jpeg");
  assert(r.outcome === "unavailable" && r.vendorRef === "timeout", JSON.stringify(r));
});

Deno.test("safer: multipart media and the token; matched / empty / anything else", async () => {
  const ok = recorder(() => json({ id: "task-1", output: { file: { reasons: [] }, hashes: [] } }));
  const m = matcherFromEnv({
    env: env({ CSAM_MATCHER: "safer", SAFER_API_KEY: "s-1", SAFER_MATCH_URL: "https://safer.example/match" }),
    fetch: ok.fetchFn,
    environment: "production",
  });
  const r = await m.match(IMAGE, "image/jpeg");
  assert(r.outcome === "clear" && r.vendorRef === "task-1", JSON.stringify(r));
  const call = ok.calls[0];
  assert(call.url === "https://safer.example/match", call.url);
  assert((call.init.headers as Record<string, string>).Authorization === "Token s-1", "token");
  const form = call.init.body as FormData;
  assert(form instanceof FormData && form.get("media") instanceof Blob, "multipart media");

  const matched = readSaferMatch({
    output: { file: { reasons: ["matched"] }, hashes: [{ sources: [{ matches: [{ sourceId: "src-9" }] }] }] },
  });
  assert(matched.outcome === "match" && matched.vendorRef === "src-9", JSON.stringify(matched));
  for (const body of [{}, { output: { file: { reasons: ["other"] }, hashes: [] } },
                      { output: { file: { reasons: [] }, hashes: [{}] } }, { output: { file: {} } }, null]) {
    assert(readSaferMatch(body).outcome === "unavailable", JSON.stringify(body));
  }
  const err = saferMatcher("k", "https://safer.example/match", recorder(() => json({}, 500)).fetchFn);
  assert((await err.match(IMAGE, "image/jpeg")).vendorRef === "http:500", "500");
  // A matched reason wins even with no hash rows (match-biased).
  assert(readSaferMatch({ output: { file: { reasons: ["matched"] }, hashes: [] } }).outcome === "match", "matched, no hashes");

  // B5 I-3: a network error, a slow answer and a 200 that is not JSON are
  // unavailable, never clear.
  const down = await saferMatcher("k", "https://safer.example/match", () => Promise.reject(new TypeError("dns"))).match(IMAGE, "image/jpeg");
  assert(down.outcome === "unavailable" && down.vendorRef === "network", JSON.stringify(down));
  const slow = hangingFetch();
  const late = await saferMatcher("k", "https://safer.example/match", slow, 20).match(IMAGE, "image/jpeg");
  assert(late.outcome === "unavailable" && late.vendorRef === "timeout", JSON.stringify(late));
  const html = await saferMatcher("k", "https://safer.example/match", recorder(() => new Response("<html>", { status: 200 })).fetchFn)
    .match(IMAGE, "image/jpeg");
  assert(html.outcome === "unavailable" && html.vendorRef === "unreadable_response", JSON.stringify(html));
});

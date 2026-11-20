// Spec 2 W5b (§4.7, §7.3; carries 12-14): dating-photo-urls. A viewer gets
// URLs only for the keys the service function allows, 60 seconds each,
// in position order; the phone's hash is passed on and a phone with no id
// is device_unavailable; refusals are fixed codes, a server error is busy;
// the answer carries only position and url, a storage key only inside its
// signed URL (as Storage builds it), never a server's text or an error;
// nothing is logged; the hash matches dating-verification's.
// Fix round 1 (T5 review M-1..M-6): realistic signed URLs; a viewer id in
// the body is ignored; a photo that fails to sign is dropped, all of them
// failing is busy; a rejected or slow call is busy; an upper-case id; the
// request wiring (request.ts) with no-store on every answer.
import {
  deviceHashOf,
  handlePhotoUrls,
  type PhotoUrlDeps,
  RPC_TIMEOUT_MS,
  SIGN_TIMEOUT_MS,
  SIGNED_URL_SECONDS,
} from "./handler.ts";
import { deviceHashOf as verificationHash } from "../dating-verification/handler.ts";
import { handleRequest, type PhotoClient } from "./request.ts";
import { HttpError } from "../_shared/attune_auth.ts";

function eq(actual: unknown, expected: unknown, why = "") {
  const a = JSON.stringify(actual), e = JSON.stringify(expected);
  if (a !== e) throw new Error(`${why} expected ${e}, got ${a}`);
}

const ID = "11111111-2222-4333-8444-555555555555";
const HASH = "a".repeat(64);
const CALLER = { userId: "99999999-2222-4333-8444-555555555555", deviceHash: HASH };

interface Seen {
  rpc: Array<[string, Record<string, unknown>]>;
  signed: Array<[string[], number]>;
}

/// A signed URL as Storage builds it: the key is in its path (T5 review M-1).
const signedUrlOf = (k: string) => `https://storage.test/storage/v1/object/sign/dating-profile-photos/${k}?token=t`;

interface Opts {
  rpcError?: boolean;
  rpcRejects?: boolean;
  rpcHangs?: boolean;
  signThrows?: boolean;
  signHangs?: boolean;
  /// Keys whose signed URL comes back null.
  unsigned?: string[];
  /// Keys answered under another path (not one that was asked).
  misplaced?: string[];
}

const never = <T>() => new Promise<T>(() => {});

function deps(data: unknown, seen: Seen, opts: Opts = {}): PhotoUrlDeps {
  return {
    rpc: (fn, args) => {
      seen.rpc.push([fn, args]);
      if (opts.rpcRejects) return Promise.reject(new Error("server text: connection reset"));
      if (opts.rpcHangs) return never();
      return Promise.resolve(opts.rpcError ? { data: null, error: { code: "XX000", message: "server text" } } : { data, error: null });
    },
    sign: (keys, seconds) => {
      seen.signed.push([keys, seconds]);
      if (opts.signThrows) return Promise.reject(new Error("storage down: key " + keys[0]));
      if (opts.signHangs) return never();
      return Promise.resolve(keys.map((k) => ({
        path: opts.misplaced?.includes(k) ? k + ".other" : k,
        signedUrl: opts.unsigned?.includes(k) ? null : signedUrlOf(k),
      })));
    },
    rpcTimeoutMs: 20,
    signTimeoutMs: 20,
  };
}

/// T5 review M-1: only position and url, each url exactly the signed one,
/// and a storage key nowhere outside a url.
function onlyInsideUrls(answer: unknown, keys: string[]) {
  const a = answer as { photos?: Array<Record<string, unknown>> };
  for (const p of a.photos ?? []) {
    eq(Object.keys(p).sort(), ["position", "url"], "fields");
    if (!keys.some((k) => p.url === signedUrlOf(k))) throw new Error("a url is not the signed one: " + String(p.url));
  }
  const withoutUrls = JSON.stringify(answer, (k, v) => (k === "url" ? undefined : v));
  for (const k of keys) if (withoutUrls.includes(k)) throw new Error("a storage key left outside its url: " + k);
}

const fresh = (): Seen => ({ rpc: [], signed: [] });

function quietly<T>(f: () => Promise<T>): Promise<T> {
  const original = { log: console.log, error: console.error, warn: console.warn, info: console.info };
  const said: unknown[] = [];
  console.log = console.error = console.warn = console.info = (...a: unknown[]) => said.push(a);
  return f().finally(() => {
    Object.assign(console, original);
    if (said.length > 0) throw new Error("the handler logged: " + JSON.stringify(said));
  });
}

Deno.test("a viewer gets 60-second URLs for exactly the allowed keys, in order; only position and url, a key only inside its URL", () =>
  quietly(async () => {
    const seen = fresh();
    const answer = await handlePhotoUrls({ kind: "introduction", id: ID }, CALLER, deps({
      ok: true,
      photos: [{ position: 2, key: "dating-photos/b.jpg" }, { position: 1, key: "dating-photos/a.jpg" }],
    }, seen));
    eq(seen.rpc, [["dating_photo_keys_for_viewer", { p_viewer: CALLER.userId, p_kind: "introduction", p_id: ID, p_device_hash: HASH }]]);
    eq(seen.signed, [[["dating-photos/b.jpg", "dating-photos/a.jpg"], 60]]);
    eq(SIGNED_URL_SECONDS, 60);
    if (!answer.ok) throw new Error("refused");
    eq(answer.photos.map((p) => p.position), [1, 2]);
    eq(answer.photos.map((p) => p.url), [signedUrlOf("dating-photos/a.jpg"), signedUrlOf("dating-photos/b.jpg")]);
    onlyInsideUrls(answer, ["dating-photos/a.jpg", "dating-photos/b.jpg"]);
  }));

Deno.test("a match reads its other member's photos the same way", () =>
  quietly(async () => {
    const seen = fresh();
    const answer = await handlePhotoUrls({ kind: "match", id: ID }, CALLER, deps({ ok: true, photos: [{ position: 1, key: "k1" }] }, seen));
    eq(seen.rpc[0][1].p_kind, "match");
    eq(answer.ok && answer.photos.length, 1);
  }));

Deno.test("no install id on the phone: device_unavailable, the database never asked (W4 I-4)", () =>
  quietly(async () => {
    const seen = fresh();
    eq(await handlePhotoUrls({ kind: "introduction", id: ID }, { ...CALLER, deviceHash: null }, deps({ ok: true, photos: [] }, seen)),
      { ok: false, reason: "device_unavailable" });
    eq(seen.rpc.length, 0);
  }));

Deno.test("refusals are fixed codes; a server error or an unknown answer is busy or unavailable, never its text", () =>
  quietly(async () => {
    eq(await handlePhotoUrls({ kind: "introduction", id: ID }, CALLER, deps({ ok: false, reason: "reverify_device" }, fresh())),
      { ok: false, reason: "reverify_device" });
    eq(await handlePhotoUrls({ kind: "introduction", id: ID }, CALLER, deps({ ok: false, reason: "photos_unavailable" }, fresh())),
      { ok: false, reason: "photos_unavailable" });
    eq(await handlePhotoUrls({ kind: "introduction", id: ID }, CALLER, deps({ ok: false, reason: "a server's own words" }, fresh())),
      { ok: false, reason: "photos_unavailable" });
    eq(await handlePhotoUrls({ kind: "introduction", id: ID }, CALLER, deps(null, fresh(), { rpcError: true })),
      { ok: false, reason: "busy" });
    const seen = fresh();
    eq(await handlePhotoUrls({ kind: "introduction", id: ID }, CALLER, deps({ ok: true, photos: [{ position: 1, key: "k" }] }, seen, { signThrows: true })),
      { ok: false, reason: "busy" });
  }));

Deno.test("no photos to sign: an empty list, Storage never asked", () =>
  quietly(async () => {
    const seen = fresh();
    eq(await handlePhotoUrls({ kind: "introduction", id: ID }, CALLER, deps({ ok: true, photos: [] }, seen)), { ok: true, photos: [] });
    eq(seen.signed.length, 0);
  }));

Deno.test("a malformed request is invalid before any call", () =>
  quietly(async () => {
    for (const body of [null, {}, { kind: "profile", id: ID }, { kind: "introduction", id: "not-a-uuid" }, { kind: "match", id: 7 }]) {
      const seen = fresh();
      eq(await handlePhotoUrls(body, CALLER, deps({ ok: true, photos: [] }, seen)), { ok: false, reason: "invalid" }, JSON.stringify(body));
      eq(seen.rpc.length, 0);
    }
  }));

Deno.test("the device hash is dating-verification's (one phone, one hash)", async () => {
  for (const h of ["0123456789abcdef0123456789abcdef", "nope", null]) {
    eq(await deviceHashOf(h), await verificationHash(h), String(h));
  }
});

// ---- Fix round 1 (T5 review M-2, M-4, M-5, M-6) ----

Deno.test("a viewer id in the body is ignored; the signed-in person's id is the viewer (M-4a)", () =>
  quietly(async () => {
    const seen = fresh();
    const other = "77777777-2222-4333-8444-555555555555";
    await handlePhotoUrls({ kind: "introduction", id: ID, viewer: other, p_viewer: other, user_id: other, p_device_hash: "b".repeat(64) },
      CALLER, deps({ ok: true, photos: [] }, seen));
    eq(seen.rpc, [["dating_photo_keys_for_viewer", { p_viewer: CALLER.userId, p_kind: "introduction", p_id: ID, p_device_hash: HASH }]]);
  }));

Deno.test("a photo whose URL comes back null or under another path is dropped; the rest return (M-4b)", () =>
  quietly(async () => {
    const answer = await handlePhotoUrls({ kind: "match", id: ID }, CALLER, deps({
      ok: true,
      photos: [{ position: 1, key: "k1" }, { position: 2, key: "k2" }, { position: 3, key: "k3" }],
    }, fresh(), { unsigned: ["k2"], misplaced: ["k3"] }));
    eq(answer, { ok: true, photos: [{ position: 1, url: signedUrlOf("k1") }] });
  }));

Deno.test("every listed photo failing to sign is busy, not an empty list (M-2)", () =>
  quietly(async () => {
    const seen = fresh();
    eq(await handlePhotoUrls({ kind: "introduction", id: ID }, CALLER, deps({
      ok: true,
      photos: [{ position: 1, key: "k1" }, { position: 2, key: "k2" }],
    }, seen, { unsigned: ["k1", "k2"] })), { ok: false, reason: "busy" });
    eq(seen.signed.length, 1);
  }));

Deno.test("the database call rejecting is busy, never its text (M-4c)", () =>
  quietly(async () => {
    const answer = await handlePhotoUrls({ kind: "introduction", id: ID }, CALLER, deps(null, fresh(), { rpcRejects: true }));
    eq(answer, { ok: false, reason: "busy" });
  }));

Deno.test("a database call that never answers is busy within its bound; Storage never asked (M-5)", () =>
  quietly(async () => {
    const seen = fresh();
    eq(await handlePhotoUrls({ kind: "introduction", id: ID }, CALLER, deps(null, seen, { rpcHangs: true })), { ok: false, reason: "busy" });
    eq(seen.signed.length, 0);
    eq(RPC_TIMEOUT_MS, 5_000, "the database bound");
  }));

Deno.test("a signing call that never answers is busy within its bound (M-5)", () =>
  quietly(async () => {
    eq(await handlePhotoUrls({ kind: "introduction", id: ID }, CALLER,
      deps({ ok: true, photos: [{ position: 1, key: "k1" }] }, fresh(), { signHangs: true })), { ok: false, reason: "busy" });
    eq(SIGN_TIMEOUT_MS, 5_000, "the signing bound");
  }));

Deno.test("an upper-case id is the same id, passed on in lower case (M-6)", () =>
  quietly(async () => {
    const seen = fresh();
    const lower = "abcdef12-2222-4333-8444-5555555555ef";
    const answer = await handlePhotoUrls({ kind: "introduction", id: lower.toUpperCase() }, CALLER, deps({ ok: true, photos: [] }, seen));
    eq(answer, { ok: true, photos: [] });
    eq(seen.rpc[0][1].p_id, lower);
  }));

// ---- The request wiring (request.ts; T5 review M-3, M-4d) ----

interface WireSeen {
  rpc: Array<[string, Record<string, unknown>]>;
  buckets: string[];
  signed: Array<[string[], number]>;
}

function client(seen: WireSeen, data: unknown, storage: "ok" | "error" | "throws" = "ok"): PhotoClient {
  return {
    rpc: (fn, args) => {
      seen.rpc.push([fn, args]);
      return Promise.resolve({ data, error: null });
    },
    storage: {
      from: (bucket) => {
        seen.buckets.push(bucket);
        return {
          createSignedUrls: (keys, seconds) => {
            seen.signed.push([keys, seconds]);
            if (storage === "throws") return Promise.reject(new Error("storage text"));
            if (storage === "error") return Promise.resolve({ data: null, error: { message: "storage text" } });
            return Promise.resolve({ data: keys.map((k) => ({ path: k, signedUrl: signedUrlOf(k) })), error: null });
          },
        };
      },
    },
  };
}

const INSTALL = "0123456789abcdef0123456789abcdef";

function post(body: unknown, headers: Record<string, string> = { "x-attune-device": INSTALL }): Request {
  return new Request("https://fn.test/dating-photo-urls", { method: "POST", headers, body: JSON.stringify(body) });
}

async function read(res: Response): Promise<[number, string | null, unknown]> {
  return [res.status, res.headers.get("cache-control"), await res.json()];
}

const signedIn = { requireUser: () => Promise.resolve({ id: CALLER.userId }) };

Deno.test("wiring: the JWT's person, the hashed install id, dating-profile-photos for 60 s; no-store (M-3, M-4d)", () =>
  quietly(async () => {
    const seen: WireSeen = { rpc: [], buckets: [], signed: [] };
    const res = await handleRequest(post({ kind: "introduction", id: ID, viewer: "someone" }), {
      ...signedIn,
      client: () => client(seen, { ok: true, photos: [{ position: 1, key: "dating-photos/a.jpg" }] }),
    });
    eq(await read(res), [200, "no-store", { ok: true, photos: [{ position: 1, url: signedUrlOf("dating-photos/a.jpg") }] }]);
    eq(seen.rpc, [["dating_photo_keys_for_viewer", {
      p_viewer: CALLER.userId, p_kind: "introduction", p_id: ID, p_device_hash: await deviceHashOf(INSTALL),
    }]]);
    if (JSON.stringify(seen.rpc).includes(INSTALL)) throw new Error("the raw install id was passed on");
    eq(seen.buckets, ["dating-profile-photos"]);
    eq(seen.signed, [[["dating-photos/a.jpg"], 60]]);
  }));

Deno.test("wiring: every refusal is no-store too, with fixed codes only (M-3, M-4d)", async () => {
  const seen = (): WireSeen => ({ rpc: [], buckets: [], signed: [] });
  // No install id on the phone.
  eq(await read(await handleRequest(post({ kind: "introduction", id: ID }, {}), { ...signedIn, client: () => client(seen(), null) })),
    [200, "no-store", { ok: false, reason: "device_unavailable" }]);
  // A refusal from the service function.
  eq(await read(await handleRequest(post({ kind: "match", id: ID }), {
    ...signedIn, client: () => client(seen(), { ok: false, reason: "reverify_device" }),
  })), [200, "no-store", { ok: false, reason: "reverify_device" }]);
  // Storage answering an error, or throwing.
  for (const storage of ["error", "throws"] as const) {
    eq(await read(await handleRequest(post({ kind: "match", id: ID }), {
      ...signedIn, client: () => client(seen(), { ok: true, photos: [{ position: 1, key: "k1" }] }, storage),
    })), [200, "no-store", { ok: false, reason: "busy" }], storage);
  }
  // Not signed in.
  eq(await read(await handleRequest(post({ kind: "match", id: ID }), {
    requireUser: () => Promise.reject(new HttpError("Invalid authorization token", 401)),
    client: () => client(seen(), null),
  })), [401, "no-store", { ok: false, reason: "unauthorized" }]);
  // Not a POST; bad JSON.
  eq(await read(await handleRequest(new Request("https://fn.test/x", { method: "GET" }), { ...signedIn, client: () => client(seen(), null) })),
    [405, "no-store", { ok: false, reason: "invalid" }]);
  eq(await read(await handleRequest(new Request("https://fn.test/x", { method: "POST", body: "{not json" }), {
    ...signedIn, client: () => client(seen(), null),
  })), [200, "no-store", { ok: false, reason: "invalid" }]);
  // An unexpected failure: busy, and only the error's code is logged.
  const said: unknown[][] = [];
  const original = console.error;
  console.error = (...a: unknown[]) => said.push(a);
  try {
    eq(await read(await handleRequest(post({ kind: "match", id: ID }), {
      ...signedIn,
      client: () => { throw Object.assign(new Error("secret server text"), { code: "PGRST301" }); },
    })), [500, "no-store", { ok: false, reason: "busy" }]);
  } finally {
    console.error = original;
  }
  eq(said, [["dating-photo-urls failed:", "PGRST301"]]);
});

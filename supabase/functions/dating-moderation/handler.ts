// supabase/functions/dating-moderation/handler.ts
// Spec 2 W7b (§4.7, §6.4, §7.3; S-5): the console's API. One POST body
// {action, ...}; each action is one moderation_* service function, called
// with the signed-in moderator's id (never one from the body). Every call
// needs a session at aal2 (TOTP); the database refuses anyone who is not an
// active moderator (not_moderator) and writes every action to the audit.
// Storage keys never leave: a case's photos, the photo queue's and a
// verification's photos are signed here for 60 seconds and only the URLs
// are answered. A refusal is a fixed code; a server's text or an error is
// never answered and nothing but an error's code is logged.
export type RpcResult = { data: unknown; error: unknown };

export interface ModerationDeps {
  rpc(fn: string, args: Record<string, unknown>): PromiseLike<RpcResult>;
  /// Signs [keys] in [bucket] for [seconds]; throws when Storage can't.
  sign(bucket: string, keys: string[], seconds: number): Promise<Array<{ path: string | null; signedUrl: string | null }>>;
  rpcTimeoutMs?: number;
  /// Told when [fn] outlives rpcTimeoutMs (fix round 1, review M-5: the
  /// wiring logs it; the late call is not awaited).
  onTimeout?(fn: string): void;
}

export interface Caller {
  userId: string;
  /// The session's authenticator assurance level ('aal1', 'aal2').
  aal: string | null;
}

export type Answer = { ok: true; [key: string]: unknown } | { ok: false; reason: string; id?: string };

export const SIGNED_URL_SECONDS = 60;
export const RPC_TIMEOUT_MS = 10_000;
export const PHOTO_BUCKET = "dating-profile-photos";
export const REVIEW_BUCKET = "dating-verification-review";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const DAY = /^\d{4}-\d{2}-\d{2}$/;
/// Spec 2 W7c (§6.5): CSA 292 only with the victim's consent (its own kind).
const ESCALATIONS = new Set(["police", "ncmec", "iwf", "csa", "csa_292_with_consent"]);
const CATEGORIES = new Set([
  "underage_risk", "csam", "child_safety", "threat_to_life", "sextortion", "romance_scam", "threats", "entrapment",
  "harassment", "explicit_content", "impersonation", "hiding_relationship", "spam", "other",
]);
/// The fixed codes the console may read; anything else is busy.
export const REASONS: ReadonlySet<string> = new Set([
  "invalid", "not_moderator", "case_unavailable", "same_decider", "appeal_unavailable", "photo_unavailable",
  "session_unavailable", "safety_owner_only", "mfa_required", "busy",
  // Task 6, from Task 5's live replies: an appeal whose restriction has no
  // recorded decider (R1-3), and publish_country_config's own refusals.
  "decider_unknown",
  // Fix round 2 (Task 5 fix round 1, M-5): another moderator's live claim.
  "claimed",
  "config:invalid_country", "config:invalid_values", "config:unknown_key", "config:invalid_tz", "config:invalid_lists",
  "config:checklist_keys_removed", "config:invalid_regions", "config:no_calling_code",
  "config:production_checks_failed",
  // Spec 2 W7c (Task 8 fix round 1): the log's request already logged with
  // another decision, a disclosure only widened, CSA on a sextortion case
  // only as the consent kind, and a CSAM hold that isn't live (or is the
  // owner's own).
  "exists", "already_disclosed", "consent_kind_required", "hold_unavailable",
]);

type Body = Record<string, unknown>;
const id = (v: unknown): string | null => (typeof v === "string" && UUID.test(v.toLowerCase()) ? v.toLowerCase() : null);
const text = (v: unknown, max: number): string | null =>
  // Fix round 1 (review M-9): code points, as the database's char_length.
  typeof v === "string" && v.trim().length > 0 && [...v].length <= max ? v : null;
const limit = (v: unknown, def: number, max: number): number =>
  typeof v === "number" && Number.isInteger(v) && v >= 1 && v <= max ? v : def;
/// W7 final client fix (I-5): the queue's kinds (moderation_queue's
/// p_kind); id_check is every case whose asked age check is live, decided
/// ones too. No kind: every open kind and the id_check set.
export const QUEUE_KINDS: ReadonlySet<string> = new Set([
  "report", "appeal", "signal", "photo", "verification", "csam_hit", "id_check",
]);

/// Each action: its function and its arguments (null: invalid input).
export const ACTIONS: Record<string, { fn: string; args: (b: Body) => Record<string, unknown> | null }> = {
  whoami: { fn: "moderation_whoami", args: () => ({}) },
  queue: {
    fn: "moderation_queue",
    args: (b) =>
      b.kind === undefined || b.kind === null
        ? { p_limit: limit(b.limit, 50, 200), p_kind: null }
        : typeof b.kind === "string" && QUEUE_KINDS.has(b.kind)
        ? { p_limit: limit(b.limit, 50, 200), p_kind: b.kind }
        : null,
  },
  case: { fn: "moderation_case", args: (b) => (id(b.case_id) ? { p_case: id(b.case_id) } : null) },
  claim: { fn: "moderation_claim", args: (b) => (id(b.case_id) ? { p_case: id(b.case_id) } : null) },
  dismiss: { fn: "moderation_dismiss", args: (b) => (id(b.case_id) ? { p_case: id(b.case_id) } : null) },
  hold: {
    fn: "moderation_place_hold",
    args: (b) =>
      id(b.case_id) && typeof b.category === "string" && CATEGORIES.has(b.category)
        ? { p_case: id(b.case_id), p_category: b.category }
        : null,
  },
  lift_hold: { fn: "moderation_lift_hold", args: (b) => (id(b.case_id) ? { p_case: id(b.case_id) } : null) },
  // W7 final client fix (server round 2): an open case's own holds (its
  // interim holds and report age checks; never the asked age check, never
  // CSAM), the way to lift them once the ID track has its outcome.
  lift_case_holds: {
    fn: "moderation_lift_case_holds",
    args: (b) => (id(b.case_id) ? { p_case: id(b.case_id) } : null),
  },
  restrict: {
    fn: "moderation_restrict",
    args: (b) => {
      const endsAt = b.ends_at === null || b.ends_at === undefined
        ? null
        : typeof b.ends_at === "string" && !Number.isNaN(Date.parse(b.ends_at))
        ? new Date(b.ends_at).toISOString()
        : undefined;
      return id(b.case_id) && (b.type === "suspended" || b.type === "under_review") && endsAt !== undefined &&
          typeof b.category === "string" && CATEGORIES.has(b.category)
        ? { p_case: id(b.case_id), p_type: b.type, p_ends_at: endsAt, p_category: b.category }
        : null;
    },
  },
  ask_for_id: { fn: "moderation_ask_for_id", args: (b) => (id(b.case_id) ? { p_case: id(b.case_id) } : null) },
  confirm_minor: { fn: "moderation_confirm_minor", args: (b) => (id(b.case_id) ? { p_case: id(b.case_id) } : null) },
  // Spec 2 W7c (server round 5): "No ID came" decides a case waiting for ID
  // (outcome no_id_received; the age check stays).
  close_no_id: { fn: "moderation_close_no_id", args: (b) => (id(b.case_id) ? { p_case: id(b.case_id) } : null) },
  note: {
    fn: "moderation_note",
    args: (b) => (id(b.case_id) && text(b.note, 1000) ? { p_case: id(b.case_id), p_note: b.note } : null),
  },
  decide_appeal: {
    fn: "moderation_decide_appeal",
    args: (b) => (id(b.case_id) && typeof b.accept === "boolean" ? { p_case: id(b.case_id), p_accept: b.accept } : null),
  },
  photos: { fn: "moderation_photos", args: () => ({}) },
  photo_decide: {
    fn: "moderation_photo_decide",
    args: (b) =>
      id(b.photo_id) && typeof b.approve === "boolean"
        ? { p_photo: id(b.photo_id), p_approve: b.approve, p_reason: typeof b.reason === "string" ? b.reason : null }
        : null,
  },
  verifications: { fn: "moderation_verifications", args: () => ({}) },
  verification_decide: {
    fn: "moderation_verification_decide",
    args: (b) =>
      id(b.session_id) && (b.outcome === "pass" || b.outcome === "fail" || b.outcome === "ask_for_id")
        ? { p_session: id(b.session_id), p_outcome: b.outcome }
        : null,
  },
  countries: { fn: "moderation_countries", args: () => ({}) },
  publish_country: {
    fn: "moderation_publish_country",
    args: (b) =>
      typeof b.country === "string" && /^[A-Z]{2}$/.test(b.country) && b.values !== null && typeof b.values === "object" &&
        !Array.isArray(b.values)
        ? { p_country: b.country, p_values: b.values }
        : null,
  },
  opinions_queue: { fn: "moderation_opinions_queue", args: (b) => ({ p_limit: limit(b.limit, 50, 200) }) },
  opinions_remove: {
    fn: "moderation_opinions_remove",
    args: (b) => ((b.type === "opinion" || b.type === "comment") && id(b.id) ? { p_type: b.type, p_id: id(b.id) } : null),
  },
  audit: { fn: "moderation_audit_log", args: (b) => ({ p_limit: limit(b.limit, 100, 500) }) },
  // Spec 2 W7c (§6.5, §6.6): an escalation (a record, never a send), the
  // law-enforcement log and the transparency summary (the safety owner's).
  escalate: {
    fn: "moderation_record_escalation",
    args: (b) =>
      id(b.case_id) && typeof b.kind === "string" && ESCALATIONS.has(b.kind) &&
        (b.reference === undefined || b.reference === null || text(b.reference, 200))
        ? { p_case: id(b.case_id), p_kind: b.kind, p_reference: typeof b.reference === "string" ? b.reference : null }
        : null,
  },
  le_requests: { fn: "moderation_le_requests", args: () => ({}) },
  le_record: {
    fn: "moderation_record_le_request",
    args: (b) =>
      (b.request_id === undefined || b.request_id === null || id(b.request_id)) && b.values !== null &&
        typeof b.values === "object" && !Array.isArray(b.values)
        ? { p_request: b.request_id ? id(b.request_id) : null, p_values: b.values }
        : null,
  },
  transparency: {
    fn: "moderation_transparency_summary",
    args: (b) =>
      typeof b.from === "string" && DAY.test(b.from) && typeof b.to === "string" && DAY.test(b.to)
        ? { p_from: b.from, p_to: b.to }
        : null,
  },
  // Spec 2 W7c (Task 8 fix round 1, (b)): a case's escalations, read by any
  // moderator who can see the case (the reference is the owner's and the
  // recorder's alone, the database's rule).
  case_escalations: {
    fn: "moderation_case_escalations",
    args: (b) => (id(b.case_id) ? { p_case: id(b.case_id) } : null),
  },
  // Owner 2026-11-22 (R-60): the CSAM hold list and its lift, the safety
  // owner's alone (the database refuses anyone else: safety_owner_only).
  // The lift needs a written reason, at most 1000 code points.
  csam_holds: { fn: "moderation_csam_holds", args: () => ({}) },
  lift_csam_hold: {
    fn: "moderation_lift_csam_hold",
    args: (b) =>
      id(b.restriction_id) && text(b.reason, 1000)
        ? { p_restriction: id(b.restriction_id), p_reason: b.reason }
        : null,
  },
};

class RpcTimeout extends Error {}

function withTimeout<T>(p: PromiseLike<T>, ms: number): Promise<T> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  const late = new Promise<never>((_, reject) => {
    timer = setTimeout(() => reject(new RpcTimeout("timeout")), ms);
  });
  return Promise.race([Promise.resolve(p), late]).finally(() => clearTimeout(timer));
}

type Photo = { key?: unknown; url?: string | null; [k: string]: unknown };
type Urls = Map<string, string | null>;

const objects = (v: unknown): Array<Record<string, unknown>> =>
  Array.isArray(v) ? v.filter((x): x is Record<string, unknown> => x !== null && typeof x === "object" && !Array.isArray(x)) : [];
const keysOf = (photos: Photo[]): string[] =>
  photos.map((p) => (typeof p.key === "string" ? p.key : null)).filter((k): k is string => k !== null);
const pathsOf = (v: unknown): string[] => (Array.isArray(v) ? v.filter((p): p is string => typeof p === "string") : []);

/// Signs [keys] in [bucket] in one call (Task 6: one call per bucket per
/// answer, never one per session). A key that fails to sign, or every key
/// when Storage can't, is missing from the map, so its url is null.
async function signKeys(keys: string[], bucket: string, deps: ModerationDeps): Promise<Urls> {
  const unique = [...new Set(keys)];
  if (unique.length === 0) return new Map();
  try {
    const signed = await deps.sign(bucket, unique, SIGNED_URL_SECONDS);
    return new Map(signed.filter((s) => s.path !== null).map((s) => [s.path as string, s.signedUrl]));
  } catch {
    return new Map();
  }
}

/// Replaces every {key} in [photos] with its {url}. Keys never stay in the
/// answer.
function withUrls(photos: Photo[], byKey: Urls): Photo[] {
  return photos.map(({ key, ...rest }) => ({ ...rest, url: typeof key === "string" ? byKey.get(key) ?? null : null }));
}

/// Signs what [action]'s answer carries as storage keys.
async function signed(action: string, data: Record<string, unknown>, deps: ModerationDeps): Promise<Record<string, unknown>> {
  if (action === "case" && data.profile && typeof data.profile === "object" && !Array.isArray(data.profile)) {
    const profile = data.profile as Record<string, unknown>;
    const photos = objects(profile.photos);
    return { ...data, profile: { ...profile, photos: withUrls(photos, await signKeys(keysOf(photos), PHOTO_BUCKET, deps)) } };
  }
  if (action === "photos" && Array.isArray(data.photos)) {
    const photos = objects(data.photos);
    return { ...data, photos: withUrls(photos, await signKeys(keysOf(photos), PHOTO_BUCKET, deps)) };
  }
  if (action === "verifications" && Array.isArray(data.sessions)) {
    const sessions = objects(data.sessions);
    const [photoUrls, reviewUrls] = await Promise.all([
      signKeys(sessions.flatMap((s) => keysOf(objects(s.photos))), PHOTO_BUCKET, deps),
      signKeys(sessions.flatMap((s) => pathsOf(s.review_paths)), REVIEW_BUCKET, deps),
    ]);
    return {
      ...data,
      sessions: sessions.map(({ review_paths, photos, ...rest }) => ({
        ...rest,
        photos: withUrls(objects(photos), photoUrls),
        review: pathsOf(review_paths).map((p) => reviewUrls.get(p) ?? null),
      })),
    };
  }
  return data;
}

export async function handleModeration(body: unknown, caller: Caller, deps: ModerationDeps): Promise<Answer> {
  const b = (body && typeof body === "object" && !Array.isArray(body) ? body : {}) as Body;
  const action = typeof b.action === "string" ? b.action : "";
  const entry = Object.prototype.hasOwnProperty.call(ACTIONS, action) ? ACTIONS[action] : undefined;
  if (!entry) return { ok: false, reason: "invalid" };
  // §6.4: TOTP for every call, read or write.
  if (caller.aal !== "aal2") return { ok: false, reason: "mfa_required" };
  const args = entry.args(b);
  if (args === null) return { ok: false, reason: "invalid" };
  let res: RpcResult;
  try {
    // Fix round 1 (review M-1): p_actor last, so no argument builder can
    // override the signed-in moderator.
    res = await withTimeout(deps.rpc(entry.fn, { ...args, p_actor: caller.userId }), deps.rpcTimeoutMs ?? RPC_TIMEOUT_MS);
  } catch (error) {
    if (error instanceof RpcTimeout) deps.onTimeout?.(entry.fn);
    return { ok: false, reason: "busy" };
  }
  if (res.error || !res.data || typeof res.data !== "object" || Array.isArray(res.data)) {
    return { ok: false, reason: "busy" };
  }
  const data = res.data as Record<string, unknown>;
  if (data.ok !== true) {
    const reason = typeof data.reason === "string" && REASONS.has(data.reason) ? data.reason : "busy";
    // Spec 2 W7c: exists names the request already in the log (a uuid, the
    // owner's own row), so the console decides it through that id. Nothing
    // else of a refusal leaves.
    const logged = action === "le_record" && reason === "exists" ? id(data.id) : null;
    return logged ? { ok: false, reason, id: logged } : { ok: false, reason };
  }
  return { ...(await signed(action, data, deps)), ok: true };
}

/// The session's assurance level from a JWT's payload ('aal' claim); null
/// when it can't be read. The token itself is checked by Auth first.
export function aalOf(token: string): string | null {
  const part = token.split(".")[1];
  if (!part) return null;
  try {
    const json = atob(part.replace(/-/g, "+").replace(/_/g, "/").padEnd(Math.ceil(part.length / 4) * 4, "="));
    const aal = (JSON.parse(json) as { aal?: unknown }).aal;
    return typeof aal === "string" ? aal : null;
  } catch {
    return null;
  }
}

// ai-sessions: the single client-reachable surface for every AI Sessions
// command Plan B's database layer exposes. Spec §3.1, §4.1, §10.
//
// Shape follows ai-assist/index.ts: a typed error envelope at the top, a
// request-contract validator that runs to completion before any DB or
// provider work, a thin `serve()` -> `handleRequest` (real JWT
// verification) -> exported `processSessionCommand` split so the whole
// lifecycle below the HTTP layer is directly testable.
//
// ONE DELIBERATE DIVERGENCE from ai-assist/ai-understand: there is no
// user-scoped client here at all. Those two split between a user-scoped
// `client` for content reads and a service client for quota/drafts;
// Plan B's Sessions tables are RLS-enabled with ZERO policies, so a
// user-scoped read returns nothing useful, and every Sessions RPC is
// granted to service_role only. Membership and authorization checks
// live inside the RPCs (spec §7.2's "narrow authorized read RPCs").
// Plan C's Architecture paragraph requires exactly this.
//
// THE ACTOR ID NEVER COMES FROM THE REQUEST BODY. Every RPC call made
// from this file passes an actor id that originated in
// requireUser(req)'s server-side auth.getUser verification, threaded
// through `SessionUserContext.user.id`. The envelope validator below
// enforces this structurally: any body field that could name an actor
// is on a reject list, and no branch receives the parsed body's
// identity fields -- see ACTOR_NAMING_FIELDS and its test.

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { isOrdinaryTextRow } from "../_shared/ai_context_loader.ts";
import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";

import {
  AuthenticatedUser,
  jsonResponse,
  requireUser,
  serviceRoleClient,
} from "../_shared/attune_auth.ts";
import {
  canonicalTimestamp,
  civilDayStartUtc,
  computeApprovalDigest,
  isValidUtcOffsetMinutes,
  scalarLength,
  selectSharedWindow,
  WINDOW_ROW_CAP,
  type WindowMessage,
} from "../_shared/ai_session_context.ts";
import {
  callGeminiJson,
  STATIC_PROHIBITED_PATTERNS,
} from "../_shared/gemini_json.ts";
import {
  type NearbyCategory,
  type PlaceSource,
  searchMapboxCategory,
  validateNearbyCategoryOutput,
} from "../_shared/mapbox_search.ts";
import {
  classifySessionContent,
  type SessionSafetyVerdict,
} from "../_shared/ai_session_safety.ts";

// ---------------------------------------------------------------------------
// Error envelope -- spec §10. "Typed envelope: code, caller-safe
// retry_after_seconds when relevant, own request state, and no raw
// exception/provider text."
//
// Diverges from ai-assist's AssistantError on purpose: that envelope
// carries `error: true` and a server-computed `retryable` boolean, both
// of which §10 replaces with the code itself plus retry_after_seconds
// "when relevant". A client of this function branches on `code`; there
// is no second derived field to disagree with it.
// ---------------------------------------------------------------------------

export type SessionErrorCode =
  | "UNAVAILABLE"
  | "CONSENT_REQUIRED"
  | "APPROVAL_REQUIRED"
  | "CONTEXT_CHANGED"
  | "INVALID_INPUT"
  | "CONTEXT_TOO_LARGE"
  | "REQUEST_CONFLICT"
  | "SESSION_BUSY"
  | "SESSION_LIMIT_REACHED"
  | "RATE_LIMITED"
  | "OVERLOADED"
  | "LOCATION_REQUIRED"
  | "LOCATION_EXPIRED"
  | "REQUEST_FAILED"
  | "PROVIDER_UNAVAILABLE"
  | "RESULT_UNAVAILABLE"
  | "FEATURE_DISABLED"
  | "INTERNAL_ERROR";

export interface SessionError {
  code: SessionErrorCode;
  retry_after_seconds?: number;
}

/// The §10 code-to-HTTP-status map. Exported so a test can assert the
/// whole table at once rather than one status per branch.
export const SESSION_ERROR_STATUS: Record<SessionErrorCode, number> = {
  // "unknown/foreign/closed/expired session, relationship change" -- one
  // indistinguishable response, per §3.1.
  UNAVAILABLE: 404,
  // "caller can open consent" -- a refusal the caller can act on.
  CONSENT_REQUIRED: 403,
  // "no automatic retry or new context": both are state conflicts.
  APPROVAL_REQUIRED: 409,
  CONTEXT_CHANGED: 409,
  // "edit or explicitly restart".
  INVALID_INPUT: 400,
  CONTEXT_TOO_LARGE: 413,
  REQUEST_CONFLICT: 409,
  // "keep own draft, retry explicitly after refetch".
  SESSION_BUSY: 409,
  // "start a new session explicitly".
  SESSION_LIMIT_REACHED: 409,
  // "bounded retry-after; never auto-generate later".
  RATE_LIMITED: 429,
  OVERLOADED: 503,
  // "fresh explicit confirmation, no fallback" -- a client-side input
  // problem, not an upstream failure.
  LOCATION_REQUIRED: 400,
  LOCATION_EXPIRED: 400,
  // "counted status explained to requester" -- an upstream failure.
  REQUEST_FAILED: 502,
  PROVIDER_UNAVAILABLE: 502,
  // "expired/revoked result; never replay provider".
  RESULT_UNAVAILABLE: 410,
  // "safe return to chat, no new work".
  FEATURE_DISABLED: 403,
  INTERNAL_ERROR: 500,
};

export function sessionError(
  code: SessionErrorCode,
  retryAfterSeconds?: number | null,
): SessionError {
  return retryAfterSeconds != null
    ? { code, retry_after_seconds: retryAfterSeconds }
    : { code };
}

/// Shapes a §10 response. The body is the envelope and nothing else --
/// no echo of the input, no exception text, no context, which is what
/// "Reads/writes return no raw context on errors" requires.
export function errorResponse(error: SessionError): Response {
  return jsonResponse(
    error as unknown as Record<string, unknown>,
    SESSION_ERROR_STATUS[error.code] ?? SESSION_ERROR_STATUS.INTERNAL_ERROR,
  );
}

// ---------------------------------------------------------------------------
// Request contract -- spec §4.1.
// ---------------------------------------------------------------------------

/// The nine commands of spec §4.1: "prepare, review-context,
/// approve/start, generate, read, publish-nearby, discard-nearby, end
/// and share-answer". Snake_case over the spec's hyphenated prose, and
/// `approve` for the spec's "approve/start" pair -- approving IS what
/// activates a session (§3.2: "Private creator approves ... then
/// activates"), so they are one command, not two.
export const SESSION_COMMANDS: ReadonlySet<string> = new Set([
  "prepare",
  "review_context",
  "approve",
  "generate",
  "read",
  // The §6.1-as-amended polled surface: revision + state, no content.
  // See handleReadState for why it is a separate command rather than a
  // field on `read`.
  "read_state",
  "publish_nearby",
  "discard_nearby",
  "end",
  "share_answer",
]);

/// Spec §4.1: "maximum 4 KiB UTF-8 body". Counted in UTF-8 BYTES, not
/// JS string length -- a 2000-character body of 3-byte characters is
/// 6 KiB on the wire while measuring 2000 by `.length`.
const MAX_BODY_BYTES = 4096;

/// Body fields that would name an actor. Spec §4.1 forbids supplying
/// "author identity" (and visibility, kind, consent version, prior
/// turns, context text, relationship ID, output content) to generate;
/// Plan C's Global Constraint generalizes it to every command.
///
/// This is belt-and-braces, not the primary defense. The primary
/// defense is that no code path in this file reads an identity out of
/// the parsed body -- every RPC call takes its actor from
/// SessionUserContext. Rejecting these fields outright means a client
/// that BELIEVES it can set an actor gets a loud INVALID_INPUT instead
/// of a silently ignored field, which is how such a field survives into
/// a later refactor that does start reading it.
export const ACTOR_NAMING_FIELDS: ReadonlySet<string> = new Set([
  "actor_id",
  "p_actor_id",
  "user_id",
  "p_user_id",
  "requester_id",
  "creator_id",
  "author_id",
  "partner_id",
  "sender_id",
  "actor",
  "user",
]);

export interface CommandEnvelope {
  command: string;
  body: Record<string, unknown>;
}

export type EnvelopeResult =
  | { ok: true; envelope: CommandEnvelope }
  | { ok: false; error: SessionError };

/// Validates the command envelope from the RAW request text. Exported
/// for direct testing: every check here must run before any DB or
/// provider call, so it must be testable with no client dependency at
/// all (ai-assist's validateAssistRequest has the same contract).
///
/// Only the envelope -- `command` plus the actor-field rejection and the
/// size cap. Each command's own bounded schema (§4.1: "All non-generation
/// commands have separate bounded schemas") belongs to the task that
/// adds that branch, validated inside the branch.
export function validateCommandEnvelope(rawText: string): EnvelopeResult {
  if (new TextEncoder().encode(rawText).length > MAX_BODY_BYTES) {
    // §4.1's cap is a hard input bound, so this is INVALID_INPUT rather
    // than CONTEXT_TOO_LARGE -- the latter is reserved for a context
    // WINDOW that exceeds its budget (§4.2), which is a different thing
    // a client fixes by narrowing a selection, not by shortening a body.
    return { ok: false, error: sessionError("INVALID_INPUT") };
  }

  let parsed: unknown;
  try {
    parsed = JSON.parse(rawText);
  } catch {
    // §4.1: "Reject ... invalid JSON".
    return { ok: false, error: sessionError("INVALID_INPUT") };
  }

  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
    return { ok: false, error: sessionError("INVALID_INPUT") };
  }
  const body = parsed as Record<string, unknown>;

  for (const key of Object.keys(body)) {
    if (ACTOR_NAMING_FIELDS.has(key)) {
      return { ok: false, error: sessionError("INVALID_INPUT") };
    }
  }

  const command = body.command;
  if (typeof command !== "string" || !SESSION_COMMANDS.has(command)) {
    return { ok: false, error: sessionError("INVALID_INPUT") };
  }

  return { ok: true, envelope: { command, body } };
}

// ---------------------------------------------------------------------------
// Eligibility gate -- spec §3.1.
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Capability flags -- spec §12, seeded by migration 20260953200000.
// ---------------------------------------------------------------------------

/// The six server-authoritative §12 capabilities: "base Assist,
/// Understand, private Sessions, shared Sessions, recent-window and
/// Nearby; defaults off."
///
/// These are the exact `public.feature_flags.key` values the migration
/// seeds. A typo here would read as an ABSENT key, which
/// ai_capability_enabled COALESCEs to false -- so a typo fails closed
/// rather than open, and the contract test asserts each literal.
export const SESSION_CAPABILITIES = [
  "ai_assist_enabled",
  "ai_understand_enabled",
  "ai_sessions_private_enabled",
  "ai_sessions_shared_enabled",
  "ai_sessions_recent_window_enabled",
  "ai_sessions_nearby_enabled",
] as const;

export type SessionCapability = typeof SESSION_CAPABILITIES[number];

/// Which §12 capabilities a session's own shape requires.
///
/// Derived from the SESSION, not from the command name: every command
/// after `prepare` acts on a session whose kind/visibility/window were
/// frozen at preparation, so the same mapping applies throughout the
/// session's life. That is what makes §12's "Subcapability disable
/// closes affected sessions" implementable -- flipping
/// ai_sessions_nearby_enabled off makes every subsequent command on a
/// Nearby session return FEATURE_DISABLED, while Ideas sessions in the
/// same relationship carry on.
///
/// Visibility and kind are independent axes, so both are required:
/// a shared Nearby session needs ai_sessions_shared_enabled AND
/// ai_sessions_nearby_enabled. A single combined flag could not express
/// "kill Nearby everywhere but leave shared Ideas running".
export function capabilitiesForSession(
  kind: string,
  visibility: string,
  includeWindow: boolean,
): SessionCapability[] {
  const required: SessionCapability[] = [
    visibility === "shared"
      ? "ai_sessions_shared_enabled"
      : "ai_sessions_private_enabled",
  ];
  if (kind === "nearby") required.push("ai_sessions_nearby_enabled");
  // The recent window is the one subcapability that puts the PARTNER's
  // chat text into a provider prompt, so it is gated separately and
  // only when actually requested.
  if (includeWindow) required.push("ai_sessions_recent_window_enabled");
  return required;
}

export type EligibilityResult =
  | { ok: true }
  | { ok: false; error: SessionError };

/// Spec §3.1's per-command server checks, in the order their failure
/// modes must NOT leak into each other:
///
///   1. active, unarchived relationship the ACTOR is a member of
///      -> UNAVAILABLE. A non-member, an unknown id, an ended or an
///      archived relationship are one indistinguishable response, per
///      §3.1's "Foreign, ended, expired and unauthorized session IDs
///      return the same unavailable response."
///   2. latest versioned dual processing consent -> CONSENT_REQUIRED.
///
/// MEMBERSHIP BEFORE CONSENT IS LOAD-BEARING, NOT STYLISTIC. Reversing
/// these two would tell an outsider "consent required" for a
/// relationship they are not in, confirming it exists and disclosing
/// its consent state. §10's own note on CONSENT_REQUIRED -- "caller can
/// open consent; no partner's withdrawal history" -- only makes sense
/// for a caller who is already established as a member.
///
/// THE ACTOR ID IS A PARAMETER, NOT A BODY READ. This function cannot
/// see the request body; it takes `actorId` from the caller, which
/// takes it from SessionUserContext.user.id.
///
/// §3.1's "enabled capability" check is CHECK 0 below, gated on the six
/// spec §12 flags that migration 20260953200000 seeds (defaults off).
/// It runs FIRST, before membership: a capability that is off must not
/// be a relationship-existence oracle. A caller who is not a member of
/// a relationship and a caller asking about a disabled capability would
/// otherwise be distinguishable -- UNAVAILABLE vs FEATURE_DISABLED --
/// which leaks whether the relationship exists to anyone who can name
/// an id while the feature is dark. With the flag off every caller gets
/// the same FEATURE_DISABLED regardless of membership, which is also
/// the honest answer: nothing about this relationship was consulted.
///
/// Enforced SERVER-SIDE through public.ai_capability_enabled(text),
/// which is granted to service_role only, per Ruling 3 and the
/// precedent in 20260712150000 ("the client-side gate was
/// advisory/spoofable"; its fix enforced inside the server-side RPC).
/// There is no client-readable path to this state at all: the RLS
/// policy hides the ai_% rows and the predicate is not executable by
/// `authenticated`.
///
/// One of §3.1's six checks is still NOT implemented here, deliberately:
///   - "supported client protocol": no protocol-version field,
///     negotiation or pinning exists anywhere in this repo (verified by
///     grep over supabase/ and lib/). §12's "Pin protocol versions and
///     test old clients; unknown versions cannot generate" has no
///     substrate yet. Reported as a plan gap; adding a field here that
///     nothing issues would be theatre.
///
/// "Session authorization", §3.1's sixth check, is per-command and lives
/// inside Plan B's RPCs (each resolves and authorizes its own session
/// id); it is not a precondition this gate can evaluate, since most
/// commands' session id is not known until the branch parses it.
export async function checkEligibility(
  service: SupabaseClient,
  actorId: string,
  relationshipId: string,
  requiredCapabilities: readonly SessionCapability[],
): Promise<EligibilityResult> {
  // CHECK 0 -- every capability this command needs is enabled.
  //
  // BEFORE membership, deliberately: see the contract note above. A
  // disabled capability must not be able to tell an outsider whether a
  // relationship id is real.
  //
  // ALL of the listed capabilities must be on. A shared session with a
  // recent window needs both ai_sessions_shared_enabled and
  // ai_sessions_recent_window_enabled, because §12's "Subcapability
  // disable closes affected sessions, not unrelated chat" means killing
  // the window must not require killing shared sessions wholesale.
  for (const capability of requiredCapabilities) {
    const flag = await service.rpc("ai_capability_enabled", {
      p_key: capability,
    });
    if (flag.error) {
      return { ok: false, error: sessionError("INTERNAL_ERROR") };
    }
    // Scalar RPC returns arrive as [{ <function_name>: value }] from
    // both PostgREST and pg_rls_client.ts's RpcCaller.
    const row = flag.data?.[0] as Record<string, unknown> | undefined;
    // FAILS CLOSED on anything that is not an explicit `true`: a NULL,
    // a missing row, an absent key or an unexpected shape all mean
    // disabled. The SQL predicate already COALESCEs an absent key to
    // false; this is the second half of the same rule, so a transport
    // that drops the value cannot read as enabled.
    if (row?.ai_capability_enabled !== true) {
      return { ok: false, error: sessionError("FEATURE_DISABLED") };
    }
  }

  // CHECK 1 -- membership and relationship liveness. Read through the
  // service client: Plan B's tables carry no policies, and this gate
  // must give the same answer regardless of which member asks.
  //
  // The predicate mirrors prepare_ai_session's own membership check
  // exactly (status = 'active' AND chat_archived_at IS NULL AND the
  // actor is user_a or user_b) so this gate cannot admit a request the
  // RPC would then reject with a different code.
  const relationship = await service
    .from("relationships")
    .select("id, user_a, user_b, status, chat_archived_at")
    .eq("id", relationshipId)
    .maybeSingle();

  if (relationship.error) {
    return { ok: false, error: sessionError("INTERNAL_ERROR") };
  }
  const row = relationship.data as Record<string, unknown> | null;
  if (!row) {
    return { ok: false, error: sessionError("UNAVAILABLE") };
  }
  if (row.status !== "active" || row.chat_archived_at != null) {
    return { ok: false, error: sessionError("UNAVAILABLE") };
  }
  if (row.user_a !== actorId && row.user_b !== actorId) {
    return { ok: false, error: sessionError("UNAVAILABLE") };
  }

  // CHECK 2 -- latest versioned DUAL consent, via Plan B's own
  // service_role predicate (migration 20260953180000). Reusing it rather
  // than reimplementing the policy-version comparison here is the point:
  // admit_ai_session_generation, publish_ai_session_nearby_result and
  // both read RPCs all gate on this same function, so this pre-flight
  // check cannot drift from the one the RPCs enforce.
  //
  // Plan A's get_ai_processing_consent_status is NOT usable here: it
  // derives its actor from auth.uid(), which is NULL under service_role.
  const consent = await service.rpc("ai_consent_granted_for_relationship", {
    p_relationship_id: relationshipId,
  });
  if (consent.error) {
    return { ok: false, error: sessionError("INTERNAL_ERROR") };
  }
  // A scalar RPC return arrives as [{ <function_name>: value }] from
  // both PostgREST and pg_rls_client.ts's RpcCaller -- see
  // claimProviderStart's note in _shared/attune_auth.ts.
  const consentRow = consent.data?.[0] as Record<string, unknown> | undefined;
  if (consentRow?.ai_consent_granted_for_relationship !== true) {
    return { ok: false, error: sessionError("CONSENT_REQUIRED") };
  }

  return { ok: true };
}

// ---------------------------------------------------------------------------
// Dispatch.
// ---------------------------------------------------------------------------

export interface SessionDeps {
  serviceClient?: SupabaseClient;
  /// The two provider calls, injectable for tests. THE DEFAULTS ARE THE
  /// REAL HELPERS, so production never depends on a caller remembering
  /// to supply them. Their TYPES are what carry the cross-provider
  /// isolation: callGemini takes a prompt and no location, searchMapbox
  /// takes a six-literal category and two numbers and no string. Task
  /// 7's spies substitute here.
  callGemini?: typeof callGeminiJson;
  searchMapbox?: typeof searchMapboxCategory;
  /// Injected `now` for the one request. Spec §4.2: the civil day is
  /// "computed ONCE from server time plus the displayed, validated
  /// offset", and the whole digest must describe one instant. A test
  /// pins it; production leaves it undefined and gets `new Date()`.
  now?: Date;
}

// ---------------------------------------------------------------------------
// Shared branch validation helpers.
// ---------------------------------------------------------------------------

/// The canonical lowercase hyphenated UUID form, which is what Postgres
/// renders and what `uuid` columns compare as.
const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

/// Spec §4.1: idempotency keys are "caller-owned UUID" values.
///
/// RULING 5 MAKES THIS LOAD-BEARING, not hygiene.
/// prepare_ai_session uses `p_idempotency_key` AS the new session's
/// primary key (`v_new_session := p_idempotency_key`), so a malformed
/// or colliding key is a malformed or colliding SESSION ID. Validating
/// the shape here is what keeps the RPC's `uuid` parameter from being
/// the only check -- a non-UUID would otherwise surface as a Postgres
/// cast error, which maps to a generic failure rather than the
/// INVALID_INPUT §4.1 calls for.
///
/// Case is NOT normalized. An uppercase key is rejected rather than
/// lowercased, because the caller is told to reuse the same key on
/// retry: silently folding case would make two spellings of one key
/// behave identically here while a client comparing its own stored key
/// to a returned session_id would see them differ.
export function isCanonicalUuid(value: unknown): value is string {
  return typeof value === "string" && UUID_PATTERN.test(value);
}

/// What each command branch receives. `actorId` is the ONLY identity a
/// branch is given, and it always originated in requireUser(req)'s
/// server-side verification -- Plan C's Global Constraint. `body` is the
/// validated envelope's body, for the branch's own bounded schema
/// (spec §4.1); it has already had every actor-naming field rejected, so
/// there is no identity in it for a branch to read even by mistake.
export interface BranchContext {
  readonly actorId: string;
  readonly body: Record<string, unknown>;
  readonly service: () => SupabaseClient;
  /// The single server instant for this request (see SessionDeps.now).
  readonly now: Date;
  /// The provider calls, already defaulted -- a branch never has to
  /// decide whether to fall back, so a branch cannot forget to.
  readonly callGemini: typeof callGeminiJson;
  readonly searchMapbox: typeof searchMapboxCategory;
}

// ---------------------------------------------------------------------------
// Branch: 'prepare' -- spec §3.2, §4.1.
// ---------------------------------------------------------------------------

/// Spec §4.1: "Prepare accepts conversation selector, kind, visibility,
/// optional target UUID, optional shared window selection, and a
/// validated UTC offset in minutes [-840,840]."
interface PrepareRequest {
  relationshipId: string;
  kind: "ideas" | "nearby";
  visibility: "private" | "shared";
  targetMessageId: string | null;
  includeWindow: boolean;
  utcOffsetMinutes: number;
  idempotencyKey: string;
}

export type PrepareParseResult =
  | { ok: true; request: PrepareRequest }
  | { ok: false; error: SessionError };

/// `prepare`'s own bounded schema (§4.1: "All non-generation commands
/// have separate bounded schemas"). Exported for direct testing so the
/// validation is provable without a database.
///
/// Strict unknown-field rejection, matching §4.1's rule for generate.
/// A field this branch does not understand is a client disagreeing with
/// the server about the contract, and silently ignoring it is how a
/// client comes to believe it set something it did not -- the same
/// reasoning Task 1 applied to ACTOR_NAMING_FIELDS.
export function parsePrepareRequest(
  body: Record<string, unknown>,
): PrepareParseResult {
  const allowed = new Set([
    "command",
    "relationship_id",
    "kind",
    "visibility",
    "target_message_id",
    "include_window",
    "utc_offset_minutes",
    "idempotency_key",
  ]);
  for (const key of Object.keys(body)) {
    if (!allowed.has(key)) {
      return { ok: false, error: sessionError("INVALID_INPUT") };
    }
  }

  const relationshipId = body.relationship_id;
  const kind = body.kind;
  const visibility = body.visibility;
  const idempotencyKey = body.idempotency_key;
  const includeWindowRaw = body.include_window ?? false;
  const targetRaw = body.target_message_id ?? null;
  const offsetRaw = body.utc_offset_minutes;

  if (!isCanonicalUuid(relationshipId)) {
    return { ok: false, error: sessionError("INVALID_INPUT") };
  }
  // RULING 5: the key BECOMES the session id, so an invalid key is an
  // invalid session id. Validated before anything touches the database.
  if (!isCanonicalUuid(idempotencyKey)) {
    return { ok: false, error: sessionError("INVALID_INPUT") };
  }
  if (kind !== "ideas" && kind !== "nearby") {
    return { ok: false, error: sessionError("INVALID_INPUT") };
  }
  if (visibility !== "private" && visibility !== "shared") {
    return { ok: false, error: sessionError("INVALID_INPUT") };
  }
  if (typeof includeWindowRaw !== "boolean") {
    return { ok: false, error: sessionError("INVALID_INPUT") };
  }
  if (targetRaw !== null && !isCanonicalUuid(targetRaw)) {
    return { ok: false, error: sessionError("INVALID_INPUT") };
  }
  if (!isValidUtcOffsetMinutes(offsetRaw)) {
    return { ok: false, error: sessionError("INVALID_INPUT") };
  }

  // §4.1's two shape rules, enforced here because Plan B's RPC does
  // NOT: prepare_ai_session accepts any (kind, visibility,
  // p_include_window, p_target_message_id) combination its CHECK
  // constraints allow, so these two would otherwise pass silently and
  // produce a session whose context settings contradict the spec.
  //
  //   "Private and Nearby sessions do not have recent windows"
  if (includeWindowRaw && (visibility !== "shared" || kind !== "ideas")) {
    return { ok: false, error: sessionError("INVALID_INPUT") };
  }
  //   "Nearby does not accept a target attachment"
  if (kind === "nearby" && targetRaw !== null) {
    return { ok: false, error: sessionError("INVALID_INPUT") };
  }

  return {
    ok: true,
    request: {
      relationshipId,
      kind,
      visibility,
      targetMessageId: targetRaw,
      includeWindow: includeWindowRaw,
      utcOffsetMinutes: offsetRaw,
      idempotencyKey,
    },
  };
}

/// RULING 5's non-optional half: "reuse-with-a-different-payload maps to
/// REQUEST_CONFLICT per §4.1".
///
/// Plan B's prepare_ai_session replay path checks ONLY the creator:
///
///     SELECT id INTO v_existing_session FROM ai_sessions
///       WHERE id = p_idempotency_key;
///     IF v_existing_session IS NOT NULL THEN
///       IF (SELECT creator_id ...) != p_actor_id THEN RAISE ...
///       RETURN QUERY SELECT v_existing_session, s.revision, false;
///
/// So re-sending the same key with a DIFFERENT kind, visibility,
/// relationship or target silently returns the ORIGINAL session and
/// reports created=false -- the caller believes its new payload took
/// effect. §4.1 is explicit that "Request IDs for retries bind actor,
/// operation, session and payload revision; different payload reuse
/// yields REQUEST_CONFLICT", so this check supplies the payload half
/// the RPC omits.
///
/// Checked BEFORE calling the RPC, not after: calling first and
/// comparing the result would already have run the RPC's slot-limit and
/// reclaim side effects for a request we are about to reject.
/// Whether `messageId` may be a session's target (sync audit I-3).
export async function targetIsOrdinary(
  service: SupabaseClient,
  relationshipId: string,
  messageId: string,
): Promise<boolean> {
  const { data, error } = await service
    .from("messages")
    .select(
      "id, relationship_id, content, deleted_at, is_system_notice, message_origin, media_url, media_type, game_session_id, message_analysis_skipped",
    )
    .eq("id", messageId)
    .maybeSingle();
  if (error || !data) return false;
  const row = data as Record<string, unknown>;
  return row.relationship_id === relationshipId && isOrdinaryTextRow(row);
}

async function detectPrepareKeyConflict(
  service: SupabaseClient,
  actorId: string,
  request: PrepareRequest,
): Promise<SessionError | null> {
  const existing = await service
    .from("ai_sessions")
    .select("id, relationship_id, creator_id, kind, visibility")
    .eq("id", request.idempotencyKey)
    .maybeSingle();

  if (existing.error) return sessionError("INTERNAL_ERROR");
  const row = existing.data as Record<string, unknown> | null;
  if (!row) return null; // fresh key, nothing to conflict with

  // A key belonging to ANOTHER actor is REQUEST_CONFLICT, not
  // UNAVAILABLE. The caller owns its own key space (§4.1: "caller-owned
  // UUID idempotency keys") and has demonstrably collided with
  // something; telling it so is correct and leaks nothing -- it already
  // supplied the value, and the response says nothing about whose it is
  // or what relationship it belongs to.
  if (
    row.creator_id !== actorId ||
    row.relationship_id !== request.relationshipId ||
    row.kind !== request.kind ||
    row.visibility !== request.visibility
  ) {
    return sessionError("REQUEST_CONFLICT");
  }

  // The target attachment is part of the payload too, and lives in a
  // different table. A retry that adds, drops or changes the target is
  // a different payload.
  const sources = await service
    .from("ai_session_sources")
    .select("source_message_id")
    .eq("session_id", request.idempotencyKey)
    .eq("source_role", "target");
  if (sources.error) return sessionError("INTERNAL_ERROR");
  const existingTarget =
    (sources.data as Record<string, unknown>[] | null)?.[0]
      ?.source_message_id ?? null;
  if ((existingTarget ?? null) !== request.targetMessageId) {
    return sessionError("REQUEST_CONFLICT");
  }

  return null;
}

async function handlePrepare(branch: BranchContext): Promise<Response> {
  const parsed = parsePrepareRequest(branch.body);
  if (!parsed.ok) return errorResponse(parsed.error);
  const request = parsed.request;
  const service = branch.service();

  const eligibility = await checkEligibility(
    service,
    branch.actorId,
    request.relationshipId,
    capabilitiesForSession(
      request.kind,
      request.visibility,
      request.includeWindow,
    ),
  );
  if (!eligibility.ok) return errorResponse(eligibility.error);

  const conflict = await detectPrepareKeyConflict(
    service,
    branch.actorId,
    request,
  );
  if (conflict) return errorResponse(conflict);

  // Sync audit I-3: the target is ordinary text in this relationship; the
  // RPC would otherwise copy a pause, note, notice or Assist output into
  // the model's input.
  if (
    request.targetMessageId !== null &&
    !(await targetIsOrdinary(service, request.relationshipId, request.targetMessageId))
  ) {
    return errorResponse(sessionError("INVALID_INPUT"));
  }

  // §4.2: "Optional shared window: up to six eligible messages AS OF
  // PREPARE TIME ... Persist source IDs, versions and snapshot time."
  // The §4.2 selection pipeline lives HERE (ai_session_context.ts's
  // selectSharedWindow, deterministic and tested); the RPC's job is to
  // persist WHICH messages were selected, as 'window' source rows. It
  // deliberately does not re-select in SQL -- two selection
  // implementations that must agree forever is exactly what the
  // determinism Global Constraint forbids, and §4.3's two-partner
  // digest equality depends on there being one.
  let windowMessageIds: string[] | null = null;
  if (request.includeWindow) {
    try {
      const window = await selectSharedWindow(
        service,
        request.relationshipId,
        // §4.2 item 3: the window excludes the selected target.
        request.targetMessageId,
        request.utcOffsetMinutes,
        // ONE instant for the whole request (§4.2: "computed once from
        // server time"), the same `now` every other branch uses.
        branch.now,
      );
      windowMessageIds = window.map((message) => message.messageId);
    } catch {
      return errorResponse(sessionError("INTERNAL_ERROR"));
    }
  }

  const result = await service.rpc("prepare_ai_session", {
    // THE ACTOR COMES FROM THE VERIFIED USER, never the body. `request`
    // carries no identity field at all -- parsePrepareRequest's
    // allowlist has no actor key, and the envelope validator already
    // rejected every actor-naming field before this branch ran.
    p_actor_id: branch.actorId,
    p_idempotency_key: request.idempotencyKey,
    p_relationship_id: request.relationshipId,
    p_kind: request.kind,
    p_visibility: request.visibility,
    p_target_message_id: request.targetMessageId,
    p_include_window: request.includeWindow,
    p_window_message_ids: windowMessageIds,
  });

  if (result.error) {
    // The slot limits are signalled by SQLSTATE, not by message text.
    // 20260953200200 added `USING ERRCODE = 'AT001'` to both slot-limit
    // RAISEs precisely so this mapping survives a reword of the
    // message: before it, a reword silently degraded §10's
    // SESSION_LIMIT_REACHED ("start a new session explicitly") to a
    // generic UNAVAILABLE, and the remedies differ -- a limit is the
    // caller's own other session, which it can end.
    //
    // The message-text leg is kept BELOW the code as a fallback, not as
    // the primary: a transport that drops `code` (and the pg_rls_client
    // test double was one such shape until this change taught it to
    // carry SQLSTATE) must still map correctly, and keeping it costs
    // nothing.
    //
    // MUTATION-TESTED, and the result is recorded rather than tidied
    // away: deleting EITHER leg alone survives the suite, because the
    // other maps the same refusal -- which is what a deliberately
    // redundant pair is for. Deleting BOTH is caught by two tests. The
    // code leg's own correctness is asserted directly instead, by the
    // "A3" test reading `error.code` off the RPC, and that assertion is
    // proven non-vacuous by a mutation that makes the test double drop
    // SQLSTATE (caught).
    const code = String(
      (result.error as { code?: unknown }).code ?? "",
    );
    if (code === "AT001") {
      return errorResponse(sessionError("SESSION_LIMIT_REACHED"));
    }
    const message = String(result.error.message ?? "");
    if (/already pending or active/i.test(message)) {
      return errorResponse(sessionError("SESSION_LIMIT_REACHED"));
    }
    if (/Idempotency key already used/i.test(message)) {
      // Belt-and-braces: detectPrepareKeyConflict above already covers
      // this, so reaching here means a concurrent prepare claimed the
      // key between that read and this call.
      return errorResponse(sessionError("REQUEST_CONFLICT"));
    }
    if (/Relationship unavailable/i.test(message)) {
      return errorResponse(sessionError("UNAVAILABLE"));
    }
    return errorResponse(sessionError("UNAVAILABLE"));
  }

  const row = (result.data as Record<string, unknown>[] | null)?.[0];
  if (!row) return errorResponse(sessionError("INTERNAL_ERROR"));

  // §4.1: "Preparation returns server session ID/revision." No context
  // text, no source content -- the review_context command is what
  // discloses the window, and only after its own authorization.
  return jsonResponse({
    session_id: row.session_id,
    revision: row.revision,
    created: row.created,
  });
}

// ---------------------------------------------------------------------------
// Branch: 'review_context' -- spec §4.2, §4.3.
// ---------------------------------------------------------------------------

/// Read-only. It does NOT call approve_ai_session_context: §4.3 says
/// "The client submits revision/digest, not replacement content", so the
/// client reviews here, then a separate `approve` command (Task 3)
/// submits the revision/digest pair it received. Keeping them separate
/// is what makes the two partners' approvals independent acts.
async function handleReviewContext(branch: BranchContext): Promise<Response> {
  // §4.1's bounded schema for this command, plus §4.3's optional window
  // toggle (Item A1 / Ruling 17). `set_include_window` is OPTIONAL: when
  // absent this command is purely read-only, exactly as it was before.
  // See applyWindowToggle's header for why the toggle rides here rather
  // than being a tenth command.
  const allowed = new Set([
    "command",
    "session_id",
    "utc_offset_minutes",
    "set_include_window",
  ]);
  for (const key of Object.keys(branch.body)) {
    if (!allowed.has(key)) {
      return errorResponse(sessionError("INVALID_INPUT"));
    }
  }
  const sessionId = branch.body.session_id;
  const offset = branch.body.utc_offset_minutes;
  const setIncludeWindow = branch.body.set_include_window;
  if (setIncludeWindow !== undefined && typeof setIncludeWindow !== "boolean") {
    return errorResponse(sessionError("INVALID_INPUT"));
  }
  if (!isCanonicalUuid(sessionId)) {
    return errorResponse(sessionError("INVALID_INPUT"));
  }
  if (!isValidUtcOffsetMinutes(offset)) {
    return errorResponse(sessionError("INVALID_INPUT"));
  }

  const service = branch.service();

  // THE SESSION IS LOOKED UP FIRST, and the relationship id, kind,
  // visibility and window setting all come from that ROW -- never from
  // the request body.
  //
  // The brief's sketched version passed `body.relationship_id` and a
  // hardcoded kind "ideas" / visibility "shared" into the digest, and
  // flagged that as an unresolved gap. It is resolved here, and the
  // reason it had to be is not merely tidiness: §4.3's digest binds
  // "kind and visibility", and Plan B's activate_ai_session compares
  // digests for equality. A digest computed from a client-supplied
  // relationship or a constant kind would (a) let a caller aim the
  // window query at a relationship the session does not belong to, and
  // (b) make every session's digest agree on kind/visibility whatever
  // the session actually is -- so a shared Nearby session and a shared
  // Ideas session over the same day would be indistinguishable to the
  // approval check.
  const session = await service
    .from("ai_sessions")
    .select(
      "id, relationship_id, creator_id, kind, visibility, state, revision, context_revision, preparation_deadline, include_window",
    )
    .eq("id", sessionId)
    .maybeSingle();
  if (session.error) return errorResponse(sessionError("INTERNAL_ERROR"));
  const row = session.data as Record<string, unknown> | null;
  // §3.1: "Foreign, ended, expired and unauthorized session IDs return
  // the same unavailable response." An unknown id is indistinguishable
  // from one belonging to someone else.
  if (!row) return errorResponse(sessionError("UNAVAILABLE"));

  const relationshipId = row.relationship_id as string;
  const kind = row.kind as string;
  const visibility = row.visibility as string;

  // Whether this session has a window is a property of the SESSION, read
  // from the STORED setting -- never inferred from kind/visibility.
  //
  // 20260953200200 (Item A) is what made this readable: before it,
  // prepare_ai_session accepted `p_include_window` and ignored it, so
  // this branch had to treat every shared Ideas session as windowed and
  // compute live. §4.3: "Window is default off" -- and a shared Ideas
  // session that the user left the window OFF for must get an EMPTY
  // window here, not the whole civil day, or the digest both partners
  // approve would bind context the requester never switched on.
  //
  // The `&& shared && ideas` conjunction is belt-and-braces: the
  // ai_sessions_window_only_shared_ideas CHECK already makes a private
  // or Nearby session with include_window true unstorable, so this can
  // only ever narrow, never widen.
  const includeWindow = row.include_window === true &&
    visibility === "shared" && kind === "ideas";

  const eligibility = await checkEligibility(
    service,
    branch.actorId,
    relationshipId,
    capabilitiesForSession(kind, visibility, includeWindow),
  );
  if (!eligibility.ok) return errorResponse(eligibility.error);

  // §5.1: "Server read-time expiry is authoritative even before
  // cleanup." A session past its preparation deadline is not
  // reviewable, and §3.1 makes expired indistinguishable from foreign.
  if (row.state !== "preparing") {
    return errorResponse(sessionError("UNAVAILABLE"));
  }
  const deadline = new Date(row.preparation_deadline as string);
  if (!(deadline.getTime() > branch.now.getTime())) {
    return errorResponse(sessionError("UNAVAILABLE"));
  }

  // Both current members, resolved SERVER-SIDE from the relationship
  // (§3.1: "resolve its relationship and both current members
  // server-side"). These are the digest's "participants".
  const relationship = await service
    .from("relationships")
    .select("user_a, user_b")
    .eq("id", relationshipId)
    .maybeSingle();
  if (relationship.error) return errorResponse(sessionError("INTERNAL_ERROR"));
  const relRow = relationship.data as Record<string, unknown> | null;
  if (!relRow) return errorResponse(sessionError("UNAVAILABLE"));
  const participants = [relRow.user_a, relRow.user_b]
    .filter((id): id is string => typeof id === "string");

  // The frozen target, if prepare attached one. Read from
  // ai_session_sources rather than recomputed, because §4.2 requires
  // "Persist source IDs, versions and snapshot time, not new selections
  // on subsequent turns" -- the target was fixed at prepare time and
  // must not be re-derived here.
  const targetRows = await service
    .from("ai_session_sources")
    .select("source_message_id, source_version, approved_clipped_text")
    .eq("session_id", sessionId)
    .eq("source_role", "target");
  if (targetRows.error) return errorResponse(sessionError("INTERNAL_ERROR"));
  const target =
    (targetRows.data as Record<string, unknown>[] | null)?.[0] ?? null;
  const targetMessageId = (target?.source_message_id as string) ?? null;

  // §4.3's WINDOW TOGGLE, if this call asked for one (Item A1 / Ruling
  // 17). It runs HERE -- after the session, membership, state, expiry
  // and the frozen target are all established, and BEFORE the digest is
  // computed -- for two reasons:
  //
  //   * the toggle needs the frozen TARGET id, because §4.2 item 3
  //     excludes the target from the window, and the target is read
  //     from the stored row just above;
  //   * the digest must be computed over the state the toggle LEFT
  //     behind, not the state it found. The toggle bumps the revision
  //     and clears approvals, so a digest computed before it would bind
  //     a revision the client could never approve at.
  //
  // The session row is therefore RE-READ below for the revision and the
  // window setting the toggle produced.
  let effectiveIncludeWindow = includeWindow;
  let effectiveRevision = row.revision as number;
  if (setIncludeWindow !== undefined) {
    const toggleError = await applyWindowToggle(
      branch,
      service,
      sessionId,
      relationshipId,
      targetMessageId,
      offset,
      setIncludeWindow,
    );
    if (toggleError) return errorResponse(toggleError);
    // RE-READ, never assumed: a no-change call bumps nothing, and the
    // RPC is the authority on what the row now holds. Computing the
    // digest from an assumed revision is how two partners end up
    // approving different integers.
    const after = await service
      .from("ai_sessions")
      .select("revision, include_window, kind, visibility")
      .eq("id", sessionId)
      .maybeSingle();
    if (after.error) return errorResponse(sessionError("INTERNAL_ERROR"));
    const afterRow = after.data as Record<string, unknown> | null;
    if (!afterRow) return errorResponse(sessionError("UNAVAILABLE"));
    effectiveRevision = afterRow.revision as number;
    effectiveIncludeWindow = afterRow.include_window === true &&
      afterRow.visibility === "shared" && afterRow.kind === "ideas";
  }

  let window: WindowMessage[] = [];
  if (effectiveIncludeWindow) {
    try {
      window = await selectSharedWindow(
        service,
        relationshipId,
        // §4.2 item 3: the window excludes the selected target.
        targetMessageId,
        offset,
        // ONE instant for the whole request (§4.2: "computed once from
        // server time").
        branch.now,
      );
    } catch {
      return errorResponse(sessionError("INTERNAL_ERROR"));
    }
  }

  // The digest's sources are the TARGET plus the window, in that order.
  // The target comes first because it is the message the user selected
  // and §4.2 lists it before the window; the order is fixed either way,
  // which is what matters -- both partners build it the same.
  const sources: { messageId: string; sourceVersion: string }[] = [];
  const displayedSnippets: string[] = [];
  if (target) {
    // CANONICALIZED, never hashed verbatim. The stored timestamptz
    // reaches this code in whichever form the transport chose, and I
    // measured three:
    //
    //   PostgREST JSON          "2026-10-10T23:17:30.222456+00:00" (µs)
    //   pg_rls_client .from()   "2026-10-10T23:17:30.222Z"         (ms)
    //   pg_rls_client raw query  a JS Date object
    //
    // Hashing any of them verbatim would bind the TRANSPORT rather than
    // the value, so two partners whose requests took different paths
    // would compute different digests and the shared session could
    // never activate.
    //
    // HONEST SCOPE NOTE: on the two paths this branch actually runs on
    // (PostgREST in production, .from() under the test double) the value
    // arrives as a STRING, so String() here would be a no-op and a
    // mutation reintroducing it does NOT fail the suite. The
    // canonicalization still earns its place -- it collapses the
    // microsecond and millisecond spellings above, which DO differ and
    // which the reproducibility test does catch -- and
    // canonicalTimestamp's Date branch covers the raw-query path, where
    // String() silently drops the milliseconds. Recorded rather than
    // papered over with a test that could not fail.
    const targetVersion = canonicalTimestamp(target.source_version);
    if (targetVersion === null) {
      return errorResponse(sessionError("INTERNAL_ERROR"));
    }
    sources.push({
      messageId: target.source_message_id as string,
      sourceVersion: targetVersion,
    });
    displayedSnippets.push(String(target.approved_clipped_text));
  }
  for (const message of window) {
    sources.push({
      messageId: message.messageId,
      sourceVersion: message.sourceVersion,
    });
    displayedSnippets.push(message.content);
  }

  if (window.length > WINDOW_ROW_CAP) {
    // Unreachable -- selectWindowFromRows caps it -- kept so a future
    // change to the cap fails closed rather than over-disclosing.
    return errorResponse(sessionError("CONTEXT_TOO_LARGE"));
  }

  const policyVersion = await service.rpc(
    "ai_current_consent_policy_version",
    {},
  );
  if (policyVersion.error) {
    return errorResponse(sessionError("INTERNAL_ERROR"));
  }
  const policyRow = policyVersion.data?.[0] as
    | Record<string, unknown>
    | undefined;
  const policy = policyRow?.ai_current_consent_policy_version;
  if (typeof policy !== "string") {
    // §4.3 binds "policy version" into the digest, so a missing one
    // cannot be defaulted -- two callers defaulting differently is the
    // exact failure mode.
    return errorResponse(sessionError("INTERNAL_ERROR"));
  }

  const civilDayStart = civilDayStartUtc(branch.now, offset).toISOString();

  const digest = await computeApprovalDigest({
    sessionId,
    policyVersion: policy,
    kind,
    visibility,
    participants,
    sources,
    displayedSnippets,
    // No offset or civil-day start is passed: Ruling 35 (N3) removed
    // them from the pre-image, because the offset is a selection input
    // and the selected rows above already encode its effect. The offset
    // still decides WHICH rows these are -- civilDayStart below is
    // still computed from it and still echoed to the client -- it just
    // is not hashed, so two partners in different timezones can agree.
    // See ApprovalDigestInput in _shared/ai_session_context.ts.
    // §4.3: approvals are stored against a separate context_revision,
    // "frozen at activation". In preparing state the session's own
    // `revision` is what an approval is submitted against (Plan B's
    // approve_ai_session_context takes p_revision and matches
    // ai_sessions.revision), so that is what the digest binds.
    //
    // THE EFFECTIVE revision, i.e. after any window toggle this call
    // performed. A toggle bumps it, so binding the pre-toggle value
    // would hand the client a digest it could only submit against a
    // revision that no longer exists.
    contextRevision: effectiveRevision,
  });

  // §4.3: "The client submits revision/digest." Both are returned so
  // the client can echo them to `approve` without recomputing either.
  return jsonResponse({
    session_id: sessionId,
    revision: effectiveRevision,
    policy_version: policy,
    kind,
    visibility,
    // The STORED setting the digest was computed under, so a client can
    // see whether its toggle took effect without a second read.
    include_window: effectiveIncludeWindow,
    utc_offset_minutes: offset,
    civil_day_start_utc: civilDayStart,
    window: window.map((message) => ({
      content: message.content,
      truncated: message.truncated,
    })),
    target: target
      ? { content: String(target.approved_clipped_text) }
      : null,
    digest,
  });
}

// ---------------------------------------------------------------------------
// Branch: 'generate' -- output validation. Spec §5.3, §8.2.5.
//
// Extends ai-assist/index.ts's validateIdeasOutput pattern with the
// `kind` discriminant §5.3 requires, the eight-token quotation check and
// the prohibited-pattern scan §8.2.5 requires across ALL output fields.
// ---------------------------------------------------------------------------

export interface SessionAnswerOutput {
  kind: "answer";
  reply_text: string;
  suggested_planning_item: {
    kind: "task" | "event";
    title: string;
    event_date: string | null;
  } | null;
}

export interface SessionRedirectOutput {
  kind: "redirect";
  reason: "unsupported" | "unsafe_to_assist" | "insufficient_context";
  offered: ("ideas" | "nearby")[];
}

export type SessionTurnOutput = SessionAnswerOutput | SessionRedirectOutput;

const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;

/// §5.3: "event_date null or REAL ISO calendar date." DATE_RE alone
/// accepts 2026-02-30 and 2026-13-01, which are not dates -- and this
/// string is handed to Planning, so a non-date is a defect that travels.
/// Round-tripping through Date and comparing components is what proves
/// the day exists in that month of that year.
function isRealCalendarDate(value: string): boolean {
  if (!DATE_RE.test(value)) return false;
  const [year, month, day] = value.split("-").map(Number);
  const parsed = new Date(Date.UTC(year, month - 1, day));
  return parsed.getUTCFullYear() === year &&
    parsed.getUTCMonth() === month - 1 &&
    parsed.getUTCDate() === day;
}

/// Rejects NUL and unpaired surrogates. §4.1 rejects these on input;
/// the same values on OUTPUT would be a Postgres error at commit time
/// (text columns forbid NUL) or invalid UTF-8 on the wire, so the
/// validator is where they stop rather than the storage layer.
function hasForbiddenCodeUnits(value: string): boolean {
  if (value.includes("\u0000")) return true;
  for (let i = 0; i < value.length; i++) {
    const unit = value.charCodeAt(i);
    if (unit >= 0xd800 && unit <= 0xdbff) {
      const next = value.charCodeAt(i + 1);
      if (!(next >= 0xdc00 && next <= 0xdfff)) return true;
      i++;
    } else if (unit >= 0xdc00 && unit <= 0xdfff) {
      return true;
    }
  }
  return false;
}

/// §8.2.5's eight-token threshold. EIGHT, not nine: "eight-token copied
/// spans" are what the check rejects, so a span of exactly eight words
/// is refused and seven is allowed. Both legs are asserted.
const QUOTED_SPAN_WORDS = 8;

/// Splits into comparable word tokens: lowercased, with everything that
/// is not a letter, a digit or an intra-word apostrophe collapsed to a
/// separator.
///
/// WHY NOT `split(/\s+/)`, which is what the task brief sketched: §8.2.5's
/// own regression fixture is a chat MESSAGE, and chat messages carry
/// punctuation. A whitespace split leaves "brainstorm." and "brainstorm"
/// as different tokens, so a model reproducing the span WITH its
/// original punctuation -- the likeliest form of a verbatim copy --
/// would not match it. The test "punctuation- and case-insensitive"
/// fails on the whitespace-split version.
function quotationTokens(value: string): string[] {
  return value
    .toLowerCase()
    .replace(/[^\p{L}\p{N}']+/gu, " ")
    .split(" ")
    .filter((token) => token.length > 0);
}

/// §8.2.5: "Mechanical checks reject direct source quotations/eight-token
/// copied spans ... across ALL output fields; benign overlap may refuse."
///
/// ONE SYMMETRIC SCAN, not the brief's two directions, and the reason is
/// a measured finding rather than a preference. The brief sketched a
/// forward pass (a source span found inside the candidate) PLUS a
/// reverse pass (a candidate span found inside a source), on the stated
/// grounds that the reverse catches the model restating its own prior
/// answer out of SESSION_HISTORY -- which §8.2.5 does name explicitly
/// ("Model answers are also untrusted in later history").
///
/// But the reverse pass is only non-redundant in the brief's version
/// because that version compared a tokenized span against a RAW
/// `.includes()` on the untokenized other side, so each direction
/// normalized a different operand. Once both sides are tokenized the
/// same way, the two directions are the SAME predicate -- "do the two
/// token streams share an 8-gram?" -- which is symmetric by
/// construction, and I verified it over 200,000 random token-stream
/// pairs before deleting the second loop. So the §8.2.5 case the brief
/// wanted the reverse pass for IS covered, by the single scan.
///
/// Recorded rather than silently simplified, because a reviewer reading
/// the brief will look for the second loop. The test
/// "catches the model restating its OWN prior answer" is the leg that
/// pins the behaviour the brief was protecting.
export function containsQuotedSpan(
  candidate: string,
  sources: readonly string[],
): boolean {
  const candidateTokens = quotationTokens(candidate);
  if (candidateTokens.length < QUOTED_SPAN_WORDS) {
    // A candidate shorter than the threshold cannot contain an
    // eight-token span, in either direction.
    return false;
  }
  const candidateSpans = new Set<string>();
  for (
    let i = 0;
    i + QUOTED_SPAN_WORDS <= candidateTokens.length;
    i++
  ) {
    candidateSpans.add(
      candidateTokens.slice(i, i + QUOTED_SPAN_WORDS).join(" "),
    );
  }

  for (const source of sources) {
    const sourceTokens = quotationTokens(source);
    for (
      let i = 0;
      i + QUOTED_SPAN_WORDS <= sourceTokens.length;
      i++
    ) {
      if (
        candidateSpans.has(
          sourceTokens.slice(i, i + QUOTED_SPAN_WORDS).join(" "),
        )
      ) {
        return true;
      }
    }
  }
  return false;
}

/// §8.2.5's "prohibited output patterns", applied HERE as well as inside
/// callGeminiJson.
///
/// NOT BELT-AND-BRACES: callGeminiJson applies STATIC_PROHIBITED_PATTERNS
/// to the raw provider response, but this validator is also the boundary
/// a test double's output and any future provider helper cross, and
/// §8.2.5 asks for the check "across ALL output fields" of the VALIDATED
/// shape. Running it here means the property holds for whatever produced
/// the object, not only for the one code path that happens to call
/// Gemini today.
function violatesProhibitedPattern(value: string): boolean {
  return STATIC_PROHIBITED_PATTERNS.some((pattern) => pattern.test(value));
}

/// Every check that applies to EVERY free-text output field, in one
/// place so a new field cannot be added with only some of them.
/// §8.2.5: "Output checks cover prose, proposals and source display
/// strings."
function isAcceptableOutputText(
  value: string,
  maxScalars: number,
  quotedSources: readonly string[],
): boolean {
  // Unicode SCALARS, not UTF-16 units (§4.1's counting rule). 1000
  // astral emoji are 1000 scalars and 2000 `.length` units, so a
  // `.length` cap would refuse a legal answer.
  const length = scalarLength(value);
  if (length < 1 || length > maxScalars) return false;
  if (hasForbiddenCodeUnits(value)) return false;
  if (violatesProhibitedPattern(value)) return false;
  if (containsQuotedSpan(value, quotedSources)) return false;
  return true;
}

/// Extends ai-assist/index.ts's validateIdeasOutput pattern with the
/// `kind` discriminant (spec §5.3) and §8.2.5's mechanical checks.
/// Returns null -- never a best-effort partial parse -- for anything
/// that does not match §5.3 exactly.
///
/// `quotedSources` is every string this request's own SESSION_HISTORY
/// and CONTEXT_WINDOW content contained. THE CALLER MUST PASS THE SAME
/// STRINGS THAT WERE ACTUALLY SENT TO THE MODEL, never a different or
/// stale set -- which is why the `generate` branch builds both from one
/// `SessionPromptInputs` value and derives this list from that same
/// value (see collectQuotedSources). A list assembled separately could
/// drift from the prompt and make the check vacuous.
///
/// `kind: "redirect"` is the MODEL's redirect -- an ordinary unsupported
/// request, which §5.3 says "become[s] [a] transcript pair". It is NOT
/// the shape a SAFETY refusal takes: safety refusals never reach this
/// function, because the safety gate runs before dispatch and its
/// verdict comes from classifySessionContent, whose copy is frozen
/// server-side. See handleGenerate.
export function validateSessionTurnOutput(
  parsed: unknown,
  quotedSources: readonly string[] = [],
): SessionTurnOutput | null {
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
    return null;
  }
  const record = parsed as Record<string, unknown>;
  const kind = record.kind;

  if (kind === "redirect") {
    // §5.3: a redirect carries "no model-written fallback advice,
    // sources or proposal", so the key set is exactly these three and a
    // proposal field is a rejection rather than an ignored extra.
    const allowedKeys = new Set(["kind", "reason", "offered"]);
    for (const key of Object.keys(record)) {
      if (!allowedKeys.has(key)) return null;
    }
    const reason = record.reason;
    if (
      reason !== "unsupported" && reason !== "unsafe_to_assist" &&
      reason !== "insufficient_context"
    ) {
      return null;
    }
    const offered = record.offered;
    if (
      !Array.isArray(offered) ||
      !offered.every((entry) => entry === "ideas" || entry === "nearby")
    ) {
      return null;
    }
    return {
      kind: "redirect",
      reason,
      offered: offered as ("ideas" | "nearby")[],
    };
  }

  if (kind !== "answer") return null;
  const allowedKeys = new Set(["kind", "reply_text", "suggested_planning_item"]);
  for (const key of Object.keys(record)) {
    if (!allowedKeys.has(key)) return null;
  }

  const replyText = record.reply_text;
  if (typeof replyText !== "string") return null;
  const trimmedReply = replyText.trim();
  // §5.3: "reply_text 1..2,000 scalars".
  if (!isAcceptableOutputText(trimmedReply, 2000, quotedSources)) return null;

  const rawItem = record.suggested_planning_item;
  let suggestedItem: SessionAnswerOutput["suggested_planning_item"] = null;
  if (rawItem !== null && rawItem !== undefined) {
    if (typeof rawItem !== "object" || Array.isArray(rawItem)) return null;
    const itemRecord = rawItem as Record<string, unknown>;
    const allowedItemKeys = new Set(["kind", "title", "event_date"]);
    for (const key of Object.keys(itemRecord)) {
      if (!allowedItemKeys.has(key)) return null;
    }
    const itemKind = itemRecord.kind;
    // §5.3: "kind task/event" only -- no Goal, no Note.
    if (itemKind !== "task" && itemKind !== "event") return null;
    const title = itemRecord.title;
    if (typeof title !== "string") return null;
    const trimmedTitle = title.trim();
    // §5.3: "title 1..120". The SAME field checks as reply_text, which
    // is what §8.2.5's "across ALL output fields" means -- its second
    // fixture asks the model to put a copied secret in exactly here.
    if (!isAcceptableOutputText(trimmedTitle, 120, quotedSources)) return null;
    const eventDate = itemRecord.event_date;
    // §5.3: "Task date null; event proposal date required."
    if (itemKind === "event") {
      if (typeof eventDate !== "string" || !isRealCalendarDate(eventDate)) {
        return null;
      }
    } else if (eventDate !== null && eventDate !== undefined) {
      return null;
    }
    suggestedItem = {
      kind: itemKind,
      title: trimmedTitle,
      event_date: itemKind === "event" ? (eventDate as string) : null,
    };
  }

  return {
    kind: "answer",
    reply_text: trimmedReply,
    suggested_planning_item: suggestedItem,
  };
}

// ---------------------------------------------------------------------------
// Branch: 'generate' -- spec §4.1, §4.3, §5.2, §5.3, §6.2, §8.1, §8.2.5.
// The ONLY branch in this function that calls a provider.
// ===========================================================================
// THE CROSS-PROVIDER ISOLATION IS STRUCTURAL, NOT DISCIPLINARY.
//
// Plan B's own review flagged spec §2's "Mapbox response text never
// re-enters Gemini" as the highest-risk data-flow claim in the whole
// spec. A comment saying "do not do that" is not a defence against a
// refactor. Four properties below make the path NOT EXIST, so that
// creating it requires a visible, reviewable change rather than an
// accidental one. Each is listed with what breaks if someone tries.
//
//  (1) THE PROMPT BUILDER TAKES A NOMINAL TYPE NOTHING MAPBOX-DERIVED
//      CAN INHABIT. buildSessionUserPrompt accepts only
//      PromptApprovedText values -- a branded string whose brand symbol
//      is module-private, so the ONLY way to obtain one is the two
//      minting functions below, each of which names its provenance
//      (approvedSourceText, priorSessionTurnText). PlaceSource.name and
//      PlaceSource.formatted_address are plain `string`, so
//      `promptApprovedText(place.name)` does not type-check and
//      `{{CONTEXT_WINDOW_JSON}}` cannot be fed a place. A refactor that
//      wanted to would have to add a third minting function or cast,
//      both of which a reviewer sees.
//
//  (2) THE PROMPT BUILDER HAS NO DATABASE CLIENT AND IS PURE.
//      Mapbox results live in public.ai_session_staging (written by
//      stage_ai_session_nearby_result) and in 'nearby_result' turn
//      payloads. buildSessionUserPrompt takes no SupabaseClient and
//      performs no IO, so it cannot read either table. It cannot
//      reach a Mapbox value even if one is persisted.
//
//  (3) THE HISTORY LOADER FILTERS BY TURN KIND AT THE SOURCE, AND
//      PROJECTS ONLY TWO FIELDS. loadPriorIdeasTurns keeps only
//      kind='ideas_answer' rows and reads only payload.instruction and
//      payload.reply_text. A 'nearby_result' turn is dropped before any
//      field is read, which is also §2's own rule: "No Nearby
//      transcript, place result, source payload or derived summary
//      becomes later model history, EVEN WITHIN THE SAME NEARBY
//      SESSION." The filter is in the SQL predicate, not a post-filter
//      a mapping could forget.
//
//  (4) NEARBY'S TWO PROVIDER CALLS NEVER SHARE A VALUE IN EITHER
//      DIRECTION, because their parameter and return types are
//      disjoint. selectNearbyCategory takes PromptApprovedText and
//      returns a NearbyCategory (one of six literals);
//      searchMapboxCategory (now in _shared/mapbox_search.ts) takes a
//      NearbyCategory plus two numbers and returns PlaceSource[]. The
//      only value crossing between them is the allowlisted category
//      token, which §2 permits by name, and the coordinates never enter
//      the Gemini side because the struct the prompt is built from has
//      no location field at all.
//
// Task 7's spy tests prove this on the live call graph. The properties
// above are why those tests should pass rather than how they are made
// to.
// ===========================================================================

/// The brand. Module-private, so no other file and no other function in
/// this file can forge a PromptApprovedText -- `as PromptApprovedText`
/// is the only escape and it is grep-able.
declare const promptApprovedBrand: unique symbol;

/// A string whose PROVENANCE is attested: it came from an approved
/// context source or from a prior committed Ideas turn of this same
/// session, and is therefore eligible to be placed inside a provider
/// prompt. See property (1) above.
export type PromptApprovedText = string & {
  readonly [promptApprovedBrand]: true;
};

/// Mints a PromptApprovedText from an APPROVED CONTEXT SOURCE -- a row
/// of ai_session_sources that both partners' digests were computed
/// over. The caller must have read it from that table; the name is the
/// attestation, and it is the reason this is a function rather than a
/// cast at the use site.
function approvedSourceText(text: string): PromptApprovedText {
  return text as PromptApprovedText;
}

/// FOR TESTS ONLY, and named so a call site is self-indicting.
///
/// Why it exists at all: the brand's whole point is that there is no
/// way to make a PromptApprovedText except from an attested
/// provenance, which is also true for a test that wants to measure
/// buildSessionUserPrompt's output size over synthetic content. The
/// alternatives were worse -- an inline `as PromptApprovedText` in the
/// test file, which is the exact cast review is supposed to catch, or
/// weakening the brand, which would delete the property.
///
/// Exporting it does NOT weaken the isolation. The negative compile
/// probe in isolation_probes/ asserts that place names, addresses and
/// serialized PlaceSource payloads cannot be passed to
/// buildSessionUserPrompt WITHOUT a mint, and the three minting
/// functions are the only ones that exist. A refactor threading Mapbox
/// text through THIS function is naming it `unsafeTestOnly...` in
/// production code, which is as loud as a cast and greppable.
export function unsafeTestOnlyPromptText(text: string): PromptApprovedText {
  return text as PromptApprovedText;
}

/// Mints a PromptApprovedText from a PRIOR COMMITTED IDEAS TURN of this
/// same session (§4.2 item 4). Separate from approvedSourceText so the
/// two provenances are distinguishable at every call site, and so a
/// future reviewer can see exactly which of the two a given prompt
/// field drew from.
function priorSessionTurnText(text: string): PromptApprovedText {
  return text as PromptApprovedText;
}

/// Everything that may be placed in a provider prompt, and nothing
/// else. §4.2's four inputs, with no location field: spec §2's
/// "automatically collected coordinates never reach Gemini" is enforced
/// by this type having nowhere to put them, so the Nearby path cannot
/// leak a point into a prompt even by passing the whole request struct.
export interface SessionPromptInputs {
  /// §4.2 item 1: "Current instruction: at most 300 scalar values,
  /// never dropped." NOT branded: it is the requester's own live text,
  /// a third provenance, and §4.1 bounds it separately.
  readonly userInstruction: string;
  /// §4.2 item 4: prior committed Ideas pairs of THIS session only.
  readonly history: readonly {
    readonly role: "user" | "attune";
    readonly content: PromptApprovedText;
  }[];
  /// §4.2 items 2-3: the frozen target and window snippets, in the
  /// order review_context displayed them.
  readonly contextWindow: readonly PromptApprovedText[];
}

/// PURE. No SupabaseClient, no IO, no Date, no randomness -- see
/// property (2). Exported so Task 7 can call it directly and assert
/// over its output without standing up a session.
export function buildSessionUserPrompt(
  template: string,
  assistKind: "ideas" | "nearby",
  inputs: SessionPromptInputs,
): string {
  return template
    .replaceAll("{{ASSIST_KIND}}", assistKind.toUpperCase())
    .replaceAll(
      "{{SESSION_HISTORY_JSON}}",
      JSON.stringify(
        inputs.history.map((turn) => ({
          role: turn.role,
          content: String(turn.content),
        })),
      ),
    )
    .replaceAll(
      "{{CONTEXT_WINDOW_JSON}}",
      JSON.stringify(inputs.contextWindow.map((snippet) => String(snippet))),
    )
    .replaceAll("{{USER_INSTRUCTION}}", inputs.userInstruction);
}

/// Every string this request's prompt actually contained, for
/// validateSessionTurnOutput's §8.2.5 quotation check.
///
/// DERIVED FROM THE SAME VALUE the prompt was built from, deliberately:
/// a list assembled by a second query could drift from what was sent
/// and make the check vacuous -- it would pass because it was scanning
/// the wrong strings, which is the exact failure mode this plan's
/// history keeps finding. The instruction is included because §8.2.5's
/// own fixture is authored BY the requester ("Both are untrusted data
/// even when authored by the requester").
export function collectQuotedSources(
  inputs: SessionPromptInputs,
): string[] {
  return [
    inputs.userInstruction,
    ...inputs.history.map((turn) => String(turn.content)),
    ...inputs.contextWindow.map((snippet) => String(snippet)),
  ];
}

/// The prompt version identifier. §12: "Pin protocol versions"; §8.1's
/// audit story needs to say WHICH prompt produced a turn.
///
/// PINNED IN THREE PLACES THAT MUST AGREE, and a test asserts all
/// three: this constant, the `prompts/v1/` directory the files are read
/// from (via import.meta.url, so the bundler ships them beside the
/// function), and the `promptId` passed to callGeminiJson, which is
/// what reaches the provider-call log line. Bumping the prompt text
/// without bumping this constant is therefore a test failure, not a
/// silent change -- the test hashes both prompt files and asserts the
/// digest, so ANY edit to either file fails until the version moves.
export const SESSION_PROMPT_VERSION = "ai_sessions_v1";

let cachedSystemPrompt: string | null = null;
let cachedUserTemplate: string | null = null;

/// Loaded relative to import.meta.url so the versioned templates are
/// packaged with the function, matching ai-assist's loadPrompts.
export async function loadSessionPrompts(): Promise<
  { system: string; userTemplate: string }
> {
  if (cachedSystemPrompt === null) {
    cachedSystemPrompt = await Deno.readTextFile(
      new URL("./prompts/v1/system.txt", import.meta.url),
    );
  }
  if (cachedUserTemplate === null) {
    cachedUserTemplate = await Deno.readTextFile(
      new URL("./prompts/v1/user.txt", import.meta.url),
    );
  }
  return { system: cachedSystemPrompt, userTemplate: cachedUserTemplate };
}

// ---------------------------------------------------------------------------
// 'generate' request parsing -- spec §4.1's generation schema, verbatim.
// ---------------------------------------------------------------------------

interface RequesterLocation {
  latitude: number;
  longitude: number;
  accuracyM: number;
  capturedAt: string;
}

interface GenerateRequest {
  sessionId: string;
  requestId: string;
  expectedRevision: number;
  userInstruction: string;
  /// Nearby only. KEPT OUT of SessionPromptInputs by construction --
  /// see property (1).
  requesterLocation: RequesterLocation | null;
}

export type GenerateParseResult =
  | { ok: true; request: GenerateRequest }
  | { ok: false; error: SessionError };

/// §4.1's "strict unknown-field rejection" over the generation schema.
/// Exported for direct testing, so every bound is provable without a
/// database.
///
/// WHAT IS DELIBERATELY ABSENT, because §4.1 forbids supplying it:
/// visibility, kind, consent version, prior turns, context text,
/// relationship ID, output content and author identity. Each would be
/// rejected by the allowlist below, and the actor-naming ones were
/// already rejected by validateCommandEnvelope before this ran.
export function parseGenerateRequest(
  body: Record<string, unknown>,
): GenerateParseResult {
  const allowed = new Set([
    "command",
    "session_id",
    "request_id",
    "expected_revision",
    "user_instruction",
    "requester_location",
  ]);
  for (const key of Object.keys(body)) {
    if (!allowed.has(key)) {
      return { ok: false, error: sessionError("INVALID_INPUT") };
    }
  }

  const sessionId = body.session_id;
  const requestId = body.request_id;
  const expectedRevision = body.expected_revision;
  const userInstruction = body.user_instruction;

  if (!isCanonicalUuid(sessionId) || !isCanonicalUuid(requestId)) {
    return { ok: false, error: sessionError("INVALID_INPUT") };
  }
  // §4.1: "expected_revision: number; // positive integer".
  if (
    typeof expectedRevision !== "number" ||
    !Number.isInteger(expectedRevision) || expectedRevision < 1
  ) {
    return { ok: false, error: sessionError("INVALID_INPUT") };
  }
  if (typeof userInstruction !== "string") {
    return { ok: false, error: sessionError("INVALID_INPUT") };
  }
  // §4.1: "Reject unpaired surrogates, NUL and invalid JSON". Checked
  // BEFORE trimming, because trim() does not remove either.
  if (hasForbiddenCodeUnits(userInstruction)) {
    return { ok: false, error: sessionError("INVALID_INPUT") };
  }
  const trimmedInstruction = userInstruction.trim();
  // §4.1: "1..300 Unicode scalar values AFTER TRIM" -- scalars, not
  // UTF-16 units, so 200 astral emoji is a legal instruction.
  const instructionLength = scalarLength(trimmedInstruction);
  if (instructionLength < 1 || instructionLength > 300) {
    return { ok: false, error: sessionError("INVALID_INPUT") };
  }

  let requesterLocation: RequesterLocation | null = null;
  const rawLocation = body.requester_location;
  if (rawLocation !== null && rawLocation !== undefined) {
    if (typeof rawLocation !== "object" || Array.isArray(rawLocation)) {
      return { ok: false, error: sessionError("INVALID_INPUT") };
    }
    const locationRecord = rawLocation as Record<string, unknown>;
    // confirmation_nonce is in §4.1's schema but has NO SUBSTRATE in
    // Plan B: there is no issuing RPC, no column and no table for a
    // "server-issued, requester/session-bound, single-use, two-minute"
    // nonce (verified by catalog query). It is accepted in the
    // allowlist below and NOT trusted, and the gap is reported rather
    // than faked -- a nonce this function invents and immediately
    // accepts would gate nothing while reading as implemented.
    const allowedLocationKeys = new Set([
      "latitude",
      "longitude",
      "accuracy_m",
      "captured_at",
      "confirmation_nonce",
    ]);
    for (const key of Object.keys(locationRecord)) {
      if (!allowedLocationKeys.has(key)) {
        return { ok: false, error: sessionError("INVALID_INPUT") };
      }
    }
    const latitude = locationRecord.latitude;
    const longitude = locationRecord.longitude;
    const accuracyM = locationRecord.accuracy_m;
    const capturedAt = locationRecord.captured_at;
    // §4.1: "latitude [-90,90], longitude [-180,180], accuracy
    // (0,5000] metres; all finite." LOCATION_REQUIRED rather than
    // INVALID_INPUT: §10 gives it "fresh explicit confirmation, no
    // fallback", which is the remedy for a bad point.
    if (
      typeof latitude !== "number" || !Number.isFinite(latitude) ||
      latitude < -90 || latitude > 90 ||
      typeof longitude !== "number" || !Number.isFinite(longitude) ||
      longitude < -180 || longitude > 180 ||
      typeof accuracyM !== "number" || !Number.isFinite(accuracyM) ||
      accuracyM <= 0 || accuracyM > 5000 ||
      typeof capturedAt !== "string"
    ) {
      return { ok: false, error: sessionError("LOCATION_REQUIRED") };
    }
    const capturedMs = Date.parse(capturedAt);
    if (!Number.isFinite(capturedMs)) {
      return { ok: false, error: sessionError("LOCATION_REQUIRED") };
    }
    requesterLocation = {
      latitude,
      longitude,
      accuracyM,
      capturedAt,
    };
  }

  return {
    ok: true,
    request: {
      sessionId,
      requestId,
      expectedRevision,
      userInstruction: trimmedInstruction,
      requesterLocation,
    },
  };
}

/// §6.2's operation fingerprint. §4.1: "Request IDs for retries bind
/// actor, operation, session and payload revision; different payload
/// reuse yields REQUEST_CONFLICT", and admit_ai_session_generation
/// compares this string verbatim on a replay.
///
/// A HASH, NOT A LENGTH. The task brief sketched `ideas:${length}`,
/// which does not distinguish two DIFFERENT instructions of the same
/// length -- so a client replaying one request_id with a same-length
/// but different instruction would be told `already_admitted` and
/// silently get the ORIGINAL request's result, which is the precise
/// failure §4.1 names. A test asserts the specific REQUEST_CONFLICT.
///
/// COORDINATES ARE DELIBERATELY NOT IN THE FINGERPRINT. §4.1: "A
/// request-ID retry cannot replace coordinates or cause a new call",
/// and "Coordinates remain Edge memory only, never SQL, telemetry,
/// PERSISTED REQUEST FINGERPRINTS or content." Hashing them would
/// persist a (salt-free, low-entropy, brute-forceable) commitment to a
/// user's position in ai_session_requests.operation_fingerprint, which
/// §4.1 forbids by name. A retry therefore cannot change the
/// instruction, and its coordinates are ignored because the result is
/// replayed rather than regenerated.
export async function computeOperationFingerprint(
  kind: string,
  sessionId: string,
  expectedRevision: number,
  userInstruction: string,
): Promise<string> {
  // Length-prefixed, like buildDigestPreimage: without it,
  // ("ab","c") and ("a","bc") share a pre-image, so two different
  // payloads could produce one fingerprint and a conflict would read
  // as a replay.
  const preimage = [
    "ai-session-op-v1",
    `kind=${scalarLength(kind)}:${kind}`,
    `session=${scalarLength(sessionId)}:${sessionId}`,
    `revision=${expectedRevision}`,
    `instruction=${scalarLength(userInstruction)}:${userInstruction}`,
  ].join("\n");
  const hashed = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(preimage),
  );
  return Array.from(new Uint8Array(hashed))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

// ---------------------------------------------------------------------------
// Context assembly for the prompt -- spec §4.2, §4.3. RULING 13's half.
// ---------------------------------------------------------------------------

/// A source row as frozen at prepare time. ITEM B / RULING 13: these
/// come from ai_session_sources, the rows the approved digest was
/// computed over -- never from a fresh window selection.
interface FrozenSource {
  messageId: string;
  sourceVersion: string;
  approvedText: string;
  role: "target" | "window";
}

/// Reads the FROZEN approved sources for a session.
///
/// RULING 13, and the reason this is a separate function rather than a
/// call to selectSharedWindow: §4.2 requires "Persist source IDs,
/// versions and snapshot time, NOT NEW SELECTIONS ON SUBSEQUENT TURNS",
/// and §4.3 requires revalidation "against the FROZEN snapshot". A
/// re-selection at dispatch time would silently substitute whatever the
/// civil day now contains for what the two partners actually approved --
/// which §4.3 says explicitly not to do ("do not use stale copies or
/// SUBSTITUTE NEW MESSAGES").
///
/// ORDER IS DETERMINISTIC AND MATCHES THE APPROVED ORDER: the target
/// first (review_context put it first, so it is snippet[0] of the
/// approved digest), then the window rows ordered
/// (source_version ASC, source_message_id ASC) -- the same chronological,
/// id-tiebroken order §4.2 fixes and selectWindowFromRows produced.
/// ai_session_sources has no explicit sequence column, so the order
/// must be derived from the stored columns; deriving it the same way
/// §4.2 does is what keeps the prompt's snippet order equal to the
/// approved one.
async function loadFrozenSources(
  service: SupabaseClient,
  sessionId: string,
): Promise<FrozenSource[] | null> {
  const result = await service
    .from("ai_session_sources")
    .select("source_message_id, source_version, approved_clipped_text, source_role")
    .eq("session_id", sessionId);
  if (result.error) return null;
  const rows = (result.data ?? []) as Record<string, unknown>[];

  const mapped: FrozenSource[] = [];
  for (const row of rows) {
    // Canonicalized for the SAME reason review_context does it: the
    // stored timestamptz reaches this code in whichever spelling the
    // transport chose (µs from PostgREST, ms from the test double), and
    // a revalidation comparing raw strings would bind the transport.
    const version = canonicalTimestamp(row.source_version);
    if (version === null) return null;
    const role = row.source_role;
    if (role !== "target" && role !== "window") return null;
    mapped.push({
      messageId: row.source_message_id as string,
      sourceVersion: version,
      approvedText: String(row.approved_clipped_text),
      role,
    });
  }

  const target = mapped.filter((source) => source.role === "target");
  const window = mapped
    .filter((source) => source.role === "window")
    .sort((a, b) =>
      a.sourceVersion === b.sourceVersion
        ? (a.messageId < b.messageId ? -1 : a.messageId > b.messageId ? 1 : 0)
        : (a.sourceVersion < b.sourceVersion ? -1 : 1)
    );
  return [...target, ...window];
}

/// §4.3: "At activation and EVERY DISPATCH, commit and share,
/// revalidate membership, consent and SOURCE EXISTENCE/VERSION against
/// the frozen snapshot. Edits, tombstones or removal make the session
/// unavailable and terminate it."
///
/// READS THE STORED ROWS, NOT A RE-SELECTION (Ruling 13). The inputs
/// are exactly the two columns §4.3 names -- `source_message_id` and
/// `source_version` -- taken from ai_session_sources, and they are
/// compared against public.messages' live
/// (deleted_at, COALESCE(edited_at, created_at)). No window query runs
/// here, so nothing the day has gained or lost since prepare time can
/// change the answer.
///
/// Returns true when every frozen source still exists undeleted at the
/// frozen version.
async function frozenSourcesStillValid(
  service: SupabaseClient,
  relationshipId: string,
  sources: readonly FrozenSource[],
): Promise<boolean | null> {
  if (sources.length === 0) return true;
  const result = await service
    .from("messages")
    .select("id, deleted_at, created_at, edited_at, relationship_id")
    .in("id", sources.map((source) => source.messageId));
  if (result.error) return null;
  const live = new Map<string, Record<string, unknown>>();
  for (const row of (result.data ?? []) as Record<string, unknown>[]) {
    live.set(row.id as string, row);
  }
  for (const source of sources) {
    const row = live.get(source.messageId);
    // Existence: a removed or tombstoned source invalidates.
    if (!row) return false;
    if (row.deleted_at != null) return false;
    // Same relationship: belt-and-braces against a source row that
    // somehow names a foreign message.
    if (row.relationship_id !== relationshipId) return false;
    // Version: the SAME expression 20260953200200 writes
    // (COALESCE(edited_at, created_at)), so an edit moves it and this
    // comparison sees the edit -- which is the whole point of Ruling
    // 9's fix.
    const liveVersion = canonicalTimestamp(row.edited_at ?? row.created_at);
    if (liveVersion === null) return null;
    if (liveVersion !== source.sourceVersion) return false;
  }
  return true;
}

/// §4.2 item 4: "Prior committed Ideas exchanges from THIS SESSION
/// ONLY: at most 6,000 scalars of model-visible content, kept as
/// complete user/answer pairs."
///
/// ISOLATION PROPERTY (3): the kind filter is in the SQL predicate, so
/// a 'nearby_result' turn is excluded before any field of it is read.
/// §2: "No Nearby transcript, place result, source payload or derived
/// summary becomes later model history, even within the same Nearby
/// session." Only two payload fields are projected, both of which
/// exist solely on 'ideas_answer' turns.
///
/// Read through read_ai_session_turns, NOT a direct table select, so
/// the RPC's own four gates (state/expiry, membership, consent,
/// creator-or-accepted-participant) apply -- and p_actor_id comes from
/// the verified user.
async function loadPriorIdeasTurns(
  service: SupabaseClient,
  actorId: string,
  sessionId: string,
): Promise<SessionPromptInputs["history"] | null> {
  const result = await service.rpc("read_ai_session_turns", {
    // THE ACTOR COMES FROM THE VERIFIED USER, never the body.
    p_actor_id: actorId,
    p_session_id: sessionId,
  });
  if (result.error) return null;
  const rows = (result.data ?? []) as Record<string, unknown>[];

  const pairs: { role: "user" | "attune"; content: PromptApprovedText }[] = [];
  for (const row of rows) {
    // THE KIND FILTER. 'nearby_result' and 'redirect' turns are dropped
    // here: a redirect is not an Ideas exchange (§4.2 item 4 says
    // "complete user/answer pairs"), and a nearby_result is §2's
    // forbidden re-entry.
    if (row.kind !== "ideas_answer") continue;
    const payload = (row.payload ?? {}) as Record<string, unknown>;
    const role = row.role;
    if (role === "user") {
      const instruction = payload.instruction;
      if (typeof instruction !== "string") continue;
      pairs.push({ role: "user", content: priorSessionTurnText(instruction) });
    } else if (role === "attune") {
      const replyText = payload.reply_text;
      if (typeof replyText !== "string") continue;
      // §4.2: "History includes only text actually displayed AND SAFE
      // STRUCTURED PROPOSAL TEXT; count all such fields, not just
      // reply_text." The proposal's title was displayed, so it is
      // history and it is counted.
      const proposal = payload.suggested_planning_item as
        | Record<string, unknown>
        | null
        | undefined;
      const title = typeof proposal?.title === "string"
        ? proposal.title
        : null;
      pairs.push({
        role: "attune",
        content: priorSessionTurnText(
          title === null ? replyText : `${replyText}\n${title}`,
        ),
      });
    }
  }

  // §4.2: "Drop oldest complete exchanges until within 6,000; no orphan
  // assistant rows ... Newest committed eligible pair is retained."
  // read_ai_session_turns orders by ordinal, and Plan B's ordinal parity
  // is 2n-1 user / 2n attune from one attempt counter, so consecutive
  // (user, attune) entries are one exchange.
  const exchanges: typeof pairs[] = [];
  for (let i = 0; i < pairs.length; i++) {
    if (
      pairs[i].role === "user" && pairs[i + 1]?.role === "attune"
    ) {
      exchanges.push([pairs[i], pairs[i + 1]]);
      i++;
    }
    // A lone user or attune entry is an ORPHAN and is dropped
    // entirely: §4.2 forbids "orphan assistant rows", and a lone user
    // turn with no answer is a failed attempt, which §4.2 also excludes
    // ("no ... failed/staged turns").
  }

  // Drop OLDEST first, keeping the newest, until within the budget.
  const kept: typeof pairs[] = [];
  let total = 0;
  for (let i = exchanges.length - 1; i >= 0; i--) {
    const cost = exchanges[i].reduce(
      (sum, entry) => sum + scalarLength(String(entry.content)),
      0,
    );
    // The NEWEST pair is retained even if it alone exceeds the budget
    // (§4.2: "do not silently alter approved sources or remove the
    // newest pair"); older pairs are dropped once the budget is spent.
    if (kept.length > 0 && total + cost > HISTORY_SCALAR_BUDGET) break;
    kept.unshift(exchanges[i]);
    total += cost;
  }
  // §5.2: "At most nine previous pairs are available before attempt
  // ten", which the 10-attempt cap already bounds; this is the explicit
  // form so a cap change cannot silently widen the prompt.
  const bounded = kept.slice(-MAX_HISTORY_PAIRS);
  return bounded.flat();
}

/// §4.2: "at most 6,000 scalars of model-visible content".
const HISTORY_SCALAR_BUDGET = 6000;
/// §5.2: "At most nine previous pairs are available before attempt ten."
const MAX_HISTORY_PAIRS = 9;
/// §4.2: "cap fully serialized provider input, including
/// instructions/roles, at 64 KiB UTF-8".
const PROVIDER_INPUT_BYTE_CAP = 64 * 1024;

// ---------------------------------------------------------------------------
// The safety gate -- spec §8.1, and the plan's non-disclosure constraint.
// ---------------------------------------------------------------------------

/// The ONE shape a safety refusal takes, on BOTH the pre-dispatch and
/// pre-publish paths.
///
/// HOW THIS AVOIDS DISCLOSING THE DETECTOR, to either party:
///
///  - It is built from classifySessionContent -- Task 3's CALLER-FACING
///    export, whose verdict is four fields with no rule id, family,
///    tier, count or config version, and whose `unsafe_to_assist` copy
///    is byte-identical for a tier-1 self-harm match, a tier-2
///    coercion match and any chat family. detectSessionSafetyConcern,
///    the operator-side export that DOES carry matchedRuleIds, is not
///    called on any path whose value reaches a response body.
///  - It is the SAME response whichever check fired and whichever
///    content tripped it: the instruction, a frozen source, a prior
///    turn or the model's own output. A probing requester cannot tell
///    which of the four it was, nor which pass caught it, because the
///    body is a function of the verdict alone.
///  - IT IS A SILENT NON-POST FOR THE PARTNER. No turn is committed, no
///    staging row is written, and `ai_sessions.revision` is NOT bumped
///    on this path, so a partner polling session_revision (Ruling 1's
///    sanctioned mechanism) sees exactly what it sees when the
///    requester simply typed nothing: the same integer. §5.3: "Safety
///    refusals remain requester-only, not shared transcript events."
///  - The HTTP status is 200, not an error code. A distinct status
///    would make a safety refusal distinguishable from an ordinary
///    model redirect in any proxy log or client-side metric, and
///    §8.1's "A refusal/error must not signal a private detector
///    result" covers the error as much as the refusal.
function safetyRefusalResponse(verdict: SessionSafetyVerdict): Response {
  return jsonResponse({
    kind: "redirect",
    // §5.3: "server-rendered fixed copy from allowlisted reason". Both
    // fields are copied verbatim from Task 3's frozen table; nothing is
    // interpolated, so no phrase or rule name can reach a user.
    reason: verdict.reason,
    copy: verdict.copy,
    // Always true, on every path including the allowed one -- its
    // presence is a constant, never a signal (§8.1).
    show_safety_resources: verdict.showSafetyResources,
    offered: [],
  });
}

/// Runs the deterministic safety corpus over EVERY string that is about
/// to reach a provider: the current instruction, every approved source
/// and every eligible history entry. §8.1: "Deterministic synchronous
/// checks run BEFORE DISPATCH on current instruction, approved sources
/// and eligible history."
///
/// SYNCHRONOUS AND PURE -- no await, no IO. That is not incidental:
/// §8.1 requires the check before dispatch and again on every output
/// field, and an IO-bearing check could not run on every field inside
/// §8.2.1's budget. It is also what makes "the check ran before the
/// provider call" provable by ordering rather than by hope.
function checkPromptInputsSafety(
  inputs: SessionPromptInputs,
): SessionSafetyVerdict {
  // The instruction FIRST, because it is the one string the requester
  // just typed and therefore the likeliest to be the reason.
  const instructionVerdict = classifySessionContent(inputs.userInstruction);
  if (!instructionVerdict.allowed) return instructionVerdict;
  for (const snippet of inputs.contextWindow) {
    const verdict = classifySessionContent(String(snippet));
    if (!verdict.allowed) return verdict;
  }
  for (const turn of inputs.history) {
    const verdict = classifySessionContent(String(turn.content));
    if (!verdict.allowed) return verdict;
  }
  return instructionVerdict;
}

/// §8.1: "and BEFORE PUBLISHING ON EVERY OUTPUT FIELD". Every field,
/// not just reply_text -- the proposal title is an output field and
/// §5.3's own note says "Output checks cover prose, proposals and
/// source display strings".
function checkOutputSafety(
  output: SessionTurnOutput,
): SessionSafetyVerdict {
  if (output.kind === "redirect") {
    // A redirect carries no model-written text at all (§5.3), so there
    // is no field to check -- but it must still return an ALLOWED
    // verdict rather than being skipped, so the caller's "both checks
    // passed" precondition is satisfied explicitly rather than by
    // falling through.
    return classifySessionContent("");
  }
  const replyVerdict = classifySessionContent(output.reply_text);
  if (!replyVerdict.allowed) return replyVerdict;
  const title = output.suggested_planning_item?.title;
  if (typeof title === "string") {
    const titleVerdict = classifySessionContent(title);
    if (!titleVerdict.allowed) return titleVerdict;
  }
  return replyVerdict;
}

// ---------------------------------------------------------------------------
// The 'generate' handler.
// ---------------------------------------------------------------------------

/// THE ORDER OF OPERATIONS, and why each step is where it is.
///
///   1. Parse and bound the request (§4.1). No DB work yet.
///   2. Resolve the session SERVER-SIDE and run the §3.1 eligibility
///      gate (capability, membership, consent) from the session ROW --
///      never from the body.
///   3. Load the FROZEN approved sources and the eligible history
///      (§4.2, Ruling 13), and revalidate source existence/version
///      against them (§4.3's "every dispatch").
///   4. SAFETY PASS 1, synchronous, over the instruction + approved
///      sources + eligible history (§8.1). BEFORE admission, so an
///      unsafe instruction consumes no attempt slot and no quota --
///      §5.2: "Validation, consent, busy, oversized context and
///      rate-limit rejections consume neither."
///   5. Budget checks (§4.2's 64 KiB / scalar caps) -> CONTEXT_TOO_LARGE
///      "before reserving quota/provider work".
///   6. admit_ai_session_generation -- the slot and the quota. ONE
///      transaction, entirely before dispatch.
///   7. claim_ai_session_dispatch -- the provider-start marker.
///   8. THE PROVIDER CALL(S). No SQL transaction is open across them:
///      steps 6 and 7 each committed, and step 9 opens a new one.
///   9. Validate the output (§5.3, §8.2.5), then SAFETY PASS 2 over
///      every output field (§8.1).
///  10. commit/stage -- the completion RPC, entirely after dispatch.
///
/// NO TRANSACTION SPANS A PROVIDER CALL. Each `service.rpc(...)` above
/// is its own autocommitted statement; this function never issues
/// BEGIN, and steps 6/7 complete before step 8 starts. Plan B's RPCs
/// are built for exactly this split -- admit takes the locks and the
/// quota, the completion RPCs take them again afterwards -- and the
/// lease (35s) is what covers the gap instead of a held lock.
async function handleGenerate(branch: BranchContext): Promise<Response> {
  const parsed = parseGenerateRequest(branch.body);
  if (!parsed.ok) return errorResponse(parsed.error);
  const request = parsed.request;
  const service = branch.service();

  // --- 2. The session, resolved server-side -----------------------------
  const session = await service
    .from("ai_sessions")
    .select(
      "id, relationship_id, creator_id, kind, visibility, state, revision, context_revision, include_window, expires_at",
    )
    .eq("id", request.sessionId)
    .maybeSingle();
  if (session.error) return errorResponse(sessionError("INTERNAL_ERROR"));
  const row = session.data as Record<string, unknown> | null;
  // §3.1: "Foreign, ended, expired and unauthorized session IDs return
  // the same unavailable response."
  if (!row) return errorResponse(sessionError("UNAVAILABLE"));

  const relationshipId = row.relationship_id as string;
  const kind = row.kind as string;
  const visibility = row.visibility as string;
  const includeWindow = row.include_window === true;

  const eligibility = await checkEligibility(
    service,
    // THE ACTOR COMES FROM THE VERIFIED USER.
    branch.actorId,
    relationshipId,
    capabilitiesForSession(kind, visibility, includeWindow),
  );
  if (!eligibility.ok) return errorResponse(eligibility.error);

  // §5.1: "Server read-time expiry is authoritative even before
  // cleanup."
  //
  // MUTATION-TESTED, AND THE RESULT IS RECORDED RATHER THAN TIDIED
  // AWAY: deleting either of these two checks -- or both -- leaves the
  // suite GREEN, because admit_ai_session_generation makes the same two
  // refusals itself, twice each (once pre-lock, once under the session
  // row lock, lines "state != 'active'" and "expires_at <= now()" in
  // its body). So they are honestly REDUNDANT-BY-DESIGN, not untested:
  // the §5.1 test below asserts the refusal and the "no provider call /
  // no slot" consequence, and that test passes with these lines gone
  // because the RPC is what refuses.
  //
  // They stay because they refuse EARLIER -- before the frozen-source
  // read, the revalidation query, the history read and the three safety
  // passes -- so a dead session costs four queries and no safety work
  // instead of all of it. That is a cost property, not a correctness
  // one, which is why no test is bent into shape around it.
  if (row.state !== "active") return errorResponse(sessionError("UNAVAILABLE"));
  const expiresAt = row.expires_at;
  if (
    typeof expiresAt === "string" &&
    new Date(expiresAt).getTime() <= branch.now.getTime()
  ) {
    return errorResponse(sessionError("UNAVAILABLE"));
  }

  // §4.1's "required only for Nearby", enforced both ways: an Ideas
  // session supplying a point is rejected rather than quietly ignored
  // (a client that believes it sent a location must not be told it
  // worked), and a Nearby session without one gets LOCATION_REQUIRED.
  if (kind === "nearby" && request.requesterLocation === null) {
    return errorResponse(sessionError("LOCATION_REQUIRED"));
  }
  if (kind !== "nearby" && request.requesterLocation !== null) {
    return errorResponse(sessionError("INVALID_INPUT"));
  }
  // §4.1: "Location timestamp within two minutes of server time."
  // Checked against branch.now, the single server instant.
  if (request.requesterLocation !== null) {
    const skewMs = Math.abs(
      branch.now.getTime() - Date.parse(request.requesterLocation.capturedAt),
    );
    if (skewMs > 120_000) {
      // §10: LOCATION_EXPIRED -> "fresh explicit confirmation, no
      // fallback". Distinct from LOCATION_REQUIRED because the remedy
      // differs: recapture, rather than ask for permission.
      return errorResponse(sessionError("LOCATION_EXPIRED"));
    }
  }

  // --- 3. The FROZEN context (Ruling 13) --------------------------------
  const frozenSources = await loadFrozenSources(service, request.sessionId);
  if (frozenSources === null) {
    return errorResponse(sessionError("INTERNAL_ERROR"));
  }
  const sourcesValid = await frozenSourcesStillValid(
    service,
    relationshipId,
    frozenSources,
  );
  if (sourcesValid === null) {
    return errorResponse(sessionError("INTERNAL_ERROR"));
  }
  if (!sourcesValid) {
    // §4.3: "Edits, tombstones or removal make the session unavailable
    // and terminate it; do not use stale copies or substitute new
    // messages." Terminating is end_ai_session's job and it is
    // idempotent, so it is safe to call here; the caller is told
    // CONTEXT_CHANGED, which §10 gives "no automatic retry or new
    // context".
    await service.rpc("end_ai_session", {
      p_actor_id: branch.actorId,
      p_session_id: request.sessionId,
    });
    return errorResponse(sessionError("CONTEXT_CHANGED"));
  }

  const history = await loadPriorIdeasTurns(
    service,
    branch.actorId,
    request.sessionId,
  );
  if (history === null) return errorResponse(sessionError("INTERNAL_ERROR"));

  // THE ONE STRUCT EVERYTHING DOWNSTREAM IS BUILT FROM. The prompt, the
  // safety pass and the §8.2.5 quoted-source list all derive from THIS
  // value, so they cannot disagree about what was sent -- which is the
  // property that keeps the quotation check from being vacuous.
  //
  // Note what is NOT here: no location (isolation property 1), no
  // Mapbox result, no relationship id, no session id, no actor id, no
  // policy version -- §2's "Provider requests never contain account/
  // relationship/session UUIDs".
  const promptInputs: SessionPromptInputs = {
    userInstruction: request.userInstruction,
    history,
    contextWindow: frozenSources.map((source) =>
      approvedSourceText(source.approvedText)
    ),
  };

  // --- 4. SAFETY PASS 1, before admission -------------------------------
  const inputVerdict = checkPromptInputsSafety(promptInputs);
  if (!inputVerdict.allowed) {
    // No admission, no quota, no slot, no revision bump, no turn. §5.2:
    // a validation/consent rejection "consume[s] neither". And a
    // partner polling session_revision sees nothing at all.
    return safetyRefusalResponse(inputVerdict);
  }

  // --- 5. Budgets (§4.2), before reserving quota or provider work -------
  const { system, userTemplate } = await loadSessionPrompts();
  const assistKind = kind === "nearby" ? "nearby" : "ideas";
  const userPrompt = buildSessionUserPrompt(
    userTemplate,
    assistKind,
    promptInputs,
  );
  // §4.2: "cap FULLY SERIALIZED provider input, INCLUDING
  // instructions/roles, at 64 KiB UTF-8" -- so the system prompt counts
  // too, which is why this is measured here and not inside the builder.
  const serializedBytes = new TextEncoder().encode(system + userPrompt).length;
  if (serializedBytes > PROVIDER_INPUT_BYTE_CAP) {
    // §4.2: "If mandatory content still exceeds a cap, reject
    // CONTEXT_TOO_LARGE BEFORE RESERVING QUOTA/PROVIDER WORK."
    //
    // The 16,384-TOKEN half of §4.2's cap is NOT enforced: it requires
    // "the pinned model's validated tokenizer", and no tokenizer exists
    // in this repo (verified by grep). §4.2 says "Tokenizer
    // unavailability fails closed", which this byte cap does not
    // satisfy -- reported as a plan gap rather than approximated, since
    // a chars/4 guess would read as implemented while bounding nothing.
    return errorResponse(sessionError("CONTEXT_TOO_LARGE"));
  }

  // --- 6. Admission: the slot, the quota, one transaction ---------------
  const fingerprint = await computeOperationFingerprint(
    kind,
    request.sessionId,
    request.expectedRevision,
    request.userInstruction,
  );
  const admitResult = await service.rpc("admit_ai_session_generation", {
    // THE ACTOR COMES FROM THE VERIFIED USER, never the body.
    p_actor_id: branch.actorId,
    p_request_id: request.requestId,
    p_session_id: request.sessionId,
    p_expected_revision: request.expectedRevision,
    p_operation_fingerprint: fingerprint,
  });
  if (admitResult.error) {
    const message = String(admitResult.error.message ?? "");
    if (/CONTEXT_CHANGED/.test(message)) {
      return errorResponse(sessionError("CONTEXT_CHANGED"));
    }
    if (/BUSY/.test(message)) {
      return errorResponse(sessionError("SESSION_BUSY"));
    }
    if (/LIMIT_REACHED/.test(message)) {
      return errorResponse(sessionError("SESSION_LIMIT_REACHED"));
    }
    if (/consent/i.test(message)) {
      return errorResponse(sessionError("CONSENT_REQUIRED"));
    }
    // 'UNAVAILABLE', 'Not a current member' and anything unrecognized
    // collapse to UNAVAILABLE -- §3.1's indistinguishable response.
    return errorResponse(sessionError("UNAVAILABLE"));
  }
  const admission =
    (admitResult.data as Record<string, unknown>[] | null)?.[0];
  if (!admission) return errorResponse(sessionError("INTERNAL_ERROR"));
  switch (admission.outcome) {
    case "admitted":
      break;
    case "already_admitted":
      // §6.2 step 2: "For an existing actor/request ID, return its
      // state/result ... NEVER A NEW PROVIDER LEASE." A replay must not
      // dispatch again, so this returns the committed turn rather than
      // falling through to the provider call below.
      return await replayAdmittedRequest(service, branch, request, admission);
    case "busy":
      return errorResponse(sessionError("SESSION_BUSY"));
    case "limit_reached":
      return errorResponse(sessionError("SESSION_LIMIT_REACHED"));
    case "rate_limited":
      return errorResponse(sessionError(
        "RATE_LIMITED",
        typeof admission.retry_after_seconds === "number"
          ? admission.retry_after_seconds
          : null,
      ));
    case "conflict":
      // §4.1: "different payload reuse yields REQUEST_CONFLICT". This
      // is the fingerprint doing its work.
      return errorResponse(sessionError("REQUEST_CONFLICT"));
    default:
      return errorResponse(sessionError("UNAVAILABLE"));
  }

  // --- 7. The dispatch claim -------------------------------------------
  const workerToken = admission.worker_token as string;
  const claimed = await service.rpc("claim_ai_session_dispatch", {
    p_worker_token: workerToken,
    p_request_id: request.requestId,
  });
  if (claimed.error) return errorResponse(sessionError("INTERNAL_ERROR"));
  const claimRow = (claimed.data as Record<string, unknown>[] | null)?.[0];
  if (claimRow?.claim_ai_session_dispatch !== true) {
    // The lease expired or another worker claimed it. §10:
    // REQUEST_FAILED is a "counted status explained to requester".
    return errorResponse(sessionError("REQUEST_FAILED"));
  }

  // --- 8/9/10. Dispatch, validate, commit -------------------------------
  // Split by kind into two functions with DISJOINT signatures, which is
  // isolation property (4): the Ideas path never receives a location,
  // and the Nearby path's Mapbox leg never receives prompt text.
  if (assistKind === "nearby") {
    return await dispatchNearby(
      service,
      branch,
      request,
      relationshipId,
      workerToken,
      system,
      userPrompt,
      promptInputs,
      // Non-null by the §4.1 check above; passed as its own argument
      // rather than inside promptInputs, which has no slot for it.
      request.requesterLocation!,
    );
  }
  return await dispatchIdeas(
    service,
    branch,
    request,
    relationshipId,
    workerToken,
    system,
    userPrompt,
    promptInputs,
  );
}

/// §6.2 step 2: "For an existing actor/request ID, return its
/// state/result ... never a new provider lease."
///
/// Reached only on `already_admitted`, i.e. a retry of a request_id with
/// the SAME fingerprint (a different fingerprint returns `conflict`).
/// It re-reads the committed turn through read_ai_session_turns -- so
/// the retry gets the original answer and NO provider call happens. A
/// request still in flight has no committed turn yet, which is
/// SESSION_BUSY rather than a second dispatch.
async function replayAdmittedRequest(
  service: SupabaseClient,
  branch: BranchContext,
  request: GenerateRequest,
  _admission: Record<string, unknown>,
): Promise<Response> {
  const turns = await service.rpc("read_ai_session_turns", {
    p_actor_id: branch.actorId,
    p_session_id: request.sessionId,
  });
  if (turns.error) return errorResponse(sessionError("INTERNAL_ERROR"));
  const rows = (turns.data ?? []) as Record<string, unknown>[];
  const mine = rows.filter((turn) => turn.request_id === request.requestId);
  const attuneTurn = mine.find((turn) => turn.role === "attune");
  if (!attuneTurn) {
    // Admitted but not yet committed: still in flight. §10:
    // SESSION_BUSY -> "keep own draft, retry explicitly after refetch".
    return errorResponse(sessionError("SESSION_BUSY"));
  }
  const userTurn = mine.find((turn) => turn.role === "user");
  const payload = (attuneTurn.payload ?? {}) as Record<string, unknown>;
  return jsonResponse({
    user_ordinal: userTurn?.ordinal ?? null,
    attune_ordinal: attuneTurn.ordinal,
    reply_text: payload.reply_text ?? null,
    suggested_planning_item: payload.suggested_planning_item ?? null,
    replayed: true,
  });
}

/// SETTLES A DISPATCHED REQUEST AS TERMINAL, so a refusal does not leave
/// the session SESSION_BUSY until its 35-second lease expires (Item A2 /
/// Ruling 18; Task 4 measured the gap and found no fail/release/abandon
/// RPC existed at all).
///
/// CALLED ON EVERY POST-DISPATCH FAILURE PATH, and the set is not
/// negotiable -- Task 4 enumerated three families and they all land
/// here:
///
///   * a PRE-PUBLISH SAFETY REFUSAL (pass 2, on any output field or any
///     Nearby card string),
///   * a §5.3 VALIDATOR REJECTION (validateSessionTurnOutput or
///     validateNearbyCategoryOutput returning null),
///   * a PROVIDER FAILURE (Gemini or Mapbox returning nothing).
///
/// THE RPC CANNOT DISTINGUISH THEM, by construction: it takes no reason
/// parameter, so all three write the byte-identical row. That is why
/// this helper takes no reason parameter either -- there is nothing to
/// pass and nothing a future caller could pass wrongly. A `reason`
/// argument here would be a disclosure channel one refactor away from
/// the database.
///
/// IT NEVER CHANGES WHAT THE CALLER RETURNS. The result is deliberately
/// ignored and no error can escape: a settle that failed must not turn
/// a carefully neutral §8.1 refusal body into an INTERNAL_ERROR, which
/// would make a safety refusal distinguishable from a provider failure
/// by HTTP status -- the exact property §8.1 forbids. A failed settle
/// just means the lease expires the old way, which is the behaviour
/// before this existed.
async function settleDispatchedRequest(
  service: SupabaseClient,
  actorId: string,
  requestId: string,
): Promise<void> {
  try {
    await service.rpc("settle_ai_session_request", {
      // THE ACTOR COMES FROM THE VERIFIED USER, never the body. The RPC
      // settles only the request's OWN actor's row, so a mismatch is a
      // silent no-op rather than a cross-actor cancel.
      p_actor_id: actorId,
      p_request_id: requestId,
    });
  } catch {
    // Deliberately swallowed -- see the header.
  }
}

/// Ideas. ONE provider call, no location parameter at all.
async function dispatchIdeas(
  service: SupabaseClient,
  branch: BranchContext,
  request: GenerateRequest,
  // The couple, for the cost ledger only (final review I-4).
  relationshipId: string,
  workerToken: string,
  systemPrompt: string,
  userPrompt: string,
  promptInputs: SessionPromptInputs,
): Promise<Response> {
  const gemini = branch.callGemini;
  const parsed = await gemini({
    promptId: `${SESSION_PROMPT_VERSION}_ideas`,
    attribution: { fn: "ai-sessions", relationshipId, userId: branch.actorId },
    systemPrompt,
    userPrompt,
    maxOutputTokens: 2048,
  });
  if (!parsed) {
    // ITEM A2: settle the request so the session is not SESSION_BUSY for
    // up to 35 seconds. Identical call, identical resulting row, as the
    // safety and validator paths below.
    await settleDispatchedRequest(service, branch.actorId, request.requestId);
    return errorResponse(sessionError("PROVIDER_UNAVAILABLE"));
  }

  // §5.3 / §8.2.5. quotedSources is derived from the SAME struct the
  // prompt was built from -- see collectQuotedSources.
  const validated = validateSessionTurnOutput(
    parsed,
    collectQuotedSources(promptInputs),
  );
  if (!validated) {
    // ITEM A2.
    await settleDispatchedRequest(service, branch.actorId, request.requestId);
    return errorResponse(sessionError("RESULT_UNAVAILABLE"));
  }

  // SAFETY PASS 2, on every output field, before anything is published.
  const outputVerdict = checkOutputSafety(validated);
  if (!outputVerdict.allowed) {
    // §8.1: "Unsafe pending prompts are not published." Nothing is
    // committed, so there is no transcript pair and no revision bump --
    // the partner sees a silent non-post.
    //
    // ITEM A2 / RULING 18 CLOSES TASK 4'S REPORTED GAP. The request
    // row used to stay 'started' with a live 35-second lease, so the
    // session was SESSION_BUSY until reconcile_ai_session_leases
    // settled it -- Plan B exposed no fail/release/abandon RPC at all.
    // 20260953200400 adds one and it is called here.
    //
    // THE PROPERTY TASK 4 IDENTIFIED IS PRESERVED, AND NOW
    // STRUCTURALLY RATHER THAN INCIDENTALLY: this is the IDENTICAL
    // disposition a provider timeout and a validator rejection
    // produce, because settle_ai_session_request TAKES NO REASON
    // PARAMETER -- all three paths call it with the same two arguments
    // and it writes the same row (state 'failed', terminal_code
    // 'REQUEST_FAILED'). There is no value by which the request row
    // could tell an operator, a support tool or a future read RPC that
    // a SAFETY detector fired rather than the provider having failed.
    //
    // Settled BEFORE the response is built, and the settle's own
    // outcome is ignored, so it cannot alter the refusal body or its
    // status either (see settleDispatchedRequest's header).
    await settleDispatchedRequest(service, branch.actorId, request.requestId);
    return safetyRefusalResponse(outputVerdict);
  }

  if (validated.kind === "redirect") {
    // §5.3 AS AMENDED BY TASK 6 / ITEM B: "NO redirect becomes a
    // transcript pair. ALL redirects are requester-only", like safety
    // refusals. The original text said "only ordinary unsupported
    // redirects become transcript pairs", which mandated a pair nothing
    // could create: the ai_session_turns kind CHECK allows 'redirect',
    // but commit_ai_session_ideas_turn hardcodes 'ideas_answer',
    // publish_ai_session_nearby_result hardcodes 'nearby_result', and
    // share_ai_session_turn names 'redirect' only to REJECT it. The
    // spec was amended rather than an RPC added, because a durable
    // redirect would be a safety side channel (redirect and refusal
    // share a reason set, so bumping the revision for 'unsupported' but
    // not 'unsafe_to_assist' discloses the detector to a partner
    // polling session_revision -- §8.1 forbids exactly that), would be
    // partner-visible (read_ai_session_turns does not filter by kind),
    // and would spend two of §5.2's twenty ordinals on rows the history
    // builder drops and §8.1 forbids posting.
    //
    // A safety refusal never reaches this line: pass 1 returned before
    // dispatch and pass 2 returns above it.
    //
    // ITEM B: SETTLE THE REQUEST. §5.3 now puts a redirect in the same
    // class as a provider failure, a validator rejection and a safety
    // refusal -- an outcome that commits nothing -- and all three of
    // those settle (Ruling 18 / Item A2). Without this the row stayed
    // 'started' with a live 35-second lease and every retry got
    // SESSION_BUSY until the reconciler ran, which is the identical
    // defect Ruling 18 closed for its three siblings. The same call
    // with the same two arguments writes the same row, so a redirect is
    // not distinguishable from any of them.
    await settleDispatchedRequest(service, branch.actorId, request.requestId);
    return jsonResponse({
      kind: "redirect",
      reason: validated.reason,
      offered: validated.offered,
      show_safety_resources: true,
    });
  }

  const commitResult = await service.rpc("commit_ai_session_ideas_turn", {
    p_worker_token: workerToken,
    p_request_id: request.requestId,
    p_user_instruction: request.userInstruction,
    p_reply_text: validated.reply_text,
    p_proposal: validated.suggested_planning_item,
  });
  if (commitResult.error) return errorResponse(sessionError("INTERNAL_ERROR"));
  const commit = (commitResult.data as Record<string, unknown>[] | null)?.[0];
  if (!commit) return errorResponse(sessionError("INTERNAL_ERROR"));

  return jsonResponse({
    kind: "answer",
    user_ordinal: commit.user_ordinal,
    attune_ordinal: commit.attune_ordinal,
    // Ruling 1's sanctioned invalidation mechanism: the client polls
    // this integer.
    session_revision: commit.session_revision,
    reply_text: validated.reply_text,
    suggested_planning_item: validated.suggested_planning_item,
    show_safety_resources: true,
  });
}

/// Nearby. TWO provider calls, and the only value that crosses between
/// them is the allowlisted category token -- isolation property (4).
///
/// READ THE PARAMETER LIST. `promptInputs` and `userPrompt` are the
/// GEMINI side; `location` is the MAPBOX side. They are separate
/// parameters, and nothing below combines them: the Gemini call
/// receives `userPrompt`, the Mapbox call receives `location` and a
/// `NearbyCategory`. The Mapbox return value is assigned to `places`
/// and never read again except to assemble the SERVER-OWNED reply text
/// and the staged source cards -- neither of which is a prompt, and
/// neither of which this function could turn into one, because
/// buildSessionUserPrompt will not accept a plain string.
async function dispatchNearby(
  service: SupabaseClient,
  branch: BranchContext,
  request: GenerateRequest,
  // The couple, for the cost ledger only (final review I-4).
  relationshipId: string,
  workerToken: string,
  systemPrompt: string,
  userPrompt: string,
  promptInputs: SessionPromptInputs,
  location: RequesterLocation,
): Promise<Response> {
  // --- Provider call 1: GEMINI. Receives the prompt, never the point.
  const gemini = branch.callGemini;
  const parsed = await gemini({
    promptId: `${SESSION_PROMPT_VERSION}_nearby_category`,
    attribution: { fn: "ai-sessions", relationshipId, userId: branch.actorId },
    systemPrompt,
    userPrompt,
    // §5.3: Gemini's Nearby output is "only a category ... or an
    // allowlisted refusal reason", so a small cap is correct and is
    // itself a bound on what can come back.
    maxOutputTokens: 100,
  });
  if (!parsed) {
    // ITEM A2.
    await settleDispatchedRequest(service, branch.actorId, request.requestId);
    return errorResponse(sessionError("PROVIDER_UNAVAILABLE"));
  }

  // A redirect is a legal Nearby output too (§5.3), and it short-
  // circuits BEFORE Mapbox: no category, no search.
  if ((parsed as Record<string, unknown>).kind === "redirect") {
    const validatedRedirect = validateSessionTurnOutput(
      parsed,
      collectQuotedSources(promptInputs),
    );
    if (!validatedRedirect || validatedRedirect.kind !== "redirect") {
      // ITEM A2.
      await settleDispatchedRequest(service, branch.actorId, request.requestId);
      return errorResponse(sessionError("RESULT_UNAVAILABLE"));
    }
    const redirectVerdict = checkOutputSafety(validatedRedirect);
    if (!redirectVerdict.allowed) {
      // ITEM A2 -- the same call, the same resulting row, as the
      // provider-failure and validator paths. See dispatchIdeas'
      // note on why that identity is the non-disclosure property.
      await settleDispatchedRequest(service, branch.actorId, request.requestId);
      return safetyRefusalResponse(redirectVerdict);
    }
    // ITEM B, the same reasoning as dispatchIdeas' redirect branch:
    // §5.3 as amended makes NO redirect durable, which puts it in the
    // commits-nothing class, which must settle. Identical call,
    // identical resulting row, as the provider-failure, validator and
    // safety paths above and below.
    await settleDispatchedRequest(service, branch.actorId, request.requestId);
    return jsonResponse({
      kind: "redirect",
      reason: validatedRedirect.reason,
      offered: validatedRedirect.offered,
      show_safety_resources: true,
    });
  }

  // THE ALLOWLIST CHOKEPOINT. validateNearbyCategoryOutput returns null
  // for ANY value outside the fixed six, and that null short-circuits
  // before searchMapboxCategory is reached. This is the ONLY value that
  // crosses from the Gemini side to the Mapbox side, and §2 permits it
  // by name ("except through the fixed six-category allowlist").
  const categoryOutput = validateNearbyCategoryOutput(parsed);
  if (!categoryOutput) {
    // ITEM A2. Note the settle happens AFTER the chokepoint refused, so
    // no Mapbox call was made -- settling does not change that.
    await settleDispatchedRequest(service, branch.actorId, request.requestId);
    return errorResponse(sessionError("RESULT_UNAVAILABLE"));
  }

  // --- Provider call 2: MAPBOX. Receives the category token and the
  // point. Its signature has no string parameter, so no prompt text,
  // no instruction, no source snippet and no id can be passed.
  const places = await branch.searchMapbox(categoryOutput.category, {
    latitude: location.latitude,
    longitude: location.longitude,
  });
  if (places === null) {
    // ITEM A2.
    await settleDispatchedRequest(service, branch.actorId, request.requestId);
    return errorResponse(sessionError("PROVIDER_UNAVAILABLE"));
  }

  // §5.3: "server-assembled text 1..2,000 plus zero to three source
  // cards ... Zero results is a deterministic no-results card." The
  // text is built HERE, by the server, from the category and the names
  // -- it is never model-written, and it is never a prompt.
  const replyText = buildNearbySessionReplyText(
    categoryOutput.category,
    places,
  );

  // SAFETY PASS 2 on the server-assembled text and on every source
  // card's display string. §8.1's "every output field", and §5.3's
  // "Output checks cover prose, proposals and SOURCE DISPLAY STRINGS."
  for (
    const field of [
      replyText,
      ...places.flatMap((place) => [place.name, place.formatted_address ?? ""]),
    ]
  ) {
    const verdict = classifySessionContent(field);
    if (!verdict.allowed) {
      // ITEM A2. Nothing is staged on this path, so the settle is the
      // only state change a refused Nearby generation makes -- and it
      // is the same change a Mapbox failure makes.
      await settleDispatchedRequest(service, branch.actorId, request.requestId);
      return safetyRefusalResponse(verdict);
    }
  }

  const stageResult = await service.rpc("stage_ai_session_nearby_result", {
    p_worker_token: workerToken,
    p_request_id: request.requestId,
    p_reply_text: replyText,
    // The card shape §5.3 requires, assembled server-side. Full
    // validation of its bounds (name <=160, address <=240, HTTPS URL
    // <=2,048) is Task 9 per the plan's own self-review; this task
    // stages what searchMapboxCategory already bounds.
    p_sources: places,
  });
  if (stageResult.error) return errorResponse(sessionError("INTERNAL_ERROR"));

  // §5.3 / §2: the result "remain[s] requester-only staging until
  // requester explicitly publishes that pair". publish_nearby is Task
  // 5's command; this returns the staged result to its requester.
  return jsonResponse({
    kind: "nearby_result",
    staged: true,
    request_id: request.requestId,
    reply_text: replyText,
    sources: places,
    show_safety_resources: true,
  });
}

/// SERVER-OWNED, deterministic, and never a prompt. §5.3: "Zero results
/// is a deterministic no-results card."
function buildNearbySessionReplyText(
  category: NearbyCategory,
  places: readonly PlaceSource[],
): string {
  if (places.length === 0) {
    return `No ${category} results came back nearby. Try a different category.`;
  }
  return `Here are a few ${category} options nearby: ${
    places.map((place) => place.name).join(", ")
  }`;
}


// ---------------------------------------------------------------------------
// Branch: 'approve' -- spec §3.2, §4.3. Rulings 13 + 22.
//
// ONE command, not two. §4.1 names "approve/start" as a pair and
// SESSION_COMMANDS' own note records why they are one: approving IS
// what activates (§3.2 "Private creator approves ... then activates"),
// and splitting them would let a client approve and never activate,
// leaving a shared session that both partners approved stuck in
// `preparing` until its deadline.
//
// So this branch calls approve_ai_session_context and THEN
// activate_ai_session, and reports which happened. For a PRIVATE
// session the pair completes in one call; for a SHARED one the first
// partner's call approves and activate reports APPROVAL_REQUIRED
// (returned as `approved: true, activated: false`, not an error -- the
// caller did exactly what it was asked to and is waiting for its
// partner), and the second partner's call activates.
//
// WHAT THIS BRANCH ASSERTS ABOUT THE DIGEST, AND WHY IT IS NOT A
// RECOMPUTATION (Ruling 22 sharpening Ruling 13).
//
// Ruling 13 required "Task 5's read/approve path must assert the
// approved digest is computed over the stored rows". Task 4 then
// MEASURED that full recomputation from the stored rows is impossible
// today, for three reasons: prepare_ai_session stores
// left(content, 4000) while the digest binds §4.2's 600-scalar-clipped
// snippets with the " [truncated]" marker, and ai_session_sources
// carried neither civil_day_start_utc nor utc_offset_minutes -- both of
// which buildDigestPreimage bound.
//
// Ruling 35 (N3) removed the latter two from the pre-image, so two of
// those three blockers are gone. The FIRST one remains and is still
// decisive: review_context hashes the target's snippet as the stored
// 4000-char `approved_clipped_text` but hashes the WINDOW's snippets as
// selectSharedWindow computed them LIVE, under the 600-scalar
// per-message cap and the 2400-scalar total budget that clips the final
// entry. Those budget-clipped strings are not what any column holds, so
// a recomputation would have to re-run the live window selection -- the
// one thing §4.2 forbids on subsequent turns.
//
// Ruling 22's instruction is therefore still EXISTENCE/VERSION
// REVALIDATION, not recompute-and-compare.
//
// That is what revalidateFrozenSourcesForApproval does, and it reads
// THE FROZEN STORED ROWS and nothing else:
//
//   * loadFrozenSources reads ai_session_sources -- source_message_id,
//     source_version, approved_clipped_text -- for this session.
//   * frozenSourcesStillValid compares those ids and versions against
//     public.messages' deleted_at and COALESCE(edited_at, created_at).
//
// NO WINDOW QUERY RUNS ON THIS PATH. selectSharedWindow is not called,
// so nothing the civil day has gained or lost since prepare time can
// change the answer -- which is exactly §4.2's "Persist source IDs,
// versions and snapshot time, NOT NEW SELECTIONS on subsequent turns".
// The same two functions `generate` uses, deliberately: a second
// revalidation implementation is the thing that could disagree.
//
// It runs BEFORE approve_ai_session_context, not after: §4.3 says an
// edit or tombstone makes the session "unavailable and terminate[s]
// it", and storing an approval over a snapshot already known to have
// moved would be recording consent to context that no longer exists.
// ---------------------------------------------------------------------------

/// §4.3's "revalidate membership, consent and source existence/version
/// against the frozen snapshot", for the approval path.
///
/// Returns `null` on an internal failure, `false` when the frozen
/// snapshot has moved, `true` when every frozen source is still present
/// at the version that was frozen.
async function frozenSnapshotStillApprovable(
  service: SupabaseClient,
  sessionId: string,
  relationshipId: string,
): Promise<boolean | null> {
  // THE FROZEN STORED ROWS. Not a re-selection: the same
  // loadFrozenSources `generate` calls, reading ai_session_sources.
  const frozen = await loadFrozenSources(service, sessionId);
  if (frozen === null) return null;
  // A session with no sources at all (no target, window off) has
  // nothing to revalidate and is approvable -- the digest over an
  // empty source list is still a digest both partners must agree on,
  // and review_context computes it the same way for both.
  if (frozen.length === 0) return true;
  return await frozenSourcesStillValid(service, relationshipId, frozen);
}

async function handleApprove(branch: BranchContext): Promise<Response> {
  // §4.1: "All non-generation commands have separate bounded schemas."
  const allowed = new Set([
    "command",
    "session_id",
    "revision",
    "digest",
    "policy_version",
  ]);
  for (const key of Object.keys(branch.body)) {
    if (!allowed.has(key)) {
      return errorResponse(sessionError("INVALID_INPUT"));
    }
  }
  const sessionId = branch.body.session_id;
  const revision = branch.body.revision;
  const digest = branch.body.digest;
  const policyVersion = branch.body.policy_version;
  if (!isCanonicalUuid(sessionId)) {
    return errorResponse(sessionError("INVALID_INPUT"));
  }
  if (
    typeof revision !== "number" || !Number.isInteger(revision) || revision < 1
  ) {
    return errorResponse(sessionError("INVALID_INPUT"));
  }
  // The digest is an opaque hex string the client echoes back from
  // review_context. Bounded by SHAPE, not merely by length: a client
  // that sends a truncated or re-cased digest must be refused here
  // rather than storing a value activate_ai_session will later compare
  // unequal, which would read to the user as "my partner changed the
  // context".
  if (typeof digest !== "string" || !/^[0-9a-f]{64}$/.test(digest)) {
    return errorResponse(sessionError("INVALID_INPUT"));
  }
  // §4.3 binds the policy version into the digest, and
  // approve_ai_session_context stores it alongside. It is NOT defaulted
  // to a constant here: the brief's own sketch passed p_policy_version:
  // "v1" literally, which would record every approval against a
  // version string the consent system does not own -- and after a
  // policy bump, two partners approving at different times would store
  // the same wrong constant and activate happily over stale consent.
  // The server's own current version is read below instead.
  if (policyVersion !== undefined && typeof policyVersion !== "string") {
    return errorResponse(sessionError("INVALID_INPUT"));
  }

  const service = branch.service();

  // THE SESSION IS RESOLVED SERVER-SIDE. kind, visibility, window and
  // the relationship all come from the ROW -- never from the body.
  const session = await service
    .from("ai_sessions")
    .select(
      "id, relationship_id, creator_id, kind, visibility, state, revision, include_window, preparation_deadline",
    )
    .eq("id", sessionId)
    .maybeSingle();
  if (session.error) return errorResponse(sessionError("INTERNAL_ERROR"));
  const row = session.data as Record<string, unknown> | null;
  // §3.1: "Foreign, ended, expired and unauthorized session IDs return
  // the same unavailable response."
  if (!row) return errorResponse(sessionError("UNAVAILABLE"));

  const relationshipId = row.relationship_id as string;
  const kind = row.kind as string;
  const visibility = row.visibility as string;
  const includeWindow = row.include_window === true;

  const eligibility = await checkEligibility(
    service,
    // THE ACTOR COMES FROM THE VERIFIED USER.
    branch.actorId,
    relationshipId,
    capabilitiesForSession(kind, visibility, includeWindow),
  );
  if (!eligibility.ok) return errorResponse(eligibility.error);

  // §5.1: "Server read-time expiry is authoritative even before
  // cleanup."
  if (row.state !== "preparing") {
    // An ALREADY-ACTIVE session is reported as activated rather than
    // refused: a client retrying its own approve after a dropped
    // response must not be told its session is unavailable. Any other
    // state is §3.1's indistinguishable response.
    if (row.state === "active") {
      return jsonResponse({ approved: true, activated: true, state: "active" });
    }
    return errorResponse(sessionError("UNAVAILABLE"));
  }
  const deadline = new Date(row.preparation_deadline as string);
  if (!(deadline.getTime() > branch.now.getTime())) {
    return errorResponse(sessionError("UNAVAILABLE"));
  }

  // RULINGS 13 + 22: ASSERT AGAINST THE FROZEN STORED ROWS, BEFORE
  // STORING AN APPROVAL. Existence and version, from
  // ai_session_sources, compared against public.messages -- no window
  // query, no recomputation (see this section's header for why
  // recomputation is impossible today and why §4.3 does not ask for
  // it).
  const snapshotValid = await frozenSnapshotStillApprovable(
    service,
    sessionId,
    relationshipId,
  );
  if (snapshotValid === null) {
    return errorResponse(sessionError("INTERNAL_ERROR"));
  }
  if (!snapshotValid) {
    // §4.3: "Edits, tombstones or removal make the session unavailable
    // and terminate it; do not use stale copies or substitute new
    // messages." Identical disposition to `generate`'s own
    // revalidation failure, deliberately -- the two paths must not
    // disagree about what a moved snapshot means.
    await service.rpc("end_ai_session", {
      p_actor_id: branch.actorId,
      p_session_id: sessionId,
    });
    return errorResponse(sessionError("CONTEXT_CHANGED"));
  }

  // The policy version the APPROVAL IS RECORDED AGAINST is the server's
  // own current one, never a client literal. If the client supplied one
  // it must MATCH -- a mismatch means the client reviewed under a
  // policy that has since been superseded, which is a context change,
  // not something to silently overwrite.
  const currentPolicy = await service.rpc(
    "ai_current_consent_policy_version",
    {},
  );
  if (currentPolicy.error) {
    return errorResponse(sessionError("INTERNAL_ERROR"));
  }
  const policyRow = currentPolicy.data?.[0] as
    | Record<string, unknown>
    | undefined;
  const policy = policyRow?.ai_current_consent_policy_version;
  if (typeof policy !== "string") {
    return errorResponse(sessionError("INTERNAL_ERROR"));
  }
  if (policyVersion !== undefined && policyVersion !== policy) {
    return errorResponse(sessionError("CONTEXT_CHANGED"));
  }

  const approved = await service.rpc("approve_ai_session_context", {
    // THE ACTOR COMES FROM THE VERIFIED USER, never the body.
    p_actor_id: branch.actorId,
    p_session_id: sessionId,
    p_revision: revision,
    p_digest: digest,
    p_policy_version: policy,
  });
  if (approved.error) {
    const message = String(approved.error.message ?? "");
    // The RPC's single refusal covers three cases at once ("Session not
    // found, not preparing, or revision mismatch"). Membership and
    // state were already established above, so reaching here with that
    // message means the REVISION moved -- which is §10's
    // CONTEXT_CHANGED ("no automatic retry or new context"), the code
    // whose remedy is re-reviewing. A toggle (Item A1) is exactly what
    // moves it.
    if (/revision mismatch/i.test(message)) {
      return errorResponse(sessionError("CONTEXT_CHANGED"));
    }
    if (/Not a current member/i.test(message)) {
      return errorResponse(sessionError("UNAVAILABLE"));
    }
    return errorResponse(sessionError("UNAVAILABLE"));
  }

  // §4.1's "approve/start": activation is attempted in the same
  // command. A shared session's FIRST approver legitimately cannot
  // activate yet.
  const activated = await service.rpc("activate_ai_session", {
    p_actor_id: branch.actorId,
    p_session_id: sessionId,
    p_revision: revision,
  });
  if (activated.error) {
    const message = String(activated.error.message ?? "");
    if (/APPROVAL_REQUIRED/.test(message)) {
      // NOT an error: this caller approved successfully and is waiting
      // for its partner. §10's APPROVAL_REQUIRED is for a caller that
      // tried to GENERATE without approval; reporting it here would
      // tell a partner who did everything right that they failed.
      return jsonResponse({
        approved: true,
        activated: false,
        state: "preparing",
      });
    }
    if (/CONTEXT_CHANGED/.test(message)) {
      // The two approvers' digests differ -- §4.3's own invalidation
      // case. The message deliberately does NOT say whose digest
      // differed or what it was.
      return errorResponse(sessionError("CONTEXT_CHANGED"));
    }
    if (/Revision mismatch/i.test(message)) {
      return errorResponse(sessionError("CONTEXT_CHANGED"));
    }
    return errorResponse(sessionError("UNAVAILABLE"));
  }
  const activationRow =
    (activated.data as Record<string, unknown>[] | null)?.[0];
  return jsonResponse({
    approved: true,
    activated: activationRow?.activated === true,
    state: activationRow?.state ?? "preparing",
  });
}

// ---------------------------------------------------------------------------
// Branch: 'review_context' companion -- the §4.3 WINDOW TOGGLE.
//
// Item A1's set_ai_session_include_window, wired in behind `approve`
// and `review_context` as the spec requires: §4.3's window toggle is
// part of the review-and-approve loop, not a command of its own (§4.1's
// command list has nine entries and none of them is "toggle"). A client
// sets the window while reviewing, re-reviews to get the new
// revision/digest, then approves.
//
// Exposed as an OPTIONAL field on review_context rather than as a tenth
// command, because the two acts are inseparable in the protocol: the
// toggle invalidates approvals and bumps the revision, so the ONLY
// useful thing to do after it is re-read the context -- which is what
// review_context does. Making it a separate command would guarantee a
// client that toggled and then approved against the stale revision it
// still held.
// ---------------------------------------------------------------------------

/// Applies §4.3's window toggle, if this review_context call asked for
/// one. Returns an error to surface, or null to continue reviewing.
async function applyWindowToggle(
  branch: BranchContext,
  service: SupabaseClient,
  sessionId: string,
  relationshipId: string,
  targetMessageId: string | null,
  offset: number,
  requested: boolean,
): Promise<SessionError | null> {
  // SELECTION STAYS IN TYPESCRIPT -- the same selectSharedWindow
  // `prepare` uses, at the same one server instant. The RPC persists
  // WHICH messages were selected and re-reads their text itself; it
  // never receives text (Item A1's header, and prepare's).
  let windowMessageIds: string[] = [];
  if (requested) {
    try {
      const window = await selectSharedWindow(
        service,
        relationshipId,
        // §4.2 item 3: the window excludes the selected target.
        targetMessageId,
        offset,
        branch.now,
      );
      windowMessageIds = window.map((message) => message.messageId);
    } catch {
      return sessionError("INTERNAL_ERROR");
    }
  }

  const toggled = await service.rpc("set_ai_session_include_window", {
    // THE ACTOR COMES FROM THE VERIFIED USER, never the body.
    p_actor_id: branch.actorId,
    p_session_id: sessionId,
    p_include_window: requested,
    p_window_message_ids: requested ? windowMessageIds : null,
  });
  if (toggled.error) {
    const message = String(toggled.error.message ?? "");
    // An ACTIVE session refuses (Item A1's decision: a refusal, never a
    // silent no-op, because §4.2 forbids new selections against a
    // frozen snapshot). Mapped to §3.1's indistinguishable response, so
    // the state-specific SQL message never reaches a client.
    if (/not preparing/i.test(message)) {
      return sessionError("UNAVAILABLE");
    }
    if (/Session unavailable/i.test(message)) {
      return sessionError("UNAVAILABLE");
    }
    // 'A recent window requires a shared Ideas session', 'At most six
    // window messages', 'Window messages supplied with
    // p_include_window false', 'The selected target cannot also be a
    // window message' -- all caller-shape refusals.
    return sessionError("INVALID_INPUT");
  }
  return null;
}

// ---------------------------------------------------------------------------
// Branch: 'read' -- spec §4.1, §7.2.
//
// THE DELIBERATE SILENCE IS PRESERVED, AND IT IS THE WHOLE POINT.
//
// read_ai_session_turns and read_ai_session_staging both RETURN (zero
// rows) rather than raising on every unauthorized outcome -- unknown
// session, non-member, withdrawn consent, a shared session this actor
// never approved, an expired staging row. 20260953100000's header calls
// this out, and Contract 9 asserts the live body contains no RAISE
// EXCEPTION at all, precisely so a "consistency" refactor cannot turn
// the RPC into an existence oracle: a partner's zero rows and a
// stranger's zero rows must be byte-identical.
//
// SO THIS BRANCH MUST NOT CONVERT ZERO ROWS INTO A DISTINGUISHABLE
// ERROR. It returns HTTP 200 with an empty `turns` array for all of
// them. An UNAVAILABLE here would hand back exactly the oracle the SQL
// was written to deny -- "404 means no such session, 200-with-nothing
// means it exists but you cannot see it" -- and would do it for the one
// command whose whole job is reading.
//
// The eligibility gate is deliberately NOT run before the RPC either.
// It raises distinguishable codes (FEATURE_DISABLED, UNAVAILABLE,
// CONSENT_REQUIRED) and running it here would reintroduce the
// distinction at the edge that the RPC removes in SQL. The RPC enforces
// membership, consent, state, expiry and per-visibility authorization
// itself -- that is what "narrow authorized read RPCs" in §7.2 means --
// so the gate would add no enforcement, only a side channel.
//
// ONE EXCEPTION, and it is not an oracle: a TRANSPORT error (the RPC
// could not be called at all) is INTERNAL_ERROR. That is a statement
// about this server, not about the session, and it is reachable with
// any session id including a nonexistent one.
// ---------------------------------------------------------------------------
async function handleRead(branch: BranchContext): Promise<Response> {
  const allowed = new Set(["command", "session_id", "request_id"]);
  for (const key of Object.keys(branch.body)) {
    if (!allowed.has(key)) {
      return errorResponse(sessionError("INVALID_INPUT"));
    }
  }
  const sessionId = branch.body.session_id;
  const requestId = branch.body.request_id;
  if (!isCanonicalUuid(sessionId)) {
    return errorResponse(sessionError("INVALID_INPUT"));
  }
  // The staged Nearby result is read by REQUEST id, and only when the
  // caller asks for one -- read_ai_session_staging is author-checked
  // (§7.2: "own staged Nearby reachable ONLY through an author-checking
  // RPC") and its silence is the same property.
  if (requestId !== undefined && !isCanonicalUuid(requestId)) {
    return errorResponse(sessionError("INVALID_INPUT"));
  }

  const service = branch.service();

  const turns = await service.rpc("read_ai_session_turns", {
    // THE ACTOR COMES FROM THE VERIFIED USER, never the body. This is
    // the ONLY authorization input the RPC gets, and it is why the RPC
    // can be silent: it knows exactly who is asking.
    p_actor_id: branch.actorId,
    p_session_id: sessionId,
  });
  // A transport failure is about THIS SERVER, not about the session --
  // see the header. Everything else, including "you may not see this",
  // is zero rows and HTTP 200.
  if (turns.error) return errorResponse(sessionError("INTERNAL_ERROR"));
  const turnRows = (turns.data ?? []) as Record<string, unknown>[];

  let staging: Record<string, unknown>[] = [];
  if (typeof requestId === "string") {
    const staged = await service.rpc("read_ai_session_staging", {
      p_actor_id: branch.actorId,
      p_request_id: requestId,
    });
    if (staged.error) return errorResponse(sessionError("INTERNAL_ERROR"));
    staging = (staged.data ?? []) as Record<string, unknown>[];
  }

  // PROJECTED, not echoed. The RPC returns SETOF
  // public.ai_session_turns, whose columns include session_id and
  // request_id -- server bookkeeping a client has no use for and §2
  // keeps out of responses where it can. What a client needs to render
  // a transcript is the ordinal, who wrote it, its kind and its
  // payload.
  return jsonResponse({
    turns: turnRows.map((turn) => ({
      ordinal: turn.ordinal,
      role: turn.role,
      kind: turn.kind,
      payload: turn.payload,
      created_at: turn.created_at,
    })),
    // Absent rather than empty when no request_id was asked for, so a
    // client can tell "I did not ask" from "I asked and there is
    // nothing" -- a distinction about the CALLER'S OWN REQUEST, not
    // about anyone's authorization.
    staged: typeof requestId === "string"
      ? staging.map((stagedRow) => ({
        request_id: stagedRow.request_id,
        reply_text: stagedRow.reply_text,
        sources: stagedRow.sources,
        expires_at: stagedRow.expires_at,
      }))
      : undefined,
  });
}

// ---------------------------------------------------------------------------
// Branch: 'read_state' -- spec §4.3, §6.1 (as amended), §6.2, §7.2.
//
// THE POLLED SURFACE. §6.1 was amended for Plan D: polling
// `session_revision` is the sanctioned invalidation mechanism and
// Realtime Broadcast is out of scope, so this is what the client polls.
// Migration 20260953200600 carries the full argument for why a new
// gated RPC rather than an extra field on `read` -- in short, because
// read_ai_session_turns' gate refuses `state != 'active'`, so a
// revision bolted onto THAT response would be absent during exactly the
// preparing -> active wait the poll exists to observe.
//
// RULING 6 GOVERNS THE RESPONSE SHAPE. It returns `revision` and
// `state` and NOTHING ELSE. Both are unmoved by a safety refusal (a
// refusal settles the REQUEST row and returns; it never reaches
// commit_ai_session_ideas_turn, so the `revision = revision + 1` bump
// never runs and the session stays `active`). `attempt_count` and
// `last_admitted_at` are NOT reported and must never be added: a
// refusal is ADMITTED before it is refused, so either field would move
// on a refusal when the revision did not -- which is the disclosure
// this branch's own sibling comment at handleGenerate's redirect names
// ("bumping the revision for 'unsupported' but not 'unsafe_to_assist'
// discloses the detector to a partner polling session_revision -- §8.1
// forbids exactly that").
//
// SILENT, EXACTLY LIKE handleRead, AND FOR THE SAME REASON. The RPC
// returns zero rows for an unknown session, a non-member, withdrawn
// consent, an expired session and a shared session this actor never
// approved -- byte-identically. This branch converts NONE of them into
// a distinguishable error: it answers HTTP 200 with `{state: null}`.
// An UNAVAILABLE here would be the existence oracle §7.2 and
// read_ai_session_turns' header exist to deny, and it would be worse on
// a POLLED surface than on a one-shot read, because a poll probes
// repeatedly and for free.
//
// The eligibility gate is deliberately NOT run first, the same choice
// handleRead makes: it raises distinguishable codes (FEATURE_DISABLED,
// UNAVAILABLE, CONSENT_REQUIRED) and running it here would reintroduce
// at the edge the distinction the RPC removes in SQL. The RPC enforces
// membership, consent, expiry and per-visibility authorization itself.
//
// ONE EXCEPTION, and it is not an oracle: a TRANSPORT error (the RPC
// could not be called at all) is INTERNAL_ERROR -- a statement about
// this server, reachable with any session id including a fake one.
// ---------------------------------------------------------------------------
async function handleReadState(branch: BranchContext): Promise<Response> {
  const allowed = new Set(["command", "session_id"]);
  for (const key of Object.keys(branch.body)) {
    if (!allowed.has(key)) {
      return errorResponse(sessionError("INVALID_INPUT"));
    }
  }
  const sessionId = branch.body.session_id;
  if (!isCanonicalUuid(sessionId)) {
    return errorResponse(sessionError("INVALID_INPUT"));
  }

  const state = await branch.service().rpc("read_ai_session_state", {
    // THE ACTOR COMES FROM THE VERIFIED USER, never the body -- the
    // only authorization input the RPC gets, and why it can be silent.
    p_actor_id: branch.actorId,
    p_session_id: sessionId,
  });
  if (state.error) return errorResponse(sessionError("INTERNAL_ERROR"));

  const row = (state.data as Record<string, unknown>[] | null)?.[0];
  // NULLS, NOT AN ERROR AND NOT AN OMITTED KEY. Both keys are always
  // present so the client parses one shape and reads `state: null` as
  // "no answer" -- never as "the session ended", which is reported
  // EXPLICITLY as `closed` and only ever that way.
  return jsonResponse({
    revision: row === undefined ? null : row.revision,
    state: row === undefined ? null : row.state,
  });
}

// ---------------------------------------------------------------------------
// Branch: 'publish_nearby' -- spec §5.3, §8.1, §8.2.2.
//
// TASK 4'S SAFETY ORDERING IS THE PRECEDENT AND IS NOT LOOSENED.
//
// §8.1 requires a deterministic check "BEFORE PUBLISHING ON EVERY
// OUTPUT FIELD". `generate` already ran safety pass 2 over the
// server-assembled reply text and every place name and address before
// staging. This command is a SECOND, LATER request -- a different HTTP
// call, possibly minutes later -- that turns a requester-only staged
// result into a shared transcript pair. So the check runs AGAIN here,
// on the stored staged fields, BEFORE publish_ai_session_nearby_result
// commits anything.
//
// Re-running it is not belt-and-braces. Three reasons it is load-bearing:
//
//   * The safety corpus is VERSIONED (ai_session_safety.ts). A phrase
//     added between the stage and the publish must stop the publish;
//     otherwise the staging window is a two-minute hole in the corpus.
//   * Publishing is the act that makes content visible TO THE PARTNER.
//     §8.1's constraint is about what gets published, and the stage
//     published nothing.
//   * The rows are read back from the DATABASE here, not held in
//     memory from the generate call, so this check is over what will
//     actually be committed rather than over what was once validated.
//
// The check is BEFORE the RPC, never after: the RPC commits the
// transcript pair, deletes the staging row and bumps the revision in
// one transaction, so a check afterwards would be checking content the
// partner can already see.
//
// share_ai_session_turn STAYS UNREACHABLE WITHOUT A COMMITTED TURN --
// and for a Nearby result it stays unreachable entirely: the RPC's own
// allowlist refuses any kind but 'ideas_answer' ("Allow-list, not a
// deny-list ... 'nearby_result' has its own requester-only publish
// path"). So this branch cannot be a back door into chat.
// ---------------------------------------------------------------------------
async function handlePublishNearby(branch: BranchContext): Promise<Response> {
  const allowed = new Set(["command", "request_id"]);
  for (const key of Object.keys(branch.body)) {
    if (!allowed.has(key)) {
      return errorResponse(sessionError("INVALID_INPUT"));
    }
  }
  const requestId = branch.body.request_id;
  if (!isCanonicalUuid(requestId)) {
    return errorResponse(sessionError("INVALID_INPUT"));
  }

  const service = branch.service();

  // AN ALREADY-COMMITTED PUBLISH IS AN IDEMPOTENT REPLAY, and it must
  // reach the RPC rather than being refused here.
  //
  // FOUND BY A TEST, AND IT WAS A REAL BUG IN MY FIRST ORDERING. The
  // safety pre-read below reads ai_session_staging, which
  // publish_ai_session_nearby_result DELETES on success -- so a second
  // publish of the same request found no staged row and returned
  // RESULT_UNAVAILABLE, converting a legitimate retry-after-a-dropped-
  // response into a failure. The RPC answers a replay from its own
  // `v_request.state = 'committed'` branch, deliberately placed BEFORE
  // its consent gate for exactly this reason (20260953180000's note:
  // "a retry of a publish that already succeeded must return its
  // original answer rather than raise ... and could drive a caller to
  // publish again").
  //
  // SKIPPING THE SAFETY PASS HERE IS CORRECT, NOT A LOOSENING, and the
  // reason is that there is nothing left to gate: the content is
  // ALREADY in the transcript and already visible to the partner. The
  // pass exists to decide whether to publish; on this path the publish
  // happened, and the only thing the RPC does is re-report the
  // ordinals of a write that is already durable. Re-checking would
  // either (a) pass, changing nothing, or (b) refuse, reporting failure
  // for content the partner can already see while committing nothing --
  // which tells the caller something false and leaves the transcript
  // exactly as it was.
  const requestState = await service
    .from("ai_session_requests")
    .select("state")
    .eq("id", requestId)
    .maybeSingle();
  if (requestState.error) {
    return errorResponse(sessionError("INTERNAL_ERROR"));
  }
  const alreadyCommitted =
    (requestState.data as Record<string, unknown> | null)?.state ===
      "committed";

  // THE PRE-PUBLISH SAFETY PASS, over the STAGED fields, read back
  // through the AUTHOR-CHECKED RPC (§7.2) rather than with a direct
  // table read -- so an actor who is not the staging row's author
  // cannot even cause the safety check to run over someone else's
  // content, and the "no staged result" answer stays the RPC's silent
  // one.
  const staged = alreadyCommitted
    ? { error: null, data: [] as Record<string, unknown>[] }
    : await service.rpc("read_ai_session_staging", {
      // THE ACTOR COMES FROM THE VERIFIED USER, never the body.
      p_actor_id: branch.actorId,
      p_request_id: requestId,
    });
  if (staged.error) return errorResponse(sessionError("INTERNAL_ERROR"));
  const stagedRow = (staged.data ?? [])[0] as
    | Record<string, unknown>
    | undefined;
  if (!stagedRow && !alreadyCommitted) {
    // §10: RESULT_UNAVAILABLE -> "expired/revoked result; never replay
    // provider". Covers a staged row that expired, was already
    // published, was discarded, or belongs to someone else -- ONE
    // response for all four, which is the same indistinguishability
    // §3.1 requires of session ids. Note this does NOT weaken the
    // RPC's silence: the RPC still returned zero rows without saying
    // which case it was, and this branch collapses every case to one
    // code rather than branching on it.
    return errorResponse(sessionError("RESULT_UNAVAILABLE"));
  }

  // §8.1's "every output field", and §5.3's "Output checks cover prose,
  // proposals and SOURCE DISPLAY STRINGS": the reply text plus every
  // card's name and address.
  const stagedFields: string[] = stagedRow
    ? [String(stagedRow.reply_text ?? "")]
    : [];
  const sources = stagedRow?.sources;
  if (Array.isArray(sources)) {
    for (const source of sources) {
      const card = source as Record<string, unknown>;
      if (typeof card?.name === "string") stagedFields.push(card.name);
      if (typeof card?.formatted_address === "string") {
        stagedFields.push(card.formatted_address);
      }
    }
  }
  for (const field of stagedFields) {
    const verdict = classifySessionContent(field);
    if (!verdict.allowed) {
      // NOTHING IS COMMITTED. The staged row is left alone (the
      // requester may still discard it), no transcript pair exists, and
      // ai_sessions.revision is NOT bumped -- so the partner sees
      // exactly what they see when the requester simply never
      // published: the same integer. Identical body and status to
      // every other refusal, built from the same verdict-only helper,
      // so which field tripped it is not observable.
      return safetyRefusalResponse(verdict);
    }
  }

  // Only now. The RPC takes the relationship advisory lock, the session
  // row and the request row, re-checks membership and consent under
  // them, commits the pair, deletes the staging row, marks the request
  // committed and bumps the revision -- one transaction, after both
  // safety passes.
  const published = await service.rpc("publish_ai_session_nearby_result", {
    p_actor_id: branch.actorId,
    p_request_id: requestId,
  });
  if (published.error) {
    const message = String(published.error.message ?? "");
    if (/consent is not current/i.test(message)) {
      return errorResponse(sessionError("CONSENT_REQUIRED"));
    }
    if (/Not a current member/i.test(message)) {
      return errorResponse(sessionError("UNAVAILABLE"));
    }
    if (/Session unavailable/i.test(message)) {
      return errorResponse(sessionError("UNAVAILABLE"));
    }
    // 'No staged result for this request', 'Staged result has expired',
    // 'Only the requester may publish a staged Nearby result',
    // 'Request not found' -- all RESULT_UNAVAILABLE, one response, for
    // the same reason the zero-row case above is.
    return errorResponse(sessionError("RESULT_UNAVAILABLE"));
  }
  const row = (published.data as Record<string, unknown>[] | null)?.[0];
  if (!row) return errorResponse(sessionError("INTERNAL_ERROR"));
  return jsonResponse({
    committed: row.committed === true,
    user_ordinal: row.user_ordinal,
    attune_ordinal: row.attune_ordinal,
    // Ruling 1's sanctioned invalidation mechanism: the client polls
    // this integer, and so does the partner.
    session_revision: row.session_revision,
  });
}

// ---------------------------------------------------------------------------
// Branch: 'discard_nearby' -- spec §8.2.2.
//
// The requester throwing away their own staged result. Terminal and
// COUNTED, never a quota release: the RPC's own comment records why
// (the row reached 'staged' only via claim_ai_session_dispatch, so the
// write-once provider marker is set and the call was really made).
// This branch neither adds nor relaxes that.
// ---------------------------------------------------------------------------
async function handleDiscardNearby(branch: BranchContext): Promise<Response> {
  const allowed = new Set(["command", "request_id"]);
  for (const key of Object.keys(branch.body)) {
    if (!allowed.has(key)) {
      return errorResponse(sessionError("INVALID_INPUT"));
    }
  }
  const requestId = branch.body.request_id;
  if (!isCanonicalUuid(requestId)) {
    return errorResponse(sessionError("INVALID_INPUT"));
  }

  const service = branch.service();
  const discarded = await service.rpc("discard_ai_session_nearby_staging", {
    // THE ACTOR COMES FROM THE VERIFIED USER, never the body.
    p_actor_id: branch.actorId,
    p_request_id: requestId,
  });
  if (discarded.error) {
    const message = String(discarded.error.message ?? "");
    if (/Only the requester may discard/i.test(message)) {
      // RESULT_UNAVAILABLE, not a distinct "forbidden": a staged result
      // belonging to someone else must be indistinguishable from one
      // that never existed. The RPC is already silent for a missing
      // row (idempotent no-op), so mapping the foreign-actor raise to
      // the same code is what makes the two cases agree at the edge.
      return errorResponse(sessionError("RESULT_UNAVAILABLE"));
    }
    return errorResponse(sessionError("INTERNAL_ERROR"));
  }
  // IDEMPOTENT. The RPC returns silently for a row that was already
  // discarded, published or expired, and so does this: `discarded:
  // true` means "there is no staged result for this request id now",
  // which is the only thing the caller wanted. Reporting whether work
  // was actually done would tell a caller whether a staged result
  // existed, which for a foreign request id is the oracle the mapping
  // above exists to close.
  return jsonResponse({ discarded: true });
}

// ---------------------------------------------------------------------------
// Branch: 'end' -- spec §5.4.
//
// end_ai_session purges the transcript, the sources, the approvals and
// the staging rows SYNCHRONOUSLY in its own transaction, releases the
// quota of every never-dispatched request it cancels, and bumps the
// revision so the purge is observable. It is service_role only, it is
// idempotent, and it records NO ending actor anywhere (§5.4: no
// client-readable "ended_by" column exists, and none is added).
// ---------------------------------------------------------------------------
async function handleEnd(branch: BranchContext): Promise<Response> {
  const allowed = new Set(["command", "session_id"]);
  for (const key of Object.keys(branch.body)) {
    if (!allowed.has(key)) {
      return errorResponse(sessionError("INVALID_INPUT"));
    }
  }
  const sessionId = branch.body.session_id;
  if (!isCanonicalUuid(sessionId)) {
    return errorResponse(sessionError("INVALID_INPUT"));
  }

  const service = branch.service();
  const ended = await service.rpc("end_ai_session", {
    // THE ACTOR COMES FROM THE VERIFIED USER, never the body. The RPC
    // authorizes from it: the creator only for a private session,
    // either CURRENT member for a shared one.
    p_actor_id: branch.actorId,
    p_session_id: sessionId,
  });
  if (ended.error) {
    const message = String(ended.error.message ?? "");
    if (
      /Only the creator may end/i.test(message) ||
      /Not a member of this shared session/i.test(message)
    ) {
      // §3.1: a session the caller may not end is indistinguishable
      // from one that does not exist. The RPC is already a silent
      // no-op for an unknown or already-closed session, so collapsing
      // both authorization raises to UNAVAILABLE is what makes the
      // three cases agree.
      return errorResponse(sessionError("UNAVAILABLE"));
    }
    return errorResponse(sessionError("INTERNAL_ERROR"));
  }
  // IDEMPOTENT, and deliberately says nothing about whether there was
  // anything to end. `ended: true` means "this session is not running
  // now". §5.4 also forbids disclosing WHO ended it, and nothing here
  // could: the response has no actor field and the table has no
  // column.
  return jsonResponse({ ended: true });
}

// ---------------------------------------------------------------------------
// Branch: 'share_answer' -- spec §5.3, §8.1, and Plan A's send path.
//
// Posts a COMMITTED Attune 'ideas_answer' turn into ordinary chat, with
// attune_assist provenance, by delegating to share_ai_assist_draft
// through share_ai_session_turn.
//
// WHY THERE IS NO SAFETY PASS HERE, stated rather than left to be
// noticed: the only thing shareable is a turn that was ALREADY
// committed, and a turn can only be committed by
// commit_ai_session_ideas_turn, which `generate` reaches only after
// safety pass 2 passed over every output field. The RPC's allowlist
// (`kind != 'ideas_answer'` raises) is what makes that the only
// reachable shape -- a 'redirect' cannot be posted at all (§8.1) and a
// 'nearby_result' has its own requester-only publish path. So
// share_ai_session_turn is unreachable without a committed turn, which
// pass 2 gates, and re-checking content that is already in the
// transcript would check the wrong thing at the wrong time.
//
// ERROR MAPPING DISCLOSES NOTHING ABOUT WHICH CHECK REFUSED. The RPC
// and Plan A's send path together raise for: an unavailable session, a
// non-creator on a private session, a non-member on a shared one, a
// missing ordinal, a user-authored turn, a non-'ideas_answer' kind, and
// 'Consent required' from the send path. Every one of those collapses
// into §10's RESULT_UNAVAILABLE except consent -- which §10 gives its
// own code precisely because "caller can open consent" is a refusal the
// caller can ACT on, and withholding it would leave the user stuck with
// no remedy. That is the one distinction §10 sanctions by name; it
// discloses the CALLER'S OWN consent state, never a partner's
// withdrawal history, and never which safety or authorization check
// fired.
// ---------------------------------------------------------------------------
async function handleShareAnswer(branch: BranchContext): Promise<Response> {
  const allowed = new Set(["command", "session_id", "ordinal"]);
  for (const key of Object.keys(branch.body)) {
    if (!allowed.has(key)) {
      return errorResponse(sessionError("INVALID_INPUT"));
    }
  }
  const sessionId = branch.body.session_id;
  const ordinal = branch.body.ordinal;
  if (!isCanonicalUuid(sessionId)) {
    return errorResponse(sessionError("INVALID_INPUT"));
  }
  // ai_session_turns' own CHECK is `ordinal BETWEEN 1 AND 20`, so the
  // bound is enforced here rather than letting an out-of-range value
  // reach the RPC and come back as a generic "Turn not found" -- which
  // would make a client's own input error indistinguishable from a
  // turn that does not exist.
  if (
    typeof ordinal !== "number" || !Number.isInteger(ordinal) ||
    ordinal < 1 || ordinal > 20
  ) {
    return errorResponse(sessionError("INVALID_INPUT"));
  }

  const service = branch.service();
  const shared = await service.rpc("share_ai_session_turn", {
    // THE ACTOR COMES FROM THE VERIFIED USER, never the body. This is
    // the whole reason the RPC's grant moved to service_role (fix F2):
    // it takes its actor as a parameter, so an `authenticated` grant
    // let any client supply a victim's id. The actor here cannot be
    // anything but requireUser's verified user.
    p_actor_id: branch.actorId,
    p_session_id: sessionId,
    p_ordinal: ordinal,
  });
  if (shared.error) {
    const message = String(shared.error.message ?? "");
    // The ONE distinction §10 sanctions: the caller's own consent is
    // actionable. Plan A's send path raises 'Consent required'.
    if (/Consent required/i.test(message)) {
      return errorResponse(sessionError("CONSENT_REQUIRED"));
    }
    // Everything else is ONE response. A caller cannot tell whether the
    // session was closed, the ordinal was absent, the turn was
    // user-authored, the kind was unshareable, or they were not a
    // member -- which is §3.1's indistinguishability applied to a
    // share, and §8.1's "a refusal must not signal a private detector
    // result" applied to the kind allowlist.
    return errorResponse(sessionError("RESULT_UNAVAILABLE"));
  }
  const row = (shared.data as Record<string, unknown>[] | null)?.[0];
  if (!row) return errorResponse(sessionError("INTERNAL_ERROR"));
  // The RPC returns the whole public.messages row. ONLY THE ID IS
  // ECHOED: the message body is content the caller already has (it is
  // the turn they just shared), and the row carries analysis flags,
  // sort keys and provenance columns a client has no business reading
  // back out of a share.
  return jsonResponse({ message_id: row.id });
}

/// What requireUser(req) produced. There is no `client` field, unlike
/// ai-assist's AssistUserContext -- see this file's header note on why
/// this function has no user-scoped client.
export interface SessionUserContext {
  user: AuthenticatedUser;
}

serve((req) => handleRequest(req, {}));

/// The real HTTP entry point: authenticates via requireUser (real
/// server-side auth.getUser verification) and delegates. Mirrors
/// ai-assist's handleRequest/processAssistRequest split -- requireUser
/// needs a real signed JWT verified against a running GoTrue, which
/// this environment has no Docker to provide (see
/// user_scoped_client.test.ts's own note), so index.test.ts calls
/// processSessionCommand directly with a fabricated {user} context,
/// exactly as ai-assist/index.test.ts and ai_context_loader.test.ts do.
export async function handleRequest(
  req: Request,
  deps: SessionDeps,
): Promise<Response> {
  if (req.method === "OPTIONS") return jsonResponse({ ok: true });
  if (req.method !== "POST") {
    return errorResponse(sessionError("INVALID_INPUT"));
  }

  let user: AuthenticatedUser;
  try {
    user = await requireUser(req);
  } catch {
    // §3.1's "authenticated active account". Not a distinct §10 code:
    // §10 has no UNAUTHENTICATED, and 401 is already carried by the
    // HTTP layer for a missing/invalid token.
    return errorResponse(sessionError("INVALID_INPUT"));
  }
  return processSessionCommand(req, { user }, deps);
}

/// Exported for direct testing (see handleRequest's comment). This is
/// the whole request lifecycle EXCEPT the HTTP-layer JWT verification.
///
/// `userScoped` is the ONLY source of actor identity in this function.
/// The parsed body is passed to a branch for its own bounded schema, but
/// no branch may read an identity from it -- the envelope validator
/// rejects every actor-naming field before a branch sees the body, and
/// each branch receives `actorId` as a separate parameter.
export async function processSessionCommand(
  req: Request,
  userScoped: SessionUserContext,
  deps: SessionDeps,
): Promise<Response> {
  const actorId = userScoped.user.id;

  const rawText = await req.text().catch(() => "");
  const validated = validateCommandEnvelope(rawText);
  if (!validated.ok) {
    return errorResponse(validated.error);
  }
  const { body, command } = validated.envelope;

  // The context every branch Tasks 2-7 add will receive. Built here,
  // once, so that a branch CANNOT obtain an actor id any other way:
  // `actorId` is already resolved from the verified user, and `body`
  // arrives with every actor-naming field rejected. A branch that wanted
  // an actor from the body would have to reach past this struct to the
  // raw request, which review will see.
  //
  // The service client is constructed lazily: a command that is
  // recognized but refused (below) must not cost a connection.
  const branch: BranchContext = {
    actorId,
    body,
    service: () => deps.serviceClient ?? serviceRoleClient(),
    // ONE instant for the whole request (spec §4.2's "computed once
    // from server time"), captured here rather than read per-call so
    // the civil day, the window query bound and the digest all describe
    // the same moment even if the request spans a midnight boundary.
    now: deps.now ?? new Date(),
    callGemini: deps.callGemini ?? callGeminiJson,
    searchMapbox: deps.searchMapbox ?? searchMapboxCategory,
  };

  switch (command) {
    case "prepare":
      return await handlePrepare(branch);

    case "review_context":
      return await handleReviewContext(branch);

    case "generate":
      return await handleGenerate(branch);

    case "approve":
      return await handleApprove(branch);

    case "read":
      return await handleRead(branch);

    case "read_state":
      return await handleReadState(branch);

    case "publish_nearby":
      return await handlePublishNearby(branch);

    case "discard_nearby":
      return await handleDiscardNearby(branch);

    case "end":
      return await handleEnd(branch);

    case "share_answer":
      return await handleShareAnswer(branch);

    default:
      // Unreachable: validateCommandEnvelope already rejected anything
      // outside SESSION_COMMANDS. Kept so adding a command to that set
      // without a case here fails closed rather than falling through.
      return errorResponse(sessionError("INVALID_INPUT"));
  }
}

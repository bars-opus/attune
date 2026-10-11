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
  selectSharedWindow,
  WINDOW_ROW_CAP,
  type WindowMessage,
} from "../_shared/ai_session_context.ts";

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
  const allowed = new Set(["command", "session_id", "utc_offset_minutes"]);
  for (const key of Object.keys(branch.body)) {
    if (!allowed.has(key)) {
      return errorResponse(sessionError("INVALID_INPUT"));
    }
  }
  const sessionId = branch.body.session_id;
  const offset = branch.body.utc_offset_minutes;
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

  let window: WindowMessage[] = [];
  if (includeWindow) {
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
    utcOffsetMinutes: offset,
    civilDayStartUtc: civilDayStart,
    // §4.3: approvals are stored against a separate context_revision,
    // "frozen at activation". In preparing state the session's own
    // `revision` is what an approval is submitted against (Plan B's
    // approve_ai_session_context takes p_revision and matches
    // ai_sessions.revision), so that is what the digest binds.
    contextRevision: row.revision as number,
  });

  // §4.3: "The client submits revision/digest." Both are returned so
  // the client can echo them to `approve` without recomputing either.
  return jsonResponse({
    session_id: sessionId,
    revision: row.revision,
    policy_version: policy,
    kind,
    visibility,
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
  };

  switch (command) {
    case "prepare":
      return await handlePrepare(branch);

    case "review_context":
      return await handleReviewContext(branch);

    // Task 3 implements 'approve'.
    // Task 4 implements 'generate'.
    // Task 5 implements 'read', 'publish_nearby', 'discard_nearby',
    //                      'end' and 'share_answer'.
    case "approve":
    case "generate":
    case "read":
    case "publish_nearby":
    case "discard_nearby":
    case "end":
    case "share_answer":
      // A RECOGNIZED command with no branch yet is FEATURE_DISABLED, not
      // INVALID_INPUT. §10: FEATURE_DISABLED means "safe return to chat,
      // no new work" -- exactly the state of a capability whose §12 flag
      // was never seeded (see checkEligibility's note). INVALID_INPUT
      // would tell a correct client to edit a correct request, and would
      // make a recognized command indistinguishable from a typo.
      //
      // `branch` is deliberately not consulted yet: no branch exists, so
      // nothing may read the body or open a connection. Tasks 2-7
      // replace each case above with a call taking `branch`.
      void branch;
      return errorResponse(sessionError("FEATURE_DISABLED"));
    default:
      // Unreachable: validateCommandEnvelope already rejected anything
      // outside SESSION_COMMANDS. Kept so adding a command to that set
      // without a case here fails closed rather than falling through.
      return errorResponse(sessionError("INVALID_INPUT"));
  }
}

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
/// Two of §3.1's six checks are NOT implemented here, deliberately:
///   - "enabled capability": spec §12 requires six separate
///     server-authoritative flags (base Assist, Understand, private
///     Sessions, shared Sessions, recent-window, Nearby), defaults off.
///     Plan B seeded NONE of them -- verified by catalog query, there is
///     no ai_sessions row in public.feature_flags. Until the flags exist
///     the honest state of every command is disabled, which is why
///     dispatch below returns FEATURE_DISABLED for a recognized command
///     rather than proceeding. Reported as a plan gap.
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
): Promise<EligibilityResult> {
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
  };

  switch (command) {
    // Task 2 implements 'prepare' and 'review_context'.
    // Task 3 implements 'approve'.
    // Task 4 implements 'generate'.
    // Task 5 implements 'read', 'publish_nearby', 'discard_nearby',
    //                      'end' and 'share_answer'.
    case "prepare":
    case "review_context":
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

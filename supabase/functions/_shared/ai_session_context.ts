// Context-window selection and approval-digest computation for AI
// Sessions. Spec §4.2 (deterministic context selection and budgets),
// §4.3 (snapshot approval).
//
// Claimed by Plan C per Plan B's own self-review: Plan B's
// approve_ai_session_context stores an opaque digest string and
// activate_ai_session asserts `count(DISTINCT digest) = 1` across the
// approvers -- but NOTHING in Plan B produces that string, and nothing
// produces the clipped text its ai_session_sources rows hold. This
// module is what PRODUCES both, and only this module ever runs the
// window query.
//
// ===========================================================================
// THE ONE CONSTRAINT THAT SHAPES EVERY DECISION IN THIS FILE
// ===========================================================================
//
// Spec §4.3's shared-session approval is TWO separate calls, one per
// partner, at different wall-clock times, on different Edge instances.
// Plan B's activate_ai_session:
//
//     SELECT count(DISTINCT member_id), count(DISTINCT digest) ...
//     IF v_distinct_digests > 1 THEN
//       RAISE EXCEPTION 'CONTEXT_CHANGED -- approvers did not approve
//                         the same snapshot';
//
// So a digest that varies by so much as one byte between those two
// calls does not degrade the feature -- it makes a shared session
// PERMANENTLY unactivatable, and reports it as if the context had
// changed underneath the users. There is no retry that fixes it.
//
// Therefore every function here is a PURE function of its arguments.
// Specifically:
//
//   * `now` is a PARAMETER, never Date.now() read inside. A function
//     that reads the clock cannot be called twice with the same inputs,
//     so its determinism cannot even be stated, let alone tested.
//
//   * The civil day is computed with UTC getters (getUTCFullYear etc.)
//     on an offset-shifted instant, NEVER with getFullYear(). The local
//     getters resolve against the HOST's timezone: the same code on a
//     UTC Edge worker and a developer's UTC+1 laptop computes different
//     day boundaries for the same (now, offset) pair. See
//     civilDayStartUtc.
//
//   * Timestamps entering the digest are canonicalized to a FIXED
//     precision before hashing (canonicalTimestamp). This is not
//     fastidiousness; it is a measured defect. The same stored
//     timestamptz reaches this code in at least three renderings:
//
//       Postgres text/JSON:  2026-10-10T21:27:52.511438+00:00  (µs)
//       PostgREST -> JSON:   2026-10-10T21:27:52.511438+00:00  (µs)
//       Deno pg driver ->
//         Date.toISOString(): 2026-10-10T21:27:52.511Z         (ms)
//
//     A digest over the raw string binds the TRANSPORT, not the value.
//     Partner A approving through PostgREST and partner B through any
//     path that rounds to milliseconds would disagree forever. The
//     Global Constraint's phrase "no floating timestamp precision wider
//     than what is actually stored" is exactly this: we bind the
//     millisecond-truncated UTC instant, which every path above can
//     reproduce from what it received.
//
//   * The canonical digest pre-image is built as an EXPLICIT string,
//     field by field, with lengths prefixed -- not JSON.stringify of an
//     object literal. V8's insertion-order property guarantee is real,
//     but it is an implementation detail of one engine, and more
//     importantly a bare concatenation is ambiguous: ["a","bc"] and
//     ["ab","c"] have the same concatenation. Length prefixes make the
//     pre-image injective. See buildDigestPreimage.

import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";

// ---------------------------------------------------------------------------
// Spec §4.2's literal numbers. Named, because a bare 2400 three
// functions apart is how two of them drift.
// ---------------------------------------------------------------------------

/// "limits six" -- at most six eligible window messages.
export const WINDOW_ROW_CAP = 6;
/// "clips each message to 600 scalars INCLUDING a truncation marker".
export const PER_MESSAGE_CHAR_CAP = 600;
/// "then takes the newest entries fitting 2,400 total".
export const WINDOW_TOTAL_CHAR_CAP = 2400;
/// The marker's own cost counts against both caps, per "including a
/// truncation marker".
export const TRUNCATION_MARKER = " [truncated]";

/// The digest's policy-version namespace. Bumping this invalidates every
/// outstanding approval by construction, which is what a change to the
/// pre-image FORMAT (as opposed to its content) requires: two clients
/// running different code versions must not silently agree on a digest
/// computed from differently-shaped pre-images.
export const DIGEST_FORMAT_VERSION = "ai-session-digest-v1";

export interface WindowMessage {
  messageId: string;
  /// The message's stored `created_at`, canonicalized (see
  /// canonicalTimestamp). This is the DISPLAY/ORDERING timestamp only.
  createdAt: string;
  /// The version this window binds into the approval digest:
  /// `COALESCE(edited_at, created_at)`, canonicalized.
  ///
  /// NOT `created_at`, and that distinction is a defect I measured in
  /// Plan B rather than a style choice. §4.3 requires revalidating
  /// "source existence/VERSION against the frozen snapshot" so that an
  /// edit to an approved message makes the session unavailable. But
  /// `messages.created_at` does not move on an edit -- both edit paths
  /// (20260831120000's and 20260950110000's) do
  /// `SET content = ..., edited_at = now()` and leave `created_at`
  /// alone. Measured directly:
  ///
  ///   before: created_at 2026-10-10 21:33:09.952279+00  edited_at NULL
  ///   after:  created_at 2026-10-10 21:33:09.952279+00  edited_at 21:33:09.974946+00
  ///
  /// Plan B's prepare_ai_session populates
  /// ai_session_sources.source_version from `m.created_at`, so an edit
  /// leaves the stored source_version byte-identical and the §4.3
  /// revalidation cannot see it. This field is the correct version;
  /// the Plan B write is reported as a finding for the reviewer rather
  /// than changed here (it is another task's RPC).
  sourceVersion: string;
  /// The clipped text. Spec §4.2: "Display and send the identical
  /// clipped strings" -- this exact string is what the user sees, what
  /// the provider receives, and what the digest binds.
  content: string;
  truncated: boolean;
}

// ---------------------------------------------------------------------------
// Pure helpers. Each is exported so its determinism is testable
// directly rather than only through the query path.
// ---------------------------------------------------------------------------

/// Spec §4.1: "a validated UTC offset in minutes [-840,840]".
///
/// Validated here rather than only at the request edge because the
/// offset is a digest INPUT: an unvalidated offset is an unbounded
/// digest input, and a caller that skipped validation would produce a
/// digest its partner's validated call could never match.
export function isValidUtcOffsetMinutes(value: unknown): value is number {
  return typeof value === "number" &&
    Number.isInteger(value) &&
    value >= -840 &&
    value <= 840;
}

/// Canonicalizes a stored timestamptz to a single fixed rendering:
/// UTC, millisecond precision, `Z` suffix.
///
/// Why millisecond and not microsecond: millisecond is the COARSEST
/// precision any live path produces (the Deno pg driver decodes to a JS
/// Date, which cannot hold microseconds at all). Canonicalizing UP to
/// microseconds would require inventing digits that path has already
/// lost. Truncating down to milliseconds is reproducible from every
/// rendering, which is the only property that matters.
///
/// Returns null for anything unparseable, so a caller must decide
/// explicitly rather than hashing the string "Invalid Date".
export function canonicalTimestamp(raw: unknown): string | null {
  // A Date is handled WITHOUT going through String() first. This is not
  // defensive typing -- it is a measured bug. The Deno pg driver decodes
  // a timestamptz to a JS Date, and `String(date)` renders
  //
  //   "Sat Oct 10 2026 23:17:59 GMT+0000 (Greenwich Mean Time)"
  //
  // which has NO millisecond field at all. Re-parsing that gives
  // ...59.000Z, so a caller that stringified first would hash a
  // timestamp 159ms away from the one a caller receiving ISO text
  // hashes -- two partners, two digests, a session that can never
  // activate. Exactly the "floating timestamp precision wider than what
  // is actually stored" the plan's Global Constraints forbid.
  if (raw instanceof Date) {
    const ms = raw.getTime();
    return Number.isFinite(ms) ? new Date(ms).toISOString() : null;
  }
  if (typeof raw !== "string") return null;
  const parsed = new Date(raw);
  const ms = parsed.getTime();
  if (!Number.isFinite(ms)) return null;
  return new Date(ms).toISOString();
}

/// Spec §4.2 item 3: "Civil day is computed once from server time plus
/// the displayed, validated offset." Returns the UTC instant at which
/// the viewer's civil day began.
///
/// UTC GETTERS ARE LOAD-BEARING. `new Date(t).getFullYear()` resolves
/// against the host's TZ environment, so the same (now, offset) would
/// yield a different boundary on a UTC worker than on a UTC+1 host --
/// non-determinism from an input this function is not even given. The
/// shifted-instant + UTC-getters form below depends on nothing but its
/// two arguments.
///
/// ai_context_loader.ts's own understand-mode day window uses the local
/// getters. That is a pre-existing issue there, NOT copied here, and
/// noted in this task's report rather than silently fixed in a file
/// whose regression tests belong to another feature.
export function civilDayStartUtc(now: Date, utcOffsetMinutes: number): Date {
  const shifted = new Date(now.getTime() + utcOffsetMinutes * 60_000);
  const localMidnightAsUtc = Date.UTC(
    shifted.getUTCFullYear(),
    shifted.getUTCMonth(),
    shifted.getUTCDate(),
  );
  return new Date(localMidnightAsUtc - utcOffsetMinutes * 60_000);
}

/// Clips one message body to the per-message cap, with the marker's own
/// length counted INSIDE the cap ("600 scalars including a truncation
/// marker").
///
/// Counts Unicode SCALAR VALUES, not UTF-16 code units: spec §4.1 says
/// "use identical Unicode-scalar counting in Dart, TypeScript and SQL
/// (not JavaScript UTF-16 length)". `[...s]` iterates scalars, so an
/// emoji costs 1 here and 2 under `.length`. Slicing by code unit could
/// also split a surrogate pair and emit a lone surrogate -- which §4.1
/// separately forbids ("Reject unpaired surrogates").
export function clipToScalars(content: string, cap: number): {
  content: string;
  truncated: boolean;
} {
  const scalars = [...content];
  if (scalars.length <= cap) return { content, truncated: false };
  const markerScalars = [...TRUNCATION_MARKER].length;
  const keep = Math.max(0, cap - markerScalars);
  return {
    content: scalars.slice(0, keep).join("") + TRUNCATION_MARKER,
    truncated: true,
  };
}

/// Counts Unicode scalar values, matching clipToScalars' unit so the
/// budget arithmetic and the clipping agree.
export function scalarLength(content: string): number {
  return [...content].length;
}

/// Spec §4.2's eligibility exclusions, as one predicate: "Exclude system
/// notices, deleted messages, Assist-origin messages, media/captions,
/// games, ephemeral/streak content and other non-ordinary-text types."
///
/// Deliberately the SAME rule set ai_context_loader.ts's `isEligible`
/// applies, re-expressed rather than imported: that loader's filter is
/// an inner closure of loadBoundedContext, keyed on
/// loadAiAssistantTarget's single-target shape, and is not exported.
/// The brief calls for reuse "by reference, not imported directly" for
/// exactly this reason. If the two ever need to diverge they are
/// separate; if they must agree, the window contract test is what says
/// so.
export function isEligibleWindowRow(row: Record<string, unknown>): boolean {
  return !row.deleted_at &&
    !row.is_system_notice &&
    row.message_origin !== "attune_assist" &&
    !row.media_url &&
    !row.game_session_id &&
    typeof row.content === "string" &&
    (row.content as string).trim().length > 0;
}

// ---------------------------------------------------------------------------
// The window selection itself.
// ---------------------------------------------------------------------------

export interface WindowSelectionInput {
  /// Rows as returned by the §4.2 query, NEWEST FIRST
  /// (created_at DESC, id DESC).
  rows: Record<string, unknown>[];
  /// The selected target message, excluded from the window per §4.2
  /// item 3 ("excluding the selected target").
  excludeMessageId: string | null;
}

/// The pure core of selectSharedWindow: everything after the query.
/// Separated so the budget/clipping/ordering contract is testable
/// without a database, and so the one impure thing (the query) is the
/// only thing a test has to set up.
///
/// Spec §4.2's pipeline, in its stated order:
///   filter -> limit six -> clip each to 600 -> take the newest
///   entries fitting 2,400, clipping the final entry if necessary ->
///   order chronologically for display.
export function selectWindowFromRows(
  input: WindowSelectionInput,
): WindowMessage[] {
  const eligible = input.rows
    .filter((row) =>
      row.id !== input.excludeMessageId && isEligibleWindowRow(row)
    )
    // "limits six" applies to the ELIGIBLE set, not to the raw query
    // rows -- which is why the query overfetches and this slice runs
    // after the filter. Slicing first would let six ineligible rows
    // (six deleted messages, say) yield an empty window while eligible
    // text sat just outside the limit.
    .slice(0, WINDOW_ROW_CAP);

  const clipped: WindowMessage[] = [];
  for (const row of eligible) {
    const createdAt = canonicalTimestamp(row.created_at as string);
    // An unparseable created_at is dropped rather than hashed. A row we
    // cannot canonicalize is a row whose digest contribution two
    // callers might render differently -- the exact failure this module
    // exists to prevent.
    if (createdAt === null) continue;
    // COALESCE(edited_at, created_at) -- see WindowMessage.sourceVersion
    // for why created_at alone cannot detect an edit.
    const sourceVersion = row.edited_at == null
      ? createdAt
      : canonicalTimestamp(row.edited_at as string);
    if (sourceVersion === null) continue;
    const { content, truncated } = clipToScalars(
      row.content as string,
      PER_MESSAGE_CHAR_CAP,
    );
    clipped.push({
      messageId: row.id as string,
      createdAt,
      sourceVersion,
      content,
      truncated,
    });
  }

  // Newest-first in, because the query ordered DESC. Accumulate
  // newest-to-oldest until the total budget is reached, CLIPPING the
  // entry that fits only partially rather than dropping it whole --
  // "clipping the final entry if necessary".
  const selected: WindowMessage[] = [];
  let totalScalars = 0;
  for (const message of clipped) {
    const remaining = WINDOW_TOTAL_CHAR_CAP - totalScalars;
    if (remaining <= 0) break;
    const length = scalarLength(message.content);
    if (length <= remaining) {
      selected.push(message);
      totalScalars += length;
      continue;
    }
    // Partial fit. Re-clip to exactly the remaining budget. If the
    // remainder cannot even hold the marker plus one scalar of real
    // text, stop: a message rendered as nothing but " [truncated]"
    // discloses that a message existed while conveying none of it,
    // which is worse for the user than omitting it and is not what
    // "clipping" means.
    const markerScalars = [...TRUNCATION_MARKER].length;
    if (remaining <= markerScalars) break;
    const { content } = clipToScalars(message.content, remaining);
    selected.push({ ...message, content, truncated: true });
    break;
  }

  // Spec §4.2: "Display and send the identical clipped strings, ordered
  // chronologically."
  //
  // The comparator breaks ties on messageId, matching the query's
  // (created_at, id) ordering. Without it, two messages sharing a
  // created_at -- which millisecond canonicalization makes MORE likely,
  // since it collapses microsecond-distinct timestamps -- would have an
  // order decided by Array.prototype.sort's stability over an input
  // whose own order came from a DESC query. Partner A and partner B
  // would agree (same query, same order), but the pair would be
  // ordered newest-first inside an otherwise chronological list. Tying
  // on id makes the output a function of the SET of rows, not of the
  // order they arrived in.
  return selected.sort((a, b) =>
    a.createdAt === b.createdAt
      ? a.messageId.localeCompare(b.messageId)
      : a.createdAt.localeCompare(b.createdAt)
  );
}

/// Spec §4.2's window query plus the pure selection above.
///
/// "Window query filters before LIMIT": the civil-day bound, the
/// relationship bound and the ordering are all in SQL, so the LIMIT
/// applies to day-filtered rows rather than to the whole conversation.
/// The eligibility exclusions cannot be expressed as a single
/// PostgREST filter chain without encoding each column's semantics into
/// the URL, so the query overfetches by 3x and
/// selectWindowFromRows applies them -- the same split
/// ai_context_loader.ts already uses, and the reason WINDOW_ROW_CAP is
/// applied after the filter there too.
///
/// `now` is a parameter. A caller passes ONE `now` for the whole
/// request so the civil day, the digest and any persisted snapshot time
/// all describe the same instant (§4.2: "computed ONCE from server
/// time").
export async function selectSharedWindow(
  client: SupabaseClient,
  relationshipId: string,
  excludeMessageId: string | null,
  utcOffsetMinutes: number,
  now: Date,
): Promise<WindowMessage[]> {
  if (!isValidUtcOffsetMinutes(utcOffsetMinutes)) {
    // Not a silent clamp: a clamped offset would compute a different
    // civil day than the client displayed, and §4.2 requires the day to
    // come from "the DISPLAYED, validated offset".
    throw new RangeError("utcOffsetMinutes out of [-840,840]");
  }

  const dayStartUtc = civilDayStartUtc(now, utcOffsetMinutes);

  const { data: rows, error } = await client
    .from("messages")
    .select(
      "id, sender_id, created_at, edited_at, content, deleted_at, is_system_notice, message_origin, media_url, game_session_id",
    )
    .eq("relationship_id", relationshipId)
    .gte("created_at", dayStartUtc.toISOString())
    // §4.2: "orders (created_at DESC, id DESC)".
    .order("created_at", { ascending: false })
    .order("id", { ascending: false })
    .limit(WINDOW_ROW_CAP * 3);

  if (error) throw error;

  return selectWindowFromRows({
    rows: (rows ?? []) as Record<string, unknown>[],
    excludeMessageId,
  });
}

// ---------------------------------------------------------------------------
// The approval digest -- spec §4.3.
// ---------------------------------------------------------------------------

/// Everything §4.3 requires the digest to bind: "policy version, source
/// versions, displayed snippets, offset/day, participants, kind and
/// visibility."
///
/// `sessionId` and `contextRevision` are bound too, beyond the spec's
/// list. Reason: without them, two DIFFERENT sessions over the same
/// day's messages with the same settings produce the same digest, so an
/// approval for session X would satisfy the equality check for session
/// Y at the same revision. Plan B's ai_session_approvals is keyed
/// (session_id, member_id, revision), so such a digest could not be
/// REPLAYED across sessions through that table -- but the digest is
/// what the client submits, and binding the thing being approved into
/// the thing that attests to it costs nothing.
export interface ApprovalDigestInput {
  sessionId: string;
  policyVersion: string;
  kind: string;
  visibility: string;
  /// Both current relationship members. Order-insensitive: see below.
  participants: string[];
  /// Each window/target source's stored version (its `created_at`),
  /// paired with its message id. Pairing matters: two sources swapping
  /// versions must change the digest.
  sources: { messageId: string; sourceVersion: string }[];
  /// The exact clipped strings shown to the user, in display order.
  displayedSnippets: string[];
  utcOffsetMinutes: number;
  /// The civil-day start this window was selected against, as
  /// civilDayStartUtc returned it. Bound explicitly rather than
  /// re-derived, because §4.3 names "offset/DAY" as two bindings: the
  /// offset alone does not pin the day, and two approvals minutes apart
  /// across local midnight must NOT silently agree.
  civilDayStartUtc: string;
  contextRevision: number;
}

/// Builds the exact byte string that gets hashed. Exported so a test
/// can assert the FORMAT, not just that two hashes match -- a test that
/// only compares digests passes equally well against a function
/// returning a constant.
///
/// Format: a version line, then one `key=len:value` line per field,
/// with arrays expanded as indexed entries. The length prefix is what
/// makes the encoding injective: without it, (["ab"],["c"]) and
/// (["a"],["bc"]) share a pre-image, so a snippet boundary could move
/// without changing the digest. Newline is not relied on as a
/// delimiter; the lengths are.
export function buildDigestPreimage(input: ApprovalDigestInput): string {
  const parts: string[] = [DIGEST_FORMAT_VERSION];

  const field = (key: string, value: string) => {
    // Length in Unicode scalars, matching §4.1's counting rule and the
    // clipping unit, so a snippet's prefix cannot be reinterpreted as
    // part of the next field.
    parts.push(`${key}=${scalarLength(value)}:${value}`);
  };

  field("session_id", input.sessionId);
  field("policy_version", input.policyVersion);
  field("kind", input.kind);
  field("visibility", input.visibility);

  // Participants are SORTED. §4.3 binds "participants" as a set: the
  // creator and the partner approve the same snapshot, and nothing in
  // the flow guarantees both callers enumerate the relationship's two
  // members in the same order (one may read user_a/user_b, another may
  // have them from an approvals query). Sorting makes the binding a
  // function of the SET. Count is bound separately so a third
  // participant cannot be hidden by sorting.
  const participants = [...input.participants].sort();
  field("participant_count", String(participants.length));
  participants.forEach((p, i) => field(`participant[${i}]`, p));

  // Sources are NOT re-sorted: §4.2 fixes their order (chronological,
  // id-tiebroken) and selectWindowFromRows guarantees it, so the order
  // is already canonical and IS part of what was displayed. Sorting
  // here would hide a reordering that the user would have seen.
  field("source_count", String(input.sources.length));
  input.sources.forEach((source, i) => {
    field(`source[${i}].message_id`, source.messageId);
    field(`source[${i}].version`, source.sourceVersion);
  });

  field("snippet_count", String(input.displayedSnippets.length));
  input.displayedSnippets.forEach((snippet, i) => {
    field(`snippet[${i}]`, snippet);
  });

  field("utc_offset_minutes", String(input.utcOffsetMinutes));
  field("civil_day_start_utc", input.civilDayStartUtc);
  field("context_revision", String(input.contextRevision));

  return parts.join("\n");
}

/// SHA-256 hex over buildDigestPreimage's output.
///
/// Deterministic by construction: the only inputs are the fields above,
/// the only clock reading is whatever the caller already put in them,
/// and SHA-256 is SHA-256. The accompanying test computes this twice at
/// different wall-clock times and asserts byte equality, then changes
/// each field in turn and asserts the digest moves.
export async function computeApprovalDigest(
  input: ApprovalDigestInput,
): Promise<string> {
  const preimage = buildDigestPreimage(input);
  const hashed = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(preimage),
  );
  return Array.from(new Uint8Array(hashed))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

# Chat AI Assistant — Implementation-ready design

**Status:** reviewed and ready for an implementation plan behind a disabled
feature flag; production release is blocked on the gates in §14.1
**Date:** 2026-09-15
**Scope:** on-demand, single-turn assistance from a text message in an active
couple chat

## 0. Adversarial review findings incorporated here

The pre-review draft was not implementation-ready. These were the material
findings, in priority order, and this revision changes the design rather than
leaving them as implementation notes.

| Priority | Finding | Why it mattered | Correction in this revision |
|---|---|---|---|
| P0 | The client supplied `message`, `surrounding`, and `same_day_history` strings | Relationship membership did not prove those strings came from that relationship—or from Attune at all. Bounds and deletion rules were client assertions, and arbitrary third-party text could be sent to the model under another couple's ID | Both functions accept a `message_id`; authenticated server code loads and bounds visible context itself (§4) |
| P0 | Assist attempted a normal client insert with `message_analysis_skipped = true` | Authenticated does not currently have INSERT permission for that column, and `analyse-message` does not honor the flag anyway. The insert would fail or contaminate Layer 1/2 analysis | A trusted share RPC writes the field, and the analysis workers/indexes must explicitly exclude skipped rows (§8.2) |
| P0 | `is_system_notice` plus content inspection was treated as AI provenance | Any client currently able to set that presentation flag could impersonate “Attune”; editing content makes string-based classification even less trustworthy | Add server-owned `message_origin = 'attune_assist'` and validated payload; never infer provenance from prose (§5.3, §7.2) |
| P0 | Understand's “never shared” promise rested only on client convention | A generic result/provider or future share callback could route its private interpretation into chat | Separate response types, providers, endpoint dependencies, and a static no-write contract; Understand has no message-writing capability (§6.3) |
| P1 | Strict JSON was described as the primary prompt-injection defense | Malicious content can fit a valid JSON schema. Schema validity says nothing about blame, quotation, exfiltration, factuality, or instruction following | Treat transcript text as quoted data, validate semantics and provenance, reject context echoes, and run adversarial evals (§9) |
| P1 | Location was fetched before knowing it was needed, and the Nearby pipeline leaked more than coordinates | The existing `LocationService.getCurrentLocation()` also reverse-geocodes; a model-derived free-text query could disclose chat details to Mapbox, while returning Mapbox addresses to Gemini would disclose the requester's area. A cluster of shared places also lets the partner infer an approximate area | Nearby is an explicit choice using a raw-position method; Gemini emits only a benign allowlisted category, Mapbox ranks candidates, the server assembles the card, and coordinates/distances are never shared (§5.2) |
| P1 | The spec cited Claude and the Conflict Translator as safe precedents | This repository enforces Gemini through `gemini_port.test.ts`; the current Translator accepts client context and lacks the authorization boundary required here | Use `callGeminiJson`; reuse tone/prompt ideas only, not the Translator's request/auth architecture (§7.1) |
| P1 | Assist posted immediately and persisted neither sources nor its Planning proposal | Unreviewed model output could enter shared chat, while reload removed the source cards and “Add to Planning” affordance | Generate a private short-lived draft, require explicit Share, and persist a safe payload on the resulting message (§5.3) |
| P1 | “20 calls per rolling day” had no concurrency or idempotency design | Racing requests could exceed the cap; retries could double-charge; “tomorrow” was inaccurate for a rolling window | One atomic server quota ledger shared by both modes, keyed by request UUID and returning `retry_after_seconds` (§7.3) |
| P1 | Up to 200 same-day messages was an unnecessarily large disclosure | A busy day's transcript is far more context than one terse message needs and increases cost, prompt injection, and external-provider exposure | Understand receives the target plus at most 19 nearby text messages from the same server-derived day (§4.3) |
| P1 | Message-count limits had no character/token budget | A valid chat message can contain 10,000 characters, so even 20 rows could produce an unexpectedly huge provider disclosure and cost spike | Reject oversized targets and apply deterministic per-message and whole-context character ceilings before provider work (§3, §4.3) |
| P1 | The draft relied on an “existing” global app-switcher privacy cover | The Safety spec requires one, but repository search found the explicit Quick Exit neutral route rather than a root lifecycle cover that always obscures snapshots | Treat the global cover as a verified prerequisite; Understand must not ship on documentation alone (§6.3, §14.1) |
| P1 | “Existing AI consent” was cited without a durable implementation contract | Signup copy alone cannot prove that both authors agreed to this purpose, policy version, or later withdrawal | Add append-only relationship-scoped grants and a minimal status RPC unless an existing record proves the identical invariants (§7.2, §10.1) |
| P2 | “Help me understand” could sound like mind-reading and could minimize threatening content | Confidence labels can make speculation feel authoritative; interpreting dangerous language may falsely reassure the recipient | Return plural possible readings, never `high` confidence, never diagnose intent, and always expose manual Safety Resources independently (§6.2) |

## 1. Product boundary

The assistant is pull-only. It appears only after a user long-presses a
supported text message and chooses **Ask Attune**. It never reads or speaks on
its own, never schedules work, never offers itself based on message content,
and never supports follow-up turns.

There are two deliberately separate modes:

- **Assist — “Get ideas”**: bounded ideation or nearby-place discovery. Its
  result first appears as a private preview. The requester may explicitly share
  the exact suggestion to the couple chat, where it becomes a durable
  Attune-attributed message.
- **Understand — “Possible ways to read this”**: private, uncertainty-forward
  help reading a partner-authored message and considering responses. Its result
  is requester's-eye-only, memory-only, and has no share/copy/send-to-composer
  action in v1.

This is not a conversational AI persona. Each invocation is one bounded report
about one selected message. No assistant identity persists across calls and no
previous assistant result is context for a later call.

## 2. Visibility and capability matrix

| Capability | Assist | Understand |
|---|---:|---:|
| Target own text message | Yes | No |
| Target partner text message | Yes | Yes |
| Reads server-selected nearby chat context | Up to 6 total context messages | Up to 19 context messages plus target |
| Reads profiles, insights, location history, presence, safety state, Planning, or prior AI output | Never | Never |
| May use current device location | Nearby submode only, after explicit per-call choice | Never |
| Response initially private | Yes, short-lived preview | Yes, always |
| Can become a chat message | Only exact server-held draft after Share | Never |
| Persisted output | Draft usable for 15 minutes and physically purged within 24 hours; shared message follows chat retention | Never by Attune |
| Direct Planning action | Shared Assist message only | Never |
| Included in relationship analysis | Never | Not applicable—no message row |
| Deterministic message safety pipeline | Yes, when shared | Not applicable—no message row |

No shared abstraction may expose `share()`, `copyToComposer()`, or
`createPlanningItem()` on an Understand result. Dart uses distinct sealed types
(`AssistDraft` and `UnderstandResult`), distinct Riverpod providers, and
distinct widgets. A generic `AiAssistantResult` carrying optional actions is
explicitly prohibited because it turns the privacy boundary into a nullable UI
convention.

## 3. Entry eligibility and interaction

`Ask Attune` appears only when all of these are true:

- the relationship is currently active and `chat_archived_at IS NULL`;
- the message is not deleted;
- `content` is non-blank;
- `content` is at most 4,000 PostgreSQL characters after NFC normalization;
- the row is an ordinary user-authored message, not a game/place/media-only
  card, system notice, or `message_origin = 'attune_assist'` output;
- the message is already server-acknowledged, not only an optimistic local row.

Assist is available for the requester's or partner's supported message.
Understand is available only when `message.sender_id != auth.uid()`. These are
UX gates only; both edge functions independently enforce the same rules.

The mode sheet makes the boundary visible before a call:

- **Get ideas** — “Create suggestions you can preview and choose to share.”
- **Possible ways to read this** — “Private to you. Attune cannot know what
  your partner meant.”

The first use also shows the approved third-party AI disclosure and consent
state from §10.1. The invocation does not begin until that gate succeeds.

## 4. Trusted request and context construction

### 4.1 Request contracts

Assist request:

```typescript
{
  request_id: string;                 // client UUID; idempotency + quota key
  message_id: string;
  assist_kind: 'ideas' | 'nearby';
  user_instruction: string | null;    // trimmed, 1..300 Unicode scalar values
  requester_location: {
    latitude: number;
    longitude: number;
    accuracy_m: number;
  } | null;                           // required only for nearby
}
```

Understand request:

```typescript
{
  request_id: string;                 // client UUID; idempotency + quota key
  message_id: string;
  utc_offset_minutes: number;         // integer -840..840; day boundary only
}
```

Neither request accepts `relationship_id`, `requester_id`, message content,
history, profile fields, partner identity, prior AI output, or arbitrary source
records. Identity comes from a verified bearer token via `requireUser(req)`.
Only `POST` with JSON is accepted. Reject unknown fields, bodies over 4 KiB,
invalid UUIDs/non-finite numbers, and wrong content types before database or
provider work.

### 4.2 Authorization and target loading

Each function uses a user-JWT-scoped Supabase client for content reads—not an
unrestricted service-role read—and performs this sequence before reserving
quota or calling an external provider:

1. Authenticate the JWT with `auth.getUser`; never decode and trust claims
   locally.
2. Load the target message by ID through RLS.
3. Join/load its relationship and require caller membership, `status =
   'active'`, and `chat_archived_at IS NULL`.
4. Enforce §3 eligibility, including partner authorship for Understand.
5. Reject a target whose `created_at`/sender/relationship cannot be resolved.

All target failures use the same `TARGET_UNAVAILABLE` response so the endpoint
is not an existence oracle. A relationship ending or archiving before an
external call prevents the call. The share operation rechecks the relationship
again because it may happen minutes later.

### 4.3 Server-built context

Context contains only live, non-blank, user-authored text messages from the
target's relationship. It excludes deleted rows, system notices, media/game/
place cards, Assist output, and any message the caller cannot read. It carries
pseudonymous roles (`requester` and `partner`), timestamp, and content—never
names or user UUIDs—to the model.

- **Assist:** at most six other messages total, selected as the nearest three
  before and nearest three after the target, then sorted chronologically.
- **Understand:** target plus at most nineteen nearest messages within the
  target's civil day. The day is derived from `target.created_at` using the
  validated `utc_offset_minutes`; take up to twelve before and seven after,
  then sort chronologically. The count cap is always primary, so changing the
  offset can never expose an unbounded day.

“Before,” “after,” and chronological order use the immutable
`(created_at, id)` tuple, not client list position or mutable `sort_at`.

The selected target is tagged explicitly. Context is serialized as JSON data
inside a delimited prompt section whose system instruction says that every
field is untrusted quoted conversation, never model instructions.

The target is never truncated: a target over 4,000 PostgreSQL characters is
ineligible in the client and returns `UNSUPPORTED_REQUEST` from the server
before quota. Each
surrounding message is NFC-normalized and clipped to 1,000 PostgreSQL
characters with an explicit `[truncated]` data marker. Starting with the target,
the loader adds candidates in nearest-first order only while the combined
message text remains at or below 12,000 PostgreSQL characters, then restores
chronological order. Both the row cap and this total cap apply. PostgreSQL
`char_length` is the canonical count; TypeScript/Flutter prechecks are UX only.

The edge response never returns loaded context. Application logs, provider
error logs, Sentry, analytics, traces, and rate-limit rows never contain target
text, history, location, model output, or prompts.

## 5. Assist mode

### 5.1 Supported intent

Assist supports two bounded jobs:

- **Ideas:** subjective brainstorming that does not require live facts, such as
  date themes, gift categories, activity ideas, names, or ways to organize a
  plan.
- **Nearby:** finding real places or businesses around a location the requester
  explicitly chose to use.

It is not general question answering, news, medical/legal/financial advice,
relationship advice, travel booking, shopping checkout, reservation creation,
web browsing, or factual research. Unsupported requests return
`UNSUPPORTED_REQUEST` without pretending to answer.

The model may propose a Planning Task or all-day Event, but it never creates
one and never proposes a Goal or Note in v1.

### 5.2 Nearby search and location privacy

Nearby is a separate tap; the model never silently decides to fetch location.
Before location permission, show:

> Attune will send your current coordinates and a broad place category to
> Attune's server and Mapbox for this search. Nearby suggestions may reveal your
> approximate area when shared with your partner. Your coordinates will not be
> saved or sent to Gemini.

Declining returns to the sheet without consuming assistant quota. The client
uses a new raw-position method backed directly by Geolocator. It must not call
the current `LocationService.getCurrentLocation()`, because that method first
reverse-geocodes the coordinates and may contact an additional platform
provider. Request balanced/approximate accuracy sufficient for nearby search,
not high-accuracy tracking.

Coordinates and accuracy are range-validated server-side, used for one Mapbox
request, and then discarded. They are absent from the draft row, message,
payload, logs, analytics, and error reporting. Mapbox credentials live only in
Edge Function secrets and must be a dedicated least-privilege server token;
the Flutter Mapbox package/token is not evidence that Search Box API access,
quota, billing, or terms are configured.

Mapbox receives coordinates and one fixed server-mapped category token, but
never message text, free-form user/model prose, user/relationship IDs, names,
or Gemini output. Gemini receives the bounded chat context but never
coordinates, Mapbox candidates, place names, or addresses. The only value
crossing from Gemini to the Mapbox step is one of these v1 categories:
`restaurant`, `cafe`, `park`, `cinema`, `museum`, or `recreation`. The server
owns the corresponding provider query/category mapping. Unsupported or
sensitive categories—including health, therapy, religion, lodging, adult
venues, and exact named-place searches—return `UNSUPPORTED_REQUEST` rather
than being forwarded as free text.

The result sent to chat contains no coordinates or distance labels. Even so,
the place set may reveal a general area, which is why preview and the explicit
disclosure are mandatory. Stored source fields are limited to:

```typescript
{
  provider_id: string;
  name: string;
  formatted_address: string | null;
  category: string | null;
  map_url: string | null; // server-built provider/place-id URL; no coordinates
}
```

No claim about opening hours, price, availability, ratings, accessibility, or
travel time may appear unless the exact field is returned by the contracted
Mapbox endpoint and preserved in the validated source schema. V1 omits those
claims. UI includes Mapbox attribution required by the provider contract.

Nearby generation is deterministic in its factual seam:

1. Gemini returns one category from the fixed allowlist, not a search string or
   place name.
2. Server calls Mapbox with maximum 10 results and a bounded radius.
3. Server accepts Mapbox's relevance order, takes at most three valid results,
   and constructs all place names, addresses, URLs, and display prose from
   allowlisted Mapbox fields. Mapbox results are never sent back to Gemini.

Nearby uses one Gemini call and one Mapbox call; Ideas uses one Gemini call.
The rate limit counts one user invocation, while cost monitoring records
provider-call counts by provider without content.

The model-facing contracts are exact:

```typescript
type IdeasModelOutput = {
  reply_text: string; // trimmed, 1..2000 PostgreSQL characters
  suggested_planning_item: {
    kind: 'task' | 'event';
    title: string; // trimmed, 1..120 PostgreSQL characters
    event_date: string | null; // YYYY-MM-DD; non-null only for event
  } | null;
};

type NearbyCategoryOutput = {
  category:
    | 'restaurant'
    | 'cafe'
    | 'park'
    | 'cinema'
    | 'museum'
    | 'recreation';
};
```

Ideas uses `IdeasModelOutput`. For Nearby, the server validates
`NearbyCategoryOutput`, maps it to a fixed provider token, calls Mapbox, then
constructs `reply_text` and `PlaceSource[]` itself from up to three valid
records in provider relevance order. Nearby model output can never supply a
free-text provider query, place name, address, URL, distance, rationale, or
other factual field. Empty/invalid provider results return `NO_RESULTS`; no
partial draft is stored.

### 5.3 Preview, durable message, and provenance

A successful generation creates a server-only `ai_assist_drafts` row and
returns its contents to the requester. Nothing is posted automatically. The
preview offers:

- **Share in chat** — shares the exact server-held response;
- **Edit as my message** — copies only `reply_text` into the ordinary composer,
  discards Attune provenance/source/Planning metadata, and sends only after the
  user taps the normal Send button;
- **Close** — discards client state; the server draft expires automatically.

`Share in chat` calls `share_ai_assist_draft(draft_id)`. The RPC locks the
draft, verifies requester and active relationship again, checks its 15-minute
expiry, current dual consent, and that the target message remains live and
eligible, then inserts or returns exactly one message idempotently. If the
target was deleted while the preview was open, the draft can no longer be
shared. The RPC never accepts replacement content or payload from the client.

The shared message uses:

```text
sender_id                = authenticated requester
content                  = draft.reply_text
message_origin           = "attune_assist"       // server-only
assistant_payload        = validated draft payload
is_system_notice         = false
message_analysis_skipped = true
source                   = "native"
```

It renders as an Attune suggestion attributed to the requester, not as an
authorless system notice. `message_origin`, not text or `is_system_notice`,
drives the label. The existing message INSERT trigger still creates the normal
safety and notification outbox work.

The durable `assistant_payload` is versioned and contains only:

```typescript
{
  schema_version: 1;
  suggested_planning_item: {
    kind: 'task' | 'event';
    title: string;
    event_date: string | null;
  } | null;
  sources: PlaceSource[];
}
```

It contains no prompt, raw context, location, requester ID, model chain of
thought, or hidden model fields. This payload is what keeps sources and “Add to
Planning” stable after reload and on the partner's device.

An Attune Assist message may be deleted under the existing five-minute sender
rule but may not be edited in place. The domain API splits `canEditOrDelete`
into `canEdit` and `canDelete`; `edit_message` also rejects
`message_origin = 'attune_assist'`. “Edit as my message” before sharing is the
supported path. This prevents an edited human message retaining a false Attune
label and avoids the existing content-edit path's lack of a fresh safety job.

`delete_message` must also recognize this origin. In the same transaction as
the ordinary tombstone it clears `assistant_payload`, resets `message_origin`
to `user` so the shape constraint remains valid, and deletes the
`ai_assist_planning_links` row. It does **not** delete a Planning entity that
was already created—the shared Planning item has an independent lifecycle.
Both memory and Drift representations replace the payload with the server
tombstone; they must not retain a locally cached copy behind the deleted row.

### 5.4 Add to Planning

Either partner may open the shared Assist message's proposal, review and edit
the fields, and confirm. Confirmation uses one transactional
`create_planning_from_assist_message(...)` RPC that:

- validates active relationship membership and that the message belongs to
  that same relationship;
- requires `message_origin = 'attune_assist'` and a matching proposal kind;
- validates edited title/date through Planning's normal contracts;
- creates at most one shared Planning entity for that message under concurrent
  taps; and
- records the resulting Planning kind/id in a small relationship-scoped link
  row so both clients replace the action with “Added to Planning.”

Calling generic Planning create RPCs and then marking the suggestion consumed
is prohibited because two partners can race and create duplicates. Declining
or closing creates nothing. If Planning is not shipped/enabled, the affordance
is hidden; Assist itself remains usable. If the resulting Planning entity is
later soft-deleted, Planning's delete RPC removes this link in the same
transaction and the Assist message returns to the unconsumed proposal state.

## 6. Understand mode

### 6.1 Purpose

Understand is reading support, not mind-reading, diagnosis, mediation, or a
verdict. It may identify ambiguity and offer several plausible interpretations
grounded only in the visible text. It must not use attachment profiles,
personal insights, prior conflicts, safety events, location/presence, or any
other private/derived data about either partner.

It cannot tell whether a message was sarcastic, coerced, deceptive, dangerous,
or emotionally sincere. UI says this before the result, not only when model
confidence is low.

### 6.2 Response contract

```typescript
type UnderstandResponse = {
  status: 'ok';
  possible_readings: [string, string] | [string, string, string]; // each 1..300 PostgreSQL chars
  response_options: [string, string] | [string, string, string]; // each 1..240 PostgreSQL chars
  confidence: 'low' | 'medium';
} | {
  status: 'cannot_help';
  reason: 'insufficient_context' | 'unsafe_to_infer' | 'unsupported';
};
```

Runtime code mechanically enforces lengths, counts, allowed enums,
prohibited-pattern checks, and context-echo checks. The remaining behavioral
rules are prompt constraints plus human-reviewed evaluation gates; the code
must not claim that a JSON validator can prove them:

- readings are plural possibilities, never a claim about intent or emotion;
- no blame, diagnosis, fault allocation, relationship verdict, or instruction
  to leave/stay/confront/apologize;
- no named partner or pronoun-plus-absolute characterization;
- no direct quotation or eight-token sequence copied from context;
- no secret, profile, or fact absent from the bounded input;
- response options are genuinely different, optional phrasings—not a single
  prescribed answer—and contain no automatic Send action;
- `high` confidence does not exist because text alone cannot establish another
  person's internal state.

For threats, coercion, self-harm, medical/legal questions, or other cases where
interpretation could minimize risk, return `cannot_help: unsafe_to_infer`. Do
not query or reveal deterministic safety-match state. The sheet always includes
the same discreet, manually available **Safety Resources** link regardless of
input/result, so its presence cannot reveal whether the safety pipeline fired.

### 6.3 Hard non-persistence/non-sharing boundary

`ai-understand`:

- has no import of the chat repository or message mutation client;
- cannot call `share_ai_assist_draft`;
- never inserts/updates `messages`, drafts, Planning, insights, analytics
  properties, or any table containing response/input content;
- returns `Cache-Control: no-store` and content-security headers;
- records only the data-minimized quota/audit row in §7.3; and
- never returns raw context.

The Flutter result lives in an `.autoDispose` provider owned by the sheet and
is overwritten on dispose/background/account or relationship change. It is
excluded from Drift, SharedPreferences, secure storage, state restoration,
Sentry breadcrumbs, analytics, clipboard, notification previews, and debug
logs. The Safety specification requires a global app-switcher privacy cover,
but this feature may rely on it only after an implementation test proves the
root app obscures this sheet before inactive/paused snapshots. Quick Exit's
explicit neutral route alone is not that proof.

There is no Copy, Share, Add to Planning, Send, or composer-prefill affordance.
Attune cannot prevent a user from photographing, screenshotting, memorizing,
or manually retyping what is on their own screen; the app makes no promise that
the requester is physically unable to disclose it. It promises only that
Attune supplies no persistence or sharing path.

## 7. Server architecture and data

### 7.1 Functions and model provider

Two user-authenticated Edge Functions preserve the capability boundary:

- `supabase/functions/ai-assist/index.ts`
- `supabase/functions/ai-understand/index.ts`

Both use `requireUser` and the repository's shared `callGeminiJson` helper.
They are added to `_shared/gemini_port.test.ts`, which must continue proving no
direct Anthropic/Claude call and no private per-function LLM client. Versioned
templates live at `supabase/functions/ai-assist/prompts/v1/{system,user}.txt`
and `supabase/functions/ai-understand/prompts/v1/{system,user}.txt`, loaded
relative to `import.meta.url`; a deployment test proves all four assets are
packaged. Do not copy the current Conflict Translator's raw client-context/auth
pattern or its embedded unversioned production prompt.

Provider timeouts are surfaced as `PROVIDER_UNAVAILABLE`, because the current
shared helper intentionally collapses timeout/HTTP/parse/prohibited-output
failures to null. Claiming `TIMEOUT` would be false unless the helper first
gains a typed error contract for every caller.

### 7.2 Schema additions

```sql
ALTER TABLE public.messages
  ADD COLUMN message_origin text NOT NULL DEFAULT 'user'
    CHECK (message_origin IN ('user', 'attune_assist')),
  ADD COLUMN assistant_payload jsonb;

ALTER TABLE public.messages
  ADD CONSTRAINT messages_assistant_payload_shape CHECK (
    (message_origin = 'user' AND assistant_payload IS NULL)
    OR
    (message_origin = 'attune_assist' AND assistant_payload IS NOT NULL)
  );

CREATE TABLE public.ai_assist_drafts (
  id uuid PRIMARY KEY,
  relationship_id uuid NOT NULL REFERENCES public.relationships(id)
    ON DELETE CASCADE,
  requester_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  target_message_id uuid REFERENCES public.messages(id) ON DELETE SET NULL,
  reply_text text NOT NULL CHECK (
    char_length(btrim(reply_text)) BETWEEN 1 AND 2000
  ),
  assistant_payload jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL,
  shared_message_id uuid UNIQUE REFERENCES public.messages(id)
    ON DELETE SET NULL,
  CHECK (expires_at = created_at + interval '15 minutes')
);

CREATE TABLE public.ai_assistant_usage (
  request_id uuid PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  relationship_id uuid NOT NULL REFERENCES public.relationships(id)
    ON DELETE CASCADE,
  mode text NOT NULL CHECK (mode IN ('assist', 'understand')),
  provider_calls smallint NOT NULL DEFAULT 0 CHECK (provider_calls BETWEEN 0 AND 2),
  outcome text NOT NULL CHECK (outcome IN (
    'reserved', 'succeeded', 'rejected', 'provider_failed', 'cancelled'
  )),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.ai_processing_consent_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  relationship_id uuid NOT NULL REFERENCES public.relationships(id)
    ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  policy_version text NOT NULL CHECK (char_length(btrim(policy_version)) BETWEEN 1 AND 80),
  action text NOT NULL CHECK (action IN ('granted', 'withdrawn')),
  idempotency_key uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, idempotency_key)
);

CREATE INDEX idx_ai_processing_consent_current
  ON public.ai_processing_consent_events
  (relationship_id, user_id, policy_version, created_at DESC, id DESC);

CREATE TABLE public.ai_assist_planning_links (
  message_id uuid PRIMARY KEY REFERENCES public.messages(id) ON DELETE CASCADE,
  relationship_id uuid NOT NULL REFERENCES public.relationships(id)
    ON DELETE CASCADE,
  planning_item_id uuid,
  planning_event_id uuid,
  created_by uuid REFERENCES public.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (num_nonnulls(planning_item_id, planning_event_id) = 1),
  FOREIGN KEY (planning_item_id, relationship_id)
    REFERENCES public.planning_items(id, relationship_id) ON DELETE CASCADE,
  FOREIGN KEY (planning_event_id, relationship_id)
    REFERENCES public.planning_events(id, relationship_id) ON DELETE CASCADE
);
```

Exact JSON shape is enforced in trusted SQL/RPC validation as well as Edge
Function validation; a bare `jsonb NOT NULL` is not sufficient. Cross-table
same-relationship checks are enforced by RPC/constraint, never assumed from
UUID possession.

Authenticated clients get SELECT on the new `messages` columns through the
existing explicit column allowlist, but no INSERT/UPDATE privilege for them.
Drafts, usage, and consent events have RLS enabled with no direct authenticated
table grants.
After authentication/validation, the Assist Edge Function inserts drafts using
a service-role-only function; no user may supply draft output to that function.
Quota reservation and draft sharing use user-JWT RPC clients so `auth.uid()` is
the authority. Sharing is the only authenticated command over a draft.
Planning links are readable only by active, unarchived relationship members and
writable only by the integration RPC.

Consent is changed only through a hardened `record_ai_processing_consent`
security-definer RPC: fixed `search_path`, revoked from `PUBLIC`/`anon`, caller
derived from `auth.uid()`, active membership checked, server-owned current
`policy_version`, and idempotent append-only writes. Clients cannot backdate,
update, delete, grant for a partner, or select raw consent events. A minimal
status RPC returns the caller's state plus `both_granted`, not the partner's
timestamps or history. Provider calls and draft sharing require the latest
event for each current member at the server-owned current version to be
`granted`. A version bump therefore requires two fresh grants. Withdrawal
immediately blocks new calls/shares and synchronously deletes that
relationship's unshared drafts; already shared chat messages retain the normal
chat lifecycle.

A scheduled service-role purge hard-deletes every draft—shared or unshared—no
later than 24 hours after creation; `expires_at` makes it unusable for sharing
after 15 minutes even if physical purge has not run. Usage rows are deleted
after 30 days. Shared message content/payload then follows ordinary chat
retention and deletion. Understand content is never in either table.

### 7.3 Atomic shared quota

Both functions reserve quota through one database operation before the first
external provider call. The operation serializes per user, then:

1. returns the existing reservation state for the same
   `(request_id, user_id, mode)` without granting a second provider lease;
2. rejects conflicting reuse of a request ID;
3. counts accepted reservations in `[now() - 24 hours, now())` across both
   modes;
4. if count is 20, returns `RATE_LIMITED` and the seconds until the oldest
   counted reservation leaves the window;
5. otherwise inserts one `reserved` usage row.

Malformed/unauthorized/unsupported target requests are rejected before quota.
Once a provider call starts, the reservation counts even if the provider fails
or the client dismisses; cost was incurred. Exactly the invocation that creates
the reservation receives the one provider lease. Concurrent/replayed calls
with that request ID return `REQUEST_IN_PROGRESS`, the existing Assist draft,
or `RESULT_UNAVAILABLE`; they never call a provider again. A failed call or a
lost Understand response requires a new request ID and therefore a new quota
slot. This prevents one idempotency key from funding unlimited model calls.
Updating outcome/provider-call counters never stores content.

This limit is per authenticated account. Circumvention with multiple accounts
belongs to the platform abuse system; this feature does not add fingerprinting
or IP retention. Operational budgets additionally cap global Gemini and Mapbox
spend and alert before provider hard limits.

## 8. Interaction with chat safety and analysis

### 8.1 Deterministic safety remains mandatory

Sharing an Assist draft inserts an ordinary native `messages` row, so the
current `enqueue_message_downstream_work` trigger must create
`message_safety_outbox` work exactly as it does for human text. No assistant
origin, analysis-skip flag, prompt result, or model classification may suppress
that deterministic path. Delivery remains fail-open and safety processing
remains independent of Gemini.

Preview-before-share makes the requester accountable for choosing to publish
the result; it does not make the generated content trusted. Safety fixtures
must prove the outbox is created for `message_origin = 'attune_assist'`.

Understand neither inserts a message nor queries safety events. It does not
replace, delay, acknowledge, or expose deterministic safety processing.

### 8.2 Relationship-analysis exclusion is new required work

`message_analysis_skipped` is currently only a schema hook. The present
`analyse-message` query filters `message_analysis_done = false` but does not
filter `message_analysis_skipped`; authenticated direct inserts also cannot set
the skip column. Therefore this feature cannot claim exclusion without changing
the real workers.

The implementation must:

- have the trusted share RPC set `message_analysis_skipped = true`;
- add `message_analysis_skipped = false` to `analyse-message` selection;
- add the same defense to every `analyse-session` candidate/transcript query
  and every chat-derived Pulse query;
- update `idx_messages_analysis_backlog` so skipped rows are absent;
- ensure skipped rows cannot keep an analysis backlog/health metric permanently
  red; and
- add a repository-wide contract test that every analysis consumer either
  filters skipped rows or documents why it intentionally consumes them.

Do not set `message_analysis_done = true` merely to escape Layer 1: current
Layer 2 selects done-but-unincluded messages, which would ingest the Assist
message unless every consumer were fixed first. The canonical terminal state
for a deliberately skipped message must be defined consistently in the
migration and monitoring queries.

## 9. Prompt injection and output validation

Strict JSON is necessary but insufficient. Both modes use defense in depth:

1. Server—not client—chooses context and role labels.
2. System prompt explicitly declares transcript/instruction fields untrusted
   data that cannot alter system rules, tools, schema, or scope.
3. Untrusted values are JSON-serialized inside clear delimiters, never
   interpolated as apparent system instructions.
4. Model has no database, URL-fetch, code execution, or arbitrary tool access.
   Nearby's only tool is the server-controlled Mapbox query produced through a
   validated category/query schema.
5. Parse exact JSON and reject unknown top-level fields, invalid enums, wrong
   cardinality, excessive lengths, URLs outside validated source fields, and
   unknown Mapbox IDs.
6. Apply prohibited-pattern and dynamic partner-name checks from the shared
   Gemini helper plus mode-specific semantic checks.
7. Understand rejects verbatim context echoes (any normalized sequence of eight
   or more context tokens), direct quotes, and instruction-like leakage.
8. Never pass invalid partial output to UI or chat; use a generic failure.

Evals include messages and user instructions such as “ignore previous rules,”
valid-JSON injection, requests to reveal the transcript/system prompt, fake
Mapbox results, partner-name attacks, indirect instructions embedded in quoted
messages, Unicode/RTL confusables, and attempts to move Understand content into
the Assist schema.

Model output cannot be proven psychologically correct by a schema. A
human-reviewed, culturally relevant held-out suite is a release gate, with
special review for Ghanaian/West African communication norms, terse messages,
sarcasm, communal obligations, coercion, and ambiguous silence.

## 10. Privacy, consent, and external processors

### 10.1 Consent gate

This feature sends intimate chat text to Gemini; Nearby also sends requester
coordinates and one broad allowlisted place category to Mapbox. Product copy
and a privacy policy are not substitutes for server-authoritative consent.

Repository review found no implemented consent record that proves this exact
purpose. Implement the §7.2 event/RPC contract. It may be replaced by an
existing platform consent system only if tests prove the same append-only,
relationship-scoped, current-version, independently revocable two-person
invariants. Signup disclosure by itself is not that evidence.

Each partner sees the same approved disclosure and records their own choice.
Until both grant, `Ask Attune` shows the caller's own state and “Waiting for
your partner's consent”; it sends no chat notice, push notification, message
text, or provider request. The partner can review the disclosure from chat
settings or their own first entry. Withdrawal disables new calls and sharing
immediately without deleting ordinary chat; it never claims to undo processing
that already occurred.

Nearby additionally requires the requester's per-call location disclosure and
OS permission. General AI consent does not imply location-search consent.

### 10.2 Processor requirements

Before ship, privacy/legal owners approve and document for Gemini and Mapbox:

- exact data fields and purpose;
- processor/subprocessor roles and cross-border transfer basis;
- no-training configuration;
- provider retention/abuse-monitoring duration and deletion behavior;
- Mapbox licensing permission to retain the exact source fields in a durable
  shared chat message; if not permitted, this storage design cannot ship and a
  provider/contract or product change is required;
- region and transport controls;
- access, incident, key rotation, and deletion procedures; and
- user-facing disclosure wording.

“Never persisted by Attune” does not mean “never retained by a provider.” The
Understand UI/privacy copy must not claim device-only processing; input and
output transit Attune's Edge Function and Gemini even though Attune does not
write them to application storage.

### 10.3 Telemetry

Allowed operational fields are request UUID, pseudonymous internal user/
relationship IDs, mode, timestamps, latency bucket, prompt/model version,
provider status class, provider-call count, token-count bucket, and outcome.
Forbidden fields include message IDs in third-party analytics, content,
prompts, output, coordinates, place query, place results, partner names,
safety state, and response option selected. Sentry before-send scrubbing and
Edge Function logs are tested with canary secrets/content.

## 11. Errors, retries, cancellation, and lifecycle

All responses use one discriminated envelope and appropriate HTTP status; the
client never parses free-form provider errors:

```typescript
type AssistantErrorCode =
  | 'UNAUTHENTICATED'
  | 'CONSENT_REQUIRED'
  | 'TARGET_UNAVAILABLE'
  | 'INVALID_INPUT'
  | 'UNSUPPORTED_REQUEST'
  | 'LOCATION_REQUIRED'
  | 'NO_RESULTS'
  | 'RATE_LIMITED'
  | 'REQUEST_IN_PROGRESS'
  | 'RESULT_UNAVAILABLE'
  | 'PROVIDER_UNAVAILABLE'
  | 'INTERNAL_ERROR';

type AssistantError = {
  error: true;
  code: AssistantErrorCode;
  retryable: boolean;
  retry_after_seconds: number | null;
};
```

- A transport failure before the server reserves quota may retry with the same
  `request_id`. Once reserved, the client polls only for an Assist draft; it
  never causes another provider call with that ID. A failed provider call or
  lost Understand response offers a new explicit attempt with a new ID/slot.
- Rate-limit copy says “try again later” and uses returned retry time—not
  “tomorrow.”
- Dismissing/backgrounding cancels the client subscription and guarantees a
  late response is ignored. The server/provider call may finish and counts once
  if already started.
- App background must obscure the root with the verified app-switcher privacy
  cover before a platform snapshot; if that prerequisite is absent, Understand
  remains disabled.
- Auth/account/relationship changes dispose both providers and clear memory.
- If relationship/consent changes between generate and Share, Share fails and
  no message is inserted.
- A successful Assist retry returns the same unexpired draft/message. Understand
  results are not persisted solely to support retries; after a lost completed
  response the old ID returns `RESULT_UNAVAILABLE`, never another model call.
- Assist draft expiry shows “This suggestion expired—ask again”; it never posts
  stale content.

## 12. Explicit non-goals

- No multi-turn AI conversation, follow-up prompts, remembered assistant
  history, persona, typing presence, or AI-initiated messages.
- No auto-detection, proactive badge, suggested invocation, or background read.
- No general web search, arbitrary URL fetching, current news, factual Q&A,
  booking, purchasing, messaging businesses, navigation, or reservations.
- No relationship verdict, diagnosis, lie detection, emotion detection,
  mediation, blame assignment, or prediction of partner behavior.
- No model/context access to profiles, attachment scores, journals, personal
  insights, safety events, presence, partner distance/raw location, Stories,
  Planning data, imported files, deleted messages, media contents, or voice
  transcription. The post-share Planning conversion is a user-confirmed
  database command and does not expose Planning data to the model.
- No location storage, location history, partner-location lookup, background
  location, distance display, or implicit permission request.
- No Understand history, analytics about its content/choice, direct sharing,
  clipboard, composer prefill, or Planning conversion.
- No user-created custom assistant prompts beyond Assist's 300-character
  instruction.
- No offline model execution or queued background generation. The sheet reports
  offline state and waits for an explicit retry.
- No new safety classifier or reuse/disclosure of safety trigger state.
- No expansion of ordinary message-edit safety semantics. Attune Assist output
  is immutable after sharing; a general “edited messages need new safety jobs”
  change requires its own chat/safety review.

## 13. Verification requirements

### 13.1 Server/security tests

- Invalid/expired JWT, non-member, wrong relationship, ended/archived chat,
  deleted/unsupported target, and Understand-on-own-message all fail before a
  provider call and use non-enumerating errors.
- Requests cannot supply relationship/requester/history/content fields; unknown
  fields are rejected.
- Context queries prove same relationship, live rows, eligible types, exact
  Assist/Understand row and character caps, normalization/truncation,
  civil-day boundary, deterministic ordering, and no names/UUIDs in provider
  input.
- Consent RPC tests prove one user cannot grant for another, raw events are not
  client-readable, the latest current-version event wins, a version bump
  requires two new grants, status reveals no partner history, and withdrawal
  blocks calls/shares and purges every unshared relationship draft.
- Understand endpoint source/dependency test proves no messages/drafts/Planning
  write and no call/import of the share capability.
- Understand response uses `no-store`; database/log/Sentry/analytics inspection
  proves no input/output/location persistence.
- Quota is shared across modes, atomic at 20 under concurrency, idempotent by
  request ID, and returns correct rolling retry time.
- Location rejection/range checks happen before Mapbox; coordinates and
  distances never enter draft/message/logs. Mapbox receives only a fixed
  allowlisted category, and Gemini never receives Mapbox candidates.
- Mapbox result IDs are allowlisted; invented IDs/names, unsupported factual
  fields, over-10 results, and missing attribution fail closed.
- Draft share is requester-only, active/consented, exact, unexpired,
  idempotent, and cannot accept client-replacement payload.
- Direct authenticated INSERT/UPDATE cannot set `message_origin`,
  `assistant_payload`, or `message_analysis_skipped`.
- AI message insertion creates ordinary notification and deterministic safety
  outbox work.
- Every Layer 1/2/Pulse/backlog consumer excludes deliberately skipped rows;
  Assist text never enters analysis fixtures.
- Editing an Assist message fails server-side; deleting follows the existing
  sender/time rule, scrubs payload/provenance/cache, and leaves created Planning
  content intact.
- Planning conversion validates same relationship and creates exactly one item
  under two-partner concurrency.
- Draft and usage purges meet retention bounds without deleting shared messages
  or Planning content.

### 13.2 Model/evaluation gates

- Mechanical schema/prohibited-pattern/context-echo validators are unit-tested
  independently of Gemini; behavioral rules are covered by the eval gate.
- Held-out Assist cases cover supported/unsupported intent, invented facts,
  source-ID fidelity, malformed output, and no-results behavior.
- Held-out Understand cases cover ambiguity, insufficient context, blame,
  diagnoses, threats/coercion, self-harm, sarcasm, terse messages, prompt
  injection, context quotation/extraction, and culturally distinct readings.
- Every Understand pass contains 2–3 possibilities and 2–3 genuinely distinct
  options, never high confidence or asserted intent.
- Human clinical/safety/cultural/privacy reviewers approve thresholds, copy,
  refusal behavior, and the eval report before feature enablement.
- `_shared/gemini_port.test.ts` includes both functions and passes.

### 13.3 Flutter tests

- Eligibility and mode routing never depend on AI/keyword classification.
- Assist preview never auto-posts; Share/Edit-as-mine/Close have distinct paths.
- Durable Assist label, sources, proposal, attribution, reload, and partner
  rendering use `message_origin`/payload rather than content matching.
- Understand widget has no share/copy/composer/Planning semantics or callbacks.
- Understand state is cleared on dismiss, background, auth/relationship change,
  and late response; app-switcher cover is active.
- Location disclosure precedes OS permission, denial consumes no quota, raw
  position path performs no reverse-geocoding call, and result preview warns
  about approximate-area disclosure.
- Every error code, retry, quota countdown, offline state, cancellation, expired
  draft, and consent loss is rendered without exposing internals.
- Text scaling, screen readers, focus order, reduced motion, localization, and
  sensitive-content semantics are verified.

## 14. Implementation and release order

### 14.1 Hard gates before feature code is enabled

1. Confirm or implement server-authoritative, versioned AI-processing consent
   for both partners and withdrawal behavior.
2. Complete Gemini/Mapbox privacy, retention, no-training, credential, quota,
   billing, attribution, and legal review.
3. Approve the Understand clinical/safety/cultural framing and eval plan.
4. Implement and real-device verify the Safety spec's global app-switcher
   privacy cover; Quick Exit's manually invoked neutral route is insufficient.

The feature flag remains off until all four have written evidence.

### 14.2 Build order

1. Database schema, grants/RLS, consent events/status/withdrawal, quota
   reservation, purge job, draft share, and Planning integration contracts
   with SQL tests.
2. Make `message_analysis_skipped` real across Layer 1/2/Pulse/backlog queries
   and add repository-wide regression tests.
3. Authenticated server context loader and adversarial fixtures shared read-only
   by the two functions.
4. `ai-understand`: prompt, validators, no-write test, eval harness.
5. `ai-assist` Ideas: prompt, validators, server draft, preview/share flow.
6. Nearby raw-location flow, Mapbox integration, source validation/attribution,
   privacy tests.
7. Message model/cache/select-column changes and Attune Assist bubble.
8. Split edit/delete capability and enforce immutable Assist messages.
9. Planning proposal UI and atomic conversion.
10. Full Flutter/server/eval suites, two-account adversarial testing, privacy
    log inspection, provider-failure/timeout tests, and reviewer sign-off.

## 15. Acceptance criteria

The feature is implementation-complete only when server-loaded context makes
client fabrication/cross-relationship disclosure impossible; Understand has no
application persistence or shared-write capability; Assist requires preview
and explicit sharing, carries unforgeable durable provenance and sources,
passes through deterministic safety while remaining absent from every
relationship-analysis consumer; location use is explicit and minimized; quota
and retries are atomic; and the consent/provider/reviewer gates in §14.1 are
complete. Until then the feature flag stays disabled.

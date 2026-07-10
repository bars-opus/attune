# ATTUNE - CHAT SYSTEM SPECIFICATION

**Version:** 1.3  
**Updated:** July 2026  
**Status:** Ready for engineering implementation; release requires Section 18 gates  
**Part of:** Core Communication Infrastructure  

## Governing documents

This specification is subordinate to, and must be read with:

- `attune/ATTUNE_SOUL.md`
- `attune/ATTUNE_CLINICAL.md`
- `attune/ATTUNE_MASTER_SPEC.md`, especially Sections 4, 5, 8.1, 10, 13, and 17
- `attune/ATTUNE_PRINCIPLES_CHECKLIST.md`
- `algorithms/algorithm_quality_review_checklist.md`
- `SAFETY_SYSTEM_SPEC.md`
- `CONFLICT_TRANSLATOR.md`
- `VERDICT_SYSTEM_SPEC.md`
- `NOTIFICATION_ENGINE.md` (owns the OneSignal contract Section 9 depends on)

If documents conflict, use the hierarchy in the Master Spec. The Master Spec
wins on concrete architecture and schema. The Safety System specification wins
on safety processing details. This document owns chat-specific behavior only.

## Corrections from earlier versions

Version 1.3:

- adds Section 11, Historical chat import: a Month 5, dual-consent-only
  feature letting a couple bring a prior WhatsApp export into Attune's chat
  history. Neither partner can import unilaterally; both must independently
  consent inside the app before any message is ingested. Covers consent flow,
  client-side parsing, safety-system interaction with historical matches,
  deletion/revocation, evidence-provenance confidence, edge cases, and
  production gates. All later sections renumbered (old 11-18 to new 12-19).

Version 1.2:

- names the AFTER INSERT outbox trigger as the mechanism behind "message and
  durable downstream work commit transactionally" (Sections 4.1, 7.1);
- corrects the duplicate-insert contract: a duplicate raises a unique
  violation and the client fetches the canonical row — clients cannot use
  upsert-returning because they hold no UPDATE privilege (Section 3.1);
- enumerates the exact client insert-column grant (Section 5.1);
- adds a Safety-stage latency SLO so Tier 1 notifications and Layer 1
  eligibility cannot silently stall behind worker backlog (Sections 7.2, 14);
- specifies rune-based client length validation (Dart `String.length` counts
  UTF-16 code units, not Unicode scalar values) (Section 3.4);
- defines the mapping between queue states and UI status (Sections 3.3, 4.2);
- documents that `media_url` stores a private object key, not a URL (Section 8.2);
- adds `NOTIFICATION_ENGINE.md` to the governing documents.

Version 1.1:

- replaces MMKV with the Master Spec's Drift/SQLite read cache and outgoing queue;
- replaces direct client receipt updates with authorized RPCs;
- makes sends idempotent with a stable client-generated identifier;
- places the server-authoritative Safety System before normal AI analysis;
- replaces public media URLs with private storage and short-lived signed URLs;
- replaces permissive `FOR ALL` message RLS with operation-specific policies;
- moves push creation, thumbnailing, and analysis triggers to trusted workers;
- separates solo reflections from relationship chat;
- reconciles active, read-only, and archived relationship behavior;
- reconciles Month 1, Month 2, and post-launch scope;
- adds validation, pagination, synchronization, privacy, accessibility,
  observability, failure, testing, rollout, and production-gate contracts.

---

## 1. Feature contract

### 1.1 Purpose

Chat is Attune's private, dyadic messaging surface for an active couple. It
provides reliable text messaging, delivery/read receipts, offline queuing, and
real-time synchronization. Server-side systems may use relationship messages
for the explicitly disclosed Safety and relationship-intelligence pipelines.

Chat must feel like communication first. It must not expose per-message AI
judgments, safety matches, hidden classifications, or partner-attributed
psychological claims.

### 1.2 Permanent rules

- Supabase PostgreSQL is the source of truth.
- Drift is a read-speed cache and durable local outgoing queue, not authority.
- Every send is idempotent across taps, retries, reconnects, and worker replay.
- The authenticated sender can send only as themselves into their active relationship.
- Only trusted server paths can update receipts or analysis fields.
- Safety processing is server-authoritative, deterministic, durable, and
  isolated from normal AI analysis.
- Translator use is pull-only and invisible to the recipient.
- Message media is private and accessible only to current authorized members.
- No message content, media URL, notification preview, or model output may
  appear in operational logs or analytics.
- Relationship chat and personal reflections are separate domains and stores.
- Ending a relationship makes its chat read-only. Archiving makes it inaccessible.

### 1.3 Explicit non-goals

- End-to-end encryption is not claimed in v1.
- Chat is not a social, group, dating, or anonymous messaging system.
- Dating chat is excluded until separately approved by the Dating Chat Safety Plan.
- Personal reflections are not represented as messages.
- Message editing, deletion, reactions, voice, video, and link previews are not
  launch behavior.
- The client never invokes Safety detection or normal AI analysis directly.

### 1.4 Scope by release phase

| Phase | Included |
|---|---|
| Month 1 | Text messages, optimistic UI, realtime sync, Drift cache, offline queue, new-message push, delivery/read receipts |
| Month 2 | Private image sharing, Conflict Translator composer entry, expanded chat-header drawer |
| Month 4 | Voice messages, reactions, message editing/deletion after a separate retention and audit contract |
| Month 5 | Video sharing and link previews after separate moderation/security review; historical chat import (Section 11) after its own dual-consent, Safety, and cultural gates |

Feature flags must prevent later-phase surfaces and backend mutations from
being used before their release gates pass.

---

## 2. Relationship and chat lifecycle

### 2.1 Canonical state

There is exactly one relationship chat per `relationships.id`; there is no
separate chat-section lifecycle.

| Relationship state | Read history | Send | Cache behavior |
|---|---:|---:|---|
| `pending` | No | No | No relationship cache |
| `active`, not archived | Yes, members only | Yes, members only | Normal |
| `paused`, not archived | Yes | No | Read-only |
| `ended`, not archived | Yes | No | Read-only |
| `chat_archived_at IS NOT NULL` | No | No | Purge local cache and queued sends |

When either former partner enters another active relationship, the Master
Spec's server-side archive trigger archives the old relationship chat. A new
partner can never read old relationship messages.

### 2.2 Membership changes

Authorization is evaluated on every server request, signed-URL request, RPC,
and realtime delivery. Cached data is not evidence of continuing access.

On sign-out, account switch, membership loss, relationship archive, or account
deletion, the app must cancel subscriptions and purge the affected local cache,
outgoing queue entries, decrypted media, and signed URLs.

### 2.3 Personal reflections

The chat list may link to Personal Reflections, but reflections use the
`solo_reflections` domain and self-only authorization. They must never be
inserted into `messages`, delivered to a partner, or consumed by relationship
analysis unless a separate explicit-consent contract authorizes a derived input.

---

## 3. Message contract

### 3.1 Server row

The canonical `messages` row is the Master Spec model plus these production
requirements:

```sql
ALTER TABLE public.messages
  ADD COLUMN client_message_id uuid;

UPDATE public.messages
SET client_message_id = gen_random_uuid()
WHERE client_message_id IS NULL;

ALTER TABLE public.messages
  ALTER COLUMN client_message_id SET NOT NULL,
  ADD CONSTRAINT messages_sender_client_id_unique
    UNIQUE (sender_id, client_message_id),
  ADD CONSTRAINT messages_payload_present CHECK (
    (content IS NOT NULL AND char_length(btrim(content)) > 0)
    OR media_url IS NOT NULL
  ),
  ADD CONSTRAINT messages_content_length CHECK (
    content IS NULL OR char_length(content) <= 10000
  ),
  ADD CONSTRAINT messages_receipt_order CHECK (
    read_at IS NULL OR delivered_at IS NOT NULL
  );

CREATE INDEX IF NOT EXISTS idx_messages_relationship_created
  ON public.messages (relationship_id, created_at DESC, id DESC);
```

The index definition above is byte-identical to Master Spec Section 4.3 — it
must stay identical in both documents. Under `IF NOT EXISTS`, a same-name
index with a different shape would silently no-op and leave keyset pagination
unindexed.

Migration implementation must preserve existing rows safely and guard each
operation for the repository's actual migration state. Foreign-key deletion
behavior and analysis indexes remain governed by Master Spec Section 4.3.

`client_message_id` is generated once before the optimistic message is shown.
The same value is retained for every retry.

Duplicate handling: a duplicate insert raises a unique-constraint violation
(Postgres 23505); the client then fetches the canonical row by
`(sender_id, client_message_id)` and reconciles (Section 4.3). Clients cannot
use upsert-returning (`ON CONFLICT DO UPDATE ... RETURNING`) because they hold
no UPDATE privilege on `messages` — treat the violation as success-with-fetch.
A duplicate insert commits nothing, so it creates no additional safety,
analysis, or push outbox work (Section 4.1).

### 3.2 Client model

The app model contains:

- canonical message ID, nullable before acknowledgement;
- stable `clientMessageId`;
- relationship and sender IDs;
- text or media metadata;
- server `createdAt`, plus local queue time while pending;
- `deliveredAt` and `readAt`;
- derived local status;
- local retry metadata that is never uploaded as message content.

AI analysis fields are not part of the presentation model. Chat UI must not
display or branch on `tone_score`, `nvc_violations`, `bid_type`, safety state,
or analysis completion.

### 3.3 Derived delivery status

There are four successful lifecycle states plus a local failure state:

```text
sending -> sent -> delivered -> read
    |         |
    +-> failed <-+
```

- `sending`: queued or request in flight.
- `sent`: canonical row acknowledged by Supabase.
- `delivered`: recipient device has acknowledged receipt.
- `read`: recipient opened and foregrounded the conversation.
- `failed`: send is not progressing without user action.

UI status maps to queue state (Section 4.2) as follows: `queued` with a future
next-attempt time within the automatic backoff window renders as `sending`;
`failed_permanent`, and `queued` items whose backoff attempts are exhausted,
render as `failed` with tap-to-retry/remove. "Failed" in the UI therefore
always means "will not send without user action" — automatic retries are never
shown as failures.

Status never moves backward. `read` atomically implies `delivered`. Sender-visible
timing and response shape must not reveal whether Safety rules matched.

### 3.4 Validation

- Trim only for empty-input validation; preserve intentional user formatting.
- Text maximum is 10,000 Unicode scalar values, enforced client and server side.
  Server side this is `char_length(content)` (code points). Client side, Dart's
  `String.length` counts UTF-16 code units and over-counts astral characters
  (emoji) — validate with `content.runes.length`, never `content.length`.
- Month 1 accepts text only.
- Month 2 accepts text, one image, or text plus one image.
- Reject control-only or whitespace-only text.
- Render text as text; never interpret HTML supplied by a user.
- Server timestamps are authoritative for ordering and receipts.
- Do not accept relationship ID or sender ID without server-side membership checks.

---

## 4. Sending, retry, and offline queue

### 4.1 Send sequence

```text
Generate client_message_id
  -> validate locally
  -> persist outgoing item in Drift
  -> render optimistic message
  -> submit allowed fields to Supabase
  -> database validates auth, active relationship, payload, and idempotency
  -> transaction commits message and durable downstream work
  -> return canonical row
  -> replace optimistic row and remove queue item
```

"Transaction commits message and durable downstream work" has one required
mechanism: an `AFTER INSERT` trigger on `messages` writes the downstream outbox
rows (safety work, notification work; analysis eligibility is derived from the
safety stage per Section 7.1) inside the same transaction as the message. The
client path is a plain authorized insert — it must not be replaced by an edge
function that enqueues work after the fact, because a crash between commit and
enqueue would silently drop safety processing. Outbox inserts use
`ON CONFLICT DO NOTHING` keyed on the message ID so a replayed insert (which
never commits) and worker replay both produce zero duplicate jobs.

The client may insert only:

- `relationship_id`
- `sender_id` equal to `auth.uid()`
- `client_message_id`
- validated `content`
- validated media object key/type when enabled

The client cannot insert or update timestamps, receipt fields, analysis fields,
safety fields, or session links.

### 4.2 Queue contract

The Drift queue is scoped by authenticated user and relationship. Each entry has:

- `client_message_id` primary key;
- sender and relationship IDs;
- payload or staged local-media reference;
- enqueue time;
- attempt count and next-attempt time;
- last coarse error category;
- state: `queued`, `sending`, `failed_permanent`.

Flush one logical message at a time per relationship in enqueue order. A
transient failure uses bounded exponential backoff with jitter. Authentication,
membership, archived relationship, invalid payload, and rejected media are
permanent failures requiring a user-visible action. Never retry forever.

App termination between server commit and local acknowledgement is safe because
the next insert uses the same `client_message_id`.

### 4.3 Retry behavior

Tap-to-retry reuses the queue item and `client_message_id`; it never attempts to
update a nonexistent optimistic row. If the server reports a duplicate, fetch
and reconcile the canonical row. If the relationship became read-only or
archived, stop retrying and explain that the message was not sent.

### 4.4 Local storage security

- Drift database files use platform-appropriate encryption where supported by
  the approved storage package and are excluded from backups where feasible.
- Never store signed media URLs as durable authority; store private object keys.
- Clear message caches and staged media on the lifecycle events in Section 2.2.
- Local diagnostics contain IDs only when necessary and never content.

---

## 5. Authorization and database mutations

### 5.1 RLS

Message policies extend, and never weaken, Master Spec Section 4.2:

```sql
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;

CREATE POLICY messages_select_members
ON public.messages FOR SELECT TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.relationships r
    WHERE r.id = messages.relationship_id
      AND (r.user_a = auth.uid() OR r.user_b = auth.uid())
      AND r.chat_archived_at IS NULL
  )
);

CREATE POLICY messages_insert_sender_active
ON public.messages FOR INSERT TO authenticated
WITH CHECK (
  sender_id = auth.uid()
  AND EXISTS (
    SELECT 1 FROM public.relationships r
    WHERE r.id = messages.relationship_id
      AND (r.user_a = auth.uid() OR r.user_b = auth.uid())
      AND r.status = 'active'
      AND r.chat_archived_at IS NULL
  )
);
```

There is no authenticated client `UPDATE` or `DELETE` policy at launch. Never
use `FOR ALL` on messages.

Column privileges must revoke broad insert/update access and grant exactly the
user-writable insert columns — identical to Master Spec Section 4.2:

```sql
REVOKE INSERT ON public.messages FROM authenticated;
GRANT INSERT (relationship_id, sender_id, client_message_id, content,
              media_url, media_type)
  ON public.messages TO authenticated;
```

`media_thumbnail_url` is deliberately absent — thumbnails are written by the
trusted worker (Section 8.3). Service-role workers own all downstream fields.

### 5.2 Receipt RPCs

`mark_delivered(p_message_ids uuid[])` and
`mark_conversation_read(p_relationship_id uuid)` are `SECURITY DEFINER`
functions with a fixed safe `search_path`. They must:

- require an authenticated caller;
- verify current, non-archived relationship membership;
- update only messages sent by the other relationship member;
- set timestamps only when null;
- make `read_at` imply `delivered_at` in the same statement;
- cap input arrays and affected rows;
- return only IDs and resulting receipt timestamps;
- reveal no unauthorized row through result shape or error details.

Revoke function execution from `PUBLIC` and `anon`; grant only to
`authenticated`. Add multi-account SQL tests proving sender, partner, outsider,
former member, and archived-chat behavior.

### 5.3 Trusted server writes

Only trusted server roles may write:

- delivery/read receipt fields through the constrained RPC path;
- analysis completion and result fields;
- session links;
- notification/outbox state;
- media processing state;
- safety processing state.

No edge function may trust user-supplied sender identity or relationship membership.

---

## 6. Realtime synchronization

### 6.1 Subscription lifecycle

Subscribe to `INSERT` and receipt-relevant `UPDATE` events for the current
relationship after loading cached state. Cancel on route disposal, sign-out,
account switch, membership loss, and archive.

Realtime is an invalidation/delivery mechanism, not guaranteed history. On
initial load and every reconnect, fetch canonical rows after the newest known
server cursor before declaring the view synchronized.

### 6.2 Deduplication and ordering

Merge by canonical ID and then `(sender_id, client_message_id)`. Order by
`created_at`, then `id` as a stable tie-breaker. Realtime delivery, initial
fetch, optimistic acknowledgement, push-open fetch, and queue flush may arrive
in any order and must converge to one message.

### 6.3 Pagination

- Load the newest page first.
- Use keyset pagination on `(created_at, id)`, never offset pagination.
- Page size is configurable, initially 50.
- Drift retains the newest 200 messages per relationship.
- Older server history remains fetchable while authorization permits.
- Preserve scroll position when prepending older rows.

### 6.4 Receipt behavior

On receiving a partner message through realtime or after push-open catch-up,
batch `mark_delivered`. When the conversation is visible, foregrounded, and the
message list has rendered, debounce and call `mark_conversation_read`.

Receipt failures do not block message display and are retried idempotently.

---

## 7. Safety and analysis integration

### 7.1 Authoritative pipeline

The Chat System follows the Safety System specification exactly:

```text
Authenticated send
  -> message and durable safety work committed transactionally
     (AFTER INSERT outbox trigger — Section 4.1)
  -> client receives normal acknowledgement
  -> safety worker performs deterministic detection
  -> safety stage records success or handled failure
  -> normal Layer 1 analysis becomes eligible
  -> later session, pattern, Pulse, and Verdict pipelines consume authorized data
```

Safety matching never runs on either client. A match never blocks, modifies,
labels, delays into a distinguishable timing class, or removes the message from
normal analysis. Safety events contain no message content, excerpt, sender ID,
or direct message ID and use the Safety spec's non-reversible source key.

### 7.2 Reliability

- Downstream jobs are at-least-once with idempotent effects.
- Durable work is created in the same transaction/outbox as the message.
- Transient failures retry with bounded backoff and jitter.
- Permanent failures enter restricted dead-letter handling.
- Safety failure does not block chat delivery indefinitely.
- Normal AI failure never blocks Safety processing or chat delivery.
- Backlog age and failure rate are monitored without message content.
- Safety-stage latency SLO: because the safety stage sits in front of both the
  at-risk user's Tier 1 notification and Layer 1 eligibility, it carries an
  explicit target — p95 from message commit to recorded safety completion
  under 30 seconds, p99 under 2 minutes — with a paging alert when breached
  (Section 14). "Bounded backoff" is not a substitute for this target; if
  SAFETY_SYSTEM_SPEC.md defines a stricter SLO, that one wins.

### 7.3 Clinical and presentation boundary

Chat displays messages and user-invoked tools. It does not display hidden
per-message tone labels, NVC violations, safety matches, bid classifications,
or claims about partner intent. Derived Insights, Pulse, Verdict, and Conflict
Translator output obey their own clinical and evidence contracts.

---

## 8. Private image sharing (Month 2)

### 8.1 Upload contract

- Feature-flagged off until Month 2 gates pass.
- Accept approved image MIME types only; do not trust filename extensions.
- Strip EXIF and location metadata before upload.
- Correct orientation, resize longest useful dimension, and compress to at most 800 KB.
- Reject files that cannot meet size limits or fail decoding.
- Use random server-safe object keys; never include names, phone numbers, or user IDs.
- Upload only to private bucket `message-media`.
- Object path is bound to the authorized relationship and message upload intent.

The client first obtains a short-lived authorized upload intent. The backend
validates active membership, expected MIME type, size, and object path. An
uploaded object not attached to a valid message within the expiry window is
deleted by cleanup work.

### 8.2 Reading media

Store the private object key, not a public URL. Note the column-name trap:
`messages.media_url` holds this private object key (bucket path), never a
fetchable URL — code must not sign, log, or render its raw value as a URL.
(Kept as `media_url` for Master Spec schema compatibility; the semantic is
documented here and in the repository's message model.) Authorized members
obtain short-lived signed URLs after current membership and archive checks. Do not put
signed URLs in logs, analytics, push payloads, or durable cache.

When a chat is archived, media access is denied even if an old local URL has
not yet expired. Signed-URL lifetime must be short enough for that residual
window to meet the privacy review's approved limit.

### 8.3 Thumbnail worker

Thumbnail generation is an internal worker triggered by trusted upload work,
not a public service-role endpoint. It validates the object, decodes with
resource limits, creates a 400px thumbnail, writes to the same private scope,
and records coarse success/failure only. Protect against decompression bombs,
malformed images, oversized dimensions, and unsupported formats.

### 8.4 Media deletion

Account deletion and relationship deletion workflows delete database references,
originals, thumbnails, orphaned uploads, staged local files, and cached files
according to Master Spec retention rules. Failures are retried and monitored.

---

## 9. Push notifications

### 9.1 Authority and delivery

New-message notifications are created by trusted backend/outbox processing
after message commit. Clients never send OneSignal notifications directly and
never choose another user's push destination.

Notification work is idempotent per `(recipient_id, message_id, type)`. Do not
send delivery/read push notifications at launch. In-app ticks are sufficient.

### 9.2 Privacy

Default lock-screen copy is generic, for example `New message in Attune`.
Message previews require an explicit user setting, default off, and must still
respect OS-level preview settings. Never include raw content in custom data;
route using a non-sensitive notification/work identifier resolved after auth.

Do not send if the relationship is archived, the recipient blocked notifications,
the sender and recipient are invalid, or the recipient is already actively
viewing that conversation. Push failure never changes message delivery state.

---

## 10. Conflict Translator integration (Month 2)

The composer exposes `Help me say this` only when non-empty draft text exists
and the feature is enabled. It follows `CONFLICT_TRANSLATOR.md`:

- user invocation only; never automatic suggestion;
- draft is not sent until the user explicitly chooses;
- user may send original, send rewrite, or edit rewrite;
- recipient receives an ordinary message with no translator indicator;
- translation logs contain metadata only, never either text;
- translator failure preserves the draft and does not block ordinary sending;
- send-after-translation uses the normal idempotent Chat send path.

The draft and translator result are private to the composing user. They are not
written to relationship messages until send is confirmed.

---

## 11. Historical chat import (Month 5, dual-consent only)

### 11.1 Purpose and framing

Attune's chat is new; a couple's relationship is usually not. This feature lets
a couple who choose to import a prior conversation history (WhatsApp export
initially; other sources may be added later) bring that history into Attune so
pattern detection and Pulse have material to work with sooner than four weeks
of new messages would otherwise provide.

This is explicitly **not** a growth or cold-start hack bolted onto onboarding.
It is a deliberate, opt-in, dual-consent data operation, gated behind the same
ethical architecture as everything else in Chat. If it cannot be built to that
standard, it does not ship. See `attune/ATTUNE_MASTER_SPEC.md` Section 16 for
the open-question record and `attune/ATTUNE_SOUL.md` for the surveillance and
consent principles this feature must not violate.

### 11.2 Why dual consent is structural, not a checkbox

An imported history is not one person's data. It contains the other partner's
words, sent before they had any relationship with Attune, without any
expectation that an AI would ever read them. A single-partner upload would let
one person unilaterally subject the other's past private speech to analysis —
which is precisely the "surveillance tool," "evidence-gathering weapon," and
asymmetric-power pattern the permanent constraints exist to prevent. Compare
`attune/ATTUNE_MASTER_SPEC.md` Section 11, constraints 1 and 3: this feature
must not create a new way to violate either.

Therefore: **an import is inert until both partners independently, separately
confirm it inside the app.** Neither partner can complete the consent on the
other's behalf, and there is no way to import with only one signature. Import
consent is a distinct, revocable grant — separate from account terms, from
couples-onboarding consent, and from ordinary chat use.

### 11.3 Eligibility

- Both users have completed couples onboarding and the relationship is
  `active` (Master Spec 8.8, 9). Import is not available in `pending`,
  `paused`, `ended`, or archived relationships.
- Feature-flagged off until Month 5 gates pass (12.2), independent of every
  other chat feature flag.
- Available to either partner as the uploader; the other partner is always
  the approver.

### 11.4 Consent flow (both required, in order)

```text
Partner A (uploader)
  -> opens "Import chat history" from chat settings
  -> reads the disclosure screen (11.5)
  -> selects a source file (WhatsApp .txt/.zip export)
  -> client-side parses and previews: date range, message count,
     participant labels the parser detected — no message content
     shown yet beyond a small on-device redacted sample for A to
     confirm this is the right file
  -> A confirms intent to request import
  -> server creates an import_request row: state = 'pending_partner_consent'
  -> B is notified: "Partner A wants to bring in a previous conversation
     history from [source]. Review and decide."

Partner B (approver)
  -> opens the same disclosure screen (11.5), with the same explanation
     A saw — B is never shown message content before consenting
  -> B may Approve or Decline; there is no default and no expiry-implied
     approval
  -> Decline: request closes permanently; A is told only "your partner
     chose not to proceed"; B's reason, if any, is never shared with A;
     A may not resubmit the same request but may start a new one after
     a cooldown (anti-nagging)
  -> Approve: server creates a second, independent consent record for B
     -> import proceeds only when BOTH consent records exist
```

Both consent records are append-only rows carrying user ID, policy version,
timestamp, and action (`granted`/`declined`) — the same pattern as
`attune/ATTUNE_MASTER_SPEC.md` Section 4 consent logging elsewhere in the app.
Either partner may revoke consent up to the point the import job starts
processing; once file parsing begins, revocation stops the job and deletes
already-processed data (11.9) rather than blocking retroactively.

### 11.5 Disclosure screen (shown identically to both partners)

Required content, in plain language, before either signature is possible:

- what will happen: messages from the selected file will be added to this
  relationship's Attune chat history, dated as they originally occurred;
- that both partners' words in the imported file will be analyzed by the same
  AI pipeline that reads new Attune messages (Master Spec Section 5) —
  this is not a private-to-one-partner feature;
- that historical messages will be checked by the Safety System the same as
  new messages (11.8) and that a match could surface a resource notification
  today, about something said in the past;
- that imported messages are labeled with their true origin and cannot be
  used as verdict-grade evidence at full confidence (11.10);
- that either partner can decline, and declining is never revealed to the
  other partner beyond a generic outcome;
- that either partner can request deletion of imported history at any time,
  separate from deleting the relationship (11.9);
- a link to the same privacy disclosures that govern Chat generally
  (`attune/ATTUNE_MASTER_SPEC.md` Section 10).

This screen is versioned. A content change requires both partners to
re-consent for any import initiated after the version bump; existing completed
imports are not retroactively invalidated.

### 11.6 Supported source and parsing

- Launch source: WhatsApp chat export (`.txt` inside a `.zip`, or bare `.txt`
  without media). Other sources (iMessage, Telegram, SMS) are out of scope at
  launch — iMessage in particular has no user-accessible bulk export path on
  iOS, which is why WhatsApp is the only source with a realistic parse target.
- Parsing happens **client-side first, on-device**, before any network
  upload: the raw export file is never transmitted to Supabase in its
  original form. The client parses lines into `(timestamp, sender_label,
  text)` tuples locally, using the pattern already required for the two
  participant labels the export contains.
- The client must disambiguate which exported sender label maps to which
  Attune user. This mapping is confirmed explicitly by the uploader during
  the preview step (11.4) and is not guessed silently — a wrong mapping would
  attribute one partner's words to the other, which is a correctness and
  trust failure, not a cosmetic one.
- Only text content is imported at launch. Media referenced in the export
  (`<Media omitted>` placeholders, or attached image files in a `.zip`) is
  **not** imported — this avoids re-deriving Section 8's private-media
  pipeline for historical files with unknown provenance, unknown consent
  chain for the images specifically, and unknown moderation status. A future
  version may add media import as a separate, further-gated feature.
- Reject files exceeding a configured size/message-count ceiling client-side
  before any upload attempt; reject files that fail to parse as a WhatsApp
  export format with a clear "we couldn't read this file" error, never a
  silent partial import.

### 11.7 Server-side ingestion

```text
Both consents exist
  -> client uploads the parsed, structured tuple list (not the raw export
     file) to a user-JWT edge function scoped to this relationship
  -> server re-validates: both consent records present and not revoked,
     relationship active, uploader is a current member
  -> server creates one `chat_import_job` row (state, counts, error info)
  -> server inserts messages in chronological order, backdated to their
     original `created_at`, each carrying:
       - `source = 'import:whatsapp'`
       - `import_job_id`
       - `sender_id` per the confirmed mapping (11.6)
  -> insertion reuses the existing messages INSERT path and idempotency
     contract (Section 3.1) — one client_message_id per imported message,
     deterministically derived from (import_job_id, source line number) so
     a retried/resumed job cannot duplicate rows
  -> imported messages flow through the same AFTER INSERT outbox trigger
     as any other message (Section 4.1) — Safety and Layer 1 analysis are
     never bypassed for imported content
  -> job completes with a summary count; failures are partial-safe (11.6's
     "no silent partial import" — a failed job reports how many messages
     were committed before the failure, and either partner can resume or
     abandon)
```

Imported messages do not re-trigger delivery/read receipt flows (Section 3.3)
— they are marked delivered and read at insertion time, since both partners
already know this history exists. They do not generate push notifications
(Section 9) regardless of how far in the past they land.

### 11.8 Safety System interaction

Historical messages are not exempt from Safety detection
(`SAFETY_SYSTEM_SPEC.md`) — exempting them would create a loophole where
importing old messages is a way to smuggle content past the safety net, and
would also mean genuinely dangerous historical patterns go unseen by the one
person the system exists to protect.

However, a match on a message from a year ago is a different situation than a
match on a message sent five minutes ago, and the notification design must not
imply the danger is current when it is not:

- Tier 1 (explicit threat) and Tier 2 (isolation/control) matches on imported
  content still generate the same recipient-only, generic resource
  notification as live matches — the safety system's job is to surface
  resources when relevant evidence exists, not to editorialize about recency.
- The notification copy for import-sourced matches must not claim the
  message was "just sent" — generic copy ("Some resources are available")
  already avoids this by construction (Master Spec 8.7), so no new copy
  variant is needed; this is a confirmation that the existing generic
  language remains correct for the historical case rather than a new
  requirement.
- Tier 3 (pattern-based, requires 3+ occurrences) may span both imported and
  new messages when computing its threshold — a pattern that appears twice in
  imported history and once in new chat is still a real pattern.
- Import jobs process the full Safety pass **before** the job is reported
  complete to the uploader, so a large import does not silently defer safety
  processing to "eventually." A very large import may batch this work, but
  the job cannot be marked done while safety analysis is still queued.

This section requires the same DV-professional review as the rest of the
Safety System before production (Master Spec Section 12); "does a historical
match need different routing or copy than a live match" is an open question
for that review, not a decision made unilaterally here.

### 11.9 Deletion and revocation

- Either partner may delete the imported history independently, without the
  other's consent — deletion is not itself a data operation on the other
  partner's rights the way import is; it only removes data, symmetrically for
  both, from a shared surface both already have equal access to.
- Deleting an import removes: the messages themselves, any patterns/insights
  whose only supporting evidence was imported content (recomputed without
  it, not left dangling), and the `chat_import_job` record's detailed
  contents (retaining only an anonymized audit trace: that an import
  occurred and was later deleted, per Master Spec Section 10 retention
  rules).
- Revoking consent mid-job (11.4) triggers the same deletion path for
  whatever portion had already been committed.
- Relationship-ending or archive behavior (Section 2.1) applies to imported
  messages exactly as it does to any other message — they are part of the
  one sealed chat, not a separate store.

### 11.10 Evidence provenance and confidence

Imported messages are real messages and are treated as real messages for
Safety and for ordinary chat display — a partner should be able to scroll
back and see their actual history, not a filtered version. The provenance
label matters for the *interpretive* layers, not for chat itself:

- Layer 2/4 session and pattern analysis (Master Spec Section 5) may treat
  imported sessions the same as native sessions structurally, but the
  evidence-provenance rules already required for Verdict
  (`VERDICT_SYSTEM_SPEC.md`) and personal insights must record `source_type =
  'import'` on any pattern or insight derived predominantly from imported
  messages.
- Import-sourced evidence carries a **lower** framework-confidence ceiling
  than native evidence by default — the parser cannot fully verify sender
  attribution edge cases (group-export quirks, edited/forwarded-message
  markers, timezone drift in older exports), so claims resting only on
  imported evidence should hedge one level down from what the same evidence
  quantity would earn if it were native (`attune/ATTUNE_CLINICAL.md`
  framework-confidence tiers). This is a conservative default pending
  clinical review, not a permanent ceiling.
- The Verdict and Insight UI must be able to show, when asked, that a cited
  pattern includes imported history — consistent with the transparency
  already required of every sourced claim (Master Spec Section 7, Verdict
  evidence-ID requirement) rather than a new UI surface.

### 11.11 Edge cases

| Case | Required behavior |
|---|---|
| Uploader picks a file that isn't a WhatsApp export | Reject client-side with a clear parse error before any consent request is created |
| Uploader mis-maps sender labels | Preview step (11.4) requires explicit confirmation of the mapping; no silent guess |
| Partner B declines | Request closes; A told only a generic outcome; B's reasoning never shared; cooldown before a new request |
| Either partner revokes mid-import | Job stops; already-committed imported messages and their derived evidence are deleted (11.9) |
| Import contains a Tier 1 safety match from years ago | Recipient-only generic notification fires the same as for a live match; copy does not imply the event is current |
| Import job fails partway | Partial commit is reported honestly with a resume/abandon choice; never silently truncated |
| Relationship ends before import completes | Job is cancelled; partial data is deleted, not left as an orphaned partial history |
| Former partner's re-export contains a third relationship's messages | Client-side parse only extracts the two-participant conversation matching the confirmed mapping; unrelated conversations in a multi-chat export are never selectable |
| User attempts a second import after one is already present | Allowed, but the disclosure and dual-consent flow repeats in full for the new file; imports do not silently merge without fresh consent |

### 11.12 Production gates

Historical import may not release until, in addition to the standard Chat
gates (Section 18):

- [ ] Safety System professional review explicitly covers historical-match
      routing and copy (11.8).
- [ ] Legal/privacy review approves third-party-export data handling,
      including that the export file itself is never transmitted or stored
      in raw form off-device.
- [ ] Clinical review approves the reduced-confidence treatment of
      import-sourced evidence (11.10).
- [ ] Dual-consent flow passes a four-account test proving one partner alone
      cannot create, approve, or infer the content of an import without the
      other partner's independent action.
- [ ] Cultural review confirms the disclosure and decline-notification copy
      reads as respectful and non-coercive in Ghanaian/West African use.

---

## 12. User experience

### 11.1 Chat list

Show the active relationship conversation, unread count, generic media preview,
and Personal Reflections as a separate destination. Never expose hidden
analysis or safety status in message previews.

### 11.2 Conversation

Required states:

- cached loading followed by synchronization;
- empty conversation;
- active conversation;
- read-only paused/ended conversation;
- archived/inaccessible conversation;
- offline with queued messages;
- reconnecting and synchronized;
- failed send with retry/remove action;
- media upload/processing/failure when enabled;
- recoverable and terminal authorization errors.

The header always shows partner context and Pulse according to the Master Spec.
The Month 2 drawer shows current Pulse and delta, latest eligible unread Insight,
next reminder, and routes to Pulse/Insights. Missing data has a neutral empty state.

### 11.3 Composer

- Preserve drafts across temporary navigation and translator use.
- Disable double submit while retaining idempotent protection.
- Clearly distinguish queued, sending, and failed messages.
- In read-only state, replace composer with a plain explanation.
- Do not reveal safety or analysis processing.
- Keyboard, safe-area, text scaling, and screen-reader behavior must be tested.

### 11.4 Accessibility and localization

- Every status icon has a semantic label; meaning never depends on color alone.
- Tick states meet contrast requirements in light and dark themes.
- Touch targets are at least 44x44 logical pixels.
- Dynamic text does not hide send, retry, or read-only explanations.
- Screen readers announce new incoming messages without repeatedly reading history.
- Relative times have accessible absolute-time labels.
- Copy supports localization and Ghanaian/West African cultural review; do not
  hard-code English sentence fragments into widgets.

---

## 13. Architecture and implementation boundaries

### 12.1 Flutter structure

Follow Master Spec Section 17:

```text
lib/features/chat/
  data/
    local/
    remote/
    repositories/
  domain/
    models/
    services/
  presentation/
    controllers/
    screens/
    widgets/
```

Use Riverpod `Notifier`/`AsyncNotifier` patterns consistent with the repository.
The controller coordinates domain operations; widgets do not call Supabase,
OneSignal, storage, Safety, or AI services directly. Dispose subscriptions and
avoid mutable message objects.

### 12.2 Feature flags

Server-authoritative flags, with safe local defaults off, cover:

- image sharing;
- Conflict Translator entry;
- expanded header drawer;
- historical chat import (Section 11), independent of every other flag;
- any post-launch message type;
- push previews.

Flags can disable creation immediately without making existing authorized text
history unreadable. Rollback must not require an app-store release.

### 12.3 Error taxonomy

Repositories map internal failures to coarse domain errors:

- offline/transient;
- unauthenticated;
- relationship inactive;
- relationship archived;
- payload invalid;
- media rejected;
- rate limited;
- unavailable;
- unknown with correlation ID.

User copy gives a safe next step and never exposes SQL, stack traces, policy
names, storage paths, safety state, model output, or another user's existence.

---

## 14. Privacy, retention, and security

- Disclose that server access is required for delivery and opted-in Attune intelligence;
  never claim E2EE.
- Encrypt data in transit and at rest using approved platform controls.
- Never use message data for model training.
- Raw content is prohibited from analytics, crash reports, logs, traces, push
  custom data, support tooling defaults, and admin dashboards.
- Access to production message data is least-privilege, audited, time-bound,
  and covered by an approved incident process.
- Account export/deletion and relationship lifecycle follow Master Spec Section 10.
- Server rate limits cover sends, receipt RPCs, signed URLs, uploads, and retries.
- Realtime channels, storage, functions, and RPCs receive multi-account authorization tests.
- Secrets remain server-side. The service-role key never ships in the app.
- Security review covers enumeration, replay, forged sender IDs, IDOR, stale
  membership, malicious media, notification leakage, and local-device residue.

---

## 15. Observability

Allowed operational metrics contain no content:

- send acknowledgement and end-to-end delivery latency distributions;
- queue depth and oldest queued age;
- reconnect and catch-up success rates;
- duplicate/idempotency conflict count;
- receipt RPC success/failure counts;
- realtime disconnect and resubscribe counts;
- safety and analysis backlog age using aggregate counts only;
- push enqueue/delivery failure counts;
- media processing duration and coarse rejection reason;
- cache/queue corruption and migration counts;
- authorization denial counts without target identifiers in analytics.

Structured logs use correlation IDs and coarse error codes. Sampling must not
capture request bodies, message rows, media URLs, translator text, or model output.
Alerts and runbooks are required for queue age, worker backlog, receipt failures,
realtime degradation, push failure, storage errors, and abnormal authorization denials.
The safety-stage latency SLO (Section 7.2) has a dedicated paging alert: breach
of p95 30s / p99 2m from message commit to recorded safety completion.

---

## 16. Edge-case contract

The implementation must define and test these outcomes:

| Case | Required outcome |
|---|---|
| Double tap or request replay | One canonical message |
| Commit succeeds, response is lost | Retry reconciles existing row |
| Realtime event precedes insert response | Optimistic and canonical rows merge |
| App reconnects after missed events | Cursor catch-up restores all rows |
| Two messages share timestamp | Stable ID tie-breaker preserves order |
| Relationship ends while queued | Queue stops; message remains unsent |
| Chat archives while open | Subscription cancels; cache and queue purge |
| User switches account | Previous user's local data is inaccessible and purged |
| Receipt RPC replay | Timestamp remains monotonic and unchanged after first set |
| Sender attempts own delivered/read receipt | No row changes |
| Outsider guesses relationship/message ID | No data or existence leak |
| Safety worker is unavailable | Message delivers; work retries/dead-letters; alert fires |
| Analysis worker is unavailable | Chat and Safety continue normally |
| Push is duplicated | Recipient receives at most one logical notification |
| Push opens after archive | Authenticated route refuses chat access |
| Invalid/hostile image | Upload or worker rejects safely; no decoder exhaustion |
| Signed URL is stale | Media request fails and requires reauthorization |
| Translator times out | Draft remains intact and ordinary send remains available |
| Drift migration/corruption fails | Rebuild read cache from server; preserve recoverable queue |

---

## 17. Build order and acceptance criteria

### Phase 1 - Contracts and migrations

1. Reconcile migration with existing schema; add/backfill `client_message_id`.
2. Add constraints, indexes, operation-specific RLS, and column privileges.
3. Implement and test receipt RPCs.
4. Implement transactional downstream work required by the Safety spec.
5. Add four-account RLS/RPC tests before app integration.

### Phase 2 - Deterministic domain and local persistence

6. Add immutable message/status models and validation.
7. Add Drift read cache and user-scoped outgoing queue migrations.
8. Add idempotent merge, ordering, pagination cursor, retry, and backoff logic.
9. Test process death, account switch, archive, and queue recovery.

### Phase 3 - Remote repository and realtime

10. Implement idempotent text send and canonical reconciliation.
11. Implement initial fetch, keyset pagination, realtime subscription, and reconnect catch-up.
12. Implement batched receipt RPC calls.
13. Add integration tests for event-order races and missed realtime events.

### Phase 4 - Safety, analysis, and notifications

14. Connect the transactional Safety outbox and worker.
15. Gate normal analysis after recorded Safety completion/handled failure.
16. Connect backend new-message notification outbox with generic defaults.
17. Prove sender-visible timing does not distinguish Safety matches.

### Phase 5 - Month 1 experience

18. Build list, conversation, composer, statuses, read-only, offline, and error states.
19. Add accessibility, localization, lifecycle purge, and privacy behavior.
20. Run unit, widget, integration, SQL authorization, load, and real-device tests.

### Phase 6 - Month 2 additions

21. Add private image upload intents, processing, signed reads, and cleanup.
22. Add Conflict Translator through the normal send path.
23. Add expanded chat header drawer.
24. Release each addition behind an independent server-authoritative flag.

### Phase 7 - Month 5 historical import

25. Build client-side WhatsApp export parsing and sender-mapping preview
    with no network transmission of the raw file.
26. Implement the dual-consent request/approve/decline flow and its
    append-only consent records.
27. Implement server-side ingestion: idempotent backdated insertion through
    the existing message path, chronological ordering, resumable partial-job
    handling.
28. Connect imported messages to the existing Safety outbox and Layer 1/2/4
    analysis paths — no bypass, no separate pipeline.
29. Implement deletion/revocation cascades and reduced-confidence evidence
    tagging for import-sourced patterns.
30. Add four-account tests proving one partner cannot import, infer content
    of, or bypass consent for the other partner's history.
31. Complete Safety, legal/privacy, clinical, and cultural review gates
    (Section 11.12) before enabling the feature flag.

### Acceptance criteria

- Duplicate and replayed sends create exactly one message and one set of jobs.
- No authenticated client can spoof a sender, mutate partner messages, write
  receipts directly, or tamper with analysis fields.
- Sender, recipient, outsider, former relationship, archived relationship, and
  account-switch tests pass for database, realtime, storage, functions, and RPCs.
- Offline send survives restart and converges after reconnect without duplication.
- Reconnect catch-up returns every authorized message in stable order.
- Safety work is durable, isolated, idempotent, and precedes normal analysis.
- No content or private URL appears in logs, analytics, traces, or push data.
- Private media cannot be read by outsiders or after archive authorization fails.
- Accessibility tests pass at supported text scales and with VoiceOver/TalkBack.
- Performance targets are measured on representative Ghana network conditions
  and lower-end supported devices; thresholds are approved before release.
- Feature flags, dashboards, alerts, runbooks, canary, and rollback are tested.

---

## 18. Blocking production gates

Engineering may implement this specification, but production release is blocked until:

- [ ] Master Spec schema reconciliation is represented by reviewed migrations.
- [ ] Four-account and relationship-lifecycle RLS/RPC/storage tests pass in staging.
- [ ] Safety System professional, clinical, cultural, legal, privacy, and security
      gates applicable to relationship chat are complete.
- [ ] Ghanaian/West African cultural review covers chat copy, translator entry,
      notification wording, and representative network/device behavior.
- [ ] Privacy/legal review approves non-E2EE disclosure, message processing,
      retention, export, deletion, notification previews, and admin access.
- [ ] Threat model and penetration review cover RLS, RPCs, realtime, replay,
      local storage, private media, workers, and notification routing.
- [ ] Real-device iOS and Android tests pass for offline queueing, reconnect,
      account switch, lock-screen previews, background delivery, and cache purge.
- [ ] Load/soak tests pass for send, realtime, receipts, outbox, Safety, analysis,
      media, and push workers at approved capacity margins.
- [ ] Accessibility and localization reviews pass.
- [ ] Monitoring dashboards, privacy-safe alerts, incident runbooks, dead-letter
      recovery, canary plan, feature flags, rollback, and production smoke tests
      are exercised successfully.
- [ ] `ATTUNE_PRINCIPLES_CHECKLIST.md` and the relevant algorithm quality
      checklist sections are signed off with retained evidence.

No unchecked gate may be represented as completed without review evidence.

---

## 19. Resolved decisions

| Decision | Resolution |
|---|---|
| Source of truth | Supabase PostgreSQL |
| Local persistence | Drift read cache plus durable outgoing queue |
| Local-first | No |
| Send idempotency | Stable client UUID, unique per sender |
| Receipt writes | Constrained security-definer RPCs only |
| Safety | Server-authoritative durable stage before normal analysis |
| AI trigger | Trusted backend only |
| Launch media | None; private images in Month 2 |
| Media storage | Private bucket and short-lived authorized URLs |
| Push authority | Trusted backend/outbox |
| Push preview default | Generic; content preview opt-in and privacy-reviewed |
| Translator | Month 2, pull-only, recipient never knows |
| Ended relationship | Read-only until archive |
| Archived relationship | Inaccessible; local data purged |
| Personal reflections | Separate self-only domain |
| Message edit/delete | Month 4 under a separate contract |
| Historical chat import | Month 5, dual-consent-only; neither partner can import unilaterally |
| Import source at launch | WhatsApp text export only; media not imported; iMessage has no bulk-export path |
| Import safety handling | Historical matches run through the same Safety System; recipient-only, generic, non-current-implying notification |
| Import evidence confidence | One tier lower than equivalent native evidence pending clinical review |

This specification is ready for engineering implementation and review. It is
not by itself approval to release Chat or any uncompleted later-phase feature.

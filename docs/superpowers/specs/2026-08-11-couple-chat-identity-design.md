# Couple Chat Identity (Name & Photo) — Design

Date: 2026-08-11

## Problem

A couple's chat currently has no identity of its own — the conversation's
name and avatar are always derived from the partner's own `users.display_name`
/ `users.avatar_url`. Couples want to name their relationship (e.g. "Perla" +
"Javics" → "Japerl34" or "Perlics") and set a shared photo for it, editable by
either partner at any time.

## Data model

Three new nullable columns on `public.relationships`:

```sql
ALTER TABLE public.relationships
  ADD COLUMN chat_name text,
  ADD COLUMN chat_avatar_url text,
  ADD COLUMN chat_avatar_thumbnail_url text;

ALTER TABLE public.relationships
  ADD CONSTRAINT relationships_chat_name_length
  CHECK (chat_name IS NULL OR char_length(trim(chat_name)) BETWEEN 1 AND 30);
```

`chat_name`/`chat_avatar_url` live directly on the relationship row (no new
table for those two — relationship-scoped identity, not per-user, mirroring
how `chat_archived_at` already lives there). `chat_avatar_thumbnail_url` is
populated asynchronously by the processing pipeline below; the UI shows
`chat_avatar_url` (full size) until the thumbnail exists, then prefers the
thumbnail for list/card contexts (same pattern `messages.media_thumbnail_url`
already uses).

The upload pipeline itself needs its own tables — see Photo upload below.

No new RLS policy needed: the existing `"relationship members update
limited"` policy already permits either `user_a` or `user_b` to `UPDATE`
their relationship row (`USING (user_a = auth.uid() OR user_b = auth.uid())`),
which already covers writing these two columns.

## Write path

A direct Supabase client update from the app (no new edge function), scoped
to the caller's active relationship id, guarded by the existing RLS policy —
matching how other relationship-scoped fields are already written from the
client rather than through a function. Client-side validation before the
write: trim whitespace, reject empty, cap at 30 characters. The DB
constraint above is the backstop if that's ever bypassed.

## Photo upload

**Revised after implementation research (2026-08-11):** the existing chat-
image and dating-photo upload paths are not simple upload calls — both are
full pipelines (server-generated storage key via a `SECURITY DEFINER` RPC,
a one-time-use upload-intents table, an async processing outbox with
worker-claim/stale-lease-recovery RPCs, and an edge function invoked via a
DB trigger). Per Algorithm Quality Review Checklist v3.1, this feature
follows the same pipeline *shape* for consistency and operability — new,
parallel infrastructure scoped to relationship avatars, not a literal reuse
of the message-media or dating-photo tables:

- **New bucket**: `relationship-avatars` (separate from `message-media` and
  `dating-profile-photos`).
- **New table** `relationship_avatar_upload_intents` — mirrors
  `dating_photo_upload_intents` (one-time-use, 15-minute expiry, keyed by
  relationship + requester).
- **New table** `relationship_avatar_processing_outbox` — mirrors
  `message_media_processing_outbox`/`dating_photo_moderation_outbox` in
  shape, but the job it queues is **thumbnail generation only**
  (`process-chat-media`'s pattern), not moderation/face-detection
  (`process-dating-photo`'s pattern) — a relationship avatar has no dating-
  style trust/safety requirement for a detectable face, so face-detection
  moderation does not apply here. Documented explicitly so a future reader
  doesn't wonder why this pipeline is "missing" moderation.
- **RPC** `create_relationship_avatar_upload_intent(p_relationship_id,
  p_mime_type)` — mirrors `create_dating_photo_upload_intent`: auth check,
  mime allowlist (`image/jpeg`, `image/png`, `image/webp`), membership
  check against `relationships` (must be `active`, caller is `user_a` or
  `user_b`), server-generates the storage key
  (`relationship-avatars/<relationship_id>/<random>.<ext>`), inserts the
  intent row, returns `(intent_id, storage_key, expires_at, bucket)`.
- **RPC** `set_relationship_avatar(p_relationship_id, p_intent_id)` —
  validates the intent (unused, unexpired, matches relationship + caller),
  validates the uploaded storage object exists and is ≤800KB (same cap as
  chat media), marks the intent used, writes `chat_avatar_url` on the
  relationship row, enqueues a processing-outbox row for thumbnail
  generation, returns the new `chat_avatar_url`.
- **Edge function** `process-relationship-avatar` — mirrors
  `process-chat-media` exactly (claim jobs, download+resize to a 400px
  thumbnail, upload as `relationship-avatars/<relationship_id>/thumb-
  <random>.thumb`, write back, mark outbox done/dead-letter). Invoked by a
  DB trigger on outbox insert, same fire-and-forget `net.http_post` pattern
  as the existing two pipelines (best-effort; a stuck job is picked up by
  lease recovery, not retried inline).
- **RPC** `claim_relationship_avatar_jobs` /
  `recover_stale_relationship_avatar_jobs` — mirror
  `claim_chat_media_jobs`/`recover_stale_chat_worker_leases` exactly (same
  5-attempt dead-letter threshold, same 5-minute stale-processing window).
- **Storage RLS**: `SELECT` on the `relationship-avatars` bucket restricted
  to relationship members, mirroring `message_media_select_relationship_members`.

The resulting `chat_avatar_url` (full-size storage key; the thumbnail key
is a secondary field, `chat_avatar_thumbnail_url`, added alongside it — see
Data model) is what `getConversations()` resolves into `Conversation.avatarUrl`.

## Read path / display

`SupabaseChatRepository.getConversations()` currently builds each
`Conversation.name`/`avatarUrl` from the partner's `users` row. This changes
to prefer `relationships.chat_name`/`chat_avatar_url` when set (non-null),
falling back to the partner's `display_name`/`avatar_url` when not set. This
is the single point where the couple's identity is resolved — everything
downstream (`ChatScreen`'s AppBar title, `ConversationsScreen`'s
`_ConversationCard`, `PreviousRelationshipsScreen`'s list rows) already
reads `Conversation.name`/`avatarUrl` and needs no further changes.

Default/unset behavior: before either partner sets a custom name, the
conversation continues to show the partner's own `display_name` exactly as
it does today — no visible change until someone opts in.

## New screen: ChatSettingsScreen

Reached by tapping the conversation name/avatar in `ChatScreen`'s AppBar
(currently a static, non-interactive `Text(conversation.name)` — becomes
tappable, opening this screen with the current `Conversation` passed
through).

Layout, matching the app's existing settings-screen conventions:
- Large circular avatar at the top (`relationships.chat_avatar_url` or a
  fallback), tappable to pick/upload a new photo through the reused upload
  pipeline.
- A text field pre-filled with the current `chat_name` (or empty).
- A Save action that validates (trim, non-empty, ≤30 chars) and writes both
  fields to the relationship row.
- Available to either partner at any time the relationship is `active`.

## Live sync between partners

No new realtime channel. `ChatController` already refreshes the
`Conversation` object (`_refreshConversation`, via `getConversation`) on its
existing realtime subscription (`watchConversationEvents`) and periodic
resyncs. Once `getConversations()`/`getConversation()` read the new columns,
a partner's edit surfaces to the other partner the next time that existing
refresh cycle fires — no additional plumbing, no push notification.

## Algorithm Quality Review Checklist v3.1 — scope

Tags: `[MUTATION]` (name/photo writes), `[MOBILE]` (Flutter UI), `[UI]`
(ChatSettingsScreen), `[SERVICE]` (the two new RPCs + edge function), plus
the async processing outbox is `[ASYNC]`-shaped even though it's a single
best-effort thumbnail job, not a queue consumer in the traditional sense.
No `[FIN]` (no money involved) — Financial/Money-Handling section (2.19–2.23)
skipped in full.

Key checks this design satisfies and how:
- **1.4/1.5 (authz/authn at every access point)** — every new RPC starts
  with `auth.uid()` null-check, then a membership check against
  `relationships` scoped to `active` status; storage RLS independently
  restricts bucket reads to relationship members.
- **2.1 (input sanitization)** — mime allowlist, name length/emptiness
  validated both client-side and via DB constraint (defense in depth).
- **2.5 (resource limits)** — 800KB upload cap enforced server-side in
  `set_relationship_avatar` (checked against the actual uploaded object,
  not trusted from the client), matching the existing chat-media cap.
- **2.10 (resource lifecycle)** — upload intents expire (15 min) and are
  single-use (`used_at`); a failed/abandoned upload leaves no permanently
  dangling state — an unused expired intent is simply never consumed
  (existing `cleanup_expired_chat_media_intents`-style sweep is a natural
  follow-up but not required for correctness, since expired intents just
  fail validation on use, they don't need active cleanup to stay safe).
- **2.18 (idempotency)** — `set_relationship_avatar` is called once per
  successful upload with a single-use intent; retrying with the same intent
  fails cleanly (`used_at IS NOT NULL`) rather than double-applying.
- **1.10 (compensating transactions)** — if the outbox insert fails after
  `chat_avatar_url` is written, the full-size image is still valid and
  displayable; the thumbnail simply never generates until the next manual
  edit. No user-visible broken state, so no rollback path is needed beyond
  "the full image degrades gracefully to no-thumbnail."
- **3.9/6.1 (retry bounds, edge cases)** — 5-attempt dead-letter threshold
  and 5-minute stale-lease window copied verbatim from the two proven
  existing pipelines, not reinvented.
- **4.4 (PII in logs)** — storage keys and relationship/intent UUIDs are
  logged (already the pattern in `process-chat-media`); no display names,
  no raw image bytes, no auth tokens.
- **5.5 (no internal leakage in UI)** — `ChatSettingsScreen` surfaces only
  generic failure copy ("Couldn't update your photo — try again"), never
  raw Postgres/storage error text.

Explicitly skipped with justification:
- **1.1/2.19–2.23 (Financial)** — N/A, no money handled.
- **3.1 (pagination)** — N/A, this reads/writes a single relationship row,
  never a list.
- **7.6 (CSRF/CORS)** — N/A, native-mobile-only (`[UI-WEB]` tag doesn't
  apply).
- **Face-detection moderation** (the one thing `process-dating-photo` has
  that this pipeline deliberately does NOT) — a relationship avatar has no
  dating-style trust/safety requirement for a verifiable human face;
  requiring one would actively break legitimate use (a couple's symbol, a
  pet photo, an illustration). Documented here so this isn't mistaken for
  an oversight later.

## Out of scope

- Chat-import screen (`CHAT_SYSTEM_SPEC.md`'s only prior mention of "chat
  settings" was as import's future entry point — unrelated to this feature,
  not touched).
- Push notification announcing a rename.
- History/audit trail of previous names or photos.
- Any per-partner override (both partners always see the same name/photo —
  there is exactly one relationship identity, not two).

## Testing

**Implemented**: `RelationshipChatNameValidationResult`/
`validateRelationshipChatName` (a pure function, per Checklist 2.17) covers
the client-side name rule in
`test/features/chat/relationship_chat_name_validator_test.dart` — empty,
whitespace-only, exactly-30 (boundary), 31 chars (boundary), trimming
interaction with the boundary, single-character minimum, and unicode/emoji
content (Checklist 6.1 edge cases).

**Not implemented (manual verification only)**: `SupabaseChatRepository`
has no existing mock/fake harness for its Supabase calls, and building one
is out of scope for this feature. The new repository methods
(`setRelationshipChatName`, `createRelationshipAvatarUploadIntent`,
`uploadRelationshipAvatarImage`, `applyRelationshipAvatar`) and the SQL
RPCs/triggers/edge function are verified by manual QA against a real
Supabase project, not automated tests:
- Either partner can set/edit the name and photo on an active relationship;
  the other partner sees the update on their next chat refresh.
- The DB constraint (`relationships_chat_name_length`) independently
  rejects an invalid name if somehow reached with client-side validation
  bypassed.
- Before any custom name/photo is set, conversation display is unchanged
  from current behavior (partner's `display_name`/`avatar_url`).
- Photo upload respects the 800KB cap (enforced against the actual
  uploaded object server-side, not trusted from the client) and produces a
  `relationship-avatars/`-prefixed storage key distinct from message media
  and dating photos.
- Retrying `set_relationship_avatar` with an already-used `intent_id` fails
  cleanly (Checklist 2.18 idempotency) rather than double-applying.
- A relationship no longer `active` (ended/paused) rejects both the name
  and photo RPCs.
- The async thumbnail job: succeeds and populates
  `chat_avatar_thumbnail_url`; fails gracefully and leaves
  `chat_avatar_url` (full-size) displayable in the interim; a job stuck in
  `processing` for 5+ minutes is picked up by
  `recover_stale_relationship_avatar_jobs`; 5 failed attempts land the job
  in `dead_letter` without crashing the caller.

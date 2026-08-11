# Couple Chat Identity (Name & Photo) — Design

Date: 2026-08-11

## Problem

A couple's chat currently has no identity of its own — the conversation's
name and avatar are always derived from the partner's own `users.display_name`
/ `users.avatar_url`. Couples want to name their relationship (e.g. "Perla" +
"Javics" → "Japerl34" or "Perlics") and set a shared photo for it, editable by
either partner at any time.

## Data model

Two new nullable columns on `public.relationships`:

```sql
ALTER TABLE public.relationships
  ADD COLUMN chat_name text,
  ADD COLUMN chat_avatar_url text;

ALTER TABLE public.relationships
  ADD CONSTRAINT relationships_chat_name_length
  CHECK (chat_name IS NULL OR char_length(trim(chat_name)) BETWEEN 1 AND 30);
```

No new table. This is relationship-scoped identity, not per-user, so it
belongs on the relationship row itself — mirroring how `chat_archived_at`
already lives there.

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

Reuses the existing chat-image upload pipeline
(`ChatRepository.createImageUploadIntent` → `uploadChatImage`, same 800KB
size cap already enforced for message photos) with a distinct storage key
prefix — `relationship-avatars/<relationshipId>/...` — so relationship
photos never collide with message media in the same bucket. The resulting
storage key/URL is written to `relationships.chat_avatar_url`.

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

## Out of scope

- Chat-import screen (`CHAT_SYSTEM_SPEC.md`'s only prior mention of "chat
  settings" was as import's future entry point — unrelated to this feature,
  not touched).
- Push notification announcing a rename.
- History/audit trail of previous names or photos.
- Any per-partner override (both partners always see the same name/photo —
  there is exactly one relationship identity, not two).

## Testing

- Either partner can set/edit the name and photo on an active relationship;
  the other partner sees the update on their next chat refresh.
- Name validation: empty/whitespace-only rejected client-side; the DB
  constraint rejects it as a backstop; 30-character cap enforced both
  client-side and via the DB constraint.
- Before any custom name is set, conversation display is unchanged from
  current behavior (partner's `display_name`).
- Photo upload respects the existing 800KB cap and produces a
  `relationship-avatars/`-prefixed storage key distinct from message media.

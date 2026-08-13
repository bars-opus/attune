# Message Actions (Long-Press Menu) — Design Spec

Date: 2026-08-13

## Goal

Add a WhatsApp-style long-press context menu on chat message bubbles with
six actions: **Reply, Copy, Star, Pin, Edit, Delete.** Reply already exists
as a swipe gesture — this feature adds a long-press entry point that
surfaces it alongside the five new actions, and builds Copy/Star/Pin/
Edit/Delete from scratch.

## Spec deviation this feature resolves

`lib/architecture/CHAT_SYSTEM_SPEC.md` §1.3 (line 106-108) and §1.4's scope
table (line 116) explicitly gate message edit and delete to **"Month 4,
under a separate retention and audit contract"** — not yet written as of
this feature. This document **is** that contract: the retention/audit
questions below (soft-delete model, edit history, analysis-retraction
policy, reply-parent handling) are answered here so edit/delete can ship
now rather than wait for a future, unscoped "Month 4" pass. `CHAT_SYSTEM_SPEC.md`
should be amended to reference this doc once implementation lands.

Star and pin are not mentioned in `CHAT_SYSTEM_SPEC.md` at all — no prior
decision to conflict with. This spec is their first product decision.

## Decisions (confirmed with the user)

1. **Delete model: soft delete with a visible tombstone.** The row and its
   `id` persist; content columns are cleared server-side on delete. Both
   partners see "This message was deleted" in place of the bubble content.
   Chosen over silent removal (which could read as gaslighting in a
   couples app if a partner notices a message vanish with no trace) and
   over hard delete (which would orphan reply-parent references and
   destroy any audit trail — the exact thing "audit contract" exists to
   prevent).

2. **Edit model: history is kept, not just an "edited" tag.** Every prior
   version of an edited message is stored and viewable. Chosen over a
   simple overwrite-plus-label because message content in this app already
   feeds an NVC/tone/safety analysis pipeline (`analyse-message`,
   `chat_safety.ts`) — silently allowing content to be rewritten with zero
   record undermines that pipeline's evidentiary value in exactly the kind
   of situation (conflict, safety concern) where a partner might want to
   verify what was actually said. This is the one place this spec goes
   beyond the WhatsApp reference model the user named, specifically
   because of what "audit contract" was gating in the first place.

3. **Analysis retraction: none.** Deleting or editing a message does not
   touch `tone_score`, `nvc_violations`, `bid_type`, or any
   `analysis_sessions`/Pulse data already derived from it. Matches how the
   app already treats past Pulse weeks as historical record (Pulse never
   retroactively rewrites a prior week's score), and avoids reopening the
   just-shipped chat-pulse-integration pipeline. Analysis typically
   completes within seconds of send, and the edit/delete window is 5
   minutes, so in the common case a message is already analyzed before it
   could be deleted — this is the normal path, not an edge case to special-case
   around.

4. **Reply-parent deletion: quoted preview becomes a placeholder.** When a
   message with `quoted_text` denormalized from a now-deleted parent is
   rendered, the quote block shows "Original message deleted" instead of
   the stored `quoted_text`. Requires checking the parent's deleted state
   at render/fetch time, not just trusting the denormalized copy.

5. **Star: private per-user.** A user's starred messages are visible only
   to them — mirrors WhatsApp/iMessage convention as a personal bookmark.
   Partner never sees what the other has starred.

6. **Pin: shared relationship-wide, up to 3, banner UI.** Pinning is
   visible to both partners — its purpose is surfacing something for both
   of you, unlike star's private-bookmark purpose. Up to 3 pinned messages
   at once (matches WhatsApp's current limit), shown as a banner at the
   top of the chat that cycles/lists the pinned messages; tapping jumps to
   that message.

7. **Edit/delete window: 5 minutes from `created_at`.** After 5 minutes,
   both actions are unavailable — the long-press menu simply omits them
   (not shown greyed-out, not shown with an error on tap). Matches the
   user's explicit instruction. Note this is stricter than the existing
   sibling precedent (`opinions`/`opinion_comments`/`forum_posts` use a
   15-minute window, migration `20260730120000_edit_window_opinions_comments_forum_posts.sql`)
   — deliberately shorter here because live back-and-forth chat moves
   faster than a forum post or opinion piece, and a shorter window reduces
   the "wait, did you edit that?" trust question this feature could
   otherwise introduce into a relationship-safety product.

## Data Model

### `messages` table additions

```sql
ALTER TABLE public.messages
  ADD COLUMN deleted_at timestamptz,
  ADD COLUMN edited_at timestamptz;
```

- `deleted_at IS NOT NULL` → tombstoned. Content columns (`content`,
  `media_url`, `media_type`, `media_thumbnail_url`) are set to `NULL` on
  delete (not the row — the row and `id` persist so reply references and
  analysis rows referencing `included_in_session_id` stay valid).
- `edited_at IS NOT NULL` → has been edited at least once; client renders
  the "edited" label. `content` reflects the CURRENT version; prior
  versions live in `message_edit_history` (below).
- A message cannot be both edited and deleted in a way that loses data:
  delete always wins visually (tombstone takes precedence over showing
  edit history), but `message_edit_history` rows are NOT deleted when the
  message is deleted — the audit trail persists even through a delete.

### New table: `message_edit_history`

```sql
CREATE TABLE public.message_edit_history (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  message_id uuid NOT NULL REFERENCES public.messages(id) ON DELETE CASCADE,
  previous_content text NOT NULL,
  edited_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_message_edit_history_message ON public.message_edit_history (message_id, edited_at);
```

Stores the content as it was **before** each edit (i.e., editing a message
for the first time writes one row containing the original text; the
`messages.content` column always holds the latest version). `ON DELETE
CASCADE` is intentional here — if the parent message row is ever hard-deleted
(should not happen via the app, but e.g. a relationship deletion cascade),
its edit history has no independent purpose.

Note: `ON DELETE CASCADE` from `messages` does NOT fire on a *soft* delete
(setting `deleted_at`) — only on an actual row deletion, which this feature
never performs. Soft-deleting a message leaves `message_edit_history` rows
intact, satisfying decision 2 above.

### New table: `message_stars`

```sql
CREATE TABLE public.message_stars (
  message_id uuid NOT NULL REFERENCES public.messages(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  starred_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (message_id, user_id)
);

CREATE INDEX idx_message_stars_user ON public.message_stars (user_id, starred_at DESC);
```

Per-user, private. RLS: a user can only see/insert/delete their own rows
(`user_id = auth.uid()`).

### New table: `message_pins`

```sql
CREATE TABLE public.message_pins (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  relationship_id uuid NOT NULL REFERENCES public.relationships(id) ON DELETE CASCADE,
  message_id uuid NOT NULL REFERENCES public.messages(id) ON DELETE CASCADE,
  pinned_by uuid NOT NULL REFERENCES auth.users(id),
  pinned_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (relationship_id, message_id)
);

CREATE INDEX idx_message_pins_relationship ON public.message_pins (relationship_id, pinned_at DESC);
```

Relationship-wide, visible to both partners (RLS: both members of
`relationship_id` can `SELECT`; either partner can `INSERT`/`DELETE`, same
"no per-partner override" precedent already established for chat naming in
`ChatSettingsScreen`). The 3-pin cap is enforced in the pin RPC (below),
not a DB constraint — the RPC rejects a 4th pin with a clear error rather
than silently evicting the oldest.

## RPCs (all `SECURITY DEFINER`, matching the `edit_opinion`-style precedent)

All five mutation actions go through RPCs rather than direct table
grants — `messages` currently has **no `UPDATE`/`DELETE` grant for
`authenticated`** (confirmed: only `SELECT`/`INSERT` exist), and this
feature keeps it that way. Direct grants would let a client bypass the
5-minute window or edit another user's message; RPCs enforce both
server-side, matching how `edit_opinion` et al. already work in this
codebase.

```sql
-- Delete: clears content, sets deleted_at. Only the sender, only within
-- 5 minutes of created_at.
CREATE OR REPLACE FUNCTION public.delete_message(p_message_id uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_sender_id uuid;
  v_created_at timestamptz;
BEGIN
  SELECT sender_id, created_at INTO v_sender_id, v_created_at
  FROM public.messages WHERE id = p_message_id AND deleted_at IS NULL
  FOR UPDATE;

  IF v_sender_id IS NULL THEN
    RAISE EXCEPTION 'Message not found or already deleted';
  END IF;
  IF v_sender_id != auth.uid() THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;
  IF v_created_at < now() - interval '5 minutes' THEN
    RAISE EXCEPTION 'Edit window has expired';
  END IF;

  UPDATE public.messages
  SET content = NULL, media_url = NULL, media_type = NULL,
      media_thumbnail_url = NULL, deleted_at = now()
  WHERE id = p_message_id;
END;
$$;

-- Edit: writes the OLD content to history, then updates content and
-- edited_at. Only the sender, only within 5 minutes of created_at, only
-- if not deleted.
CREATE OR REPLACE FUNCTION public.edit_message(p_message_id uuid, p_new_content text)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_sender_id uuid;
  v_created_at timestamptz;
  v_current_content text;
BEGIN
  SELECT sender_id, created_at, content INTO v_sender_id, v_created_at, v_current_content
  FROM public.messages WHERE id = p_message_id AND deleted_at IS NULL
  FOR UPDATE;

  IF v_sender_id IS NULL THEN
    RAISE EXCEPTION 'Message not found or deleted';
  END IF;
  IF v_sender_id != auth.uid() THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;
  IF v_created_at < now() - interval '5 minutes' THEN
    RAISE EXCEPTION 'Edit window has expired';
  END IF;
  IF length(p_new_content) = 0 OR length(p_new_content) > 10000 THEN
    RAISE EXCEPTION 'Invalid content length';
  END IF;

  INSERT INTO public.message_edit_history (message_id, previous_content)
  VALUES (p_message_id, v_current_content);

  UPDATE public.messages
  SET content = p_new_content, edited_at = now()
  WHERE id = p_message_id;
END;
$$;

-- Pin: enforces the 3-pin cap. Either partner may pin/unpin.
CREATE OR REPLACE FUNCTION public.pin_message(p_relationship_id uuid, p_message_id uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.relationships
    WHERE id = p_relationship_id AND (user_a = auth.uid() OR user_b = auth.uid())
  ) THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;

  IF (SELECT count(*) FROM public.message_pins WHERE relationship_id = p_relationship_id) >= 3 THEN
    RAISE EXCEPTION 'Pin limit reached (3 max) — unpin a message first';
  END IF;

  INSERT INTO public.message_pins (relationship_id, message_id, pinned_by)
  VALUES (p_relationship_id, p_message_id, auth.uid())
  ON CONFLICT (relationship_id, message_id) DO NOTHING;
END;
$$;
```

Unpin and star's insert/delete are simple enough to be plain grants rather
than RPCs — no window logic, no cap logic to enforce on the delete path:

```sql
-- message_stars: owner manages their own rows directly.
GRANT SELECT, INSERT, DELETE ON public.message_stars TO authenticated;
CREATE POLICY message_stars_owner ON public.message_stars
  FOR ALL USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

-- message_pins: both partners can view and unpin (DELETE); INSERT stays
-- server-only (via pin_message, to enforce the 3-pin cap) — no INSERT
-- grant for authenticated.
GRANT SELECT, DELETE ON public.message_pins TO authenticated;
CREATE POLICY message_pins_select ON public.message_pins
  FOR SELECT USING (
    EXISTS (SELECT 1 FROM public.relationships
      WHERE id = relationship_id AND (user_a = auth.uid() OR user_b = auth.uid()))
  );
CREATE POLICY message_pins_delete ON public.message_pins
  FOR DELETE USING (
    EXISTS (SELECT 1 FROM public.relationships
      WHERE id = relationship_id AND (user_a = auth.uid() OR user_b = auth.uid()))
  );
```

## RLS Summary

| Table | SELECT | INSERT | UPDATE | DELETE |
|---|---|---|---|---|
| `message_edit_history` | Both relationship members (via join to `messages`) | Server only (via `edit_message` RPC) | — | — |
| `message_stars` | Owner only (`user_id = auth.uid()`) | Owner only | — | Owner only |
| `message_pins` | Both relationship members | Server only (via `pin_message` RPC) | — | Both relationship members (plain grant) |
| `messages` | unchanged | unchanged | **still none** — `deleted_at`/`edited_at`/`content` only change via the RPCs above | unchanged (still none) |

## Client (Flutter)

### Long-press menu

New widget, e.g. `lib/features/chat/presentation/widgets/message_actions_sheet.dart`,
triggered by wrapping `MessageBubble`'s existing content in a
`GestureDetector.onLongPress` (new — no long-press handler exists on this
widget today) that opens a bottom sheet or a WhatsApp-style
text-focused-bubble overlay (matching the "text focused bubble effect"
the user described — likely a `showGeneralDialog` with a blurred backdrop
and the bubble copied into an overlay above the action list, rather than a
plain `showModalBottomSheet`; final visual treatment is an implementation-time
call, not a spec-level decision).

Menu items, in order (WhatsApp's own ordering): **Reply, Copy, Star/Unstar,
Pin/Unpin, Edit, Delete.** Edit and Delete are omitted entirely (not
disabled) when `now() - message.createdAt > 5 minutes` or when
`message.senderId != currentUserId` (only the sender may edit/delete their
own message — no "delete for everyone" vs "delete for me" distinction,
matching decision 1's single shared tombstone model). Star/Unstar and
Pin/Unpin toggle based on current state (query `message_stars`/
`message_pins` for this message).

### Tombstone rendering

`MessageBubble`/`UniversalBubble`: when `deletedAt != null`, render "This
message was deleted" in place of content, italic/muted style (matches the
existing low-confidence Pulse tooltip's italic treatment for a consistent
"system note" visual language), no long-press menu on a tombstoned bubble
(nothing left to act on except it staying visible).

### Edited label + history view

When `editedAt != null`, render a small "edited" label after the timestamp
(tap to view history — a simple list of `message_edit_history` rows,
oldest first, each showing `previous_content` and `edited_at`; current
content is the implicit final entry, not duplicated from `messages.content`).

### Reply-parent placeholder

Wherever `UniversalBubble` renders the quoted-parent preview
(`universal_bubble.dart:187-234`), check the parent's `deleted_at` (already
fetched or a light join) and render "Original message deleted" instead of
`quoted_text` when set.

### Pinned banner

New widget, a top-of-chat banner in `chat_screen.dart`, querying
`message_pins` for the current relationship (realtime-subscribed, same
pattern as the existing message stream). Shows up to 3 pins; tapping one
jumps to that message (reuses the existing `onJumpToParent` scroll
mechanism already built for reply).

## Testing

- RPC-level: 5-minute boundary (just under / just at / just over),
  wrong-sender rejection, double-delete rejection, edit-after-delete
  rejection, 3-pin-cap rejection, `message_edit_history` insert ordering.
- Widget-level: long-press opens the menu; menu omits edit/delete past the
  window or for a non-sender message; tombstone renders correctly; edited
  label + history sheet renders correctly; reply-parent placeholder
  renders when parent is deleted.

## Algorithm Quality Review Checklist v3.1 — scoping and gate

Scope tags for this feature: `[MOBILE][MUTATION]`. Client-side long-press
UI plus three server RPCs (`delete_message`, `edit_message`,
`pin_message`) and grant-gated table mutations (`message_stars`,
`unpin_message`). No `[SERVICE]`/`[ASYNC]`/`[FIN]` surface — no background
jobs, no money.

Checked against `lib/architecture/algorithms/algorithm_quality_review_checklist.md`:

- **2.1 (input sanitization)**: `edit_message`'s `p_new_content` is
  length-checked (`0 < length <= 10000`, matching the existing
  `messages_content_length` CHECK constraint) inside the RPC, not just
  client-side.
- **2.5 (resource limits)**: pin cap (3) enforced server-side in
  `pin_message`, not client-side-only — a malicious/buggy client can't
  bypass it by skipping the UI check.
- **2.16 (concurrency)**: `delete_message`/`edit_message` use `SELECT ...
  FOR UPDATE` before the window/ownership check to avoid a race where two
  near-simultaneous edits from the same sender (e.g. double-tap) both pass
  the window check against stale data. `pin_message`'s cap check has a
  narrow TOCTOU window (`count(*)` then `INSERT`) — acceptable here since
  the failure mode is "briefly 4 pins instead of 3 under concurrent
  same-instant pins from both partners," not a security or correctness
  issue, and the realistic concurrency (two partners racing to pin) is a
  once-in-a-blue-moon event, not a hot path. Document this as an accepted,
  bounded risk rather than adding `SELECT FOR UPDATE` + advisory lock
  machinery for a 1-in-N cosmetic edge case.
- **2.17 (side-effect isolation)**: the 5-minute-window check is a pure
  comparison (`created_at < now() - interval '5 minutes'`) — trivially
  testable by asserting the boundary in SQL directly, no mocking needed.
- **2.18 (idempotency)**: `delete_message` is naturally idempotent-safe —
  a second call finds `deleted_at IS NOT NULL` already excluded by the
  `WHERE deleted_at IS NULL` guard and raises "already deleted" rather than
  double-clearing content. `pin_message` uses `ON CONFLICT ... DO NOTHING`
  — a retried pin is a no-op, not a duplicate row or a rejected cap-check
  on an already-pinned message. `edit_message` is NOT idempotent by design
  (each call intentionally appends a new history row) — this is correct
  per decision 2 (every edit is a distinct auditable event), not a gap;
  a client-side retry after a network blip would incorrectly create two
  history entries for one logical edit, so the client must not blindly
  retry `edit_message` on timeout without checking whether the edit
  already landed (compare `messages.content` before retrying).
- **2.22 (append-only audit)**: `message_edit_history` has no `UPDATE`/
  `DELETE` grant for `authenticated` at all (rows are written only via the
  `edit_message` RPC's internal `INSERT`) — satisfies "never updated or
  deleted after write" exactly as the checklist requires for an audit
  table, without needing a trigger.
- **5.x (UX)**: edit/delete affordances are omitted rather than
  shown-disabled once the 5-minute window closes — avoids a dead menu item
  that invites a confused tap-and-error cycle.

## Out of scope

- "Delete for everyone" vs "delete for me" distinction (decision 1 makes
  delete always relationship-wide/shared — matches the existing chat-name
  "no per-partner override" precedent).
- Un-deleting a message (no undo; 5-minute window is the only recovery
  mechanism, matching the user's stated design).
- Reactions, voice/video messages — still explicitly out of scope per
  `CHAT_SYSTEM_SPEC.md` §1.4, untouched by this feature.
- Retroactively amending `CHAT_SYSTEM_SPEC.md`'s prose — flagged above as a
  followup, not part of this implementation plan.

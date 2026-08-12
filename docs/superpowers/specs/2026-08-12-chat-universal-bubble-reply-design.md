# Chat Reply/Thread + Shared UniversalBubble — Design

Date: 2026-08-12

## Problem

`ForumPostBubble` (debate room) already has swipe-to-reply, quoted-text
preview with tap-to-jump-to-parent, and a highlight-flash animation when
jumping — built explicitly to mirror `MessageBubble` (1:1 chat)'s
alignment/bubble styling ("This mirrors MessageBubble in the 1:1 chat
feature exactly, so the debate room reads like the group-chat thread it
is" — forum_post_bubble.dart's own doc comment). But the reply/swipe/jump
machinery never made it back into chat itself, and `MessageBubble` stayed
plain. `CommentThreadScreen` independently rebuilt the same
swipe/reply/report mechanics a third time (card-shaped, not a bubble — not
in scope here).

Goal: bring swipe-to-reply, quoted-reply preview, jump-to-parent, and the
highlight-flash animation into 1:1 chat, and — since forums and chat both
want the same bubble shape/gestures/animations with only content and a few
callbacks differing — extract a shared `UniversalBubble` widget so this
logic exists once, not twice.

## Data model

Two new nullable columns on `public.messages`, mirroring
`forum_posts.reply_to_post_id`/`quoted_text` exactly:

```sql
ALTER TABLE public.messages
  ADD COLUMN reply_to_message_id uuid REFERENCES public.messages(id) ON DELETE SET NULL,
  ADD COLUMN quoted_text text;
```

`ON DELETE SET NULL` (not CASCADE): message deletion isn't a feature yet,
but if it ever is, a reply losing its parent should keep existing with a
dangling quote rather than being force-deleted itself. `quoted_text` is a
short snapshot of the parent's content at reply time (same reasoning as
forums: avoids a join just to render the preview, and survives the parent
being edited/removed later).

No thread/nesting depth column — replies stay flat in the chronological
list exactly like forum replies do; a reply to a reply is still just
"a message with a reply_to_message_id," not a tree.

## Message entity + repository + controller

- `Message` gains `replyToMessageId`/`quotedText` (nullable), threaded
  through `fromRow`, `toJson`/`fromJson`, `copyWith`, and a new optional
  param on `Message.optimistic`.
- `ChatRepository.sendTextMessage(...)` gains optional
  `replyToMessageId`/`quotedText` params.
- `ChatController.sendMessage` accepts an optional reply target
  (message id + quoted preview text), passes it through to the send path,
  and the screen clears its own reply-target state after a successful send
  — mirrors `DebateRoomScreen._setReplyTarget`/`_clearReplyTarget` exactly.

## Shared widget: `UniversalBubble`

New file `lib/core/widgets/universal_bubble.dart`. Extracted from
`ForumPostBubble`, parameterized on everything that currently differs
between the two call sites:

- `content` (`Widget`, not a raw string — chat needs to render images,
  forums never do).
- `isMine` → alignment (right/left), same as both today.
- `bubbleColor`/`onBubbleColor` — passed in, not hardcoded. Chat keeps its
  existing `colorScheme.surfaceContainerHighest` (theirs) /
  `colorScheme.primary` (mine) pairing; forums keeps its own
  `onBackground`/`primary` pairing. Visually unchanged for both.
- `leading` (`Widget?`) — forum's status avatar; chat passes null (chat has
  no per-message avatar today, matching `MessageBubble`'s current look).
- `footer` (`Widget`) — the row below the bubble. Forum passes its
  time/like/reply/report/side-badge row; chat passes `MessageBubble`'s
  existing time+status-chip+retry row unchanged.
- `startActionPane`/`endActionPane` (`ActionPane?`) — swipe gestures, fully
  caller-defined. Chat gets Reply only (no delete/report — chat already has
  its own message-failure retry/remove affordances elsewhere, not
  swipe-based). Forum keeps Reply + Report/Delete exactly as today.
- `quotedText`/`onJumpToParent` — same quoted-preview block + tap-to-jump,
  now shared verbatim instead of copy-pasted.
- `isHighlighted` — same flash-on-jump animation, shared verbatim.

`ForumPostBubble` becomes a thin wrapper: builds its existing
footer/leading/action-panes and hands them to `UniversalBubble`, keeping
every one of its own behaviors (like, report, replies-bottom-sheet trigger)
unchanged from the caller's (`DebateRoomScreen`'s) point of view — no
change to `DebateRoomScreen` itself.

`MessageBubble` becomes the same kind of thin wrapper, gaining swipe-to-
reply and jump-to-parent for the first time via the shared widget, while
keeping its existing status-chip/retry footer and media rendering
(`_BubbleBody`) unchanged.

## ChatScreen

- Swipe-right-to-left on any message reveals Reply (same `DrawerMotion`,
  full-swipe-fires pattern as forums/comments).
- A reply-target state (`_replyToMessageId`/`_replyToQuotedText`, mirrors
  `DebateRoomScreen`'s fields) drives a quoted-preview strip above the
  composer with a clear (×) button, shown only while a reply is pending.
- Tapping a quoted-text block on a message that IS a reply scrolls to and
  flashes its parent — same `GlobalKey`-registry + `Scrollable.ensureVisible`
  + index-based-estimate-fallback approach as
  `DebateRoomScreen._jumpToPost`/`_tryEnsureVisible`, adapted from
  `SliverList` to chat's existing message list widget.
- No replies-bottom-sheet: a 1:1 conversation has exactly one other
  participant, so there's no "N people replied to this" grouping need the
  way a public multi-party debate has. Tap-to-jump-to-parent already covers
  "show me the context," which is the same job the bottom sheet does for
  forums in the one-parent-many-replies case.

## Out of scope

- `CommentThreadScreen`'s reply/swipe/report system — card-shaped, not a
  bubble; a third near-duplicate of this same logic, but visually different
  enough (no left/right alignment) that folding it into `UniversalBubble`
  would be a much larger, separate refactor. Not touched.
- Likes and report on chat messages — forum-specific concepts, not part of
  1:1 chat's spec.
- Message editing/deletion (not launch behavior per CHAT_SYSTEM_SPEC.md
  §1.3) — `reply_to_message_id ON DELETE SET NULL` just future-proofs the
  schema for if that ever changes.

## Testing

- Reply flow: swipe a message, quoted-preview strip appears above composer,
  send produces a message with `reply_to_message_id`/`quoted_text` set,
  strip clears after send.
- Tap a reply's quoted-text block scrolls to and flashes the parent message
  (both when the parent is already built/visible and when it's scrolled far
  out of the current build window).
- `MessageBubble`/`ForumPostBubble` visual regression: both must render
  pixel-identical to their current appearance after the `UniversalBubble`
  extraction — this is a refactor, not a redesign, for both existing
  surfaces.
- Existing `ChatController`/message send tests continue to pass with the
  new optional reply params defaulted to null (no reply = today's exact
  behavior).

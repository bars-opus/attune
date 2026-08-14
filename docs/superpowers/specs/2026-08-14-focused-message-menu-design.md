# Focused Message Menu (iMessage-style) — Design Spec

Date: 2026-08-14

## Goal

Replace the current long-press action menu — a plain `showModalBottomSheet`
sliding up from the bottom — with an iMessage-style "focused" overlay:
the long-pressed bubble stays at its exact screen position and scales up
slightly, the rest of the screen dims/blurs behind it, and the action list
floats anchored directly beside the bubble (above or below, whichever
fits) rather than as a bottom sheet. A light haptic fires the instant the
menu opens.

## Scope

- **In scope:** chat's `MessageBubble` long-press menu only (the only
  place a long-press action menu exists today).
- **Built reusable:** the overlay mechanism itself is a new,
  general-purpose widget/function — not hardcoded to chat's specific
  action list — so it can be reused if forums or another surface ever
  needs the same effect. Nothing about `ForumPostBubble` changes in this
  work; it has no long-press menu today and none is being added.
- **Reused as-is:** the actual list of actions (Reply/Copy/Star/Pin/
  Edit/Delete, their icons, labels, and the `canEditOrDelete` gating
  logic) — only the container/presentation changes, not what's inside it
  or the business logic deciding what's shown.

## Current behavior being replaced

`showMessageActionsSheet` (`lib/features/chat/presentation/widgets/message_actions_sheet.dart`)
calls `showModalBottomSheet`, rendering a `ListTile`-per-action column
that slides up from the screen bottom with a drag handle. Triggered from
`UniversalBubble`'s `onLongPress: VoidCallback?` — a bare callback with no
access to the bubble's on-screen position or a way to render a copy of it
into an overlay.

## The four pieces (per user confirmation)

1. **Blurred/dimmed backdrop** — the rest of the screen blurs (via
   `BackdropFilter`, already used elsewhere in this codebase in
   `lib/home/widgets/home_widget.dart`, so this is a known pattern here)
   and darkens behind the focused bubble.
2. **Bubble scales up slightly in place** — the long-pressed bubble grows
   from 1.0 to roughly 1.05x scale and stays at its exact original screen
   position (not centered, not moved) — the menu appears attached to it,
   not disconnected.
3. **Menu anchored beside the bubble** — the action list floats directly
   above or below the bubble at its real position, flipping to whichever
   side has room (below by default; above if the bubble is near the
   bottom of the screen and there isn't enough room below).
4. **Haptic on open** — `HapticFeedback.lightImpact()` (via
   `flutter/services.dart`, matching `UniversalBubble`'s existing direct
   `HapticFeedback` usage rather than the still-unwired `Haptics`
   abstraction, for consistency with the established pattern in this
   codebase's most recent gesture work) fires the instant the overlay
   opens.

## Mechanics

### Triggering: `onLongPress` needs geometry, not just a callback

`UniversalBubble.onLongPress` is currently `VoidCallback?`. To render a
duplicate of the bubble into a full-screen overlay at its exact position,
the trigger needs:
- The bubble's on-screen `Rect`. `GestureDetector.onLongPress` (a bare
  `VoidCallback`) has no position/context of its own, so `UniversalBubble`
  adds a `GlobalKey` (e.g. `_bubbleFillKey`) on the `DecoratedBox` that
  renders the actual bubble fill (the widget at
  `universal_bubble.dart:652`, inside the existing `GestureDetector`) and
  reads `_bubbleFillKey.currentContext!.findRenderObject() as RenderBox`
  at the moment `onLongPress` fires — `renderBox.localToGlobal(Offset.zero)
  & renderBox.size` gives the exact on-screen `Rect`. This is safe to call
  here specifically because `onLongPress` only fires after the widget has
  already been laid out and painted at least once (unlike the reveal-width
  measurement in the swipe-gesture work, which had to avoid reading size
  during `build()` — this read happens from a gesture callback, well after
  build, so no such hazard applies).
- A `Widget` representing the bubble's visual content, to paint into the
  overlay (the SAME `content`/`bubbleColor`/decoration `UniversalBubble`
  already has access to — no new data needed, just a way to hand it to
  the overlay).

Change `UniversalBubble.onLongPress` from `VoidCallback?` to a new
callback shape:

```dart
typedef LongPressWithGeometry = void Function(Rect bubbleRect, Widget bubbleSnapshot);
```

`UniversalBubble` computes `bubbleRect` from its own bubble-fill
`RenderBox` at the moment of long-press, and constructs `bubbleSnapshot`
as a widget tree reproducing the SAME visual bubble (same
`DecoratedBox`/`BoxDecoration`/`content`/padding it already renders) —
not a screenshot/image capture (avoids `RepaintBoundary.toImage()`'s
async round-trip and pixel-ratio complexity), just the same widget
subtree rendered a second time inside the overlay's `Positioned` at the
captured `Rect`.

### The overlay itself: a new reusable widget

New file: `lib/core/widgets/focused_action_menu.dart`

```dart
Future<void> showFocusedActionMenu({
  required BuildContext context,
  required Rect anchorRect,
  required Widget anchorSnapshot,
  required List<Widget> actions,
}) async { ... }
```

- Uses `showGeneralDialog` (not `showModalBottomSheet`) with a fully
  transparent barrier color and a custom `pageBuilder`, so the caller
  controls 100% of the visual presentation instead of inheriting bottom
  -sheet chrome.
- `pageBuilder` renders, in a `Stack`:
  1. `BackdropFilter(filter: ImageFilter.blur(...))` + a semi-transparent
     `Container` scrim, covering the full screen — the "dim and blur the
     rest" layer.
  2. `Positioned.fromRect(rect: anchorRect, child: ScaleTransition(...
     child: anchorSnapshot))` — the bubble redrawn at its real position,
     animating from scale 1.0 to ~1.05 as the overlay opens (driven by
     `pageBuilder`'s own provided `Animation<double>` from
     `showGeneralDialog`'s `transitionBuilder`, not a separate
     controller — reuses the dialog route's own entrance animation rather
     than adding a second one).
  3. The action list (built from the SAME `actions: List<Widget>` the
     caller passes — i.e., `message_actions_sheet.dart`'s existing
     per-item `ListTile`s, unchanged in content), positioned via
     `Positioned` computed from `anchorRect`: default below the bubble
     (`top: anchorRect.bottom + gap`), flipped above
     (`bottom: screenHeight - anchorRect.top + gap`) when
     `anchorRect.bottom + estimatedMenuHeight > screenHeight -
     safeAreaBottom`.
- Tapping the scrim (anywhere outside the bubble/menu) or tapping an
  action dismisses the overlay via `Navigator.pop`.
- Haptic fires once, synchronously, at the top of `showFocusedActionMenu`
  before `showGeneralDialog` is even called — matches "fires the instant
  the menu opens," not deferred to an animation-complete callback.

### `message_actions_sheet.dart` becomes an action-list builder, not a sheet

Rename/refactor `showMessageActionsSheet` into a function that BUILDS the
`List<Widget>` actions (same `ListTile`s, same `canEditOrDelete` gating,
same icons/labels/colors) without calling `showModalBottomSheet` itself —
that call moves to `showFocusedActionMenu`. `MessageBubble`'s call site
changes from "call `showMessageActionsSheet` directly" to "call
`showFocusedActionMenu`, passing the action-list builder's output."

### Dismiss behavior

- Tap outside (on the scrim) → dismiss, no action fires.
- Tap an action → the action's own `onTap` fires (pops first, then calls
  the callback — same order the current `ListTile`s already use, so
  `onDelete`/`onEdit` etc. behave identically to today once the menu is
  showing).
- Android back button / system back gesture → dismiss (default
  `showGeneralDialog` behavior, no extra wiring needed).

## What does NOT change

- The actual six actions, their icons, labels, colors, and
  `canEditOrDelete` gating logic — reused exactly as `message_actions_sheet.dart`
  already implements them.
- `MessageBubble`'s other props (`onReply`, `onCopy`, `onStar`, etc.) —
  unchanged, still passed through to whichever action is tapped.
- `ForumPostBubble` — no long-press menu exists there today, none is
  added by this work. `UniversalBubble.onLongPress`'s signature change
  (from `VoidCallback?` to `LongPressWithGeometry?`) is the only
  `ForumPostBubble`-adjacent change, but since `ForumPostBubble` never
  sets `onLongPress` (confirmed — it's `null` by default and this caller
  doesn't pass it), this is a compile-safe, behavior-neutral type change
  for that file.
- The swipe-gesture system (`onReply`/`endActions`/the whole custom drag
  mechanism) — completely unrelated code path, untouched.

## Testing

- Widget test: long-pressing a bubble opens the overlay (bubble snapshot
  visible at the captured position, backdrop present).
- Widget test: tapping the scrim dismisses without firing any action
  callback.
- Widget test: tapping an action fires its callback and dismisses.
- Widget test: menu flips to render ABOVE the bubble when the bubble is
  near the bottom of the screen (simulate via a tall `SizedBox` pushing
  the bubble down in the test tree).
- Widget test: `canEditOrDelete` gating still correctly omits Edit/Delete
  past the 5-minute window or for a non-sender message (same assertions
  `message_actions_sheet_test.dart` already has, migrated to the new
  entry point).
- Regression: `MessageBubble`'s existing swipe/tap/long-press tests
  (from the swipe-gesture feature) must still pass — the long-press
  TRIGGER changes shape, but nothing about when it fires or what gates it
  (`canOpenActions = currentUserId != null && !message.isDeleted`)
  changes.

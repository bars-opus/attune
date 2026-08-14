# Custom Swipe-to-Reply — Design Spec

Date: 2026-08-14

## Goal

Replace `flutter_slidable` entirely inside `UniversalBubble` (shared by
chat's `MessageBubble` and forum's `ForumPostBubble`) with a custom-built
gesture implementation. Reply (start-direction swipe) matches WhatsApp's
actual feel: drag the bubble sideways, a reply icon fades in behind it,
releasing past a small threshold fires reply immediately (no button to
tap), bubble springs back either way. `ForumPostBubble`'s end-direction
swipe (Report/Delete) becomes a custom reveal-and-stay pane: dragging
right reveals tappable action buttons behind the bubble, which stay open
until tapped, dragged back closed, or another bubble in the same group is
opened — same behavior `flutter_slidable`'s `groupTag` currently provides,
reimplemented without the package.

## Why both panes move, not just reply

The original plan was to build only the reply gesture and leave forums'
end pane on `flutter_slidable`, nesting a `Slidable` (with `startActionPane:
null`) inside `UniversalBubble` alongside the new custom drag. Verified
against the package's source
(`~/.pub-cache/hosted/pub.dev/flutter_slidable-4.0.3/lib/src/slidable.dart`
and `gesture_detector.dart`): `Slidable` installs one shared
`HorizontalDragGestureRecognizer` for the *whole* widget whenever
`Slidable.enabled` is true (the default), gated on the widget-level
`enabled` flag — NOT on whether the specific pane in a given drag direction
is null. So a nested `Slidable` kept only for the end pane would still
claim horizontal drags in the reply (start) direction too, competing with
the new custom recognizer on identical bounds — two
`HorizontalDragGestureRecognizer`s on overlapping hit-test regions is a
genuine arena conflict (undefined precedence between two recognizers of
the *same* type, unlike the drag/long-press/tap coexistence discussed
below, which works specifically because those recognizer types differ).
The only way to safely support both directions is one recognizer owning
the whole horizontal axis — hence building both panes on the same custom
primitive.

## Scope

- **In scope:** both the reply gesture (start-direction) and the
  Report/Delete reveal pane (end-direction), on `UniversalBubble`, used by
  `MessageBubble` (chat, start-direction only — chat has no end pane
  today) and `ForumPostBubble` (forums, both directions).
- **Out of scope:** `comment_thread_screen.dart` (opinions feature) stays
  on `flutter_slidable` unchanged — it has its own independent `Slidable`
  setup, not routed through `UniversalBubble`, and was not part of this
  request. `flutter_slidable` remains a dependency in `pubspec.yaml` for
  that one remaining consumer; it is fully removed from `UniversalBubble`
  and both bubble widgets that use it.

## Current behavior being replaced

- **Start pane (reply):** `UniversalBubble.startActionPane`, an
  `ActionPane` with a `DismissiblePane` that vetoes its own dismiss via
  `confirmDismiss` returning `false`, plus a visible `SlidableAction` reply
  chip. Both `MessageBubble` and `ForumPostBubble` configure this
  identically: full swipe past threshold fires `onReply()` directly via
  `confirmDismiss`, matching WhatsApp's "no tap needed" behavior already.
  The *visual* (a solid-color chip with icon+label sliding in,
  `extentRatio: 0.25` — a quarter of the bubble's width) becomes a
  fading/scaling reply icon in a small fixed-size gap, matching WhatsApp's
  actual look more closely.
- **End pane (Report/Delete, forums only):** `UniversalBubble.endActionPane`,
  a tap-to-reveal `ActionPane` (no `DismissiblePane` — the pane opens and
  stays open until a `SlidableAction` is tapped or the pane is otherwise
  closed). This behavior is preserved as-is functionally — reveal on drag,
  stay open, tap an action to fire it — just reimplemented on the new
  custom primitive instead of `flutter_slidable`.

What's being replaced in both cases is the *mechanism* (a third-party
package with an internal `Stack`/resize/removal/notification state machine)
with a purpose-built drag primitive that owns the bubble's entire
horizontal gesture axis.

## Mechanics

### Reply (start direction — right-to-left drag)

- **Trigger direction:** right-to-left drag only (bubble moves left,
  revealing the icon behind it on the right side of the bubble) —
  matches the existing `startActionPane`'s single direction. Not
  `isMine`-aware; both sent and received bubbles drag the same way,
  matching WhatsApp and the existing pre-replacement behavior.
- **Fire threshold:** 60 logical pixels of leftward drag.
- **Max drag / rubber-band cap:** 75px. Dragging past the fire threshold
  continues to move the bubble but with resistance (each additional pixel
  of raw drag moves the bubble less than 1:1), capping visually at 75px
  regardless of how far the underlying pointer travels — prevents the
  bubble from sliding an unbounded distance on an aggressive swipe.
- **Reply icon reveal:** a reply icon sits in the gap behind the bubble
  (revealed as the bubble slides left), fading in (opacity 0→1) and
  scaling slightly (0.7→1.0) as drag progresses from 0 to the fire
  threshold; held at full opacity/scale beyond the threshold.
  - Chat's icon color: `colorScheme.primary` (matches the old chip's
    `isMine ? colorScheme.primary : colorScheme.surfaceContainerHighest`
    background intent, simplified since there's no chip background
    anymore — just the icon, tinted primary).
  - Forums' icon color: the same `sideColor` (for/against) already used by
    the old `SlidableAction`'s `backgroundColor`.
- **Fire behavior:** on drag end (pointer up), if the drag distance at
  release was ≥ the fire threshold (60px), call `onReply()` immediately —
  no separate tap required, matching the current `confirmDismiss`-fires
  -on-full-swipe behavior. A light haptic
  (`HapticFeedback.lightImpact()`, via the existing unused `Haptics`
  abstraction in `lib/core/ui/feedback/haptics.dart` — this is the first
  real usage of that class) fires once, at the instant the drag crosses
  the 60px threshold during the drag (not on release) — matches WhatsApp's
  "you feel it commit before you let go" feel.
- **Spring-back:** regardless of whether `onReply` fired, the bubble
  animates back to its rest position (offset 0) over 200ms with an
  ease-out curve.
- **Below-threshold release:** no `onReply` call, bubble still springs
  back over the same 200ms — this is what makes it feel like a live drag
  rather than a two-state toggle.

### Report/Delete (end direction — left-to-right drag, forums only)

- **Trigger direction:** left-to-right drag only (bubble moves right,
  revealing action buttons behind it on the left side of the bubble).
  Only enabled when `endActions` (the new param, see below) is non-null —
  chat never sets this, so `MessageBubble` only ever exposes the reply
  direction.
- **Reveal threshold / stay-open extent:** dragging past 25% of the
  bubble's own width (matching the old `extentRatio: 0.25`) and releasing
  leaves the pane open at that fixed reveal width — no rubber-band cap
  needed here since there's no "fire on release," just a binary
  open/closed state once past a release threshold roughly at the midpoint
  of the reveal distance (drag more than half the target reveal width →
  snap fully open on release; less than half → snap back closed).
- **Revealed content:** whatever `endActions` renders — for forums, the
  existing Report (others' posts) or Delete (own posts) buttons, same
  icons/colors/logic as today's `SlidableAction`s, just laid out in a
  plain `Row` behind the bubble instead of inside a package's action pane.
- **Closing:** tapping a revealed action fires it (same as today) and
  closes the pane; dragging the bubble back left past the reveal threshold
  closes it without firing anything; opening another bubble in the same
  `groupTag` closes this one (see Group-close below).
- **No haptic, no auto-fire:** this pane is reveal-and-tap, not
  drag-to-commit — Delete is destructive and must not fire from a swipe
  alone, matching the existing (and correct) design decision already
  encoded in forums' current `endActionPane` (no `DismissiblePane` there,
  unlike the start pane).

### Group-close (`groupTag` replacement)

`flutter_slidable`'s `groupTag` uses a `NotificationListener` bubbling up
from each `Slidable` to a shared ancestor, which then closes every sibling
sharing the same tag when one opens. Reimplemented as a small
`ValueNotifier<Object?>`-based registry: an `InheritedNotifier` (or a
simple static `Map<Object, VoidCallback>` keyed by `groupTag`, given this
is a leaf-widget-to-leaf-widget signal, not something that needs full
`InheritedWidget` rebuild propagation) that each `UniversalBubble` instance
registers a close-callback into on mount and calls into on open — when
bubble A's end pane opens, it looks up any other registered callback under
the same `groupTag` and invokes it to close bubble B's pane if open. Scoped
per-screen (the registry lives no higher than the list/screen that already
passes a shared `groupTag` down, not global app state).

## Gesture arena interaction — must not break long-press or quote-tap

`UniversalBubble` already has two other gesture consumers on overlapping
widget bounds:
- `onLongPress` (the message-actions long-press menu, added when message
  actions shipped) — a `GestureDetector.onLongPress` wrapping the bubble
  fill.
- `onJumpToParent` (tap on the quoted-reply preview block) — a nested
  `GestureDetector.onTap` inside the bubble fill, only present when
  `quotedText != null`.

The new drag gesture must coexist with both:
- A **horizontal drag** and a **long press** are different gesture types
  (`HorizontalDragGestureRecognizer` vs `LongPressGestureRecognizer`) and
  don't compete in the arena the way two recognizers of the same type
  would — both observe the same pointer-down, and Flutter's arena resolves
  based on which one's win condition is met first (drag wins on
  sufficient horizontal movement before the long-press timer fires; the
  long-press timer wins if the pointer stays still long enough without
  horizontal movement past `kTouchSlop`). This is the same reasoning
  already validated for `onLongPress` coexisting with the quote-tap
  `onTap` (see prior long-press implementation's design notes) — extending
  it to a third, differently-typed recognizer follows the same rule.
- A **horizontal drag** and **vertical list scroll** (the message list is
  a vertically-scrolling `ListView`) are the classic case Flutter's gesture
  system is built to disambiguate via direction: use
  `HorizontalDragGestureRecognizer` specifically (not a generic pan/drag
  recognizer), which only claims the gesture once horizontal movement
  exceeds vertical movement past the touch slop — vertical drags fall
  through to the parent `ListView` untouched. This is exactly what
  `flutter_slidable`'s own `Slidable` widget does internally (it also uses
  a horizontal-only recognizer for this reason), so behavior here should
  match the pre-replacement feel.

## Widget structure change

`UniversalBubble` becomes a `StatefulWidget` (was `StatelessWidget`) to own
the `AnimationController` for the spring-back animation, the current
drag-offset state, and (when `endActions` is set) the open/closed state of
the end pane. `flutter_slidable` is no longer imported. Its public API
changes:

- **Removed:** `startActionPane` and `endActionPane` (the `ActionPane?`
  params) — no longer used; `flutter_slidable`'s `ActionPane`/
  `SlidableAction`/`DismissiblePane` types are gone from this widget's
  surface entirely.
- **Added:** `onReply: VoidCallback?` — null disables the reply swipe
  entirely (same "null disables it" convention every other optional
  callback on this widget already uses).
- **Added:** `endActions: List<Widget>?` — the buttons revealed by the
  end-direction drag (forums' Report/Delete). Null disables that swipe
  direction entirely — `MessageBubble` never sets this, so chat only ever
  exposes the reply direction, matching today's behavior exactly.
- **Kept:** `groupTag` (now backing the custom group-close registry
  instead of `flutter_slidable`'s `NotificationListener` mechanism —
  same caller-facing meaning, different implementation). `slidableKey`
  is renamed to `bubbleKey` (still a `Key?`, same purpose — preserving
  per-item drag/open state across list rebuilds — just no longer named
  after the package it originally came from).
- **Unchanged:** `onLongPress`, `onJumpToParent`, `quotedText`, and
  everything else not related to the swipe gesture.

## Testing

**Reply (start direction):**
- Dragging past 60px and releasing calls `onReply`.
- Dragging to 40px (below threshold) and releasing does NOT call
  `onReply`, and the bubble's rendered offset returns to 0 after the
  spring-back animation completes (`tester.pumpAndSettle()`).
- A vertical drag (simulating list scroll) does not trigger `onReply` and
  does not visibly offset the bubble.
- Dragging past the 75px cap does not move the bubble beyond 75px
  (rubber-band ceiling).

**Report/Delete (end direction, `endActions` set):**
- Dragging right past the reveal threshold and releasing leaves the pane
  open (buttons visible, tappable).
- Dragging right less than the reveal threshold and releasing snaps the
  pane back closed.
- Tapping a revealed action fires its callback and closes the pane.
- Opening bubble A's end pane (same `groupTag` as bubble B, which starts
  open) closes bubble B.
- `endActions == null` (chat's case) disables the end-direction drag
  entirely — dragging right does nothing.

**Shared / regression:**
- `onLongPress` still fires correctly on a stationary long-press
  (regression guard — must still work after this widget becomes
  stateful).
- `onJumpToParent` (quote-tap) still fires correctly on a quick tap when
  `quotedText != null` (regression guard).
- Full chat + forums test suites pass; `flutter analyze` clean on
  `universal_bubble.dart`, `message_bubble.dart`, `forum_post_bubble.dart`.
- Confirm `flutter_slidable` import is fully removed from all three files
  (`grep -rn "flutter_slidable" lib/core/widgets/universal_bubble.dart
  lib/features/chat/presentation/widgets/message_bubble.dart
  lib/features/forums/presentation/widgets/forum_post_bubble.dart` returns
  nothing) while `comment_thread_screen.dart` still imports it
  (untouched, out of scope).

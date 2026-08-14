# Bubble Press-Down Feedback — Design Spec

Date: 2026-08-14

## Goal

Add iMessage-style press feedback to `UniversalBubble`/`MessageBubble`: the
bubble scales down slightly the instant a finger touches it, holds while
pressed, then transitions into the existing focused-menu animation
(blur/scale-up, already built) once the long-press threshold fires. If the
press is cancelled (finger lifts or drags away before the threshold), the
bubble animates back to its resting scale rather than snapping.

## Current state

`UniversalBubble` wires `onLongPress` only — no `onTapDown`/`onTapUp`/
`onTapCancel` — so there is currently zero visual feedback while a finger is
down before the long-press fires. `_UniversalBubbleState` already has one
`AnimationController` (`_springController`, `SingleTickerProviderStateMixin`),
entirely dedicated to the swipe-gesture spring-back and driven by
`_dragOffset`. It is unrelated to press feedback and must not be reused or
disturbed.

The bubble fill's `GestureDetector` (the one carrying `onLongPress`) is
already nested inside the outer horizontal-drag `GestureDetector` — see
`universal_bubble.dart` around line 743. Both recognizers coexist today
without conflict; the new tap-down/up/cancel handlers must preserve that.

## Mechanics

### A second `AnimationController` for press scale

`_UniversalBubbleState` upgrades from `SingleTickerProviderStateMixin` to
`TickerProviderStateMixin` (required to host more than one ticker). A new
controller, `_pressController`, created eagerly in `initState` (matching
`_springController`'s existing eager-creation pattern and its documented
reason: a lazily-created controller's first tick after `dispose` calls
`createTicker` on an already-deactivated element via `TickerMode`'s
inherited-widget lookup, throwing "Looking up a deactivated widget's
ancestor is unsafe" — this codebase already hit and documented this exact
hazard for `_springController`, so `_pressController` must follow the same
eager pattern):

```dart
late final AnimationController _pressController;

@override
void initState() {
  super.initState();
  _springController = AnimationController(vsync: this, duration: _springBackDuration);
  _pressController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 120),
    reverseDuration: const Duration(milliseconds: 150),
    lowerBound: 0.0,
    upperBound: 1.0,
  );
}

@override
void dispose() {
  _springController.dispose();
  _pressController.dispose();
  super.dispose();
}
```

`_pressController`'s value drives a scale interpolation from `1.0` (rest) to
`0.97` (pressed), applied via a `Transform.scale` wrapping the bubble fill
`DecoratedBox` (the same widget carrying `_bubbleFillKey`). 120ms forward
(press-in, matches this codebase's existing "quick tactile feedback" feel
established by the swipe-reply icon's own 60ms-class timings) and 150ms
reverse (release/cancel, slightly slower — a soft settle, not a snap).

### Gesture wiring: `onTapDown` / `onTapUp` / `onTapCancel` alongside `onLongPress`

Add to the SAME `GestureDetector` that already carries `onLongPress` (the
bubble-fill one, not the outer horizontal-drag one):

```dart
GestureDetector(
  onLongPress: widget.onLongPress == null ? null : _handleLongPress,
  onTapDown: widget.onLongPress == null ? null : _handlePressDown,
  onTapUp: widget.onLongPress == null ? null : _handlePressUp,
  onTapCancel: widget.onLongPress == null ? null : _handlePressCancel,
  behavior: HitTestBehavior.opaque,
  child: Transform.scale(
    scale: _pressScale,
    child: DecoratedBox(
      key: _bubbleFillKey,
      ...
```

Gated identically to `onLongPress` (`widget.onLongPress == null ? null :
...`) — a bubble with no long-press affordance (read-only conversation, no
`currentUserId`) gets no press feedback either, matching the existing
null-disables-gesture convention this codebase already uses throughout
(`onReply`, `onLongPress` itself).

`GestureDetector` in Flutter fires `onTapDown`/`onTapUp`/`onTapCancel` from
its own internal `TapGestureRecognizer`, and `onLongPress` from a SEPARATE
`LongPressGestureRecognizer` — both recognizers enter the SAME gesture
arena for a single pointer-down, and Flutter's arena resolves them
independently: `onTapDown` fires immediately on pointer-down (before any
arena resolution, per `TapGestureRecognizer`'s own eager-acceptance
behavior), then EITHER `onTapUp` fires (if the pointer lifts before the
long-press timer) OR `onLongPress` fires (if the timer elapses first) OR
`onTapCancel` fires (if the pointer moves far enough to fail the tap's own
slop tolerance, e.g. a small drag). This is standard, well-defined
`GestureDetector` behavior — confirmed against Flutter's own
`gesture_detector.dart` source, not assumed — so no custom
`RawGestureDetector`/recognizer-priority work is needed.

```dart
void _handlePressDown(TapDownDetails details) {
  _pressController.forward();
}

void _handlePressUp(TapUpDetails details) {
  _pressController.reverse();
}

void _handlePressCancel() {
  _pressController.reverse();
}
```

`_handleLongPress` (the existing method that captures the bubble `Rect`
and calls `widget.onLongPress`) is UNCHANGED — it does not need to touch
`_pressController` at all. The moment `onLongPress` fires,
`showFocusedActionMenu` opens a dialog route whose `pageBuilder` snapshots
the bubble at ITS OWN captured `Rect` (already true today) and the
existing blur/scale-up animation takes over visually on that snapshot,
INDEPENDENT of the real bubble underneath. The real bubble's
`_pressController` should simply reverse back to 1.0 once the gesture
ends (Flutter calls `onTapCancel`, not `onTapUp`, when a long-press wins
the arena over the tap — confirmed against
`LongPressGestureRecognizer`/`TapGestureRecognizer`'s arena-resolution
source: the losing recognizer's `didStopTrackingLastPointer` path fires
the loser's own cancel, i.e. `onTapCancel` on the `TapGestureRecognizer`
when `LongPressGestureRecognizer` wins), so `_handlePressCancel` already
covers this path with no special-casing needed — the same reverse
animation that handles "finger lifted early" also naturally handles
"long-press fired instead."

### Value exposed to `build()`

```dart
double get _pressScale => 1.0 - 0.03 * _pressController.value;
```

Read inside `build()`'s existing `AnimatedBuilder`-free render path —
`_pressController` needs its own `AnimatedBuilder` (or
`AnimatedBuilder`-equivalent) wrapping just the `Transform.scale`, matching
the EXACT lesson already learned and documented in this codebase for
`focused_action_menu.dart`: a plain `build()` read of an
`AnimationController`'s `.value` outside an `AnimatedBuilder` only
re-renders on the NEXT unrelated rebuild, not on every animation tick —
freezing the scale at whatever value it happened to be on the last build
that ran for an unrelated reason. `_springController` in this same file
already gets this right (check its existing usage pattern for
`_dragOffset`-driven rebuilds before writing `_pressController`'s — follow
the same wrapping shape, do not introduce a second, differently-structured
pattern in the same file).

## What does NOT change

- `_springController`, `_dragOffset`, the whole swipe-gesture system —
  completely untouched, different controller, different recognizer
  (horizontal drag vs. tap/long-press), no shared state.
- `showFocusedActionMenu`'s own animation (blur backdrop, bubble
  scale-up-to-1.05, menu fade-in) — untouched. This spec only adds the
  PRE-long-press press-down phase; the POST-long-press focused-menu
  animation already exists and already works.
- `_handleLongPress`'s `Rect`/snapshot capture logic — untouched.
- `ForumPostBubble` — shares `UniversalBubble`, gets this behavior for
  free (same as it already gets the existing swipe/long-press mechanics)
  with no `ForumPostBubble`-specific code changes needed, matching this
  file's established "shared shell, callers opt in via the props they
  pass" pattern.

## Testing

- Widget test: `onTapDown` on a bubble with `onLongPress` set starts the
  press animation (`_pressController.value` moves off 0 within a pump).
- Widget test: `onTapUp` before the long-press threshold reverses the
  press animation back toward 0 (verify via `tester.pump()` at a partial
  duration, not just settled start/end values — matching this session's
  established "assert mid-transition, not just at rest" discipline from
  the focused-menu animation's own fix round).
- Widget test: a drag/cancel (`onTapCancel`) also reverses the press
  animation.
- Widget test: a bubble with `onLongPress: null` gets no press animation
  at all (gated identically) — `_pressController` never leaves 0, or the
  handlers are simply never wired (either is an acceptable implementation
  detail; the observable behavior — no scale change — is what the test
  asserts).
- Regression: all existing `universal_bubble_test.dart` swipe-gesture
  tests must still pass unmodified — the new press controller must not
  alter `_dragOffset`/`_springController` behavior in any way.
- Regression: `message_bubble_test.dart`'s long-press tests (opens the
  action sheet, snapshot sizing, deleted-message no-op) must still pass
  — `_handleLongPress`'s own behavior is unchanged, only what happens
  BEFORE it fires is new.

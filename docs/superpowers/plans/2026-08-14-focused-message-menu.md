# Focused Message Menu Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the current bottom-sheet long-press menu with an iMessage-style focused overlay — the bubble stays at its exact screen position and scales up slightly, the backdrop blurs/dims, the action list floats anchored beside the bubble, and a haptic fires the instant it opens.

**Architecture:** A new reusable overlay function (`showFocusedActionMenu`) built on `showGeneralDialog` with a custom `pageBuilder`/`transitionBuilder` drives the entrance/exit animation (scale + blur + fade) as a single dialog-route transition, no separate `AnimationController`. `UniversalBubble.onLongPress` changes shape from a bare `VoidCallback?` to a callback carrying the bubble's captured screen `Rect` and a snapshot widget, captured via a new `GlobalKey` on the existing bubble-fill `DecoratedBox`. `message_actions_sheet.dart`'s action list becomes a `List<Widget>` builder consumed by the new overlay instead of calling `showModalBottomSheet` itself.

**Tech Stack:** Flutter (`showGeneralDialog`, `BackdropFilter`/`ImageFilter.blur`, `HapticFeedback`), no new packages.

## Global Constraints

- Design spec: `docs/superpowers/specs/2026-08-14-focused-message-menu-design.md` — every mechanic below must match it exactly.
- Scope: chat's `MessageBubble` long-press menu only. `ForumPostBubble` never sets `onLongPress` today (confirmed) and none is added — its only exposure to this plan is `UniversalBubble.onLongPress`'s type change, which is compile-safe and behavior-neutral for it.
- The overlay mechanism (`showFocusedActionMenu`) is general-purpose, not chat-specific — takes an anchor `Rect`, a snapshot `Widget`, and a `List<Widget>` of actions; has no knowledge of `Message`/chat domain types.
- The six actions (Reply/Copy/Star/Pin/Edit/Delete), their icons/labels/colors, and the `canEditOrDelete` gating logic are reused exactly as `message_actions_sheet.dart` already implements them — only the container changes.
- Blur sigma: 12 (matching this codebase's existing `BackdropFilter` precedent in `lib/home/widgets/home_widget.dart`). `ClipRect`/`ClipRRect` must wrap any `BackdropFilter` — confirmed existing codebase requirement, blur otherwise spills unclipped.
- Bubble scale: 1.0 → ~1.05 as the overlay opens, driven by the dialog route's own transition animation, not a second independent `AnimationController`.
- Menu position: below the bubble by default (`top: anchorRect.bottom + gap`), flips above when there isn't room below the safe area.
- Haptic (`HapticFeedback.lightImpact()` from `package:flutter/services.dart`, matching `UniversalBubble`'s existing direct-call pattern established in the swipe-gesture work — not the still-unwired `Haptics` abstraction) fires synchronously at the top of `showFocusedActionMenu`, before `showGeneralDialog` is called.
- Dismiss: tap the scrim (outside bubble/menu) → close, no action fires. Tap an action → its callback fires, then closes. System back → closes (default `showGeneralDialog` behavior).
- Algorithm Quality Review Checklist v3.1 gate: this feature is scoped `[MOBILE][UI]`. Checklist items this plan explicitly satisfies: 5.2 (interactive p95 ≤200ms — dialog transition duration must feel immediate, not sluggish; target ≤250ms total open animation, matching iOS's own context-menu feel), 5.6 (accessibility — the overlay's action list must remain screen-reader-navigable, same `Semantics` behavior `ListTile` already provides for free), 2.10/2.16 (resource lifecycle — the dialog route's own animation controller is owned and disposed by the Navigator, not manually managed, avoiding a leak class this plan would otherwise have to guard against).

---

### Task 1: `showFocusedActionMenu` — the reusable overlay widget

**Files:**
- Create: `lib/core/widgets/focused_action_menu.dart`
- Test: `test/core/widgets/focused_action_menu_test.dart`

**Interfaces:**
- Consumes: nothing from other tasks (first task, fully self-contained — takes only `BuildContext`, `Rect`, `Widget`, `List<Widget>`, no chat/message domain types).
- Produces: `Future<void> showFocusedActionMenu({required BuildContext context, required Rect anchorRect, required Widget anchorSnapshot, required List<Widget> actions})` — for Task 3 (`MessageBubble`/`message_actions_sheet.dart` wiring) to call.

- [ ] **Step 1: Write the failing tests**

```dart
// test/core/widgets/focused_action_menu_test.dart
import 'package:attune/core/widgets/focused_action_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('opens the overlay showing the anchor snapshot and the given actions',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showFocusedActionMenu(
                context: context,
                anchorRect: const Rect.fromLTWH(20, 100, 200, 60),
                anchorSnapshot: const Text('bubble snapshot'),
                actions: [
                  ListTile(title: const Text('Action A'), onTap: () {}),
                ],
              ),
              child: const Text('trigger'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('trigger'));
    await tester.pumpAndSettle();

    expect(find.text('bubble snapshot'), findsOneWidget);
    expect(find.text('Action A'), findsOneWidget);
  });

  testWidgets('tapping the scrim dismisses without firing any action', (tester) async {
    var fired = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showFocusedActionMenu(
                context: context,
                anchorRect: const Rect.fromLTWH(20, 100, 200, 60),
                anchorSnapshot: const Text('bubble snapshot'),
                actions: [
                  ListTile(title: const Text('Action A'), onTap: () => fired = true),
                ],
              ),
              child: const Text('trigger'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('trigger'));
    await tester.pumpAndSettle();

    // Tap far outside both the snapshot and the action list — a corner of
    // the screen the scrim covers but the anchored content does not.
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    expect(fired, isFalse);
    expect(find.text('Action A'), findsNothing);
  });

  testWidgets(
      'tapping an action that pops its own route fires onTap and closes the overlay',
      (tester) async {
    // Contract: each action item is responsible for popping its own route
    // on tap, same as message_actions_sheet.dart's real ListTiles already
    // do — the menu wrapper deliberately swallows taps that land on it
    // (see _FocusedActionMenuOverlay's menu-level GestureDetector) so an
    // action's own tap never falls through to the scrim's dismiss handler
    // and double-fires. An action that does NOT pop itself is expected to
    // leave the overlay open — that's this test's contrast case, not a bug
    // in the overlay.
    var fired = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showFocusedActionMenu(
                context: context,
                anchorRect: const Rect.fromLTWH(20, 100, 200, 60),
                anchorSnapshot: const Text('bubble snapshot'),
                actions: [
                  Builder(
                    builder: (actionContext) => ListTile(
                      title: const Text('Action A'),
                      onTap: () {
                        Navigator.of(actionContext).pop();
                        fired = true;
                      },
                    ),
                  ),
                ],
              ),
              child: const Text('trigger'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('trigger'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Action A'));
    await tester.pumpAndSettle();

    expect(fired, isTrue);
    expect(find.text('Action A'), findsNothing);
  });

  testWidgets('menu flips above the bubble when there is no room below',
      (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showFocusedActionMenu(
                context: context,
                // Anchored near the very bottom of an 800-tall viewport —
                // no room below for a multi-item action list.
                anchorRect: const Rect.fromLTWH(20, 760, 200, 30),
                anchorSnapshot: const Text('bubble snapshot'),
                actions: [
                  ListTile(title: const Text('Action A'), onTap: () {}),
                  ListTile(title: const Text('Action B'), onTap: () {}),
                  ListTile(title: const Text('Action C'), onTap: () {}),
                ],
              ),
              child: const Text('trigger'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('trigger'));
    await tester.pumpAndSettle();

    final actionATop = tester.getTopLeft(find.text('Action A')).dy;
    final anchorTop = 760.0;
    // Flipped-above means the action list's top sits above the anchor's
    // own top, not below its bottom.
    expect(actionATop, lessThan(anchorTop));
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/core/widgets/focused_action_menu_test.dart`
Expected: FAIL — `focused_action_menu.dart` doesn't exist yet.

- [ ] **Step 3: Write the widget**

```dart
// lib/core/widgets/focused_action_menu.dart
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;

/// iMessage-style long-press action menu: the anchor (a duplicate of the
/// long-pressed bubble, painted at its real screen position) scales up
/// slightly as the backdrop blurs and dims behind it, and the given
/// [actions] float anchored beside it — below by default, flipped above
/// when there isn't room. General-purpose: has no knowledge of chat or
/// Message — callers hand in exactly what to render.
///
/// See docs/superpowers/specs/2026-08-14-focused-message-menu-design.md.
Future<void> showFocusedActionMenu({
  required BuildContext context,
  required Rect anchorRect,
  required Widget anchorSnapshot,
  required List<Widget> actions,
}) {
  // Fires synchronously, before the route even opens — matches "the
  // instant the menu opens," not deferred to an animation-complete
  // callback.
  HapticFeedback.lightImpact();

  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierColor: Colors.transparent,
    barrierLabel: 'Message actions',
    // 220ms: comfortably under the checklist's 250ms interactive-feel
    // target for the full open animation, matching iOS's own
    // context-menu transition speed.
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (dialogContext, animation, secondaryAnimation) {
      return _FocusedActionMenuOverlay(
        anchorRect: anchorRect,
        anchorSnapshot: anchorSnapshot,
        actions: actions,
        animation: animation,
      );
    },
  );
}

class _FocusedActionMenuOverlay extends StatelessWidget {
  const _FocusedActionMenuOverlay({
    required this.anchorRect,
    required this.anchorSnapshot,
    required this.actions,
    required this.animation,
  });

  final Rect anchorRect;
  final Widget anchorSnapshot;
  final List<Widget> actions;
  final Animation<double> animation;

  // Rough per-item height estimate for the flip-above/below decision —
  // ListTile's default dense-false height is 56, plus a little breathing
  // room. Doesn't need to be exact: worst case the menu slightly overlaps
  // the safe area edge on an unusually tall action list, which is far
  // better than rendering fully off-screen.
  static const double _estimatedItemHeight = 56;
  static const double _gap = 8;

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final safeAreaBottom = MediaQuery.of(context).padding.bottom;
    final estimatedMenuHeight = actions.length * _estimatedItemHeight;

    final fitsBelow = anchorRect.bottom + _gap + estimatedMenuHeight <=
        screenSize.height - safeAreaBottom;

    return GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      behavior: HitTestBehavior.opaque,
      child: Stack(
        children: [
          ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Container(color: Colors.black.withValues(alpha: 0.3 * animation.value)),
            ),
          ),
          Positioned.fromRect(
            rect: anchorRect,
            child: IgnorePointer(
              child: Transform.scale(
                scale: 1.0 + 0.05 * animation.value,
                child: anchorSnapshot,
              ),
            ),
          ),
          Positioned(
            left: anchorRect.left,
            top: fitsBelow ? anchorRect.bottom + _gap : null,
            bottom: fitsBelow
                ? null
                : screenSize.height - anchorRect.top + _gap,
            child: FadeTransition(
              opacity: animation,
              child: GestureDetector(
                // Swallow taps on the menu itself so they don't fall
                // through to the scrim's dismiss-on-tap-outside handler —
                // individual action ListTiles still handle their own
                // onTap and pop the route themselves.
                onTap: () {},
                child: Material(
                  borderRadius: BorderRadius.circular(14),
                  elevation: 8,
                  clipBehavior: Clip.antiAlias,
                  child: SizedBox(
                    width: 240,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: actions,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
```

Note: each item in `actions` is responsible for calling
`Navigator.of(context).pop()` itself before/after firing its own callback
— this matches the existing `ListTile.onTap` pattern
`message_actions_sheet.dart` already uses (Task 3 wires this). This
widget's own outer `GestureDetector.onTap` handles ONLY the
tap-outside-to-dismiss case; it never intercepts an action's own tap
because the `Positioned` menu `GestureDetector` sits above it in the
`Stack` and swallows its own taps first (confirm this ordering in the
tests — Step 1's "tapping an action fires its own onTap" test is the
proof this coexistence works).

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/core/widgets/focused_action_menu_test.dart`
Expected: all 4 tests PASS.

- [ ] **Step 5: Run `dart analyze`**

Run: `dart analyze lib/core/widgets/focused_action_menu.dart`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add lib/core/widgets/focused_action_menu.dart test/core/widgets/focused_action_menu_test.dart
git commit -m "feat(chat): add reusable iMessage-style focused action menu overlay"
```

---

### Task 2: `UniversalBubble` — capture bubble geometry for the long-press trigger

**Files:**
- Modify: `lib/core/widgets/universal_bubble.dart`
- Modify: `test/core/widgets/universal_bubble_test.dart`

**Interfaces:**
- Consumes: nothing from Task 1 (parallel-safe, but sequenced after it in this plan since Task 3 needs both).
- Produces: `UniversalBubble.onLongPress` changes type from `VoidCallback?` to `void Function(Rect bubbleRect, Widget bubbleSnapshot)?` — for Task 3 (`MessageBubble`) to consume.

- [ ] **Step 1: Read the current file's long-press wiring in full**

Read `lib/core/widgets/universal_bubble.dart` around the `DecoratedBox`
that renders the bubble fill (search for `color: widget.bubbleColor,` —
this is the exact widget whose `Rect` needs capturing) and the
`GestureDetector` that wraps it (`onLongPress: widget.onLongPress`,
currently one level up). Confirm no drift from what this plan assumes
before editing.

- [ ] **Step 2: Write the failing tests**

Replace the two existing long-press tests in
`test/core/widgets/universal_bubble_test.dart`
(`onLongPress fires when the bubble is long-pressed` and
`omitting onLongPress renders with no long-press handler`) — both
currently use a bare `() => longPressed = true` callback, which no
longer type-checks once `onLongPress`'s signature changes. Replace with:

```dart
  testWidgets('onLongPress fires with the bubble\'s captured Rect and a snapshot widget',
      (tester) async {
    Rect? capturedRect;
    Widget? capturedSnapshot;
    await _pump(
      tester,
      UniversalBubble(
        isMine: true,
        bubbleColor: Colors.blue,
        onBubbleColor: Colors.white,
        content: const Text('hello'),
        footer: const SizedBox.shrink(),
        onLongPress: (rect, snapshot) {
          capturedRect = rect;
          capturedSnapshot = snapshot;
        },
      ),
    );

    await tester.longPress(find.text('hello'));
    await tester.pumpAndSettle();

    expect(capturedRect, isNotNull);
    // A real, non-degenerate on-screen rect — not a zero-size default.
    expect(capturedRect!.width, greaterThan(0));
    expect(capturedRect!.height, greaterThan(0));
    expect(capturedSnapshot, isNotNull);
  });

  testWidgets('omitting onLongPress renders with no long-press handler',
      (tester) async {
    // Regression guard for ForumPostBubble, the other UniversalBubble
    // caller, which does not pass onLongPress — must keep rendering with
    // zero behavior change when the param is omitted.
    await _pump(
      tester,
      UniversalBubble(
        isMine: true,
        bubbleColor: Colors.blue,
        onBubbleColor: Colors.white,
        content: const Text('hello'),
        footer: const SizedBox.shrink(),
      ),
    );

    await tester.longPress(find.text('hello'));
    await tester.pumpAndSettle();
    // No assertion needed beyond "did not throw" — absence of a handler
    // must be a true no-op, not an error.
  });
```

- [ ] **Step 3: Run tests to verify the first one fails**

Run: `flutter test test/core/widgets/universal_bubble_test.dart`
Expected: the new first test FAILS (type mismatch — `onLongPress` is
still `VoidCallback?`); the second test currently still compiles/passes
as-is since it doesn't touch the callback's signature, but note both were
replaced in Step 2 for consistency — confirm the file still compiles
after Step 2's edit before concluding this step (if it doesn't compile at
all yet, that's expected until Step 4 lands the type change).

- [ ] **Step 4: Implement the geometry capture**

In `lib/core/widgets/universal_bubble.dart`:

Change the field type and doc comment:

```dart
  /// Long-press handler on the bubble's fill (not the quote block, which
  /// has its own tap-to-jump gesture). Receives the bubble's captured
  /// on-screen Rect and a duplicate of its visual content, for a caller
  /// to render into a focused-menu overlay (see
  /// docs/superpowers/specs/2026-08-14-focused-message-menu-design.md).
  /// Null (the default) means no long-press behavior — ForumPostBubble,
  /// this widget's other caller, does not pass this and must see zero
  /// behavior change.
  final void Function(Rect bubbleRect, Widget bubbleSnapshot)? onLongPress;
```

Add a `GlobalKey` to `_UniversalBubbleState` (alongside the existing
`_bubbleRowKey`/`_endActionsRowKey`):

```dart
  /// Keys the actual bubble-fill DecoratedBox (not the outer Row/Padding
  /// wrappers) so onLongPress can read its exact on-screen Rect at the
  /// moment of a long-press — safe to call here specifically because
  /// onLongPress only fires after the widget has already been laid out
  /// and painted at least once, unlike the reveal-width measurement
  /// elsewhere in this file, which has to avoid reading size during
  /// build().
  final GlobalKey _bubbleFillKey = GlobalKey();
```

Add a handler method:

```dart
  void _handleLongPress() {
    final onLongPress = widget.onLongPress;
    if (onLongPress == null) return;
    final renderBox =
        _bubbleFillKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.attached) return;
    final rect = renderBox.localToGlobal(Offset.zero) & renderBox.size;
    // Reconstructs the SAME visual bubble fill — same decoration, same
    // padding, same content — as a fresh widget subtree to paint into the
    // overlay, rather than an async RepaintBoundary.toImage() capture
    // (avoids the pixel-ratio/async round-trip that would introduce for a
    // menu that needs to open instantly).
    final snapshot = DecoratedBox(
      decoration: BoxDecoration(
        color: widget.bubbleColor,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: widget.content,
      ),
    );
    onLongPress(rect, snapshot);
  }
```

Update the `GestureDetector` and `DecoratedBox` to use the key and the
new handler:

```dart
                                  child: GestureDetector(
                                    onLongPress: widget.onLongPress == null
                                        ? null
                                        : _handleLongPress,
                                    behavior: HitTestBehavior.opaque,
                                    child: DecoratedBox(
                                      key: _bubbleFillKey,
                                      decoration: BoxDecoration(
                                        color: widget.bubbleColor,
                                        borderRadius: BorderRadius.circular(18),
                                      ),
```

(Only the two lines shown change — `onLongPress:` and the added `key:` —
everything else inside `DecoratedBox` stays exactly as it is today.)

Note the deliberate omission from the snapshot: it does NOT reproduce the
quoted-text preview block or the `AnimatedContainer` highlight border —
just the bubble fill's color/shape/content, matching the design spec's
"same visual bubble... not a screenshot" framing at the level of "looks
like the bubble," not a pixel-perfect clone including reply-preview
chrome. This is a deliberate scope boundary, not an oversight — flag in
your report if you think this reads as visually incomplete once built,
but do not expand scope to compensate without checking with the plan
first.

- [ ] **Step 5: Run tests to verify they pass**

Run: `flutter test test/core/widgets/universal_bubble_test.dart`
Expected: all tests pass (the two long-press tests from Step 2, plus
every pre-existing test in this file — none of which touch
`onLongPress`'s signature — must still pass unchanged).

- [ ] **Step 6: Run `dart analyze`**

Run: `dart analyze lib/core/widgets/universal_bubble.dart`
Expected: `No issues found!`

- [ ] **Step 7: Confirm `ForumPostBubble` still compiles**

Run: `dart analyze lib/features/forums/presentation/widgets/forum_post_bubble.dart`
Expected: `No issues found!` (confirms the type change is genuinely
compile-safe for the caller that never sets this param — per the design
spec's explicit claim, verify it holds).

- [ ] **Step 8: Commit**

```bash
git add lib/core/widgets/universal_bubble.dart test/core/widgets/universal_bubble_test.dart
git commit -m "feat(chat): UniversalBubble.onLongPress now captures the bubble's screen Rect and a content snapshot"
```

---

### Task 3: Wire `MessageBubble` + `message_actions_sheet.dart` to the focused menu

**Files:**
- Modify: `lib/features/chat/presentation/widgets/message_actions_sheet.dart`
- Modify: `lib/features/chat/presentation/widgets/message_bubble.dart`
- Modify: `test/features/chat/presentation/widgets/message_actions_sheet_test.dart`

**Interfaces:**
- Consumes: `showFocusedActionMenu` (Task 1), `UniversalBubble.onLongPress`'s new signature (Task 2).
- Produces: nothing for later tasks — this is the plan's final code task.

- [ ] **Step 1: Read both files in full**

Read `lib/features/chat/presentation/widgets/message_actions_sheet.dart`
(98 lines) and `lib/features/chat/presentation/widgets/message_bubble.dart`
(the `onLongPress:` wiring around line 94-110) to confirm no drift before
editing.

- [ ] **Step 2: Rewrite `message_actions_sheet.dart` as an action-list builder**

Replace the whole file:

```dart
// lib/features/chat/presentation/widgets/message_actions_sheet.dart
import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:flutter/material.dart';

/// Builds the six-action list (Reply/Copy/Star/Pin/Edit/Delete) for a
/// message's long-press menu — Edit/Delete are omitted (not
/// shown-disabled) once [Message.canEditOrDelete] is false, matching the
/// design spec's "no dead menu item that invites a confused tap"
/// decision. Pure UI, no repository/Riverpod dependency, no
/// presentation container of its own — the caller (MessageBubble, via
/// showFocusedActionMenu) owns how/where this list is displayed and all
/// mutation logic/error handling behind each callback.
List<Widget> buildMessageActionItems({
  required BuildContext context,
  required Message message,
  required String currentUserId,
  required bool isStarred,
  required bool isPinned,
  required VoidCallback onReply,
  required VoidCallback onCopy,
  required VoidCallback onStar,
  required VoidCallback onUnstar,
  required VoidCallback onPin,
  required VoidCallback onUnpin,
  required VoidCallback onEdit,
  required VoidCallback onDelete,
}) {
  final canEditOrDelete = message.canEditOrDelete(
    currentUserId: currentUserId,
    now: DateTime.now(),
  );

  return [
    ListTile(
      leading: const Icon(Icons.reply),
      title: const Text('Reply'),
      onTap: () {
        Navigator.of(context).pop();
        onReply();
      },
    ),
    ListTile(
      leading: const Icon(Icons.copy),
      title: const Text('Copy'),
      onTap: () {
        Navigator.of(context).pop();
        onCopy();
      },
    ),
    ListTile(
      leading: Icon(isStarred ? Icons.star : Icons.star_border),
      title: Text(isStarred ? 'Unstar' : 'Star'),
      onTap: () {
        Navigator.of(context).pop();
        isStarred ? onUnstar() : onStar();
      },
    ),
    ListTile(
      leading: Icon(isPinned ? Icons.push_pin : Icons.push_pin_outlined),
      title: Text(isPinned ? 'Unpin' : 'Pin'),
      onTap: () {
        Navigator.of(context).pop();
        isPinned ? onUnpin() : onPin();
      },
    ),
    if (canEditOrDelete) ...[
      ListTile(
        leading: const Icon(Icons.edit),
        title: const Text('Edit'),
        onTap: () {
          Navigator.of(context).pop();
          onEdit();
        },
      ),
      ListTile(
        leading: Icon(Icons.delete, color: Theme.of(context).colorScheme.error),
        title: Text(
          'Delete',
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
        onTap: () {
          Navigator.of(context).pop();
          onDelete();
        },
      ),
    ],
  ];
}
```

Note the critical detail: each `ListTile.onTap` calls
`Navigator.of(context).pop()` using the `context` THIS FUNCTION is
called with — Task 1's `showFocusedActionMenu` passes its own
`dialogContext`-scoped `BuildContext` down through wherever these
`ListTile`s end up in the widget tree, so `Navigator.of(context)` here
must resolve to the SAME navigator the dialog route was pushed onto. This
works correctly because `buildMessageActionItems` is called with the
`BuildContext` from INSIDE `showFocusedActionMenu`'s `pageBuilder`
(passed through by `MessageBubble` in Step 3 below) — not the original
long-press call site's context, which is a different, now-stale
`BuildContext` once the dialog route exists on top of it.

- [ ] **Step 3: Run the existing test file to see what breaks**

Run: `flutter test test/features/chat/presentation/widgets/message_actions_sheet_test.dart`
Expected: FAIL to compile — `showMessageActionsSheet` no longer exists.

- [ ] **Step 4: Rewrite the test file to match the new function name/shape**

Replace the whole file — same five test cases, adapted to call
`buildMessageActionItems` directly (a pure function returning
`List<Widget>`, no `showModalBottomSheet`/`showFocusedActionMenu`
involved — that's Task 1's already-tested job) and render the returned
list in a plain `Column` for assertions:

```dart
// test/features/chat/presentation/widgets/message_actions_sheet_test.dart
import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:attune/features/chat/presentation/widgets/message_actions_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Message _ownMessage({bool starred = false, bool canEditOrDelete = true}) {
  return Message.optimistic(
    id: 'm1',
    clientMessageId: 'c1',
    relationshipId: 'r1',
    senderId: 'u1',
    content: 'hello',
    createdAt: canEditOrDelete
        ? DateTime.now()
        : DateTime.now().subtract(const Duration(minutes: 10)),
  );
}

Widget _wrap(List<Widget> Function(BuildContext) build) {
  return MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => Column(children: build(context)),
      ),
    ),
  );
}

void main() {
  testWidgets('shows Reply, Copy, Star, Pin, Edit, Delete for an own recent message',
      (tester) async {
    await tester.pumpWidget(
      _wrap((context) => buildMessageActionItems(
            context: context,
            message: _ownMessage(),
            currentUserId: 'u1',
            isStarred: false,
            isPinned: false,
            onReply: () {},
            onCopy: () {},
            onStar: () {},
            onUnstar: () {},
            onPin: () {},
            onUnpin: () {},
            onEdit: () {},
            onDelete: () {},
          )),
    );

    expect(find.text('Reply'), findsOneWidget);
    expect(find.text('Copy'), findsOneWidget);
    expect(find.text('Star'), findsOneWidget);
    expect(find.text('Pin'), findsOneWidget);
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
  });

  testWidgets('omits Edit and Delete when the 5-minute window has passed',
      (tester) async {
    await tester.pumpWidget(
      _wrap((context) => buildMessageActionItems(
            context: context,
            message: _ownMessage(canEditOrDelete: false),
            currentUserId: 'u1',
            isStarred: false,
            isPinned: false,
            onReply: () {},
            onCopy: () {},
            onStar: () {},
            onUnstar: () {},
            onPin: () {},
            onUnpin: () {},
            onEdit: () {},
            onDelete: () {},
          )),
    );

    expect(find.text('Reply'), findsOneWidget);
    expect(find.text('Edit'), findsNothing);
    expect(find.text('Delete'), findsNothing);
  });

  testWidgets('omits Edit and Delete for a message from the other partner',
      (tester) async {
    final theirMessage = Message.optimistic(
      id: 'm2',
      clientMessageId: 'c2',
      relationshipId: 'r1',
      senderId: 'partner',
      content: 'hi',
      createdAt: DateTime.now(),
    );

    await tester.pumpWidget(
      _wrap((context) => buildMessageActionItems(
            context: context,
            message: theirMessage,
            currentUserId: 'u1',
            isStarred: false,
            isPinned: false,
            onReply: () {},
            onCopy: () {},
            onStar: () {},
            onUnstar: () {},
            onPin: () {},
            onUnpin: () {},
            onEdit: () {},
            onDelete: () {},
          )),
    );

    expect(find.text('Edit'), findsNothing);
    expect(find.text('Delete'), findsNothing);
  });

  testWidgets('shows Unstar instead of Star when isStarred is true', (tester) async {
    await tester.pumpWidget(
      _wrap((context) => buildMessageActionItems(
            context: context,
            message: _ownMessage(),
            currentUserId: 'u1',
            isStarred: true,
            isPinned: false,
            onReply: () {},
            onCopy: () {},
            onStar: () {},
            onUnstar: () {},
            onPin: () {},
            onUnpin: () {},
            onEdit: () {},
            onDelete: () {},
          )),
    );

    expect(find.text('Unstar'), findsOneWidget);
    expect(find.text('Star'), findsNothing);
  });

  testWidgets('tapping Delete calls onDelete', (tester) async {
    var deleted = false;
    await tester.pumpWidget(
      _wrap((context) => buildMessageActionItems(
            context: context,
            message: _ownMessage(),
            currentUserId: 'u1',
            isStarred: false,
            isPinned: false,
            onReply: () {},
            onCopy: () {},
            onStar: () {},
            onUnstar: () {},
            onPin: () {},
            onUnpin: () {},
            onEdit: () {},
            onDelete: () => deleted = true,
          )),
    );

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(deleted, isTrue);
  });
}
```

(This test file intentionally does NOT assert on `Navigator.pop()`
behavior — there's no dialog route pushed in this test's plain-`Column`
setup, so calling `Navigator.of(context).pop()` on a `Scaffold`-only
route would pop the WHOLE test route, which isn't what's being tested
here and isn't meaningful without Task 1's overlay in the tree. Pop
behavior in the context of a real dialog route is implicitly covered by
Task 1's own "tapping an action fires its own onTap and the overlay
closes" test, which uses a real `ListTile`+`Navigator.pop` inside an
actual dialog route.)

- [ ] **Step 5: Run the rewritten test file**

Run: `flutter test test/features/chat/presentation/widgets/message_actions_sheet_test.dart`
Expected: all 5 tests PASS.

- [ ] **Step 6: Wire `MessageBubble` to call `showFocusedActionMenu`**

In `lib/features/chat/presentation/widgets/message_bubble.dart`:

Change the import from `message_actions_sheet.dart`'s old function name,
and add the new overlay import:

```dart
import 'package:attune/core/widgets/focused_action_menu.dart';
import 'package:attune/features/chat/presentation/widgets/message_actions_sheet.dart';
```

Replace the `onLongPress: canOpenActions ? () => showMessageActionsSheet(...) : null`
block (currently lines 94-110) with:

```dart
      onLongPress: canOpenActions
          ? (bubbleRect, bubbleSnapshot) => showFocusedActionMenu(
                context: context,
                anchorRect: bubbleRect,
                anchorSnapshot: bubbleSnapshot,
                actions: buildMessageActionItems(
                  context: context,
                  message: message,
                  currentUserId: currentUserId!,
                  isStarred: isStarred,
                  isPinned: isPinned,
                  onReply: onReply ?? () {},
                  onCopy: onCopy ?? () {},
                  onStar: onStar ?? () {},
                  onUnstar: onUnstar ?? () {},
                  onPin: onPin ?? () {},
                  onUnpin: onUnpin ?? () {},
                  onEdit: onEdit ?? () {},
                  onDelete: onDelete ?? () {},
                ),
              )
          : null,
```

Note the `context` passed to `buildMessageActionItems` here is
`MessageBubble.build`'s own context (the long-press call site), not a
context from inside the dialog's `pageBuilder` — and that's correct, not
a bug. `Navigator.of(context)` resolves to the nearest ANCESTOR
`Navigator` by walking the LIVE widget tree at the moment it's called,
not by capturing anything at closure-creation time — so a `ListTile.onTap`
closure created here, then invoked later (after `showGeneralDialog` has
pushed the dialog route onto that same `Navigator`), still finds that
`Navigator` and pops whichever route is currently on top of it, which by
then is the dialog. `MessageBubble` remains mounted throughout (the
long-press flow never unmounts it), so its `context` stays valid the
whole time. `showFocusedActionMenu`'s `actions:` parameter staying a
plain, already-built `List<Widget>` (as Task 1 defined it) is therefore
correct as-is — no signature change needed. Task 1's own "tapping an
action fires its own onTap and the overlay closes" test already proves
this exact mechanism works (a `ListTile` built with the OUTER
`Builder`'s context, tapped after the dialog is showing, correctly pops
only the dialog) — this task's Step 7 chat-suite run is the second,
real-usage confirmation of the same property, not a novel risk.

- [ ] **Step 7: Run the full chat test suite**

Run: `flutter test test/features/chat/`
Expected: PASS, no regressions. Pay particular attention to any test that
exercises the long-press → menu → action-tap flow end to end (if none
exists yet at the `MessageBubble` level, that's fine — Task 1's and this
task's own test files are the primary coverage; note in your report
whether an end-to-end `MessageBubble`-level test would be valuable and,
if it's a small addition, add it).

- [ ] **Step 8: Run `dart analyze`**

Run: `dart analyze lib/features/chat/presentation/widgets/message_actions_sheet.dart lib/features/chat/presentation/widgets/message_bubble.dart`
Expected: `No issues found!`

- [ ] **Step 9: Commit**

```bash
git add lib/features/chat/presentation/widgets/message_actions_sheet.dart lib/features/chat/presentation/widgets/message_bubble.dart test/features/chat/presentation/widgets/message_actions_sheet_test.dart
git commit -m "feat(chat): wire MessageBubble's long-press menu to the focused action menu overlay"
```

---

### Task 4: Full regression pass + Algorithm Quality Review Checklist verification

**Files:** none (verification only)

**Interfaces:**
- Consumes: everything from Tasks 1-3.
- Produces: nothing — this is the plan's final verification task.

- [ ] **Step 1: Run the full Flutter test suite**

Run: `flutter test`
Expected: PASS, matching the project's known pre-existing baseline (at
last count: 15 failures — 13 unrelated pre-existing failures in
`test/core/intro/`, `test/app/routing/feature_intro_route_wiring_test.dart`,
`test/features/settings/sound_toggle_widget_test.dart`,
`test/features/settings/chat_feel_section_widget_test.dart`,
`test/widget_test.dart`, `test/login_profile_test.dart`, plus 2 in
`test/features/chat/chat_couples_locked_screen_healing_entry_test.dart`).
Confirm the failing set is IDENTICAL to this list, not a superset. If any
NEW test fails, that's a regression this plan introduced — stop and fix
it before proceeding.

- [ ] **Step 2: Run `dart analyze` on the whole project**

Run: `dart analyze`
Expected: 0 errors. Compare the total issue count against `git log -1
--format=%H -- .` on the commit before Task 1 if the count seems
meaningfully higher — some new `info`-level lints from new code are
expected and fine, 0 errors is non-negotiable.

- [ ] **Step 3: Algorithm Quality Review Checklist v3.1 — explicit gate walkthrough**

This feature is scoped `[MOBILE][UI]`. Walk and document each item the
plan's Global Constraints section claims to satisfy:

- **5.2 (p95 ≤200ms interactive / ≤250ms full transition here)**: confirm
  `showFocusedActionMenu`'s `transitionDuration` is `220ms` (unchanged
  from Task 1) — this is a static config value, not something requiring a
  runtime trace in this sandboxed environment, but confirm the value is
  actually what's shipped, not accidentally altered by any later task's
  edits.
- **5.6 (accessibility)**: confirm the action list inside the overlay is
  still built from real `ListTile` widgets (not custom-painted, no-semantics
  replacements) — `ListTile` provides `Semantics` support out of the box,
  and this plan never replaces it with anything else, so this should hold
  by construction. Confirm by reading the final `message_actions_sheet.dart`.
- **2.10/2.16 (resource lifecycle / concurrency)**: confirm no manually-
  created `AnimationController` was added anywhere in this feature (the
  design deliberately reuses `showGeneralDialog`'s own route-owned
  animation, per the Global Constraints section) — grep for
  `AnimationController` across the three new/changed files in this plan
  and confirm zero matches, which is the structural proof this constraint
  holds.

Document the outcome of this walkthrough in your final report — a short
paragraph per item is sufficient, this is a verification checklist, not a
place to introduce new work.

- [ ] **Step 4: Manual smoke-test note**

This plan builds real interactive animation (scale, blur, fade, position
flip) that automated widget tests can verify mechanically (does the
overlay open, does it contain the right widgets, does dismiss work) but
cannot fully judge for VISUAL feel — does the blur look right, does the
scale feel subtle rather than jarring, does the menu's flip-above
transition look smooth on a real device. Note in your final report that a
human should manually test the focused message menu in a running app
(long-press a message near the top of the chat, near the bottom, and in
the middle) before considering this fully verified — this is a limitation
of automated verification in this environment, not a step to silently
skip.

- [ ] **Step 5: No commit needed unless a regression was found and fixed**

This task is verification-only. If Steps 1-2 pass cleanly, report DONE
with the checklist walkthrough from Step 3 and the smoke-test note from
Step 4. If a regression was found, fix it and commit with a message
describing what was caught and corrected.

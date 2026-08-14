# Custom Swipe-to-Reply Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `flutter_slidable` inside `UniversalBubble` with a custom-built drag gesture matching WhatsApp's real swipe-to-reply feel (start direction) and a custom reveal-and-stay pane for forums' Report/Delete (end direction), removing the package from `UniversalBubble`, `MessageBubble`, and `ForumPostBubble` entirely.

**Architecture:** `UniversalBubble` becomes a `StatefulWidget` owning one `AnimationController`-driven horizontal offset, a small `HorizontalDragGestureRecognizer`-based gesture (via `GestureDetector.onHorizontalDragStart/Update/End`) that serves both directions, and a lightweight static registry replacing `flutter_slidable`'s `groupTag` "close my siblings" mechanism. `MessageBubble` and `ForumPostBubble` pass `onReply`/`endActions` instead of `startActionPane`/`endActionPane`.

**Tech Stack:** Flutter (`AnimationController`, `GestureDetector`, `HapticFeedback` from `flutter/services.dart`), no new packages.

## Global Constraints

- Design spec: `docs/superpowers/specs/2026-08-14-custom-swipe-to-reply-design.md` — every numeric value (60px fire threshold, 75px rubber-band cap, 200ms spring-back, ease-out curve) and every behavioral rule below must match it exactly.
- `flutter_slidable` is removed from `universal_bubble.dart`, `message_bubble.dart`, and `forum_post_bubble.dart` — confirmed by `grep` at the end of this plan. It remains a `pubspec.yaml` dependency (still used by `comment_thread_screen.dart`, out of scope, untouched).
- Reply (start direction, right-to-left drag): fires `onReply` immediately on release past the 60px threshold — no separate tap. Below-threshold release always springs back with no callback fired.
- Report/Delete (end direction, left-to-right drag, forums only via `endActions`): reveal-and-stay, never auto-fires on drag — only a tap on a revealed action fires it. `MessageBubble` never sets `endActions`.
- Group-close: opening one bubble's end pane must close any other bubble's open end pane sharing the same `groupTag`, matching the old `flutter_slidable` behavior exactly.
- Gesture-arena safety: the new horizontal drag must not break the existing `onLongPress` (long-press menu) or `onJumpToParent` (quote-block tap) gestures, and must not intercept vertical list-scroll gestures — verified in the design spec by reasoning about recognizer types; this plan's tests assert it directly.
- Haptic: `HapticFeedback.lightImpact()` (from `package:flutter/services.dart`, called directly — `UniversalBubble` has zero Riverpod dependency today and this plan does not introduce one) fires once, at the instant the reply drag crosses the 60px threshold during the drag (not on release).

---

### Task 1: `UniversalBubble` — reply gesture (start direction only)

**Files:**
- Modify: `lib/core/widgets/universal_bubble.dart`
- Modify: `test/core/widgets/universal_bubble_test.dart`

**Interfaces:**
- Consumes: nothing from other tasks (first task).
- Produces: `UniversalBubble` becomes `StatefulWidget`; new `onReply: VoidCallback?` param; `startActionPane` param removed. `endActionPane`, `slidableKey` (kept, not yet renamed — Task 2 renames it), `groupTag` are UNCHANGED in this task (still present, still typed as before) — Task 2 builds the end-direction pane and the group-close registry on top of this task's drag-offset machinery. This task's job is ONLY the reply direction; leave `endActionPane`'s existing `flutter_slidable` rendering in place for now (still imported, still used for the end pane) so `ForumPostBubble` keeps compiling and working between this task and Task 2.

- [ ] **Step 1: Read the current full file**

Read `lib/core/widgets/universal_bubble.dart` in full (already read during
planning — 267 lines) before editing, to confirm no drift since this plan
was written.

- [ ] **Step 2: Write the failing tests**

Replace the two `Slidable`-asserting tests in
`test/core/widgets/universal_bubble_test.dart` (`startActionPane is wired
into the Slidable` and `no action panes means Slidable still renders with
null panes`) with new tests for the custom gesture. Remove the
`import 'package:flutter_slidable/flutter_slidable.dart';` line from this
test file — it will no longer be needed anywhere in it. Replace those two
tests with:

```dart
  testWidgets('dragging past the fire threshold and releasing calls onReply',
      (tester) async {
    var replied = false;
    await _pump(
      tester,
      UniversalBubble(
        isMine: false,
        bubbleColor: Colors.blue,
        onBubbleColor: Colors.white,
        content: const Text('swipeable'),
        footer: const SizedBox.shrink(),
        onReply: () => replied = true,
      ),
    );

    final center = tester.getCenter(find.text('swipeable'));
    final gesture = await tester.startGesture(center);
    await gesture.moveBy(const Offset(-70, 0));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(replied, isTrue);
  });

  testWidgets('dragging below the fire threshold and releasing does not call onReply',
      (tester) async {
    var replied = false;
    await _pump(
      tester,
      UniversalBubble(
        isMine: false,
        bubbleColor: Colors.blue,
        onBubbleColor: Colors.white,
        content: const Text('swipeable'),
        footer: const SizedBox.shrink(),
        onReply: () => replied = true,
      ),
    );

    final center = tester.getCenter(find.text('swipeable'));
    final gesture = await tester.startGesture(center);
    await gesture.moveBy(const Offset(-40, 0));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(replied, isFalse);
  });

  testWidgets('onReply null disables the swipe gesture entirely', (tester) async {
    await _pump(
      tester,
      UniversalBubble(
        isMine: false,
        bubbleColor: Colors.blue,
        onBubbleColor: Colors.white,
        content: const Text('no gesture'),
        footer: const SizedBox.shrink(),
      ),
    );

    final center = tester.getCenter(find.text('no gesture'));
    final gesture = await tester.startGesture(center);
    await gesture.moveBy(const Offset(-70, 0));
    await gesture.up();
    await tester.pumpAndSettle();
    // No assertion beyond "did not throw" — omitting onReply must be a
    // true no-op, matching this widget's existing null-disables convention.
  });

  testWidgets('a vertical drag does not trigger onReply', (tester) async {
    var replied = false;
    await _pump(
      tester,
      UniversalBubble(
        isMine: false,
        bubbleColor: Colors.blue,
        onBubbleColor: Colors.white,
        content: const Text('vertical drag'),
        footer: const SizedBox.shrink(),
        onReply: () => replied = true,
      ),
    );

    final center = tester.getCenter(find.text('vertical drag'));
    final gesture = await tester.startGesture(center);
    await gesture.moveBy(const Offset(0, -70));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(replied, isFalse);
  });
```

Keep every other existing test in this file (`isMine=true aligns...`,
`renders content and footer`, `quotedText renders...`, `no quotedText
means...`, `onLongPress fires...`, `omitting onLongPress renders...`) —
they don't touch swipe internals and must keep passing unchanged.

- [ ] **Step 3: Run tests to verify the new ones fail**

Run: `flutter test test/core/widgets/universal_bubble_test.dart`
Expected: the 4 new tests FAIL (`onReply` param doesn't exist yet); the
existing 6 tests still PASS (they don't reference the removed
`startActionPane` param — `Slidable` is still in the widget tree for
`endActionPane` at this point in the plan).

- [ ] **Step 4: Implement the reply-direction drag gesture**

In `lib/core/widgets/universal_bubble.dart`:

Change the class declaration and add the state class:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_slidable/flutter_slidable.dart';

// ... (doc comment unchanged) ...
class UniversalBubble extends StatefulWidget {
  const UniversalBubble({
    super.key,
    required this.isMine,
    required this.bubbleColor,
    required this.onBubbleColor,
    required this.content,
    required this.footer,
    this.leading,
    this.onReply,
    this.endActionPane,
    this.quotedText,
    this.onJumpToParent,
    this.isHighlighted = false,
    this.highlightColor,
    this.maxWidth = 320,
    this.slidableKey,
    this.groupTag,
    this.onLongPress,
    this.quoteBackgroundColor,
    this.quoteForegroundColor,
    this.quoteTextStyle,
    this.quoteIconSize = 20,
  });

  // ... all existing fields EXCEPT startActionPane, which is deleted ...

  /// Swipe-right-to-left-to-reply target. Null disables the reply swipe
  /// gesture entirely (e.g. a read-only/archived conversation has nothing
  /// sensible to reply into). Fires immediately on release once the drag
  /// has passed the fire threshold — no separate tap required, matching
  /// WhatsApp's swipe-to-reply.
  final VoidCallback? onReply;

  /// Swipe-left-to-right action pane (e.g. Report/Delete). Null disables
  /// that swipe direction entirely. Still flutter_slidable-backed as of
  /// this task — Task 2 replaces it with the custom endActions pane.
  final ActionPane? endActionPane;

  // ... leading, quotedText, onJumpToParent, isHighlighted, highlightColor,
  // maxWidth, slidableKey, groupTag, onLongPress, quoteBackgroundColor,
  // quoteForegroundColor, quoteTextStyle, quoteIconSize: ALL UNCHANGED ...

  @override
  State<UniversalBubble> createState() => _UniversalBubbleState();
}

class _UniversalBubbleState extends State<UniversalBubble>
    with SingleTickerProviderStateMixin {
  static const double _fireThreshold = 60;
  static const double _maxDrag = 75;
  static const Duration _springBackDuration = Duration(milliseconds: 200);

  late final AnimationController _springController = AnimationController(
    vsync: this,
    duration: _springBackDuration,
  );
  Animation<double>? _springAnimation;

  /// Current horizontal drag offset in logical pixels. Negative = dragged
  /// left (reply direction). 0 at rest. Rubber-banded to _maxDrag once the
  /// raw drag exceeds _fireThreshold.
  double _dragOffset = 0;
  bool _hapticFired = false;

  @override
  void dispose() {
    _springController.dispose();
    super.dispose();
  }

  void _onHorizontalDragStart(DragStartDetails details) {
    if (widget.onReply == null) return;
    _springController.stop();
    _hapticFired = false;
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    if (widget.onReply == null) return;
    final rawOffset = _dragOffset + details.delta.dx;
    // Only leftward (negative) drag matters for reply in this task —
    // clamp at 0 so a rightward drag has no visual effect (Task 2 adds
    // rightward behavior for endActions).
    final clamped = rawOffset > 0 ? 0.0 : rawOffset;
    final magnitude = clamped.abs();
    setState(() {
      if (magnitude <= _fireThreshold) {
        _dragOffset = clamped;
      } else {
        // Rubber-band: linearly compress the excess past the threshold
        // into the remaining (_maxDrag - _fireThreshold) budget.
        final excess = magnitude - _fireThreshold;
        final compressed = _fireThreshold +
            (excess / (excess + 40)) * (_maxDrag - _fireThreshold);
        _dragOffset = -compressed;
      }
    });
    if (!_hapticFired && _dragOffset.abs() >= _fireThreshold) {
      _hapticFired = true;
      HapticFeedback.lightImpact();
    }
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    if (widget.onReply == null) return;
    final shouldFire = _dragOffset.abs() >= _fireThreshold;
    _animateSpringBack();
    if (shouldFire) {
      widget.onReply!();
    }
  }

  void _animateSpringBack() {
    final start = _dragOffset;
    _springAnimation = Tween<double>(begin: start, end: 0).animate(
      CurvedAnimation(parent: _springController, curve: Curves.easeOut),
    )..addListener(() {
        setState(() => _dragOffset = _springAnimation!.value);
      });
    _springController.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    // ... body below replaces the old build() — see Step 5 for the full
    // widget tree, which wraps the existing Slidable (still handling
    // endActionPane in this task) in a new outer GestureDetector for the
    // reply direction, and applies _dragOffset via Transform.translate.
  }
}
```

- [ ] **Step 5: Wire the gesture and offset into the widget tree**

Replace the old `build` method's `Slidable`-wrapping structure. Keep the
existing `Slidable` (for `endActionPane`, still `flutter_slidable`-backed
in this task) but set `startActionPane: null` unconditionally on it (it
never handled the reply direction after this task anyway — confirm the old
`Slidable` widget still accepts a `null` `startActionPane`, which it
already does today when `MessageBubble.onReply` was null), and wrap the
whole `IntrinsicWidth` in a new `GestureDetector` that owns the reply
drag, with the drag offset applied via `Transform.translate` and a reply
icon rendered behind the bubble when `_dragOffset != 0`:

```dart
  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: widget.isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: GestureDetector(
          onHorizontalDragStart: widget.onReply == null ? null : _onHorizontalDragStart,
          onHorizontalDragUpdate: widget.onReply == null ? null : _onHorizontalDragUpdate,
          onHorizontalDragEnd: widget.onReply == null ? null : _onHorizontalDragEnd,
          behavior: HitTestBehavior.opaque,
          child: Stack(
            alignment: Alignment.centerRight,
            children: [
              if (_dragOffset < 0)
                Positioned(
                  right: 0,
                  child: Opacity(
                    opacity: (_dragOffset.abs() / _fireThreshold).clamp(0.0, 1.0),
                    child: Transform.scale(
                      scale: 0.7 + 0.3 * (_dragOffset.abs() / _fireThreshold).clamp(0.0, 1.0),
                      child: Icon(
                        Icons.reply,
                        color: widget.isMine
                            ? widget.bubbleColor
                            : widget.onBubbleColor,
                      ),
                    ),
                  ),
                ),
              Transform.translate(
                offset: Offset(_dragOffset, 0),
                // IntrinsicWidth: Slidable internally builds a Stack for its
                // action panes, which expands to fill whatever width it's
                // handed regardless of its child's own size — without this
                // every bubble renders full-width and Align's left/right
                // positioning above is silently defeated.
                child: IntrinsicWidth(
                  child: Slidable(
                    key: widget.slidableKey,
                    groupTag: widget.groupTag,
                    startActionPane: null,
                    endActionPane: widget.endActionPane,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (widget.leading != null) ...[
                          widget.leading!,
                          const SizedBox(width: 4),
                        ],
                        Flexible(
                          child: Column(
                            crossAxisAlignment: widget.isMine
                                ? CrossAxisAlignment.end
                                : CrossAxisAlignment.start,
                            children: [
                              ConstrainedBox(
                                constraints: BoxConstraints(maxWidth: widget.maxWidth),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 400),
                                  curve: Curves.easeOut,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: widget.isHighlighted
                                          ? (widget.highlightColor ?? widget.bubbleColor)
                                          : Colors.transparent,
                                      width: 2,
                                    ),
                                  ),
                                  padding: const EdgeInsets.all(2),
                                  child: GestureDetector(
                                    onLongPress: widget.onLongPress,
                                    behavior: HitTestBehavior.opaque,
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        color: widget.bubbleColor,
                                        borderRadius: BorderRadius.circular(18),
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 14,
                                          vertical: 10,
                                        ),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            if (widget.quotedText != null) ...[
                                              GestureDetector(
                                                onTap: widget.onJumpToParent,
                                                behavior: HitTestBehavior.opaque,
                                                child: Container(
                                                  padding: const EdgeInsets.all(6),
                                                  decoration: BoxDecoration(
                                                    color: widget.quoteBackgroundColor ??
                                                        widget.onBubbleColor.withValues(alpha: 0.15),
                                                    borderRadius: BorderRadius.circular(8),
                                                  ),
                                                  child: Row(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      Icon(
                                                        Icons.format_quote,
                                                        size: widget.quoteIconSize,
                                                        color: widget.quoteForegroundColor ?? widget.onBubbleColor,
                                                      ),
                                                      const SizedBox(width: 4),
                                                      Flexible(
                                                        child: Text(
                                                          widget.quotedText!,
                                                          style: widget.quoteTextStyle ??
                                                              TextStyle(
                                                                color: widget.quoteForegroundColor ?? widget.onBubbleColor,
                                                                fontSize: 12,
                                                              ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                            ],
                                            widget.content,
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 4),
                              ConstrainedBox(
                                constraints: BoxConstraints(maxWidth: widget.maxWidth),
                                child: widget.footer,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
```

(This is the same widget tree as before, with every `this.` reference
changed to `widget.` since the build logic moved from `StatelessWidget` to
`State`, `startActionPane` removed from the `Slidable` construction, and
the new outer `GestureDetector`/`Stack`/`Transform.translate`/reply-icon
layer added around the existing `IntrinsicWidth`.)

- [ ] **Step 6: Run tests to verify they pass**

Run: `flutter test test/core/widgets/universal_bubble_test.dart`
Expected: all 10 tests PASS (6 pre-existing + 4 new).

- [ ] **Step 7: Update `MessageBubble` — remove `startActionPane`, add `onReply`**

In `lib/features/chat/presentation/widgets/message_bubble.dart`:

Remove the `import 'package:flutter_slidable/flutter_slidable.dart';` line.

Replace the `startActionPane: onReply == null ? null : ActionPane(...)`
block (the whole multi-line `ActionPane`/`DismissiblePane`/`SlidableAction`
construction, lines 112-145 as of this plan's writing) with a single line
in the `UniversalBubble(...)` constructor call:

```dart
      onReply: onReply,
```

`MessageBubble`'s own `onReply` field/doc-comment stays exactly as-is —
only the internal wiring into `UniversalBubble` changes.

- [ ] **Step 8: Run the chat test suite**

Run: `flutter test test/features/chat/`
Expected: PASS, no regressions. (Neither existing
`message_bubble_test.dart` file references `Slidable`/`ActionPane`
directly — confirmed during planning — so no test changes needed there
beyond what Step 2 already did to `universal_bubble_test.dart`.)

- [ ] **Step 9: Commit**

```bash
git add lib/core/widgets/universal_bubble.dart lib/features/chat/presentation/widgets/message_bubble.dart test/core/widgets/universal_bubble_test.dart
git commit -m "feat(chat): custom swipe-to-reply gesture, replacing flutter_slidable's start pane"
```

---

### Task 2: `UniversalBubble` — end pane (`endActions`) + group-close registry

**Files:**
- Modify: `lib/core/widgets/universal_bubble.dart`
- Modify: `test/core/widgets/universal_bubble_test.dart`

**Interfaces:**
- Consumes: `_UniversalBubbleState`'s drag-offset/spring-back machinery from Task 1.
- Produces: `endActions: List<Widget>?` param (replaces `endActionPane: ActionPane?`), `bubbleKey` (renamed from `slidableKey`), fully removes `flutter_slidable` from this file. For Task 3 (`ForumPostBubble`) to consume.

- [ ] **Step 1: Write the failing tests**

Add to `test/core/widgets/universal_bubble_test.dart`:

```dart
  testWidgets('dragging right past the reveal threshold and releasing leaves the end pane open',
      (tester) async {
    await _pump(
      tester,
      UniversalBubble(
        isMine: false,
        bubbleColor: Colors.blue,
        onBubbleColor: Colors.white,
        content: const Text('has end actions'),
        footer: const SizedBox.shrink(),
        endActions: [
          TextButton(onPressed: () {}, child: const Text('Delete')),
        ],
      ),
    );

    final center = tester.getCenter(find.text('has end actions'));
    final gesture = await tester.startGesture(center);
    await gesture.moveBy(const Offset(60, 0));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.text('Delete'), findsOneWidget);
    // The button must be laid out with a real, tappable size once revealed
    // — not clipped to zero width.
    final buttonSize = tester.getSize(find.text('Delete'));
    expect(buttonSize.width, greaterThan(0));
  });

  testWidgets('dragging right below the reveal threshold snaps the end pane back closed',
      (tester) async {
    await _pump(
      tester,
      UniversalBubble(
        isMine: false,
        bubbleColor: Colors.blue,
        onBubbleColor: Colors.white,
        content: const Text('has end actions'),
        footer: const SizedBox.shrink(),
        endActions: [
          TextButton(onPressed: () {}, child: const Text('Delete')),
        ],
      ),
    );

    final center = tester.getCenter(find.text('has end actions'));
    final gesture = await tester.startGesture(center);
    await gesture.moveBy(const Offset(20, 0));
    await gesture.up();
    await tester.pumpAndSettle();

    // Closed means the revealed action is not hit-testable/visible at a
    // meaningful size — the widget may still exist in the tree behind the
    // bubble, so assert on the bubble's own rendered offset instead.
    final transform = tester.widget<Transform>(
      find.ancestor(of: find.text('has end actions'), matching: find.byType(Transform)).first,
    );
    expect(transform.transform.getTranslation().x, 0);
  });

  testWidgets('tapping a revealed end action fires it and closes the pane',
      (tester) async {
    var deleted = false;
    await _pump(
      tester,
      UniversalBubble(
        isMine: false,
        bubbleColor: Colors.blue,
        onBubbleColor: Colors.white,
        content: const Text('has end actions'),
        footer: const SizedBox.shrink(),
        endActions: [
          TextButton(onPressed: () => deleted = true, child: const Text('Delete')),
        ],
      ),
    );

    final center = tester.getCenter(find.text('has end actions'));
    final gesture = await tester.startGesture(center);
    await gesture.moveBy(const Offset(60, 0));
    await gesture.up();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(deleted, isTrue);
  });

  testWidgets('endActions null disables the end-direction drag entirely', (tester) async {
    await _pump(
      tester,
      UniversalBubble(
        isMine: false,
        bubbleColor: Colors.blue,
        onBubbleColor: Colors.white,
        content: const Text('no end actions'),
        footer: const SizedBox.shrink(),
      ),
    );

    final center = tester.getCenter(find.text('no end actions'));
    final gesture = await tester.startGesture(center);
    await gesture.moveBy(const Offset(60, 0));
    await gesture.up();
    await tester.pumpAndSettle();
    // No assertion beyond "did not throw" — matches this widget's existing
    // null-disables convention.
  });

  testWidgets('opening bubble A closes bubble B in the same groupTag', (tester) async {
    await _pump(
      tester,
      Column(
        children: [
          UniversalBubble(
            key: const ValueKey('a'),
            isMine: false,
            bubbleColor: Colors.blue,
            onBubbleColor: Colors.white,
            content: const Text('bubble A'),
            footer: const SizedBox.shrink(),
            groupTag: 'group1',
            endActions: [TextButton(onPressed: () {}, child: const Text('Delete A'))],
          ),
          UniversalBubble(
            key: const ValueKey('b'),
            isMine: false,
            bubbleColor: Colors.blue,
            onBubbleColor: Colors.white,
            content: const Text('bubble B'),
            footer: const SizedBox.shrink(),
            groupTag: 'group1',
            endActions: [TextButton(onPressed: () {}, child: const Text('Delete B'))],
          ),
        ],
      ),
    );

    // Open A.
    var center = tester.getCenter(find.text('bubble A'));
    var gesture = await tester.startGesture(center);
    await gesture.moveBy(const Offset(60, 0));
    await gesture.up();
    await tester.pumpAndSettle();

    // Open B — A should close as a side effect.
    center = tester.getCenter(find.text('bubble B'));
    gesture = await tester.startGesture(center);
    await gesture.moveBy(const Offset(60, 0));
    await gesture.up();
    await tester.pumpAndSettle();

    final transformA = tester.widget<Transform>(
      find.ancestor(of: find.text('bubble A'), matching: find.byType(Transform)).first,
    );
    expect(transformA.transform.getTranslation().x, 0);
  });
```

- [ ] **Step 2: Run tests to verify the new ones fail**

Run: `flutter test test/core/widgets/universal_bubble_test.dart`
Expected: the new tests FAIL (`endActions` param doesn't exist yet).

- [ ] **Step 3: Implement the group-close registry**

Add a new top-level (file-private) class in `universal_bubble.dart`, above
`UniversalBubble`:

```dart
/// Replaces flutter_slidable's groupTag "close my siblings" mechanism.
/// One registry entry per active groupTag; each open UniversalBubble
/// registers a close callback under its tag, overwriting any prior
/// registrant — opening a new bubble in the same group therefore only
/// needs to invoke whatever callback was registered before it, then
/// register its own. Scoped to process lifetime (a static field), which
/// is fine here since the only state is "how do I close myself," not
/// anything that needs disposal beyond what each bubble's own dispose()
/// already does (removing its registration).
class _EndPaneGroupRegistry {
  static final Map<Object, VoidCallback> _openCallbacks = {};

  static void notifyOpening(Object groupTag, VoidCallback closeSelf) {
    final previous = _openCallbacks[groupTag];
    if (previous != null && previous != closeSelf) {
      previous();
    }
    _openCallbacks[groupTag] = closeSelf;
  }

  static void notifyClosed(Object groupTag, VoidCallback closeSelf) {
    if (_openCallbacks[groupTag] == closeSelf) {
      _openCallbacks.remove(groupTag);
    }
  }
}
```

- [ ] **Step 4: Add end-direction drag state and handlers**

In `_UniversalBubbleState`, add:

```dart
  static const double _endPaneRevealRatio = 0.25;

  bool _endPaneOpen = false;

  double get _endPaneRevealWidth {
    // Matches the old ActionPane's extentRatio: 0.25 — a quarter of the
    // bubble's own rendered width. context.size is only valid after the
    // first layout; guard with a sane fallback used only on the very
    // first build before layout has happened.
    final width = context.size?.width ?? 200;
    return width * _endPaneRevealRatio;
  }

  void _onEndPaneDragUpdate(DragUpdateDetails details) {
    if (widget.endActions == null) return;
    final rawOffset = _dragOffset + details.delta.dx;
    final clamped = rawOffset < 0 ? 0.0 : rawOffset;
    setState(() {
      _dragOffset = clamped.clamp(0.0, _endPaneRevealWidth);
    });
  }

  void _onEndPaneDragEnd(DragEndDetails details) {
    if (widget.endActions == null) return;
    final shouldOpen = _dragOffset >= _endPaneRevealWidth / 2;
    if (shouldOpen) {
      _openEndPane();
    } else {
      _closeEndPane();
    }
  }

  void _openEndPane() {
    setState(() {
      _dragOffset = _endPaneRevealWidth;
      _endPaneOpen = true;
    });
    if (widget.groupTag != null) {
      _EndPaneGroupRegistry.notifyOpening(widget.groupTag!, _closeEndPane);
    }
  }

  void _closeEndPane() {
    if (!_endPaneOpen && _dragOffset == 0) return;
    setState(() {
      _endPaneOpen = false;
    });
    _animateSpringBackFrom(_dragOffset);
    if (widget.groupTag != null) {
      _EndPaneGroupRegistry.notifyClosed(widget.groupTag!, _closeEndPane);
    }
  }
```

Rename the existing `_animateSpringBack` (from Task 1, which always
targets 0 from the current `_dragOffset`) to accept an explicit start value
so both the reply-direction bounce-back and the end-pane close can share
it — replace Task 1's `_animateSpringBack()` (no args) with:

```dart
  void _animateSpringBackFrom(double start) {
    _springAnimation = Tween<double>(begin: start, end: 0).animate(
      CurvedAnimation(parent: _springController, curve: Curves.easeOut),
    )..addListener(() {
        setState(() => _dragOffset = _springAnimation!.value);
      });
    _springController.forward(from: 0);
  }
```

And update Task 1's `_onHorizontalDragEnd` to call `_animateSpringBackFrom(_dragOffset)`
instead of the old no-arg `_animateSpringBack()`.

Update `dispose()` to also clean up any group registration:

```dart
  @override
  void dispose() {
    if (widget.groupTag != null && _endPaneOpen) {
      _EndPaneGroupRegistry.notifyClosed(widget.groupTag!, _closeEndPane);
    }
    _springController.dispose();
    super.dispose();
  }
```

- [ ] **Step 5: Merge the two drag directions into one gesture, add the `endActions` field, remove `flutter_slidable`**

Remove `import 'package:flutter_slidable/flutter_slidable.dart';` entirely.

Replace `final ActionPane? endActionPane;` with:

```dart
  /// Widgets revealed by a left-to-right drag (e.g. Report/Delete buttons).
  /// Null disables that swipe direction entirely. Stays open once past the
  /// reveal threshold until a revealed action is tapped, the bubble is
  /// dragged back closed, or another bubble sharing [groupTag] opens.
  final List<Widget>? endActions;
```

Rename `slidableKey` to `bubbleKey` (update both the field declaration and
its doc comment to drop the `flutter_slidable`-specific framing — "needed
so per-item drag/open state stays attached to the right item when this
widget is rendered in a rebuilt/reordered list," same purpose, no longer
tied to the removed package).

Merge the horizontal drag callbacks into single handlers that branch by
sign, replacing the three `_onHorizontalDrag*` methods from Task 1 with
versions that also call the end-pane handlers:

A per-event sign check on `details.delta.dx` is NOT safe here — a real
drag isn't perfectly monotonic, and a single frame of jitter in the
opposite direction (common near the start of a drag, before the gesture
has "committed") would misroute that frame's delta to the wrong handler.
Instead, lock a `_DragMode` once at the first update that has a
non-trivial magnitude, and route every subsequent update in that same
gesture through that mode until the gesture ends:

```dart
  _DragMode? _activeDragMode;

  void _onHorizontalDragStart(DragStartDetails details) {
    _springController.stop();
    _hapticFired = false;
    _activeDragMode = null;
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    _activeDragMode ??= details.delta.dx < 0 ? _DragMode.reply : _DragMode.endPane;
    if (_activeDragMode == _DragMode.reply && widget.onReply != null) {
      _onReplyDragUpdate(details);
    } else if (_activeDragMode == _DragMode.endPane && widget.endActions != null) {
      _onEndPaneDragUpdate(details);
    }
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    if (_activeDragMode == _DragMode.reply) {
      _onReplyDragEnd(details);
    } else if (_activeDragMode == _DragMode.endPane) {
      _onEndPaneDragEnd(details);
    }
    _activeDragMode = null;
  }
```

Add the enum near the top of the file, alongside the other private
helpers:

```dart
enum _DragMode { reply, endPane }
```

(Rename Task 1's `_onHorizontalDragUpdate`/`_onHorizontalDragEnd` to
`_onReplyDragUpdate`/`_onReplyDragEnd` to free up the merged names above —
their bodies are otherwise unchanged from Task 1.)

Update the `GestureDetector` in `build()` to always wire these three
handlers unconditionally (no longer gated on `widget.onReply == null`
alone, since the end direction has its own independent null-check inside
each handler):

```dart
        child: GestureDetector(
          onHorizontalDragStart: _onHorizontalDragStart,
          onHorizontalDragUpdate: _onHorizontalDragUpdate,
          onHorizontalDragEnd: _onHorizontalDragEnd,
          behavior: HitTestBehavior.opaque,
```

Replace the inner `Slidable(...)` construction entirely — it's no longer
needed now that `endActionPane` (the `ActionPane?`) is gone. The
`endActions` widgets render in a new `Positioned` layer on the LEFT side of
the `Stack` (mirroring the reply icon's `Positioned(right: 0, ...)` from
Task 1), revealed behind the bubble as it's dragged right:

```dart
              if (_dragOffset > 0)
                Positioned(
                  left: 0,
                  child: SizedBox(
                    width: _dragOffset,
                    child: ClipRect(
                      child: OverflowBox(
                        maxWidth: _endPaneRevealWidth,
                        alignment: Alignment.centerLeft,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: widget.endActions ?? const [],
                        ),
                      ),
                    ),
                  ),
                ),
```

And replace the `IntrinsicWidth(child: Slidable(key: ..., groupTag: ...,
startActionPane: null, endActionPane: ..., child: Row(...)))` wrapper with
just `IntrinsicWidth(child: Row(key: widget.bubbleKey, mainAxisSize:
MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children:
[...]))` — same `Row` children as before (the `if (widget.leading !=
null)` + `Flexible(child: Column(...))` structure), just no longer nested
inside a `Slidable`.

- [ ] **Step 6: Run tests to verify they pass**

Run: `flutter test test/core/widgets/universal_bubble_test.dart`
Expected: all tests PASS (10 from Task 1 + 5 new from this task = 15).

- [ ] **Step 7: Confirm `flutter_slidable` is fully gone from this file**

Run: `grep -n "flutter_slidable\|Slidable\|ActionPane" lib/core/widgets/universal_bubble.dart`
Expected: no output.

- [ ] **Step 8: Commit**

```bash
git add lib/core/widgets/universal_bubble.dart test/core/widgets/universal_bubble_test.dart
git commit -m "feat(chat): custom reveal-and-stay end pane + group-close registry, remove flutter_slidable from UniversalBubble"
```

---

### Task 3: `ForumPostBubble` — migrate to `onReply`/`endActions`/`bubbleKey`

**Files:**
- Modify: `lib/features/forums/presentation/widgets/forum_post_bubble.dart`

**Interfaces:**
- Consumes: `UniversalBubble.onReply`/`endActions`/`bubbleKey` from Tasks 1-2.
- Produces: nothing for later tasks — this is the plan's final code task.

- [ ] **Step 1: Read the current full file**

Read `lib/features/forums/presentation/widgets/forum_post_bubble.dart` in
full (already read during planning — 508 lines) to confirm no drift.

- [ ] **Step 2: Remove the `flutter_slidable` import and rewrite the pane wiring**

Remove `import 'package:flutter_slidable/flutter_slidable.dart';`.

Replace the `startActionPane: !canReply ? null : ActionPane(...)` block
(the whole `DismissiblePane`/`SlidableAction` construction) with:

```dart
      onReply: canReply ? widget.onReply : null,
```

Replace the `endActionPane: ActionPane(motion: ..., extentRatio: 0.25,
children: [...])` block with:

```dart
      endActions: [
        if (!isMine)
          _EndPaneButton(
            icon: Icons.flag_outlined,
            label: 'Report',
            color: colorScheme.error,
            onPressed: _showReportDialog,
          ),
        if (isMine)
          _EndPaneButton(
            icon: Icons.delete_outline,
            label: 'Delete',
            color: colorScheme.error,
            onPressed: () async {
              if (await _confirmDeletePost(context)) {
                await deleteForumPost(
                  ref,
                  postId: post.id,
                  topicId: post.topicId,
                  side: post.side,
                );
              }
            },
          ),
      ],
```

Rename `slidableKey: ValueKey(post.id),` to `bubbleKey: ValueKey(post.id),`.

- [ ] **Step 3: Add the `_EndPaneButton` helper widget**

`SlidableAction` provided a fixed-size tappable button with an icon,
label, and background/foreground color out of the box — `endActions` just
takes raw widgets, so add a small private replacement at the bottom of the
file, styled to match the old `SlidableAction`'s appearance (background
fill, centered icon+label column, white/onError foreground):

```dart
class _EndPaneButton extends StatelessWidget {
  const _EndPaneButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 72,
      child: Material(
        color: color,
        child: InkWell(
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: colorScheme.onError, size: 20),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: TextStyle(color: colorScheme.onError, fontSize: 11),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

(This is a new widget, not a modification of `_SideBadge` — add it as a
sibling private class at the bottom of the file, near `_SideBadge`.)

- [ ] **Step 4: Run `dart analyze`**

Run: `dart analyze lib/features/forums/presentation/widgets/forum_post_bubble.dart`
Expected: `No issues found!`

- [ ] **Step 5: Confirm `flutter_slidable` is fully gone from this file**

Run: `grep -n "flutter_slidable\|Slidable\|ActionPane" lib/features/forums/presentation/widgets/forum_post_bubble.dart`
Expected: no output.

- [ ] **Step 6: Manually verify (no automated test file exists for this widget — confirmed during the message-actions feature's Task 4, same precedent applies here)**

This widget has zero existing widget-test coverage (confirmed absent
during a prior feature's planning). Do not add new test infrastructure for
it in this task — matches the established precedent of relying on static
analysis plus `UniversalBubble`'s own test suite (which now covers the
`endActions`/`onReply` contract this widget depends on) for this specific
file. Note this explicitly in your report as a deliberate scope call, not
an oversight.

- [ ] **Step 7: Run the forums test suite**

Run: `flutter test test/features/forums/`
Expected: PASS, no regressions (if this directory doesn't exist or is
empty, note that in your report — it would mean forums has no test
coverage at all today, consistent with Step 6's finding).

- [ ] **Step 8: Commit**

```bash
git add lib/features/forums/presentation/widgets/forum_post_bubble.dart
git commit -m "feat(forums): migrate ForumPostBubble to UniversalBubble's custom swipe gesture, remove flutter_slidable"
```

---

### Task 4: Full regression pass + `pubspec.yaml` note

**Files:** none (verification + one-line comment only)

**Interfaces:**
- Consumes: everything from Tasks 1-3.
- Produces: nothing — this is the plan's final verification task.

- [ ] **Step 1: Confirm `flutter_slidable` remains a dependency, used only by `comment_thread_screen.dart`**

Run: `grep -rln "flutter_slidable" lib --include="*.dart"`
Expected: exactly one file —
`lib/features/opinions/presentation/screen/comment_thread_screen.dart`. If
any other file still imports it, that's a gap this plan must close before
proceeding — go back and find what was missed.

- [ ] **Step 2: Run the full Flutter test suite**

Run: `flutter test`
Expected: PASS, matching the project's known pre-existing baseline (at
last count: `chat_couples_locked_screen_healing_entry_test.dart`'s 2
failures plus a further ~13 unrelated pre-existing failures in
`test/core/intro/`, `test/app/routing/feature_intro_route_wiring_test.dart`,
`test/features/settings/sound_toggle_widget_test.dart`,
`test/features/settings/chat_feel_section_widget_test.dart`,
`test/widget_test.dart`, `test/login_profile_test.dart` — confirm the
failing set is IDENTICAL to this list, not a superset. If any NEW test
fails, that's a regression this plan introduced — stop and fix it, don't
proceed to Step 3.

- [ ] **Step 3: Run `dart analyze` on the whole project**

Run: `dart analyze`
Expected: 0 errors. Compare the total issue count against a `git stash`
baseline if it seems meaningfully higher than before this plan's changes
— some new `info`-level lints from new code are expected and fine (e.g.
this plan's new `Transform`/`GestureDetector` code), but 0 errors is
non-negotiable.

- [ ] **Step 4: Manual smoke-test note**

This plan changes real interactive gesture behavior that automated widget
tests can exercise mechanically (drag-and-release) but cannot fully judge
for *feel* (does the rubber-band resistance feel right, does the reply
icon's fade/scale look smooth, does the haptic tick land at the right
moment). Since this is a UI/UX-sensitive change, note in your final report
that a human should manually test swipe-to-reply and swipe-to-reveal in a
running app (chat + forums) before considering this fully done — this is
explicitly a limitation of what this task's automated verification can
confirm, not a step to skip silently.

- [ ] **Step 5: No commit needed**

This task is verification-only. If Steps 1-3 all pass cleanly, nothing to
commit — report DONE with the verification results. If anything fails,
fix it as part of this task and commit the fix with a message describing
what regression was caught and corrected.

---

## Algorithm Quality Review Checklist v3.1 — scoping note

This feature is UI-only (`[MOBILE]`), no server surface, no data mutation
beyond calling existing callbacks (`onReply`, forum's existing
report/delete flows — both already implemented and already
checklist-reviewed in their own original features). No new checklist gate
applies beyond what's already implicit in "don't regress existing tested
behavior," which Task 4's full regression pass verifies directly.

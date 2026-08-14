import 'package:attune/core/widgets/universal_bubble.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
}

void main() {
  testWidgets('isMine=true aligns bubble to the right', (tester) async {
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

    final align = tester.widget<Align>(find.byType(Align).first);
    expect(align.alignment, Alignment.centerRight);
  });

  testWidgets('isMine=false aligns bubble to the left', (tester) async {
    await _pump(
      tester,
      UniversalBubble(
        isMine: false,
        bubbleColor: Colors.blue,
        onBubbleColor: Colors.white,
        content: const Text('hello'),
        footer: const SizedBox.shrink(),
      ),
    );

    final align = tester.widget<Align>(find.byType(Align).first);
    expect(align.alignment, Alignment.centerLeft);
  });

  testWidgets('renders content and footer', (tester) async {
    await _pump(
      tester,
      UniversalBubble(
        isMine: true,
        bubbleColor: Colors.blue,
        onBubbleColor: Colors.white,
        content: const Text('bubble content'),
        footer: const Text('footer content'),
      ),
    );

    expect(find.text('bubble content'), findsOneWidget);
    expect(find.text('footer content'), findsOneWidget);
  });

  testWidgets('quotedText renders a tappable preview block that calls onJumpToParent',
      (tester) async {
    var jumped = false;
    await _pump(
      tester,
      UniversalBubble(
        isMine: false,
        bubbleColor: Colors.blue,
        onBubbleColor: Colors.white,
        content: const Text('reply body'),
        footer: const SizedBox.shrink(),
        quotedText: 'the original message',
        onJumpToParent: () => jumped = true,
      ),
    );

    expect(find.text('the original message'), findsOneWidget);
    await tester.tap(find.text('the original message'));
    expect(jumped, isTrue);
  });

  testWidgets('no quotedText means no quote block rendered', (tester) async {
    await _pump(
      tester,
      UniversalBubble(
        isMine: false,
        bubbleColor: Colors.blue,
        onBubbleColor: Colors.white,
        content: const Text('plain message'),
        footer: const SizedBox.shrink(),
      ),
    );

    expect(find.byIcon(Icons.format_quote), findsNothing);
  });

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
    await gesture.moveBy(const Offset(70, 0));
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
    await gesture.moveBy(const Offset(40, 0));
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
    await gesture.moveBy(const Offset(70, 0));
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

  testWidgets(
      'onLongPress snapshot includes the quoted-text preview when the bubble has one',
      (tester) async {
    // The captured Rect is the real bubble fill's height, which INCLUDES
    // the quote block for a reply. A snapshot of content alone would be
    // painted shorter than its own reserved space in the overlay.
    Widget? capturedSnapshot;
    await _pump(
      tester,
      UniversalBubble(
        isMine: true,
        bubbleColor: Colors.blue,
        onBubbleColor: Colors.white,
        content: const Text('the reply body'),
        footer: const SizedBox.shrink(),
        quotedText: 'the original message',
        onLongPress: (rect, snapshot) => capturedSnapshot = snapshot,
      ),
    );

    await tester.longPress(find.text('the reply body'));
    await tester.pumpAndSettle();

    expect(capturedSnapshot, isNotNull);

    // Render the captured snapshot in isolation and confirm the quoted
    // text is actually present in it, not just in the live bubble behind
    // it.
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: capturedSnapshot!)),
    );

    expect(find.text('the original message'), findsOneWidget);
    expect(find.text('the reply body'), findsOneWidget);
  });

  testWidgets(
      'onLongPress snapshot has no quote block when the bubble has no quotedText',
      (tester) async {
    // The non-reply case must stay a true no-op: the same snapshot Task 2
    // already produced, with no quote chrome introduced by this fix.
    Widget? capturedSnapshot;
    await _pump(
      tester,
      UniversalBubble(
        isMine: true,
        bubbleColor: Colors.blue,
        onBubbleColor: Colors.white,
        content: const Text('a plain message'),
        footer: const SizedBox.shrink(),
        onLongPress: (rect, snapshot) => capturedSnapshot = snapshot,
      ),
    );

    await tester.longPress(find.text('a plain message'));
    await tester.pumpAndSettle();

    expect(capturedSnapshot, isNotNull);

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: capturedSnapshot!)),
    );

    expect(find.text('a plain message'), findsOneWidget);
    expect(find.byIcon(Icons.format_quote), findsNothing);
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

  testWidgets('dragging left past the reveal threshold and releasing leaves the end pane open',
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
    await gesture.moveBy(const Offset(-60, 0));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.text('Delete'), findsOneWidget);
    // The button must be laid out with a real, tappable size once revealed
    // — not clipped to zero width.
    final buttonSize = tester.getSize(find.text('Delete'));
    expect(buttonSize.width, greaterThan(0));
  });

  testWidgets('dragging left below the reveal threshold snaps the end pane back closed',
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
    await gesture.moveBy(const Offset(-20, 0));
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
    await gesture.moveBy(const Offset(-60, 0));
    await gesture.up();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(deleted, isTrue);
    // ...and the pane closed behind it, same as the pre-replacement
    // SlidableAction behavior.
    final transform = tester.widget<Transform>(
      find.ancestor(of: find.text('has end actions'), matching: find.byType(Transform)).first,
    );
    expect(transform.transform.getTranslation().x, 0);
  });

  testWidgets('a revealed end action stays tappable even on a short bubble',
      (tester) async {
    var fired = false;
    await _pump(
      tester,
      UniversalBubble(
        isMine: false,
        bubbleColor: Colors.blue,
        onBubbleColor: Colors.white,
        content: const Text('Yes'),
        footer: const SizedBox.shrink(),
        endActions: [
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: () => fired = true,
          ),
        ],
      ),
    );

    final center = tester.getCenter(find.text('Yes'));
    final gesture = await tester.startGesture(center);
    await gesture.moveBy(const Offset(-60, 0));
    await gesture.up();
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.delete));
    await tester.pumpAndSettle();

    expect(fired, isTrue);
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
    await gesture.moveBy(const Offset(-60, 0));
    await gesture.up();
    await tester.pumpAndSettle();
    // No assertion beyond "did not throw" — matches this widget's existing
    // null-disables convention.
  });

  testWidgets(
      'a bubble with both onReply and endActions set: reply swipe does not throw and fires correctly',
      (tester) async {
    // ForumPostBubble's REAL production shape — every other test in this
    // file sets one or the other, never both, which is exactly why the
    // negative-width SizedBox in the end pane survived four reviews.
    var replied = false;
    await _pump(
      tester,
      UniversalBubble(
        isMine: false,
        bubbleColor: Colors.blue,
        onBubbleColor: Colors.white,
        content: const Text('forums-shaped bubble'),
        footer: const SizedBox.shrink(),
        onReply: () => replied = true,
        endActions: [
          IconButton(icon: const Icon(Icons.flag), onPressed: () {}),
        ],
      ),
    );

    final center = tester.getCenter(find.text('forums-shaped bubble'));
    final gesture = await tester.startGesture(center);
    await gesture.moveBy(const Offset(70, 0));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(replied, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'a short bubble with endActions: opening then dragging right closes the pane',
      (tester) async {
    // The bubble is translated left by Transform when the pane is open, but
    // Transform moves paint only — the gesture detector's hit region has to
    // be reserved in layout or a drag started on the visible bubble misses
    // it entirely and the pane can never be dragged shut.
    await _pump(
      tester,
      UniversalBubble(
        isMine: false,
        bubbleColor: Colors.blue,
        onBubbleColor: Colors.white,
        content: const Text('Yes'),
        footer: const SizedBox.shrink(),
        endActions: [
          IconButton(icon: const Icon(Icons.delete), onPressed: () {}),
        ],
      ),
    );

    // Open the pane.
    var center = tester.getCenter(find.text('Yes'));
    var gesture = await tester.startGesture(center);
    await gesture.moveBy(const Offset(-60, 0));
    await gesture.up();
    await tester.pumpAndSettle();

    // Now drag right on the CURRENTLY VISIBLE (translated) bubble to close it.
    center = tester.getCenter(find.text('Yes'));
    gesture = await tester.startGesture(center);
    await gesture.moveBy(const Offset(60, 0));
    await gesture.up();
    await tester.pumpAndSettle();

    final transform = tester.widget<Transform>(
      find.ancestor(of: find.text('Yes'), matching: find.byType(Transform)).first,
    );
    expect(transform.transform.getTranslation().x, 0);
  });

  testWidgets(
      'a forums-shaped bubble returns to its exact original position after opening and closing the end pane',
      (tester) async {
    // The end-pane translation reserve is real layout width. If it is applied
    // unconditionally (rather than only while the pane is open or being
    // dragged), the bubble is permanently narrowed at rest — and because the
    // reserve tracks the measured reveal width, which is only measured on the
    // first gesture, the resting geometry silently jumps the first time the
    // bubble is ever touched.
    await _pump(
      tester,
      UniversalBubble(
        isMine: true,
        bubbleColor: Colors.blue,
        onBubbleColor: Colors.white,
        content: const Text('forums bubble'),
        footer: const SizedBox.shrink(),
        endActions: [
          IconButton(icon: const Icon(Icons.delete), onPressed: () {}),
        ],
      ),
    );

    final beforeRect = tester.getRect(find.text('forums bubble'));

    // Open then close the end pane.
    var center = tester.getCenter(find.text('forums bubble'));
    var gesture = await tester.startGesture(center);
    await gesture.moveBy(const Offset(-60, 0));
    await gesture.up();
    await tester.pumpAndSettle();

    center = tester.getCenter(find.text('forums bubble'));
    gesture = await tester.startGesture(center);
    await gesture.moveBy(const Offset(60, 0));
    await gesture.up();
    await tester.pumpAndSettle();

    final afterRect = tester.getRect(find.text('forums bubble'));
    expect(afterRect, equals(beforeRect));
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
    await gesture.moveBy(const Offset(-60, 0));
    await gesture.up();
    await tester.pumpAndSettle();

    // Open B — A should close as a side effect.
    center = tester.getCenter(find.text('bubble B'));
    gesture = await tester.startGesture(center);
    await gesture.moveBy(const Offset(-60, 0));
    await gesture.up();
    await tester.pumpAndSettle();

    final transformA = tester.widget<Transform>(
      find.ancestor(of: find.text('bubble A'), matching: find.byType(Transform)).first,
    );
    expect(transformA.transform.getTranslation().x, 0);

    // Reopening A must still close B — the registry entry B left behind
    // when it opened has to be live, not stale.
    center = tester.getCenter(find.text('bubble A'));
    gesture = await tester.startGesture(center);
    await gesture.moveBy(const Offset(-60, 0));
    await gesture.up();
    await tester.pumpAndSettle();

    final transformB = tester.widget<Transform>(
      find.ancestor(of: find.text('bubble B'), matching: find.byType(Transform)).first,
    );
    expect(transformB.transform.getTranslation().x, 0);
  });
}

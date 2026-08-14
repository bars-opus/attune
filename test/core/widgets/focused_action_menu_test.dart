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
                quickReactions: const [],
                onReact: (_) {},
                onOpenFullPicker: () {},
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
                quickReactions: const [],
                onReact: (_) {},
                onOpenFullPicker: () {},
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
                quickReactions: const [],
                onReact: (_) {},
                onOpenFullPicker: () {},
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
                quickReactions: const [],
                onReact: (_) {},
                onOpenFullPicker: () {},
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

  testWidgets(
      'the bubble scale animates mid-transition, not just at rest and settled',
      (tester) async {
    // Regression guard: showGeneralDialog's pageBuilder runs once per
    // route, not once per animation frame — a widget that reads
    // animation.value directly in a plain build() method (rather than
    // inside an AnimatedBuilder or similar) would silently freeze at
    // whatever value animation.value happened to be on that single
    // build, with every other test in this file (which all use
    // pumpAndSettle and only assert the FINAL state) unable to tell the
    // difference. Pumping a partial frame is the only way to prove the
    // animated properties actually move during the transition, not just
    // that they land on the right value once it's over.
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
                quickReactions: const [],
                onReact: (_) {},
                onOpenFullPicker: () {},
              ),
              child: const Text('trigger'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('trigger'));
    // First pump starts the route transition; a second pump partway
    // through the 220ms duration samples an in-flight frame.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 110));

    final transform = tester.widget<Transform>(
      find
          .ancestor(
            of: find.text('bubble snapshot'),
            matching: find.byType(Transform),
          )
          .first,
    );
    // storage[0] is the X-scale component of the transform matrix — 1.0
    // at rest, moving toward 1.05 as the transition progresses. Anything
    // greater than 1.0 here proves the animation is genuinely ticking,
    // not frozen at its initial (pre-animation) value.
    expect(transform.transform.storage[0], greaterThan(1.0));

    // Let the transition finish so the test doesn't leave a pending
    // timer/animation behind.
    await tester.pumpAndSettle();
  });

  testWidgets(
      'the anchor snapshot inherits normal text styling, not the no-Material debug fallback',
      (tester) async {
    // Regression guard: a Text with no Material ancestor falls back to
    // Flutter's debug-only style (fontFamily: 'monospace', fontSize: 48)
    // — tall enough to overflow a realistically-sized bubble rect. This
    // bug shipped undetected in this file's other four tests because none
    // of them asserted on the snapshot's rendered style, only its
    // presence (findsOneWidget) — and the hardcoded 60px-tall anchorRect
    // used elsewhere in this file happened to be generous enough to hide
    // the overflow. This test uses a REALISTIC bubble height (20px, a
    // single line of normal body text) specifically so the debug
    // fallback's 48px would overflow it if the Material wrapper regressed.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showFocusedActionMenu(
                context: context,
                anchorRect: const Rect.fromLTWH(20, 100, 200, 20),
                anchorSnapshot: const Text('bubble snapshot'),
                actions: [
                  ListTile(title: const Text('Action A'), onTap: () {}),
                ],
                quickReactions: const [],
                onReact: (_) {},
                onOpenFullPicker: () {},
              ),
              child: const Text('trigger'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('trigger'));
    await tester.pumpAndSettle();

    // No overflow exception — the debug fallback's 48px text would
    // overflow this 20px-tall rect and throw during layout.
    expect(tester.takeException(), isNull);

    final textWidget = tester.widget<Text>(find.text('bubble snapshot'));
    final resolvedStyle = DefaultTextStyle.of(
      tester.element(find.text('bubble snapshot')),
    ).style.merge(textWidget.style);

    // The debug fallback is specifically 48.0/monospace — anything
    // meaningfully smaller and non-monospace proves real DefaultTextStyle
    // inheritance is active, not the no-Material fallback.
    expect(resolvedStyle.fontFamily, isNot('monospace'));
    expect(resolvedStyle.fontSize ?? 14, lessThan(30));
  });

  testWidgets(
      'the menu stays within the screen width when the bubble sits near the right edge',
      (tester) async {
    // Regression guard: Positioned(left: anchorRect.left, ...) with no
    // clamping, combined with the menu's fixed 240px width, rendered up to
    // 94px (39%) off the right edge of a realistic 390-wide phone for a
    // short own-message bubble — the single most common message shape.
    // This anchorRect approximates that case: a short bubble's rect sitting
    // near the right edge of a 390-wide screen.
    tester.view.physicalSize = const Size(390, 844);
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
                anchorRect: const Rect.fromLTWH(244, 372, 100, 40),
                anchorSnapshot: const Text('ok'),
                actions: [
                  ListTile(title: const Text('Action A'), onTap: () {}),
                ],
                quickReactions: const [],
                onReact: (_) {},
                onOpenFullPicker: () {},
              ),
              child: const Text('trigger'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('trigger'));
    await tester.pumpAndSettle();

    final menuRenderBox = tester.renderObject<RenderBox>(
      find.byWidgetPredicate((w) => w is SizedBox && w.width == 240),
    );
    final menuRect = menuRenderBox.localToGlobal(Offset.zero) & menuRenderBox.size;

    expect(menuRect.left, greaterThanOrEqualTo(0));
    expect(menuRect.right, lessThanOrEqualTo(390));
    // Sanity: prove the fixture actually reproduces the pre-fix overflow
    // shape (anchorRect.left + 240 > 390) rather than accidentally fitting
    // on its own — if this fails, the fixture no longer exercises the bug.
    expect(244.0 + 240.0, greaterThan(390.0));
  });

  testWidgets('tapping a quick reaction calls onReact with that emoji and dismisses',
      (tester) async {
    String? reacted;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showFocusedActionMenu(
                context: context,
                anchorRect: const Rect.fromLTWH(20, 100, 200, 60),
                anchorSnapshot: const Text('bubble snapshot'),
                actions: [ListTile(title: const Text('Action A'), onTap: () {})],
                quickReactions: const [
                  ReactionQuickOption(emoji: '❤️'),
                  ReactionQuickOption(emoji: '👍'),
                ],
                onReact: (emoji) => reacted = emoji,
                onOpenFullPicker: () {},
              ),
              child: const Text('trigger'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('trigger'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('❤️'));
    await tester.pumpAndSettle();

    expect(reacted, '❤️');
    // Dismissed: the action list from this call is no longer in the tree.
    expect(find.text('Action A'), findsNothing);
  });

  testWidgets('each quick-reaction tap target meets the 44x44 accessibility minimum',
      (tester) async {
    // Algorithm Quality Review Checklist 5.6 (accessibility): a touch
    // target smaller than 44x44 logical pixels fails the minimum
    // tap-target size guideline. Found during Task 8's checklist
    // verification — the original 22px glyph + 6px padding sizing
    // measured ~34px, below the minimum.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showFocusedActionMenu(
                context: context,
                anchorRect: const Rect.fromLTWH(20, 100, 200, 60),
                anchorSnapshot: const Text('bubble snapshot'),
                actions: [ListTile(title: const Text('Action A'), onTap: () {})],
                quickReactions: const [
                  ReactionQuickOption(emoji: '❤️'),
                  ReactionQuickOption(emoji: '👍'),
                ],
                onReact: (_) {},
                onOpenFullPicker: () {},
              ),
              child: const Text('trigger'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('trigger'));
    await tester.pumpAndSettle();

    for (final target in [find.text('❤️'), find.text('👍'), find.byIcon(Icons.add)]) {
      final size = tester.getSize(
        find.ancestor(of: target, matching: find.byType(InkWell)),
      );
      expect(size.width, greaterThanOrEqualTo(44));
      expect(size.height, greaterThanOrEqualTo(44));
    }
  });

  testWidgets('tapping the "+" calls onOpenFullPicker and dismisses',
      (tester) async {
    var openedPicker = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showFocusedActionMenu(
                context: context,
                anchorRect: const Rect.fromLTWH(20, 100, 200, 60),
                anchorSnapshot: const Text('bubble snapshot'),
                actions: [ListTile(title: const Text('Action A'), onTap: () {})],
                quickReactions: const [ReactionQuickOption(emoji: '❤️')],
                onReact: (_) {},
                onOpenFullPicker: () => openedPicker = true,
              ),
              child: const Text('trigger'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('trigger'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    expect(openedPicker, isTrue);
  });

  testWidgets(
      'a full tapback row stays within the screen width near the right edge',
      (tester) async {
    // Regression guard: the reaction row is a SEPARATE card from the 240px
    // action list and is sized by its own content, so a realistic six-emoji
    // tapback set measures ~257px — wider than menuWidth. Clamping the
    // menu's left edge against menuWidth alone let the wider row hang ~8px
    // off the right edge of a 390-wide phone. The pre-existing right-edge
    // test above cannot catch this: it asserts on the 240px SizedBox (the
    // action list), not on the reaction row.
    tester.view.physicalSize = const Size(390, 844);
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
                anchorRect: const Rect.fromLTWH(244, 372, 100, 40),
                anchorSnapshot: const Text('ok'),
                actions: [ListTile(title: const Text('Action A'), onTap: () {})],
                quickReactions: const [
                  ReactionQuickOption(emoji: '❤️'),
                  ReactionQuickOption(emoji: '👍'),
                  ReactionQuickOption(emoji: '😂'),
                  ReactionQuickOption(emoji: '😮'),
                  ReactionQuickOption(emoji: '😢'),
                  ReactionQuickOption(emoji: '🙏'),
                ],
                onReact: (_) {},
                onOpenFullPicker: () {},
              ),
              child: const Text('trigger'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('trigger'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);

    final rowBox = tester.renderObject<RenderBox>(
      find
          .ancestor(
            of: find.byIcon(Icons.add),
            matching: find.byType(Material),
          )
          .first,
    );
    final rowRect = rowBox.localToGlobal(Offset.zero) & rowBox.size;

    expect(rowRect.left, greaterThanOrEqualTo(0));
    expect(rowRect.right, lessThanOrEqualTo(390));
    // Sanity: prove the fixture reproduces the overflow shape — the row is
    // genuinely wider than the 240px action list it is clamped alongside.
    expect(rowRect.width, greaterThan(240));
  });

  testWidgets('an over-long reaction row scrolls instead of overflowing',
      (tester) async {
    // The row's width is unbounded in its own right, so a caller passing an
    // unusually long emoji list must not paint off-screen or throw a layout
    // overflow — it is capped to the usable width and scrolls horizontally.
    tester.view.physicalSize = const Size(320, 700);
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
                anchorRect: const Rect.fromLTWH(200, 300, 100, 40),
                anchorSnapshot: const Text('ok'),
                actions: [ListTile(title: const Text('Action A'), onTap: () {})],
                quickReactions: List.generate(
                  20,
                  (_) => const ReactionQuickOption(emoji: '❤️'),
                ),
                onReact: (_) {},
                onOpenFullPicker: () {},
              ),
              child: const Text('trigger'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('trigger'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);

    final rowBox = tester.renderObject<RenderBox>(
      find
          .ancestor(
            of: find.byType(SingleChildScrollView),
            matching: find.byType(Material),
          )
          .first,
    );
    final rowRect = rowBox.localToGlobal(Offset.zero) & rowBox.size;

    expect(rowRect.left, greaterThanOrEqualTo(0));
    expect(rowRect.right, lessThanOrEqualTo(320));
  });
}

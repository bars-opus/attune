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

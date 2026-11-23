import 'package:attune/features/games/platform/feel/game_tile.dart';
import 'package:attune/features/games/platform/shell/game_buttons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/game_test_support.dart';

/// Every control here is hand-built from a GestureDetector, so nothing
/// gives it a screen-reader tap for free. Each one is checked the same
/// way: the node a screen reader lands on can be activated, and
/// activating it does what a finger does.
void main() {
  Future<void> pump(WidgetTester tester, Widget child) async {
    useSurface(tester, phone);
    await tester.pumpWidget(
      gameHost(Scaffold(body: Center(child: child)), prefs: await testPrefs()),
    );
  }

  void activate(WidgetTester tester, String label) {
    final node = tester.getSemantics(find.bySemanticsLabel(label));
    tester.binding.performSemanticsAction(
      SemanticsActionEvent(
        type: SemanticsAction.tap,
        viewId: tester.view.viewId,
        nodeId: node.id,
      ),
    );
  }

  testWidgets('a round button can be activated by a screen reader', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    var taps = 0;
    await pump(
      tester,
      GameRoundButton(
        icon: Icons.close_rounded,
        semanticLabel: 'Close',
        onTap: () => taps++,
      ),
    );

    expect(
      tester.getSemantics(find.bySemanticsLabel('Close')),
      matchesSemantics(
        label: 'Close',
        isButton: true,
        hasEnabledState: true,
        isEnabled: true,
        hasTapAction: true,
      ),
    );
    activate(tester, 'Close');
    expect(taps, 1);
    handle.dispose();
  });

  testWidgets('the primary button can be activated by a screen reader', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    var taps = 0;
    await pump(tester, GamePrimaryButton(label: 'Play', onTap: () => taps++));

    activate(tester, 'Play');
    expect(taps, 1);
    handle.dispose();
  });

  testWidgets('a disabled primary button says so and offers no tap', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pump(tester, const GamePrimaryButton(label: 'Waiting for Ama'));

    expect(
      tester.getSemantics(find.bySemanticsLabel('Waiting for Ama')),
      matchesSemantics(
        label: 'Waiting for Ama',
        isButton: true,
        hasEnabledState: true,
      ),
    );
    handle.dispose();
  });

  testWidgets('a busy primary button shows progress and takes no taps', (
    tester,
  ) async {
    // The progress ring turns for ever, so nothing here may pumpAndSettle.
    final handle = tester.ensureSemantics();
    var taps = 0;

    // The control: the same button, not busy, shows its icon and counts a
    // tap.
    await pump(
      tester,
      GamePrimaryButton(
        label: 'Play',
        icon: Icons.play_arrow_rounded,
        onTap: () => taps++,
      ),
    );
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.tap(find.text('Play'));
    expect(taps, 1);

    taps = 0;
    await pump(
      tester,
      GamePrimaryButton(
        label: 'Play',
        icon: Icons.play_arrow_rounded,
        busy: true,
        onTap: () => taps++,
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      find.byIcon(Icons.play_arrow_rounded),
      findsNothing,
      reason: 'the ring takes the icon\'s place',
    );
    expect(
      tester.getSize(find.byType(CircularProgressIndicator)),
      const Size(20, 20),
    );

    await tester.tap(find.text('Play'));
    expect(taps, 0);

    expect(
      tester.getSemantics(find.bySemanticsLabel('Play')),
      matchesSemantics(
        label: 'Play',
        isButton: true,
        hasEnabledState: true,
        isEnabled: false,
        hasTapAction: false,
      ),
    );
    expect(tester.hasRunningAnimations, isTrue, reason: 'the ring turns');

    // Under reduced motion the ring is still there, and still.
    await tester.pumpWidget(
      gameHost(
        Scaffold(
          body: Center(
            child: GamePrimaryButton(label: 'Play', busy: true, onTap: () {}),
          ),
        ),
        prefs: await testPrefs(),
        reduceMotion: true,
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(tester.hasRunningAnimations, isFalse);
    handle.dispose();
  });

  testWidgets('the secondary button can be activated by a screen reader', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    var taps = 0;
    await pump(
      tester,
      GameSecondaryButton(label: 'Back to games', onTap: () => taps++),
    );

    activate(tester, 'Back to games');
    expect(taps, 1);
    handle.dispose();
  });

  testWidgets('a labelled tile can be activated by a screen reader', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    var taps = 0;
    await pump(
      tester,
      GameTile(
        semanticLabel: 'Letter A',
        onTap: () => taps++,
        child: const Text('A'),
      ),
    );

    activate(tester, 'Letter A');
    expect(taps, 1);
    handle.dispose();
  });

  testWidgets('an unlabelled tile is read by its content, and still taps', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    var taps = 0;
    await pump(tester, GameTile(onTap: () => taps++, child: const Text('A')));

    expect(
      tester.getSemantics(find.bySemanticsLabel('A')),
      matchesSemantics(label: 'A', isButton: true, hasTapAction: true),
    );
    activate(tester, 'A');
    expect(taps, 1);
    handle.dispose();
  });
}

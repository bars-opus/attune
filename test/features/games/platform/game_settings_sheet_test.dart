import 'package:attune/features/games/platform/game_definition.dart';
import 'package:attune/features/games/platform/game_prefs.dart';
import 'package:attune/features/games/platform/shell/game_settings_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/demo_game.dart';
import 'support/game_test_support.dart';
import 'support/ink_on_ground.dart';

void main() {
  Future<void> open(
    WidgetTester tester, {
    GameDefinition? definition,
    VoidCallback? onHowToPlay,
    VoidCallback? onReportProblem,
    VoidCallback? onLeaveGame,
    Map<String, Object> stored = const {},
    double textScale = 1,
  }) async {
    useSurface(tester, phone);
    await tester.pumpWidget(
      gameHost(
        Scaffold(
          body: Builder(
            builder:
                (context) => TextButton(
                  onPressed:
                      () => showGameSettingsSheet(
                        context,
                        definition: definition ?? demoGame(),
                        onHowToPlay: onHowToPlay,
                        onReportProblem: onReportProblem,
                        onLeaveGame: onLeaveGame,
                      ),
                  child: const Text('open'),
                ),
          ),
        ),
        prefs: await testPrefs(stored),
        textScale: textScale,
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  GamePrefs prefsOf(WidgetTester tester) => ProviderScope.containerOf(
    tester.element(find.byType(GameSettingsSheet)),
  ).read(gamePrefsProvider);

  testWidgets('opened from above the game, in a light app, it is dark', (
    tester,
  ) async {
    // `open` calls it from a plain Scaffold, as a screen does from its own
    // build context in GameScaffold(onSettings: ...): no GameBackdrop above.
    await open(tester);

    expect(
      Theme.of(tester.element(find.text('open'))).brightness,
      Brightness.light,
      reason: 'the control: the app is light where the sheet was opened',
    );
    expect(
      Theme.of(tester.element(find.byType(GameSettingsSheet))).brightness,
      Brightness.dark,
    );
  });

  testWidgets('opens on General, with sound and vibration', (tester) async {
    await open(tester);

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Sound effects'), findsOneWidget);
    expect(find.text('Vibration'), findsOneWidget);
    expect(find.byType(Switch), findsNWidgets(2));
  });

  testWidgets('turning sound off is saved', (tester) async {
    await open(tester);
    expect(prefsOf(tester).sound, isTrue);

    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();

    expect(prefsOf(tester).sound, isFalse);
    expect(prefsOf(tester).haptics, isTrue);
  });

  testWidgets('turning vibration off is saved', (tester) async {
    await open(tester);

    await tester.tap(find.byType(Switch).last);
    await tester.pumpAndSettle();

    expect(prefsOf(tester).haptics, isFalse);
    expect(prefsOf(tester).sound, isTrue);
  });

  testWidgets('the switches show what was stored', (tester) async {
    await open(tester, stored: {GamePrefsNotifier.soundKey: false});

    final switches = tester.widgetList<Switch>(find.byType(Switch)).toList();
    expect(switches, hasLength(2));
    expect(switches.first.value, isFalse);
    expect(switches.last.value, isTrue);
  });

  testWidgets('a game with its own settings gets its own tab', (tester) async {
    await open(tester, definition: demoGame(withSettings: true));

    expect(find.bySemanticsLabel('Tile Tutorial'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Tile Tutorial'));
    await tester.pumpAndSettle();

    expect(find.text('Demo game settings'), findsOneWidget);
    expect(find.text('Sound effects'), findsNothing);
  });

  testWidgets('a game without settings has no tab for them', (tester) async {
    // The control is the test above, where the same lookup finds the tab.
    await open(tester);

    expect(find.bySemanticsLabel('Tile Tutorial'), findsNothing);
    expect(find.bySemanticsLabel('General'), findsOneWidget);
    expect(find.bySemanticsLabel('Support'), findsOneWidget);
  });

  testWidgets('Support offers only what the caller can act on', (tester) async {
    final taps = <String>[];
    await open(
      tester,
      onHowToPlay: () => taps.add('how'),
      onReportProblem: () => taps.add('report'),
      onLeaveGame: () => taps.add('leave'),
    );
    await tester.tap(find.bySemanticsLabel('Support'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('How to play'));
    await tester.tap(find.text('Report a problem'));
    await tester.tap(find.text('Leave game'));

    expect(taps, ['how', 'report', 'leave']);
  });

  testWidgets('there is no Leave game where no game is in progress', (
    tester,
  ) async {
    await open(tester, onHowToPlay: () {});
    await tester.tap(find.bySemanticsLabel('Support'));
    await tester.pumpAndSettle();

    expect(find.text('How to play'), findsOneWidget);
    expect(find.text('Leave game'), findsNothing);
    expect(find.text('Report a problem'), findsNothing);
  });

  testWidgets('a tab that is only partly showing comes fully into view when '
      'chosen', (tester) async {
    await open(
      tester,
      definition: demoGame(withSettings: true),
      onLeaveGame: () {},
    );
    final support = find.bySemanticsLabel('Support');
    expect(
      tester.getRect(support).left,
      greaterThan(phone.width),
      reason:
          'the control: three tabs do not fit, so Support starts off '
          'the edge',
    );

    // Pull the row until a sliver of Support shows, and tap the sliver.
    await tester.drag(find.bySemanticsLabel('General'), const Offset(-150, 0));
    await tester.pumpAndSettle();
    final sliver = tester.getRect(support);
    expect(sliver.left, lessThan(phone.width));
    expect(sliver.right, greaterThan(phone.width));
    await tester.tapAt(Offset(sliver.left + 12, sliver.center.dy));
    await tester.pumpAndSettle();

    expect(find.text('Leave game'), findsOneWidget);
    expect(tester.getRect(support).right, lessThanOrEqualTo(phone.width));
    expect(tester.getRect(support).left, greaterThanOrEqualTo(0));
  });

  testWidgets('a screen reader can change tab', (tester) async {
    final handle = tester.ensureSemantics();
    await open(tester, onLeaveGame: () {});

    final node = tester.getSemantics(find.bySemanticsLabel('Support'));
    tester.binding.performSemanticsAction(
      SemanticsActionEvent(
        type: SemanticsAction.tap,
        viewId: tester.view.viewId,
        nodeId: node.id,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Leave game'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('everything written on the sheet can be read there', (
    tester,
  ) async {
    await open(tester);

    final ink = inkOnGround(tester, of: find.byType(GameSettingsSheet));
    expect(
      ink.map((piece) => piece.text),
      containsAll(['Settings', 'General', 'Support', 'Sound effects']),
    );
    expect(
      ink.where((piece) => piece.contrast < 4.5).map((piece) => piece.text),
      isEmpty,
    );
  });

  testWidgets('the selected tab is announced as selected', (tester) async {
    final handle = tester.ensureSemantics();
    await open(tester);

    expect(
      tester.getSemantics(find.bySemanticsLabel('General')),
      matchesSemantics(
        label: 'General',
        isButton: true,
        isSelected: true,
        hasTapAction: true,
      ),
    );

    await tester.tap(find.bySemanticsLabel('Support'));
    await tester.pumpAndSettle();
    expect(
      tester.getSemantics(find.bySemanticsLabel('Support')),
      matchesSemantics(
        label: 'Support',
        isButton: true,
        isSelected: true,
        hasTapAction: true,
      ),
    );
    handle.dispose();
  });

  testWidgets('close dismisses the sheet', (tester) async {
    await open(tester);

    await tester.tap(find.bySemanticsLabel('Close'));
    await tester.pumpAndSettle();

    expect(find.byType(GameSettingsSheet), findsNothing);
  });

  testWidgets('the largest text size does not overflow', (tester) async {
    await open(
      tester,
      definition: demoGame(withSettings: true),
      onHowToPlay: () {},
      onReportProblem: () {},
      onLeaveGame: () {},
      textScale: 2,
    );
    expect(tester.takeException(), isNull);

    // At this size the tabs run well past the edge; the row scrolls.
    await tester.ensureVisible(find.bySemanticsLabel('Support'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Support'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // Every row is still reachable.
    await tester.scrollUntilVisible(
      find.text('Leave game'),
      100,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Leave game'), findsOneWidget);
  });
}

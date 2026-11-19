import 'package:attune/features/games/platform/game_theme.dart';
import 'package:attune/features/games/platform/shell/game_buttons.dart';
import 'package:attune/features/games/platform/shell/game_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/game_test_support.dart';
import 'support/ink_on_ground.dart';

void main() {
  const theme = GameTheme(primary: GameColors.wordHunt);

  testWidgets('shows the title over its subtitle', (tester) async {
    useSurface(tester, phone);
    await tester.pumpWidget(
      gameHost(
        const GameScaffold(
          theme: theme,
          title: 'Learn the Basics',
          subtitle: 'Word Hunt',
          body: SizedBox(),
        ),
        prefs: await testPrefs(),
      ),
    );

    expect(find.text('Learn the Basics'), findsOneWidget);
    expect(find.text('Word Hunt'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Word Hunt')).dy,
      lessThan(tester.getTopLeft(find.text('Learn the Basics')).dy),
    );
  });

  testWidgets('the header and an unstyled body are light on the ground', (
    tester,
  ) async {
    useSurface(tester, phone);
    await tester.pumpWidget(
      gameHost(
        const GameScaffold(
          theme: theme,
          title: 'Learn the Basics',
          subtitle: 'Word Hunt',
          body: Center(child: Text('a game that sets no colours')),
        ),
        prefs: await testPrefs(),
      ),
    );

    final ink = inkOnGround(tester, of: find.byType(GameScaffold));
    expect(
      ink.map((piece) => piece.text),
      contains('a game that sets no colours'),
    );
    expect(
      ink.where((piece) => piece.contrast < 4.5).map((piece) => piece.text),
      isEmpty,
    );
  });

  testWidgets('turning the phone keeps what the player was doing', (
    tester,
  ) async {
    useSurface(tester, phone);
    final prefs = await testPrefs();
    Widget host() => gameHost(
      const GameScaffold(
        theme: theme,
        title: 'Play',
        body: Center(child: _Counter()),
      ),
      prefs: prefs,
    );
    await tester.pumpWidget(host());
    await tester.tap(find.text('count 0'));
    await tester.pump();
    expect(find.text('count 1'), findsOneWidget);

    // On its side a phone is wider than the content column, so the
    // column's side margins appear. The body must survive that.
    tester.view.physicalSize = Size(phone.height, phone.width);
    await tester.pump();

    expect(find.text('count 1'), findsOneWidget);
  });

  testWidgets('the header is solid white and bold, the ink that reads on a '
      'game colour', (tester) async {
    // The header sits on the colour itself, not the ground. The theme test
    // holds white on every game colour to 3:1, which is the bar for bold
    // text -- so the header has to be bold, and must not be thinned out
    // with transparency.
    useSurface(tester, phone);
    await tester.pumpWidget(
      gameHost(
        const GameScaffold(
          theme: theme,
          title: 'Round 3 of 10',
          subtitle: 'Word Hunt',
          body: SizedBox(),
        ),
        prefs: await testPrefs(),
      ),
    );

    for (final words in ['Round 3 of 10', 'Word Hunt']) {
      final style =
          tester
              .widget<RichText>(
                find.descendant(
                  of: find.text(words),
                  matching: find.byType(RichText),
                ),
              )
              .text
              .style!;
      expect(style.color, GameTheme.onGround, reason: words);
      expect(
        style.fontWeight!.value,
        greaterThanOrEqualTo(FontWeight.w700.value),
        reason: words,
      );
    }
  });

  testWidgets('back and settings each report their own tap', (tester) async {
    useSurface(tester, phone);
    final taps = <String>[];
    await tester.pumpWidget(
      gameHost(
        GameScaffold(
          theme: theme,
          title: 'Play',
          body: const SizedBox(),
          onBack: () => taps.add('back'),
          onSettings: () => taps.add('settings'),
        ),
        prefs: await testPrefs(),
      ),
    );

    await tester.tap(find.bySemanticsLabel('Back'));
    await tester.tap(find.bySemanticsLabel('Settings'));

    expect(taps, ['back', 'settings']);
  });

  testWidgets('the gear only exists when there are settings to open', (
    tester,
  ) async {
    useSurface(tester, phone);
    final prefs = await testPrefs();

    await tester.pumpWidget(
      gameHost(
        const GameScaffold(theme: theme, title: 'Play', body: SizedBox()),
        prefs: prefs,
      ),
    );
    expect(find.bySemanticsLabel('Settings'), findsNothing);

    await tester.pumpWidget(
      gameHost(
        GameScaffold(
          theme: theme,
          title: 'Play',
          body: const SizedBox(),
          onSettings: () {},
        ),
        prefs: prefs,
      ),
    );
    expect(find.bySemanticsLabel('Settings'), findsOneWidget);
  });

  testWidgets('back leaves the screen when nothing else is asked of it', (
    tester,
  ) async {
    useSurface(tester, phone);
    await tester.pumpWidget(
      gameHost(
        Builder(
          builder:
              (context) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed:
                        () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder:
                                (_) => const GameScaffold(
                                  theme: theme,
                                  title: 'In the game',
                                  body: SizedBox(),
                                ),
                          ),
                        ),
                    child: const Text('open'),
                  ),
                ),
              ),
        ),
        prefs: await testPrefs(),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('In the game'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Back'));
    await tester.pumpAndSettle();
    expect(find.text('In the game'), findsNothing);
  });

  testWidgets('actions sit under the body', (tester) async {
    useSurface(tester, phone);
    await tester.pumpWidget(
      gameHost(
        GameScaffold(
          theme: theme,
          title: 'Play',
          body: const Center(child: Text('board')),
          actions: [
            GameRoundButton(
              icon: Icons.lightbulb_outline_rounded,
              semanticLabel: 'Hint',
              caption: 'Hint',
              onTap: () {},
            ),
          ],
        ),
        prefs: await testPrefs(),
      ),
    );

    expect(find.text('Hint'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Hint')).dy,
      greaterThan(tester.getCenter(find.text('board')).dy),
    );
  });

  testWidgets('the largest text size does not break the header', (
    tester,
  ) async {
    useSurface(tester, phone);
    await tester.pumpWidget(
      gameHost(
        GameScaffold(
          theme: theme,
          title: 'A game title long enough to need a second line',
          subtitle: 'A subtitle that is also rather long for a phone',
          body: const SizedBox(),
          onSettings: () {},
        ),
        prefs: await testPrefs(),
        textScale: 2,
      ),
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('the body is capped and centred on a tablet', (tester) async {
    useSurface(tester, tablet);
    await tester.pumpWidget(
      gameHost(
        const GameScaffold(
          theme: theme,
          title: 'Play',
          body: SizedBox.expand(key: ValueKey('body')),
        ),
        prefs: await testPrefs(),
      ),
    );

    final body = tester.getRect(find.byKey(const ValueKey('body')));
    expect(body.width, lessThan(tablet.width));
    expect(body.center.dx, closeTo(tablet.width / 2, 0.5));
  });
}

class _Counter extends StatefulWidget {
  const _Counter();

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int _count = 0;

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: () => setState(() => _count++),
    child: Text('count $_count'),
  );
}

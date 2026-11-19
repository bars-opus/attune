import 'package:attune/features/games/platform/game_theme.dart';
import 'package:attune/features/games/platform/shell/game_backdrop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/game_test_support.dart';

void main() {
  const theme = GameTheme(primary: GameColors.thisOrThat);

  testWidgets('inside a game, Material widgets are dark even in a light app', (
    tester,
  ) async {
    useSurface(tester, phone);
    late ThemeData outside;
    late ThemeData inside;
    await tester.pumpWidget(
      gameHost(
        // gameHost's app theme is light.
        Builder(
          builder: (context) {
            outside = Theme.of(context);
            return Scaffold(
              body: GameBackdrop(
                theme: theme,
                child: Builder(
                  builder: (context) {
                    inside = Theme.of(context);
                    return const TextField();
                  },
                ),
              ),
            );
          },
        ),
        prefs: await testPrefs(),
      ),
    );

    expect(outside.brightness, Brightness.light, reason: 'the control');
    expect(inside.brightness, Brightness.dark);
    expect(
      contrast(inside.colorScheme.onSurface, GameTheme.ground),
      greaterThanOrEqualTo(4.5),
    );
    expect(inside.textTheme.bodyMedium!.fontFamily, 'Roboto');
    expect(
      inside.textTheme.bodyMedium!.fontFamily,
      outside.textTheme.bodyMedium!.fontFamily,
      reason: 'the app font is kept',
    );
  });

  testWidgets('a dialog opened from inside a game is dark too', (tester) async {
    useSurface(tester, phone);
    BuildContext? dialogContext;
    await tester.pumpWidget(
      gameHost(
        Scaffold(
          body: GameBackdrop(
            theme: theme,
            child: Builder(
              builder:
                  (context) => Center(
                    child: TextButton(
                      onPressed:
                          () => showDialog<void>(
                            context: context,
                            builder: (context) {
                              dialogContext = context;
                              return const AlertDialog(content: Text('hello'));
                            },
                          ),
                      child: const Text('open'),
                    ),
                  ),
            ),
          ),
        ),
        prefs: await testPrefs(),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('hello'), findsOneWidget);
    expect(Theme.of(dialogContext!).brightness, Brightness.dark);
  });
}

import 'package:attune/app/theme/app_theme.dart';
import 'package:attune/app/theme/chat_color_scheme.dart';
import 'package:attune/features/games/presentation/providers/game_card_provider.dart';
import 'package:attune/features/games/presentation/widgets/game_message_bubble.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

const _state = GameCardState(
  status: 'active',
  gameType: 'snakes_and_ladders',
  currentTurnUserId: 'them',
  winnerUserId: null,
  currentRound: null,
  totalRounds: null,
  viewerAnswered: null,
  partnerAnswered: null,
);

void main() {
  Future<Color?> cardColour(
    WidgetTester tester, {
    required bool viewerIsSender,
    required bool dark,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gameCardProvider.overrideWith((ref, id) => Stream.value(_state)),
        ],
        child: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder:
              (context, _) => MaterialApp(
                theme: AppTheme.lightTheme,
                darkTheme: AppTheme.darkTheme,
                themeMode: dark ? ThemeMode.dark : ThemeMode.light,
                home: Scaffold(
                  body: GameMessageBubble(
                    sessionId: 's1',
                    viewerId: 'me',
                    viewerIsSender: viewerIsSender,
                    onTap: (_, __, ___) {},
                  ),
                ),
              ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final container = tester.widget<Container>(
      find
          .descendant(
            of: find.byType(GameMessageBubble),
            matching: find.byType(Container),
          )
          .first,
    );
    return (container.decoration as BoxDecoration?)?.color;
  }

  group('a game card is a chat bubble', () {
    testWidgets('a game you sent is the sender colour, not a neutral', (
      tester,
    ) async {
      // The bug this pins: the card painted one neutral grey on BOTH
      // sides, so your own invitation looked like your partner had sent
      // it -- the one thing a bubble's colour exists to say.
      final mine = await cardColour(tester, viewerIsSender: true, dark: false);
      expect(mine, ChatColorScheme.light.senderBubble);
    });

    testWidgets('a game they sent is the receiver colour', (tester) async {
      final theirs = await cardColour(
        tester,
        viewerIsSender: false,
        dark: false,
      );
      expect(theirs, ChatColorScheme.light.receiverBubble);
      expect(theirs, isNot(ChatColorScheme.light.senderBubble));
    });

    testWidgets('the two sides differ in dark mode too', (tester) async {
      final mine = await cardColour(tester, viewerIsSender: true, dark: true);
      final theirs = await cardColour(
        tester,
        viewerIsSender: false,
        dark: true,
      );
      expect(mine, ChatColorScheme.dark.senderBubble);
      expect(theirs, ChatColorScheme.dark.receiverBubble);
      expect(mine, isNot(theirs));
    });

    testWidgets('the sender bubble keeps dark ink in dark mode', (
      tester,
    ) async {
      // senderBubble is the SAME mint green in both themes, so its text
      // must be the same near-black in both. A theme-derived onSurface
      // would go white in dark mode and disappear.
      expect(
        ChatColorScheme.dark.onSenderBubble,
        ChatColorScheme.light.onSenderBubble,
      );
      expect(
        ChatColorScheme.dark.onSenderBubble.computeLuminance(),
        lessThan(0.2),
      );
    });
  });
}

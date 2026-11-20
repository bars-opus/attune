import 'dart:async';

import 'package:attune/core/ui/feedback/haptics.dart';
import 'package:attune/core/ui/feedback/sound_service.dart';
import 'package:attune/features/games/platform/feel/game_letter_tiles.dart';
import 'package:attune/features/games/platform/feel/game_tile.dart';
import 'package:attune/features/games/platform/game_prefs.dart';
import 'package:attune/features/games/platform/shell/game_buttons.dart';
import 'package:attune/features/games/platform/shell/game_complete_screen.dart';
import 'package:attune/features/games/presentation/providers/game_partner_name_provider.dart';
import 'package:attune/features/games/presentation/providers/game_session_live_provider.dart';
import 'package:attune/features/games/this_or_that/data/models/game_round.dart';
import 'package:attune/features/games/this_or_that/data/models/this_or_that_session.dart';
import 'package:attune/features/games/this_or_that/presentation/providers/this_or_that_providers.dart';
import 'package:attune/features/games/this_or_that/presentation/screens/end_screen.dart';
import 'package:attune/features/games/this_or_that/presentation/screens/this_or_that_session_router_screen.dart';
import 'package:attune/features/games/this_or_that/presentation/screens/waiting_screen.dart';
import 'package:attune/features/games/this_or_that/presentation/widgets/this_or_that_game_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import '../platform/support/game_test_support.dart';
import '../platform/support/route_recorder.dart';
import 'support/this_or_that_fakes.dart';

/// This or That's end, on the shell's completion screen, and where its
/// buttons lead.
void main() {
  setUpAll(loadGameTestFonts);

  const longPick = 'Stay in and cook something slow together';
  const pickTile = ValueKey('this-or-that-end-pick');

  Map<String, dynamic> pick({
    String question = 'Beach morning or city night?',
    String you = 'Beach morning',
    String partner = 'City night',
  }) => {
    'question_text': question,
    'answer_a': 'a',
    'answer_b': 'b',
    'answer_a_text': you,
    'answer_b_text': partner,
    'answer_a_emoji': '🌊',
    'answer_b_emoji': '🌃',
  };

  EndScreen end({
    Key? key,
    int matchCount = 7,
    int totalRounds = 10,
    Map<String, dynamic>? mostInterestingPick,
    VoidCallback? onPlayAgain,
    VoidCallback? onTryAnotherGame,
  }) => EndScreen(
    key: key,
    matchCount: matchCount,
    totalRounds: totalRounds,
    mostInterestingPick: mostInterestingPick ?? pick(),
    onPlayAgain: onPlayAgain ?? () {},
    onTryAnotherGame: onTryAnotherGame ?? () {},
  );

  Future<void> pumpEnd(
    WidgetTester tester,
    Widget screen, {
    String? partnerName = 'Ama',
    Size size = phone,
    FakeSoundService? sound,
    FakeHaptics? haptics,
    Map<String, Object> stored = const {},
  }) async {
    useSurface(tester, size);
    await tester.pumpWidget(
      gameHost(
        screen,
        prefs: await testPrefs(stored),
        sound: sound,
        haptics: haptics,
        reduceMotion: true,
        overrides: [
          gamePartnerNameProvider.overrideWith((ref) async => partnerName),
        ],
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Every piece of writing under [of], with the face it is drawn on: the
  /// nearest coloured box around it.
  List<({String text, double contrast})> inkOnFaces(
    WidgetTester tester, {
    required Finder of,
  }) {
    final found = <({String text, double contrast})>[];
    final texts = find.descendant(of: of, matching: find.byType(RichText));
    for (final element in texts.evaluate()) {
      final rich = element.widget as RichText;
      final text = rich.text.toPlainText();
      if (text.trim().isEmpty) continue;
      final isIcon = text.runes.every(
        (rune) => (rune >= 0xE000 && rune <= 0xF8FF) || rune >= 0xF0000,
      );
      if (isIcon) continue;
      Color? face;
      element.visitAncestorElements((ancestor) {
        final widget = ancestor.widget;
        if (widget is DecoratedBox &&
            widget.decoration is BoxDecoration &&
            (widget.decoration as BoxDecoration).color != null) {
          face = (widget.decoration as BoxDecoration).color;
          return false;
        }
        return true;
      });
      expect(face, isNotNull, reason: '"$text" is on no face');
      final ink = rich.text.style?.color ?? const Color(0xFF000000);
      found.add((
        text: text,
        contrast: contrast(Color.alphaBlend(ink, face!), face!),
      ));
    }
    return found;
  }

  group('the end screen', () {
    testWidgets('says the score in words and names the two players', (
      tester,
    ) async {
      await pumpEnd(tester, end(matchCount: 7, totalRounds: 10));

      expect(find.byType(GameCompleteScreen), findsOneWidget);
      expect(find.text('More alike than not'), findsOneWidget);
      expect(find.text('You matched on 7 of 10.'), findsOneWidget);
      expect(
        find.text(
          'A little alignment, a little discovery. Exactly the good stuff.',
        ),
        findsOneWidget,
      );
      expect(find.text('You & Ama'), findsOneWidget);
      // The ring is gone: the count is said, not drawn as a percentage.
      // Control: the score sentence above, found.
      expect(find.textContaining('%'), findsNothing);

      final tiles = find.descendant(
        of: find.byType(GameLetterTiles),
        matching: find.byType(GameTile),
      );
      expect(tiles, findsNWidgets(8));
      final letters = [
        for (final element in tiles.evaluate())
          tester
              .widget<Text>(
                find.descendant(
                  of: find.byWidget(element.widget),
                  matching: find.byType(Text),
                ),
              )
              .data,
      ];
      expect(letters.join(), 'COMPLETE');
    });

    testWidgets('every verdict keeps its words', (tester) async {
      await pumpEnd(tester, end(matchCount: 9));
      expect(find.text('Very much in sync'), findsOneWidget);
      expect(find.text('You matched on 9 of 10.'), findsOneWidget);
      expect(
        find.text('You found the same side 9 times. That deserves a rematch.'),
        findsOneWidget,
      );
    });

    testWidgets('a low score is still not a loss', (tester) async {
      await pumpEnd(tester, end(matchCount: 1));

      expect(find.text('Full of surprises'), findsOneWidget);
      expect(find.text('You matched on 1 of 10.'), findsOneWidget);
      expect(
        find.text(
          'Different answers are not misses. They are invitations to know '
          'each other better.',
        ),
        findsOneWidget,
      );
      // Control: the same kind of lookup finds a word that is there.
      expect(
        find.textContaining(RegExp('surprises', caseSensitive: false)),
        findsOneWidget,
      );
      for (final word in ['lost', 'failed', 'wrong', 'only']) {
        expect(
          find.textContaining(RegExp(word, caseSensitive: false)),
          findsNothing,
          reason: '"$word" is on a shared result',
        );
      }
    });

    testWidgets('the pick worth talking about is shown, on a tile', (
      tester,
    ) async {
      await pumpEnd(tester, end());

      expect(find.byKey(pickTile), findsOneWidget);
      expect(tester.widget(find.byKey(pickTile)), isA<GameTile>());
      for (final text in [
        'TALK ABOUT THIS ONE',
        'Beach morning or city night?',
        'YOU',
        'AMA',
        '🌊 Beach morning',
        '🌃 City night',
      ]) {
        expect(
          find.descendant(of: find.byKey(pickTile), matching: find.text(text)),
          findsOneWidget,
          reason: text,
        );
      }
    });

    testWidgets('with no pick there is no tile for one', (tester) async {
      // Control: the test above, where the same lookup finds it.
      await pumpEnd(tester, end(mostInterestingPick: const {}));

      expect(find.text('You matched on 7 of 10.'), findsOneWidget);
      expect(find.byKey(pickTile), findsNothing);
    });

    testWidgets('a partner whose name is not known is "your partner"', (
      tester,
    ) async {
      // Control: the two tests above, where Ama is named.
      await pumpEnd(tester, end(), partnerName: null);

      expect(find.text('You & your partner'), findsOneWidget);
      expect(find.text('YOUR PARTNER'), findsOneWidget);
      expect(find.textContaining('Partner'), findsNothing);
      expect(find.text('PARTNER'), findsNothing);
      expect(
        find.textContaining(RegExp('both of you', caseSensitive: false)),
        findsNothing,
      );
    });

    testWidgets('the buttons are the shell\'s pills and do what they say', (
      tester,
    ) async {
      final taps = <String>[];
      await pumpEnd(
        tester,
        end(
          onPlayAgain: () => taps.add('again'),
          onTryAnotherGame: () => taps.add('back'),
        ),
      );

      expect(
        find.widgetWithText(GamePrimaryButton, 'Play again'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(GameSecondaryButton, 'Back to games'),
        findsOneWidget,
      );
      await tester.tap(find.text('Play again'));
      await tester.tap(find.text('Back to games'));
      expect(taps, ['again', 'back']);
    });

    testWidgets('the win sound plays once', (tester) async {
      final sound = FakeSoundService();
      final haptics = FakeHaptics();
      await pumpEnd(tester, end(), sound: sound, haptics: haptics);

      expect(sound.played, [AppSound.gameComplete]);
      expect(haptics.mediumCount, 1);

      // A rebuild is not a second win.
      await tester.pumpWidget(
        gameHost(
          end(matchCount: 8),
          prefs: await testPrefs(),
          sound: sound,
          haptics: haptics,
          reduceMotion: true,
          overrides: [
            gamePartnerNameProvider.overrideWith((ref) async => 'Ama'),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('You matched on 8 of 10.'), findsOneWidget);
      expect(sound.played, [AppSound.gameComplete]);
      expect(haptics.mediumCount, 1);
    });

    testWidgets('with the games\' sound and vibration off, the end is quiet', (
      tester,
    ) async {
      // Control: the test above, where the same screen plays and buzzes.
      final sound = FakeSoundService();
      final haptics = FakeHaptics();
      await pumpEnd(
        tester,
        end(),
        sound: sound,
        haptics: haptics,
        stored: {
          GamePrefsNotifier.soundKey: false,
          GamePrefsNotifier.hapticsKey: false,
        },
      );

      expect(find.text('You matched on 7 of 10.'), findsOneWidget);
      expect(sound.played, isEmpty);
      expect(haptics.mediumCount, 0);
    });

    testWidgets('every word on its tiles can be read on its face', (
      tester,
    ) async {
      for (final matches in [7, 1]) {
        await pumpEnd(tester, end(key: ValueKey(matches), matchCount: matches));

        final onPick = inkOnFaces(tester, of: find.byKey(pickTile));
        expect(onPick, isNotEmpty);
        expect(
          onPick.map((piece) => piece.text),
          containsAll(['TALK ABOUT THIS ONE', 'YOU', 'AMA']),
        );
        final onLetters = inkOnFaces(tester, of: find.byType(GameLetterTiles));
        expect(onLetters, hasLength(8));
        expect(
          [...onPick, ...onLetters]
              .where((piece) => piece.contrast < 4.5)
              .map(
                (piece) =>
                    '${piece.text} (${piece.contrast.toStringAsFixed(2)})',
              ),
          isEmpty,
        );
      }
    });

    testWidgets('on the smallest phone, the verdict, the score and both '
        'buttons are in view without scrolling', (tester) async {
      const small = Size(320, 568);
      await pumpEnd(
        tester,
        end(
          matchCount: 3,
          mostInterestingPick: pick(
            question: 'A free Saturday with nothing planned: what do we do?',
            you: longPick,
            partner: longPick,
          ),
        ),
        partnerName: 'Kwame Mensah',
        size: small,
      );

      expect(tester.takeException(), isNull);
      expect(find.text('You & Kwame Mensah'), findsOneWidget);
      expect(find.text('KWAME MENSAH'), findsOneWidget);

      final body = find.descendant(
        of: find.byType(GameCompleteScreen),
        matching: find.byType(Scrollable),
      );
      expect(body, findsOneWidget);
      expect(tester.state<ScrollableState>(body).position.pixels, 0);

      final screen = Offset.zero & small;
      final again = tester.getRect(find.byType(GamePrimaryButton));
      final back = tester.getRect(find.byType(GameSecondaryButton));
      for (final button in [again, back]) {
        expect(screen.contains(button.topLeft), isTrue);
        expect(button.bottom, lessThanOrEqualTo(small.height));
        expect(button.right, lessThanOrEqualTo(small.width));
      }
      for (final text in ['Full of surprises', 'You matched on 3 of 10.']) {
        final rect = tester.getRect(find.text(text));
        expect(rect.top, greaterThanOrEqualTo(0), reason: text);
        expect(rect.bottom, lessThanOrEqualTo(again.top), reason: text);
      }
      // The long pick wraps rather than being cut short.
      for (final piece in tester.widgetList<Text>(
        find.descendant(
          of: find.byKey(pickTile),
          matching: find.textContaining(longPick),
        ),
      )) {
        expect(piece.maxLines, isNull);
        expect(piece.overflow, isNot(TextOverflow.ellipsis));
      }
    });
  });

  group('the router\'s end', () {
    late MockThisOrThatRepository repository;

    setUp(() {
      repository = MockThisOrThatRepository();
      createSessionAnswers(repository);
      when(() => repository.abandonSession(any())).thenAnswer((_) async {});
    });

    final rounds = [
      for (var i = 1; i <= 10; i++)
        GameRound(
          id: 'r$i',
          sessionId: 's1',
          roundNumber: i,
          answerA: 'a',
          answerB: i <= 7 ? 'a' : 'b',
          bothAnswered: true,
          questionText: 'Question $i?',
          optionA: 'This $i',
          optionB: 'That $i',
        ),
    ];

    List<Override> overrides(
      ThisOrThatSession? session, {
      String? relationshipId = 'rel-1',
    }) => [
      thisOrThatRepositoryProvider.overrideWithValue(repository),
      currentUserIdProvider.overrideWithValue('user-a'),
      currentRelationshipIdProvider.overrideWith((ref) async => relationshipId),
      sessionProvider.overrideWith((_, __) async => session),
      sessionRoundsProvider.overrideWith((_, __) async => rounds),
      partnerNameProvider.overrideWith((_) async => 'Ama'),
      gamePartnerNameProvider.overrideWith((_) async => 'Ama'),
      relationshipMembersProvider.overrideWith(
        (_, __) async => (userA: 'user-a', userB: 'user-b'),
      ),
      gameSessionLiveProvider.overrideWith(
        (_, __) => const Stream<void>.empty(),
      ),
    ];

    /// The router, pushed over a page that says where the player was.
    Future<void> pumpRouter(
      WidgetTester tester,
      ThisOrThatSession? session, {
      String? relationshipId = 'rel-1',
    }) async {
      useSurface(tester, phone);
      await tester.pumpWidget(
        gameRouterHost(
          home: Builder(
            builder:
                (context) => Scaffold(
                  body: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('came from here'),
                      TextButton(
                        onPressed: () => context.pushNamed('routerUnderTest'),
                        child: const Text('open the game'),
                      ),
                    ],
                  ),
                ),
          ),
          prefs: await testPrefs(),
          overrides: overrides(session, relationshipId: relationshipId),
          routes: [
            GoRoute(
              path: '/router-under-test',
              name: 'routerUnderTest',
              builder:
                  (context, state) => MediaQuery(
                    // Still: the waiting marks would never settle.
                    data: MediaQuery.of(
                      context,
                    ).copyWith(disableAnimations: true),
                    child: const ThisOrThatSessionRouterScreen(sessionId: 's1'),
                  ),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('open the game'));
      await tester.pumpAndSettle();
      // Control for every "came from here" below: it is out of sight now.
      expect(find.text('came from here'), findsNothing);
    }

    final finished = thisOrThatSession(
      tone: 'playful',
      status: 'completed',
      currentRound: 10,
    );

    testWidgets('a finished game ends on the completion screen', (
      tester,
    ) async {
      await pumpRouter(tester, finished);

      expect(find.byType(EndScreen), findsOneWidget);
      expect(find.text('You matched on 7 of 10.'), findsOneWidget);
      expect(find.text('You & Ama'), findsOneWidget);
    });

    testWidgets('Play again starts a new game in the same tone', (
      tester,
    ) async {
      await pumpRouter(tester, finished);

      await tester.tap(find.text('Play again'));
      await tester.pumpAndSettle();

      expect(createdTones(repository), ['playful']);
      expect(
        find.text('opened:thisOrThatSessionRouter:new-session'),
        findsOneWidget,
      );
      // It replaced the finished game: Back leads to where the player was.
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('came from here'), findsOneWidget);
    });

    testWidgets('Play again tapped twice starts one game', (tester) async {
      final creating = Completer<ThisOrThatSession>();
      when(
        () => repository.createSession(
          relationshipId: any(named: 'relationshipId'),
          initiatorId: any(named: 'initiatorId'),
          tone: any(named: 'tone'),
          idempotencyKey: any(named: 'idempotencyKey'),
        ),
      ).thenAnswer((_) => creating.future);
      await pumpRouter(tester, finished);

      await tester.tap(find.text('Play again'));
      await tester.pump();
      await tester.pump();
      await tester.tap(find.text('Play again'));
      await tester.pump();
      await tester.pump();

      expect(createdTones(repository), ['playful']);

      creating.complete(
        thisOrThatSession(
          id: 'new-session',
          tone: 'playful',
          status: 'invited',
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('opened:thisOrThatSessionRouter:new-session'),
        findsOneWidget,
      );
    });

    testWidgets('Play again that cannot start stays on the end', (
      tester,
    ) async {
      // Control: 'Play again starts a new game in the same tone'.
      await pumpRouter(tester, finished, relationshipId: null);

      await tester.tap(find.text('Play again'));
      await tester.pumpAndSettle();

      verifyNoSessionCreated(repository);
      expect(
        find.text('This game unlocks when a relationship is active.'),
        findsOneWidget,
      );
      expect(find.text('You matched on 7 of 10.'), findsOneWidget);
      expect(find.textContaining('opened:'), findsNothing);
    });

    testWidgets('Back to games returns to where the player came from', (
      tester,
    ) async {
      await pumpRouter(tester, finished);

      await tester.tap(find.text('Back to games'));
      await tester.pumpAndSettle();

      expect(find.text('came from here'), findsOneWidget);
      expect(find.textContaining('opened:'), findsNothing);
    });

    testWidgets('a game that is gone: Back to games returns there too', (
      tester,
    ) async {
      await pumpRouter(tester, null);
      expect(find.text('This game has ended'), findsOneWidget);

      await tester.tap(find.text('Back to games'));
      await tester.pumpAndSettle();

      expect(find.text('came from here'), findsOneWidget);
      expect(find.textContaining('opened:'), findsNothing);
    });

    testWidgets('an ended round: Back to games returns there too', (
      tester,
    ) async {
      await pumpRouter(tester, thisOrThatSession(status: 'abandoned'));
      expect(find.text('This round has ended'), findsOneWidget);

      await tester.tap(find.text('Back to games'));
      await tester.pumpAndSettle();

      expect(find.text('came from here'), findsOneWidget);
      expect(find.textContaining('opened:'), findsNothing);
    });

    testWidgets('a cancelled invitation is ended, then returns there', (
      tester,
    ) async {
      await pumpRouter(
        tester,
        thisOrThatSession(status: 'invited', currentRound: 1),
      );
      expect(find.text('Ama has the next move'), findsOneWidget);

      await tester.tap(find.text('Cancel invitation'));
      await tester.pumpAndSettle();

      verify(() => repository.abandonSession('s1')).called(1);
      expect(find.text('came from here'), findsOneWidget);
      expect(find.textContaining('opened:'), findsNothing);
    });
  });

  group('a partner whose name is not known', () {
    testWidgets('the nudge was sent to "your partner"', (tester) async {
      for (final (name, said) in [
        // The control: a real name reads as it always has.
        ('Ama', 'A gentle nudge was sent to Ama.'),
        ('Partner', 'A gentle nudge was sent to your partner.'),
      ]) {
        final repository = MockThisOrThatRepository();
        when(
          () => repository.sendReminder(any(), any()),
        ).thenAnswer((_) async => true);
        useSurface(tester, phone);
        await tester.pumpWidget(
          gameHost(
            WaitingScreen(
              key: ValueKey(name),
              sessionId: 'session-1',
              roundId: 'round-3',
              questionText: 'Friday night: stay in or go out?',
              userChoice: 'a',
              userChoiceText: 'Stay in',
              userChoiceEmoji: '🛋️',
              optionA: 'Stay in',
              optionB: 'Go out',
              roundNumber: 3,
              totalRounds: 10,
              isPartnerA: true,
              partnerName: name,
              answeredAt: DateTime.now().subtract(const Duration(hours: 3)),
            ),
            prefs: await testPrefs(),
            reduceMotion: true,
            overrides: [
              thisOrThatRepositoryProvider.overrideWithValue(repository),
              currentUserIdProvider.overrideWithValue('user-a'),
            ],
          ),
        );
        await tester.pumpAndSettle();

        final nudge = find.byWidgetPredicate(
          (widget) =>
              widget is GameSecondaryButton && widget.label.startsWith('Nudge'),
        );
        await tester.ensureVisible(nudge);
        await tester.tap(nudge);
        await tester.pump();
        await tester.pump();

        expect(find.text(said), findsOneWidget);
        expect(find.textContaining('to Partner'), findsNothing);
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 5));
      }
    });

    testWidgets('the question screen\'s presence says "Your partner"', (
      tester,
    ) async {
      for (final (name, answered, said) in [
        // The controls: a real name reads as it always has.
        ('Ama', false, 'Ama is choosing'),
        ('Ama', true, 'Ama picked'),
        ('Partner', false, 'Your partner is choosing'),
        ('Partner', true, 'Your partner picked'),
      ]) {
        useSurface(tester, phone);
        await tester.pumpWidget(
          gameHost(
            Scaffold(
              body: Center(
                child: ThisOrThatPartnerPresence(
                  key: ValueKey('$name $answered'),
                  partnerName: name,
                  answered: answered,
                ),
              ),
            ),
            prefs: await testPrefs(),
            reduceMotion: true,
          ),
        );
        await tester.pump();

        expect(find.text(said), findsOneWidget);
        expect(find.textContaining('Partner'), findsNothing);
      }
    });
  });
}

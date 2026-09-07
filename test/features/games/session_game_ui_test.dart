import 'package:attune/features/games/session_games/presentation/widgets/session_game_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('identity', () {
    testWidgets('each game gets its own accent', (tester) async {
      // Four games share this flow. Without distinct accents a player
      // moving between them cannot tell which one they are in, and the
      // shared components would flatten four games into one.
      const games = ['scenario', 'mirror', 'sliding_scale', 'love_map'];
      final seen = <Color>{};

      for (final game in games) {
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) {
                seen.add(SessionGamePalette.of(context, gameType: game).accent);
                return const SizedBox();
              },
            ),
          ),
        );
      }

      expect(
        seen.length,
        games.length,
        reason: 'two games share an accent, so one reads as the other',
      );
    });

    testWidgets('the accent reaches widgets never handed a game type', (
      tester,
    ) async {
      late Color scoped;
      await tester.pumpWidget(
        MaterialApp(
          home: SessionGameTypeScope(
            gameType: 'mirror',
            child: Builder(
              builder: (context) {
                scoped =
                    SessionGamePalette.of(
                      context,
                      gameType: SessionGameTypeScope.of(context),
                    ).accent;
                return const SizedBox();
              },
            ),
          ),
        ),
      );

      late Color direct;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              direct =
                  SessionGamePalette.of(context, gameType: 'mirror').accent;
              return const SizedBox();
            },
          ),
        ),
      );

      expect(scoped, direct);
    });
  });

  group('reveal', () {
    testWidgets('the two voices are visually distinct', (tester) async {
      // "You said" and "They said" in identical grey is a transcript. The
      // point of a reveal is two people, so they get different colours.
      late Color yours;
      late Color theirs;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              final palette = SessionGamePalette.of(context);
              yours = palette.yours;
              theirs = palette.theirs;
              return const SizedBox();
            },
          ),
        ),
      );

      expect(yours, isNot(theirs));
    });

    testWidgets('an empty answer is not rendered as one', (tester) async {
      // The reveal gate should make this unreachable, but a blank card
      // that looks like an answer would be worse than saying nothing.
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SessionGameAnswerCard(
              speaker: 'Them',
              answer: '',
              isYours: false,
            ),
          ),
        ),
      );

      expect(find.text('No answer recorded.'), findsOneWidget);
    });
  });

  group('options', () {
    testWidgets('no option is styled as the preferred one', (tester) async {
      // These games pose situations with no right answer. Privileging one
      // visually would turn a conversation starter into a test you can
      // fail -- so unselected options must be identical to each other.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                SessionGameOptionCard(text: 'A', index: 0, onTap: () {}),
                SessionGameOptionCard(text: 'B', index: 1, onTap: () {}),
                SessionGameOptionCard(text: 'C', index: 2, onTap: () {}),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final decorations =
          tester
              .widgetList<AnimatedContainer>(find.byType(AnimatedContainer))
              .map((widget) => widget.decoration as BoxDecoration)
              .toList();

      expect(decorations, hasLength(3));
      for (final decoration in decorations.skip(1)) {
        expect(
          decoration.color,
          decorations.first.color,
          reason: 'one option is tinted differently from its siblings',
        );
        expect(
          (decoration.border! as Border).top.width,
          (decorations.first.border! as Border).top.width,
          reason: 'one option is outlined more heavily than its siblings',
        );
      }
    });
  });

  group('motion', () {
    testWidgets('a question arrives rather than being already there', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SessionGameQuestionCard(text: 'What would you do?'),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 120));
      expect(
        tester
            .widget<FadeTransition>(find.byType(FadeTransition).first)
            .opacity
            .value,
        lessThan(1.0),
      );

      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FadeTransition>(find.byType(FadeTransition).first)
            .opacity
            .value,
        1.0,
      );
    });

    testWidgets('reduce motion shows the question immediately', (tester) async {
      await tester.pumpWidget(
        const MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: MaterialApp(
            home: Scaffold(
              body: SessionGameQuestionCard(text: 'What would you do?'),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(
        tester
            .widget<FadeTransition>(find.byType(FadeTransition).first)
            .opacity
            .value,
        1.0,
      );
    });
  });

  group('waiting', () {
    testWidgets('waiting breathes rather than spinning', (tester) async {
      // A spinner says "something is loading and may be stuck". This wait
      // is on a person who may answer in an hour, and the difference is
      // the whole feeling of the screen -- one invites anxiety, the other
      // patience.
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Center(child: SessionGameWaitingMark())),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('reduce motion stops it rather than hanging', (tester) async {
      await tester.pumpWidget(
        const MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: MaterialApp(
            home: Scaffold(body: Center(child: SessionGameWaitingMark())),
          ),
        ),
      );
      await tester.pump();

      // pumpAndSettle would never return on a repeating animation, so
      // completing at all is the assertion.
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}

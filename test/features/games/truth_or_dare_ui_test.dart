import 'dart:io';

import 'package:attune/features/games/truth_or_dare/presentation/widgets/truth_or_dare_game_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('tone', () {
    testWidgets('every server-side tone gets its own colour', (tester) async {
      // An unhandled tone falls through to the playful green, which would
      // quietly tell an Intimate session it was something lighter. The
      // server accepts five, so all five must be distinct.
      const tones = ['connecting', 'romantic', 'playful', 'spicy', 'intimate'];
      final seen = <Color>{};

      for (final tone in tones) {
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) {
                seen.add(TruthOrDarePalette.of(context, tone: tone).toneAccent);
                return const SizedBox();
              },
            ),
          ),
        );
      }

      expect(
        seen.length,
        tones.length,
        reason: 'two tones share a colour, so one of them reads as the other',
      );
    });

    testWidgets('tone reaches widgets that were never handed it', (
      tester,
    ) async {
      // Passing tone down by parameter meant any widget that forgot to
      // forward it rendered a Playful glow inside a Spicy session.
      late Color inner;

      await tester.pumpWidget(
        MaterialApp(
          home: TruthOrDareScaffold(
            tone: 'spicy',
            child: Builder(
              builder: (context) {
                inner = TruthOrDarePalette.of(context).toneAccent;
                return const SizedBox();
              },
            ),
          ),
        ),
      );

      late Color spicy;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              spicy = TruthOrDarePalette.of(context, tone: 'spicy').toneAccent;
              return const SizedBox();
            },
          ),
        ),
      );

      expect(inner, spicy);
    });
  });

  group('write path', () {
    test('no screen writes an answer column directly', () {
      // THE BUG THIS GUARDS. Both reveal screens updated the round row
      // from the client and set the PARTNER's answer column to a
      // '__revealed__' sentinel -- so whoever answered second destroyed
      // what the first person had said, in a game whose whole point is
      // hearing them.
      //
      // Answers now go through submit_truth_or_dare_answer, which derives
      // the column from auth.uid() and cannot touch the other one.
      for (final path in [
        'lib/features/games/truth_or_dare/presentation/screens/'
            'truth_reveal_screen.dart',
        'lib/features/games/truth_or_dare/presentation/screens/'
            'dare_reveal_screen.dart',
      ]) {
        final source = File(path).readAsStringSync();

        expect(
          source.contains("'__revealed__'"),
          isFalse,
          reason: '$path writes the reveal sentinel into an answer column',
        );
        expect(
          source.contains('submit_truth_or_dare_answer'),
          isTrue,
          reason: '$path does not submit through the server-side RPC',
        );
      }
    });
  });

  group('reduce motion', () {
    testWidgets('the waiting mark stops rather than spinning', (tester) async {
      await tester.pumpWidget(
        const MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: MaterialApp(
            home: Scaffold(body: Center(child: TruthOrDareWaitingMark())),
          ),
        ),
      );
      await tester.pump();

      // pumpAndSettle would hang forever on a repeating animation, so
      // completing at all is the assertion.
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('sound', () {
    test('truth and dare are sounded differently', () {
      // The flip landing is the most dramatic moment in the game. One
      // sound for both verdicts wastes it -- a player should know which
      // they got before the text resolves.
      final source =
          File(
            'lib/features/games/truth_or_dare/presentation/screens/'
            'card_flip_screen.dart',
          ).readAsStringSync();

      expect(source.contains('AppSound.gameTruth'), isTrue);
      expect(source.contains('AppSound.gameDare'), isTrue);
    });

    test('the end of a session is not silent', () {
      final source =
          File(
            'lib/features/games/truth_or_dare/presentation/screens/'
            'truth_or_dare_end_screen.dart',
          ).readAsStringSync();

      expect(
        source.contains('AppSound.gameComplete'),
        isTrue,
        reason: 'a finished game must sound finished',
      );
    });

    test('every Truth or Dare sound has a file behind it', () {
      // A missing asset fails silently at runtime, so the game would
      // simply lose a beat with nothing to show for it.
      for (final name in ['game_truth', 'game_dare', 'game_answer']) {
        expect(
          File('assets/sounds/$name.wav').existsSync(),
          isTrue,
          reason: '$name.wav is referenced but not generated',
        );
      }
    });
  });

  group('motion', () {
    testWidgets('a prompt arrives rather than being already there', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: TruthOrDarePromptCard(
              kind: 'truth',
              prompt: 'What made you laugh today?',
            ),
          ),
        ),
      );

      // Part-way through the entrance it is still fading in.
      await tester.pump(const Duration(milliseconds: 120));
      final mid = tester.widget<FadeTransition>(
        find.byType(FadeTransition).first,
      );
      expect(
        mid.opacity.value,
        lessThan(1.0),
        reason: 'the card is already fully present, so it never arrived',
      );

      await tester.pumpAndSettle();
      final settled = tester.widget<FadeTransition>(
        find.byType(FadeTransition).first,
      );
      expect(settled.opacity.value, 1.0);
    });

    testWidgets('reduce motion shows the prompt immediately', (tester) async {
      await tester.pumpWidget(
        const MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: MaterialApp(
            home: Scaffold(
              body: TruthOrDarePromptCard(
                kind: 'dare',
                prompt: 'Send a voice note.',
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final fade = tester.widget<FadeTransition>(
        find.byType(FadeTransition).first,
      );
      expect(
        fade.opacity.value,
        1.0,
        reason: 'reduce motion must not mean waiting for a fade',
      );
    });
  });
}

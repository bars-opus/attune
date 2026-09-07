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
}

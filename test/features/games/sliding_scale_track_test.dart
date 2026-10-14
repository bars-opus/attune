import 'dart:ui';

import 'package:attune/core/ui/neon/neon_quality.dart';
import 'package:attune/features/games/session_games/data/models/session_game_question.dart';
import 'package:attune/features/games/sliding_scale/presentation/screens/sliding_scale_question_screen.dart';
import 'package:attune/features/games/sliding_scale/presentation/widgets/sliding_scale_track.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records draw calls so the track's geometry is assertable without a
/// golden, the same idiom the Paint Ball painters use.
class _RecordingCanvas implements Canvas {
  final paths = <Path>[];
  final circles = <({Offset centre, double radius})>[];

  @override
  void drawPath(Path path, Paint paint) => paths.add(path);

  @override
  void drawCircle(Offset c, double radius, Paint paint) =>
      circles.add((centre: c, radius: radius));

  @override
  noSuchMethod(Invocation invocation) => null;
}

void main() {
  const low = Color(0xFF6FE3C8);
  const high = Color(0xFF2C7FB8);

  group('where a value sits on the scale', () {
    test('the ends are the ends', () {
      expect(slidingScaleFraction(1), 0);
      expect(slidingScaleFraction(10), 1);
    });

    test('the middle is the middle', () {
      // 5 of 1-10 is slightly below centre, which is correct: there is
      // no exact midpoint on an even-length scale, and rounding it to
      // 0.5 would misreport the answer.
      expect(slidingScaleFraction(5), closeTo(4 / 9, 0.001));
      expect(slidingScaleFraction(5.5), closeTo(0.5, 0.001));
    });

    test('out-of-range values clamp rather than running off the track', () {
      // The Slider's divisions keep real input inside 1-10, but a value
      // restored from a stale answer could be anything.
      expect(slidingScaleFraction(0), 0);
      expect(slidingScaleFraction(-50), 0);
      expect(slidingScaleFraction(11), 1);
      expect(slidingScaleFraction(1000), 1);
    });

    test('a NaN reads as the low end, not as a crash', () {
      expect(slidingScaleFraction(double.nan), 0);
    });

    test('a degenerate range does not divide by zero', () {
      expect(slidingScaleFraction(5, min: 3, max: 3), 0);
      expect(slidingScaleFraction(5, min: 9, max: 2), 0);
    });
  });

  group('what the track draws', () {
    _RecordingCanvas render(
      double fraction, {
      NeonQuality quality = NeonQuality.rich,
      Size size = const Size(300, 48),
    }) {
      final canvas = _RecordingCanvas();
      SlidingScaleTrackPainter(
        fraction: fraction,
        lowColor: low,
        highColor: high,
        quality: quality,
      ).paint(canvas, size);
      return canvas;
    }

    test('the full span is always drawn', () {
      // The unclaimed part of the spectrum has to stay visible, or the
      // player cannot see how far there is left to go.
      final canvas = render(0);

      expect(canvas.paths, isNotEmpty, reason: 'a positive control');
    });

    test('the lit portion grows with the answer', () {
      // The mark's position IS the answer, so this is the assertion the
      // whole widget exists for.
      final lowEnd = render(0).circles.first.centre.dx;
      final middle = render(0.5).circles.first.centre.dx;
      final highEnd = render(1).circles.first.centre.dx;

      expect(lowEnd, lessThan(middle));
      expect(middle, lessThan(highEnd));
    });

    test('nothing is drawn outside the track', () {
      // A mark that ran past the inset would sit outside the span it is
      // supposed to be measuring.
      const size = Size(300, 48);
      for (final f in [0.0, 0.5, 1.0]) {
        final mark = render(f, size: size).circles.first.centre;
        expect(mark.dx, inInclusiveRange(0, size.width), reason: 'at $f');
        expect(mark.dy, closeTo(size.height / 2, 0.01), reason: 'at $f');
      }
    });

    test('a zero-sized track does not throw', () {
      expect(() => render(0.5, size: Size.zero), returnsNormally);
    });

    test('a track narrower than its own inset does not throw', () {
      // Reachable mid-layout, and the guard is a real one: without it
      // `right <= left` would produce a backwards span.
      expect(() => render(0.5, size: const Size(4, 48)), returnsNormally);
    });

    test('the plain tier drops the mark’s halo but keeps the mark', () {
      // §6.10's launch gate. Degrading removes decoration, never the
      // answer -- a track whose mark vanished on a cheap device would
      // make the game unplayable there.
      final rich = render(0.5);
      final plain = render(0.5, quality: NeonQuality.plain);

      expect(rich.circles.length, greaterThan(plain.circles.length));
      expect(
        plain.circles,
        isNotEmpty,
        reason: 'the answer itself survives every tier',
      );
    });
  });

  group('the question screen', () {
    SessionGameQuestion question() => const SessionGameQuestion(
      id: 'q1',
      gameType: 'sliding_scale',
      questionText: 'How much do you need time alone to recharge?',
      scaleLow: 'Not at all',
      scaleHigh: 'Completely',
    );

    testWidgets('it shows the spectrum, not just a slider', (tester) async {
      // The point of this task: Sliding Scale is literally a gradient
      // and shipped without one. It is also the neon toolkit's second
      // consumer, which is what proves the toolkit generalises.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SlidingScaleQuestionScreen(
              question: question(),
              onSubmit: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(SlidingScaleTrack), findsOneWidget);
      expect(find.text('Not at all'), findsOneWidget);
      expect(find.text('Completely'), findsOneWidget);
    });

    testWidgets('the slider remains the input, and submits its value', (
      tester,
    ) async {
      // The Slider is kept deliberately: it carries keyboard traversal,
      // screen-reader semantics and drag handling, and its divisions are
      // what keep the answer inside the 1-10 the server accepts.
      String? submitted;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SlidingScaleQuestionScreen(
              question: question(),
              onSubmit: (value) => submitted = value,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(Slider), findsOneWidget);

      await tester.tap(find.byType(FilledButton));
      await tester.pump();

      expect(submitted, '5', reason: 'the default answer is the midpoint');
    });

    testWidgets('moving the slider moves the drawn mark', (tester) async {
      // Without this the track could be painting a constant and every
      // other test here would still pass.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SlidingScaleQuestionScreen(
              question: question(),
              onSubmit: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      double fraction() =>
          tester.widget<SlidingScaleTrack>(find.byType(SlidingScaleTrack))
              .fraction;

      final before = fraction();

      await tester.drag(find.byType(Slider), const Offset(200, 0));
      await tester.pumpAndSettle();

      expect(
        fraction(),
        greaterThan(before),
        reason: 'the drawn spectrum follows the answer',
      );
    });
  });
}

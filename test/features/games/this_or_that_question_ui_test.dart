import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final source =
      File(
        'lib/features/games/this_or_that/presentation/screens/'
        'question_screen.dart',
      ).readAsStringSync();

  test('the round shows progress', () {
    // roundNumber and totalRounds were passed in and never rendered, so
    // every round of a ten-round game looked identical to the last.
    expect(source.contains('LinearProgressIndicator'), isTrue);
    expect(
      source.contains(r"'${widget.roundNumber} of ${widget.totalRounds}'"),
      isTrue,
      reason: 'the count must be readable, not only a bar',
    );
  });

  test('waiting on a partner breathes', () {
    // "Partner has not answered yet" was a grey caption under a button --
    // the most emotionally live fact on the screen rendered as the least
    // alive thing on it.
    expect(source.contains('BreathingDots'), isTrue);
    expect(
      source.contains('Partner has not answered yet'),
      isFalse,
      reason: 'replaced by the live indicator',
    );
  });

  test('the two choices are visually distinct before selection', () {
    // A game about contrast opened as two identical grey boxes: both
    // cards used the same neutral surface until one was picked.
    expect(source.contains('_warmTint'), isTrue);
    expect(source.contains('_coolTint'), isTrue);
    expect(
      source.contains('isWarm: true'),
      isTrue,
      reason: 'the sides must be told apart by the caller',
    );
    expect(
      source.contains(
        'colorScheme.surfaceContainerHighest.withOpacity(0.3)',
      ),
      isFalse,
      reason: 'the shared neutral surface is what made them identical',
    );
  });
}

import 'package:attune/features/games/platform/game_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/game_test_support.dart';

void main() {
  test('the backdrop runs from the colour down to the ground', () {
    const theme = GameTheme(primary: GameColors.wordHunt);
    final gradient = theme.backdrop;

    expect(gradient.colors.first, theme.primary);
    expect(gradient.colors.last, GameTheme.ground);
    expect(gradient.begin, Alignment.topCenter);
    expect(gradient.end, Alignment.bottomCenter);
  });

  test('the ground is reached by a little past halfway', () {
    // Body text and lists live on the lower half. If the colour ran
    // further down, they would be sitting on it.
    const theme = GameTheme(primary: GameColors.thisOrThat);

    expect(theme.backdrop.stops!.last, lessThanOrEqualTo(0.6));
    expect(theme.backdrop.stops!.last, greaterThan(0.4));
  });

  test('the five launch colours are five different colours', () {
    expect(GameColors.all, hasLength(5));
    expect(GameColors.all.toSet(), hasLength(5));
  });

  test('white titles stay readable on every game colour', () {
    // 3:1 is the bar for large bold text, which is all that sits on the
    // colour. A retune that drops below it makes a header unreadable.
    for (final colour in GameColors.all) {
      expect(
        contrast(GameTheme.onGround, colour),
        greaterThanOrEqualTo(3.0),
        reason: 'white on $colour',
      );
    }
  });

  test('body text is comfortably readable on the ground', () {
    expect(
      contrast(GameTheme.mutedOnGround, GameTheme.ground),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      contrast(GameTheme.mutedOnGround, GameTheme.raised),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      contrast(GameTheme.tileInk, GameTheme.tile),
      greaterThanOrEqualTo(7.0),
    );
  });
}

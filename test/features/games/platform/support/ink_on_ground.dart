import 'package:attune/features/games/platform/feel/game_tile.dart';
import 'package:attune/features/games/platform/game_theme.dart';
import 'package:attune/features/games/platform/shell/game_buttons.dart';
import 'package:attune/features/games/platform/shell/game_hub_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'game_test_support.dart';

/// What is written directly on the dark ground under [of], and how well
/// each piece can be read there.
///
/// Words on a white tile or the white Play button are left out: those are
/// meant to be dark. So are a hub card's, which sit on the game's colour and
/// are checked against it. Everything else has to be light, and a golden is
/// the only other thing that would notice if it were not.
List<({String text, double contrast})> inkOnGround(
  WidgetTester tester, {
  required Finder of,
}) {
  final found = <({String text, double contrast})>[];
  final texts = find.descendant(of: of, matching: find.byType(RichText));
  for (final element in texts.evaluate()) {
    var onLightSurface = false;
    element.visitAncestorElements((ancestor) {
      final widget = ancestor.widget;
      if (widget is GameTile ||
          widget is GamePrimaryButton ||
          widget is GameHubCard) {
        onLightSurface = true;
        return false;
      }
      return true;
    });
    if (onLightSurface) continue;

    final rich = element.widget as RichText;
    final text = rich.text.toPlainText();
    if (text.trim().isEmpty) continue;
    // Icons are RichText too, drawn with private-use glyphs. They sit on
    // surfaces of their own (a white disc, a tinted button), so the ground
    // is not what they are read against.
    final isIcon = text.runes.every(
      (rune) => (rune >= 0xE000 && rune <= 0xF8FF) || rune >= 0xF0000,
    );
    if (isIcon) continue;
    final color = rich.text.style?.color ?? const Color(0xFF000000);
    // Translucent ink is judged as it lands on the ground, not as if it
    // were solid: white at half strength is grey, and reads like grey.
    final asDrawn = Color.alphaBlend(color, GameTheme.ground);
    found.add((text: text, contrast: contrast(asDrawn, GameTheme.ground)));
  }
  return found;
}

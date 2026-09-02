import 'dart:io';
import 'dart:math' as math;

import 'package:attune/app/theme/chat_color_scheme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double _luminance(Color c) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) +
      0.7152 * channel(c.g) +
      0.0722 * channel(c.b);
}

double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  // The album label ("4 photos" and its grid icon) sits on the WALLPAPER,
  // not inside a bubble: a media group draws a transparent bubble so the
  // images show through. Its colour therefore has to read against the
  // wallpaper, not against a bubble fill.
  //
  // onSenderBubble is a near-black green designed for the pale mint sender
  // bubble. Against the dark wallpaper it is ~1:1 -- invisible. This test
  // exists because that is not something the eye catches while working in
  // light mode, which is where such a change gets made.
  const light = ChatColorScheme.light;
  const dark = ChatColorScheme.dark;

  test('both on-bubble colours read on the light wallpaper', () {
    for (final colour in [light.onSenderBubble, light.onReceiverBubble]) {
      expect(
        _contrast(colour, light.background),
        greaterThanOrEqualTo(3.0),
        reason: 'the album label must be legible on the light wallpaper',
      );
    }
  });

  test('dark mode must not use the sender on-colour for the label', () {
    expect(
      _contrast(dark.onSenderBubble, dark.background),
      lessThan(1.5),
      reason:
          'near-black on near-black; if this ever rises the guard can be '
          'revisited, but while it holds the label must avoid this colour',
    );

    expect(
      _contrast(dark.onReceiverBubble, dark.background),
      greaterThanOrEqualTo(3.0),
      reason: 'the colour dark mode does use must read on the wallpaper',
    );
  });

  test('the bubble wires the label to a colour that reads in both themes', () {
    // The theme checks above prove which colours are safe; this proves the
    // widget actually picks them. It used to pass metadataColor -- flat
    // black/white chosen for the FOOTER after the footer moved out onto
    // the wallpaper. The label was left pointing at that value and never
    // followed it.
    final source =
        File(
          'lib/features/chat/presentation/widgets/message_bubble.dart',
        ).readAsStringSync();

    expect(
      source.contains('mediaLabelColor: metadataColor'),
      isFalse,
      reason: 'the album label is not footer chrome; it heads a bubble',
    );
    expect(
      source.contains('chatColors.onReceiverBubble'),
      isTrue,
      reason: 'dark mode needs the receiver on-colour for both sides',
    );
  });
}

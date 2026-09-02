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
  // The album label ("4 photos" and its grid icon) is carried on a pill
  // filled with the BUBBLE's colour, so the album reads as part of the
  // message rather than as chrome floating on the wallpaper.
  //
  // A fill rather than coloured text, because a media group draws a
  // transparent bubble so the images show through -- the label sits
  // directly on the wallpaper, and the sender bubble is a pale mint that
  // is close to invisible as text there.
  const light = ChatColorScheme.light;
  const dark = ChatColorScheme.dark;

  test('the label text reads against the pill it sits on', () {
    // 3:1 is the threshold that applies: this is bold ~15px text, which
    // WCAG treats as large.
    final cases = <String, List<Color>>{
      'light / mine': [light.onSenderBubble, light.senderBubble],
      'light / theirs': [light.onReceiverBubble, light.receiverBubble],
      'dark / mine': [dark.onSenderBubble, dark.senderBubble],
      'dark / theirs': [dark.onReceiverBubble, dark.receiverBubble],
    };

    cases.forEach((name, pair) {
      expect(
        _contrast(pair[0], pair[1]),
        greaterThanOrEqualTo(3.0),
        reason: '$name: the album label must read on its own pill',
      );
    });
  });

  test('the pill needs its shadow to separate from the wallpaper', () {
    // Bubble colours sit deliberately close to the wallpaper -- the
    // sender's mint measures ~1.04:1 against it -- so a filled pill alone
    // would read as a flat patch. Real bubbles carry a faint shadow for
    // exactly this reason, and the pill copies it.
    //
    // Pinned as a fact about the palette: if these ever diverge enough to
    // stand alone, the shadow becomes optional rather than load-bearing.
    expect(
      _contrast(light.senderBubble, light.background),
      lessThan(1.5),
      reason: 'while this holds, the pill cannot rely on fill alone',
    );

    // Scoped to the PILL's own decoration: the file also draws stacked
    // back-cards with their own boxShadow, so a whole-file search passes
    // even with the pill's shadow deleted.
    final source =
        File(
          'lib/features/chat/presentation/widgets/chat_media_group.dart',
        ).readAsStringSync();
    final pillStart = source.indexOf('color: widget.bubbleColor,');
    expect(pillStart, greaterThan(-1), reason: 'the pill fill is missing');
    final pillDecoration = source.substring(
      pillStart,
      source.indexOf('),', source.indexOf('child: Padding(', pillStart)),
    );
    expect(
      pillDecoration.contains('boxShadow'),
      isTrue,
      reason: 'the pill must carry the same lift a bubble does',
    );
  });

  test('the pill is filled with the bubble colour, not the text colour', () {
    final source =
        File(
          'lib/features/chat/presentation/widgets/chat_media_group.dart',
        ).readAsStringSync();

    expect(
      source.contains('color: widget.bubbleColor,\n                  borderRadius'),
      isTrue,
      reason: 'the pill fill is what makes the label match the bubble',
    );
  });

  test('the bubble stops passing the footer colour', () {
    // It used to be metadataColor -- flat black/white, chosen for the
    // FOOTER after the footer moved out onto the wallpaper. The label was
    // left pointing at that value and never followed it.
    final source =
        File(
          'lib/features/chat/presentation/widgets/message_bubble.dart',
        ).readAsStringSync();

    expect(source.contains('mediaLabelColor: metadataColor'), isFalse);
    expect(source.contains('mediaLabelColor: onBubbleColor'), isTrue);
  });
}

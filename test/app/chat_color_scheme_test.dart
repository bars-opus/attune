import 'dart:math' as math;

import 'package:attune/app/theme/app_theme.dart';
import 'package:attune/app/theme/chat_color_scheme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('app themes register their semantic chat palettes', () {
    expect(AppTheme.lightTheme.chatColors, same(ChatColorScheme.light));
    expect(AppTheme.darkTheme.chatColors, same(ChatColorScheme.dark));
  });

  test('bubble foreground pairs meet WCAG AA contrast', () {
    for (final palette in [ChatColorScheme.light, ChatColorScheme.dark]) {
      expect(
        _contrastRatio(palette.onSenderBubble, palette.senderBubble),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        _contrastRatio(palette.onReceiverBubble, palette.receiverBubble),
        greaterThanOrEqualTo(4.5),
      );
    }
  });
}

double _contrastRatio(Color foreground, Color background) {
  final foregroundLuminance = _relativeLuminance(foreground);
  final backgroundLuminance = _relativeLuminance(background);
  final high = math.max(foregroundLuminance, backgroundLuminance);
  final low = math.min(foregroundLuminance, backgroundLuminance);
  return (high + 0.05) / (low + 0.05);
}

double _relativeLuminance(Color color) {
  double linearize(double channel) {
    return channel <= 0.04045
        ? channel / 12.92
        : math.pow((channel + 0.055) / 1.055, 2.4).toDouble();
  }

  return 0.2126 * linearize(color.r) +
      0.7152 * linearize(color.g) +
      0.0722 * linearize(color.b);
}

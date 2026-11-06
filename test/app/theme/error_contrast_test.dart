// Spec 1 W10a (owner question 3): the light theme's error colour reads at
// least 4.5:1 with its onError text and as text on the light surfaces
// (WCAG 1.4.3). The dark theme's pair is checked too, unchanged.
import 'package:attune/app/theme/app_colors.dart';
import 'package:attune/app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  final light = AppTheme.lightTheme.colorScheme;
  final dark = AppTheme.darkTheme.colorScheme;

  for (final (name, a, b) in [
    ('light error with onError', light.error, light.onError),
    ('light error on the surface', light.error, light.surface),
    ('light error on the background', light.error, LightColors.background),
    ('dark error with onError', dark.error, dark.onError),
  ]) {
    test('$name: at least 4.5:1', () {
      final ratio = _contrast(a, b);
      expect(
        ratio,
        greaterThanOrEqualTo(4.5),
        reason: '$name: ${ratio.toStringAsFixed(2)}',
      );
    });
  }
}

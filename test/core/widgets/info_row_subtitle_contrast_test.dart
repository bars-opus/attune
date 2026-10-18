// Spec 5 (R5-13, plan review I6): InfoRowWidget's default subtitle reaches
// WCAG AA (4.5:1) on the light and dark surfaces it sits on.
import 'dart:math' as math;

import 'package:attune/app/theme/app_theme.dart';
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/widgets/info_row_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

double _lum(Color c) {
  double ch(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double _contrast(Color fg, Color bg) {
  final a = _lum(Color.alphaBlend(fg, bg)), b = _lum(bg);
  return (math.max(a, b) + 0.05) / (math.min(a, b) + 0.05);
}

void main() {
  for (final (name, theme) in [('light', AppTheme.lightTheme), ('dark', AppTheme.darkTheme)]) {
    test('$name: the secondary-text alpha reaches 4.5:1', () {
      final s = theme.colorScheme;
      for (final bg in [s.surface, s.surfaceContainerLow, s.surfaceContainer]) {
        final ratio = _contrast(s.onSurface.withValues(alpha: OpacityTokens.secondaryText), bg);
        expect(ratio, greaterThanOrEqualTo(4.5), reason: '$name on $bg: $ratio');
      }
    });
  }

  testWidgets('the subtitle uses it by default', (t) async {
    await t.pumpWidget(ScreenUtilInit(
      designSize: const Size(390, 844),
      builder: (_, __) => MaterialApp(
        theme: AppTheme.lightTheme,
        home: const Scaffold(body: InfoRowWidget(title: 'T', subtitle: 'S', icon: Icons.info)),
      ),
    ));
    final text = t.widget<Text>(find.text('S'));
    expect(text.style?.color?.a, closeTo(OpacityTokens.secondaryText, 0.01));
  });
}

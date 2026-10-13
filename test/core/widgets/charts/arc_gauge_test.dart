import 'package:attune/core/widgets/charts/arc_gauge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ArcGauge', () {
    testWidgets('fills to the fraction, says what is left, and turns to the error colour when over', (tester) async {
      Widget gauge(double fraction, {bool over = false}) => MaterialApp(
            home: Scaffold(
              body: ArcGauge(
                fraction: fraction,
                over: over,
                headline: over ? 'GHS10 over' : 'GHS70 left',
                caption: 'of GHS100',
                semanticLabel: 'Budget',
              ),
            ),
          );
      await tester.pumpWidget(gauge(0.3));
      await tester.pumpAndSettle();
      expect(find.text('GHS70 left'), findsOneWidget);
      expect(find.text('of GHS100'), findsOneWidget);
      expect(tester.state<ArcGaugeState>(find.byType(ArcGauge)).shown, moreOrLessEquals(0.3));

      await tester.pumpWidget(gauge(1.0, over: true));
      await tester.pumpAndSettle();
      expect(find.text('GHS10 over'), findsOneWidget);
      final painter = tester.widget<CustomPaint>(
          find.descendant(of: find.byType(ArcGauge), matching: find.byType(CustomPaint)).first).painter! as ArcGaugePainter;
      expect(painter.fill, Theme.of(tester.element(find.byType(ArcGauge))).colorScheme.error);
    });

    test('the fraction is clamped to the arc', () {
      expect(ArcGauge.clampFraction(-1), 0);
      expect(ArcGauge.clampFraction(1.7), 1);
      expect(ArcGauge.clampFraction(double.nan), 0);
    });
  });
}

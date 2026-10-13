import 'package:attune/core/widgets/charts/rose_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('topSlices', () {
    test('past the limit, the smallest are gathered into Other', () {
      final s = topSlices({for (var i = 1; i <= 10; i++) 'x$i': i.toDouble()}, limit: 8);
      expect(s, hasLength(8));
      expect(s.last.key, 'Other');
      expect(s.last.value, 1 + 2 + 3);
    });
  });

  RosePainter painter(WidgetTester tester) => tester
      .widget<CustomPaint>(find.descendant(of: find.byType(RoseChart), matching: find.byType(CustomPaint)).first)
      .painter! as RosePainter;

  Widget chart({bool reduce = false}) => MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduce),
          child: const Scaffold(
            body: Center(
              child: RoseChart(semanticLabel: 'Spending', slices: [
                RoseSlice(label: 'Hotel', valueLabel: 'GHS4K', value: 4000, color: Colors.indigo, textColor: Colors.white),
                RoseSlice(label: 'Taxi', valueLabel: 'GHS15', value: 15, color: Colors.indigoAccent, textColor: Colors.indigo),
                RoseSlice(label: 'Food', valueLabel: 'GHS80', value: 80, color: Colors.grey, textColor: Colors.black),
              ]),
            ),
          ),
        ),
      );

  testWidgets('every wedge is the same full height, whatever its amount: a complete circle', (tester) async {
    await tester.pumpWidget(chart());
    await tester.pumpAndSettle();
    expect(painter(tester).reach, [1.0, 1.0, 1.0]);
  });

  testWidgets('one solid colour per wedge as given, and described for screen readers', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(chart());
    await tester.pumpAndSettle();
    expect([for (final s in painter(tester).slices) s.color], [Colors.indigo, Colors.indigoAccent, Colors.grey]);
    expect(find.bySemanticsLabel(RegExp(r'Spending.*Hotel GHS4K.*Taxi GHS15.*Food GHS80')), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('it grows in, unless motion is reduced', (tester) async {
    await tester.pumpWidget(chart());
    expect(tester.state<RoseChartState>(find.byType(RoseChart)).progress, lessThan(1));
    await tester.pumpAndSettle();
    expect(tester.state<RoseChartState>(find.byType(RoseChart)).progress, 1);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(chart(reduce: true));
    expect(tester.state<RoseChartState>(find.byType(RoseChart)).progress, 1);
  });
}

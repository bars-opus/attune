import 'package:attune/core/widgets/charts/app_pie_chart.dart';
import 'package:fl_chart/fl_chart.dart';
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

  const slices = [
    PieSlice(label: 'Shopping', valueLabel: r'$4K', value: 4000, color: Colors.green, textColor: Colors.white),
    PieSlice(label: 'Left in budget', valueLabel: r'$648', value: 648, color: Colors.grey, textColor: Colors.black),
    PieSlice(label: 'Shoes', valueLabel: r'$32', value: 32, color: Colors.lightGreen, textColor: Colors.green),
  ];

  Widget app({bool reduce = false}) => MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduce),
          child: const Scaffold(body: Center(child: AppPieChart(semanticLabel: 'Spending', slices: slices))),
        ),
      );

  PieChart pie(WidgetTester tester) => tester.widget<PieChart>(find.byType(PieChart));

  testWidgets("a standard pie: each slice its share, in its own colour, starting at the top", (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    final data = pie(tester).data;
    expect([for (final s in data.sections) s.value], [4000, 648, 32]);
    expect([for (final s in data.sections) s.color], [Colors.green, Colors.grey, Colors.lightGreen]);
    expect(data.centerSpaceRadius, 0, reason: 'a full pie, no hole');
    expect(data.startDegreeOffset, -90);
  });

  testWidgets('slices of 8% or more carry their amount and name; smaller ones stay unlabelled', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    final sections = pie(tester).data.sections;
    expect(sections[0].showTitle, isTrue);
    expect(sections[0].title, '\$4K\nShopping');
    expect(sections[1].showTitle, isTrue, reason: '648 is 14% of the whole');
    expect(sections[2].showTitle, isFalse, reason: '32 is under 1%');
    expect(sections[0].titleStyle?.color, Colors.white);
  });

  testWidgets('described for screen readers', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel(RegExp(r'Spending.*Shopping \$4K.*Left in budget \$648.*Shoes \$32')), findsOneWidget);
    semantics.dispose();
  });

  // Like the budget gauge: it sweeps in clockwise from the top over 700ms.
  AppPieChartState state(WidgetTester tester) => tester.state<AppPieChartState>(find.byType(AppPieChart));

  testWidgets('it sweeps in from the top when it first shows', (tester) async {
    await tester.pumpWidget(app());
    expect(state(tester).revealed, 0, reason: 'nothing drawn on the first frame');
    await tester.pump(const Duration(milliseconds: 200));
    expect(state(tester).revealed, inExclusiveRange(0, 1), reason: 'part way round');
    await tester.pump(const Duration(milliseconds: 600));
    expect(state(tester).revealed, 1, reason: 'the whole pie after 700ms');
    expect(find.byKey(const ValueKey('app-pie-chart-sweep')), findsNothing, reason: 'no clip once it is all there');
  });

  testWidgets('with reduce motion it is all there at once', (tester) async {
    await tester.pumpWidget(app(reduce: true));
    expect(state(tester).revealed, 1);
  });

  testWidgets('new numbers do not sweep it in again', (tester) async {
    Widget chart(List<PieSlice> s) => MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(),
            child: Scaffold(body: Center(child: AppPieChart(semanticLabel: 'Spending', slices: s))),
          ),
        );
    await tester.pumpWidget(chart(slices));
    await tester.pumpAndSettle();
    await tester.pumpWidget(chart([
      ...slices,
      const PieSlice(label: 'Hats', valueLabel: r'$90', value: 90, color: Colors.teal, textColor: Colors.white),
    ]));
    expect(state(tester).revealed, 1, reason: 'the slices change in place');
    expect(pie(tester).data.sections, hasLength(4));
  });

  testWidgets('changes animate, unless motion is reduced', (tester) async {
    await tester.pumpWidget(app());
    expect(pie(tester).duration, greaterThan(Duration.zero));
    await tester.pumpWidget(app(reduce: true));
    expect(pie(tester).duration, Duration.zero);
  });
}

// Spec 1 W10a: the large-text helpers are inert at the normal text size
// (the same layout, no extra scroll view) and fix the overflow once the
// phone's text is scaled up.
import 'package:attune/core/ui/text/large_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester t, Widget child, double scale) async {
  await t.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: const Size(390, 844),
          textScaler: TextScaler.linear(scale),
        ),
        child: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: 200, height: 120, child: child),
          ),
        ),
      ),
    ),
  );
}

Widget _tallColumn() => const Column(
  mainAxisAlignment: MainAxisAlignment.center,
  children: [
    Text('Nothing here yet', key: ValueKey('title')),
    Spacer(),
    Text('Add your first plan to get started', key: ValueKey('body')),
  ],
);

Widget _wideRow() => const Row(
  mainAxisSize: MainAxisSize.min,
  children: [Text('12 days to go', key: ValueKey('count'))],
);

Rect _rect(WidgetTester t, String key) => t.getRect(find.byKey(ValueKey(key)));

void main() {
  testWidgets('isTextScaledUp is false at 1.0 and true above it', (t) async {
    Future<bool> scaledUpAt(double scale) async {
      late bool scaledUp;
      await t.pumpWidget(
        MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: Builder(
            builder: (context) {
              scaledUp = isTextScaledUp(context);
              return const SizedBox();
            },
          ),
        ),
      );
      return scaledUp;
    }

    expect(await scaledUpAt(1.0), isFalse);
    expect(await scaledUpAt(1.05), isTrue);
  });

  testWidgets('ScrollWhenTall: the same layout and no scroll view at 1.0', (
    t,
  ) async {
    await _pump(t, _tallColumn(), 1.0);
    final title = _rect(t, 'title');
    final body = _rect(t, 'body');
    await _pump(t, ScrollWhenTall(child: _tallColumn()), 1.0);
    expect(_rect(t, 'title'), title);
    expect(_rect(t, 'body'), body);
    expect(find.byType(SingleChildScrollView), findsNothing);
  });

  testWidgets('ScrollWhenTall: scrolls instead of overflowing at 2.0', (
    t,
  ) async {
    await _pump(t, _tallColumn(), 2.0);
    expect(t.takeException(), isA<FlutterError>(), reason: 'the bug');
    await _pump(t, ScrollWhenTall(child: _tallColumn()), 2.0);
    expect(t.takeException(), isNull);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
  });

  testWidgets('ScaleDownToFit: the same size at 1.0, fits at 2.0', (t) async {
    await _pump(t, _wideRow(), 1.0);
    final count = _rect(t, 'count');
    await _pump(t, ScaleDownToFit(child: _wideRow()), 1.0);
    expect(_rect(t, 'count'), count);
    expect(find.byType(FittedBox), findsNothing);
    await _pump(
      t,
      const SizedBox(
        width: 60,
        child: ScaleDownToFit(child: Text('12 days to go')),
      ),
      2.0,
    );
    expect(t.takeException(), isNull);
    expect(find.byType(FittedBox), findsOneWidget);
  });

  testWidgets('ScrollWhenScaledUp: nothing at 1.0, a scroll view above', (
    t,
  ) async {
    const sheet = Column(
      mainAxisSize: MainAxisSize.min,
      children: [Text('Report this opinion'), Text('Spam')],
    );
    await _pump(t, const ScrollWhenScaledUp(child: sheet), 1.0);
    expect(find.byType(SingleChildScrollView), findsNothing);
    await _pump(t, const ScrollWhenScaledUp(child: sheet), 1.3);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
  });

  testWidgets('ScrollsInPlaceUnlessScaledUp: Expanded scroll at 1.0, in '
      'place once the column scrolls', (t) async {
    Widget column() => ScrollWhenTall(
      child: Column(
        children: [
          const Text('Stage 2 of 5'),
          ScrollsInPlaceUnlessScaledUp(
            child: Container(height: 400, color: const Color(0xFF00FF00)),
          ),
        ],
      ),
    );
    await _pump(t, column(), 1.0);
    expect(find.byType(Expanded), findsOneWidget);
    expect(t.takeException(), isNull);
    await _pump(t, column(), 2.0);
    expect(find.byType(Expanded), findsNothing);
    expect(t.takeException(), isNull);
  });
}

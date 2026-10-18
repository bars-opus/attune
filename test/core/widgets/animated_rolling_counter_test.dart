// The odometer counter: rolls a changed figure; can roll up from 0 on first
// show; formats money (only the digits roll); lands at once with reduce
// motion; screen readers hear the whole figure; can settle back into one
// plain text.
import 'package:attune/core/widgets/animated_rolling_counter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

String _ghs(int minor) {
  final whole = minor ~/ 100;
  final s = whole.toString().replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
  return 'GHS $s.${(minor % 100).toString().padLeft(2, '0')}';
}

Widget _app(Widget child, {bool reduce = false}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: reduce),
    child: Scaffold(body: Center(child: child)),
  ),
);

// Rolling digits: the digit row's slides, or the painter over a settling
// figure's text.
Finder _rolling() => find.descendant(
  of: find.byType(AnimatedRollingCounter),
  matching: find.byWidgetPredicate(
    (w) => w is Transform || w.key == const ValueKey('animated-rolling-counter-rolling'),
  ),
);

void main() {
  testWidgets(
    'from zero: the digits roll up on first show, then settle into one text',
    (t) async {
      await t.pumpWidget(
        _app(
          AnimatedRollingCounter(
            count: 150000,
            format: _ghs,
            fromZero: true,
            settleAsText: true,
          ),
        ),
      );
      await t.pump(const Duration(milliseconds: 100));
      expect(_rolling(), findsWidgets, reason: 'mid-roll');
      // Mid-roll the settled text is already laid out (its rolling digits
    // hidden), so nothing moves when the roll ends.
      await t.pumpAndSettle();
      expect(_rolling(), findsNothing);
      expect(find.text('GHS 1,500.00'), findsOneWidget);
    },
  );

  // The glitch: the rolling digits laid out taller (and wrapped differently)
  // than the settled text, so the figure jumped when it stopped.
  for (final style in const [
    TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
    TextStyle(fontSize: 14),
    TextStyle(fontSize: 12, height: 1.5),
  ]) {
    testWidgets('rolling, it takes exactly the room it takes settled (${style.fontSize}/${style.height})', (t) async {
      await t.pumpWidget(_app(SizedBox(
        width: 120,
        child: Center(
          child: AnimatedRollingCounter(
              count: 7000, format: _ghs, suffix: ' left', fromZero: true, settleAsText: true, style: style),
        ),
      )));
      await t.pump(const Duration(milliseconds: 100));
      expect(_rolling(), findsWidgets);
      final rolling = t.getRect(find.byType(AnimatedRollingCounter));
      await t.pumpAndSettle();
      expect(t.getRect(find.byType(AnimatedRollingCounter)), rolling);
    });
  }

  testWidgets('without fromZero the first show does not roll (as before)', (
    t,
  ) async {
    await t.pumpWidget(_app(const AnimatedRollingCounter(count: 42)));
    await t.pump(const Duration(milliseconds: 100));
    expect(_rolling(), findsNothing);
  });

  testWidgets('a new figure rolls from the old one, then settles', (t) async {
    Widget at(int m) => _app(
      AnimatedRollingCounter(count: m, format: _ghs, settleAsText: true),
    );
    await t.pumpWidget(at(150000));
    await t.pumpAndSettle();
    expect(find.text('GHS 1,500.00'), findsOneWidget);
    await t.pumpWidget(at(160000));
    await t.pump(const Duration(milliseconds: 100));
    expect(_rolling(), findsWidgets);
    await t.pumpAndSettle();
    expect(find.text('GHS 1,600.00'), findsOneWidget);
  });

  testWidgets('reduce motion: the whole figure at once, never rolling', (
    t,
  ) async {
    await t.pumpWidget(
      _app(
        AnimatedRollingCounter(count: 150000, format: _ghs, fromZero: true),
        reduce: true,
      ),
    );
    expect(_rolling(), findsNothing);
    expect(find.text('GHS 1,500.00'), findsOneWidget);
  });

  testWidgets('screen readers hear the whole figure, even mid-roll', (t) async {
    final semantics = t.ensureSemantics();
    await t.pumpWidget(
      _app(
        AnimatedRollingCounter(
          count: 150000,
          format: _ghs,
          fromZero: true,
          prefix: '+',
        ),
      ),
    );
    await t.pump(const Duration(milliseconds: 100));
    expect(find.bySemanticsLabel('+GHS 1,500.00'), findsOneWidget);
    await t.pumpAndSettle();
    semantics.dispose();
  });
}

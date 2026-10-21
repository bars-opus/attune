import 'package:attune/core/ui/motion/make_room.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Measures the space the item OCCUPIES in the list, which is what
/// displaces everything above it in a reverse: true list.
///
/// Deliberately the MakeRoom box, not the child's: the child is laid out
/// at its natural height throughout and revealed by a shrinking clip, so
/// measuring the child would report the final height on every frame and
/// the test would pass against a widget that animates nothing.
double _height(WidgetTester tester) =>
    tester.getSize(find.byType(MakeRoom)).height;

Widget _wrap({bool animate = true}) => MaterialApp(
  home: Scaffold(
    body: Align(
      alignment: Alignment.bottomCenter,
      child: MakeRoom(
        animate: animate,
        child: SizedBox(
          key: const ValueKey('room-child'),
          height: 60,
          width: 100,
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('the slot opens from nothing to the child\'s full height', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap());

    // First frame: the item takes no vertical room, so the list above it
    // has not been displaced yet.
    expect(_height(tester), lessThan(6.0));

    await tester.pump(const Duration(milliseconds: 120));
    final mid = _height(tester);
    expect(mid, greaterThan(5.0));
    expect(mid, lessThan(60.0), reason: 'still opening at the midpoint');

    await tester.pumpAndSettle();
    expect(
      _height(tester),
      60.0,
      reason: 'must settle at exactly the child height, not an estimate',
    );
  });

  testWidgets('clips only while revealing, never once open', (tester) async {
    // A child that paints past its box (the jump flash's ring) must not be
    // cut flat once the slot is fully open.
    Clip clip() =>
        tester
            .widget<ClipRect>(
              find.descendant(
                of: find.byType(MakeRoom),
                matching: find.byType(ClipRect),
              ),
            )
            .clipBehavior;
    await tester.pumpWidget(_wrap());
    await tester.pump(const Duration(milliseconds: 120));
    expect(clip(), Clip.hardEdge, reason: 'mid grow-in');
    final child = tester.element(find.byKey(const ValueKey('room-child')));
    await tester.pumpAndSettle();
    expect(clip(), Clip.none, reason: 'fully open');
    expect(
      tester.element(find.byKey(const ValueKey('room-child'))),
      same(child),
      reason: 'the behaviour changes, the element is kept',
    );

    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(_wrap(animate: false));
    expect(clip(), Clip.none, reason: 'open from the start');
  });

  testWidgets('animate:false occupies full height immediately', (tester) async {
    // Cached history and scroll-back must not replay the opening.
    await tester.pumpWidget(_wrap(animate: false));
    expect(_height(tester), 60.0);
  });

  testWidgets('reduce-motion skips straight to the end state', (tester) async {
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: MakeRoom(
                child: SizedBox(
                  key: ValueKey('room-child'),
                  height: 60,
                  width: 100,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(_height(tester), 60.0);
  });

  testWidgets('a taller message opens a taller slot', (tester) async {
    // The displacement is the arriving bubble's OWN height -- a long
    // message must push the list further than a short one, which is the
    // whole point of growing the slot rather than sliding a fixed offset.
    Future<double> midHeightFor(double full) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: MakeRoom(
                key: ValueKey('h$full'),
                child: SizedBox(
                  key: const ValueKey('room-child'),
                  height: full,
                  width: 100,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 120));
      final h = _height(tester);
      await tester.pumpAndSettle();
      return h;
    }

    final short = await midHeightFor(40);
    final tall = await midHeightFor(200);
    expect(
      tall,
      greaterThan(short * 2),
      reason: 'the slot must scale with the content, not a fixed distance',
    );
  });
}

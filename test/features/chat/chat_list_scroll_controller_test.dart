import 'package:attune/features/chat/presentation/widgets/chat_list_scroll_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A DrivenScrollActivity writes absolute pixels each tick, so without help
/// an offset correction mid-animation is undone on the next tick (a stall or
/// a jump). ChatListScrollController carries the running animation across
/// the correction (task 9 review, Important 1).
void main() {
  Future<ScrollPosition> pumpList(
    WidgetTester tester,
    ChatListScrollController controller,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ListView.builder(
          controller: controller,
          reverse: true,
          itemCount: 200,
          itemBuilder: (_, i) => SizedBox(height: 50, child: Text('row $i')),
        ),
      ),
    );
    return controller.position;
  }

  testWidgets('toward the newest end: continuous, and still lands at 0', (
    tester,
  ) async {
    final controller = ChatListScrollController();
    addTearDown(controller.dispose);
    final position = await pumpList(tester, controller);
    position.jumpTo(2000);
    await tester.pump();

    position.animateTo(
      0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
    final seen = <double>[position.pixels];
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      seen.add(position.pixels);
    }
    // What Flutter's sliver does when it repairs the content origin.
    position.correctBy(150);
    seen.add(position.pixels);
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      seen.add(position.pixels);
    }

    expect(position.pixels, 0);
    // The step just before the correction bounds every step after it: an
    // overwritten correction shows up as one step of ~150 px extra.
    final stepBefore = seen[6] - seen[5];
    final afterCorrection = seen.sublist(7);
    for (var i = 1; i < afterCorrection.length; i++) {
      final step = afterCorrection[i] - afterCorrection[i - 1];
      expect(step, lessThanOrEqualTo(0), reason: '$afterCorrection');
      expect(
        step.abs(),
        lessThanOrEqualTo(stepBefore.abs() * 1.5 + 1),
        reason: 'jumped after the correction: $afterCorrection',
      );
    }
  });

  testWidgets('toward a row: the target moves with the content', (
    tester,
  ) async {
    final controller = ChatListScrollController();
    addTearDown(controller.dispose);
    final position = await pumpList(tester, controller);
    position.jumpTo(500);
    await tester.pump();

    position.animateTo(
      1500,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final before = position.pixels;
    position.correctBy(80);
    await tester.pump(const Duration(milliseconds: 16));
    expect(position.pixels, greaterThan(before + 80));
    await tester.pumpAndSettle();

    expect(position.pixels, closeTo(1580, 0.5));
  });

  testWidgets('a new gesture ends the carried animation', (tester) async {
    final controller = ChatListScrollController();
    addTearDown(controller.dispose);
    final position = await pumpList(tester, controller);
    position.jumpTo(2000);
    await tester.pump();
    position.animateTo(
      0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.linear,
    );
    await tester.pump(const Duration(milliseconds: 50));
    position.jumpTo(1000); // idle: the drive is over
    position.correctBy(40);
    await tester.pump(const Duration(milliseconds: 16));
    expect(position.pixels, 1040);
  });

  testWidgets('a correction in the last half pixel toward the newest end '
      'still lands at the newest end', (tester) async {
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final controller = ChatListScrollController();
    addTearDown(controller.dispose);
    final position = await pumpList(tester, controller);
    position.jumpTo(0.4);
    await tester.pump();
    position.animateTo(
      0,
      duration: const Duration(milliseconds: 100),
      curve: Curves.linear,
    );
    position.correctBy(30);
    await tester.pumpAndSettle();
    expect(position.pixels, closeTo(0, 0.01));
  });
  testWidgets('a sliver correction never pins a row itself (final wave M-7)', (
    tester,
  ) async {
    final controller = ChatListScrollController();
    addTearDown(controller.dispose);
    final position = await pumpList(tester, controller);
    position.jumpTo(500);
    await tester.pump();
    var pinAsks = 0;
    var pinned = false;
    controller.pinRowBeingRead = () {
      pinAsks++;
      return pinned = true;
    };
    controller.rowPinned = () => pinned;
    // Mid-layout, Flutter's correctBy: only an existing pin counts it.
    position.correctBy(12);
    expect(pinAsks, 0, reason: 'correctBy must not arm a pin');
    expect(pinned, isFalse);
    controller.pinRowBeingRead = null;
    controller.rowPinned = null;
  });

  group('ChatListAnchor among built rows (final wave M-6)', () {
    // After a far jump thousands of rows are loaded while a screenful is
    // built: the per-layout pin must cost O(built), not O(loaded).
    testWidgets('looks at built rows only and pins what arm would', (
      tester,
    ) async {
      const count = 3000;
      final keys = List.generate(count, (_) => GlobalKey());
      final controller = ChatListScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: ListView.builder(
            controller: controller,
            reverse: true,
            itemCount: count,
            itemBuilder:
                (_, i) => KeyedSubtree(
                  key: ValueKey<String>('row-$i'),
                  child: KeyedSubtree(
                    key: keys[i],
                    child: SizedBox(height: 40 + (i % 3) * 10, child: Text('row $i')),
                  ),
                ),
          ),
        ),
      );
      controller.position.jumpTo(30000);
      await tester.pump();

      final list = ChatListAnchor.findListElement(controller.position);
      expect(list, isNotNull);
      var lookups = 0;
      final anchor = ChatListAnchor();
      expect(
        anchor.armAmongBuilt(list!, (rowKey) {
          lookups++;
          if (rowKey is! ValueKey<String>) return null;
          return keys[int.parse(rowKey.value.substring(4))];
        }),
        isTrue,
      );
      expect(lookups, lessThan(60), reason: 'built rows only, not $count');
      final reference = ChatListAnchor()..arm(keys);
      expect(anchor.debugPinnedKey, isNotNull);
      expect(anchor.debugPinnedKey, same(reference.debugPinnedKey));
    });

    testWidgets('not a list: no sliver element', (tester) async {
      final controller = ChatListScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: SingleChildScrollView(
            controller: controller,
            child: const SizedBox(height: 2000),
          ),
        ),
      );
      expect(ChatListAnchor.findListElement(controller.position), isNull);
    });
  });
}

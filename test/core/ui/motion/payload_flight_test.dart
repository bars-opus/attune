import 'package:attune/core/ui/motion/payload_flight.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('waits for and lands on the measured destination', (
    tester,
  ) async {
    Rect? destination;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder:
                (context) => TextButton(
                  onPressed: () {
                    showPayloadFlight(
                      context: context,
                      sourceRect: const Rect.fromLTWH(20, 500, 120, 44),
                      fallbackDestination: const Rect.fromLTWH(
                        220,
                        400,
                        100,
                        44,
                      ),
                      resolveDestination: () => destination,
                      builder:
                          (context, progress) => ColoredBox(
                            key: const ValueKey('payload'),
                            color: Colors.green,
                          ),
                    );
                  },
                  child: const Text('send'),
                ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('send'));
    await tester.pump();
    expect(find.byKey(const ValueKey('payload')), findsOneWidget);

    destination = const Rect.fromLTWH(250, 120, 90, 50);
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));

    final middle = tester.getRect(find.byKey(const ValueKey('payload')));
    expect(middle.top, lessThan(500));
    expect(middle.left, greaterThan(20));

    await tester.pump(const Duration(milliseconds: 260));
    expect(find.byKey(const ValueKey('payload')), findsNothing);
  });

  testWidgets('reduced motion skips the travelling overlay', (tester) async {
    var builtPayload = false;

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: Builder(
              builder:
                  (context) => TextButton(
                    onPressed: () {
                      showPayloadFlight(
                        context: context,
                        sourceRect: const Rect.fromLTWH(20, 500, 120, 44),
                        fallbackDestination: const Rect.fromLTWH(
                          220,
                          400,
                          100,
                          44,
                        ),
                        resolveDestination: () => null,
                        builder: (context, progress) {
                          builtPayload = true;
                          return const SizedBox();
                        },
                      );
                    },
                    child: const Text('send'),
                  ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('send'));
    await tester.pump();

    expect(builtPayload, isFalse);
  });

  testWidgets('tracks a destination that moves with the keyboard', (
    tester,
  ) async {
    var destination = const Rect.fromLTWH(250, 300, 100, 50);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder:
                (context) => TextButton(
                  onPressed: () {
                    showPayloadFlight(
                      context: context,
                      sourceRect: const Rect.fromLTWH(20, 600, 120, 44),
                      fallbackDestination: destination,
                      resolveDestination: () => destination,
                      trackDestination: true,
                      builder:
                          (context, progress) => const ColoredBox(
                            key: ValueKey('tracked-payload'),
                            color: Colors.green,
                          ),
                    );
                  },
                  child: const Text('reply'),
                ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('reply'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));
    final beforeMove = tester.getRect(
      find.byKey(const ValueKey('tracked-payload')),
    );

    destination = const Rect.fromLTWH(60, 80, 260, 58);
    await tester.pump(const Duration(milliseconds: 80));
    final afterMove = tester.getRect(
      find.byKey(const ValueKey('tracked-payload')),
    );

    expect(afterMove.top, lessThan(beforeMove.top));
    expect(afterMove.width, greaterThan(beforeMove.width));

    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('tracked-payload')), findsNothing);
  });
}

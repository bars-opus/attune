import 'package:attune/core/widgets/universal_bubble.dart';
import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
}

void main() {
  testWidgets('isMine=true aligns bubble to the right', (tester) async {
    await _pump(
      tester,
      UniversalBubble(
        isMine: true,
        bubbleColor: Colors.blue,
        onBubbleColor: Colors.white,
        content: const Text('hello'),
        footer: const SizedBox.shrink(),
      ),
    );

    final align = tester.widget<Align>(find.byType(Align).first);
    expect(align.alignment, Alignment.centerRight);
  });

  testWidgets('isMine=false aligns bubble to the left', (tester) async {
    await _pump(
      tester,
      UniversalBubble(
        isMine: false,
        bubbleColor: Colors.blue,
        onBubbleColor: Colors.white,
        content: const Text('hello'),
        footer: const SizedBox.shrink(),
      ),
    );

    final align = tester.widget<Align>(find.byType(Align).first);
    expect(align.alignment, Alignment.centerLeft);
  });

  testWidgets('renders content and footer', (tester) async {
    await _pump(
      tester,
      UniversalBubble(
        isMine: true,
        bubbleColor: Colors.blue,
        onBubbleColor: Colors.white,
        content: const Text('bubble content'),
        footer: const Text('footer content'),
      ),
    );

    expect(find.text('bubble content'), findsOneWidget);
    expect(find.text('footer content'), findsOneWidget);
  });

  testWidgets('quotedText renders a tappable preview block that calls onJumpToParent',
      (tester) async {
    var jumped = false;
    await _pump(
      tester,
      UniversalBubble(
        isMine: false,
        bubbleColor: Colors.blue,
        onBubbleColor: Colors.white,
        content: const Text('reply body'),
        footer: const SizedBox.shrink(),
        quotedText: 'the original message',
        onJumpToParent: () => jumped = true,
      ),
    );

    expect(find.text('the original message'), findsOneWidget);
    await tester.tap(find.text('the original message'));
    expect(jumped, isTrue);
  });

  testWidgets('no quotedText means no quote block rendered', (tester) async {
    await _pump(
      tester,
      UniversalBubble(
        isMine: false,
        bubbleColor: Colors.blue,
        onBubbleColor: Colors.white,
        content: const Text('plain message'),
        footer: const SizedBox.shrink(),
      ),
    );

    expect(find.byIcon(Icons.format_quote), findsNothing);
  });

  testWidgets('startActionPane is wired into the Slidable', (tester) async {
    await _pump(
      tester,
      UniversalBubble(
        isMine: false,
        bubbleColor: Colors.blue,
        onBubbleColor: Colors.white,
        content: const Text('swipeable'),
        footer: const SizedBox.shrink(),
        startActionPane: ActionPane(
          motion: const DrawerMotion(),
          children: [
            SlidableAction(
              onPressed: (_) {},
              icon: Icons.reply,
              label: 'Reply',
            ),
          ],
        ),
      ),
    );

    final slidable = tester.widget<Slidable>(find.byType(Slidable));
    expect(slidable.startActionPane, isNotNull);
  });

  testWidgets('no action panes means Slidable still renders with null panes',
      (tester) async {
    await _pump(
      tester,
      UniversalBubble(
        isMine: false,
        bubbleColor: Colors.blue,
        onBubbleColor: Colors.white,
        content: const Text('no gestures'),
        footer: const SizedBox.shrink(),
      ),
    );

    final slidable = tester.widget<Slidable>(find.byType(Slidable));
    expect(slidable.startActionPane, isNull);
    expect(slidable.endActionPane, isNull);
  });
}

import 'package:attune/features/chat/presentation/widgets/chat_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(
  WidgetTester tester, {
  required TextEditingController controller,
  VoidCallback? onSend,
  VoidCallback? onOpenTranslator,
  VoidCallback? onAttachImage,
  bool showTranslator = false,
  bool showAttachImage = false,
  bool enabled = true,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ChatTextField(
          controller: controller,
          onSend: onSend ?? () {},
          onOpenTranslator: onOpenTranslator,
          onAttachImage: onAttachImage,
          showTranslator: showTranslator,
          showAttachImage: showAttachImage,
          enabled: enabled,
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('send is disabled when empty and enabled once text is entered',
      (tester) async {
    final controller = TextEditingController();
    var sent = 0;
    await _pump(tester, controller: controller, onSend: () => sent++);

    final sendButton = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.send_rounded),
    );
    expect(sendButton.onPressed, isNull); // disabled while empty

    await tester.enterText(find.byType(TextField), 'hello');
    await tester.pump();

    await tester.tap(find.widgetWithIcon(IconButton, Icons.send_rounded));
    expect(sent, 1);
  });

  testWidgets('translator entry only appears with non-empty text (Spec 10)',
      (tester) async {
    final controller = TextEditingController();
    await _pump(
      tester,
      controller: controller,
      showTranslator: true,
      onOpenTranslator: () {},
    );

    expect(find.byIcon(Icons.help_outline_rounded), findsNothing);

    await tester.enterText(find.byType(TextField), 'draft');
    await tester.pump();
    expect(find.byIcon(Icons.help_outline_rounded), findsOneWidget);
  });

  testWidgets('translator entry stays hidden when flag is off', (tester) async {
    final controller = TextEditingController(text: 'draft');
    await _pump(tester, controller: controller, showTranslator: false);
    expect(find.byIcon(Icons.help_outline_rounded), findsNothing);
  });

  testWidgets('attach-image button visibility follows its flag', (tester) async {
    final controller = TextEditingController();
    await _pump(
      tester,
      controller: controller,
      showAttachImage: false,
    );
    expect(find.byIcon(Icons.photo_outlined), findsNothing);

    await _pump(
      tester,
      controller: controller,
      showAttachImage: true,
      onAttachImage: () {},
    );
    expect(find.byIcon(Icons.photo_outlined), findsOneWidget);
  });

  testWidgets('disabled composer prevents send even with text', (tester) async {
    final controller = TextEditingController(text: 'hi');
    var sent = 0;
    await _pump(
      tester,
      controller: controller,
      enabled: false,
      onSend: () => sent++,
    );

    final sendButton = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.send_rounded),
    );
    expect(sendButton.onPressed, isNull);
    expect(sent, 0);
  });
}
